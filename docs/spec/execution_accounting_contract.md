# Execution Accounting Contract — Phase X1.0 / X1 (Semantic Accounting Contract)

**Status**: Approved (Phase X1.0) + X1 canonical boundary installed (DEBT#458 closed)
**Canonical reducer**: `src/verification/accounting/run_accounting.nim` (importable, unit-tested)
**Thin CLI**: `tools/phase_x0_accounting.nim`
**Spec authority**: this document. The reducer and its unit tests are bound by this contract.

---

## 1. Canonical model — three axes + telemetry + satisfaction source

```
Axis 1 — RequirementDecision (planning axis, Phase P type reuse)
         REQUIRED | NOT_REQUIRED | UNRESOLVED
         authority: canonical OGR ("backends do not decide obligation existence")
Axis 2 — VerificationOutcome (result axis, defined only for REQUIRED units)
         SATISFIED | UNSATISFIED | PENDING
Axis 3 — Consistency (report-consistency axis)
         CONSISTENT | CONTESTED
ExecutionEvidence (telemetry): ATTEMPTED | NOT_ATTEMPTED
SatisfactionSource: FRESH | REUSED | PRE_SIEVED
  · SATISFIED + execution witness → FRESH
  · SATISFIED + verified reuse basis (5 conditions, §15.2) → REUSED
  · NOT_REQUIRED (no obligation) → PRE_SIEVED
RunOutcome (Plan 1 — INV-X1 inversion, §9):
  raw completeness projections: planComplete, executionComplete, verificationComplete
  run-level verdict + verbal basis: verdict ∈ {PASS, FAIL, BLOCKED, INCONCLUSIVE}
                                     basis ∈ {PROVEN, NO_OBLIGATION, REUSED, NONE}
  authority: verification_decision_authority.evaluateRunOutcome — the SOLE
             run-verdict producer (only it may produce PASS; §17)
```

- **Axis 1 (RequirementDecision)** is a run-wide planning property. Its authority is
  the canonical OGR basis (the eligibility classification recorded at selection,
  `src/verification/obligation/candidate_eligibility.nim` — `elProofCandidate` /
  `ogrGenerated` ⇒ REQUIRED; `elNoObligation` / `elUnsupported` / `elMalformed` ⇒
  NOT_REQUIRED). Runtime backends do **not** decide obligation existence: a runtime
  `no_obligation` report is evidence about the report, never about the obligation.
  Units with no eligibility/OGR basis in the data are **UNRESOLVED** (never
  NOT_REQUIRED — fail-closed).
- **Axis 2 (VerificationOutcome)** is defined only for REQUIRED units. PENDING means
  the unit reached no terminal satisfaction/unsatisfaction disposition.
- **Axis 3 (Consistency)** is a report-consistency property, **not** an outcome.
  CONTESTED is fail-closed and never satisfying.
- **ExecutionEvidence** is telemetry: whether the runtime processed the unit at all.
  Units never processed by the runtime are NOT_ATTEMPTED.
- **SatisfactionSource** classifies satisfied units (FRESH vs REUSED) and
  not-required units (PRE_SIEVED). **REUSED is a provenance/basis, never a
  decision-maker**: a cache-hit row is REUSED-satisfied only when its reuse
  record passes the 5-condition re-verification (§15.2); the final run-level
  PASS is decided by VDA (§17), never by the cache-hit flag alone.

## 2. Deterministic mapping (single mapping, no alternatives)

| Canonical OGR | Runtime report | RequirementDecision | VerificationOutcome | Consistency |
|---|---|---|---|---|
| REQUIRED | NO_OBLIGATION | REQUIRED | PENDING | **CONTESTED** |

There is exactly one deterministic CONTESTED mapping. CONTESTED is a consistency
property (not an outcome), fail-closed (never satisfying).

**Context**: a clean-state Full closure produces such contested units — the runtime
cert-writer classifies `certNoObligation` on obligation-bearing units (DEBT#416), so
`contestedCount > 0` is **expected evidence of that defect**, NOT a valid satisfaction.

Plan 1 removes the old `GateVerdict` column from this table: run_accounting never
derives a gate verdict (INV-X1 inversion, §9); the run-level verdict is decided by
VerificationDecisionAuthority (§17) with CONTESTED → INCONCLUSIVE (consistency
failure — never FAIL, never PASS: **FAIL 축소** = proof-level failures only).

## 3. Canonical fields

```
requiredCount, notRequiredCount, unresolvedDecisionCount,
satisfiedCount, unsatisfiedCount, pendingCount, contestedCount,
satisfiedByFresh, satisfiedByReused, preSievedCount,
attemptedCount, notAttemptedCount,
freshExecutionCount (= |FreshExecutionObservedSet|), executedCount
```

- `freshCount = |FreshExecutionObservedSet|` = distinct units with an invocation
  witness (a runtime verdict that requires a genuine solver/proof invocation; cache hits are
  excluded). Evidence source for this phase: **terminal_verdict_proxy** (see §12).
- `obligationAttemptedCount` is **NOT** `freshCount`: it is obligation-**weighted**
  (`loop_driver.nim:934` adds the node's whole `obligationCount`) and the parallel
  path never increments it. Both defects are documented (DEBT#458, closed in X1).
- `executedCount` = units with a runtime verdict record. Cache-hit rows ARE
  verdict records with NOT_ATTEMPTED evidence (DEBT#459, §15), so
  `executedCount = attemptedCount + cache-hit-reused rows` (the ATTEMPTED ⇔
  runtime-verdict-record equality holds for non-reuse rows).

## 4. Invariants

- RequirementDecision total over the unit universe (every unit has exactly one).
- VerificationOutcome total over REQUIRED units:
  `requiredCount == satisfiedCount + unsatisfiedCount + pendingCount`.
- Consistency total over units with a runtime verdict (default CONSISTENT).
- Raw completeness projections (computed at construction only):
  `planComplete = unresolvedDecisionCount == 0`;
  `executionComplete` = every REQUIRED unit has ATTEMPTED evidence;
  `verificationComplete = false` when `contestedCount > 0 ∨ unsatisfiedCount > 0
  ∨ unresolvedDecisionCount > 0 ∨ pendingCount > 0` (fail-closed — a REQUIRED
  unit that never reached a terminal state is unverified). These are RAW
  facts — they are NOT verdicts (INV-X1 inversion, §9).
- REUSED rows are SATISFIED only when their reuse record passes the five
  conditions (§15.2); every rejected cache-hit row is PENDING + anomaly.
- `unsatisfiedCount == proofFailedCount + timeoutUnsatCount` — the raw
  UNSATISFIED total is split into proof-level failures (status=failed) and
  timeout-only units; **the timeout→UNSATISFIED aggregation expression is the
  raw fact and is never rewritten** — VDA interprets it (§17).
- **Run-level verdict (INV-X1 inversion)**: `verdict/basis ∈ RunOutcome` are
  decided EXCLUSIVELY by `verification_decision_authority.evaluateRunOutcome`
  (§17). run_accounting never derives a gate verdict (the old
  `GateVerdict = PASS iff verificationComplete` derivation is removed).

## 5. Join operators (component-wise, per-unit keyed)

| Component | Join | Notes |
|---|---|---|
| RequirementDecision | assert-equal; conflict → UNRESOLVED + anomaly | run-wide decision |
| VerificationOutcome | worse-wins semilattice PENDING < SATISFIED < UNSATISFIED | precedent request_result.nim:19-36 (rvPass<rvFail<rvTimeout<rvError, sup=worse wins) |
| Consistency | OR (CONTESTED absorbing) | |
| ExecutionEvidence | OR (ATTEMPTED absorbing) | |
| SatisfactionSource | precedence-absorb FRESH > REUSED > PRE_SIEVED | |

All joins are **associative · commutative · idempotent** ⇒ wave ordering cannot affect
RunAccounting (permutation-invariant, byte-identical JSON). Conflict anomalies are
deduped so the anomaly set is order-independent too.

## 6. Historical-context facts (documented, not canonical)

1. **(a) Fail-open seam**: `closureComplete = false` + exit 0 is an **undocumented
   fail-open seam** — exit 0 ⟺ `failedCount == 0 ∧ timeoutCount == 0` only
   (`report_engine.nim:25-42`). Closure completeness is not part of the exit code.
2. **(b) Last-wave merge defect — CLOSED (DEBT#458)**: historically
   `axiom_engine.nim:933/946-948/1049-1059` lost non-final-wave `nodeReports` +
   `executionStats` (last wave wins). Phase X1 installs the canonical boundary
   (§9-§16): the wave loop accumulates per-wave reports and dispatched sets; the
   legacy report/state file/TrustCommit are pure projections of
   (CanonicalRunResult, PreRunContext). The defect is closed.
3. **(c) Legacy mixed aggregate**: legacy `completedCount = Verified + NoObligation +
   InductiveValid` mixed aggregate (`closure_evaluation.nim:66-68`). Not canonical.

## 7. Measurement source (X1)

`MeasurementSource` enum (`tools/phase_x0_accounting.nim`):

```
ProductionCanonical       = "production_canonical"        (measurementCompensated=false)
TrajectoryReconstruction  = "trajectory_reconstruction"   (measurementCompensated=true)
```

- Since X1, the merged report carries `runAccounting`/`runOutcome` (canonical
  boundary installed — DEBT#458 closed). The tool reads the accounting DIRECTLY
  from the report: `measurementSource=production_canonical`,
  `measurementCompensated=false`, `compensationSource="production_canonical"`.
- `measurementCompensated` is **derived** from the source (only trajectory
  reconstruction compensates for a missing canonical boundary).
- Pre-X1 reports (no `runAccounting` key) fall back to trajectory reconstruction
  (`logs/ax_prove_trajectory.jsonl` `skReport` records embed the per-wave report
  under `extra`) — a **temporary measurement compensation** that X1 removes for
  new runs. Output artifacts carry `measurementSource` explicitly.

## 8. Legacy projection (structural isolation)

The canonical computation must not read legacy fields. `parseLegacyClosure` is a
separate parse function reading only the merged report's `closure` block; the canonical
path receives only wave reports + eligibility. Legacy fields emitted:
`legacyCompletedCount, legacyUncompletedRequiredCount, legacyClosureComplete` — with
comments stating the mixed-aggregate (fact (c)) and last-wave (fact (b)) limitations.
Since X1, the merged report's closure is itself recomputed from the merged rows
(§11), so the legacy projection's last-wave caveat no longer applies to new runs.

## 9. CanonicalRunResult structure + INV-X1 (inverted, Plan 1)

```
CanonicalRunResult (src/verification/accounting/run_accounting.nim)
├─ RunAccounting      — 3-axis + evidence per-unit rows + canonical fields +
│                       REUSED re-verification rows/counts + raw FAIL/timeout
│                       split (X1.0 contract + Plan 1, unchanged as raw state)
├─ ExecutionEvidence  — per-wave dispatched sets + per-unit ATTEMPTED(observed);
│                       timings are ExecutionMetrics (doc-level separation only)
└─ RunOutcome         — RAW completeness projections (deriveRunOutcome) at
                        construction + verdict/basis decided EXCLUSIVELY by
                        verification_decision_authority.evaluateRunOutcome
```

`buildCanonicalRunResult(waves, eligibility, dispatchedPerWave, reuseContext)`
constructs the result: `RunAccounting` via the X1.0 reducer (join semantics
byte-identical — no new production merge implementation) with per-row REUSED
re-verification against the current reuse context, `ExecutionEvidence` from
the per-wave dispatched sets + observed rows, and `RunOutcome`'s raw
projections **derived at construction only**.

**INV-X1 (inverted)**: RunOutcome is the SOLE run-verdict authority —
`run_accounting` preserves raw state and NEVER derives a gate verdict; the
`verdict`/`basis` fields are set by NO other code path than
`verification_decision_authority.evaluateRunOutcome`. `deriveRunOutcome`
re-derives the raw projections from (RunPlanInput, RunAccounting,
ExecutionEvidence) with fail-closed consistency guards:
- `planComplete = unresolvedDecisionCount == 0 ∧ |planInput.requiredUnitIds| == requiredCount`
  (the canonical OGR REQUIRED set must match the reducer's required count);
- `executionComplete`: no REQUIRED unit NOT_ATTEMPTED **and** every DISPATCHED unit
  has an observed (ATTEMPTED) verdict row — a dispatched unit without a runtime
  verdict never reached the runtime (fail-closed execution evidence);
- `verificationComplete`: no pending/contested/unsatisfied/unresolved.
The report's `runOutcome` block is `runOutcomeToJson(construction-time raw
projections + VDA-decided verdict)` — the projection never recomputes the
verdict. The execution path (axiom_engine) assigns the VDA-evaluated outcome
once, before any serialization; every projection reads that value.

## 10. canonicalSerialize / canonicalRunDigest contract

`canonicalSerialize(runResult) → string` is a **code-level contract function**,
SEPARATE from the report JSON serializer (JCS RFC 8785 spirit):

- unit rows sorted by `unitId` (the reducer already sorts);
- per-wave dispatched sets sorted, and the dispatched set-list sorted
  lexicographically (permutation-invariant over wave ordering);
- fixed key order (`runAccounting`, `executionEvidence`, `runOutcome`);
- no timestamps / run-dependent fields — report key ordering, timestamps and CLI
  metadata cannot affect it. Doc-level presentation fields (observed rows,
  executionStats, runScalars, runtimeMeta, gates, refactor records) are excluded.

`canonicalRunDigest = sha256Hex(canonicalSerialize(runResult))` — the whole-tree
canonical hash of the RUN RESULT (not the report document).

**Fixed-key schema change (Plan 1, approved)**: the `runOutcome` block now
carries `{planComplete, executionComplete, verificationComplete, verdict,
basis, gateVerdict, reuseConditions}` (previously
`{planComplete, executionComplete, verificationComplete, gateVerdict}`) and
the `runAccounting` block gained `proofFailedCount`, `timeoutUnsatCount`,
`reuseEligibleRowCount`, `reuseRejectedRowCount` while dropping its
`gateVerdict` key (the verdict moved to the runOutcome block). **Digest
changes with this boundary change are EXPECTED and correct** (whole-tree
canonical hash; no stored expected digest exists). The report document
additionally carries `canonicalRunDigest` for auditability.

## 11. Canonical ownership matrix — legacy report keys

`renderLegacyReport(runResult, preRun, projections)` is a PURE projection. The
last-wave document is NEVER a data source; every key is derived from canonical
inputs or pre-loop data:

| Key(s) | Source | Projection function |
|---|---|---|
| nodeReports | RunAccounting (keyed union across waves) | `observedRows` (merged, sorted by unitId) |
| executionStats | ExecutionEvidence | cross-wave aggregate: nodeStats concat, depthStats concat, additive counts summed, wall/hotspot from merged (ExecutionMetrics, doc-level) |
| summary | merged rows + run-wide scalars | per-unit-aggregatable counts (verified/failed/timeout/blocked/vacuous/preSieved/cacheHit/solverInvocation/tierCounts/statusCounts) + runScalars (verifiedRatio/vsr/completionRate/netVerifiedFunctions/demotions/refactorRepaired/asi) + PreRunContext skeleton |
| closure | merged rows + cumulative verifiedSet | `evaluateClosure` called with merged `seq[OrchestrationNodeReport]` (signature unchanged) |
| crossValidation | merged request count | scope = sum of per-wave request counts |
| leanVerify | run-wide | post-loop projection (unchanged) |
| scopeObservability | cross-wave accumulation (§13.1) | `irPipelineFailures` (out-of-scope failure channel, deduped order-stable) + `discoveredBeyond` (later-wave dispatched units outside declaredRequired) — post-loop projection; never a subject-outcome input |
| diagnostics, verificationQueue, structuralBottlenecks, repairPriorityDependencies, eligibility, census, declaredRequired | **PreRunContext** (pre-loop skeleton captured BEFORE the wave loop as an immutable snapshot; NOT stored in RunResult; `declaredRequired` = §13.1 frozen declared frontier) | passthrough |
| schemaVersion | constant | `axiomReportSchemaVersion` |
| runtimeMeta | doc-level metadata | last wave's timing metadata (ExecutionMetrics) |
| runAccounting, runOutcome, canonicalRunDigest | additive canonical keys | `toJson(runAccounting)` + `runOutcomeToJson` + digest |

`renderPersist(statePath, runResult, preRun, projections)` is the state-file
projection: the pre-loop skeleton write creates the PreRunContext on disk; the
post-loop persist writes `projection(RunResult, PreRunContext)` — never the
last-wave document.

## 12. FreshExecutionObservedSet + evidence hierarchy

Naming honesty: `freshExecutionCount = |FreshExecutionObservedSet|` — NOT
"FreshExecutionSet". The observation basis for this phase is
**evidenceSource = terminal_verdict_proxy** — a runtime verdict record that
proxies a genuine solver/proof invocation (cache hits excluded).

```
Evidence hierarchy: dispatch-only < terminal-verdict-proxy < solver-observed < invocation-witness
```

Invocation-witness emission (a first-class witness record pinned to the
invocation) is an **X2 entry condition** — the current phase observes fresh
execution through terminal verdicts only.

## 13. universeDigestRef (planDigest honesty note)

The trajectory reference record (`skRunAccounting`) carries
`universeDigestRef = universeDigestStart` — the kernel-scope digest captured at
pipeline start (I-F freshness guard). It is **NOT** `planDigestRef`: the normal
`ax prove` path has NO ExecutionPlan (plans apply only to `--plan` runs), so
plumbing a plan digest into the canonical record would be forward-architecture
work and is deliberately NOT done in X1.

### 13.1 Execution Scope (frozen at run start — subject-scoped coupling severed)

Normative for every `ax prove` run. The coupling this section severs is
measured, not hypothetical: a subject-scoped run (`--project <subject>`) folded
the engine's own kernel-registry verification failures into the subject run's
persist axis (persist FAIL → exit 2) and re-admitted eligibility-excluded
units in later waves (UNRESOLVED accounting rows with no eligibility record).

**Scope freezing (start invariant).** At run start the execution scope is
fixed and immutable for the run's duration. It consists of exactly:

- **subject identity** — the source root (`--project`/CWD), resolved once;
- **the declared claim set** — the declared `--target` claims when present,
  otherwise the full subject sweep (every in-scope unit is declared);
- **the scope policy** — the eligibility classification (kernel-registry hit /
  overlay synthesis / external-candidate census) and the VKD selection policy,
  read once.

`PreparedRun` is the single in-memory carrier of this snapshot; a mid-run
re-read of the scope lock, the VKD baseline, or any scope-policy input is a
contract violation (start-snapshot unification). `universeDigestStart` (§13,
I-F freshness guard) is re-derived at closure-evaluation time over the SAME
frozen kernel scope — a digest re-derived from a re-loaded scope is not a
freshness guard. The pre-run snapshot (`PreRunContext`) carries the declared
set so the on-disk document records what the run declared.

**declaredRequired vs discoveredBeyond.** `declaredRequired` is the
transitively-required unit set precomputed at start under the frozen scope
policy (the post-eligibility declared frontier). The multi-wave discovery loop
(DiscoveryFixedPoint) is intended and stays: units that enter the accounting
universe in a later wave through the dependency fixpoint are
`discoveredBeyond`. Exactly two dispositions exist:

- **subject-discovered** — the discovered unit's dependency edge terminates in
  the declared subject: absorbed into the declared scope declaratively (the
  unit is accounted as required-discovered; no second scope class is invented);
- **out-of-scope discovery** — the unit belongs to the engine's own kernel
  registry (or any universe outside the declared subject): reported through the
  dedicated out-of-scope channel (below), never folded into the subject run's
  requirement/outcome axes.

**Frontier recomputation re-applies the frozen scope policy.** Between waves,
frontier recomputation must respect the SAME eligibility classification as the
initial selection. A unit excluded by the gate at start never re-enters in a
later wave; a later wave that admits an eligibility-excluded unit manufactures
UNRESOLVED rows with no eligibility record — a fail-closed violation, never a
satisfaction path.

**Out-of-scope failure severance (subject-scoped runs).** Verification
failures of out-of-scope units (kernel-registry units absent from the subject
universe) are severed from the subject run's outcome: they surface in the
dedicated report channel (`irPipelineFailures`), the IR batch summary and
ERROR logs — observable, never silently swallowed (§0.9 theater prohibition) —
and they do not reach the persist axis (`persistFailures` is defined by R8 as
"a promotable certificate whose canonical-vault promotion failed", which an
out-of-scope unit that produced no promotable certificate is not) nor the
run-exit rule. Full-sweep runs declare the whole subject universe: a
declared-scope failure must not be omitted.

**The exit axis stays §7; the verdict stays VDA.** The run-exit rule remains
the single §7 rule over the subject summary, and the run-level verdict remains
decided exclusively by `verification_decision_authority` (§17, INV-X1). This
section changes what feeds those axes (scope-filtered inputs), never who
decides them.

**VKD lane unchanged.** DECISION-0011 ("a *fetch* widening, not an execution
budget") stands: the VKD measurement lane samples the kernel scope regardless
of the execution scope and is not an adjudication input.

**RunAccounting alignment (no duplicate semantic state).** The reducer's unit
universe (eligibility keys ∪ per-wave nodeReport nodeIds, §1 authority) remains
the canonical projection: after scope-policy re-application, later-wave node
reports contribute only subject-discovered units (absorbed into the frozen
universe) and out-of-scope units carry their separate report channel — the
reducer gains no second universe representation and no duplicated meaning.

## 14. TrustCommit migration

`commitUniverseIntegrityAndLock` now receives
`UniverseIntegrityProjection(runResult)` — nodeReports rows
(`nodeId`/`status`/`assuranceTier`) projected from the MERGED rows, instead of
the last wave's `proofReport.orchestrationNodeReports`. This fixes wave-1
verified units never reaching the TrustCommit — presented as the natural
consequence of the canonical boundary migration (TrustCommit now reads the
canonical projection instead of the last-wave report), NOT a separate algorithm
fix.

## 15. DEBT#459 — parallel cache-hit evidence attribution (CLOSED, FIXED)

DEBT#459 (closed 2026-09-07): the parallel cache-hit row emitted by
`processOneNodeParallelBody` (`loop_depth_scheduler.nim` stage 3) carried
`status=failed` while the row's own `cacheHit` field was never assigned
(serialized `false`), so the canonical reducer classified it UNSATISFIED +
invocation-witnessed — inflating `failedCount`/`unsatisfiedCount`,
contaminating X2 regime-C (warm) economics. **X2 entry condition resolved.**

### 15.0 Reuse is not reproduction (terminology, normative)

A cache hit is a **reuse** of a prior result. It is **not** a reproduction, and the
two MUST NOT be conflated: nothing was executed on the reuse path, so a cache hit can
never stand as fresh-execution evidence (§15.1 `NOT_ATTEMPTED`; §12
`FreshExecutionObservedSet` exclusion).

Reuse becomes **authoritative** only when the prior result is **re-validated against
the current context, per read** — the five conditions of §15.3, of which condition
(d) re-reads the artifact bytes and recomputes SHA-256 on every read rather than
trusting a recorded claim. Fail-closed: any uncertainty (missing file, corrupted
JSON, schema mismatch, digest mismatch) → **cache miss → re-execute**
(`workunit_fingerprint_cas_contract.md` §6.1-§6.2).

The negative half is load-bearing and stays: **a cache is acceleration, never
evidence and never a verdict input** (`docs/spec/github_delegation_residuals.md:7`,
J3). That is NOT the claim that cache is never an execution input — cached state does
participate in execution semantics, and the paths through which it can change
verification meaning are the judgment target
(`docs/spec/ci_optimization_tcb_judgments.md` §3.1). What is forbidden is a cache
hit *asserting* an execution that did not happen.

### 15.1 Classification of a cache-hit row (canonical, both paths)

The `(status, cacheHit=true)` pair is interpreted as evidence of **REUSED
satisfaction** — a valid cache hit (re-validated per read against the current
context, §15.3(d); fail-closed by construction) is a satisfaction WITHOUT fresh
execution:

| Axis | Value | Meaning |
|---|---|---|
| VerificationOutcome | **SATISFIED** | verdict inherited from the replayed summary (same module/fn + checksum) |
| SatisfactionSource | **REUSED** | satisfaction via cache reuse (never FRESH) |
| ExecutionEvidence | **NOT_ATTEMPTED** | no fresh solver/kernel invocation on the reuse path |
| Invocation witness | never | cache hits are excluded from FreshExecutionObservedSet (§12) |

The runtime status of the row stays `orchestrationProofFailed` — cache hit ≠
kernel acceptance (P3b/C0.4 hardening: the parallel summary cache can hold
candidate-level summaries, so the row must never claim `orchestrationVerified`).
Outcome is decided by the reducer's pair mapping, not by the status string.

**Blocking scope (explicit — this is narrower than "block the witness fields").**
What is prohibited is **cache-derived state being promoted as a fresh-execution
witness**. It is NOT a prohibition on `orchestrationVerified` or on
`FreshExecutionObservedSet` as such: **genuine fresh execution MUST remain able to
set `orchestrationVerified` and to enter `FreshExecutionObservedSet`.** A rule that
blocked those writes unconditionally would reject real verification and implement
this contract wrongly. In scope, and only these: a row whose satisfaction derives
from cache reuse — `SatisfactionSource = REUSED`, including REUSED rows whose §15.3
basis is not established — never (a) counts as `orchestrationVerified`, (b) enters
`FreshExecutionObservedSet`, or (c) enters the TrustCommit verified set.

**Path symmetry (serial vs parallel):** cache-hit semantics are
path-independent — reuse never witnesses a fresh invocation and never
attributes ATTEMPTED evidence. The serial path (`loop_driver.nim:937-945`,
stage-1d) emits NO nodeReport row for cache hits (unit invisible to the
reducer: PENDING + NOT_ATTEMPTED if REQUIRED by eligibility — a structural
limitation, `loop_driver` unchanged), while the parallel path emits the
cache-hit row with `cacheHit=true`, making per-unit REUSED attributable. The
reducer mapping is identical for both: a cache-hit row classifies exactly as a
serial-style `verified + cacheHit=true` row (byte-identical unit rows).

### 15.2 Count-semantic changes + REUSED provenance rules (Plan 1)

- `runAccounting`: cache-hit rows join SATISFIED (REUSED) **only when their
  reuse record passes the 5-condition re-verification (§15.3)**; rejected or
  record-less (count-only) rows are fail-closed PENDING + anomaly (`REUSED
  basis not established for unit <uid>: <reasons>`). `attemptedCount` /
  `freshExecutionCount` are unaffected by cache-hit rows
  (`notAttemptedCount` includes them); `executedCount = attemptedCount +
  cache-hit-reused rows` (cache-hit rows ARE runtime verdict records).
- `executionStatsProjection`/`attemptedUnits`: cache-hit rows excluded from
  `attemptedUnits` — a dispatched reuse-only unit therefore fails
  `executionComplete` (fail-closed fresh-execution evidence); the dispatched-
  set guard in `deriveRunOutcome` flags such units identically.
- Report summary (`summaryProjection` + `wf_render.jsonFromOrchestrationReport`):
  cache-hit rows are counted under **`reusedCount`** / `statusCounts["reused"]`
  (new additive keys) and no longer under `failedCount` /
  `statusCounts["failed"]` — the exit-code path (`axProofShortcutExitCode`
  reads `summary.failedCount`) no longer fails warm parallel runs on reuse.
  `verificationSuccessRate` excludes cache-hit rows from numerator and
  denominator (serial path: cache hits are invisible to per-unit counts too).
  **Summary counting remains RAW telemetry** — it does not depend on the reuse
  record and is not a verdict.
- Pre-push gate (`axiom_engine.nim:531`, `allPassed = verifiedCount ==
  nodeReports.len`): unchanged — cache-hit rows keep the fail-closed status,
  never count as `orchestrationVerified`; TrustCommit likewise receives them
  as `orchestrationProofFailed` (UNIVERSE integrity keeps cache hits out of
  the verified set). Scope is REUSED-derived rows only (§15.1 blocking scope):
  a row backed by genuine fresh execution still counts as `orchestrationVerified`
  and still reaches the TrustCommit verified set.
- **FAIL 축소 (Plan 1)**: the run-level `FAIL` verdict is EXCLUSIVELY
  proof-level — `proofFailedCount ≥ 1` (a REQUIRED unit merged UNSATISFIED
  with a genuine proof-attempt failure, status=`failed`). Timeout-only
  UNSATISFIED rows stay in the raw `unsatisfiedCount`/`timeoutUnsatCount`
  aggregates (the timeout→UNSATISFIED aggregation expression is NEVER
  rewritten) and VDA interprets them as **INCONCLUSIVE** — never mixed into
  FAIL. CONTESTED / unresolved enumeration → INCONCLUSIVE as well.
- **NO_OBLIGATION conditions (Plan 1)**: PASS(NO_OBLIGATION) requires a
  non-empty universe (units ≥ 1), every unit NOT_REQUIRED
  (`requiredCount == 0 ∧ unresolvedDecisionCount == 0`), and
  `NoObligationProvenance` (the caller's evidence that the canonical
  OGR/eligibility enumeration completed over the full universe). An empty
  universe or an absent enumeration is **INCONCLUSIVE** — "0이라서 PASS" is
  forbidden.
- **GateVerdict (inverted)**: `run_accounting` no longer derives a gate
  verdict; the report's `runOutcome.gateVerdict` is a serialization projection
  of the VDA-decided verdict (`PASS` iff `verdict == PASS`, else `FAIL`).
  A warm run (all units satisfied by reuse) is `PASS(REUSED)` only when every
  reuse row's basis is established; **unconditional PASS on cache-hit rows is
  discarded** (fail-closed).

### 15.3 REUSED basis — the five conditions (who may call a replay a satisfaction)

A cache-hit row is a REUSED satisfaction iff its `reuseRecord` passes every
condition against the **current** reuse-verification context (the wiring of the
previously unwired contract `workunit_fingerprint_cas_contract.md` §6.1 —
`reusable(U) ≡ Fingerprint(U.inputs, U.contract, U.toolchain) ==
CachedFingerprint ∧ contentDigest(CachedResult) == SHA256(CachedResult)` —
at the reducer, per row; the strong CAS `canonical_cache.nim` is NOT yet wired
into the runtime — minimal conditional re-verification applies):

| # | Condition | Row/record field | Verified against |
|---|---|---|---|
| (a) | subject identity | `row.subjectFingerprint` == `record.subjectFingerprint` | the unit's CURRENT transitive source fingerprint (same fingerprint the runtime compares at cache lookup) |
| (b) | execution identity | `record.executionBundleFingerprint` == `ctx.executionBundleFingerprint` | the pinned canonical execution bundle fingerprint (`identity.nim:188`, measured by `lean_kernel_boundary.computeBundleDigest`) |
| (c) | state identity | `record.executionConfigDigest` == `ctx.executionConfigDigest` | the current execution-contract digest (`identity.nim:141`, canonical role-literal contract — the per-unit input binding is covered by (a)) |
| (d) | evidence artifact | `record.artifactRef` concrete (cert/vault/spec path) ∧ `record.contentDigest` valid 64-hex ∧ `record.artifactVerified == true` | `artifactVerified` is set by the IO-side reader on the execution path, which RE-READS the artifact and recomputes SHA-256 on every read |
| (e) | evidence validity | `record.toolchainIdentity` == `ctx.toolchainIdentity` ∧ `record.recordedStatus` terminal-verified (`verified`/`inductive_valid`) ∧ `record.leanCompilerVerified` ∧ `record.validatedAtEpoch` == `ctx.currentEpoch` | the D2 toolchain identity + the current `executionEpoch` (§15.4; wire field `ctx.currentEpoch`) — staleness: a record validated under an older identity or older `executionEpoch` is stale |

Fail-closed: any missing/mismatched component → basis NOT established → the
row classifies **PENDING** (+ anomaly) and `verificationComplete` excludes it —
**VDA does not decide PASS** on such a unit. Per-unit rule: a unit's reuse
basis is established only when ALL its cache-hit rows pass (one rejected row
poisons the unit). Count-only rows (no `reuseRecord`, as emitted by the current
parallel path `loop_depth_scheduler.nim:157-171`) are always rejected. The
failure-reason union is recorded per unit in `anomalies`.

The current context is captured once per run on the execution path
(`axiom_engine.captureRunReuseContext`): measured bundle fingerprint +
role-literal contract digest + D2 toolchain identity + derived
`executionEpoch` (§15.4). The 2-arg reducer forms use the fail-closed default
(empty context) — no record can verify.

### 15.4 `executionEpoch` vs `ciGeneration` — disambiguated naming

Two unrelated quantities are both historically called "epoch". They MUST NOT be
conflated, because exactly one of them is an identity constituent and the other must
never become one:

| Name | Definition | Identity role |
|---|---|---|
| **`executionEpoch`** | the reuse-validation semantic epoch — `validatedAtEpoch == ctx.currentEpoch`, where `ctx.currentEpoch = sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)` (`axiom_engine.captureRunReuseContext`; condition (e), `run_accounting.nim`) | **identity constituent** of condition (e) — moves exactly when the execution closure moves |
| **`ciGeneration`** | the CI cutover generation — the `.github/workflows/` topology generation produced by the AGENTS.md §2.5 freeze → record → tombstone → new generation → atomic binding update protocol (`docs/agents/ci_epoch_cutover.md`); the frozen marker for the current generation is the tag `ci-epoch-pre-authority-structure-2026-10-04` (`docs/evidence/ci_epoch_record_2026-10-04.md` §1) | **never** an identity constituent — a cutover generation number must not be able to leak into a cache key, a reuse record, or a verdict identity |

**Wire-field stability**: the reported/persisted field names `currentEpoch` and
`validatedAtEpoch` are **compatibility-stable** and are NOT renamed by this section.
`executionEpoch` is the *concept* name used in prose; code and wire keep the existing
identifiers unless a separate, explicitly-bound migration says otherwise. Renaming a
wire field is a schema change, not a vocabulary correction.

*Landed state observed 2026-10-04*: the struct field is still `currentEpoch`
(`run_accounting.nim` `ReuseVerificationContext`), the record read field is still
`validatedAtEpoch`, and new identifiers introduced alongside this correction use the
`executionEpoch` name (e.g. the context dump key `executionEpochKey`). This section is
what authorises that split — it does not itself migrate any field.

**Direction of the guarantee**: a new `ciGeneration` MUST leave every
`executionEpoch`, every execution-contract digest, and every verdict identity
bit-identical unless the execution closure itself changed. Conversely an
`executionEpoch` change MUST NOT be interpretable as a CI topology generation change.
The general form already exists — `docs/spec/merge_admission_controller.md` §2b:
"Queue-journal epoch and dispatch depth are NEVER part of content identity"; this section
fixes the vocabulary that made that rule ambiguous, and adds the queue-journal epoch
disambiguation used there.

## 16. PRUNE #1 — CI shared canonical proof artifact (CI-graph prune, no semantics change)

**The duplication (verified, removed):** CI `verify-integration` ran TWO
identical `bin/ax prove --target normalizeMaxWorkers` computations per run:

1. `verify-contract-release-e2e-full` ("Release product E2E (G7)", Makefile) —
   producer; runs the prove, captures `report --json`, asserts schema, exactly-1
   target node, report-exit↔summary consistency, cert verify, state file, 6-key
   report↔state equality, binary-hash stability.
2. `verify-contract` fan-out g7 = `verify-contract-release-e2e` (non-full,
   Makefile) — re-ran the identical prove (warm cache), asserting exit codes only.

Both proves were input-identical while the target cert stays non-promotable
(prove never reads `logs/ax_proof_state.json` — write-only; identical CI-purged
read-vault data); if the cert ever promoted, run 2 would diverge (warm). The
shared-artifact contract removes that conditionality entirely — run 2 no longer
exists.

**The shared-artifact contract ("prove once → artifact → both consumers read"):**

- **Artifact paths:** `logs/verify_contract_e2e_report.json` (canonical report,
  persisted by the producer) + `logs/ax_proof_state.json` (persisted canonical
  state — written by the prove itself via persistAxProofState). `logs/` is
  gitignored; artifacts are per-run ephemeral, and same-run by construction
  within one CI job (producer step immediately precedes the fan-out).
- **Producer:** `verify-contract-release-e2e-full` — captures `REPORT`, persists
  it to the artifact, and keeps ALL its existing assertions unchanged (it
  remains the strongest gate). Report-exit consistency is asserted only here:
  the saved artifact carries no prove exit code.
- **Consumer:** `verify-contract-release-e2e-consume` (fan-out g7) — fail-closed
  guard: BOTH artifacts must exist; if either is missing it falls back to the
  non-full e2e prove path, so local standalone `make verify-contract` still
  works. Consumer assertions on the saved artifact mirror the producer's jq
  checks: (a) `schemaVersion=="axiom.report.v1"`; (b) **exactly-1 row per
  requested `--target` node** — the `--target` contract invariant "exactly the
  selected target node(s)", generalized to ∀ requested target: 1 row (per-node
  assertion in `axiom_engine.nim`); (c) 6-key report↔state equality (same jq as
  the producer). g7's unique smokes stay: release rebuild of `bin/ax`, `ax scope
  hash`, `ax status --json`.
- **Outcome:** the `--target normalizeMaxWorkers` prove now executes ONCE per CI
  run. No cache algorithm or semantic verification behavior changed — this is a
  CI-graph prune only; gate preservation and coverage are unchanged (producer
  assertions intact, g7's checks moved onto the shared artifact).

---

## 17. Run-level verdict decision tree (Plan 1 — Authority Unification)

Raw execution state → `verification_decision_authority.evaluateRunOutcome`
(the SOLE run-verdict writer) → `RunOutcome{verdict, basis}`:

```
raw state (RunAccounting + universe/REUSED evidence)
        │
        ▼
┌────────────────────────────────────────────────────────────────────┐
│ VDA decision tree (precedence top-down; ONLY VDA may produce PASS) │
├────────────────────────────────────────────────────────────────────┤
│ 1. proofFailedCount ≥ 1           → FAIL        basis NONE          │
│    (proof-level failure only: counterexample/UNSATISFIED after     │
│     a genuine attempt — status=failed rows)                        │
│ 2. timeoutUnsatCount ≥ 1          → INCONCLUSIVE (raw timeout —     │
│    the accounting's timeout→UNSATISFIED aggregation is never       │
│    rewritten; VDA interprets it — never mixed into FAIL)           │
│ 3. pendingCount ≥ 1 ∧ attempted==0 ∧ fact-gate → BLOCKED           │
│ 4. pendingCount ≥ 1               → INCONCLUSIVE                   │
│    (attempted-but-unresolved: not_verifiable/vacuous/skipped, or   │
│     reuse rows whose REUSED basis was not established — VDA does   │
│     NOT decide PASS on them)                                       │
│ 5. contestedCount ≥ 1             → INCONCLUSIVE (consistency      │
│    failure — never satisfying)                                     │
│ 6. unresolvedDecisionCount ≥ 1    → INCONCLUSIVE (enumeration      │
│    incomplete)                                                     │
│ 7. requiredCount ≥ 1 ∧ fresh≥1    → PASS  basis PROVEN             │
│    (obligation ≥1 ∧ KAA verified evidence exists)                  │
│ 8. requiredCount ≥ 1 ∧ reused≥1   → PASS  basis REUSED             │
│    (REUSED = provenance/basis only: VDA verified the per-row       │
│     5-condition basis (§15.3) and decides the final PASS — the     │
│     condition set is carried on the outcome)                       │
│ 9. units ≥ 1 ∧ all NOT_REQUIRED ∧ NoObligationProvenance           │
│                                   → PASS  basis NO_OBLIGATION      │
│    ("0이라서 PASS" 금지 — empty/absent enumeration → INCONCLUSIVE)  │
│10. otherwise                      → INCONCLUSIVE (fail-closed)     │
└────────────────────────────────────────────────────────────────────┘
```

- `gateVerdict` in the report's `runOutcome` block is a serialization
  projection: `PASS` iff `verdict == PASS`, else `FAIL`.
- The unit-level analogue stays: only VDA may produce `vdVerified`
  (`evaluate(KAA, Policy)`); only VDA may produce run-level `vrPass`
  (`evaluateRunOutcome`). Both are enforced by the
  evidence-truth-boundary-gate symbol table (`makeVerifiedDecision`/
  `vdVerified` + `makeRunOutcomeVerdict`/`vrPass`).

### 17.1 Read-path binding precondition (restored state)

A persisted run STATE is a verdict carrier on the read path (`ax report`): a
different process re-reads it, possibly from a cache that outlived the run that
produced it. The read-time re-validation (`revalidateRestoredStateIdentity` —
§15.3 conditions (b)(c)(e) applied to the state as a whole) and the demotion of
REUSED satisfiations it cannot establish (`demoteRestoredReusedUnits`) are pure
projections in `run_accounting`; the DECISION they feed belongs to
`verification_decision_authority.evaluateRestoredStateRunOutcome`, because §9
INV-X1 admits exactly one run-verdict writer. No read path may assign
`verdict`/`basis`/`gateVerdict` itself.

**The precondition.** §17's PASS rules (7 `PROVEN`, 8 `REUSED`, 9
`NO_OBLIGATION`) additionally require the state to be **bound to the current
execution identity** (`revalidateRestoredStateIdentity(...).established`):

- rules 1-6 and 10 are **unchanged**. A proof-level FAIL, a timeout, a PENDING
  unit, a contested or unresolved enumeration are facts of the run itself and
  are not identity-dependent — an unbound envelope must never obtain a MORE
  favourable verdict by hiding them.
- the PASS rules require binding. An unbound state cannot assert a PASS: the
  satisfaction it records was established under an identity that is no longer
  provably current. This is §15.0's "a cache is acceleration, never evidence
  and never a verdict input" applied to the state as a whole.

**The binding-sensitive case, normatively.** A state with **zero reused rows**
whose envelope **cannot be bound** (`demoted == 0` ∧ re-validation failed) is
**INCONCLUSIVE**, never PASS — including when every unit was satisfied by a
genuine fresh execution, where §17 rule 7 reads `PASS basis PROVEN` on BOUND
state. `demoted == 0` is a statement about the ROWS (nothing was
cache-derived, so the demotion is silent), never about the IDENTITY; rule 7 is
decided on bound state and the unbound reading of that same state is rule 10
(fail-closed). The verdict is INCONCLUSIVE and not BLOCKED because BLOCKED has
its own §17 rule 3 terms (PENDING ∧ nothing attempted ∧ fact-gate), which an
unbindable envelope does not establish — BLOCKED stays reachable on its own
terms on the read path. `gateVerdict` therefore projects to FAIL.

A restored state can never claim PASS(NO_OBLIGATION): rule 9 requires
universe/OGR enumeration provenance, which the persisted document does not
carry.

**Read-path invariants.** The demotion is total: applied to an ESTABLISHED
re-validation it is a no-op, so the established path returns the document
exactly as recorded and a genuinely current fresh run still reads
`PASS basis PROVEN`. The RAW completeness projections are re-derived from the
re-hydrated rows rather than read back from the document, so a demoted state
cannot assert `verificationComplete` from a stale stored copy. Fail-closed
re-hydration: a missing or malformed field reads as its zero value and an
unrecognized axis string reads as that axis's bottom value.
