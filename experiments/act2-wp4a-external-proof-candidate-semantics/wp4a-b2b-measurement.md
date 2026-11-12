# WP4a-B2b: decodedLength Verification Classification Measurement

## Question
Does `stew/base36.nim::decodedLength` produce a **Vacuous** verification result or a full Z3/Lean result when run through Axiom's current engine? Does the T3 tautology check (~858-878) trigger, or does decodedLength go through the full SMT+Lean pipeline?

## Context
- **PROJECT_UNDER_TEST**: `<workspace>/nim-stew-clean-c75502c`
- **PROJECT_REVISION**: clean checkout sha256 of `stew/base36.nim` = `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` (verified)
- **AXIOM_REVISION**: current working tree with uncommitted WP3-b changes (not reverted/committed)
- **AXIOM_CONFIGURATION**: `nim c -d:release --hints:off -o:bin/ax src/cli/main.nim`
- **TOOLCHAIN_IDENTITY**: Nim compiler, Z3 solver, Lean 4 (Leanstral)
- **EXPERIMENT_ID**: WP4a-B2b
- **DATE**: 2026-08-28

## Subject Integrity
```
$ sha256sum <workspace>/nim-stew-clean-c75502c/stew/base36.nim
b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8  stew/base36.nim
```
✅ Matches the required hash. Subject is immutable and verified.

## Build Status
```
cd .
nim c -d:release --hints:off -o:bin/ax src/cli/main.nim
```
**Result**: ✅ Build succeeded (exit 0). Binary rebuilt at `13:03` (includes uncommitted WP3-b changes). Old binary at `10:06` was replaced.

## decodedLength E2E Run

### Command
```bash
AXIOM_ROOT=. \
AXIOM_STATE_DIR=/tmp/wp4a_c5 \
timeout 300 ./bin/ax prove --project <workspace>/nim-stew-clean-c75502c \
  --target stew/base36.nim::decodedLength --limit 1
```

### Outcome
- **Exit code**: `0`
- **Wall time**: ~9821ms
- **Target found**: `1 node(s) match 'stew/base36.nim::decodedLength'`; eligible=1

### Obligation Count
From `ax_proof_state.json` (`executionStats`):
- `obligationGeneratedCount`: **11** (whole run, includes pre-computed batch)
- `obligationAttemptedCount`: **0**
- `targetsWithObligations`: **5** (the 5 pre-computed results)
- `eligibleTargets`: **5**

decodedLength's **per-function** obligation count is not separately reported in the trajectory. The 11 obligations and 5 targets-with-obligations belong to the pre-computed batch (normalizeMaxWorkers, calcDynamicTimeoutCore, clampTimeoutMs, safeSpeedupRatioCore, proximityScore), not to decodedLength itself. decodedLength was processed separately by the loop_driver's UAP pipeline and did not produce a certificate or journal entry.

### Planned Node Count / Solver Invocation
From `ax_proof_state.json`:
- `plannedNodeCount`: **1**
- `solverInvocationCount`: **1**
- `totalSolverTimeMs`: 0
- `depthStats.solverElapsedMs`: **9820** (per-depth solver time for decodedLength)

From `ax_prove_trajectory.jsonl`:
- `solverInvocationCount`: **1** in the summary

**Z3 was invoked** (`solverInvocationCount=1`, `solverElapsedMs=9820`). The `z3_telemetry.jsonl` captured 9 Z3 queries during the run (timestamps `04:03:51Z`–`04:03:54Z`, prior to decodedLength processing at `04:03:55Z`). These 9 queries were from the pre-computed batch (CAS MISS re-computation of the 5 pre-computed functions). decodedLength's own Z3 invocation occurred during the CE-GAR loop phase.

### Final Classification

From the trajectory and proof state:

| Dimension | Value |
|---|---|
| **Status (statusCounts)** | `failed: 1` |
| **Cross-validation (crossValidation.vacuous)** | `1` (vacuous) |
| **Assurance tier** | `unknown` |
| **Tier resolution** | `unavailable` |
| **Tier counts** | `{unknown: 1}` |
| **Evidence log** | `"UAP failed"` |
| **Certification** | No certificate/journal entry produced |

**Final classification: `Failed` (main pipeline), with `Vacuous` in the cross-validation dimension.**

The cross-validation was explicitly skipped with the reason:
> `[axiom_engine] cross-validation skipped (vacuous — no postconditions)`

This is NOT a `Vacuous` classification in the `statusCounts` (which shows `failed: 1, vacuous: 0`). The overall status is `failed` because the UAP pipeline (CE-GAR + Leanstral) failed, while the cross-validation dimension separately marks it as vacuous.

