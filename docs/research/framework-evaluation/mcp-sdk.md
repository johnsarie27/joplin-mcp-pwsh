# Framework evaluation: MCP.SDK (`KevinMarquette/pwsh.mcp.sdk`)

One of three framework reviews; see the [comparison and recommendation](comparison.md).

**Method and limits.** Read-only review of a shallow clone at commit `de5505d` (2026-04-13), then **confirmed by running** the SDK on PowerShell 7.7.0 (Ubuntu 24.04) from a scratch copy, driving the stdio server with piped input and three trivial tools written for the test (an echo tool, one that calls `Write-Host`, one that throws). The SDK's own Pester suite was **not** run (Pester is not bundled and the PowerShell Gallery is blocked in the review sandbox), and the HTTP transport was not run. The Gallery listing was not checked directly; the manifest (0.1.0, `Prerelease = 'alpha'`, `PowerShellVersion = '5.1'`) matches the Gallery description seen in a search result, so it is almost certainly the same package.

## What it is
MIT-licensed, ~7,600 lines of PowerShell including 278 Pester tests, no CI config. Folder-convention SDK: scripts in `tools/`, `prompts/` and `resources/` become MCP tools, prompts and resources. Tool schemas are generated from the script's parameters, `Mandatory`, `ValidateSet` and help text. Stdio and Streamable HTTP transports.

## Against our requirements

| Requirement | Result | Notes |
|---|---|---|
| Rejects unknown or invalid arguments | **Yes** (confirmed) | An unknown argument returned `-32602` "Invalid parameters: Unknown parameter 'Bogus' is not defined in the tool schema." The published schema does not say `additionalProperties: false`, although the validator enforces it. |
| Tool failures return `isError` | **Yes, with a catch** (confirmed) | `isError: true`, but the text is a dump of the exception's properties (`ErrorRecord`, `TargetSite`, `Message`, `Data`, `InnerException`, `HelpLink`, `Source`, `HResult`, `StackTrace`) and `structuredContent` carries the same set as an object. Unscrubbed, no hook to scrub. (No local path appeared in the test.) |
| Pluggable per-tool access gate | **No** | Tools are discovered by scanning `tools/*.ps1`; scripts run as `& $Path @Parameters` with only their declared arguments, so there is no way to pass every tool a resolved access object, and no hook between lookup and execution. |
| stdout stays clean | **No** (confirmed) | A tool that called `Write-Host` put a bare `LEAK-FROM-WRITE-HOST` line on stdout **before** the JSON response, which would break a client. Tools run in-process; the only protection is documentation. It also sets `$WarningPreference = 'Stop'`, so any warning fails the call. |
| Testable without a client | **Yes** | Per-function Pester tests; `Get-Console` / `Out-Console` wrappers exist to be mocked. (Suite not run here.) |
| License, floor, maintenance | **Mixed** | MIT; runs on 7.1+ (covers our 7.4 floor). Alpha, placeholder-looking metadata (sequential GUID, "PowerShell MCP SDK Team", copyright 2024), manifest says 5.1 while the module requires 7.1. `serverInfo` is always `LocalMCPServer` / `1.0.0`. Last visible commit 2026-04-13; history not assessed (shallow clone). |

## Problems found
1. **Always-on plaintext request/response logging** to `mcp-server.log` in the server folder, no off switch. **Confirmed:** a call with the argument `SECRET-NOTE-BODY` left that string in the log twice (request and response). For us that would put note titles and bodies on disk.
2. **Malformed JSON kills the server.** **Confirmed:** one non-JSON line made the process exit with code 1 and no response; the valid `ping` sent after it was never answered. (`ConvertFrom-Json` runs outside the `try` and `$ErrorActionPreference = 'Stop'` is set.)
3. **Busy loop after the client disconnects.** **Confirmed:** after stdin closed the process never exited (killed by a 6 s timeout), used about 5.6 s of CPU in those 6 s, and appended 8,585 `Received request|` lines (~127 KB) to the log. Cause: the loop is `while ($Wait)` and nothing breaks it when `ReadLine` returns null.
4. **Protocol version is echoed unvalidated.** **Confirmed:** a client sending `protocolVersion: "1999-01-01"` got `1999-01-01` back.
5. **HTTP listener:** no authentication or `Origin` handling found (grep only; not run, not a full review). Binds `http://localhost:<port>/mcp/`.
6. **Coarse type mapping**: unknown types become `string`; no nested object schemas; `ValidateRange` / `ValidatePattern` / `ValidateLength` are not mapped. (Read, not run.)
7. **Enum checks are case-insensitive.** **Confirmed:** `Mode = "ABC"` passed a schema enum of `abc`/`def` and the tool ran with `ABC`. (PowerShell's own `ValidateSet` is case-insensitive as well, and the validator's `-notin` is too.)

