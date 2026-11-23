function Get-SafeErrorMessage {
    <#
    .SYNOPSIS
        Returns the text of a tool failure that is safe to send to the client.
    .DESCRIPTION
        A tool error raised by this module carries a message written for the client, and is returned as is. Any other
        exception may contain a request URL and the Joplin token, so its message is never used: the client gets a
        generic message, and only the exception's type name goes to stderr.
    .PARAMETER ErrorRecord
        The error caught while running a tool.
    .INPUTS
        System.Management.Automation.ErrorRecord.
    .OUTPUTS
        System.String.
    .EXAMPLE
        PS C:\> try { Write-Error -Message 'boom' -ErrorAction Stop } catch { Get-SafeErrorMessage -ErrorRecord $PSItem }
        Returns 'The tool call failed.' and writes the exception type name to stderr.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'The error caught while running a tool')]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($ErrorRecord.Exception -is [McpToolError]) {
            $ErrorRecord.Exception.Message
        }
        else {
            [System.Console]::Error.WriteLine(('[diag] Tool failed: {0}' -f $ErrorRecord.Exception.GetType().Name))
            'The tool call failed.'
        }
    }
}
