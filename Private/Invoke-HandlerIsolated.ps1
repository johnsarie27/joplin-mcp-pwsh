function Invoke-HandlerIsolated {
    <#
    .SYNOPSIS
        Runs a tool handler so that nothing it writes can reach the protocol stream.
    .DESCRIPTION
        Merges every stream of the handler into the output, then sends each information, warning, verbose, debug and
        error record to stderr and keeps only the success output. The handler must produce exactly one value; any other
        count is an error, so a stray pipeline value is never mistaken for the result. The handler is invoked as a
        script block, never looked up by name.
    .PARAMETER Handler
        The registered handler script block.
    .PARAMETER Arguments
        The validated tool arguments, passed as the handler's first argument.
    .PARAMETER Access
        The access object, passed as the handler's second argument.
    .INPUTS
        None.
    .OUTPUTS
        System.Object.
    .EXAMPLE
        PS C:\> Invoke-HandlerIsolated -Handler { param($Arguments, $Access) 'result' } -Arguments @{} -Access $access
        Returns 'result'. Anything the handler wrote to another stream would go to stderr.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The registered handler script block')]
        [System.Management.Automation.ScriptBlock] $Handler,

        [Parameter(Mandatory, HelpMessage = 'The validated tool arguments')]
        [System.Collections.IDictionary] $Arguments,

        [Parameter(Mandatory, HelpMessage = 'The access object')]
        [NotebookAccess] $Access
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # POWERSHELL HAS NO 3>&2-STYLE REDIRECTION (A PARSE ERROR), SO MERGE EVERYTHING AND SPLIT BY RECORD TYPE
        $items = @(& $Handler $Arguments $Access *>&1)
        # @() SO A SINGLE VALUE STAYS AN ARRAY: INDEXING A BARE STRING WOULD RETURN ITS FIRST CHARACTER
        $output = @(foreach ($item in $items) {
                if ($item -is [System.Management.Automation.InformationRecord] -or
                    $item -is [System.Management.Automation.WarningRecord] -or
                    $item -is [System.Management.Automation.VerboseRecord] -or
                    $item -is [System.Management.Automation.DebugRecord] -or
                    $item -is [System.Management.Automation.ErrorRecord]) {
                    [System.Console]::Error.WriteLine(('[diag:{0}] {1}' -f $item.GetType().Name, $item))
                }
                else {
                    , $item
                }
            })
        if ($output.Count -ne 1) {
            $contract = [System.InvalidOperationException]::new('A tool handler must return exactly one value.')
            Write-Error -Exception $contract -ErrorAction 'Stop'
        }
        $output[0]
    }
}
