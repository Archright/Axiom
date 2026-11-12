## Summary

Request a **symbolic partial evaluation** mode for NimVM / `static:` blocks that can fold expressions containing **symbolic/runtime parameters** into a canonical form for comparison, without requiring their concrete compile-time values.

## Motivation

Static analysis tools (e.g., DRY duplicate detectors) need to determine whether two expressions are semantically equivalent even when they differ syntactically:

```nim
proc foo(a: int): int = a * 2
proc bar(a: int): int = a + a
```

These are semantically equivalent, but their ASTs are completely different (`nkInfix(*, a, 2)` vs `nkInfix(+, a, a)`). Current NimVM cannot evaluate `a * 2` at compile time because `a` is a runtime parameter.

## Current Limitation

Per the Nim manual:

> "A constant in Nim is a symbol bound to the value of a constant expression."
> "The `static` statement forces compile-time execution ... It is a static error if the compiler cannot execute the block at compile time."

NimVM correctly rejects:

```nim
proc foo(a: int) =
  static:
    echo a * 2   # Error: cannot evaluate at compile time
```

## Proposed Solution

A new compiler directive or macro API that enables **symbolic evaluation**:

```nim
import std/macros

macro areEquivalent(e1, e2: untyped): static[bool] =
  ## Returns true if e1 and e2 are semantically equivalent under symbolic evaluation.
  ## Does NOT require concrete values for parameters.
  result = newLit(symbolicPartialEval(e1) == symbolicPartialEval(e2))
```

Under symbolic evaluation:
- Variables (parameters) are treated as opaque symbols.
- Arithmetic operators are reduced using algebraic rules (`a * 2` → `a + a`, commutativity, associativity).
- The result is a canonical AST form that can be compared structurally.

## Use Cases

1. **DRY detection in architecture gates**: Detect duplicate logic across modules even when written differently.
2. **Refactoring safety**: Verify that two implementations are equivalent before replacing one with the other.
3. **Test oracle generation**: Derive expected outputs for symbolic inputs.

## Scope Clarification

This is **not** a request for general runtime evaluation at compile time. It is specifically a **macro/static-analysis** feature that operates on ASTs with symbolic variables, producing a canonical form. It would likely live in `macros.nim` or a new `std/symeval` module.

## Related Issues

- #4516 (inline iterator parameter passing) — unrelated to symbolic evaluation.
- #6785 (NimNode to typedesc conversion) — unrelated to symbolic evaluation.

Neither existing issue covers this request.
