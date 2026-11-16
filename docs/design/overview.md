# Overview

A Joplin MCP server written in PowerShell 7.4+. It exposes Joplin's Web Clipper REST API as MCP tools over stdio, behind a per-notebook access-control model.

It is the PowerShell sibling of the Python server, [`johnsarie27/joplin-mcp`](https://github.com/johnsarie27/joplin-mcp). Throughout these docs, "the Python server" means that repository.

## Goals

- Expose Joplin's Web Clipper REST API as MCP tools over stdio, written in PowerShell 7.4+.
- Reproduce the Python server's security model (per-notebook read/write access, fail-closed by default, access checked on the note's notebook) and extend it with opt-in inheritance, explicit deny, paths and tag management. See [access-control.md](access-control.md).
- Be testable (Pester 5) and keep the access layer small enough to audit.

## Non-goals

- **Windows PowerShell 5.1 support.** Encoding and stdout behavior differ; not worth the compatibility cost.
- **Arbitrary script execution.** Only registered tool handlers can run.
- **A config format that diverges from the Python server without reason.** The config is a superset: entries that use only the Python server's keys and unambiguous ids or titles grant the same access in both servers. New keys are designed to fail safe on the Python server (`descendants` is ignored, so it stays flat and narrower; paths match nothing; `access: "none"` makes it refuse to load). Known behavioral differences are listed in [access-control.md](access-control.md#intentional-differences-from-the-python-server).

## Architecture

```text
+------------+   stdio / JSON-RPC 2.0   +-------------------------------+   HTTP (token in query)   +----------------+
| MCP client | <----------------------> | pwsh MCP host                 | <-----------------------> | Joplin Web     |
|            |                          |  protocol -> dispatcher       |                           | Clipper API    |
+------------+                          |  -> access gate -> handler    |                           | :41184         |
                                        +-------------------------------+                           +----------------+
```

Request path: `read line` -> `parse` -> `route by method` -> (for `tools/call`) `validate args against schema` -> `access gate` -> `handler` -> `single response write`.

The core is written from scratch rather than built on an existing PowerShell MCP framework ([ADR 7](../adr/0007-thin-core-no-framework.md)).

## Module layout

```text
JoplinMcp/
├── JoplinMcp.psd1 / JoplinMcp.psm1
├── Start-JoplinMcpServer.ps1        # entry point: pwsh -NoProfile -NonInteractive -File ...
├── Private/
│   ├── Config.ps1                   # Import-JoplinConfig + validation
│   ├── Access.ps1                   # [NotebookAccess], Resolve-NotebookAccess, Get-AccessibleNote, Select-ReadableNotes
│   ├── Client.ps1                   # Invoke-JoplinApi (token handling, error scrubbing, ID validation)
│   ├── Protocol.ps1                 # stdio loop, JSON-RPC routing, response writer
│   ├── Registry.ps1                 # Register-JoplinTool, schema validation
│   └── Tools/                       # one file per tool, each calls Register-JoplinTool
└── tests/                           # Pester 5: config, access, registry invariants, dispatcher
```

The module is named `JoplinMcp` and the repository `joplin-mcp-pwsh` ([ADR 6](../adr/0006-repository-and-module-name.md)).

**No port discovery.** An early outline scanned ports 41184–41194 for the Clipper server. That is dropped: the Python server reads `host`/`port` from config (default `localhost:41184`), and so does this one. See [config.md](config.md).

## Where to go next

| Topic | Document |
|---|---|
| What the server protects and how | [security-model.md](security-model.md) |
| The access rules (inheritance, deny, sentinels, names, paths, information hiding) | [access-control.md](access-control.md) |
| `config.json` format and validation | [config.md](config.md) |
| Tool registry, `tools/list`, tool inventory | [tools.md](tools.md) |
| stdio loop, dispatch, error conventions | [dispatcher.md](dispatcher.md) |
| Test plan | [testing.md](testing.md) |
