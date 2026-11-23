function Invoke-McpLine {
    <#
    .SYNOPSIS
        Handles one line of input: parses it, dispatches it and writes at most one response.
    .DESCRIPTION
        Malformed JSON gets -32700 with a null id, and a message that is not a valid JSON-RPC 2.0 request gets -32600,
        so the client is never left waiting. A message with no id key is a notification and is never answered, even
        when it fails. An unexpected exception becomes -32603 with a generic message; only its type name goes to stderr.
        The input line is never echoed anywhere: a parse failure logs only the line's length.
    .PARAMETER Line
        One line of input.
    .PARAMETER Writer
        The protocol stream.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Invoke-McpLine -Line '{"jsonrpc":"2.0","id":1,"method":"ping"}' -Writer $writer
        Writes {"jsonrpc":"2.0","id":1,"result":{}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'One line of input')]
        [System.String] $Line,

        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        try {
            # -NoEnumerate: A JSON ARRAY MUST STAY ONE VALUE, NOT BE UNROLLED INTO ITS ELEMENTS, SO IT IS REJECTED AS A BATCH
            $message = ConvertFrom-Json -InputObject $Line -AsHashtable -NoEnumerate -Depth 32 -ErrorAction 'Stop'
        }
        catch {
            [System.Console]::Error.WriteLine(('[diag] Parse error: input of length {0}' -f $Line.Length))
            Write-McpError -Writer $Writer -Id $null -Code -32700 -Message 'Parse error'
            return
        }
        $isObject = $message -is [System.Collections.IDictionary]
        $id = $null
        $hasValidId = $false
        if ($isObject -and $message.Contains('id')) {
            $id = $message['id']
            $hasValidId = $id -is [System.String] -or $id -is [System.Int32] -or $id -is [System.Int64] -or $id -is [System.Double]
        }
        if ($isObject -and -not $message.Contains('method') -and ($message.Contains('result') -or $message.Contains('error'))) {
            # THE SERVER SENDS NO REQUESTS, SO A RESPONSE FROM THE CLIENT IS NOT AN ERROR; THERE IS NOTHING TO MATCH IT TO
            return
        }
        # jsonrpc MUST BE THE STRING '2.0'. -cne ALONE IS NOT ENOUGH: POWERSHELL CONVERTS '2.0' TO AN INTEGER TO COMPARE IT WITH ONE
        if (-not $isObject -or $message['jsonrpc'] -isnot [System.String] -or $message['jsonrpc'] -cne '2.0' -or
            $message['method'] -isnot [System.String] -or ($message.Contains('id') -and -not $hasValidId)) {
            $errorId = $null
            if ($hasValidId) {
                $errorId = $id
            }
            Write-McpError -Writer $Writer -Id $errorId -Code -32600 -Message 'Invalid Request'
            return
        }
        # A NOTIFICATION IS A MESSAGE WITH NO id KEY, NOT ONE WHOSE id IS NULL
        $hasId = $message.Contains('id')
        try {
            $result = switch -CaseSensitive ($message['method']) {
                'initialize' { Get-InitializeResult -Params $message['params'] }
                'notifications/initialized' { $null }
                'ping' { [ordered]@{} }
                'tools/list' { [ordered]@{ tools = @(Get-ToolList) } }
                'tools/call' { Invoke-ToolCall -Params $message['params'] }
                default { Write-Error -Exception ([McpProtocolError]::new(-32601, 'Method not found.')) -ErrorAction 'Stop' }
            }
            if ($null -eq $result) {
                $result = [ordered]@{}
            }
            if ($hasId) {
                Write-McpResult -Writer $Writer -Id $id -Result $result
            }
        }
        catch [McpProtocolError] {
            if ($hasId) {
                Write-McpError -Writer $Writer -Id $id -Code $PSItem.Exception.Code -Message $PSItem.Exception.Message
            }
        }
        catch {
            # NEVER SURFACE RAW EXCEPTION TEXT: IT MAY CONTAIN THE REQUEST URI AND THE TOKEN
            [System.Console]::Error.WriteLine(('[diag] Unhandled: {0}' -f $PSItem.Exception.GetType().Name))
            if ($hasId) {
                Write-McpError -Writer $Writer -Id $id -Code -32603 -Message 'Internal error'
            }
        }
    }
}
