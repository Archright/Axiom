# docs/spec/axiom_dsl_quirks.md — Axiom Specification DSL Quirks

## §1. DSL Expression Subset

| Category | Allowed | Forbidden |
|----------|---------|-----------|
| Logic | and, or, not, implies, iff | xor, nand |
| Arithmetic | +, -, *, div, mod, <, <=, >, >=, ==, != | ^, sqrt, abs |
| Quantifiers | forall, exists (finite domains) | unbounded infinite domains |
| Pattern matching | case (object variant) | match (Nim-native) |
| Types | int, bool, enum, object, object variant | seq, ref, string, float, Table |

## §2. getTypeImpl Limitations

- `getTypeImpl` in macro context does NOT resolve generic instantiations
- Compile-time `registerDatatype(T)` requires concrete ADT types only
- Generic properties must be instantiated per concrete type

## §3. SMT-LIB2 Sort Mapping

| Nim Type | SMT-LIB2 Sort |
|----------|---------------|
| int | Int |
| bool | Bool |
| enum | (declare-datatypes ((Enum 0)) ((Val1 Val2 ...))) |
| object | (declare-datatypes ((Sort 0)) ((Cons (field1 Int) ...))) |
| object variant | Multiple constructors in declare-datatypes |

## §4. Z3 Deterministic Seeds

```
sat.random_seed=0
fp.spacer.random_seed=0
```

Ensures identical results across runs. Required for reproducible property verification.

## §5. Quantifier Handling

- `forall`/`exists` are transpiled to SMT-LIB2 `(forall ((x T)) body)`
- Finite domain enumeration needed for counterexample generation
- Z3 may return `unknown` for complex quantifier alternation

## §6. Known Edge Cases

- Division by zero: SMT-LIB2 `div` is Euclidean (no runtime crash)
- Integer overflow: SMT integers are arbitrary precision (no overflow)
- Empty quantifier domain: vacuously true
