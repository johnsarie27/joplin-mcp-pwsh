# Documentation

Design documentation for `JoplinMcp`, a Joplin MCP server in PowerShell 7.4+ with per-notebook access control. Start with the [overview](design/overview.md).

The design was worked out in [issue #1](https://github.com/johnsarie27/joplin-mcp-pwsh/issues/1) (transferred from the Python server's repository). These files are now the source of truth; the issue keeps the discussion history.

## Design

What the server does and how. Each document states the current design; the reasoning lives in the ADRs.

| Document | Covers |
|---|---|
| [overview.md](design/overview.md) | Goals, non-goals, architecture, module layout |
| [security-model.md](design/security-model.md) | Parity with the Python server, the access object, structural enforcement, PowerShell hardening |
| [access-control.md](design/access-control.md) | Inheritance, deny, `$root` / `$tags`, name and path resolution, information hiding |
| [config.md](design/config.md) | `config.json` format, validation, compatibility with the Python server |
| [tools.md](design/tools.md) | Tool registration, `tools/list` schema, tool inventory and access checks |
| [dispatcher.md](design/dispatcher.md) | stdio loop, dispatch, handler isolation, error conventions, initialization |
| [testing.md](design/testing.md) | Test plan and CI |

## Architecture decisions

| ADR | Decision |
|---|---|
| [1](adr/0001-opt-in-descendant-inheritance.md) | Opt-in descendant inheritance |
| [2](adr/0002-explicit-deny-wins.md) | Explicit deny that always wins |
| [3](adr/0003-root-and-tags-sentinels.md) | `$root` and `$tags` sentinels |
| [4](adr/0004-name-resolution-and-paths.md) | Ambiguous name resolution and notebook paths |
| [5](adr/0005-hidden-indistinguishable-from-missing.md) | Hidden content is indistinguishable from missing content |
| [6](adr/0006-repository-and-module-name.md) | Repository and module name |
| [7](adr/0007-thin-core-no-framework.md) | Thin core instead of an MCP framework |

### ADR conventions

- Michael Nygard's format: Title, Status, Context, Decision, Consequences, and no other sections.
- **Deviation:** the Status line carries the ISO date the status took effect (`Accepted — 2026-11-15`).
- Rationale and rejected alternatives are recorded as "Why" and "Rejected" bullets inside Decision, so the five-section format is kept.
- Numbers are monotonic and never reused. Accepted ADRs are not rewritten; a later ADR supersedes or amends them.
- There is no "we will use ADRs" record; this section serves that purpose, and ADR 1 is the first design decision.

## Research

Evidence behind decisions, kept as a record rather than maintained as current design.

| Document | Covers |
|---|---|
| [framework-evaluation/comparison.md](research/framework-evaluation/comparison.md) | Comparison of three PowerShell MCP frameworks and the recommendation behind ADR 7 |
| [framework-evaluation/mcp-sdk.md](research/framework-evaluation/mcp-sdk.md) | MCP.SDK review |
| [framework-evaluation/pwsh-mcp.md](research/framework-evaluation/pwsh-mcp.md) | pwsh.mcp review |
| [framework-evaluation/poshmcp.md](research/framework-evaluation/poshmcp.md) | PoshMCP review |
| [slash-in-notebook-titles.md](research/slash-in-notebook-titles.md) | Open live check: `/` and `\` in Joplin notebook titles |
