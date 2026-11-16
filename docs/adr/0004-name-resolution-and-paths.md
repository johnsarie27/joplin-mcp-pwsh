# ADR 4: Ambiguous Name Resolution and Notebook Paths

Amends: ADR-0001

## Status

Accepted — 2026-11-15

## Context

- Joplin notebook titles are not unique; nested notebooks can share a title.
- The Python server resolves a config name to every notebook with that title (case-insensitive) and grants the access level to all of them.
- With `descendants` ([ADR 1](0001-opt-in-descendant-inheritance.md)), an ambiguous grant could expand into several whole subtrees, and a notebook created later with a matching title would silently widen access.
- Over-denying is the safe direction for a deny entry ([ADR 2](0002-explicit-deny-wins.md)).
- Notebook ids are 32-char hex strings, unique, and stable across renames and moves, but opaque to a person reading the config.
- Resolution already builds a `parent_id -> children` map for `descendants`, so walking a path costs no extra API calls.
- Whether Joplin permits `/` inside a notebook title is unverified ([procedure](../research/slash-in-notebook-titles.md)).
- The Python server treats a value such as `Personal/Tech` as a title, which matches nothing.

## Decision

- We will make grants (`read` / `write`) refuse ambiguity: a name or path that matches more than one notebook grants nothing for that entry. Ids always work.
- We will keep grant-all for denies (`none`): an entry matching several notebooks denies all of them and logs a stderr warning.
- We will scope failure to the single entry: an ambiguous or unresolved grant is skipped and reported, every other entry still resolves, and tool calls touching the affected notebook get an explanatory error rather than the server failing to start.
- We will make errors actionable: name the entry and the match count, and list each match's id and path.
- We will warn on stderr for every grant or deny entry that matches no notebook.
- We will support root-anchored, `/`-separated paths in `id` (`Personal/Tech`), with case-insensitive segment matching, `\/` and `\\` escapes (any other backslash sequence is a `ConfigError`), and empty segments rejected. Resolution order is exact id, then path (unescaped `/` present), then plain title.
- We will print paths with `/` and `\` escaped, so printed paths are unambiguous and can be pasted back into a config.
- We will parse path syntax at config load and match it in `Resolve-NotebookAccess` against the live tree.
- Why refuse ambiguous grants: fail closed is the safe direction for a grant, and it stops a later notebook with a matching title from widening access.
- Why paths: a path pins a grant to a location (`Tech` could later match a second notebook; `Personal/Tech` cannot); moves and renames make a path stop matching, which only narrows access; and the Python server grants nothing for a path, so it stays stricter for the same file.

## Consequences

- Ambiguous names no longer silently grant several notebooks or subtrees. This replaces ADR 1's statement that `descendants` applies to every match of an ambiguous name.
- A config that worked with the Python server can grant less here, when it relies on an ambiguous title. The user sees an error naming the matches and must switch to an id or path.
- Path entries break on rename or move (fail closed with a warning) where id entries keep working. This is a genuine trade-off, made visible by the unresolved-entry warning.
- Ambiguity is still possible per segment (two siblings with the same title), handled by the same grant and deny rules; paths make it much rarer.
- The config gains an escape syntax that may turn out to be dead code if Joplin rejects `/` in titles; the live check decides.
- The resolver carries a diagnostics list that feeds both stderr and per-call errors, adding code and tests.
- Porting paths and the ambiguity rules to the Python server is proposed in johnsarie27/joplin-mcp#68.
