# Access control

The rules that decide what the LLM can read, write and see. This document states the rules as they currently stand; the reasoning and rejected alternatives for each are in the ADRs linked from each section. Config syntax is in [config.md](config.md); the access object and gate that enforce these rules are in [security-model.md](security-model.md).

## Evaluation model in brief

1. Resolve every config entry against the live notebook tree (ids, then paths, then titles).
2. Union all grants. `write` implies `read`. Entries with `descendants: true` cover their whole subtree.
3. Compute the denied set: every `none` entry plus all of its descendants.
4. Subtract the denied set from both grant sets. **Deny always wins**, including over `*`.
5. Nothing granted means no access (fail closed).

This is applied once per call, in `Resolve-NotebookAccess`, producing an immutable `[NotebookAccess]`. `CanRead` / `CanWrite` answer by notebook id, so handlers, the registry and the dispatcher gate never need to know about inheritance, deny or paths.

## Inheritance (`descendants`)

Decided in [ADR 1](../adr/0001-opt-in-descendant-inheritance.md).

```json
{ "id": "Work", "access": "write", "descendants": true }
```

- `descendants` defaults to `false`, which reproduces the Python server's flat behavior exactly.
- When `true`, the entry applies to the named notebook **and every notebook below it**.
- Descendants are computed from the live notebook list (each folder has a `parent_id`) on every call, the same way ids and names are already resolved live. No extra API calls are needed beyond the folder list the server already fetches.
- **Additive grants.** Entries combine by union. Write implies read at every node. Example: `read` + `descendants` on `Work`, plus `write` (no descendants) on `Work/Projects`, gives write on `Work/Projects` and read on the rest of the `Work` subtree. No precedence ordering is needed; deny is the only exception.
- **Robustness.** Cap the tree walk and detect cycles. A notebook whose `parent_id` is unknown (orphan) is treated as a root and **never inherits** access.
- **Moves take effect immediately.** Because the tree is re-resolved per call, a notebook moved into a `descendants` grant gains access, and one moved out loses it, with no config change.

**Implementation.** Build a `parent_id -> children` map once per resolution from the folder list, then breadth-first expand each `descendants` entry into the concrete id sets.

## Deny (`access: "none"`)

Decided in [ADR 2](../adr/0002-explicit-deny-wins.md).

```json
{
  "notebooks": [
    { "id": "*",        "access": "write" },
    { "id": "Personal", "access": "none"  }
  ]
}
```

- `access: "none"` denies read and write on the named notebook **and every notebook below it**. Deny is always recursive, so `none` entries take no `descendants` flag.
- **Deny always wins.** If a notebook or any of its ancestors is denied, there is no access, regardless of any grant (including `*`, an explicit grant on the notebook itself, or an inherited grant). Same evaluation model as AWS IAM: explicit deny overrides any allow; absent any allow, implicit deny.
- **Carve-outs** under a denied parent are not expressible. Workaround: grant the specific sibling notebooks instead of the parent.

