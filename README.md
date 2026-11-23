# joplin-mcp-pwsh

`JoplinMcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server for [Joplin](https://joplinapp.org), written in PowerShell 7.6+. It exposes Joplin's Web Clipper API as MCP tools over stdio, so an AI assistant can search, read and edit your notes, but only in the notebooks you grant it.

It is the PowerShell sibling of the Python server [`johnsarie27/joplin-mcp`](https://github.com/johnsarie27/joplin-mcp), and reads the same `config.json` format, extended with:

- **Opt-in inheritance:** grant a notebook and everything below it with `"descendants": true`.
- **Explicit deny:** `"access": "none"` blocks a notebook and its subtree, and always wins over any grant.
- **Notebook paths:** grant `Personal/Tech` rather than every notebook titled `Tech`.
- **Tag management** behind its own `$tags` permission.
- **Information hiding:** notes and notebooks the assistant can't see are indistinguishable from ones that don't exist.

## Status

**Early development. The server starts and speaks MCP, but it has no tools yet.** The module scaffold, protocol loop, tool registry and CI are in place. Config loading, the access layer, the Joplin client and the tools are still to come; the design is recorded in [`docs/`](docs/README.md) and the work is tracked in [issue #1](https://github.com/johnsarie27/joplin-mcp-pwsh/issues/1). Until a release exists, use the [Python server](https://github.com/johnsarie27/joplin-mcp).

## Documentation

- [Design overview](docs/design/overview.md): goals, architecture and module layout.
- [Access control](docs/design/access-control.md): how grants, deny, paths and information hiding work.
- [Configuration](docs/design/config.md): the `config.json` format.
- [Architecture decisions](docs/adr/README.md): why the design is the way it is.

## Contributing

Changes go through pull requests against `main`, which requires the `docs` check to pass. AI coding agents should read [AGENTS.md](AGENTS.md) first.

## Security

Please don't report vulnerabilities in public issues. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
