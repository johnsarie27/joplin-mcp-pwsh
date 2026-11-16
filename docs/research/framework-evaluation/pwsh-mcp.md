# Framework evaluation: pwsh.mcp (`warm-snow-13/pwsh-mcp`)

One of three framework reviews; see the [comparison and recommendation](comparison.md).

**Method and limits.** Read-only review of a shallow clone at commit `d1a30ea` (2026-08-27), then **confirmed by running** the module on PowerShell 7.7.0 (Ubuntu 24.04) from a scratch copy, driving the stdio server with piped input and five small tools written for the test (an echo tool with `ValidateSet` / `ValidatePattern` / `ValidateRange` parameters, one that calls `Write-Host`, one that throws, one that returns a deeply nested object, and one named `echo`). The project's own Pester suite was **not** run (Pester is not available in the sandbox and the PowerShell Gallery is blocked). The Gallery listing and download counts were not checked.

## What it is
MIT-licensed, v0.1.6, single maintainer. About 4,200 lines across source, samples and tests, of which about 2,100 are Pester tests; CI runs PSScriptAnalyzer and Pester 6.1.0 (tests on Ubuntu, macOS and Windows, PowerShell 7.5 only). Releases per its changelog: 2026-03-09, 2026-04-01, 2026-08-27. You write ordinary PowerShell functions and pass them to `New-MCPServer -FunctionInfo (Get-Item Function:name)`; schemas are generated from parameters and help. Stdio and tools only (no resources, prompts or HTTP).

## Against our requirements

| Requirement | Result | Notes |
|---|---|---|
| Rejects unknown or invalid arguments | **Partial** (confirmed) | PowerShell's own parameter binding rejects unknown names and enforces `ValidateSet`, `ValidatePattern` and `ValidateRange` with readable messages (returned as `isError`). But: **common parameters are accepted** (`ErrorAction: "Ignore"` changed the tool's `$ErrorActionPreference`); a JSON **array** of arguments is splatted **positionally**; the string `"3"` was accepted for an integer parameter; and none of the constraints are published in the tool's `inputSchema`. No `additionalProperties: false`. |
| Tool failures return `isError` | **Yes** (confirmed) | The text is just `Exception.Message`, with no property dump (better than MCP.SDK). No scrubbing hook. An unknown tool is also an `isError` result, where the spec calls for a protocol error. |
| Pluggable per-tool access gate | **No hook, one choke point** | Every call passes through `mcp.callTool`, so a gate is a small patch. Tools are in-process functions, so passing shared context to handlers is natural. |
| stdout stays clean | **No** (confirmed) | `Write-Host` in a tool put a bare line on stdout before the JSON response. The framework's own `ConvertTo-Json` depth warning also landed on stdout. (The same defect as MCP.SDK.) |
| Testable without a client | **Yes, best of the two** | The loop takes injected `-In [TextReader]` / `-Out [TextWriter]`; the transport tests use `StringReader` / `StringWriter`. |
| Loop robustness | **Good** (confirmed) | Closing stdin exits promptly with code 0. A malformed JSON line is caught per line and the loop continues. Blank lines are skipped. |
| Protocol version | **OK** (confirmed) | A client asking for `1999-01-01` was answered with the server's own `2025-11-25`, which fits the spec. There is a documented client-specific fallback to `2025-06-18` for GitHub Copilot CLI. |
| Logging / data at rest | **Good** (confirmed) | No log file was written during the whole run. A rotating file logger exists in the source but is never called from the server. |
| License, floor, maintenance | **Mixed** | MIT, steady releases. `PowerShellVersion = '7.5.0'` and `#Requires -Version 7.5` are **above our 7.4+ target**; CI tests only 7.5. GitHub Actions are pinned by tag (`@v6`), not by commit SHA. |

## Other bugs found
1. **Silent data truncation.** A result nested five levels deep came back as `{"a":{"b":{"c":"System.Collections.Hashtable"}}}`: non-string results are serialized with `ConvertTo-Json` at its default depth of 2. (Not an issue for handlers that return formatted strings, which ours do.)
2. **Name shadowing.** A tool named `echo` never ran: `& $toolName` resolves the `echo` **alias** first, so `Write-Output` received the client's arguments and returned `["-text:","hi"]`.
3. **Requests can hang.** A request with `jsonrpc: "1.0"` was dropped without any response, so a client would wait forever. Malformed JSON gets no `-32700` either, only a stderr line.
4. **Raw input echoed to stderr.** On a parse failure the whole input line is written to stderr as `input_line`, which for us could contain note text.
5. **Weak tool descriptions.** A function without comment-based help gets its own name as the tool description.
6. **Empty `required` arrays** are emitted for tools with no required parameters.

## Verdict
**Not usable as-is, but the best fork or contribution candidate of the two.** Its structure fits ours: an in-process registry, an injected reader and writer, clean EOF and per-line error handling, no data at rest, and a single dispatch point. What we would have to add anyway is exactly what makes our server different: an access gate in `mcp.callTool`, strict schema validation before any handler runs (rejecting common parameters, positional arrays and wrong types), stdout isolation, invoking the registered scriptblock instead of a command name, and a 7.4 floor. Rough saving if we fork rather than write from scratch: about 1.5-2 days of the 10-15 day estimate.

## What to borrow, and how to adapt it

