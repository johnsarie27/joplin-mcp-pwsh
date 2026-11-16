# ADR 2: Explicit Deny That Always Wins

## Status

Accepted — 2026-11-15

## Context

- With additive grants and optional inheritance ([ADR 1](0001-opt-in-descendant-inheritance.md)), access can only be widened. There is no way to say "everything except Personal".
- A deny that did not cover its children would be a trap: denying `Personal` while `Personal/Taxes` stays open is almost never what anyone means.
- The Python server validates `access` against `{read, write}` and raises a `ConfigError` for anything else. It ignores unknown top-level keys.
- AWS IAM is a widely understood model: an explicit deny overrides any allow, and absent any allow the result is an implicit deny.
- A most-specific-entry-wins model (ACL / CSS style) would allow carve-outs such as `Work: write`, `Work/Personal: none`, `Work/Personal/Shared: read`.

## Decision

- We will add deny entries to the existing `notebooks` list as `access: "none"`.
- `none` denies read and write on the named notebook and every notebook below it. Deny is always recursive, so `none` entries take no `descendants` flag (`ConfigError` if present).
- Deny always wins: if a notebook or any of its ancestors is denied, there is no access, regardless of any grant, including `*`, an explicit grant on the notebook itself, or an inherited grant.
- `none` on `*` is a `ConfigError` (use an empty list). `none` on `$root` is allowed and revokes root-level notebook creation even under `*` write.
- We will apply deny once, in `Resolve-NotebookAccess`, by subtracting the denied subtree from both grant sets; `CanRead` / `CanWrite` also check the denied set so `*` respects it.
- Why:
  - **Easy to audit.** To see what is blocked, read the `none` entries; nothing can override them.
  - **Hard to misconfigure.** Always-recursive deny removes the "denied parent, open child" trap.
  - **Consistent with ADR 1.** Grants union; deny is the only operation that subtracts.
  - **Fail-safe for the shared config.** A `none` entry makes the Python server fail loudly at load time instead of running with broader access than the author intended.
- Rejected: a separate top-level `deny: []` list. The Python server would silently ignore it and grant more than intended.
- Rejected: most-specific entry wins. The extra expressiveness serves a rare case; it would change ADR 1's union semantics (a child `read` could lower a parent's `write`); and it is a one-way door, since moving to it later would widen access on existing configs, whereas starting with deny-wins costs nothing if carve-outs are never needed.

## Consequences

- "Everything except X" is expressible, and the set of blocked notebooks is readable directly from the config.
- Carve-outs under a denied parent are not expressible. The workaround is to grant the specific sibling notebooks instead of the parent.
- A config that uses `none` cannot be shared with the current Python server until it gains equivalent support. This is the intended failure mode; porting is proposed in johnsarie27/joplin-mcp#68.
- Denied notebooks disappear from `list_notebooks`, search, tag and listing results, and reads, writes and creates in them are refused. Error text for a denied notebook must not reveal more than a nonexistent one, which [ADR 5](0005-hidden-indistinguishable-from-missing.md) settles.
- A `none` entry that matches nothing or several notebooks must warn on stderr so typos are visible; a config of only `none` entries fails closed.