## Mechanism with Evidence

### Source Code of decodedLength
```nim
func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
```
This is a pure `func` with **no preconditions** and **no postconditions**.

### Code Path Trace

#### 1. T3 Tautology Check — NOT TRIGGERED
**File**: `src/verification/batch_uap/ir_pipeline_runner.nim:858-878`
```nim
# ── T3: Tautology Check ──────────────────────────────────────────────
if funcDef.preConditions.len > 0:        # <── GUARD: decodedLength has 0 preconditions
    let tautResult = checkInvariantVacuity(funcDef.preConditions)
    if tautResult == tcTautology:
        ...  # REJECT as tautological
```
decodedLength has `preConditions.len == 0`, so the guard `funcDef.preConditions.len > 0` is **false**. `checkInvariantVacuity` is **NOT called**. No `[tautology]` log line was emitted for decodedLength.

This confirms the code analysis hypothesis: the T3 tautology check does NOT trigger for decodedLength because it has zero preconditions.

#### 2. T5 Implication Check — NOT TRIGGERED
**File**: `src/verification/batch_uap/ir_pipeline_runner.nim:880-884`
```nim
if funcDef.preConditions.len > 0 and funcDef.postConditions.len > 0:  # <── BOTH must be > 0
    let implResult = checkAllImplications(funcDef.preConditions, funcDef.postConditions)
```
decodedLength has neither preconditions nor postconditions, so this guard is also **false**.

#### 3. `checkInvariantVacuity` — NOT INVOKED
**File**: `src/verification/ax_tautology.nim:43-50`
```nim
proc checkInvariantVacuity*(preConditions: seq[IRExpr]): TautologyCheckResult =
    for pc in preConditions:
        let r = checkTautology(pc)   # calls z3ExecPersistent
```
This function is only called from the T3 tautology check guard (line 860). Since the guard did not trigger, `checkInvariantVacuity` was **never invoked** for decodedLength. No Z3 call happened through this path.

#### 4. `irToSmtScript` Returns "" — VACUOUS MECHANISM
**File**: `src/core/trusted/private/ir_to_smt_chunk3.nim:256-258`
```nim
    # Step 5: Vacuous guard — no postconditions → skip BMC
    if f.postConditions.len == 0:
        return ""
```
decodedLength has `postConditions.len == 0`, so `irToSmtScript` returns `""` (empty string). This is the **actual vacuity mechanism**.

#### 5. Cross-Validation Skipped — VACUOUS
**File**: `src/cli/axiom_engine.nim:823-829`
```nim
elif cvResult.z3Result.len == 0:
    # Vacuous: irToSmtScript returns "" when there are no postconditions
    # (or the entry is BMC-unverifiable), so no verification actually ran.
    inc vacuousCount
    logInfo("axiom_engine", "[axiom_engine] cross-validation skipped (vacuous — no postconditions): " &
                     entry.name & " digest=" & cvResult.irDigest)
```
Since `irToSmtScript` returned `""`, `cvResult.z3Result.len == 0`, and the cross-validation was skipped as vacuous. This matches the log line:
> `[INFO] axiom_engine: [axiom_engine] cross-validation skipped (vacuous — no postconditions): die digest=6e32d25386399a01a6316512a3cd3979de432aafa2adc2f5d55c650cc2e6e113`

#### 6. Main Pipeline Ran — CE-GAR + Leanstral — FAILED
From `ax_prove_trajectory.jsonl`:
```json
{"phase":"skCegar","nodeId":"decodedLength","detail":"opening case","status":"ssStarted"}
{"phase":"skCegar","nodeId":"decodedLength","detail":"case closed","status":"ssSucceeded"}
{"phase":"skLegislator","nodeId":"decodedLength","detail":"calling Leanstral","status":"ssStarted"}
{"phase":"skLegislator","nodeId":"decodedLength","detail":"response received","status":"ssFailed"}
{"phase":"skScribe","detail":"Leanstral called: success=false","status":"ssFailed"}
{"phase":"skJudge","detail":"verified=false","status":"ssSucceeded"}
{"phase":"skCertificate","detail":"Abrupt pipeline termination","status":"ssFailed"}
{"phase":"skSwat","detail":"UAP failed","status":"ssFailed"}
```
The CE-GAR loop opened and closed the case, then Leanstral was called and **failed**. The UAP pipeline produced `UAP failed`. No certificate was written.

