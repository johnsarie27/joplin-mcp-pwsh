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
| `descendants` | boolean, default `false` | Applies the entry to the notebook and every notebook below it. Not allowed on `none` (always recursive) or on sentinels. On `*` it has no effect and logs a warning (see [below](#the-descendants-flag-on-the-wildcard-entry)). |

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

The following load normally but warn on stderr:

- a grant or deny entry that matches no notebook ([access-control.md](access-control.md#ambiguity));
- a `none` entry that matches several notebooks;
- `descendants: true` on `*` ([below](#the-descendants-flag-on-the-wildcard-entry)).

### The descendants flag on the wildcard entry

`{ "id": "*", "descendants": true }` is accepted, and the flag is ignored with a stderr warning such as `Config entry "*": descendants has no effect on "*", which already covers every notebook.`

- **Why not an error:** the entry grants exactly the same access with or without the flag, so refusing the config would protect nothing. The Python server loads it (it ignores `descendants`), so rejecting it would also make a shared config unloadable here over a flag that changes nothing.
- **Why not silent:** writing it suggests a misunderstanding of `*`, which already covers every notebook, and the warning says so.
- This differs from `none` on `*` and `descendants` on sentinels, which are errors because they would change or misstate what the entry grants.

The original design discussion called this case a no-op (Decision 1 in issue #1); the warning was added when settling it (#13).

## Compatibility with the Python server

| Key or value | Python server behavior | Effect |
|---|---|---|
| `descendants` | Ignored (unknown key) | Python stays flat, so it grants less than this server for the same file. |
| A path such as `Personal/Tech` | Treated as a title, which matches nothing | Python grants nothing for that entry. |
| `access: "none"` | `ConfigError` at load | Python refuses to start rather than run with broader access. |

In each case the Python server is stricter than, or refuses, the same file. How the Python server treats a `$tags` entry is not recorded in the source design.

## Secrets

`config.json` holds the Web Clipper token. It is never committed (only a `config.example.json` is), and neither the file nor the token is ever printed.
