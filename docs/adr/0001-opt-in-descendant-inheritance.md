# ADR 1: Opt-in Descendant Inheritance

## Status

Accepted — 2026-11-15

Amended by [ADR-0004](0004-name-resolution-and-paths.md) — 2026-11-15. One statement below is now inaccurate and is left in place:

- The Consequences bullet reading "If a name matches several notebooks, `descendants` applies to every match". ADR-0004 replaces it: a grant whose name or path matches several notebooks grants nothing, so `descendants` never expands an ambiguous name.

Everything else in this record still stands.

## Context

- The Python server's access model is flat: access to `Work` does not extend to `Work/Projects`.
- People think of notebooks as folders: "give it access to Work" usually means everything under Work.
- Under a flat model every sub-notebook has to be listed, and a newly created sub-notebook is silently inaccessible.
- The notebook tree is cheap to obtain: every folder carries a `parent_id`, and the server already fetches the folder list on every call to resolve ids and names. Expanding a subtree is an in-memory pass with no extra API calls.
- Inheritance creates a silent-widening risk: if a notebook is moved into a granted parent in the Joplin UI, the LLM gains access with no config change.
- One `config.json` is meant to work with both servers. The Python server ignores unknown keys.

## Decision

- We will support hierarchy inheritance as an explicit per-entry opt-in: `{ "id": "Work", "access": "write", "descendants": true }`.
- `descendants` defaults to `false`, which reproduces the Python server's flat behavior exactly. When `true`, the entry applies to the named notebook and every notebook below it.
- Grants combine by union; write implies read at every node. No precedence ordering is needed among grants.
- We will compute descendants from the live folder list on every call, inside `Resolve-NotebookAccess`, expanding each entry into concrete id sets. `CanRead` / `CanWrite` keep answering by notebook id, so no handler knows about inheritance.
- We will cap the tree walk and detect cycles; an orphan (unknown `parent_id`) is treated as a root and never inherits.
- Why inheritance at all: it matches how people think about folders, avoids enumerating every sub-notebook, and costs only an in-memory pass.
- Why opt-in rather than default:
  - **Silent widening.** With opt-in, a move into a granted parent widens access only where the user asked for that behavior on that specific entry.
  - **Shared-config safety.** The Python server ignores `descendants`, so for the same file it is stricter than this server, never looser. Inheritance by default would make one file grant broader access in one server than the other.

## Consequences

- Users can grant a whole subtree in one entry, and new sub-notebooks under it are covered automatically.
- A notebook moved into or out of a `descendants` grant gains or loses access on the next call, with no config change. This is intended, but it means access can change through the Joplin UI alone.
- Grants can only widen access; "all of Work except Personal" is still inexpressible. This motivated [ADR 2](0002-explicit-deny-wins.md).
- If a name matches several notebooks, `descendants` applies to every match, which raises the stakes of ambiguous names ([ADR 4](0004-name-resolution-and-paths.md)).
- The resolver gains a tree walk with cycle and orphan guards, which needs its own tests.
- Until the Python server supports `descendants`, the two servers grant different access for the same file (Python narrower). Porting is proposed in johnsarie27/joplin-mcp#68.
