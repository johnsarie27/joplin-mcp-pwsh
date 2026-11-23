function Resolve-NotebookAccess {
    <#
    .SYNOPSIS
        Builds the access object for one tool call.
    .DESCRIPTION
        Placeholder. Returns an access object that grants nothing, so every tool that needs access is refused until
        config loading and notebook resolution replace this function. The dispatcher calls it on every tools/call.
    .INPUTS
        None.
    .OUTPUTS
        NotebookAccess.
    .EXAMPLE
        PS C:\> Resolve-NotebookAccess
        Returns an access object for which every check is false.
    .NOTES
        Status: Experimental
    #>
    [CmdletBinding()]
    [OutputType([NotebookAccess])]
    Param()
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        [NotebookAccess]::new()
    }
}
