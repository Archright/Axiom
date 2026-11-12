# SemanticProfileV1 — Verified Semantics (machine-determined)

- **Status**: binding (spec SSOT for `core/trusted/semantic_profile.nim` declarations)
- **Bound**: 2026-10-07 (coherent generation, DEBT#494 resolution)
- **Predecessor note**: `semantic_profile.nim:8-21` previously declared a *nominal* contract
  ("Axiom guarantees this; Phase 2 makes the encoder conform"). That direction is **withdrawn**:
  the declarations now state what the encoder **actually verifies**. This document is the
  machine-semantics record of that move.

## 1. Signed division and modulo: Nim truncation vs Lean floor/emod

Nim defines `div`/`mod` on signed integers as **truncation toward zero** with the remainder
taking the **sign of the dividend**; Lean's `/` on `Int` is **floor division** and `%`
(`Int.emod`) yields a **nonnegative remainder for a nonzero divisor**. The two families
coincide exactly on the **nonnegative domain** (both operands ≥ 0 for `/`; nonnegative
dividend for `%`, `Int.tmod_eq_emod_of_nonneg`) and **diverge on negative operands**.

Measured counterexamples (Nim 2.2.10, pinned toolchain; Lean `Int` semantics per
`proofs/IR/Denotation.lean` Certified forms):

| Expression | Nim (trunc) | Lean (floor/emod) | coincide? |
|---|---|---|---|
| `-7 div 5` / `-7 / 5` | `-1` | `-2` | NO |
| `-7 mod 5` / `-7 % 5` | `-2` | `3` | NO |
| `7 div 5` / `7 / 5` | `1` | `1` | YES |
| `7 mod 5` / `7 % 5` | `2` | `2` | YES |
| `-7 %% 5` (Nim floored `%%`) | `4` | `3` (`-7 % 5`) | NO (different operator; `%%` is not the encoded term) |

The encoder verifies the **coincidence domain only**: the renderer emits Lean `/` (floor) and
`%` (`Int.emod`) while the Nim subject computes `div`/`mod`; the rendered proposition carries
the nonnegative-domain preconditions as discharged hypotheses (div/rem identity segments
`div=lean-floor/nim-trunc/coincident-nonneg-domain`,
`rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain`,
`src/verification/obligation/canonical_verification.nim:117,123`).

**Consequence for declarations**: `divisionMode` must NOT claim `spDivTruncTowardZero`
(all-operand truncation). V1 declares `spDivCoincidentNonnegative`: `Nim div (trunc) == Lean /
(floor)` on the nonnegative domain, **no claim for negative operands**. `spModuloSigned`
similarly names the nonnegative-dividend coincidence with `Int.emod`; negative-dividend sign
semantics is NOT claimed.

## 2. Overflow: reachability is not modeled — discharged as an obligation

The encoder does **not** model checked-overflow reachability. Instead, each checked-arithmetic
node contributes a **no-overflow goal conjunct** inside the negated query
(`(assert (not (and (no_overflow_add x y) (no_underflow_add x y))))`,
`src/core/trusted/private/ir_to_smt_chunk3.nim:271,357`; goal-not-assumption rule:
`docs/spec/obligation_semantics.md §3.8`, acceptance-tested by
`tests/verification/test_overflow_conformance.nim`). Overflow is therefore **discharged as an
obligation**: a verified obligation states "no overflow occurs on this path", so within the
verified domain checked (→ `OverflowDefect`) and wrapping arithmetic **coincide** — the solver
never explores either behavior.

**Overflow discharge invariant**: *no-overflow obligation ⇒ overflow reachability excluded in
the verified domain ⇒ checked and wrapping semantics coincide there; neither is claimed beyond
it.*

**Consequence for declarations**: `overflowMode` must NOT claim `spOverflowBounded`
(checked → `OverflowDefect` as an unconditional program meaning). V1 declares
`spOverflowObligationDischarged`: reachability not modeled; discharged via no-overflow goals;
checked/wrap coincide in the verified domain. `spOverflowBounded` / `spOverflowTrapping` /
`spOverflowWrapping` remain as **nominal V2+ encoder-conformance targets only**.

## 3. Declared (before) vs verified (now)

| Field | Old nominal declaration | V1 verified declaration (now) | Encoder reality |
|---|---|---|---|
| `divisionMode` | `spDivTruncTowardZero` (all operands) | `spDivCoincidentNonnegative` | floor `/` verified; coincidence proven on n ≥ 0 only |
| `overflowMode` | `spOverflowBounded` (checked → `OverflowDefect`) | `spOverflowObligationDischarged` | reachability unmodeled; no-overflow goals discharge it |
| `moduloMode` | `spModuloSigned` | `spModuloSigned` (doc corrected: nonnegative-dividend coincidence with `Int.emod`) | same coincidence shape as division |
| `moduloMode` (unsigned) | `spModuloUnsigned` (`%%`) | unchanged | — |
| `shiftMode` / `floatMode` / `stringMode` | unsupported | unchanged | not guaranteed |
| `uintMode` | `spUintWrapping` | unchanged | wrapping arithmetic |

## 4. Identity: hash regeneration and epoch semantics

`SemanticProfileV1Hash = ProfileHash(GlobalSemanticProfileV1)` =
SHA-256 of the canonical serialization (`target|intWidth|uintWidth|ord(overflow)|ord(div)|ord(mod)|ord(shift)|ord(float)|ord(string)|ord(uint)`).

- **Before** (`overflow=spOverflowBounded=0`, `division=spDivTruncTowardZero=0`):
  canonical `x86_64|64|64|0|0|0|0|0|0|0` →
  `af30124e618db1dae9bc8ba95991f620f07077847a29d3f42b4fcd67b48bdf4d`
- **After** (`spOverflowObligationDischarged`=3, `spDivCoincidentNonnegative`=1):
  canonical `x86_64|64|64|3|1|0|0|0|0|0` →
  `d2c44f569ef61e349a915582c4237b1b747df4d30a4701712178655bdd5bc44e`

All identity consumers take the same constant in one coherent generation (no second semantic
state source): `modelProfileIdentitySegment` (`src/verification/obligation/identity.nim:129`),
D2 capture (`canonical_verification.nim:130`), attestation `pinnedToolchainIdentity`
(`attestation_orchestrator.nim:111`), certificate `semanticProfileId` fallback
(`cert_writer.nim:406-407`), runner/evidence capture, `project_setup.profileIdentityFor`,
scope identity. The `modelprofile` suffix
(`/no-overflow-obligations/coincident-checked-wrap-domain`) is **unchanged** — it already
stated the coincidence domain, which the declarations now name themselves.

**Epoch semantics** (canonical meaning of `base36_sizing_binding_contract.md §9`): an identity
change **invalidates evidence sealed under the old identity** — recorded-vs-current identity
comparisons fail closed and re-execute. Sealed artifacts carrying the old hash
(`src/verification/certificates/c14243cd….json`,
`data/readiness/golden/negative/93af4444….json`) are Ed25519-signed records of past runs and
are NOT rewritten: their stored `semanticProfileId` truthfully names the (now-former)
nominal-generation semantics, and any comparison against the current identity fails closed by
design. The B-pinned, unsigned draft (`data/certification/evidence-draft.json`) is regenerated
in this generation.

## 5. Behavior invariance (declaration change ≠ engine change)

The weakening changes **declarations and identity strings only**. Verification-engine behavior
is byte-invariant:

- SMT emission: `ir_pipeline_runner.nim` computes
  `includeOverflowDefines` from the profile; the expression is aligned to
  `GlobalSemanticProfileV1.overflowMode in {spOverflowBounded, spOverflowObligationDischarged}`
  so the V1 profile keeps emitting the same no-overflow defines as before the weakening
  (previously `== spOverflowBounded`). `GlobalSemanticProfileV1` has exactly this one
  behavioral consumer (measured by search over `src/`, `tests/`, `tools/`).
- `crossValidate`/default-flag emission is untouched (`irToSmtScript` default
  `includeOverflowDefines = false`).
- Encoder lowering, Lean rendering, obligation generation: no reference to the weakened enum
  values; nothing changed.

## 6. Direction reversal record

The previous header declared "Phase 2 makes the encoder conform" (option (a) of DEBT#494:
bring truncation + explicit overflow modeling into the encoder). This generation executes
option (b): **declarations move to the verified meaning**; the Phase-2 encoder-conformance
direction is withdrawn as the contract direction. Justification:

- No documented product contract requires truncation-toward-zero or checked-overflow
  guarantees: `docs/spec/productization_contract.md` and `config/readiness_policy.json` contain
  no truncation/overflow guarantee (measured 2026-10-07, zero matches).
- The weakening removes an untracked semantics gap (nominal claim vs verified domain) rather
  than shrinking a shipped guarantee — the opposite of theater: the identity now names exactly
  what is proven.
- Reaching the nominal semantics later (negative-operand truncation encoding, explicit
  overflow-reachability modeling) is a future *narrowing→widening* change that regenerates the
  identity again under the same coherent-generation rule.
