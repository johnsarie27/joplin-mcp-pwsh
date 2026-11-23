# ADR 11: Test on Linux and Windows, Not macOS

Amends: ADR-0010

## Status

Accepted — 2026-11-23

## Context

- [ADR 10](0010-adopt-pwsh-module-ci.md) adopted the `pwsh-module-ci` harness, whose default runner matrix is Linux, macOS and Windows, and planned to test on all three.
- The first CI run of the scaffold (#12) passed on all three, executing 178 tests on each.
- The harness takes the runner list as an input (`os-matrix`), so the matrix can be narrowed in this repository's `ci` caller without touching the harness.
- PowerShell on Linux and on macOS runs on .NET's Unix implementations of the console, standard streams, file paths and line endings; Windows differs in each. The module has no platform-specific branches (`$IsMacOS`, `$IsLinux` or `$IsWindows`; checked 2026-11-23).
- Every leg runs the full suite on every push and pull request, so each extra runner is spent again on every change.
- The maintainer develops on macOS.

## Decision

- We will run the `ci` workflow on `ubuntu-latest` and `windows-latest` only, by setting `os-matrix` in `.github/workflows/ci.yml`.
- We will set the `min-tests` floor from the executed count on those legs, as the harness documents: `executed - min(floor(executed * 0.05), 10)`. The current count and floor are in the `ci` caller's comment.
- We will test on macOS by running the suite locally from time to time, not in CI.
- Why: Linux already exercises the Unix code paths macOS would, so a macOS leg would mostly repeat the Linux result while adding a runner to every run. Dropping it serves the Well-Architected Sustainability pillar (less compute for the same coverage) and shortens the feedback loop.
- Rejected: macOS on a schedule or before a release. It would catch macOS-only drift without a per-push cost, but it adds a second CI path to maintain for a platform the maintainer already uses daily.
- The server stays a cross-platform PowerShell module; this changes what CI exercises, not what the code supports.

## Consequences

- macOS-specific behavior is no longer exercised by CI: Console and process handling, file permissions, and the PowerShell build the macOS runner installs (7.6.9 when checked on 2026-11-15). Linux remains the Unix leg, which covers most of it.
- The required checks in the `protect` ruleset are `validate / validate (ubuntu-latest)`, `validate / validate (windows-latest)` and `validate / normalize matrix`; there is no macOS check to require.
- Adding macOS back is one line in the `ci` caller, and the floor needs no change if the suite is the same.
- Reliability is traded for Sustainability: the platform the maintainer develops on is not checked by CI. macOS coverage depends on someone remembering to run the suite locally, and nothing records when it last ran.
- A local run uses whatever PowerShell is installed (7.7.0 on 2026-11-23), so the 7.6 floor ([ADR 8](0008-powershell-7-6-floor.md)) is not exercised on macOS by anything.
- Revisit this if the module gains a platform-specific branch, or a defect is found that only reproduces on macOS.
