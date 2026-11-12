## Summary

Nim Concepts currently enforce **type-level** constraints (e.g., "`T` must support `+`"). There is no language-level mechanism to restrict **which modules or call-sites** may invoke a given procedure.

## Motivation

In large codebases with strict architectural layering (e.g., domain / infrastructure / presentation separation), certain low-level procs must only be callable from specific layers. Examples:

- `z3ExecPersistent` should only be called from `src/core/`.
- `runLeanCompiler` should only be called from `src/verification/`.

Currently, this enforcement must be done via external static analysis tools that parse ASTs. A native language mechanism would be more robust and zero-cost.

## Proposed Solutions

### Option A: Extend Concepts to Call-Site Constraints

Allow Concepts to express requirements about the **caller context**, not just the type parameters:

```nim
type
  CoreLayerCaller = concept
    ## Magic: only satisfied when the caller's module path matches "src/core/*"
    proc callerPath: static[string]

proc z3ExecPersistent(...)
  where caller is CoreLayerCaller =
  ...
```

### Option B: New `{.caller: "pattern".}` Pragma

A simpler, more explicit pragma:

```nim
proc z3ExecPersistent(...)
  {.caller: "src/core/*".} =
  ...
```

The compiler would reject calls from modules whose paths do not match the glob pattern.

## Why Not External Tools?

We already maintain an AST-based architecture gate (using `compiler/ast` PNode extraction). It works, but:
- It is heuristic (macros that forward `untyped` arguments hide calls).
- It requires keeping the parser in sync with Nim compiler AST changes.
- It cannot see through template/macro expansion without full semantic analysis (`compiler/sem`), which is internal and fragile.

A language-native mechanism would be deterministic, zero-cost, and fundamental.

## Related

- `distinct` types prevent accidental value mixing but do not enforce call-site boundaries.
- Nim's effect system (`{.tags: [IOEffect].}`) tracks **what** a proc does, not **who** may call it.
