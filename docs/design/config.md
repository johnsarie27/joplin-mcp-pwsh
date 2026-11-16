# Configuration

`config.json` is a superset of the Python server's shape, so one file can serve both until the Python server gains the new keys. The rules these fields express are in [access-control.md](access-control.md).

## Example

```json
{
  "token": "paste-your-web-clipper-token-here",
  "host": "localhost",
  "port": "41184",
  "notebooks": [
    { "id": "Work",                             "access": "write", "descendants": true },
    { "id": "Personal/Tech",                    "access": "read" },
    { "id": "0123456789abcdef0123456789abcdef", "access": "read" },
    { "id": "Personal/Taxes",                   "access": "none" },
    { "id": "$root",                            "access": "write" },
    { "id": "$tags",                            "access": "write" }
  ]
}
```

`host` and `port` default to `localhost` and `41184`. There is no port discovery.

## `notebooks` entries

| Field | Values | Notes |
|---|---|---|
| `id` | notebook id (32 hex), title, `/`-separated path, `*`, `$root`, `$tags` | Resolution order: exact id, then path (contains an unescaped `/`), then plain title. Paths are anchored at the root; titles compare case-insensitively. `\/` is a literal slash and `\\` a literal backslash in a title (written `"Q3\\/Q4 Plans"` in JSON). |
| `access` | `read` (default), `write`, `none` | `write` implies `read`. `none` denies the notebook and its entire subtree, and always wins. |
| `descendants` | boolean, default `false` | Applies the entry to the notebook and every notebook below it. Not allowed on `none` (always recursive) or on sentinels. See the open question about `*` below. |

## Rules in brief

- Grants are additive.
- `*` + `write` implies `$root` and `$tags`; `$root` / `$tags` with `none` revoke them even under `*` write.
- A grant that matches several notebooks grants nothing (use an id or path); a `none` that matches several denies all of them and warns.
- Grant or deny entries that match nothing warn on stderr.

## Loading and validation

- Path from `$env:JOPLIN_CONFIG`, falling back to `./config.json`.
- Loaded with `ConvertFrom-Json -AsHashtable`.
- **Re-read on every call**, so edits apply without a restart.
- On startup, warn on stderr if `config.json` is group- or world-readable (Unix).

The following are a fatal `ConfigError`:

- a non-object entry, or an unknown `access` level;
- `none` on `*`;
- `descendants` on a `none` entry or on a sentinel;
- a non-boolean `descendants`;
- empty path segments (`A//B`, a leading or trailing `/`);
- an invalid backslash escape (anything other than `\/` or `\\`).

## Open question: `descendants` on `*`

The source design is inconsistent here. [ADR 1](../adr/0001-opt-in-descendant-inheritance.md) calls `descendants` on `*` a no-op (since `*` already covers everything), the consolidated config table lists it as not allowed, and the list of fatal `ConfigError` cases does not mention it. Decide whether it is accepted silently, warned about, or rejected, then update this page and the tests.

## Compatibility with the Python server

| Key or value | Python server behavior | Effect |
|---|---|---|
| `descendants` | Ignored (unknown key) | Python stays flat, so it grants less than this server for the same file. |
| A path such as `Personal/Tech` | Treated as a title, which matches nothing | Python grants nothing for that entry. |
| `access: "none"` | `ConfigError` at load | Python refuses to start rather than run with broader access. |

In each case the Python server is stricter than, or refuses, the same file. How the Python server treats a `$tags` entry is not recorded in the source design.

## Secrets

`config.json` holds the Web Clipper token. It is never committed (only a `config.example.json` is), and neither the file nor the token is ever printed.
