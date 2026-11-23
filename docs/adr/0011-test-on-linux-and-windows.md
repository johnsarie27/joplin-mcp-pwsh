# ADR 11: Test on Linux and Windows, Not macOS

Amends: ADR-0010

## Status

Accepted — 2026-11-23

## Context

- [ADR 10](0010-adopt-pwsh-module-ci.md) adopted the `pwsh-module-ci` harness, whose default runner matrix is Linux, macOS and Windows, and planned to test on all three.
- The first CI run of the scaffold (#12) passed on all three, executing 178 tests on each.
- The harness takes the runner list as an input (`os-matrix`), so the matrix can be narrowed in this repository's `ci` caller without touching the harness.

## Decision

- We will run the `ci` workflow on `ubuntu-latest` and `windows-latest` only, by setting `os-matrix` in `.github/workflows/ci.yml`.
- We will set the `min-tests` floor from the executed count on those legs, as the harness documents: `executed - min(floor(executed * 0.05), 10)`. With 178 executed that is 170.
- Why: the maintainer's decision (2026-11-23). No technical reason is recorded.
- The server stays a cross-platform PowerShell module; this changes what CI exercises, not what the code supports.

## Consequences

- macOS-specific behavior is no longer exercised by CI: Console and process handling, file permissions, and the PowerShell build the macOS runner installs (7.6.9 when checked on 2026-11-15). Linux remains the Unix leg, which covers most of it.
- The required checks in the `protect` ruleset are `validate / validate (ubuntu-latest)`, `validate / validate (windows-latest)` and `validate / normalize matrix`; there is no macOS check to require.
- Adding macOS back is one line in the `ci` caller, and the floor needs no change if the suite is the same.
