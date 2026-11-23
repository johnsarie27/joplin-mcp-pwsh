# AGENTS.md

Guidance for AI coding agents working in this repository. It covers rules that are not obvious from the code and are costly to get wrong; the design itself lives in [`docs/`](docs/README.md).

## Project

`JoplinMcp`: a Joplin MCP server in PowerShell 7.6+ with per-notebook access control, the PowerShell sibling of the Python server [`johnsarie27/joplin-mcp`](https://github.com/johnsarie27/joplin-mcp). The module scaffold is in place (manifest, protocol loop, tool registry, CI) but there are no tools yet, and config loading, the access layer and the Joplin client are not built; the design is in `docs/`. Start with [docs/README.md](docs/README.md).

## Design docs and ADRs are the source of truth

- [`docs/design/`](docs/design/) states the current design. Read the relevant document before changing behavior it covers, and update it in the same PR when behavior changes.
- [`docs/adr/`](docs/adr/) records the decisions and their reasoning. A new architecturally significant decision gets a new ADR with the next number. Never edit an accepted ADR's Context, Decision or Consequences: a later ADR supersedes or amends it, and only the old ADR's Status section changes. Update the [ADR index](docs/adr/README.md) in the same PR; it also holds the conventions.
- [`docs/research/`](docs/research/) is a point-in-time record. Don't update it to match later changes; add a new record instead.
- Issue #1 holds the original design discussion. Its comments are hidden as outdated; where they differ from `docs/`, `docs/` wins.

## Secrets: never print `config.json`

`config.json` (gitignored) holds the live Joplin Web Clipper `token`. Anything an agent prints goes into the session transcript, so never expose that file, or whatever `$env:JOPLIN_CONFIG` points at, by any means. Joplin requires the token in the query string, so a request URL contains it too: never print request URLs.

- To learn the config's shape, read `config.example.json` (or [docs/design/config.md](docs/design/config.md)).
- To check a specific key, load the file in code and print only non-secret facts (key names, lengths, counts).
- In smoke tests, print result sizes or status codes, never the config or a URL.
- If the token is exposed, tell the user to regenerate it in Joplin (Settings → Web Clipper) and update `config.json`.

## Rules the implementation must keep

Each is explained in the linked document; these are the ones a small, reasonable-looking change can break.

- **Nothing but protocol messages on stdout.** Diagnostics go to stderr; handlers run through `Invoke-HandlerIsolated` and return exactly one value. A stray `Write-Host` or pipeline output corrupts the JSON-RPC stream. ([security-model.md](docs/design/security-model.md#powershell-specific-hardening), [dispatcher.md](docs/design/dispatcher.md))
- **Every tool declares `Access`** (`Read`, `Write`, `CreateNotebook` or `ManageTags`) and does per-note checks through `Get-AccessibleNote` / `Select-ReadableNotes`, never by fetching and filtering itself. ([security-model.md](docs/design/security-model.md#structural-enforcement), [tools.md](docs/design/tools.md))
- **Invoke the registered scriptblock, never a command name**, and never splat client-supplied keys. ([security-model.md](docs/design/security-model.md#powershell-specific-hardening))
- **Hidden looks like missing.** No response may vary with content the caller cannot see: no counts, hints or distinct errors. ([access-control.md](docs/design/access-control.md#information-hiding))
- **No `throw`.** Raise errors with `Write-Error -Exception <typed exception> -ErrorAction Stop`, which keeps the exception type and its `Code`, so a typed `catch` still matches. One function per file, named after it; every class and enum goes in `Private/Classes.ps1`, which loads first ([ADR 12](docs/adr/0012-classes-in-one-file.md)).
- **Tests go in the area folder for the property they protect** (`Tests/Registry/`, `Tests/Protocol/`, ...), not `Tests/Unit/<function>.tests.ps1` as in other modules and the house PowerShell standard; private functions are tested through `InModuleScope`. ([ADR 13](docs/adr/0013-tests-grouped-by-property.md))
- **Only `Invoke-JoplinApi` touches the token**, and no error message carries a raw exception or URL.
- **PowerShell 7.6 is the floor.** Don't use features from later versions. ([ADR 8](docs/adr/0008-powershell-7-6-floor.md))

## Workflow

- All changes go through a pull request from a `feature/` or `fix/` branch; don't commit to `main`. The `protect` ruleset blocks direct pushes, force-pushes and deleting `main`.
- Every PR has an issue: open one first, or use the task issue it completes. The PR body says `Closes #<issue>.`
- Commit and PR subjects follow `feat(<scope>): <title> (refs #<issue>)`; the PR title uses `(closes #<issue>)`.
- Pin GitHub Actions by commit SHA, not by tag. The one exception is the build harness, `jjohns-dev/pwsh-module-ci`, which is called by its `@v2` major tag by design ([ADR 10](docs/adr/0010-adopt-pwsh-module-ci.md)).

### Getting a PR merged

- **Before merging any PR, ask the maintainer whether they want to review it first, and wait for the answer.** There is no rule for which PRs they review; they decide each time. Merge only once they approve it or tell you to go ahead. Opening a PR, or a green check, is not approval.
- Merge with squash (`gh pr merge <n> --squash --delete-branch`). The squash commit takes the PR title, and the head branch is deleted on merge.
- The ruleset requires the branch to be up to date with `main`. If `main` has moved, update the branch (`gh api -X PUT repos/johnsarie27/joplin-mcp-pwsh/pulls/<n>/update-branch`) and wait for the checks to pass again before merging.
- Required checks: `docs` today; the build harness's checks are added once they exist ([testing.md](docs/design/testing.md#ci)).
- When a PR closes one of the task issues listed on issue #1, tick its box there by hand; GitHub does not tick it automatically.
- Write issue and PR bodies to a file and pass `--body-file`, then read the body back to check it. Interpolating a body inline has dropped `$root` / `$tags` and collapsed line breaks before.
