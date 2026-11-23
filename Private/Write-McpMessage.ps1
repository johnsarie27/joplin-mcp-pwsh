function Write-McpMessage {
    <#
    .SYNOPSIS
        Writes one JSON-RPC message to the protocol stream as a single line.
    .DESCRIPTION
        The only place a protocol message is serialized and written. The message is serialized first, so a
        serialization failure writes nothing, and the line is written with one call. Serialization fails, rather than
        truncating, when the message is nested deeper than 32 levels (see ConvertTo-McpJson).
    .PARAMETER Writer
        The protocol stream: the dedicated stdout writer, or a StringWriter in tests.
    .PARAMETER Message
        The JSON-RPC message to write.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpMessage -Writer $writer -Message ([ordered]@{ jsonrpc = '2.0'; id = 1; result = @{} })
        Writes {"jsonrpc":"2.0","id":1,"result":{}} and a line feed.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The JSON-RPC message to write')]
        [System.Collections.IDictionary] $Message
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $json = ConvertTo-McpJson -InputObject $Message
        $Writer.WriteLine($json)
        $Writer.Flush()
    }
}
