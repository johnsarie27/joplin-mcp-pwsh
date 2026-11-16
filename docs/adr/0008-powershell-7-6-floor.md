# ADR 8: PowerShell 7.6 as the Minimum Version

Amends: ADR-0007

## Status

Accepted — 2026-11-15

## Context

- The design targeted PowerShell 7.4+ from the start, and [ADR 7](0007-thin-core-no-framework.md) cites that floor as one reason not to fork pwsh.mcp, which requires 7.5.
- Per Microsoft's [PowerShell support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle) (page updated 2026-09-09), PowerShell 7.4 (LTS, .NET 8) and 7.5 (Stable, .NET 9) both reached end of support on 10-Nov-2026. After end of support, no further updates are provided, including security updates.
- PowerShell 7.6 is the current LTS release (.NET 10), released 18-Mar-2026, with end of support on 14-Nov-2028. 7.7 is in preview.
- This server guards access to a personal notes vault, so the runtime it runs on should still receive security fixes.
- No implementation exists yet, so changing the floor costs only documentation edits.
- The planned CI harness (`jjohns-dev/pwsh-module-ci`) varies runners by operating system only and runs each runner's installed PowerShell; it has no input to select a PowerShell version. Which version GitHub's hosted runners currently install has not been checked.

## Decision

- We will require PowerShell 7.6 or later, and declare `PowerShellVersion = '7.6'` in the module manifest once it exists.
- We will move the floor to the next LTS release when 7.6 approaches its end of support, recording the change in a new ADR.
- We will test on the runners' installed PowerShell rather than adding a separate job pinned to the floor version, provided the installed version is at least 7.6. This is to be verified when the CI harness is adopted.
- Why: the floor should be a supported LTS release; 7.4 no longer is. Choosing the current LTS gives a supported runtime until November 2028, and keeps the floor close to what CI runners install, so testing the installed version largely tests the floor.

## Consequences

- The server never targets a runtime without security updates, at launch or for the next two years.
- Users on PowerShell 7.4 or 7.5 must upgrade to run the server. Both are out of support, so this affects only installations that are already unpatched.
- PowerShell 7.6 features are available, for example the array form of `Join-Path -ChildPath`.
- If GitHub's runners install a version newer than 7.6, CI no longer exercises the exact floor; a 7.6-specific regression could ship unnoticed. Accepted while the floor is the current LTS; revisit if the runners move to a version past 7.6 that changes behavior this server relies on.
- ADR 7's statements that the 7.4 floor is kept, and that pwsh.mcp's 7.5 requirement sits above our floor, no longer hold. ADR 7's decision stands on its remaining reasons: no per-tool access gate, stdout leaks and loose argument validation in all three frameworks.
- The floor becomes a recurring decision tied to the PowerShell LTS cadence.
