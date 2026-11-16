# Testing

Tests use Pester, at the version the build harness pins (6.2.0 at the time of writing; [ADR 10](../adr/0010-adopt-pwsh-module-ci.md)). The safety properties (registry invariants, stdout isolation, argument strictness) are meant to exist as tests before the features they protect.

Many cases below come from defects observed in the [evaluated frameworks](../research/framework-evaluation/comparison.md), so they are known-real regressions rather than hypothetical ones.

## Access layer

### Parity with the Python server

A parity matrix against the Python server's tests: `read` / `write` / `*` / `$root`, name vs id, ambiguous names, write-implies-read, empty config fails closed.

Where this server is intentionally stricter, the matrix asserts the difference rather than parity: an ambiguous grant name grants nothing here, where the Python server grants every match ([ADR 4](../adr/0004-name-resolution-and-paths.md)). The full list of differences is in [access-control.md](access-control.md#intentional-differences-from-the-python-server); each one should appear in the matrix as an explicit expected difference.

### Inheritance ([ADR 1](../adr/0001-opt-in-descendant-inheritance.md))

- Flat default unchanged.
- `descendants` expands exactly the subtree; sibling and parent are not granted.
- Read on a parent with `descendants` plus write on a child.
- Moved notebook: re-resolution picks up the new tree.
- Orphan and cycle guards.
- A non-boolean `descendants` is a `ConfigError`.
- `descendants: true` on `*` loads, grants exactly what plain `*` grants, and writes one warning to stderr and nothing to stdout ([config.md](config.md#the-descendants-flag-on-the-wildcard-entry)).

### Deny ([ADR 2](../adr/0002-explicit-deny-wins.md))

- Deny beats a grant on the same notebook.
- Deny beats an inherited grant (`descendants: true` on an ancestor).
- Deny beats `*` read and `*` write.
- Deny covers descendants, and does not affect siblings or parents.
- `none` on `*` and `descendants` on a `none` entry are rejected.
- `none` on `$root` blocks root creation under `*` write.
- A config containing only `none` entries fails closed.
- Search, tag and list results exclude denied notebooks; reads and writes on denied notes are refused.
- An unknown deny target logs a warning and changes nothing.

### Sentinels ([ADR 3](../adr/0003-root-and-tags-sentinels.md))

- `$tags` write permits create, rename and delete; absent, they are refused.
- `*` write implies `$tags`; `$tags` + `none` overrides `*` write.
- `$root` behavior matches the Python tests.
- `$root` / `$tags` alone do not satisfy the `HasAnyAccess()` gate.
- `tag_note` / `untag_note` follow the note's notebook, not `$tags`.
- `delete_tag` is refused when the tag is attached to a note in a read-only, denied or unlisted notebook, and allowed when unattached or attached only to writable notes. The refusal contains a count and no titles or ids from hidden notebooks.
- Sentinels with `descendants`, and `read`-only sentinel entries, behave as specified.

### Names and paths ([ADR 4](../adr/0004-name-resolution-and-paths.md))

- Plain name: unique match, case-insensitive match, multi-match.
- An ambiguous grant grants nothing but other entries still resolve; the error lists ids and paths.
- An ambiguous deny denies all matches and warns.
- Path anchoring: `Personal/Tech` matches the root-anchored notebook and not a deeper one with the same titles.
- Paths with `descendants`, with `none`, and combined with deny-wins.
- Escaping: `\/` and `\\` parse correctly; invalid escapes, empty segments, and leading or trailing `/` are `ConfigError`.
- Renamed or moved notebook: a path entry stops matching and warns; an id entry keeps working.
- Unresolved grant and unresolved deny entries warn without failing the server.
- 32-char hex strings are resolved as ids before paths or names.
- Printed paths are escaped, and round-trip when pasted back into a config.
- Fixtures for literal `/` and `\` in titles, once [the live check](../research/slash-in-notebook-titles.md) is done.

### Information hiding ([ADR 5](../adr/0005-hidden-indistinguishable-from-missing.md))

- A search whose matches are all hidden returns byte-identical text to a search with no matches.
- A search with mixed visible and hidden matches returns only visible ones; the count in the header matches what is shown.
- Pagination: hidden results neither produce nor suppress "more results exist"; the page cap bounds the number of Joplin requests; the same text is used when the cap is hit.
- `get_note` on a denied note and on a nonexistent id produce identical errors.
- A readable but non-writable note still gets a write-access error on write attempts.
- Tag and notebook-listing tools omit hidden items without counts.
- The scope statement appears on every empty result and on no non-empty result; tool descriptions contain the static scope text.
- Diagnostics reach stderr and never appear in any stdout message.

## Registry

- Every tool has `Access`, one of `Read`, `Write`, `CreateNotebook`, `ManageTags`; a tool declared `Write` has a write-assertion path.
- Every schema sets `additionalProperties: false`; ids use the hex pattern; no empty `required` array.
- Every tool has a description of useful length.
- The `-ListTools` output matches the golden file.
- Only registered tools are callable; a function defined in the same file but not registered is unreachable.

## Argument strictness

- Common parameters (`ErrorAction`, `Verbose`, `WhatIf`, `Confirm`, `OutVariable`) in `arguments` are rejected with `-32602` before the handler runs.
- Non-object `arguments` (an array) are rejected, never bound positionally.
- A string for an integer is rejected; the string `"false"` (or any non-boolean) for a boolean is rejected, never coerced.
- Enum and pattern checks are case-sensitive (`'ABC'` rejected where `'abc'` is required).
- A tool named like an alias or cmdlet (`echo`, `ls`, `select`) runs the registered handler.
- The published schema contains no common parameter, asserted against `[PSCmdlet]::CommonParameters` and `OptionalCommonParameters` at runtime.

## Protocol

- Feed lines to the dispatcher: exactly one response line per request, zero for notifications.
- Nothing but JSON ever reaches stdout. Include a handler that calls `Write-Host`, `Write-Warning`, `Write-Verbose` and `[Console]::WriteLine`, and assert none of it reaches stdout.
- An invalid request gets `-32600`; malformed JSON gets `-32700` with `id: null` and the loop keeps running; neither leaves the client waiting.
- No response ever reuses a previous request's id.
- `ping` returns `{}`; every error `code` is an integer.
- Unknown tool is `-32602`, not an `isError` result; tool execution failures are `isError` results, never JSON-RPC errors.
- Closing stdin ends the loop promptly, with no spin and no file growth.
- `initialize` negotiates against the supported-version list rather than echoing.
- A handler returning a nested object either serializes fully or fails loudly.
- Startup problems go to stderr and stdout stays empty until the first response.

## Secrets and data at rest

- **Token leak:** force a failing request and assert the token string appears in no output stream.
- Error results contain no raw exception object and no URL or token.
- No log file is written by default; the raw input line never appears in stderr or any log.

## Test layout

The harness discovers tests one folder below `Tests/`, named in lowercase: `Tests/<area>/*.tests.ps1`, and `*.tests.windows.ps1` for Windows-only tests.

- `Tests/Private/<function>.tests.ps1`: one file per private function.
- `Tests/Public/start-joplinmcpserver.tests.ps1`: the entry point, including `-ListTools` against the golden file.
- `Tests/Registry/`, `Tests/Protocol/`, `Tests/Access/`: the registry, protocol, access-layer and information-hiding suites above.

The harness adds its own shared tests to every run (manifest, file encoding, path literals), so this repository does not keep copies of them.

## CI

CI comes from the shared harness, `jjohns-dev/pwsh-module-ci` `@v2` ([ADR 10](../adr/0010-adopt-pwsh-module-ci.md)):

- **`ci`:** stages the module, runs PSScriptAnalyzer (fails on Error and Warning) and Pester on Linux, macOS and Windows, then verifies the JUnit result: no result file, any error at the root, or zero tests fails the run. Set a `min-tests` floor once the suite exists, and raise it as the suite grows.
- **`pssa-sarif`:** analyzer findings for the whole repository in the Security tab.
- **`release`:** builds the module archive; on a pull request, runs everything except publishing.
- **`docs`** (this repository): `Build/Test-DocLinks.ps1`, the broken-link check.
- **PowerShell version:** each runner's installed PowerShell, which must be at least 7.6, the floor ([ADR 8](../adr/0008-powershell-7-6-floor.md)). The runner images listed 7.6.9–7.6.10 when checked on 2026-11-15, and the harness's manifest test fails on any runner older than the manifest's `PowerShellVersion`.
- **Pinning:** third-party Actions by commit SHA; the harness by its `@v2` major tag (the one exception).
- **Required checks:** the `protect` ruleset requires `docs` today; add the harness's checks once they have run and their names exist.

Run the same build locally with the shim: `./Build/build.ps1 -ResolveDependency -TaskList Init`, then `./Build/build.ps1 -TaskList CombineFunctionsAndStage, Analyze, Test`.

## Manual

A pass with the MCP Inspector, as in the Python repository.
