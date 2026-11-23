# Protocol loop and dispatcher

The stdio JSON-RPC loop, how a `tools/call` reaches a handler, and the error conventions. The stdout-isolation and argument-strictness rules this code implements are explained in [security-model.md](security-model.md#powershell-specific-hardening).

## Sketch

```powershell
function Start-McpLoop {
    $stdin  = [System.IO.StreamReader]::new([Console]::OpenStandardInput(),  [System.Text.UTF8Encoding]::new($false))
    $stdout = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput(), [System.Text.UTF8Encoding]::new($false))
    $stdout.NewLine   = "`n"
    $stdout.AutoFlush = $true
    [Console]::SetOut([Console]::Error)   # stray Console.Out writes must never reach the protocol stream

    while ($null -ne ($line = $stdin.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try   { $msg = $line | ConvertFrom-Json -AsHashtable -Depth 32 }
        catch { Write-McpError $stdout $null -32700 'Parse error'; continue }

        $hasId = $msg.ContainsKey('id')      # no id => notification => never respond
        try {
            $result = switch ($msg.method) {
                'initialize'                { Get-InitializeResult $msg.params }
                'notifications/initialized' { $null }
                'ping'                      { @{} }
                'tools/list'                { @{ tools = Get-ToolList } }
                'tools/call'                { Invoke-ToolCall $msg.params }
                default                     { throw [McpProtocolError]::new(-32601, "Method not found: $($msg.method)") }
            }
            if ($hasId) { Write-McpResult $stdout $msg.id $result }
        }
        catch [McpProtocolError] {
            if ($hasId) { Write-McpError $stdout $msg.id $_.Exception.Code $_.Exception.Message }
        }
        catch {
            # Never surface raw exception text: it may contain the request URI/token.
            [Console]::Error.WriteLine("Unhandled: $($_.Exception.GetType().Name)")   # stderr only
            if ($hasId) { Write-McpError $stdout $msg.id -32603 'Internal error' }
        }
    }
}

function Invoke-ToolCall([hashtable] $params) {
    $tool = $script:ToolRegistry[$params.name]
    if (-not $tool) { throw [McpProtocolError]::new(-32602, "Unknown tool: $($params.name)") }

    $arguments = $params.arguments ?? @{}
    Test-ToolArgument -Schema $tool.InputSchema -Arguments $arguments   # throws -32602: non-object arguments, unknown or common parameters, wrong JSON types (booleans never coerced)

    try {
        $access = Resolve-NotebookAccess                 # re-reads config, resolves names live
        switch ($tool.Access) {
            { $_ -in 'Read', 'Write' } {
                if (-not $access.HasAnyAccess()) {
                    throw [NotebookAccessError]::new('No notebooks are configured for access. Add a `notebooks` list to the config file.')
                }
            }
            'ManageTags' {
                if (-not $access.CanManageTags()) { throw [NotebookAccessError]::new('Tag management is not permitted by the configured access.') }
            }
            # 'CreateNotebook' is checked in the handler: CanWrite($parent_id) or CanCreateRootNotebook().
        }
        # Diagnostics (Write-Host, warnings, verbose, debug, errors) go to stderr; only the single
        # success value is returned. (`3>&2`-style redirection is a parse error in PowerShell.)
        $text = Invoke-HandlerIsolated -Handler $tool.Handler -Arguments $arguments -Access $access
        @{ content = @(@{ type = 'text'; text = [string] $text }); isError = $false }
    }
    catch {
        # Tool-level failures are results with isError, not JSON-RPC errors,
        # so the model can read the message and recover.
        @{ content = @(@{ type = 'text'; text = (Get-SafeErrorMessage $_) }); isError = $true }
    }
}

function Invoke-HandlerIsolated($Handler, $Arguments, $Access) {
    $items = @(& $Handler $Arguments $Access *>&1)      # merge every stream into the output
    $out = foreach ($item in $items) {
        if ($item -is [System.Management.Automation.InformationRecord] -or
            $item -is [System.Management.Automation.WarningRecord] -or
            $item -is [System.Management.Automation.VerboseRecord] -or
            $item -is [System.Management.Automation.DebugRecord] -or
            $item -is [System.Management.Automation.ErrorRecord]) {
            [Console]::Error.WriteLine("[diag:$($item.GetType().Name)] $item")   # diagnostics -> stderr
        } else { $item }
    }
    if (@($out).Count -ne 1) { throw 'Handler must return exactly one value.' }
    $out
}
```

The stdout-isolation technique (dedicated writer, `[Console]::SetOut` to stderr, `*>&1` split by record type) was verified on PowerShell 7.7: by default seven kinds of stray output reached stdout, and with this technique none did. An earlier sketch used `3>&2 4>&2 5>&2 6>&2`, which is a parse error ("reserved for future use"), and `Write-Error ... 2>&1 | Out-Host`, which writes to stdout.

## Loop requirements

These come from defects observed in the [evaluated frameworks](../research/framework-evaluation/comparison.md):

- **Testable without a client.** Inject a `[System.IO.TextReader]` and `[System.IO.TextWriter]` into the loop rather than mocking wrapper functions, so tests pass `StringReader` / `StringWriter` and assert the exact bytes written. (The sketch above opens the console streams directly; the injected form is the target.)
- **EOF ends the loop.** When `ReadLine` returns null the loop exits promptly, with no spin and no file growth.
- **One bad line never kills the server.** Parsing happens per line inside a `try`; a malformed line gets `-32700` and the loop continues.
- **A notification is a message with no `id` key**, not one whose `id` is null.
- **Never echo the raw input line** to stderr or any log; log the method and length only.
- **Problems during startup go to stderr**, leaving stdout empty until the first response.

## Error conventions

| Situation | Response |
|---|---|
| Malformed JSON | JSON-RPC error `-32700` with `id: null` (never a previous request's id) |
| Unknown method | `-32601` |
| Unknown tool / schema validation failure | `-32602` |
| Invalid request (missing or wrong `jsonrpc`, missing `method`) | `-32600`; never silently dropped, so the client is not left waiting |
| Access denied on something the caller can see (e.g. writing a read-only note, tag management without `$tags`), Joplin 4xx/5xx, handler failure | Normal result with `isError: true` and a sanitized message |
| Note or notebook that is hidden, denied or nonexistent | The same not-found result for all three ([ADR 5](../adr/0005-hidden-indistinguishable-from-missing.md)) |
| Unexpected exception | `-32603` with a generic message; details to stderr only |

Further rules:

- A message is a valid request only if `jsonrpc` is the string `"2.0"` (a number is not enough), `method` is a string, and `id`, when present, is a string or a number. A JSON array (a batch) is `-32600`. A message with `result` or `error` and no `method` is a client response, which the server has no use for, so it is ignored rather than answered.
- A method name is matched case-sensitively, and a tool name by exact ordinal match in the registry.
- Every serialized error `code` is an integer.
- `ping` returns `{}`.
- Use a typed `[McpProtocolError]` with a `Code` to map failures to JSON-RPC codes, and a typed response envelope. Never infer an envelope by duck-typing a handler result (a result with a `result` or `error` property is not an envelope).
- Results that are not strings are serialized with an explicit `-Depth` and fail loudly if anything would be truncated; never `System.Collections.Hashtable` strings. `ConvertTo-McpJson` is the one serializer: it captures `ConvertTo-Json`'s truncation warning, which would otherwise print next to the protocol, and throws instead.
- The function is `Test-ToolArgument`, not `Test-ToolArguments`: PSScriptAnalyzer's `PSUseSingularNouns` is a warning and the build fails on warnings.

## Initialization

- **Version negotiation.** `initialize` echoes the client's `protocolVersion` if it is in the server's supported list, otherwise returns the server's latest. Never echo an unsupported version. The supported list is to be pinned against the MCP spec at implementation time and tested against the real clients that matter (pwsh.mcp carries a client-specific fallback, which shows why).
- **Capabilities.** Advertise only what is implemented (`tools`).
- **Instructions.** Optionally load server `instructions` from a file, to state scope once ("searches only notebooks you can access") beyond the tool descriptions.
