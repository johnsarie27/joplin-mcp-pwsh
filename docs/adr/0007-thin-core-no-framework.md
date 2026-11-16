# ADR 7: Thin Core Instead of an MCP Framework

## Status

Accepted — 2026-11-15

Amended by [ADR-0008](0008-powershell-7-6-floor.md) — 2026-11-15. Three statements below are now inaccurate and are left in place:

- The Context bullet saying pwsh.mcp's PowerShell 7.5 requirement is "above this project's 7.4 floor". The floor is now 7.6, so pwsh.mcp's requirement is below it.
- The Decision bullet listing "7.4 floor" among the things any framework would need added. The floor is now 7.6; that item no longer applies.
- The Consequences bullet reading "The 7.4 floor is kept." ADR-0008 replaces it with a 7.6 floor.

Everything else in this record still stands, including the decision: the per-tool access gate, strict argument validation and stdout isolation are still missing from all three frameworks.

## Context

- Three existing PowerShell MCP frameworks were reviewed and run on PowerShell 7.7: MCP.SDK, pwsh.mcp and PoshMCP ([comparison](../research/framework-evaluation/comparison.md)).
- All three leak stray output onto stdout, which corrupts the JSON-RPC stream.
- None has the per-tool access gate this design requires. MCP.SDK's folder-of-scripts model cannot pass a resolved access object to handlers; PoshMCP offers only a config allowlist; pwsh.mcp has a single dispatch point where a gate could be patched in.
- Only MCP.SDK validates arguments strictly against its schema. pwsh.mcp and PoshMCP accept PowerShell common parameters, and pwsh.mcp binds array arguments positionally.
- pwsh.mcp is the closest fit (in-process registry, injected reader and writer, clean EOF and per-line error handling, no data at rest), but it requires PowerShell 7.5, above this project's 7.4 floor.
- The stdio loop a framework would save is roughly 100 lines. Forking pwsh.mcp was estimated to save about 1.5-2 days of a 10-15 day build.
- Every framework is another dependency to track, audit and upgrade.

## Decision

- We will write a thin core ourselves (stdio loop, registry, schema validation, access gate, handler isolation) and take no dependency on, or fork of, any of the three frameworks.
- We will borrow patterns, not code dependencies, in this order of value: the injected reader/writer loop shape and per-line error handling (pwsh.mcp); registry or attribute metadata that drives `annotations` (pwsh.mcp); the `-ListTools` schema snapshot (pwsh.mcp's `-WhatIf`); the enumerate-and-assert test pattern and CI structure (pwsh.mcp); schema generation and the collect-all-violations validator (MCP.SDK / pwsh.mcp), only if a "wrap an existing function" mode is added.
- Why: everything that makes this server different (access gate, strict validation, stdout isolation, invoking the registered scriptblock, 7.4 floor) would have to be added to any framework anyway, the saving is small, and fewer dependencies leave less to audit and maintain.

## Consequences

- No third-party runtime dependency; the whole server, including its security-critical paths, is code this project owns and tests.
- The 7.4 floor is kept.
- About 1.5-2 days more build effort than forking pwsh.mcp.
- Protocol details a maintained framework would track (new MCP versions, new message types) are this project's job; supported protocol versions must be pinned and tested against real clients.
- Fixes found here (stdout isolation, strict validation) do not reach the frameworks unless contributed upstream to pwsh.mcp, which remains an option once this version works.
- A generic, templated framework (PoshMCP's declarative allowlist plus this project's access gate) is left as a possible later project, after the Joplin server exists.
