# ADR 13: Tests Grouped by the Property They Protect

## Status

Accepted — 2026-11-23

## Context

- The maintainer's other modules (PS.YNAB, SecurityTools) and the house PowerShell standard put tests in `Tests/Unit/`, one file per function, and test exported behaviour rather than private helpers.
- This module exports one function, `Start-JoplinMcpServer` ([ADR 9](0009-module-with-exported-entry-point.md)). Every other function is private.
- The properties that matter most span several functions: nothing but protocol messages on stdout, every registered tool obeying the registration rules, the JSON-RPC error table, and hidden content looking like missing content ([ADR 5](0005-hidden-indistinguishable-from-missing.md)). [testing.md](../design/testing.md) plans its suites by these properties.
- Some properties can only be observed in a real `pwsh` process, such as what reaches stdout; others are fastest to test in-process against private functions.
- The `pwsh-module-ci` harness ([ADR 10](0010-adopt-pwsh-module-ci.md)) discovers tests one folder below `Tests/`; it ran the `Registry`, `Protocol` and `Public` folders unchanged on 2026-11-23, so the layout is this repository's choice, not the harness's.
- The first test plan mixed both: area folders, plus `Tests/Private/<function>.tests.ps1` for each private function.

## Decision

- We will put tests in area folders named for the property they protect, `Tests/<area>/*.tests.ps1`: today `Registry`, `Protocol` and `Public`, and `Access` when the access layer is built.
- We will test private functions directly, through `InModuleScope`, wherever that is the clearest way to pin a property.
- Only the public entry point gets a file of its own, in `Tests/Public/`.
- Why: a property is the unit a reviewer checks against the design, so one folder per property maps each rule in testing.md to the tests that enforce it. With a single export, testing only exported behaviour would leave every property to end-to-end tests.
- Rejected: `Tests/Unit/<function>.tests.ps1`, as in the other modules. One property would be spread across several files, and a test that needs a real process belongs to no single function.
- Rejected: area folders plus one file per private function, as first planned. Each private function would have two homes for its tests, and nothing would say which one a new test goes in.

## Consequences

- Each property in testing.md has one obvious place for its tests, and a reviewer can check the suite against the design folder by folder.
- The layout differs from the maintainer's other modules and from the house standard, so agents and contributors who follow the standard will reach for `Tests/Unit/`. AGENTS.md points them here.
- Tests that call private functions depend on their names and parameters, so renaming or reshaping a private function means editing its tests, which a test of exported behaviour alone would not need.
- A new property needs a decision about its folder. Adding a folder is cheap, but the list in testing.md must be kept current.
