# Certified Refactoring Patterns

CompCert-style pre-verified refactoring patterns for Axiom.

Each pattern's correctness is proved **once** in Lean 4, then **reused** for every application.
This eliminates the need for automatic bisimulation generation (which is an open research problem).

## Architecture

```
Layer 1: pattern_guard.nim     — AST structural precondition check (deterministic)
Layer 2: equivalence_checker.nim — Z3 semantic equivalence (post-application)
Layer 3: certified_patterns/    — Lean 4 proof of pattern correctness (pre-verified)
```

## Patterns

| Pattern | File | Precondition | Theorem |
|---------|------|-------------|---------|
| Extract Pure Function | `extract_pure_function.lean` | No side effects, no I/O | `extract_pure_preserves_semantics` |
| Add Loop Invariant | `add_loop_invariant.lean` | Loop exists, no existing invariant | `add_loop_invariant_preserves_result` |
| Linearize Variables | `linearize_variables.lean` | Non-linear arithmetic | `linearize_preserves_equivalence` |
| Insert Composition Node | `insert_composition.lean` | Call chain depth ≥ 3 | `composition_preserves_behavior` |
| Isolate Interface | `isolate_interface.lean` | I/O boundary exists | `isolation_preserves_contract` |
| Add Decrease Measure | `add_decrease_measure.lean` | Recursion exists | `measure_preserves_termination` |

## Verification

Each `.lean` file should compile with:
```bash
lean certified_patterns/extract_pure_function.lean
```

The anti-vacuity check (negative test) should FAIL to compile, proving the proof is non-trivial.

## References

- Leroy, X. (2008). "Formal verification of a realistic compiler." CACM.
- CompCert forward simulation: `forward_simulation_plus` pattern.