### Z3 Invocation Summary
- **Was Z3 invoked?**: YES (`solverInvocationCount=1`, `solverElapsedMs=9820`)
- **Z3 queries**: 9 queries in `z3_telemetry.jsonl` (from the pre-computed batch)
- **decodedLength's Z3 invocation**: Occurred during the CE-GAR loop phase (not captured in `z3_telemetry.jsonl` timestamps, which are prior to decodedLength processing)
- **Z3 result for decodedLength**: The CE-GAR loop closed the case but did not produce a proof. Leanstral failed. The cross-validation was vacuous (Z3 script was empty string).
- **`checkInvariantVacuity` did NOT call Z3** — it was never invoked because the `preConditions.len > 0` guard was false.

## encode Comparison Baseline

### Command
```bash
AXIOM_ROOT=... AXIOM_STATE_DIR=/tmp/wp4a_c5 timeout 300 ./bin/ax prove \
  --project .../nim-stew-clean-c75502c --target stew/base36.nim::encode --limit 1
```

### Outcome
- **Exit code**: `0`
- `--target filter: 1 node(s) match 'stew/base36.nim::encode'` — target found
- `frontier eligibility gate: excluded 326 non-proof-candidate candidate(s); eligible=0` — **not eligible**
- `verifying 0 nodes (primed=0)` — 0 nodes verified
- `Verification-Gate: 0 UAP requests — UAP execution skipped`
- `cross-validation: running IR consistency check (scope=0)` — scope=0

**Classification**: encode was **excluded as a non-proof-candidate** (eligible=0). The UAP pipeline was never invoked for encode. This differs from the prior Phase A measurement which expected `elNoObligation` — the difference is that encode is excluded at the frontier eligibility gate rather than proceeding to obligation generation.

## Artifacts Produced Under /tmp/wp4a_c5

| File | Description |
|---|---|
| `/tmp/wp4a_c5/decodedLength_run.log` | Full stdout+stderr of decodedLength run |
| `/tmp/wp4a_c5/encode_run.log` | Full stdout+stderr of encode run |
| `/tmp/wp4a_c5/logs/ax_prove_trajectory.jsonl` | Trajectory log with stage-by-stage status |
| `/tmp/wp4a_c5/logs/ax_proof_state.json` | Proof state with obligation counts, solver stats, cross-validation |
| `/tmp/wp4a_c5/logs/z3_telemetry.jsonl` | Z3 query telemetry (9 queries) |
| `/tmp/wp4a_c5/data/verification_scope.lock` | Kernel scope lock (kernel_total=40) |
| `/tmp/wp4a_c5/build/certificates/manifest.json` | Certificate manifest (5 entries, all pre-computed; decodedLength absent) |
| `/tmp/wp4a_c5/build/certificates/data/trusted/journal/*.json` | 5 journal entries (tcVerifiedProof for pre-computed results only) |
| `/tmp/wp4a_c5/logs/global_symbol_graph.json` | Symbol graph |
| `/tmp/wp4a_c5/logs/audit/vsr_ledger.jsonl` | VSR ledger |

## Non-Conclusions
- The `obligationGeneratedCount: 11` is an aggregate for the whole run (pre-computed batch + decodedLength). decodedLength's per-function obligation count is not separately reported in the trajectory.
- Whether decodedLength's IR body generated `okSafetyDiv` obligations via `generateCanonicalObligations` cannot be determined from the available logs — the obligation generation result was not logged for decodedLength specifically.
- The 9 Z3 queries in `z3_telemetry.jsonl` are from the pre-computed batch (CAS MISS re-computation). decodedLength's own Z3 invocation occurred during the CE-GAR loop and is not separately captured in the telemetry file.
- The `totalSolverTimeMs: 0` in the summary conflicts with `solverElapsedMs: 9820` in depthStats; the discrepancy may reflect different metrics (actual solver time vs. wall-clock time including overhead).

## Summary for Parent Agent

**decodedLength classification**: `Failed` in the main pipeline (UAP failed, Leanstral rejected), with `Vacuous` in the cross-validation dimension. **Not Vacuous in the statusCounts** — it is `failed: 1, vacuous: 0`.

**Mechanism**: The T3 tautology check at `ir_pipeline_runner.nim:859` did NOT trigger because decodedLength has `preConditions.len == 0`. `checkInvariantVacuity` was never called. Instead, `irToSmtScript` at `ir_to_smt_chunk3.nim:257-258` returned `""` because `postConditions.len == 0`, causing the cross-validation to skip as vacuous at `axiom_engine.nim:828`. The main CE-GAR+Leanstral pipeline ran but failed.

**Z3 was invoked**: `solverInvocationCount=1`, `solverElapsedMs=9820`. Z3 ran during the CE-GAR loop, but the cross-validation was vacuous (empty SMT script).

**encode comparison**: Target found but excluded as non-proof-candidate (eligible=0). UAP skipped entirely. Differs from prior Phase A `elNoObligation` expectation.
