function Write-McpResult {
    <#
    .SYNOPSIS
        Writes a JSON-RPC success response.
    .DESCRIPTION
        Wraps a result in a JSON-RPC 2.0 response envelope with the request's id, and writes it as one line.
    .PARAMETER Writer
        The protocol stream.
    .PARAMETER Id
        The id of the request being answered, exactly as the client sent it.
    .PARAMETER Result
        The result object.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpResult -Writer $writer -Id 7 -Result @{}
        Writes {"jsonrpc":"2.0","id":7,"result":{}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The id of the request being answered')]
        [AllowNull()]
        [System.Object] $Id,

        [Parameter(Mandatory, HelpMessage = 'The result object')]
        [System.Collections.IDictionary] $Result
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        Write-McpMessage -Writer $Writer -Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result })
    }
}
