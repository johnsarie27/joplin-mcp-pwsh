# ADR 9: A Module with an Exported Server Entry Point

## Status

Accepted — 2026-11-15

## Context

- An MCP client launches a stdio server as a process from a command line in its config. Nothing in MCP requires the server to be a PowerShell module; a plain script would also work.
- The design so far mixed two shapes: [ADR 6](0006-repository-and-module-name.md) names a module, `JoplinMcp`, and the design lays out a manifest, root module and `Private/` code, but the overview launched the server with `pwsh -File Start-JoplinMcpServer.ps1`, a script outside the module.
- The Python sibling is a package with an entry point, which its maintainer runs pinned to a release tag (`uvx --from git+...@<tag>`). The PowerShell equivalent of a versioned, installable unit is a module.
- A module can export commands for the person operating the server alongside the server itself, for example `-ListTools` today and a possible config-inspection command later. A script offers one entry point.
- The PowerShell build harness used by the maintainer's other modules (`jjohns-dev/pwsh-module-ci`, see [ADR 10](0010-adopt-pwsh-module-ci.md)) builds modules only, and stages only the manifest, root module, `README.md`, `Public/` and `Private/`. A launcher script at the root would not ship.
- Every launch imports the module, and the server's stdout carries only JSON-RPC ([security-model.md](../design/security-model.md#powershell-specific-hardening)).

## Decision

- We will package `JoplinMcp` as a PowerShell module: `JoplinMcp.psd1` and `JoplinMcp.psm1` at the repository root, exported functions in `Public/`, everything else in `Private/` (including `Private/Tools/`).
- We will make `Start-JoplinMcpServer` an exported function and the server's entry point. Clients launch it with `pwsh -NoProfile -NonInteractive -Command Start-JoplinMcpServer`, relying on module auto-loading from `PSModulePath`; `Start-JoplinMcpServer -ListTools` prints the tool schemas and exits.
- We will export only commands meant for the person running the server. The MCP tools are the server's interface to the assistant and are never exported as PowerShell commands.
- We will keep module import silent: importing `JoplinMcp` writes nothing to any stream.
- Why: a module is the PowerShell form of the Python sibling's versioned package, it can carry operator commands next to the server, and it is the shape the build harness, Pester conventions and the maintainer's other repositories already use.
- Rejected: a standalone script application launched with `-File`. Simplest to run from a checkout, but no manifest or versioned install, no room for operator commands, and no harness support.
- Rejected: a module plus a separate launcher script (the previous design). The launcher would not ship with the module, and two entry points is one more thing to keep in step.

## Consequences

- Install, update and version pinning use module tooling (`Install-PSResource`, `Update-PSResource`, `-Version`), the same habits as the maintainer's other modules.
- The module must be installed in a folder on `PSModulePath` for the short launch command to work. Otherwise the client config needs `Import-Module <path>; Start-JoplinMcpServer`, which is awkward to quote in a JSON config, especially on Windows.
- Until the module is published to the PowerShell Gallery, installing means extracting a release archive into a module folder; the README must document this. Publishing is a separate decision.
- Exported functions are a public PowerShell interface with their own help and compatibility expectations, separate from the MCP tool schemas.
- Each launch pays for a module import; the server's long-running loop makes this negligible.
- The overview's module layout and launch instructions change to match.
