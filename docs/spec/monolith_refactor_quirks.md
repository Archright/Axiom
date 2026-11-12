# docs/spec/monolith_refactor_quirks.md — Monolith Refactor Quirks

## Q1: `{.noSideEffect.}` vs `func`

`func` is syntactic sugar for `{.noSideEffect.}`. Prefer `func` for brevity.
Use explicit `{.noSideEffect, raises: [].}` when additional pragmas are needed.

## Q2: `ref object` with `var` parameters

Extracted procs that take `var` parameters on `ref object` may trigger
"expression has no address" errors. Use explicit `var` annotation or
pass by value if the ref is not mutated.

## Q3: HashSet value copy semantics

`HashSet[T]` is a value type in Nim. Assignment copies the entire set.
Pass by `var` for mutation, by value for read-only.

## Q4: Effect system interaction with `{.push raises: [].}`

`{.push raises: [].}` at module level affects all procs. If an extracted
`func` calls a proc with `{.raises: [CatchableError].}`, the func will
fail to compile. Solution: use `{.push raises: [].}` only in pure sections.

## Q5: Malebolgia `spawn` with value types only

`spawn` in malebolgia requires value types. `ref object` parameters cause
undefined behavior. Use `distinct` wrappers or serialize to `seq[byte]`.

## Q6: Import encapsulation boundary

Extracted funcs must not import from I/O boundary modules. Use
forwarding stubs or interface modules to maintain the boundary.

## Q7: Dead code after `quit()`

`printDiagnosticMatrix` calls `quit()` which makes subsequent code dead.
The compiler may warn about this. Keep `quit()` at the very end.
