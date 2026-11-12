# Phase X0 Execution Accounting — Analysis Report

**Experiment**: `phase_x0_execution_accounting`
**Branch**: `feat/phase-x0-exec-accounting` (based on `origin/main` @ `2dbd0ce71`, Phase P merged)
**Date**: 2026-09-06
**Tool**: `tools/phase_x0_accounting.nim` v0.1.0
**Evidence**: `data/benchmarks/phase_x0_exec_accounting.json`

---

## 1. Representative Run (real, clean-state)

| Field | Value |
|---|---|
| **Command** | `AXIOM_CI=1 bin/ax prove --limit 25` (full-frontier, untargeted, closure loop) |
| **Clean State** | Certificate vault purged (`data/trusted/certificates/`); `.axiom/cache` + `build/nimcache` preserved per CI determinism guard |
| **Wall Time** | 2,496 ms (real `/usr/bin/time` 9.58 s incl. startup; report `totalWallTimeMs` 2,496) |
| **Exit** | 0 |
| **Closure** | requiredCount=23, completedCount=12, uncompletedRequired=11, wavesExecuted=2, closureComplete=false, frontierEmpty=true |
| **Universe** | kernelScopeSize=40, universeCount=23 |

### Measured accounting (from `bin/ax report --json`)

| Category | Metric | Value |
|---|---|---|
| **Plan** | universeCount / requiredCount | 23 / 23 |
| | reusableCount (cacheHit) | 0 |
| | preSievedCount | 12 |
| | **freshCount (obligationAttemptedCount)** | **0** |
| **Execution** | invocationCount (solverInvocationCount) | 12 |
| | cacheHitCount | 0 |
| | blocked / failed / timeout | 0 / 0 / 0 |
| | unresolvedCount (uncompleted required) | 11 |
| **DAG** | nodeCount / edgeCount | 12 / 0 |
| | criticalPath (max depth+1) | 1 |
| | maxWidth / averageWidth | 12 / 12.0 |
| **Time** | totalWallMs | 2,496 |
| | totalSolverTimeMs (freshExecutionMs) | 0 |
| | planningMs (wall − solver) | 2,496 |
| | cacheClassificationMs | 0 (not instrumented) |
| | reductionMs | −2,496 (serialBaseline=0) |

**Case verdict: `unclassified`** — see §3.

---

## 2. What the real run shows

- All 12 processed nodeReports have `status = no_obligation`; `summary.statusCounts.pre_sieved = 12`.
- `eligibleTargets = 5`, `targetsWithObligations = 5`, `obligationGeneratedCount = 11`, **`obligationAttemptedCount = 0`**.
- `solverInvocationCount = 12` are **IR-pipeline Z3 pre-checks that returned instantly as FAIL** (`provenance=pkNone`, `solverMethod=smBMC`) — e.g. `safeSpeedupRatioCore`, `proximityScore`. These are NOT genuine proof obligations; no real Lean/Z3 model-checking work occurred.
- The 11 "uncompleted" required units never became eligible: the discoverable frontier in this clean state is only 5 `elProofCandidate` nodes, and after obligation generation all classify `no_obligation`. `blockedNodes=[]`, no unresolved edges.

**Conclusion**: In clean state on the current main-based tree, the Full prove reaches **zero genuine solver obligations**. The historical ~59-min CI cost came from a pre-Phase-P tree with warm cached certificates enabling real Lean/Z3 proofs on units that here are all `no_obligation`. The 23-required / 12-executed figure from earlier measurements is **not reproducible** in this environment.

---

## 3. Why the case is `unclassified` (honest limitation)

Phase X cases A–E decompose the cost of a run that **actually executes solver work** (fresh ≈ required → parallelism; fresh=12 + small critical path → scheduler; per-invocation slow → prover; etc.). This run executed **zero** proof obligations (`freshCount=0`, `totalSolverTimeMs=0`), so none of the A–E bottlenecks is observable — classifying it as "Case D (cache)" or "Case E (planner)" would be **fabrication**, not measurement.

The two prior commits (6ba7049bd, b91dc7e42) mislabeled partial runs as a 59-min decomposition:
- 6ba7049bd: ran `--target normalizeMaxWorkers` (single symbol, 81 ms) and reported `freshCount=22`, `Case D` — wrong command, wrong numbers.
- b91dc7e42: ran the clean-state full prove but reported `Case E` (planner) from `planningMs=totalWallMs`, ignoring that zero solver work means no decomposition is possible.