| # | Source | Take | Adapt before using |
|---|---|---|---|
| 1 | `mcp.core.stdio.main` (`src/pwsh.mcp/psmcp.core.ps1`, ~lines 465-570) | The loop shape: injected `-In` / `-Out`, `break` on EOF, `continue` on blank lines, per-line `try`/`catch`. | Write protocol messages through our dedicated `StreamWriter` (their default `$Out = [Console]::Out` is the same stream that stray output hits). Answer parse failures with `-32700` (id `null`) and invalid requests with `-32600` instead of silently dropping them. Treat "no `id` key" as a notification, not `$null -eq $request.id`. **Do not echo the raw input line** to stderr or any log; log the method and length only. |
| 2 | `classes/AnnotationsAttribute.cs` and `mcp.InputSchema.getSchema` (~lines 252-265) | Declaring tool metadata with an attribute on the function (`[Annotations(Title=..., ReadOnlyHint=...)]`), which is emitted as the tool's `annotations` and `title`. | Add an `Access` attribute in the same style (mandatory; registration fails if missing, which is what our registry-invariant test enforces) and **derive `readOnlyHint` from it** (`Read` implies read-only). Avoid `Add-Type -Path ... -ErrorAction SilentlyContinue` (`pwsh.mcp.psm1` line 10), which hides compile errors. A PowerShell `class : System.Attribute` would avoid a C# compile step at import; untested. |
| 3 | `mcp.InputSchema.getTypeSchema` / `getSchema` / `mcp.getCmdHelpInfo` | Recursive array `items`; `date-time` format for date types; tool description from `.SYNOPSIS` via `Ast.GetHelpContent()` (cheaper than `Get-Help`); parameter descriptions from `HelpMessage`. | Publish `enum`, `pattern`, `minimum` / `maximum`, `minLength` / `maxLength` from `ValidateSet`, `ValidatePattern`, `ValidateRange`, `ValidateLength`; set `additionalProperties: false`; omit empty `required`; **fail registration when the description is missing** instead of falling back to the function name. Optional for the Joplin server (our registry declares schemas explicitly); relevant for a generic framework. |
| 4 | `New-MCPServer -WhatIf` (~lines 644-664) | A dry run that prints the generated tool schema as JSON without starting the server. | Offer `Start-JoplinMcpServer -ListTools`, and use its output as a golden-file snapshot test so any change to a tool's published schema shows up in review. |
| 5 | `tests/psmcp.transport.tests.ps1`, `tests/psmcp.help.tests.ps1` | Driving the loop with `StringReader` / `StringWriter`; and the "enumerate everything the manifest exports and assert each has help" pattern, which is the same enumerate-and-assert shape as our registry-invariant test. | Apply the pattern to the registry (every tool has `Access`, a non-empty description and a strict schema). Its code-compliance test only checks that files exist, load and parse, so skip it. |
| 6 | `.github/workflows/ci.yml` | Separate analyzer and test jobs; PSScriptAnalyzer plus a pinned Pester version; test matrix across operating systems; test-result artifacts. | Add PowerShell **7.4** to the matrix; **pin actions by commit SHA** (the convention referenced in johnsarie27/joplin-mcp#2) rather than `@v6`. |
| 7 | `mcp.requestHandler` `initialize` branch (~lines 382-408) | Always answering with a version the server supports, plus an explicit, commented per-client fallback (with the upstream issue link). | Feeds our open task "pin the supported MCP protocol versions": keep a list, answer the client's version if supported, otherwise the latest, and test against the real clients we care about. |
| 8 | `New-MCPServer` (~lines 633-637) | `$PSStyle.OutputRendering = PlainText` (our test showed ANSI colour codes in stderr diagnostics without it). | Use `UTF8Encoding($false)` for the console encodings; `[Text.Encoding]::UTF8` carries a BOM preamble (not tested on Windows). |

**Do not borrow:** `& $toolName @toolArgs` (alias shadowing, and it splats client-supplied keys, which is how common parameters and positional arrays get through), default-depth `ConvertTo-Json`, the silent drops, the raw-input echo, the hard 7.5 floor, and the unused file logger.

## Test cases this adds to our plan
Each was observed failing in pwsh.mcp, so they are known-real regressions to guard against:
- Common parameters (`ErrorAction`, `Verbose`, `WhatIf`, `Confirm`, `OutVariable`) in `arguments` are rejected with `-32602` before the handler runs.
- `arguments` that is an array (or any non-object) is rejected with `-32602`, never bound positionally.
- Strict JSON types: a string for an integer parameter is rejected.
- A tool whose name matches a PowerShell alias or cmdlet (`echo`, `ls`, `select`) runs the **registered handler**, not the alias.
- A request with an invalid `jsonrpc` version or no `method` gets `-32600`; malformed JSON gets `-32700`; neither leaves the client waiting.
- The raw input line never appears in stderr or any log.
- Unknown tool returns `-32602` (a protocol error), not an `isError` result.
- A handler returning a nested object either serializes it fully or fails loudly; never `System.Collections.Hashtable` strings.
- No tool is registered without a description of at least some minimum length.

## Corrections to our own design found along the way
Running real PowerShell showed two defects in the original dispatcher sketch: `3>&2 4>&2 5>&2 6>&2` is a **parse error** ("reserved for future use"), and `Write-Error ... 2>&1 | Out-Host` writes to stdout. Both are fixed in [dispatcher.md](../../design/dispatcher.md). The verified replacement is: capture a dedicated stdout `StreamWriter`, call `[Console]::SetOut([Console]::Error)`, and run each handler with `*>&1`, sending every non-output record to stderr. On PowerShell 7.7, by default seven kinds of stray output reached stdout; with this technique none did.

## Still unverified
The project's own Pester suite; behavior on Windows and on PowerShell 7.4 (its declared floor is 7.5); its `.agents/skills/new-mcp-server` skill (relevant to the generic/templated-server idea, not read); and the Gallery package versus the repository.
