# ADR 5: Hidden Content Is Indistinguishable from Missing Content

## Status

Accepted — 2026-11-15

## Context

- The Python server answers a search whose matches are all in unreadable notebooks with "Found 3 note(s) matching 'X', but none are in a notebook you have read access to." That confirms three hidden notes match the query.
- The intent of denying a notebook ([ADR 2](0002-explicit-deny-wins.md)) is that the LLM has no information about it. An LLM that gets a different answer for "hidden" than for "absent" can map a denied notebook one query at a time.
- `has_more` is computed from Joplin's raw, unfiltered page, so "more results exist" can also reveal hidden matches.
- The Python message is useful to a person debugging a misconfigured access list.
- An LLM that sees an empty result may assume a note does not exist in the vault and act on it, for instance by creating a duplicate.
- Note ids are 32 random hex characters, so guessing them is impractical.

## Decision

- We will make "exists but hidden" and "does not exist" produce identical caller-visible responses in every tool that filters or looks up by id: counts, pagination hints and error text must not vary with hidden content.
- We will append the same scope sentence to every empty search, tag lookup or listing result, whatever the cause: "No notes found matching 'X' in the notebooks you can access." It is worded as scope, not cause, and never appended to non-empty results.
- We will put a static scope statement in the descriptions of filtering tools, e.g. "Searches only notebooks the server has been granted access to."
- We will compute pagination from filtered results: fetch pages until the output page is full or results run out, up to a bounded page cap, and use the standard "more results exist" text when the cap is hit.
- We will return the not-found error for direct access by id (`get_note` and the write tools) on a note in a denied or unreadable notebook. Exception: a note the caller can read but not write gets a write-access error, because the caller already knows it exists.
- We will send diagnostics (which notebook ids caused filtering and why, with counts) to stderr only.
- We will centralise the policy in `Select-ReadableNotes` and `Get-AccessibleNote` so handlers never filter or count on their own.
- Why: denying a notebook only hides it if no response varies with its contents, and identical errors cost nothing. Static scope text carries no per-query signal but still tells the LLM its view is limited.

## Consequences

- A denied notebook cannot be probed through searches, counts, pagination or error text.
- Harder to debug from the client side: a user who has misconfigured access sees an ordinary empty result. Mitigated by the stderr diagnostics and the unresolved-entry warnings from ADRs 2 and 4.
- `list_notebooks` must be filtered, unlike the Python server, which lists every notebook by design. Every writable notebook still appears, so ids needed for `create_note` and `create_notebook` stay discoverable.
- Extra API calls when many matches are hidden, bounded by the page cap.
- Behavior differs from the Python server's messages. Intentional; porting is proposed in johnsarie27/joplin-mcp#68.
- `list_tags` is out of scope and keeps its known tag-name leak ([ADR 3](0003-root-and-tags-sentinels.md)).
- A Pester invariant must hold: for a fixed query, responses with hidden matches present and absent are byte-identical.
