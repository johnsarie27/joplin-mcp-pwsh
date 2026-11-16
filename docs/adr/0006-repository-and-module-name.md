# ADR 6: Repository and Module Name

## Status

Accepted — 2026-11-15

## Context

- The PowerShell server lives in its own repository, separate from the Python server, `johnsarie27/joplin-mcp`.
- Newer repositories under the `johnsarie27` account use lowercase kebab-case (`joplin-mcp`, `debug-stick`, `photo-management`); older ones are PascalCase.
- PowerShell module names conventionally use PascalCase, so repository and module names need not match.
- The Python repository is public and MIT-licensed, and the design was written up for sharing.
- Alternatives considered: `pwsh-joplin-mcp` (leads with the language but sorts away from the Python repo) and `joplin-mcp-powershell` (clearest to a stranger but longer).

## Decision

- We will name the repository `johnsarie27/joplin-mcp-pwsh`.
- We will name the PowerShell module `JoplinMcp`.
- We will make the repository public under the MIT license, as in the Python repository.
- Why `joplin-mcp-pwsh`: it follows the newer naming convention, sorts next to `joplin-mcp`, and says what it is, so the Python repository can link to it as "the PowerShell sibling".

## Consequences

- The two servers sit next to each other in repository listings and are clearly related.
- Repository and module names differ (`joplin-mcp-pwsh` vs `JoplinMcp`), which a newcomer has to learn.
- Whether `JoplinMcp` is free on the PowerShell Gallery was not checked. Nothing in the design depends on publishing, but it must be checked before planning to publish.
- Public visibility means the design, issues and history are open from the start.
