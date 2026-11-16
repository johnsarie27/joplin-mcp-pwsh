# Security model

The server's security model starts from the Python server's (the parity target below), makes the access gate structural rather than per-tool, and adds PowerShell-specific hardening. The access rules themselves (inheritance, deny, sentinels, name and path resolution, information hiding) are in [access-control.md](access-control.md).

## Parity target: what the Python server does

1. **Flat config list.** Entries are `{ "id": <id | name | "*" | "$root">, "access": "read" | "write" }`. `write` implies `read`; a missing `access` defaults to `read`.
2. **Fail closed.** If nothing is configured, every note-content tool refuses.
3. **Live resolution.** Notebook ids and names are resolved against the live notebook list on every call; names are case-insensitive and may match several notebooks (all matches are granted). The config file is re-read on every call so edits apply without a restart.
4. **Check on `parent_id`.** For single-note operations the server fetches the note first and checks its notebook. Search results are post-filtered so out-of-scope notes are never shown.
5. **`$root` sentinel** grants permission to create notebooks at the root; it deliberately does *not* count as access to any notebook.
6. **No hierarchy inheritance.** Access to a parent notebook does not extend to its children. This server makes inheritance opt-in ([ADR 1](../adr/0001-opt-in-descendant-inheritance.md)).
7. **`list_notebooks` is unfiltered, by design.** In `server.py`, `list_notebooks` calls neither `_require_access()` nor `can_read`, and returns the title and id of *every* notebook, including ones the config never grants. That was a deliberate original choice (johnsarie27/joplin-mcp#1: "metadata only, not note content"), not an oversight. This server filters it to readable notebooks ([ADR 5](../adr/0005-hidden-indistinguishable-from-missing.md), [tools.md](tools.md#list_notebooks-differs-from-the-python-server)); whether the Python server should change is an open question in johnsarie27/joplin-mcp#68.

## Access object

A PowerShell 7 `class`, immutable after construction. `Resolve-NotebookAccess` builds it from the config and the live notebook tree, so every set below is already fully expanded: `descendants` applied, paths and names resolved to ids, and denied subtrees removed from the grant sets.

```powershell
class NotebookAccess {
    hidden [bool] $ReadAll
    hidden [bool] $WriteAll
    hidden [System.Collections.Generic.HashSet[string]] $ReadIds
    hidden [System.Collections.Generic.HashSet[string]] $WriteIds
    hidden [System.Collections.Generic.HashSet[string]] $DeniedIds   # denied notebooks + all descendants
    hidden [bool] $GrantRoot     # {"id": "$root", "access": "write"}
    hidden [bool] $RootDenied    # {"id": "$root", "access": "none"}
    hidden [bool] $GrantTags     # {"id": "$tags", "access": "write"}
    hidden [bool] $TagsDenied    # {"id": "$tags", "access": "none"}

    [bool] CanRead([string] $notebookId) {
        if ($this.DeniedIds.Contains($notebookId)) { return $false }   # deny always wins
        return $this.ReadAll -or $this.WriteAll -or
               $this.ReadIds.Contains($notebookId) -or $this.WriteIds.Contains($notebookId)
    }
    [bool] CanWrite([string] $notebookId) {
        if ($this.DeniedIds.Contains($notebookId)) { return $false }
        return $this.WriteAll -or $this.WriteIds.Contains($notebookId)
    }
    [bool] CanCreateRootNotebook() { return -not $this.RootDenied -and ($this.WriteAll -or $this.GrantRoot) }
    [bool] CanManageTags()         { return -not $this.TagsDenied  -and ($this.WriteAll -or $this.GrantTags) }
    # $root and $tags are intentionally excluded: they are permissions to create notebooks / manage
    # tags, not to touch notes, so they never satisfy the note-content gate on their own.
    [bool] HasAnyAccess() {
        return $this.ReadAll -or $this.WriteAll -or
               $this.ReadIds.Count -gt 0 -or $this.WriteIds.Count -gt 0
    }
}
```

IDs use `StringComparer.Ordinal`; notebook-name matching uses `OrdinalIgnoreCase` (closest .NET equivalent to Python's `casefold()`). A config consisting solely of `none` entries leaves both grant sets empty and therefore fails closed.

## Structural enforcement

In the Python server each tool calls `_require_access()` by hand. Here the registry makes the gate structural:

- Every tool is registered with a mandatory **`Access`** value: `Read`, `Write`, `CreateNotebook` or `ManageTags`.
- The dispatcher calls the fail-closed gate (`HasAnyAccess()`) before every `Read` and `Write` handler. `ManageTags` tools are gated by `CanManageTags()` in the dispatcher. `CreateNotebook` is checked in the handler against `CanCreateRootNotebook()` / `CanWrite($parent_id)`. A config containing only `$root` / `$tags` sentinels therefore never opens note-content tools.
- Handlers receive the `[NotebookAccess]` instance and do the per-note check through `Get-AccessibleNote`, which fetches the note and returns it only if `CanRead` / `CanWrite` allows on its `parent_id`, and otherwise throws the same not-found error a missing note produces ([ADR 5](../adr/0005-hidden-indistinguishable-from-missing.md)).
- A Pester test enumerates the registry and **fails the build if any tool lacks `Access`**, or if a tool declared `Write` has no write-assertion path. A new tool cannot ship unguarded by accident.
- `Access` also drives MCP tool annotations (`readOnlyHint`) in `tools/list`. It can be declared as a parameter of `Register-JoplinTool` or as an attribute on the handler function in the style of pwsh.mcp's `[Annotations()]`; either way it is mandatory, and a tool without it fails registration.

## PowerShell-specific hardening

| Risk | Mitigation |
|---|---|
| **Token leakage via errors.** `Invoke-RestMethod` exceptions can embed the request URL, and Joplin requires the token in the query string. | One wrapper, `Invoke-JoplinApi`, is the only code that touches the token. It builds the URI internally, catches exceptions, and rethrows a sanitized message from status code + Joplin's response body. Never `throw $_`. Never log URIs. |
| **ID injection / path traversal.** `note_id` is interpolated into a URL path. | Validate every id against `^[0-9a-f]{32}$` before use; `[uri]::EscapeDataString` all query values. |
| **stdout corruption.** Any stray pipeline output, `Write-Host`, warning, verbose/debug line or `[Console]::WriteLine` breaks the JSON-RPC stream. (Verified on PowerShell 7.7: by default all of these reach stdout.) | Capture a dedicated stdout `StreamWriter` at startup and write *only* protocol messages to it; then call `[Console]::SetOut([Console]::Error)` so stray `Console.Out` writes go to stderr. Run each handler through `Invoke-HandlerIsolated` ([dispatcher.md](dispatcher.md)): merge all streams with `*>&1` and route every non-output record (information, warning, verbose, debug, error) to stderr, keeping only the success output. Handlers must return exactly one value. Launch with `-NoProfile -NonInteractive` (profiles can write to stdout). PowerShell has no `3>&2`-style redirection (it is a parse error, "reserved for future use"), so `*>&1` plus filtering by record type is the working technique. |
| **Encoding.** | PowerShell 7 defaults to UTF-8 without BOM, but set `[Console]::InputEncoding`/`OutputEncoding` explicitly and use `[System.Text.UTF8Encoding]::new($false)` on the writer (not `[Text.Encoding]::UTF8`, which carries a BOM preamble). Set `$PSStyle.OutputRendering = 'PlainText'` so diagnostics carry no ANSI colour codes. |
| **Arbitrary execution and name resolution.** | Dispatch by hashtable lookup of registered handlers and invoke the **registered scriptblock** with the validated arguments, never a command name: PowerShell resolves aliases before functions, so a tool named `echo` would run `Write-Output` with the client's arguments (seen in pwsh.mcp). No `Invoke-Expression`. Never splat client-supplied keys. |
| **Unknown, extra and mistyped arguments.** (Each [evaluated framework](../research/framework-evaluation/comparison.md) let some of these through.) | Strict schema validation before any handler runs: `arguments` must be a JSON object (an array would bind positionally); unknown properties are rejected (`additionalProperties: false`), including PowerShell **common parameters** (`ErrorAction`, `Verbose`, `WhatIf`, `Confirm`, `OutVariable`, ...); JSON types must match exactly, so a string is never accepted for an integer and the string `"false"` is never accepted for a boolean (it coerces to true); enum and pattern checks are case-sensitive (`-cnotin`, `-cmatch`; PowerShell's `-in` is case-insensitive). The published schema never contains a common parameter: derive that list at runtime from `[PSCmdlet]::CommonParameters` and `OptionalCommonParameters`, because a hand-written list misses `ProgressAction`, added in 7.4. |
| **TOCTOU** (note moved between check and write). | Same gap as the Python server. Cheap mitigation: re-fetch `parent_id` immediately before write operations. Joplin has no transactions, so no stronger guarantee is promised. |
| **Config file permissions.** | On startup, warn on stderr if `config.json` is group/world-readable (Unix). Windows ACL check is a possible follow-up. |
| **Data at rest and logging.** | No log file by default. Any logging is opt-in and never records request bodies, tool arguments or results. The raw input line is never echoed to stderr (a parse failure logs only its length). |
