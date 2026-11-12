# axiom_pragmas Facade Split Structure

This directory contains the split modules for `axiom_pragmas.nim`.

## Load Order (mandatory)

1. **types.nim** — Pure types and constants
2. **vm_helpers.nim** — Compile-time helpers for macros
3. **macros.nim** — Macro and template definitions
4. **[codeReordering enabled here]**
5. **procs.nim** — Runtime logic

## Rules

- No independent imports in sub-files (all imports in Facade root)
- No templates/macros in `procs.nim` (won't be found by codeReordering)
- Maximum depth: 50 include levels (enforced by `architecture_invariants.nim`)

## Why This Order?

`{.experimental: "codeReordering".}` only reorders `proc`/`func` declarations. Templates and macros must be defined before use, and compile-time helpers must be available to macros. The split order ensures:

1. Types are available to all subsequent includes
2. VM helpers are available to macros
3. Macros are fully defined before codeReordering activates
4. Procs can be freely reordered by the compiler

## Example

```nim
# src/core/trusted/axiom_pragmas.nim (Facade root)
import std/[strutils, sequtils, os, strformat, hashes]
import core/trusted/env_types

include core/trusted/axiom_pragmas/types
include core/trusted/axiom_pragmas/vm_helpers
include core/trusted/axiom_pragmas/macros

{.experimental: "codeReordering".}

include core/trusted/axiom_pragmas/procs
```
