# ADR 10: Build and Test with `pwsh-module-ci`

## Status

Accepted — 2026-11-15

## Context

- The test plan ([testing.md](../design/testing.md)) needs PSScriptAnalyzer, Pester on Linux, macOS and Windows, and GitHub Actions pinned by commit SHA.
- `jjohns-dev/pwsh-module-ci` is the maintainer's shared harness for PowerShell modules, used by eight other repositories (per its README). Its `v2` reusable workflows run staging, PSScriptAnalyzer, Pester and packaging from one harness, with the build tools pinned once (Pester 6.2.0, psake 5.0.4, PSScriptAnalyzer 1.25.0) and third-party Actions pinned by SHA in that repository.
- Its `ci` workflow verifies the JUnit result itself: the run fails if no result file is produced, if the root element reports errors, or if zero tests ran, and an optional `min-tests` floor catches a shrinking suite. These are the silent-green failures this project's tests are meant to prevent.
- It also runs shared tests on every consumer: manifest checks (including `PowerShellVersion` no higher than the PowerShell running the tests), no BOM, tab or NUL byte in source files, and no hard-coded path separators.
- `pssa-sarif` uploads analyzer findings to the repository's Security tab, and `release` builds the module archive and, on a pull request, runs the whole release path except publishing.
- The harness requires a module shape ([ADR 9](0009-module-with-exported-entry-point.md)): one manifest and root module at the repository root, a non-empty `Public/`, and tests at `Tests/<folder>/*.tests.ps1`.
- Its runner matrix varies the operating system only and uses each runner's installed PowerShell. The GitHub runner images' READMEs (checked 2026-11-15) list PowerShell 7.6.10 on Ubuntu 24.04 and Windows 2025, and 7.6.9 on macOS 15 arm64, matching the floor in [ADR 8](0008-powershell-7-6-floor.md).
- Consumers call it by its moving major tag (`@v2`) by design: its ADR 3 keeps immutable `vX.Y.Z` tags for staged rollouts and a moving major tag so consumers receive centralized Action updates. This repository's convention is to pin Actions by commit SHA.
- [ADR 7](0007-thin-core-no-framework.md) avoids frameworks the server depends on at runtime. The harness is build-time only and is maintained by the same person.

## Decision

- We will build and test the module with `jjohns-dev/pwsh-module-ci` `v2`, calling its `ci`, `pssa-sarif` and `release` (dry run on pull requests) reusable workflows from thin caller workflows in this repository, with the `Build/build.ps1` shim from its template for local runs.
- We will pin the harness by its moving major tag `@v2`, as an explicit exception to this repository's SHA-pinning rule. Third-party Actions in this repository's own workflows stay SHA-pinned.
- We will use the harness's pinned Pester (6.2.0) rather than choose a version here, and follow its layout: `Tests/<folder>/*.tests.ps1`, lowercase file names.
- We will set a `min-tests` floor once the suite exists, and add the harness's checks to the `protect` ruleset's required checks after their first run, when their names exist.
- We will keep this repository's `docs` workflow; the harness does not check documentation.
- Why: the harness already provides everything the test plan asks of CI, plus result verification and shared tests this project would otherwise write itself, and keeps this repository consistent with the maintainer's other modules.
- Rejected: hand-written workflows in this repository. More to write and maintain, and they would drift from the other modules.
- Rejected: pinning the harness by SHA. The repository would stop receiving the centralized Action bumps the harness exists to deliver, and the harness is maintained by the same person, so the supply-chain risk a SHA pin guards against is small.

## Consequences

- CI gains result verification, a test-count floor, shared manifest and encoding tests, Security-tab analyzer findings and a release dry run on every PR, with no workflow logic in this repository.
- The harness's conventions apply here and can change without a PR in this repository: a new `v2` release reaches this repository on its next run. Breaking changes require a new major tag, per the harness's own ADRs.
- No CI run pins PowerShell to the floor version. Mitigated: the shared manifest test fails on any runner older than the manifest's `PowerShellVersion` (7.6).
- The manifest must meet the shared tests: `Description`, `Author`, `Copyright`, `ProjectUri`, and `FunctionsToExport` equal to the `Public/` file names, with no wildcards.
- The SHA-pinning rule in AGENTS.md gains a documented exception.
- This repository should be added to the harness's list of consumers, a change in `jjohns-dev/pwsh-module-ci`.
- The required checks in the `protect` ruleset change when the harness is adopted; until then only `docs` is required.
