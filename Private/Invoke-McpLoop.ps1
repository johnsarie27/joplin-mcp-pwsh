function Invoke-McpLoop {
    <#
    .SYNOPSIS
        Reads requests line by line until the input ends.
    .DESCRIPTION
        Takes the reader and writer as parameters, rather than opening the console, so tests can pass a StringReader
        and a StringWriter and assert the exact bytes written. A blank line is skipped. The loop ends promptly when the
        reader returns null at end of input. One bad line never stops it, because each line is handled on its own.
    .PARAMETER Reader
        Where requests come from, one JSON-RPC message per line.
    .PARAMETER Writer
        The protocol stream.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Invoke-McpLoop -Reader ([System.IO.StringReader]::new('{"jsonrpc":"2.0","id":1,"method":"ping"}')) -Writer $writer
        Answers the ping, then returns at the end of the input.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Where requests come from')]
        [System.IO.TextReader] $Reader,

        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        while ($null -ne ($line = $Reader.ReadLine())) {
            if (-not [System.String]::IsNullOrWhiteSpace($line)) {
                Invoke-McpLine -Line $line -Writer $Writer
            }
        }
    }
}
