# Framework evaluation: PoshMCP (`cezarypiatek/PoshMCP`)

One of three framework reviews; see the [comparison and recommendation](comparison.md).

**Method and limits.** Read-only review of a shallow clone at commit `c70f22e` (2025-11-30), then **confirmed by running** the module on PowerShell 7.7.0 (Ubuntu 24.04) from a scratch copy, driving the stdio server with piped input, a JSON config, and five small tools written for the test (an echo tool with a `ValidateSet` parameter, one with a `[switch]`, one that calls `Write-Host`, one that throws, and one deliberately left out of the allowlist). Not tested: the module-import path in the config, Windows, its declared 7.0 floor, and the publish workflow's behavior. The Gallery listing was not checked.

## What it is
A single 400-line module (`posh-mcp.psm1`), MIT-licensed, v0.1.0, single maintainer, last commit 2025-11-30 (about 11.5 months before this review). No tests; the only workflow publishes to the PowerShell Gallery. Different purpose from the other two: you do not write tools for it. A JSON config lists PowerShell modules or scripts and, per entry, the **cmdlets to expose**; it imports/dot-sources them and generates tool schemas from `Get-Command` / `Get-Help`. Tools only, stdio only.

## Against our requirements

| Requirement | Result | Notes |
|---|---|---|
| Rejects unknown or invalid arguments | **No** (confirmed) | Arguments are mapped to parameter names and splatted. The `errorAction: "Ignore"` common parameter was accepted and changed the tool's `$ErrorActionPreference`. Published schemas do not carry `ValidateSet` and have no `additionalProperties: false`. |
| Types are honest | **No** (confirmed) | A `[switch]` is published as type `string`, and the string `"false"` is converted with `[bool]` to **true**: `permanent: "false"` ran with `permanent=True`. |
| Tool failures return `isError` | **No** (confirmed) | A tool exception is returned as a JSON-RPC **error** with code `-32601` ("Method not found") and the message `Tool error: <Exception.Message>`. |
| Valid JSON-RPC | **No** (confirmed) | Error `code` is serialized as a **string** (`"-32601"`), not an integer, which strict clients may reject. `ping` returns an error instead of `{}`. |
| Pluggable access gate | **Config allowlist only** | Allowlisting by cmdlet name works (confirmed: a function defined in the same script but not listed was unreachable). No per-call hook, and no notion of caller-dependent access. |
| stdout stays clean | **No** (confirmed) | `Write-Host` in a tool leaks to stdout; a config naming a cmdlet that does not exist printed a `WARNING:` line to stdout **at startup**, before any protocol message. |
| Testable without a client | **No** | No tests, and the loop reads `[Console]::In` and writes `[Console]::WriteLine` directly. |
| License, floor, maintenance | **Weak** | MIT; declared floor 7.0; protocol version hardcoded to `2024-11-05` regardless of what the client asks; stale for ~11.5 months; tag-pinned actions (`@v4`). |

## Other bugs found
1. **`progressAction` is published as an input property on every tool.** The hand-written list of common parameters to skip predates PowerShell 7.4's `-ProgressAction`, so on 7.4+ it leaks into every schema. (Our floor is 7.4.)
2. **A malformed line gets an error carrying the previous request's id.** After `initialize` (id 11), a non-JSON line produced a second response with `"id":11`: a stale variable is reused, which can confuse a client's request matching.
3. **`required: []`** is emitted for tools with no required parameters, and enums, arrays and `ValidateSet` constraints are not published.
4. The README's "Isolated Scope" claim is not supported by the code: scripts are dot-sourced and modules imported into the global scope, with nothing isolating them.

## Verdict
**Not a candidate for the Joplin server.** It targets wrapping existing cmdlets, and as a framework it fails every requirement that matters to us except the allowlist. Its value is one idea and two lessons, below.

## What to borrow, and how to adapt it

| # | Source | Take | Adapt before using |
|---|---|---|---|
| 1 | `Build-ToolRegistry` and the config shape (`modules[]` / `scripts[]` with a `cmdlets[]` allowlist; paths relative to the config file) | A **declarative allowlist config** for a "wrap an existing module without writing handlers" mode. This is the natural basis for the generic/templated framework idea, combined with a pluggable access gate. | Validate the config strictly (unknown keys, types). Confine paths to the config's directory (it joins `..` freely today). Fail closed and loudly **on stderr** when an allowlisted cmdlet is missing, instead of a stdout warning. Avoid importing and dot-sourcing into the global scope. Not relevant to the Joplin server, whose handlers are bespoke. |
| 2 | `Get-CmdletToolSchema`, the "skip common parameters" step | The idea of keeping common parameters out of published schemas. | Derive the list from the runtime (`[PSCmdlet]::CommonParameters` plus `OptionalCommonParameters`), never by hand, because the set changed in 7.4. **Also reject them at call time**, which none of the three frameworks does. |
| 3 | `Start-PoshMcp` (~line 288) | `$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)`, the correct BOM-free form (compare pwsh.mcp's `[Text.Encoding]::UTF8`). | Also set `[Console]::InputEncoding`. We already use `UTF8Encoding($false)` on our own stdout writer. |
| 4 | `Invoke-McpTool` result handling (~lines 220-227) | Always returning a consistent shape (a single result wrapped as an array) serialized at an explicit `-Depth 10`. | For generic wrappers only. Handlers should return formatted strings; where structured data is returned, use an explicit depth and fail loudly if anything is truncated. |

**Do not borrow:** the splat-everything invocation, the `[bool]` coercion, error-as-`-32601`, string error codes, the global-scope loading, and the hardcoded protocol version.

## Test cases this adds to our plan
- Booleans and switches: the schema publishes `boolean`; the string `"false"` (or any non-boolean) is **rejected**, never coerced.
- The published schema never contains a PowerShell common parameter on any PowerShell version: the test enumerates `[PSCmdlet]::CommonParameters` and `OptionalCommonParameters` at runtime and asserts none is a published property.
- Every serialized error has an **integer** `code`.
- `ping` returns `{}`.
- An error for a malformed line has `id: null`; it never reuses a previous request's id.
- Startup problems (missing handler, bad config) go to stderr and leave stdout empty until the first response.
- Tool execution failures are `isError` results, never JSON-RPC errors with `-32601`.
- Only registered tools are callable; a function that exists in the same file but is not registered is unreachable.