## Verdict
**Do not adopt as a dependency.** The folder-of-scripts model cannot carry our central idea (every handler receives the resolved `[NotebookAccess]` and goes through `Get-AccessibleNote`), and the loop would need rewriting for items 1-4 anyway. **Worth borrowing as ideas/code to adapt**, below. Rough saving: about 1 day of the estimate, not the 3-4 days (protocol loop + registry) that adopting a framework would have saved.

## What to borrow, and how to adapt it

| # | Source | Take | Adapt before using |
|---|---|---|---|
| 1 | `Private/Get-ToolSignature.ps1` (91 lines) | Building an `inputSchema` from `Get-Command` parameters: skip common parameters via `[PSCmdlet]::CommonParameters` + `OptionalCommonParameters`; `Mandatory` -> `required`; `ValidateSet` -> `enum` (`items.enum` for arrays); help text -> `description`; untyped parameters omit `type`. | Emit `additionalProperties: false`. Map `ValidateRange` -> `minimum`/`maximum`, `ValidatePattern` -> `pattern`, `ValidateLength` -> `minLength`/`maxLength`. Optional for the Joplin server (our registry declares schemas explicitly); relevant for a future "wrap an existing function" generic module. |
| 2 | `Private/ConvertTo-JsonType.ps1` (52 lines) | The PowerShell-type -> JSON-type map and the `[]` suffix -> `array` with `items`. | It uses unanchored `switch -Regex` on the type name, so overlapping patterns can match more than one clause. Use anchored/exact matches; add `Nullable`, enum types and `Guid`/`Uri` handling. |
| 3 | `Private/Test-ToolParameter.ps1` (91 lines) | Collect **all** violations and throw one error listing them; integer/number checks that exclude `bool`; enum checks on scalars and on array items; mapping validation failures to `-32602`. | **`-in` / `-notin` are case-insensitive for strings in PowerShell** (confirmed above), so use `-cnotin` / `-cmatch`. Drive `additionalProperties`, `minimum`/`maximum`, `minLength` and `pattern` (our ids use `^[0-9a-f]{32}$`) from the schema. Decide the null policy explicitly (it silently skips null for non-required keys). Accept whole-number doubles for `integer`. |
| 4 | `Private/Start-McpStdioListener.ps1` lines 1-12 | The seam idea: wrap console I/O so tests can drive the loop. | Inject `[System.IO.TextReader]` / `[System.IO.TextWriter]` into the loop instead of mocking wrapper functions. Tests then pass `StringReader` / `StringWriter` and can assert the exact bytes written to stdout, which is our "nothing but JSON reaches stdout" test. |
| 5 | `Private/ConvertTo-JsonRpcResponse.ps1` | Mapping exception types to JSON-RPC codes (`NotImplementedException` -> `-32601`, `ArgumentException` -> `-32602`). | We already use an explicit `[McpProtocolError]` with a `Code`, which is clearer. **Avoid** its duck-typing (`if ($InputObject.result)` / `.error`), which would mistake a handler result with those property names for an envelope, and `$InputObject.ToString()` as the error message (unscrubbed). Use a typed envelope. |
| 6 | `Private/Get-Initialization.ps1` | Deriving `capabilities` from what actually exists (`tools` only if any tool is registered) and loading server `instructions` from a file. | Advertise only capabilities we implement (`tools`). Take the instructions-file idea; useful for stating scope ("searches only notebooks you can access") once, beyond tool descriptions. |
| 7 | `Tests/` layout and `Run-Tests.ps1` | One Pester file per private function (`Tests/Private/<Function>.Tests.ps1`), plus module and public-API tests. | Add the registry-invariant and information-hiding tests in [testing.md](../../design/testing.md); those have no equivalent there. |
| 8 | Folder convention (`tools/ prompts/ resources/ instructions.md`) | Convention-based discovery as the basis for a generic scaffold. | Only relevant to the "generic, templated framework" idea; not for the Joplin server. |

**Do not borrow:** the stdio loop (items 2-3 above), the always-on logging, `Get-Initialization`'s version echo, the HTTP listener, and `Invoke-Tool` / `Invoke-Script` (no place to inject access context; re-scans and re-parses help for every tool on each call).

## Test cases this adds to our plan
Each of these was observed failing in MCP.SDK, so they are known-real regressions to guard against:
- A malformed JSON line returns `-32700` and the loop keeps running.
- Closing stdin ends the loop and the process exits promptly (no spin, no growth of any file).
- The server writes **no** log file by default; any logging is opt-in and never includes request bodies.
- `initialize` negotiates the protocol version against a supported list rather than echoing.
- Enum and pattern checks are case-sensitive (`'ABC'` rejected where `'abc'` required).
- A handler or module that calls `Write-Host` / `Write-Output` cannot corrupt stdout.
- Error results contain no raw exception object and no URL or token.

## Still unverified
The SDK's own Pester suite, the HTTP transport, and a direct comparison with the Gallery package.
