function Start-JoplinMcpServer {
    <#
    .SYNOPSIS
        Starts the Joplin MCP server on standard input and output.
    .DESCRIPTION
        Reads one JSON-RPC 2.0 message per line from stdin and writes one response line per request to stdout, until
        stdin closes. Nothing but protocol messages is ever written to stdout: diagnostics go to stderr, and stray output
        from tool handlers is captured and sent to stderr as well.

        Start it from an MCP client with profiles disabled, because a profile can write to stdout:
        pwsh -NoProfile -NonInteractive -Command Start-JoplinMcpServer

        With -ListTools it prints the JSON that tools/list publishes and returns, without reading stdin.
    .PARAMETER ListTools
        Print the published tool list as JSON and return, instead of starting the server.
    .INPUTS
        None.
    .OUTPUTS
        System.String. Only with -ListTools: the tool list as compressed JSON.
    .EXAMPLE
        PS C:\> Start-JoplinMcpServer
        Starts the server on stdin and stdout.
    .EXAMPLE
        PS C:\> Start-JoplinMcpServer -ListTools
        Prints {"tools":[...]} and returns.
    .NOTES
        Status: Beta
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Start-JoplinMcpServer begins a read-eval loop and changes no system state, so there is nothing to confirm.')]
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(HelpMessage = 'Print the published tool list as JSON and return')]
        [System.Management.Automation.SwitchParameter] $ListTools
    )
    Begin {
        # DEVIATES FROM OPENING WITH Write-Verbose: THIS FUNCTION OWNS THE PROTOCOL STREAM, SO Console.Out MOVES TO STDERR
        # FIRST. OTHERWISE A CALLER'S -Verbose WOULD PUT THE LINE BELOW ON STDOUT, NEXT TO THE PROTOCOL
        if (-not $ListTools) {
            [System.Console]::SetOut([System.Console]::Error)
        }
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($ListTools) {
            ConvertTo-McpJson -InputObject ([ordered]@{ tools = @(Get-ToolList) })
        }
        else {
            # UTF-8 WITHOUT A BYTE ORDER MARK, ON BOTH ENDS. [System.Text.Encoding]::UTF8 WOULD WRITE A BOM
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            try {
                [System.Console]::InputEncoding = $utf8
                [System.Console]::OutputEncoding = $utf8
            }
            catch [System.IO.IOException] {
                # NO CONSOLE TO CONFIGURE, AS WHEN STDIN AND STDOUT ARE PIPES ON WINDOWS. THE STREAMS BELOW SET THEIR OWN ENCODING
                [System.Console]::Error.WriteLine('[diag] Could not set the console encoding; using explicit UTF-8 streams.')
            }
            # DIAGNOSTICS CARRY NO ANSI COLOUR CODES
            $PSStyle.OutputRendering = 'PlainText'
            $reader = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput(), $utf8)
            $writer = [System.IO.StreamWriter]::new([System.Console]::OpenStandardOutput(), $utf8)
            $writer.NewLine = "`n"
            $writer.AutoFlush = $true
            try {
                Invoke-McpLoop -Reader $reader -Writer $writer
            }
            finally {
                $writer.Flush()
            }
        }
    }
}
