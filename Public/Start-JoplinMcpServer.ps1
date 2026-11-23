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
        # DEVIATES FROM OPENING WITH Write-Verbose: THIS FUNCTION OWNS STDOUT, SO A CALLER'S -Verbose MUST NOT PUT A LINE
        # THERE. THE SERVER MOVES Console.Out TO STDERR FIRST; -ListTools CAPTURES ITS OWN STREAMS IN THE PROCESS BLOCK
        # INSTEAD, BECAUSE ITS JSON IS PIPELINE OUTPUT THAT THE HOST WRITES TO Console.Out. THE CLEAN BLOCK PUTS BOTH
        # SETTINGS BACK
        $originalOut = [System.Console]::Out
        $originalRendering = $PSStyle.OutputRendering
        if (-not $ListTools) {
            [System.Console]::SetOut([System.Console]::Error)
            Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        }
    }
    Process {
        if ($ListTools) {
            # NOT [Console]::SetOut: THE HOST KEEPS THE WRITER IT FIRST WRITES THROUGH, SO A VERBOSE LINE WRITTEN WHILE
            # STDOUT WAS MOVED WOULD TAKE THE JSON TO STDERR WITH IT. ONLY THE JSON STRING IS OUTPUT; ANY OTHER RECORD IS STDERR
            # CAPTURED HERE: INSIDE THE SCRIPT BLOCK $MyInvocation IS THE BLOCK, NOT THIS FUNCTION
            $commandName = $MyInvocation.MyCommand.Name
            $items = & {
                Write-Verbose -Message ('Starting {0}' -f $commandName)
                ConvertTo-McpJson -InputObject ([ordered]@{ tools = @(Get-ToolList) })
            } *>&1
            foreach ($item in $items) {
                if ($item -is [System.String]) {
                    $item
                }
                else {
                    [System.Console]::Error.WriteLine(('[diag:{0}] {1}' -f $item.GetType().Name, $item))
                }
            }
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
    Clean {
        # RUNS HOWEVER THE FUNCTION ENDS: END OF INPUT, AN ERROR OR CTRL+C. Console.Out COMES BACK, BUT IF THE HOST WROTE
        # ANYTHING WHILE IT WAS MOVED, THE HOST'S OWN LATER OUTPUT STAYS ON STDERR; THE SERVER IS MEANT TO OWN ITS PROCESS
        if ($null -ne $originalOut) {
            [System.Console]::SetOut($originalOut)
        }
        # $null -ne, NOT A TRUTH TEST: THE DEFAULT, Host, IS THE ENUM'S ZERO VALUE
        if ($null -ne $originalRendering) {
            $PSStyle.OutputRendering = $originalRendering
        }
    }
}
