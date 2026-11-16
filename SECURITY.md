# Security policy

`JoplinMcp` exists to limit what an AI assistant can see and change in a Joplin vault, so a flaw in its access control is a security issue even when no credential is exposed.

## Reporting a vulnerability

**Please don't open a public issue, discussion or pull request for a vulnerability.**

Report it privately through GitHub: on this repository's **Security** tab, choose **Report a vulnerability** ([direct link](https://github.com/johnsarie27/joplin-mcp-pwsh/security/advisories/new)). Only the maintainer can see the report.

Please include:

- what an attacker or a misbehaving assistant can do, and what access they need first;
- steps to reproduce, with the relevant part of `config.json` (never the `token`);
- the version or commit, PowerShell version and operating system.

## What's in scope

- **Access-control bypass:** reading, writing, creating or deleting anything the configuration doesn't grant, including through tags, search, pagination or inheritance.
- **Information leaks:** any response that lets the assistant tell a hidden note or notebook apart from a missing one.
- **Token exposure:** the Joplin Web Clipper token appearing in any output, error, log or file.
- **Protocol integrity:** anything that corrupts the MCP stdout stream or makes the server run code other than a registered tool handler.

Known, accepted behavior is not a vulnerability; it's listed in the design, for example the [tag-name leak](docs/design/access-control.md#known-accepted-leak-tag-names) through `list_tags`.

Issues in Joplin itself, its Web Clipper API, or MCP clients belong with those projects.

## Supported versions

There is no release yet. Once there is, security fixes go into the latest release only.

## What to expect

This is a personal project maintained on a best-effort basis. Reports are acknowledged, fixed privately where possible, and disclosed in a GitHub security advisory once a fix is available, crediting the reporter unless they prefer otherwise.
