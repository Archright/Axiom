# WP4-h-3 getBitsBE end-to-end prove replay — runs record

## Command (reproducible)
```
export AXIOM_STATE_DIR=/tmp/axanchor/state
bin/ax prove \
  --project <workspace>/nim-stew-clean-c75502c \
  --target 'stew/bitops2.nim::getBitsBE' \
  --limit 1
```
- Working dir: `.`
- State dir seeded with `data/verification_scope.lock` from the Axiom repo's `data/`.
- Binary: `bin/ax` (rebuilt 2026-08-30 12:33, post typed-lowering).
- Exit code: 0.

## Result — capability boundary at StructuralAST ingress (NOT at Z3)
The pipeline for `getBitsBE` stops BEFORE any obligation reaches SMT/Z3. The
Sieve-Gate hard-rejects the symbol at the structural-ingress stage:

```
[Sieve-Gate] getBitsBE — escalated: erGuardHardReject
  Context: Failed to parse source: Failed to parse Nim source
  ↳ StructuralAST: rejected (counterexample)
```

Canonical trajectory report (state/logs/ax_prove_trajectory.jsonl) shows, for
every getBitsBE run:
- `refactorEvidence.layerTrace = [{layerName: StructuralAST, outcome: leFailedSat, stepCount: 0}]`
- `refactorEvidence.smtlib2Query = ""`   ← no SMT query generated
- `solverInvocationCount = 0`, `obligationAttemptedCount = 0`  ← Z3 never invoked
- node status `pre_sieved`, assurance tier `unknown`

## Root cause (subject-side, pre-existing structural ingress gap)
`getBitsBE` signature in the immutable subject
`nim-stew-clean-c75502c/stew/bitops2.nim:559`:
```nim
func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T
```
contains `openArray[byte]`, `HSlice`, and `type[SomeUnsignedInt]` (parametrized
type / generic signature). The StructuralAST parser cannot parse this
signature, so the Sieve-Gate fails closed (`erGuardHardReject`). This is the
documented, deliberately-deferred successor capability
("External signature/structural ingress generalization: openArray, HSlice,
typedesc, generic signature"), not a regression from WP4-h-3's typed-SMT
lowering (which lives downstream of this gate).

## What WP4-h-3 DID establish (separately, via probe, not this replay)
- `obligation_smt_lowering` typed `IRExpr → SmtExpr → SMT-LIB2` lowering works,
  deterministically, and reaches Z3 for `okSafetyDiv(resultBits != 0)`
  (BitVec64). See `../probe/lowering_probe.nim` and its two byte-identical runs.
- This end-to-end `prove` path for getBitsBE does NOT exercise the typed
  lowering because admission is blocked upstream at the structural sieve.

## Classification
Unsupported (structural/signature ingress) → the pipeline never produces an
SMT goal; lower stages (typed lowering, Z3, Lean, KAA, Trust) never engage.
Not Verified, not Vacuous-at-proof, not a solver failure, not a
ToolchainFailure. The honest boundary of WP4-h-3 for `getBitsBE` is:
**source → (structural) admission fails before obligation → SMT**.

## Artifacts
- `prove_getBitsBE_run1.log` — full run 1 log (this file's run).
- Trajectory + z3 telemetry preserved in `/tmp/axanchor/state/logs/`.
