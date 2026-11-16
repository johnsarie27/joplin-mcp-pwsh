# Effort estimate

**Status:** point-in-time estimate from 2026-11-15, made before any code existed. Kept as a planning record; not updated as work progresses.

Revised after ADRs 1–5: the resolver, tag tools and information-hiding rules add work over the first estimate of about 7–10 days. The estimate assumes a thin core written from scratch with patterns borrowed from the [framework evaluations](framework-evaluation/comparison.md), as decided in [ADR 7](../adr/0007-thin-core-no-framework.md). Forking `pwsh.mcp` instead would have saved about 1.5–2 days but added a PowerShell 7.5 floor and another project's design to maintain.

| Piece | Effort |
|---|---|
| Config loading + validation (`descendants`, `none`, sentinels, path and escape syntax) | 1 day |
| `NotebookAccess` + `Resolve-NotebookAccess` (live tree, descendants, deny subtraction, paths, ambiguity diagnostics) | 2–3 days |
| Registry + schema validation + required-access enforcement (4 access kinds) | 1 day |
| `Invoke-JoplinApi` (token scrubbing, id validation) | 0.5–1 day |
| Protocol loop + stdout hygiene | 1–2 days |
| 18 tool handlers, including `Select-ReadableNotes` (bounded paging) and `Get-AccessibleNote` | 2–3 days |
| Pester suite + inspector pass | 2.5–3.5 days |
| Live-Joplin verification of slashes in titles | 0.25 day |
| **Total** | **~10–15 days** for the Python server's tools plus the extended security model |
