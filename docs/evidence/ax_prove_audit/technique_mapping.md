# 6 Techniques Audit

> Audit date: 2026-06-03  
> Scope: `src/` tree only (production code, excluding tests/certificates/vault artifacts)  
> Method: deterministic `grep`/`sed` on source; ReadFile not used on `.nim` per AGENTS.md §2.2.

---

## Summary Table

| Technique | Expected Module | Actually Called? | Call Site | Evidence |
|---|---|---|---|---|
| CEGAR | `cegar_engine.nim` | **YES** | `src/core/orchestrator_topology_worker.nim:92` inside `applyCegarAbstraction`, called from `src/core/orchestrator_parts/orchestrator_part1.nim:84` | `grep -rn "runCegarLoop" src/` returns `orchestrator_topology_worker.nim:92` |
| BMC (`bmc_generic`) | `bmc_generic.nim` | **NO (dead code)** | None outside `bmc_generic.nim` and `cegar_bmc_bridge.nim` | `grep -rn "verifyGenericProperty" src/` shows only internal + `cegar_bmc_bridge.nim:70`; `bridgeCegarToBmc` itself has zero callers |
| BMC (`bmc_race`) | `bmc_race.nim` | **YES** | `src/core/axiom_api_parts/axiom_api_part2.nim:37,53` | `bmc_race.verifyRaceConditionWithDelta` and `bmc_race.verifyRaceCondition` called directly |
| SMT Inductive | `solver_bridge.nim` | **YES (indirectly)** | `src/verification/pipeline_negative_scan_parts/pipeline_negative_scan_part2.nim:282` via `parseZ3StdoutAsResult` | Called inside Detective's `runNegativeInvariantSearch` flow; `solver_bridge` imported by `pipeline_negative_scan.nim:11` |
| Fixed-point | `cegar_engine.nim` | **YES (embedded)** | `src/verification/cegar_engine.nim:212-225` fingerprint loop inside `runCegarLoop` | Explicit fixed-point convergence with `computeInvariantFingerprint` and `prevFingerprint` comparison |
| Summary-based | `detective.nim` | **NO** | N/A | `grep -rn "summary\|modular" detective.nim` returns zero matches for technique logic; only `proofSummaryPath` output filename in `universal_pipeline.nim:206` |
| Deductive (Lean) | `judge.nim` | **YES** | `src/personas/judge.nim:41` and `src/verification/universal_pipeline.nim:64` | `judge.certify` calls `runLeanReplay`; pipeline pre-synthesizes via `leanstral_gateway` then passes to judge |

---

## Detailed Findings

### 1. CEGAR — INVOKED ✅

- **`runCegarLoop`** (exported proc in `src/verification/cegar_engine.nim:148`) is invoked from `src/core/orchestrator_topology_worker.nim:92`.
- The caller `applyCegarAbstraction` is itself called from `src/core/orchestrator_parts/orchestrator_part1.nim:84` during topology worker processing.
- **`bridgeCegarToBmc`** (`cegar_bmc_bridge.nim:54`) is **defined but never called**; `cegar_bmc_bridge.nim` has zero import statements in `src/`.

### 2. BMC — PARTIALLY INVOKED ⚠️

- **`bmc_generic.nim`** (`verifyGenericProperty`, `verifyIntegerOverflow`, `verifyIndexBounds`, `verifyNullDereference`) is effectively **dead code**:
  - Functions are called only internally or from `cegar_bmc_bridge.nim:70`.
  - Since `bridgeCegarToBmc` has no callers, `bmc_generic` never executes in the live UAP pipeline.
- **`bmc_race.nim`** is **live**:
  - `verifyRaceConditionWithDelta` called at `src/core/axiom_api_parts/axiom_api_part2.nim:37`
  - `verifyRaceCondition` called at `src/core/axiom_api_parts/axiom_api_part2.nim:53`
  - Also imported by `solver_bridge.nim`, `axiom_api.nim`, `axiom_api_session.nim`, `expression_parser.nim`, `session_parser.nim`.

### 3. SMT-based inductive proof — INVOKED ✅ (indirect)

- **`solver_bridge.nim`** is imported by `pipeline_negative_scan.nim:11`, `axiom_api.nim`, `axiom_api_session.nim`, and `heal_node_executor.nim`.
- Concrete SMT invocation occurs at `src/verification/pipeline_negative_scan_parts/pipeline_negative_scan_part2.nim:282`:
  ```nim
  let parsed = parseZ3StdoutAsResult(solverStdout, translation.smt2, violatedProperty)
  ```
- This is inside the `runNegativeInvariantSearch` flow, which is triggered by `detective.openCase` in `universal_pipeline.nim:33`.
- **Note:** No direct `solver_bridge` calls exist in `universal_pipeline.nim` or `batch_uap_orchestrator.nim`; the SMT track is exercised through the detective sub-module.

### 4. Fixed-point static analysis — INVOKED ✅ (embedded in CEGAR)

- `src/core/solver/fixedpoint_engine.nim` exists (CHC → Z3 fixedpoint engine) but has **zero callers** in `src/`.
- However, `cegar_engine.nim` implements its own fixed-point loop:
  - `runCegarLoop` (line 148) explicitly documents: "Fixed-point convergence loop for loop invariant synthesis."
  - Iteration termination checks `newFingerprint == prevFingerprint` (line ~212-225).
  - When the fingerprint stabilizes, the proc returns `cegarProven`.
- Therefore fixed-point logic **is** exercised, but it is bundled inside the CEGAR module rather than calling the standalone `fixedpoint_engine.nim`.

### 5. Summary-based modular analysis — NOT INVOKED ❌

- `src/personas/detective.nim` exports `openCase` and `investigate`.
- Neither function performs modular decomposition or function summarization.
- `grep -rn "summary\|modular" detective.nim` returns **zero** technique-related matches.
- The only "summary" occurrence in the expected scope is `proofSummaryPath` in `universal_pipeline.nim:206`, which is a **JSON output file path**, not an analysis technique.

### 6. Deductive program verification (Lean 4) — INVOKED ✅

- `src/personas/judge.nim:41`: `certify` calls `runLeanReplay(req.functionName, preSynthesizedLeanSource)`.
- `src/verification/universal_pipeline.nim:64`: pipeline pre-synthesizes a Lean proof via `callLeanstral(leanPrompt)`, then runs `runLeanReplay(req.functionName, lsResult.theoremSource)`.
- If Leanstral succeeds, the verified source is forwarded to `judge.certify` as `preSynthesizedLeanSource`.
- `leanstral_gateway` is imported at `universal_pipeline.nim:20`.
- Additional `runLeanReplay` wrappers live in `src/core/solver/wrappers.nim`, `src/core/provider_interface.nim`, and `src/core/the_judge_eval.nim`.

---

## Verdict

| Technique | Status |
|---|---|
| CEGAR | ✅ Active in pipeline |
| BMC (generic) | ❌ Dead code (`bmc_generic` unreachable) |
| BMC (race) | ✅ Active via `axiom_api_part2` |
| SMT-based inductive proof | ✅ Active via detective negative scan |
| Fixed-point static analysis | ✅ Active (embedded in CEGAR loop) |
| Summary-based modular analysis | ❌ Not implemented / not invoked |
| Deductive program verification (Lean 4) | ✅ Active in UAP + Judge layers |

**Raw evidence file:** `docs/evidence/verifications/technique_verification.md`
