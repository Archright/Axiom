# Phase 2 — Semantic Cases: Golden Test Specification

**Status:** DESIGN DELIVERABLE (READ-verified)
**Date:** 2026-08-13
**Scope:** Encoder repair for three known soundness defects. No source modification.

---

## §1. Defect A — `%%` unsigned modulo mis-encoded as signed

**Root cause:** `ast_to_ir.nim:174` maps `%`/`mod` → `boRem`. `axiom_ir_helpers.nim:209,236` maps `boRem` → `bvsrem` (signed). Nim's `%%` treats operands as unsigned → should map to `bvurem`. No `boRemU` exists yet.

**Target files:** `ast_to_ir.nim` (`convertBinOp`: add `%%` → `boRemU`), `axiom_ir.nim` (add `boRemU` to `BinOpKind`), `axiom_ir_helpers.nim` (`binOpSymbol`/`binOpSmt`: `boRemU → "bvurem"`), `ir_to_lean.nim` (`irBinOpToLean`: `boRemU → "%ᵤ"`).

### Golden Case A1 — `%%` with unsigned max-value operand

```nim
let x = 0xFFFF_FFFF_FFFF_FFFF'u64
let y = 3'u64
let z = x %% y
```

```
Expected IR:    irBinOp(boRemU, irLit(0xFFFFFFFFFFFFFFFF), irLit(3))
Expected SMT:   (bvurem #xFFFFFFFFFFFFFFFF #x0000000000000003)
Expected outcome: z = 1; solver unsat for (assert (not (= z 1)))
```

### Golden Case A2 — `%%` with signed operand treated as unsigned

```nim
let x = -1'i64
let y = 2'u64
let z = x %% y
```

```
Expected IR:    irBinOp(boRemU, irLit(0xFFFFFFFFFFFFFFFF), irLit(2))
Expected SMT:   (bvurem #xFFFFFFFFFFFFFFFF #x0000000000000002)
Expected outcome: z = 1; solver unsat for (assert (not (= z 1)))
```

### Golden Case A3 — `%%` vs `mod` divergence (regression guard)

```nim
let x = -5'i64
let y = 3'i64
let a = x %% y    # unsigned remainder
let b = x mod y   # signed Euclidean remainder
```

```
Expected IR:    a → boRemU;  b → boRem
Expected SMT:   a → (bvurem ...);  b → (bvsrem ...)
Expected outcome: Both yield 1 for this case, but IR operators differ.
  Golden test asserts boRemU ≠ boRem and each maps to its correct SMT op.
```

---

## §2. Defect B — Overflow predicate divergence across callers

**Root cause:** `ir_pipeline_runner.nim:726` calls `irToSmtScript(funcDef, includeOverflowDefines = true)` while `ir_pipeline_runner.nim:202` (`runZ3CheckViaIR`) and `cross_validation.nim:94` (`crossValidate`) call `irToSmtScript(funcDef)` with default `includeOverflowDefines = false`. The overflow define-fun declarations are only emitted in the pipeline runner path, breaking cross-validation consistency.

**Desired:** All callers consistent, governed by `SemanticProfileV1.overflowMode` (new type: `Checked`/`Unchecked`/`Strict`).

**Target files:** `ir_pipeline_runner.nim:202` (pass `includeOverflowDefines = true`), `cross_validation.nim:94` (pass `includeOverflowDefines = true`), `ir_to_smt_chunk3.nim:131` (add `overflowMode` parameter).

### Golden Case B1 — Pipeline runner path emits overflow defines

```nim
proc p(x: int, y: int): int =
  result = x + y
  assert result >= x
```

```
Expected SMT (includeOverflowDefines = true):
  (define-fun no_overflow_add ...)
  (define-fun no_underflow_add ...)
  (define-fun p_impl ((x (_ BitVec 64)) (y (_ BitVec 64))) (_ BitVec 64)
    (let ((result (bvadd x y))) result))
  (assert (>= result x))
  (assert (let ((result (p_impl x y))) (not (>= result x))))
  (check-sat)
Expected outcome: solver unsat (postcondition holds for no-overflow add).
```

### Golden Case B2 — Cross-validation path emits identical overflow defines

```nim
# Same function as B1, called via crossValidate
```

```
Expected SMT: Identical to B1 — same define-fun declarations, same p_impl body.
Expected outcome: crossValidate returns CrossValidationResult(consistent = true).
```

### Golden Case B3 — `SemanticProfileV1.overflowMode` governs all callers

```nim
let profile = SemanticProfileV1(overflowMode = OverflowMode.Checked)
let smtScript = irToSmtScript(funcDef, overflowMode = profile.overflowMode)
```

```
Expected outcome:
  Checked:  overflow assertions emitted, solver proves no overflow.
  Unchecked: no overflow assertions, solver result depends on postcondition alone.
  Strict:   assertions emitted + solver must return unsat (unknown = proof failure).
```

---

## §3. Defect C — Shift operations undefined in IR

**Root cause:** `BinOpKind` (`axiom_ir.nim:31-46`) has no `boShl`/`boShr`. `ast_to_ir.nim` has no `shl`/`shr` mapping. Current behavior: silent fallthrough to `boAdd` in `convertBinOp`'s `else` branch (`ast_to_ir.nim:182`).

