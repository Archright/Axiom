# TCB Formal Verification Roadmap

**Created**: 2026-06-20
**Status**: Phase 0 Complete (TCB defined, cast(noSideEffect) audit active)
**Policy**: AGENTS.md §0.5b Quirk Documentation Mandate

## Problem Statement

`{.cast(noSideEffect).}` is an escape hatch that bypasses Nim's effect system. While necessary for wrapping impure stdlib functions, it creates a **Trusted Computing Base (TCB)** — code that must be manually verified to be actually pure.

Current state:
- `src/core/pure/json_parse.nim` — `pureParseJson` uses `{.cast(noSideEffect).}` (the `pure_stdlib.nim`/`pure_path.nim` split originally described in this roadmap no longer exists — the TCB directory was restructured; it now contains `json_parse.nim`, `hermetic_effects.nim`, and `README.md`)
- Pre-existing casts in `src/core/gate/`, `src/core/bmc/`, etc. — 18+ locations

## TCB Invariant

All functions in `src/core/pure/` MUST be:
1. `func` (not `proc`)
2. `{.raises: [].}` (no exceptions)
3. Documented with WHY the cast is safe

## Formal Verification Strategy

### Phase 0: Manual Audit (COMPLETE)
- [x] `tcb_cast_audit.nim` — detects unauthorized `{.cast(noSideEffect).}` usage
- [x] Only `src/core/pure/` may contain the cast pragma
- [x] README.md documents TCB policy

### Phase 1: Z3 SMT Verification (Planned Q4 2026)

For each cast-wrapped function, generate a Z3 proof obligation:

```
; parseJsonPure verification
(declare-const content String)
(assert (= (parseJsonPure content) (parseJson content)))
(assert (not (hasSideEffect parseJsonPure)))
; Prove: parseJson on String input does not perform I/O
```

Z3 can verify:
- No filesystem access (no `open`, `read`, `write` calls)
- No network access (no `socket`, `connect` calls)
- No process creation (no `exec`, `fork` calls)
- No mutable global state modification

**Implementation**: `tools/verify/z3_purity_checker.nim` **[PLANNED — does not yet exist; proposed location for the Phase 1 Z3 purity checker]**
- Generates Z3 SMT-LIB2 from Nim AST
- Calls Z3 solver to verify purity
- Reports counterexamples if impurity detected

### Phase 2: Lean 4 Proof (Planned Q1 2027)

For critical TCB functions, create Lean 4 proofs:

```lean
-- pure_stdlib.lean
theorem parseJsonPure_is_pure (content : String) :
  ¬ (hasIOEffect (parseJsonPure content)) := by
  simp [parseJsonPure]
  -- parseJson uses StringStream internally
  -- StringStream is in-memory, no I/O
  constructor
  · intro h; contradiction
```

Lean provides:
- **Machine-checkable proofs** — no manual audit needed
- **Composition proofs** — if f and g are pure, f ∘ g is pure
- **Refinement types** — `sanitizeFilename` returns valid filename

**Integration**: Lean proofs stored in `proofs/pure/`, verified in CI.

### Phase 3: Automated Proof Generation (Planned Q2 2027)

Use LLM-based proof generation:
1. Parse Nim function AST
2. Generate Lean proof sketch
3. Lean kernel verifies proof
4. If proof fails, flag for manual review

**Risk**: LLM-generated proofs may be incorrect. Always require Lean kernel verification.

## Cast Audit Coverage

### Current Coverage
```
tools/nimtry/tcb_cast_audit.nim
  Scans: src/**/*.nim
  Pattern: {.cast(noSideEffect).} or cast(noSideEffect)
  Allowed: src/core/pure/**
  Mode: ERROR on violation
```

### Future: Effect Inference
Nim 2.x has improved effect inference. As the compiler evolves:
- Some casts may become unnecessary (compiler proves purity)
- `tcb_cast_audit` should be updated to remove obsolete casts
- Track Nim compiler changelog for effect system improvements

## Pre-Existing Cast Inventory

The following locations have `{.cast(noSideEffect).}` from before the TCB policy:

| Location | Function | Reason for Cast | Risk Level |
|----------|----------|-----------------|------------|
| `src/core/gate/` | Various | Effect system false positives | Medium |
| `src/core/bmc/` | Various | Bounded model checking | Medium |
| `src/core/boundary/` | Various | Layer guard functions | Low |
| `src/core/topology/` | Various | Graph traversal | Low |
| `src/core/codec/` | Various | Encoding/decoding | Low |

**Action**: These should be migrated to `src/core/pure/` or have their casts removed as the compiler improves. Priority: Medium (not blocking, but audit-worthy).

## References

- [Z3 SMT Solver](https://github.com/Z3Prover/z3)
- [Lean 4 Theorem Prover](https://leanprover.github.io/)
- Nim effect system: `docs/spec/nim_effect_system_quirks.md`
- TCB policy: `src/core/pure/README.md`
