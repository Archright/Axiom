# WP4-k Phase B — Contract Freeze (First Obligation Execution Closure)

**Experiment ID:** act2-wpk-obligation-execution
**Axiom revision:** 44fefd470
**Subject revision (nim-stew):** c75502ce

This document freezes the semantic contract that Phase C implements. It is
the reference for the implementation, the O1–O11 invariant checks, and the
Phase D tests.

---

## 1. Scope of this WP

**GOAL (one sentence):** Transport exactly one generated intrinsic safety
obligation from getBitsBE — `okSafetyDiv`, proposition `resultBits != 0` —
through the existing IR pipeline executor to a real Z3 invocation, with a
deterministic ledger, without building a new UAP or touching Lean/KAA.

**Explicit NON-GOALS (must not be touched in this WP):**
- No new UAP/scheduler code.
- No Lean/KAA changes.
- No `if getBitsBE` name special-casing anywhere.
- No `request.origin` change.
- No `replayKey` / `canonicalV3FieldKeys` / `schemaVersion` change.
- Do not modify `identity.nim:52` (canonicalizeEnvValue — pre-existing audit
  item, out of scope).
- No `proc` added under `src/core` (cap 950, currently 898).
- No git mutation, no certificate artifact regeneration.
- No widening of structural ingress (openArray/HSlice/typedesc).

The pipeline's job in this WP is to EXECUTE the already-lowered obligation
script via the existing caller-supplied-script Z3 path.

---

## 2. The canonical obligation ledger (v10)

New fields added to `IrPipelineResult` (additive-safe; value type):

```nim
ObligationExecutionRecord = object
  generatedObligationIds: seq[string]       # ALL ids from ogr.obligations.value (P3 scope :943-952)
  plans: seq[PlanExecutionRecord]
  terminalOutcome: Option[SemanticOutcome]  # obligation-level terminal semantic outcome
  droppedObligations: seq[DroppedObligationRecord]

PlanExecutionRecord = object
  planRevision: int
  obligationId: string
  attempts: seq[AttemptRecord]

AttemptRecord = object
  attemptNumber: int
  solverInvocationId: string
  solverInputDigest: string                 # H(raw SMT) == smtScriptDigest
  canonicalEnvelopeDigest: string          # H(pre-sentinel bytes)
  transportPayloadDigest: string            # H(full payload incl sentinel)
  rawSolverStatus: string
  semanticAttemptOutcome: SemanticOutcome
  derivationProvenance: string

DroppedObligationRecord = object
  obligationId: string
  dropReason: string
  planRevision: int
```

`SemanticOutcome` is defined in the new interpreter module (Section 4).

**Obligation Conservation invariant (O3):** every `generatedObligationId`
must appear in EXACTLY ONE of:
- one `PlanExecutionRecord.obligationId`, or
- one `DroppedObligationRecord.obligationId` (with a dropReason).

Golden slice rule: exactly one obligation (`okSafetyDiv`, the lowest id in
canonical ordering) is admitted into a plan; all other generated ids are
recorded as `droppedObligations` with reason `osrDroppedOutsideScope`, where
`osrDroppedOutsideScope` and `osrDroppedNoPlan` are two new members of
`ObligationSkipReason`.

---

## 3. Digest identity (O9) — three layers

Layer | Digest of | Where computed
------|-----------|----------------
`solverInputDigest` | raw SMT script (`sha256Hex(smtScript)`) | at/after script finalized — equals existing `SolverInvocation.smtScriptDigest` when populated
`canonicalEnvelopeDigest` | pre-sentinel envelope bytes from `buildZ3QueryEnvelope` | immediately after envelope build, BEFORE sentinel append
`transportPayloadDigest` | full payload incl sentinel | at payload-fix point (z3_pool :901 area)

**`canonicalEnvelopeDigest` naming contract:** it is a deterministic
**backend transport identity** — NOT a semantic identity. As the executor
evolves, `ProofRequest → BackendInput → Z3Envelope`, this digest stays the
transport identity of the Z3 envelope format. Do not promote it to a
semantic-proposition identity.

**`solverInvocationId`:** derived from the EFFECTIVE observation of the
invocation only — the caller's `timeoutMs` (budget) is NOT used; use
`z3SafetyNetMs`(60000), rlimit `z3DeterministicBudget`, seeds 0, and the
envelope digest. `replayKey` must remain byte-identical to current output;
do not alter the legacy replay key.

**O9 determinism:** same source + same profile → same 3-layer digests.
Run A == Run B (barring wall-clock fields) for the SAME invocation.

---

