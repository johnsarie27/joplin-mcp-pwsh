# ADR 3: `$root` and `$tags` Sentinels

## Status

Accepted — 2026-11-15

## Context

- Some operations are not scoped to any existing notebook, so `CanRead(notebookId)` / `CanWrite(notebookId)` has nothing to evaluate: creating a notebook at the root, and creating, renaming or deleting a tag. Tags are vault-wide, not notebook-scoped.
- The Python server already handles root-level notebook creation with a `$root` sentinel entry, which does not count as access to any notebook.
- Tag mutation is the open access-control question in johnsarie27/joplin-mcp#28, tied to the root-notebook question in johnsarie27/joplin-mcp#17.
- Attaching or detaching a tag changes one note, which already has a notebook to check.
- Deleting a tag removes it from every note it is attached to, including notes in notebooks the server cannot see or write. Renaming a tag changes its display name everywhere but no note content.
- `list_tags` in the Python server returns every tag, ungated.

## Decision

- We will carry `$root` over from the Python server unchanged: `{ "id": "$root", "access": "write" }` permits creating notebooks at the root, `*` write implies it, and it is not access to any notebook.
- We will add a parallel `$tags` sentinel. `$tags` + `write` allows `create_tag`, `rename_tag` and `delete_tag`; `*` write implies it; `$tags` + `none` revokes it even under `*` write ([ADR 2](0002-explicit-deny-wins.md)); `$tags` + `read` is a no-op, like `$root` + `read`; `descendants` on either sentinel is a `ConfigError`.
- Neither sentinel counts as notebook access: `HasAnyAccess()` ignores both, so a config of only sentinels still fails closed for note-content tools.
- We will keep `tag_note` / `untag_note` notebook-scoped (`CanWrite(note.parent_id)`, like `update_note`), with no `$tags` requirement.
- We will leave `list_tags` ungated and keep `get_notes_by_tag` post-filtered by readable notebooks.
- We will refuse `delete_tag` if the tag is attached to any note in a notebook the caller cannot write to (including denied notebooks), checked via `GET /tags/:id/notes` and `CanWrite(note.parent_id)` per note. The refusal reports a count only. `rename_tag` needs only `$tags` write.
- We will add a fourth registry `Access` value, `ManageTags`, gated in the dispatcher by `CanManageTags()`.
- Why sentinels: they keep every permission in the single `notebooks` list, so deny rules, validation and the shared parser apply to them for free.
- Rejected: requiring `write_all` for tag management. Too coarse; it makes tag management impossible for anyone who scopes writes to specific notebooks.
- Rejected: a dedicated knob such as `allow_tag_management`. It works, but adds a second place to look for permissions.
- Rejected: allowing tag CRUD given any write access. Too loose; one writable notebook would let the LLM rename or delete every tag in the vault.

## Consequences

- Tag management can be granted or revoked independently of notebook access, and the server gains `create_tag`, `rename_tag`, `delete_tag`, `tag_note` and `untag_note`.
- This settles, for this server, the access-control questions blocking johnsarie27/joplin-mcp#17 and johnsarie27/joplin-mcp#28.
- `delete_tag` costs extra API calls (paginated attached-notes check) and can be refused for reasons the caller cannot fully see; the refusal reveals a count of notes outside the writable notebooks.
- `rename_tag` can change how a tag appears on notes in notebooks the caller cannot see. Accepted because no note content changes.
- **Known, accepted leak:** `list_tags` returns tags used only in denied notebooks, so tag names can hint at hidden content. Closing it would mean filtering tags to those attached to at least one readable note, at extra API calls per tag. Left for parity with the Python server; revisit if it matters in practice.
- The registry-invariant test must cover four `Access` values instead of three.