**Desired:** Explicit UNSUPPORTED rejection with diagnostic, not silent mis-compilation.

**Target files:** `axiom_ir.nim` (add `boShl`, `boShr` to enum), `ast_to_ir.nim` (`convertBinOp`: `"shl"`/`"shr"` → diagnostic error), `axiom_ir_helpers.nim` (`binOpSymbol`/`binOpSmt`: future `bvshl`/`bvlshr`), `ir_to_lean.nim` (future `<<`/`>>`).

### Golden Case C1 — `shl` explicitly rejected

```nim
let x = 1'i64
let y = 3'i64
let z = x shl y
```

```
Expected IR:    ERROR — nil irExpr; diagnostic: "UNSUPPORTED: shift 'shl' not in V1 IR"
Expected SMT:   (empty string — irToSmtScript returns "")
Expected outcome: pipeline returns IrPipelineResult(success = false, provenance = vpUnsupported,
  fallbackReason = "shift 'shl' not supported in V1"). No Z3 query, no Lean proof.
```

### Golden Case C2 — `shr` (arithmetic) explicitly rejected

```nim
let x = -8'i64
let y = 2'i64
let z = x shr y    # arithmetic shift, result = -2
```

```
Expected IR:    ERROR — same rejection as C1
Expected SMT:   (empty string)
Expected outcome: Same as C1 — diagnostic at conversion time, no silent mis-compilation.
```

### Golden Case C3 — `shr` with unsigned operand also rejected (no bvashr/bvlshr ambiguity)

```nim
let x = 0xFFFF_FFFF_FFFF_FFFF'u64
let y = 4'u64
let z = x shr y
```

```
Expected IR:    ERROR — same rejection as C1/C2
Expected SMT:   (empty string)
Expected outcome: V1 does not distinguish logical vs arithmetic shift — all shifts unsupported.
  Future V2 will add boShl/boShr with a shift-kind discriminator.
```

---

## §4. IR↔SMT Identity Alignment Plan

### Current state

| Aspect | Today | Problem |
|--------|-------|---------|
| IR identity hash | `canonicalizeIR` (`axiom_ir.nim:421`) — alpha-renames, sorts commutative pairs | Correct for hashing |
| SMT text generation | `irToSmtScript` (`ir_to_smt_chunk3.nim:5`) — uses **RAW** (non-canonical) IR | SMT text varies for alpha-equivalent IR trees |
| Identity invariant | None enforced | Same source → different SMT text depending on variable naming |

### Three canonical invariants

**Invariant I — Structural canonicalization:** Same source → same IR hash. After `canonicalizeIR`, `computeIrDigest` must be identical for alpha-equivalent IR trees.

*Test:* Parse function → raw IR → canonicalize → hash. Repeat with swapped parameter names. Assert digests equal.
*File:* `axiom_ir.nim:421` (`canonicalizeIR`), `axiom_ir.nim:441` (`computeIrDigest`).

**Invariant II — Encoding canonicalization:** Same CanonicalIR → same SMT text. `irToSmtScript` must produce byte-identical output for structurally identical canonical IR.

*Test:* Produce canonical IR for function F. Call `irToSmtScript(canonicalF)` twice. Assert `smtScript_A == smtScript_B`.
*File:* `ir_to_smt_chunk3.nim:131` (`irToSmtScript`).

**Invariant III — SMT generation switches to canonical IR (RECOMMENDED: YES).** `irToSmtScript` should canonicalize before SMT emission so the identity hash equals the SMT-input IR.

*Files to change:*
- `ir_to_smt_chunk3.nim:131` — `irToSmtScript`: add `let canonical = canonicalizeIR(f)` at top; use `canonical` for all SMT generation
- `ir_to_smt_chunk3.nim:19` — `irFuncDefToSmt`: accept canonicalized IR
- `ir_to_smt_chunk3.nim:5` — Update NOTE comment from "ORIGINAL (non-canonical)" to "canonical"
- All callers benefit automatically (no changes needed at call sites)

---

## §5. Phase 2 Acceptance Criteria

All three conditions must be met:

1. **All golden cases pass** — 11 golden cases (A1–A3, B1–B3, C1–C3) produce expected IR, SMT-LIB fragment, and semantic outcome through the Phase 2 encoder.

2. **Both canonical invariants tested** — Invariant I (structural → same hash) and Invariant II (encoding → same SMT text) have deterministic test cases that pass.

3. **No behavior change outside supported subset** — Only `boRem` (split to `boRem`/`boRemU`), overflow assertions (now consistent), and shift operations (now explicitly rejected) change. All other IR nodes (`boAdd`, `boSub`, `boMul`, `boDiv`, comparisons, boolean ops) retain existing encoding.

---

## §6. Implementation Notes

- Nim's `%%`: unsigned remainder; distinct from `%` (C-style signed) and `mod` (Euclidean). Encoder must distinguish `%%` from `%`/`mod` at `convertBinOp`.
- Nim's `shl`/`shr`: `shl` = logical left, `shr` = arithmetic right (sign-preserving). V1 supports neither — explicit rejection is correct.
- `SemanticProfileV1.overflowMode`: default is `Checked` (matches current pipeline runner behavior).
- Canonical IR in SMT generation is backward-compatible: alpha-renaming already handles variable-name differences.