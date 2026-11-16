# Verification: `/` and `\` in notebook titles

**Status:** open. Needs a live Joplin instance; not yet run.

## Why

[ADR 4](../adr/0004-name-resolution-and-paths.md) adds `/`-separated paths with `\/` and `\\` escapes. Whether Joplin accepts `/` (or `\`) inside a notebook title is unverified: a web search turned up nothing Joplin-specific, and the only adjacent evidence suggests titles accept separator characters. The design works either way, but the answer decides whether the escape syntax is ever needed, and the resolver tests should reflect the real behavior.

## Procedure

Use a **throwaway profile or a scratch vault**, never a real one. Do not print the token or any URL containing it; print only titles, ids and status codes.

1. **Literal slash.** `POST /folders` with `{"title": "A/B"}`. Record the HTTP status. If it succeeds, `GET /folders/:id?fields=id,title,parent_id` and compare the stored `title` with `A/B`.
2. **Nested vs. literal.** Create root notebook `A`, then a child `B` with `parent_id` = A's id. `GET /folders` and confirm the tree shows `A` -> `B` as two notebooks, distinct from the literal `A/B` from step 1. This is the case the path resolver must tell apart.
3. **Literal backslash.** `POST /folders` with `{"title": "A\\B"}` (the JSON string `A\B`); read it back as in step 1.
4. **Escape round-trip.** With the fixtures above, run the resolver (once it exists) on `A/B` (expect the nested pair), `A\\/B` (expect the literal-slash notebook) and `A\\\\B` (expect the literal-backslash notebook), and confirm each resolves to exactly one notebook.
5. **Sync/UI sanity (optional).** Confirm the desktop app displays the literal-slash notebook normally and that it survives a sync round-trip.
6. **Clean up.** Delete every notebook created.

## Outcomes to record

| Observation | Meaning for the design |
|---|---|
| Title stored as typed (`A/B`) | Escape syntax is needed and the resolver must distinguish step 1 from step 2. Keep as specified. |
| Request rejected (status + message recorded) | Slashes cannot occur in titles; keep the escape syntax for forward-compatibility, but it is dead code today. |
| Title altered (e.g. slash replaced or stripped) | Record the exact transformation. Config titles are compared against stored titles, so the resolver must match what is actually stored. |
| Backslash handled differently from slash | Record separately; the `\\` escape rule may need adjusting. |

## Result

_Not yet recorded._ Add the observed behavior, Joplin version and platform here, then turn the outcomes into Pester fixtures for the resolver ([testing.md](../design/testing.md#names-and-paths-adr-4)).
