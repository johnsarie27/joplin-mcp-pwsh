# Architecture decision records

Every architecture decision for `JoplinMcp`, with its current status and how later decisions changed it. Each record explains one decision's context, the decision itself and its consequences; the current design they produce is in [`docs/design/`](../design/).

## Index

| ADR | Decision | Status | Changed by |
|---|---|---|---|
| [1](0001-opt-in-descendant-inheritance.md) | Opt-in descendant inheritance | Accepted — 2026-11-15 | Amended by [ADR 4](0004-name-resolution-and-paths.md) |
| [2](0002-explicit-deny-wins.md) | Explicit deny that always wins | Accepted — 2026-11-15 | |
| [3](0003-root-and-tags-sentinels.md) | `$root` and `$tags` sentinels | Accepted — 2026-11-15 | |
| [4](0004-name-resolution-and-paths.md) | Ambiguous name resolution and notebook paths | Accepted — 2026-11-15 | |
| [5](0005-hidden-indistinguishable-from-missing.md) | Hidden content is indistinguishable from missing content | Accepted — 2026-11-15 | |
| [6](0006-repository-and-module-name.md) | Repository and module name | Accepted — 2026-11-15 | |
| [7](0007-thin-core-no-framework.md) | Thin core instead of an MCP framework | Accepted — 2026-11-15 | Amended by [ADR 8](0008-powershell-7-6-floor.md) |
| [8](0008-powershell-7-6-floor.md) | PowerShell 7.6 as the minimum version | Accepted — 2026-11-15 | |

## Supersessions and amendments

A superseded ADR is no longer in force; an amended one still is, except for the statements its amendment note lists.

| Later ADR | Relationship | Earlier ADR | What changed |
|---|---|---|---|
| [ADR 4](0004-name-resolution-and-paths.md) | Amends | [ADR 1](0001-opt-in-descendant-inheritance.md) | An ambiguous grant name no longer applies `descendants` to every match; it grants nothing. |
| [ADR 8](0008-powershell-7-6-floor.md) | Amends | [ADR 7](0007-thin-core-no-framework.md) | The PowerShell floor is 7.6, not 7.4; ADR 7's decision stands on its other reasons. |

No ADR has been superseded or deprecated.

## Conventions

- Michael Nygard's format: Title, Status, Context, Decision, Consequences, and no other sections.
- **Deviation:** the Status line carries the ISO date the status took effect (`Accepted — 2026-11-15`).
- Rationale and rejected alternatives are recorded as "Why" and "Rejected" bullets inside Decision, so the five-section format is kept.
- Numbers are monotonic and never reused. Accepted ADRs are not rewritten: a later ADR supersedes or amends them, and only the earlier ADR's Status section changes, with a dated note naming each statement that no longer holds.
- A new or changed ADR updates this index in the same PR: its row, its status, and any supersession or amendment.
- There is no "we will use ADRs" record; this section serves that purpose, and ADR 1 is the first design decision.