## 4. Result interpreter (new module)

New file: `src/verification/obligation/verification_result_interpreter.nim`.

```nim
QuerySemantics* = enum
  qsStandard              # solver status → semantic verdict via standard mapping
  qsDirect                # pass-through for tests that supply status directly

QuerySemanticsResult* = object
  rawSolverStatus: string
  semanticOutcome: SemanticOutcome
  failClosed: bool        # true when input incomplete → failed-closed unknown

SemanticOutcome* = enum
  smOutcomeUnsat          # validity established
  smOutcomeSat            # counterexample (would be found)
  smOutcomeUnknown
  smOutcomeTimeout
  smOutcomeResourceLimit
  smOutcomeProcessError
  smOutcomeParseError
  smOutcomeNotExecuted    # no attempt reached a solver
  smOutcomeFailedClosed   # result absent → fail-closed unknown
```

**Contract:** the interpreter is fail-closed. If no raw solver result exists,
it returns `smOutcomeFailedClosed` (NOT a success, NOT a silent skip). It maps
existing `SolverStatus` values to `SemanticOutcome` exactly, and reserves the
`qvStandard`/`qsDirect` distinction so tests can supply a status directly.

`verification_result_interpreter.nim` must be ALL `func` (it is in
`verification/`, not `core/`, so the proc-cap does not apply, but purity is
required for determinism).

---

## 5. O11 — terminal attribution completeness

New verification `func` (precedent: `assertNotTerminal` in
`proof_state_machine.nim:112`, returns `errResult` on violation):

```nim
func checkTerminalAttribution*(r: IrPipelineResult): Result[void, string]
```

Rules — REJECT if ANY of:
1. a `generatedObligationId` has 0 terminal accounts (neither plan nor drop),
2. a `generatedObligationId` has 2+ terminal accounts,
3. a `generatedObligationId` has both a terminal account and an explicit drop,
4. a drop without a reason (`dropReason == ""`),
5. a drop for an `obligationId` that is NOT in `generatedObligationIds` (unknown obligation dropped),
6. a duplicate drop (same obligationId dropped more than once).

This machine-checks O3/O3b (Generated = TerminallyAccounted) at the system
level and is the acceptance gate for Phase E.

---

## 6. Phase C concrete change list

1. **Gap 2 fix (ir_pipeline_runner.nim:1017):**
   `runZ3CheckViaIR(funcDef, phase = spBmc)` → `runZ3CheckViaIR(smtScript, phase = spBmc)`
   where `smtScript` is the local var set at :952 (obligation-derived when
   `ogr.kind == ogrGenerated`; classic adapter output otherwise). This makes
   the already-lowered obligation script the thing actually executed, instead
   of re-generating via `irToSmtScript(funcDef)`.

2. **Ledger on IrPipelineResult:** add `ObligationExecutionRecord` (+plan/attempt/dropped
   sub-records), capture all generated ids at :943-952 scope, classify non-golden
   ids as dropped (osrDroppedOutsideScope), populate the plan/attempt/terminal outcome.

3. **z3_pool digests:** compute `canonicalEnvelopeDigest` (pre-sentinel) and
   `transportPayloadDigest` (full payload) per invocation and make them
   available so the IR pipeline can record them in the attempt ledger.

4. **New interpreter:** `verification_result_interpreter.nim` per Section 4.

5. **O11 func:** `checkTerminalAttribution` per Section 5.

6. **osr enum:** add `osrDroppedOutsideScope`, `osrDroppedNoPlan` to
   `ObligationSkipReason` (obligation_types.nim:236) with `of` branches in the
   `$` renderer (:242) and any exhaustive `case` sites (loop_driver.nim:998-1003,
   stages.nim:336,349,360,372).

---

## 7. Fail-closed preservation

The TheaterGuard (:960) MUST remain intact. If typed lowering fails (empty
script), the guard still fires. The gap-2 fix does NOT remove the guard; it
makes correct artifacts reach the executor so the guard is not falsely
triggered.

---

## 8. Acceptance (Phase E)

- Pre-sieve must NOT be a hidden eligibility gate (mechanical admission only).
- Pattern mismatch must NOT terminally reject a candidate (getBitsBE reaches the IR pipeline).
- O1–O11 hold on the golden slice.
- getBitsBE reaches a real Z3 invocation (solverInvocationId + smtScriptDigest
  + canonicalEnvelopeDigest + transportPayloadDigest evidence, plus telemetry).
- Run A and Run B produce identical canonical evidence (deterministic).
- Result classification is `Incomplete` — NOT `Verified` (Lean/KAA not reached).
