function Write-McpError {
    <#
    .SYNOPSIS
        Writes a JSON-RPC error response.
    .DESCRIPTION
        Wraps an error code and message in a JSON-RPC 2.0 error envelope and writes it as one line. The code is
        always an integer. Use an id of null when the request's id is unknown, such as a parse error.
    .PARAMETER Writer
        The protocol stream.
    .PARAMETER Id
        The id of the request being answered, or null when it cannot be known.
    .PARAMETER Code
        The JSON-RPC error code, for example -32602.
    .PARAMETER Message
        A short message safe to show the client. Never raw exception text.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpError -Writer $writer -Id $null -Code -32700 -Message 'Parse error'
        Writes {"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The id of the request being answered, or null')]
        [AllowNull()]
        [System.Object] $Id,

        [Parameter(Mandatory, HelpMessage = 'The JSON-RPC error code')]
        [System.Int32] $Code,

        [Parameter(Mandatory, HelpMessage = 'A short message safe to show the client')]
        [System.String] $Message
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $errorBody = [ordered]@{ code = $Code; message = $Message }
        Write-McpMessage -Writer $Writer -Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; error = $errorBody })
    }
}
