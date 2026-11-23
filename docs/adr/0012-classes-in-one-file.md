# ADR 12: All Classes in One File, Loaded First

## Status

Accepted — 2026-11-23

## Context

- The module has one file per function, the house PowerShell standard, and defines its types as PowerShell classes and enums: the tool access enum, the protocol and tool error types, and the access object.
- A function that names a class as a parameter type needs that class loaded before the function's file is dot-sourced.
- Across files, every type reference depends on load order. Within one file, a class may use a type declared later in the same file as a property or parameter type; only a base class must be declared above the classes that extend it (checked on PowerShell 7.7 while reviewing #12).
- PSScriptAnalyzer parses one file at a time and reports a base class declared in another file as `TypeNotFound`.
- The first scaffold kept one class per file in `Private/Classes/`, loaded in name order. A class could only use classes whose file name sorted before its own, and a derived error class had to share its base class's file.
- More classes are expected as the access layer and the Joplin client are built.

## Decision

- We will declare every class and enum in one file, `Private/Classes.ps1`, which the root module dot-sources by name before any other file.
- Within that file a base class is declared above the classes that extend it. No other ordering rule applies.
- A test fails if any other file under `Public/` or `Private/` declares a class or enum.
- Why: the only ordering rule left is the inheritance one, which the parser enforces at import with a clear error, and PSScriptAnalyzer sees every base class.
- Rejected: one file per class with an explicit load-order list in the root module. It works, but each new class means editing the list in the right place, and PSScriptAnalyzer still reports a base class in another file.
- Rejected: one file per class loaded in name order, as in the first scaffold. Whether the module loads depends on file names.

## Consequences

- Adding a class means editing one file, with no load order to maintain.
- The file grows with every type and is an exception to one function per file. If it becomes unwieldy, a later ADR can split it.
- The root module names the file explicitly, so renaming `Classes.ps1` means editing the root module and the layout test.