| Case | Behavior |
|---|---|
| `none` on `*` | `ConfigError` (equivalent to configuring no access; use an empty list). |
| `none` on `$root` | Allowed. Revokes root-level notebook creation even if `*` write would grant it. |
| `none` on `$tags` | Allowed. Revokes tag management even under `*` write. |
| `descendants` on a `none` entry | `ConfigError`. Deny is always recursive; the flag would be misleading. |
| `none` on a name or path matching several notebooks | Denies every match and warns on stderr (see [name resolution](#name-and-path-resolution)). |
| `none` entry for an unknown id/name | Ignored for resolution but logged to stderr, so a typo in a deny entry is visible rather than silent. |
| Orphaned notebook (unknown `parent_id`) | Treated as a root; it is only denied if it, or a real ancestor, is denied. |
| Config containing only `none` entries | Fails closed: `HasAnyAccess()` is false. |

**Effect on tools.** Denied notebooks are removed from `list_notebooks` and from search, tag and `list_notes_in_notebook` results. Reads and writes on a note in a denied notebook are refused. `create_note` and `create_notebook` into a denied notebook are refused. A denied notebook looks exactly like a nonexistent one ([information hiding](#information-hiding)).

**Implementation.** Compute the denied subtree (denied ids plus all descendants, with the same cycle and orphan guards as inheritance), then subtract it from both the read set and the write set. `ReadAll` / `WriteAll` (`*`) must also respect the denied set, which is why `CanRead` / `CanWrite` check `DeniedIds` first.

## Sentinels: `$root` and `$tags`

Decided in [ADR 3](../adr/0003-root-and-tags-sentinels.md).

Some operations are not scoped to an existing notebook: creating a notebook at the root, and creating, renaming or deleting a tag (tags are vault-wide). Two sentinel entries in the `notebooks` list cover them.

| Entry | Effect |
|---|---|
| `$root` + `write` | Allows creating notebooks at the root. Unchanged from the Python server. |
| `$tags` + `write` | Allows `create_tag`, `rename_tag`, `delete_tag`. |
| `*` + `write` | Implies both `$root` write and `$tags` write. |
| `$root` / `$tags` + `none` | Revokes that permission even under `*` write (deny wins). |
| `$root` / `$tags` + `read` | No-op; there is nothing to read. Matches how `$root` + `read` behaves in the Python server. |
| `descendants` on a sentinel | `ConfigError` (meaningless). |
| Either sentinel | Never counts as access to any notebook. `HasAnyAccess()` ignores both, so a config containing only sentinels still fails closed for note-content tools. |

- **Attach and detach stay notebook-scoped.** `tag_note(note_id, tag_id)` and `untag_note(note_id, tag_id)` check `CanWrite(note.parent_id)`, exactly like `update_note` / `complete_todo`. They do not need `$tags`.
- **Reading tags stays ungated.** `list_tags` is unchanged from the Python server. `get_notes_by_tag` post-filters by readable notebooks.
- **`rename_tag`** changes the tag's display name everywhere but no note content, so it needs only `$tags` write.

### `delete_tag` safety rule

Deleting a tag removes it from notes in notebooks the server may not be able to see or write. So:

- `delete_tag(tag_id)` requires `$tags` write **and** is refused if the tag is attached to any note in a notebook the caller cannot write to (including denied notebooks).
- Check: `GET /tags/:id/notes` (paginated), then `CanWrite(note.parent_id)` for each note. A refusal reports a count, not the contents, e.g. "Tag is attached to N note(s) outside your writable notebooks."
- Tags attached to no notes, or only to writable notes, can be deleted.

### Known, accepted leak: tag names

`list_tags` returns every tag, including tags used only in denied notebooks, so tag *names* can hint at hidden content. Left as-is for parity with the Python server. Closing it would mean filtering tags to those attached to at least one readable note, which costs extra API calls per tag. Revisit if this matters in practice.

## Name and path resolution

Decided in [ADR 4](../adr/0004-name-resolution-and-paths.md).

An entry's `id` is resolved in this order:

1. **Exact id.** A 32-char hex string is treated as an id first. Ids need no escaping and are the most robust option (stable across renames and moves).
2. **Path**, if the value contains an unescaped `/`. An unescaped `Personal/Tech` always means a path, never a literal title; a title containing `/` is addressed as `Personal\/Tech` or by id.
3. **Plain title**, matched against every notebook's own title anywhere in the tree (parity with the Python server).

### Paths

```json
{ "id": "Personal/Tech", "access": "write", "descendants": true }
```

| Rule | Behavior |
|---|---|
| Anchoring | Always from the root. `Personal/Tech` is a notebook titled `Tech` whose parent is a root notebook titled `Personal`. It does not match a `Personal/Tech` nested deeper. |
| Matching | Segment titles compare case-insensitively (`OrdinalIgnoreCase`). |
| Escaping | `\/` is a literal slash inside a title; `\\` is a literal backslash. In JSON this is written `"Q3\\/Q4 Plans"`. Any other backslash sequence is a `ConfigError`. |
| Empty segments | `A//B`, a leading `/` and a trailing `/` are a `ConfigError`. |
| Combined features | Paths work with `descendants`, with `none`, and with deny-wins exactly like names and ids. |
| Moves and renames | If a segment is renamed or the notebook moved, the path stops matching and the grant stops applying (fail closed), with an unresolved-entry warning. Ids keep working. |
| Printed paths | Any output that prints a path escapes `/` and `\` in titles, so printed paths are unambiguous and can be pasted back into a config. |

Whether Joplin actually permits `/` or `\` in a notebook title is unverified; the design works either way. See [slash-in-notebook-titles.md](../research/slash-in-notebook-titles.md).

### Ambiguity

Titles are not unique, and a path can still be ambiguous if two siblings share a title.

- **Grants (`read` / `write`) refuse ambiguity.** A name or path that matches more than one notebook grants **nothing** for that entry.
- **Denies (`none`) apply to every match**, and log a stderr warning (over-denying is the safe direction; the user probably did not intend it).
- **Failure is scoped to the entry.** An ambiguous or unresolved grant is skipped and reported; every other entry still resolves. Tool calls that touch the affected notebook are refused with an explanatory error rather than the whole server failing to start.
- **Errors are actionable.** The error names the entry and the match count, and lists each match's id and path, e.g.:
  `Config entry "Archive" matches 2 notebooks; no access granted. Use an id or a path: 3f2a…c1 (Work/Archive), 9b7d…44 (Personal/Archive).`
- **Unresolved entries warn.** A grant or deny entry that matches no notebook is logged to stderr, so renamed or moved notebooks are visible instead of silently losing access.

**Implementation.** `Resolve-NotebookAccess` builds, once per call: `idSet`, `titleIndex` (title -> ids) and `children` (parent_id -> ids). Path resolution walks `children` from the roots segment by segment. Path syntax is parsed and validated in `Import-JoplinConfig` so syntax errors surface at load time; matching happens in `Resolve-NotebookAccess` because it needs the live tree. The resolution result carries a list of diagnostics (ambiguous and unresolved entries) that is written to stderr and also used to build the per-call error above.

## Information hiding

Decided in [ADR 5](../adr/0005-hidden-indistinguishable-from-missing.md).

1. **Hidden and nonexistent are indistinguishable.** For every tool that filters or looks up by id, the caller-visible response for "exists but hidden" is identical to "does not exist". Counts, pagination hints and error text must not vary with hidden content.
2. **Uniform scope statement on empty results.** Whenever a search, tag lookup or listing returns nothing, append the same sentence regardless of why:
   > No notes found matching 'X' in the notebooks you can access.
   - Always appended on empty results, whether the cause was no match, a hidden match, or an empty vault.
   - Worded as the *scope* of the search, not a *cause* (not "with your current access").
   - Never appended to non-empty results.
3. **Static scope statement in tool descriptions**, e.g. "Searches only notebooks the server has been granted access to." Static text carries no per-query signal and tells the LLM its view is limited, so it does not assume absence means the note is not in the vault (for instance, creating a duplicate).
4. **Pagination reflects filtered results.** `has_more` and "more results exist" are computed from what the caller can see. Fetch pages until the output page is full or results run out, with a **bounded page cap**. When the cap is hit, return what was found with the standard "more results exist" note (same text regardless of cause).
5. **Direct access by id.** `get_note`, `update_note`, `update_note_section`, `append_note_section`, `delete_note` and `complete_todo` on a note in a denied or unreadable notebook return **the same error as a note that does not exist**.
   - Exception: a note the caller **can read but not write** is refused with a write-access error, because the caller already knows it exists.
6. **Diagnostics go to stderr only.** stderr records which notebook ids caused results to be filtered and why (denied / not granted / unresolved entry), with counts. The LLM never sees it.

| Tool | Behavior |
|---|---|
| `search_notes` | Post-filtered; uniform empty-result text; filtered pagination. |
| `get_notes_by_tag` | Same as search. |
| `list_notes_in_notebook` | A denied or unreadable notebook returns the same result as a notebook that does not exist. |
| `list_notebooks` | Hidden notebooks are omitted; no count of omitted entries. |
| `get_note` and write tools | Same not-found error for hidden and missing notes. |
| `list_tags` | Unchanged ([known tag-name leak](#known-accepted-leak-tag-names)). |

**Implementation.** The policy lives in two helpers so handlers never filter or count on their own:

- `Select-ReadableNotes` takes the raw page stream, the access object and a target size, pages through Joplin's results up to the cap, and returns the visible items plus whether more exist.
- `Get-AccessibleNote` fetches a note and returns it only if `CanRead` / `CanWrite` allows on its `parent_id`, throwing the same not-found error otherwise. Write handlers call it instead of fetching directly.

## Intentional differences from the Python server

The PowerShell server is stricter in each case:

- `list_notebooks` returns only readable notebooks (the Python server lists all, by design: notebook names are treated as metadata, not note content).
- Ambiguous grant names grant nothing (the Python server grants every match).
- Empty and hidden results are uniform, with no "N notes but none readable" message (the Python server reveals the count).
- Hidden notes and missing notes produce the same error on direct access.
- `access: "none"`, `descendants`, paths and `$tags` are new. A config using `none` will not load in the current Python server (by design: failing loudly beats silently granting more). Porting these to the Python server is proposed in johnsarie27/joplin-mcp#68.
