# Documentation

Design documentation for `JoplinMcp`, a Joplin MCP server in PowerShell 7.6+ with per-notebook access control. Start with the [overview](design/overview.md).

The design was worked out in [issue #1](https://github.com/johnsarie27/joplin-mcp-pwsh/issues/1) (transferred from the Python server's repository). These files are now the source of truth. The issue's comments are the original, timestamped discussion behind the ADRs; they are hidden as outdated and can be expanded on the issue page.

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

Why the design is the way it is. The [ADR index](adr/README.md) lists every ADR with its status, which later ADRs amend or supersede which earlier ones, and the conventions for writing them.

## Research

Evidence behind decisions, kept as a record rather than maintained as current design.

| Document | Covers |
|---|---|
| [framework-evaluation/comparison.md](research/framework-evaluation/comparison.md) | Comparison of three PowerShell MCP frameworks and the recommendation behind ADR 7 |
| [framework-evaluation/mcp-sdk.md](research/framework-evaluation/mcp-sdk.md) | MCP.SDK review |
| [framework-evaluation/pwsh-mcp.md](research/framework-evaluation/pwsh-mcp.md) | pwsh.mcp review |
| [framework-evaluation/poshmcp.md](research/framework-evaluation/poshmcp.md) | PoshMCP review |
| [slash-in-notebook-titles.md](research/slash-in-notebook-titles.md) | Open live check: `/` and `\` in Joplin notebook titles |
| [effort-estimate.md](research/effort-estimate.md) | Per-piece effort estimate made before implementation |
| [original-outline.md](research/original-outline.md) | The first, superseded outline of the design, preserved verbatim |
