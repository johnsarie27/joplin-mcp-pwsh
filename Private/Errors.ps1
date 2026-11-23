# ==============================================================================
# Filename: Errors.ps1
# Author:   Justin Johns
# ==============================================================================
# TYPED ERRORS. A PROTOCOL ERROR BECOMES A JSON-RPC ERROR; A TOOL ERROR BECOMES A RESULT WITH isError. THE MESSAGE
# OF EITHER IS WRITTEN BY THIS MODULE AND IS SAFE TO SHOW THE CLIENT. NO OTHER EXCEPTION'S MESSAGE EVER IS, BECAUSE IT
# MAY CARRY A REQUEST URL AND THE TOKEN IN ITS QUERY STRING (docs/design/dispatcher.md).

class McpProtocolError : System.Exception {
    [System.Int32] $Code

    McpProtocolError([System.Int32] $Code, [System.String] $Message) : base($Message) {
        $this.Code = $Code
    }
}

class McpToolError : System.Exception {
    McpToolError([System.String] $Message) : base($Message) { }
}

class NotebookAccessError : McpToolError {
    NotebookAccessError([System.String] $Message) : base($Message) { }
}

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
        PS C:\> try { throw 'boom' } catch { Get-SafeErrorMessage -ErrorRecord $_ }
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
            return $ErrorRecord.Exception.Message
        }
        [System.Console]::Error.WriteLine(('[diag] Tool failed: {0}' -f $ErrorRecord.Exception.GetType().Name))
        'The tool call failed.'
    }
}
