# ==============================================================================
# Filename: Access.ps1
# Author:   Justin Johns
# ==============================================================================
# PLACEHOLDER ACCESS OBJECT. EVERY CHECK ANSWERS "NO" UNTIL CONFIG LOADING AND NOTEBOOK RESOLUTION ARE BUILT
# (docs/design/security-model.md#access-object), SO THE DISPATCHER'S GATE EXISTS AND FAILS CLOSED FROM THE START.

# WHAT A TOOL NEEDS FROM THE ACCESS OBJECT. AN ENUM, SO A TOOL REGISTERED WITHOUT ONE, OR WITH ANY OTHER VALUE, FAILS
# AT REGISTRATION (docs/design/tools.md#registration)
enum JoplinToolAccess {
    Read
    Write
    CreateNotebook
    ManageTags
}

class NotebookAccess {
    [System.Boolean] HasAnyAccess() { return $false }
    [System.Boolean] CanRead([System.String] $NotebookId) { return $false }
    [System.Boolean] CanWrite([System.String] $NotebookId) { return $false }
    [System.Boolean] CanCreateRootNotebook() { return $false }
    [System.Boolean] CanManageTags() { return $false }
}

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
        Status: Placeholder
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
