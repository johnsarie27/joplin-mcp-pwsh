# Overview

A Joplin MCP server written in PowerShell 7.6+ ([ADR 8](../adr/0008-powershell-7-6-floor.md)). It exposes Joplin's Web Clipper REST API as MCP tools over stdio, behind a per-notebook access-control model.

It is the PowerShell sibling of the Python server, [`johnsarie27/joplin-mcp`](https://github.com/johnsarie27/joplin-mcp). Throughout these docs, "the Python server" means that repository.

## Goals

- Expose Joplin's Web Clipper REST API as MCP tools over stdio, written in PowerShell 7.6+.
- Reproduce the Python server's security model (per-notebook read/write access, fail-closed by default, access checked on the note's notebook) and extend it with opt-in inheritance, explicit deny, paths and tag management. See [access-control.md](access-control.md).
- Be testable (Pester, built and run by the shared harness in [ADR 10](../adr/0010-adopt-pwsh-module-ci.md)) and keep the access layer small enough to audit.

## Non-goals

- **Windows PowerShell 5.1 support.** Encoding and stdout behavior differ; not worth the compatibility cost.
- **PowerShell versions out of Microsoft support.** The floor is the current LTS release and moves with it ([ADR 8](../adr/0008-powershell-7-6-floor.md)).
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

`JoplinMcp` is a PowerShell module whose exported `Start-JoplinMcpServer` is the server's entry point ([ADR 9](../adr/0009-module-with-exported-entry-point.md)). The module sits at the repository root, in the shape the build harness expects ([ADR 10](../adr/0010-adopt-pwsh-module-ci.md)):

```text
joplin-mcp-pwsh/
├── JoplinMcp.psd1                   # manifest: PowerShellVersion 7.6, FunctionsToExport = Public/ names
├── JoplinMcp.psm1                   # root module: dot-sources Public/ and Private/; writes nothing on import
├── Public/
│   └── Start-JoplinMcpServer.ps1     # the server entry point; -ListTools prints the tool schemas and exits
├── Private/
│   ├── Config.ps1                   # Import-JoplinConfig + validation
│   ├── Access.ps1                   # [NotebookAccess], Resolve-NotebookAccess, Get-AccessibleNote, Select-ReadableNotes
│   ├── Client.ps1                   # Invoke-JoplinApi (token handling, error scrubbing, ID validation)
│   ├── Protocol.ps1                 # stdio loop, JSON-RPC routing, response writer
│   ├── Registry.ps1                 # Register-JoplinTool, schema validation
│   └── Tools/                       # one file per tool, each calls Register-JoplinTool
├── Tests/<area>/*.tests.ps1         # Pester; see testing.md
├── Build/build.ps1                  # harness shim for local builds (copied from the harness template)
└── .github/workflows/               # thin callers of the harness, plus the docs check
```

Only the manifest, root module, `README.md`, `Public/` and `Private/` ship in the built module. Exported functions are commands for the person running the server; the MCP tools are never exported as PowerShell commands.

The module is named `JoplinMcp` and the repository `joplin-mcp-pwsh` ([ADR 6](../adr/0006-repository-and-module-name.md)).

## Running the server

An MCP client starts the server as a process. With the module installed in a folder on `PSModulePath`, PowerShell auto-loads it:

```json
{
  "command": "pwsh",
  "args": ["-NoProfile", "-NonInteractive", "-Command", "Start-JoplinMcpServer"],
  "env": { "JOPLIN_CONFIG": "/path/to/config.json" }
}
```

- `-NoProfile` keeps profile output off the protocol stream; `-NonInteractive` makes any prompt fail instead of hanging.
- A module outside `PSModulePath` needs `Import-Module <path>; Start-JoplinMcpServer` as the command, which is awkward to quote in JSON, so installing into a module folder is the supported path.
- Until the module is published to the PowerShell Gallery, installation means extracting a release archive into a module folder. Publishing is a separate, undecided step.

**No port discovery.** An early outline scanned ports 41184–41194 for the Clipper server. That is dropped: the Python server reads `host`/`port` from config (default `localhost:41184`), and so does this one. See [config.md](config.md).

## Where to go next

| Topic | Document |
|---|---|
| What the server protects and how | [security-model.md](security-model.md) |
| The access rules (inheritance, deny, sentinels, names, paths, information hiding) | [access-control.md](access-control.md) |
| `config.json` format and validation | [config.md](config.md) |
| Tool registry, `tools/list`, tool inventory | [tools.md](tools.md) |
| stdio loop, dispatch, error conventions | [dispatcher.md](dispatcher.md) |
| Test plan and CI | [testing.md](testing.md) |