Both are superseded by this commit's honest `unclassified` evidence.

---

## 4. Measurement-availability finding (actionable)

The 59-min CI Full-closure per-node decomposition **cannot currently be measured**:
1. **CI does not persist the per-node report**: the GitHub Actions log for verify-integration (run 33991178524, 59m08s) contains only aggregated PASS lines (g1/g2/g6g4/g7) and the 5-entry smoke report — no `nodeReports`/`executionStats`/`closure` JSON. The `axiom.report.v1` with full executionStats is not uploaded as an artifact.
2. **Local clean-state reproduction yields zero obligations** (see §2), so it cannot stand in for the warm-cached CI run.

**Recommended next step (Phase X1)**: make the accounting *measurable* before optimizing — persist `bin/ax report --json` (which already contains `executionStats.nodeStats`/`depthStats`, `closure`, per-node `status`/`cacheHit`/`solverElapsedMs`) as a CI artifact on the verify-integration job. Then a single warm CI run yields the real Plan/Cache/Fresh/DAG/Time decomposition and a genuine A–E classification. This is a CI artifact-persistence change (not a semantic change), and ci.yml is §-1 locked — so it requires architect approval, exactly as the Phase X brief anticipated ("그때 ci.yml을 수정할 충분한 근거가 생긴다").

---

## 5. Files

- `tools/phase_x0_accounting.nim` — pure accounting tool (reads report JSON → X0 schema; `freshCount = obligationAttemptedCount`).
- `data/benchmarks/phase_x0_exec_accounting.json` — real clean-state measurement (supersedes 6ba7049bd, b91dc7e42).
- `docs/reports/phase_x0_execution_accounting.md` — this report.

---

## 6. Addendum — X1.0 canonical accounting (same run, semantic contract)

**Contract**: `docs/spec/execution_accounting_contract.md`; reducer `tools/accounting/canonical_accounting.nim`; tool v0.2.0, schema v2.0.
**Measurement compensation**: per-wave reports re-read from `logs/ax_prove_trajectory.jsonl` (skReport `extra`), `measurementCompensated: true, compensationSource: "trajectory"` — TEMPORARY compensation for the last-wave merge defect (DEBT#458).

### Canonical numbers (last clean-state Full run, 2026-09-06 05:50, 2 waves)

| Field | Value |
|---|---|
| requiredCount (canonical OGR basis) | **5** |
| notRequiredCount | 0 |
| unresolvedDecisionCount | **12** (runtime no_obligation units with no eligibility/OGR basis in the data) |
| satisfiedCount / unsatisfiedCount | 0 / 0 |
| pendingCount (REQUIRED) | 5 |
| **contestedCount** (REQUIRED + runtime no_obligation) | **4** |
| freshExecutionCount (\|FreshExecutionSet\|) | 0 |
| attemptedCount / notAttemptedCount | 17 / 0 |
| preSievedCount / satisfiedByFresh / satisfiedByReused | 0 / 0 / 0 |
| runOutcome | planComplete=false, executionComplete=true, **verificationComplete=false** |
| **GateVerdict** | **FAIL** |

**Interpretation**: the 4 contested units are exactly the expected evidence of the DEBT#416 defect (`certNoObligation` classified on obligation-bearing units) — REQUIRED units whose runtime reports claim no obligation. These are NOT valid satisfactions (CONTESTED is fail-closed, never satisfying). On the requirement-decided universe (5), every unit stayed PENDING; zero fresh executions (`freshExecutionCount=0`), consistent with the X0 finding that the clean-state run reached no genuine solver obligation. Canonical GateVerdict=FAIL stands in contrast to the legacy exit-0 seam documented in the contract (exit 0 ⟺ failedCount==0 ∧ timeoutCount==0 only — closure completeness is not part of the exit code).

The legacy projection (legacyCompletedCount=12, legacyUncompletedRequiredCount=11, legacyClosureComplete=false) is emitted for continuity only; it is a mixed aggregate (Verified+NoObligation+InductiveValid, closure_evaluation.nim:66-68) and reflects only the last wave's data (DEBT#458).
