# Framework evaluation: comparison and recommendation

Three existing PowerShell MCP frameworks were reviewed read-only, then run on PowerShell 7.7.0 (Ubuntu 24.04) against their stated behavior, to decide whether this server should build on one of them:

- [MCP.SDK](mcp-sdk.md) (`KevinMarquette/pwsh.mcp.sdk`)
- [pwsh.mcp](pwsh-mcp.md) (`warm-snow-13/pwsh-mcp`)
- [PoshMCP](poshmcp.md) (`cezarypiatek/PoshMCP`)

The outcome is [ADR 7](../../adr/0007-thin-core-no-framework.md): build a thin core and borrow patterns. The findings are folded into [security-model.md](../../design/security-model.md), [tools.md](../../design/tools.md), [dispatcher.md](../../design/dispatcher.md) and [testing.md](../../design/testing.md).

## Overall comparison

| | MCP.SDK | pwsh.mcp | PoshMCP |
|---|---|---|---|
| Purpose | Folder of scripts becomes tools | Functions become tools | Existing cmdlets become tools |
| stdout stays clean | no | no | no |
| Strict argument validation | **yes** (unknown, type, enum) | partial (binder only) | no |
| Common parameters / positional arrays rejected | n/a (script params) | no | no |
| Access-gate hook | none | one choke point (`mcp.callTool`) | config allowlist only |
| Test seam | mockable wrappers | **injected reader/writer** | none |
| Error convention | `isError` (raw exception dump) | `isError` (message only) | JSON-RPC `-32601` |
| Data at rest | always-on request/response log | none by default | none |
| EOF / malformed line | busy loop / server exits | **clean** / continues | clean / stale id |
| Version floor, activity | 5.1 manifest vs 7.1 module; alpha | 7.5 hard floor; releases through 2026-08 | 7.0; stale ~11.5 months |
| Verdict | borrow ideas | best fork or contribution candidate | borrow one idea, two lessons |

## Recommendation

**Build a thin core ourselves, borrowing patterns; do not adopt or fork any of the three.** Accepted as [ADR 7](../../adr/0007-thin-core-no-framework.md).

- Everything that makes this server different has to be added to any of them anyway: the per-tool access gate, strict argument validation (no common parameters, no positional arrays, exact JSON types), stdout isolation, invoking the registered scriptblock instead of a command name, and a 7.4 floor.
- The part a framework would save is small: the stdio loop is roughly 100 lines. Forking `pwsh.mcp` would save about 1.5-2 days of the 10-15 day estimate but leave us maintaining another project's design and a 7.5 floor.
- Do borrow, in order of value: the injected reader/writer loop shape and per-line error handling (pwsh.mcp); attribute or registry metadata that drives `annotations` (pwsh.mcp); schema generation and the collect-all-violations validator (MCP.SDK/pwsh.mcp), only if we add a "wrap an existing function" mode; the `-ListTools` schema snapshot (pwsh.mcp's `-WhatIf` dry run); the enumerate-and-assert test pattern and CI structure (pwsh.mcp).
- Contributing the stdout-isolation technique and strict validation back to `pwsh.mcp` upstream is an option once our own version works.
- For the generic/templated-framework idea: the declarative allowlist config from PoshMCP plus our access-gate abstraction is the shape to explore, as a second step after the Joplin server exists.

## Still unverified

The three projects' own Pester suites (Pester is not available in the review sandbox), behavior on Windows and on PowerShell 7.4, `pwsh.mcp`'s agent skill for creating servers, and the Gallery packages versus their repositories.
