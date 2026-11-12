# nimtry 12 class-(ii) production violations — design manifest (Track-B step 1) — 2026-10-16

**Status: DESIGN MANIFEST ONLY.** This document authorizes and records no code change. It
partitions the 12 production nimtry violations (BUDGET#004, classified in
[docs/evidence/nimtry_drift_23_classification_2026-10-16.md]) into independently
landable remediation slices, each with its own evidence, root-cause class,
trust-surface obligations, frozen-contract list, and validation set. Implementation is
follow-up work, one slice per PR (AGENTS.md §0.12: contract precedes implementation;
§2.2: scope of THIS slice is the manifest alone).

- **Workstream**: `docs/nimtry-12-design-manifest` — dedicated worktree off fresh
  `origin/main` `4484fa09e` (MERGE 4484fa09e = PR #868).
- **Source data**: PR #857 TASK B classification (`c606c4373`, 2026-10-16) — re-derived
  against current main in §0 below.
- **Rule names / limits** cited below are the nimtry tool's own output
  (`src/gate/nimtry/` is the rule SSOT; the baseline protocol is v2 fingerprint-anchored
  — `src/gate/nimtry/nimtry_cli.nim`).

---

## 0. Re-derivation record (baseline → current, 2026-10-16)

Commands (per the documented report path, built from this worktree's source):

```
make bin/nimtry
./bin/nimtry src/ --diff-baseline        # New: 19 / Resolved: 7 / Stable: 4156
./bin/nimtry src/                        # EXIT=1 — FAIL: 7 new ERROR violations (all class (i) fixtures)
```

**Deltas vs the 2026-10-16 snapshot: ZERO metric drift.** The live enumeration at
`4484fa09e` is byte-identical to the classification's (New 19 / Resolved 7 / Stable
4156; all 12 class-(ii) metrics unchanged). Machine cross-check:
`git log c606c4373..4484fa09e` touches **none** of the five carrying files — the
post-snapshot landings (G2 admission-check restructure, P3 wrappers, PRs #865–#868)
did not modify them. Only line anchors shifted relative to the *baseline* snapshot
(the 2026-10-14 baseline predates the classification too):

| # | Rule (nimtry) | File | Baseline anchor | Current (tool, 2026-10-16, @4484fa09e) | Δ |
|---|---|---|---|---|---|
| V1 | SOLID soc-surface-area | src/cli/merge_cli.nim | 58 exported functions | **60 exported functions** (layer cli max 20) | +2 |
| V2 | SOLID soc-surface-area | src/cli/merge_cli.nim:1886 | collectAdmissionFacts 79 SLOC (@:1813) | **84 effective SLOC** (max 50) | +5 |
| V3 | SOLID soc-surface-area | src/infrastructure/external_ir_materializer.nim:272 | (none — post-baseline item) | **materializeExternalIR 61 effective SLOC** (max 50) | new |
| V4 | SOLID solid-ocp | src/infrastructure/external_ir_materializer.nim | (none) | **7 case branches, 0 registry calls** [register, registerImpl] | new |
| V5 | SOLID soc-surface-area | src/verification/batch_uap/loop_depth_scheduler.nim:133 | processOneNodeParallelBody 196 SLOC (@:129) | **200 effective SLOC** (max 50) | +4 |
| V6 | SOLID soc-surface-area | src/verification/batch_uap/loop_depth_scheduler.nim:398 | runParallelDepthBatchUap 194 SLOC (@:390) | **196 effective SLOC** (max 50) | +2 |
| V7 | SoC soc-surface-area | src/verification/batch_uap/loop_driver.nim | 58 imports | **59 imports** (layer verification max 30) | +1 |
| V8 | SOLID soc-surface-area | src/verification/batch_uap/loop_driver.nim:356 | stage2Budget 252 SLOC (@:349) | **267 effective SLOC** (max 50) | +15 |
| V9 | SOLID soc-surface-area | src/verification/batch_uap/loop_driver.nim:729 | runBatchUapOrchestration 566 SLOC (@:707) | **588 effective SLOC** (max 50) | +22 |
| V10 | PURITY-new-code-must-be-func | src/engine/profiler.nim:26 | (module has ZERO baseline entries) | **new proc** `gitHeadCommit` in non-I/O module | new |
| V11 | PURITY-new-code-must-be-func | src/engine/profiler.nim:36 | (none) | **new proc** `leanToolchainRef` in non-I/O module | new |
| V12 | PURITY-new-code-must-be-func | src/engine/profiler.nim:47 | (none) | **new proc** `existingMeasurements` in non-I/O module | new |

The 7 `Resolved` fingerprints are the superseded predecessor readings of exactly the
rows above (58 exports / 79 SLOC / 196 / 194 / 58 imports / 252 / 566) — no stale
baseline entries exist (verified against `data/nimtry_baseline.json`, total 4163,
created 2026-10-14). The remaining 7 NEW items are the class-(i) fixture ERRORs
(`tests/fixtures/workflow_lane_guard` ×2 @3fb37fd12/PR #851, `workflow_poison` ×5
@a35708fb5) — governed by the sequence rule in §15, not by this manifest's slices.

---

## 1. V1 — merge_cli.nim: 60 exported functions (58→60, max 20)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/cli/merge_cli.nim has 60 exported functions (layer cli max 20)`; baseline anchored 58 (`data/nimtry_baseline.json` id `5dbec1b4…`).
- Grep verification: 60+ `proc X*` / `func X*` declarations spanning :547–:3129, from
  `pathMatchesGlob*` through `mergeCli*`. Importers (no re-exports exist):
  `src/cli/action_interpreter_cli.nim`, `src/cli/landing_cli.nim`, and 4 test files.

### Root-cause class
**public-interface over-exposure (export reduction candidate).** Reading the export
list against cross-module usage: **30 exported symbols have zero references outside
merge_cli itself** (src/, tools/, and tests/ all scanned):
`parseTrustSurfaceJson, closurePathFromLine, qualificationName, isCoreSourcePath,
layerStatusName, layerVerdictName, unknownLayerFacts, extractImportTargets,
judgeCoreFileImports, layerAdmissibilityVerdict, firstLayerViolation,
trustSurfaceOutcome, loadJson, checkedStr, checkedInt, getPrFiles,
getChangeGraphFacts, fetchFileAtRef, parseLayerPairRegistry,
collectLayerAdmissibility, collectVaultCertFacts, logMergePublish, logMergeAdmission,
parseMergeSuccess, requestGitHubPut, observePullState, classifyMergeFailure,
resolveMergeShapeLocal, runMergeCli, runMergeActuatorCli`. The `*` markers are
historical, not consumed surface — the real external contract is `mergeCli`,
`collectAdmissionFacts`, `MergeAdmissible`, `dryRunExit`, the rotation pure family
(`adjudicateRotation`, `rotationAllowlistOk`, `pinClosureLineSet`,
`parseDerivedSet`, …) consumed by `action_interpreter_cli.nim`, and the trailer/actuator
surface consumed by `landing_cli.nim` + tests.

### Trust-surface status
**TRUST-SURFACE MEMBER — ROT companion ceremony required for any change.**
`config/trusted_writer_set.json` `trustedCheckerTreeClosure` pin:
`"src/cli/merge_cli.nim": 4519a59320c2a290b03b16a9f8582dff0bef2345` (876-member
closure). Independently re-derived with the closure derivation authority:
`tools/ci/derive_checker_closure.nim --tree <HEAD tree>` → 876 members, merge_cli
present, live blob `git hash-object` == pin (0 drift at this base).

### Proposed remediation sketch (design only)
- Slice S3 (§13): unexport the 30 internal-only symbols (drop the `*`), plus retire
  dead exports if any prove unused internally. Purely mechanical; zero behavior
  change; zero signature change.
- Frozen contracts each change must not alter: the pure admission predicate family —
  `MergeAdmissible` verdict vocabulary (`mergeGo` / `mergeAborted` + reason codes
  `TRUST_SURFACE_MODIFIED`, `TRUST_SURFACE_INCOMPLETE`, `ROT_UNSPECIFIED`,
  `ROT_OLD_PIN`, `ROT_ALLOWLIST`, `ROT_NEW_PIN`, `NO_CERT`, `STALE_BASE`;
  merge_cli.nim:1113–1146), `adjudicateRotation` fixed failure ladder
  (Amendment F, merge_cli.nim:752–838: ③ old-anchor single deny `ROT_OLD_PIN`,
  ④ candidate-delta classification, ① allowlist `ROT_ALLOWLIST`), and
  `dryRunExit` code mapping (`TRUST_SURFACE_MODIFIED → 0` policy routing).
- Pinning regression tests: `tests/cli/test_merge_cli.nim` (123 tests —
  `MergeAdmissible` + `adjudicateRotation` pure predicates),
  `tests/cli/test_merge_cli_trailers.nim`,
  `tests/cli/test_merge_admission_candidate.nim`. Validation = these suites green +
  `bin/nimtry src/ --diff-baseline` shows V1 resolved (≤20 exports).
- Regression risk: LOW (visibility-only), but the file is a closure member → each
  landing passes the ROTATION path (§14 ceremony).

## 2. V2 — merge_cli.nim: collectAdmissionFacts 84 SLOC (79→84, max 50)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/cli/merge_cli.nim:1886 function collectAdmissionFacts spans 84 effective SLOC (max 50)`; baseline 79 @:1813 (id `3626da2c…`).
- Read verification: `proc collectAdmissionFacts*` :1886–:2044 — one proc that
  sequentially fetches and assembles **8 fact sources**: PR JSON (:1921), PR files
  pagination (:1935), trust-surface matching (:1942–1950), rotation/closure inputs
  (:1982–1992), vault-certificate facts (:1973–1980), layer admissibility (:1999),
  ChangeGraph facts (:2003), certificate-continuity facts with the `--cert` artifact
  pre-bind branch (:2014–2028) — then assembles `AdmissionFacts` (:2030–2043).

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** The proc is legitimately an
I/O-boundary orchestrator (`{.axiomEffect: IOEffect.}`), but pure decision/computation
is inlined into it: the trust-surface match loop over files (:1946–1950), the
changed-files set computation with rename sources (:1960–1965), and the artifact
pre-bind eligibility decision (:2014–2028). These are extractable as pure helpers
(take the facts in, return the decision), leaving the proc a thin sequencer of
per-fact collectors — several of which already exist
(`collectVaultCertFacts`, `collectRotationInputs`, `collectLayerAdmissibility`,
`getChangeGraphFacts`, `collectCertificateContinuityFacts`).

### Trust-surface status
**TRUST-SURFACE MEMBER** (same closure pin as V1) — ROT companion ceremony required.

### Proposed remediation sketch (design only)
- Slice S4 (§13): extract pure helpers — `computeChangedFiles(files): seq[string]`,
  `matchTrustSurfaceHits(files, surface): seq[TrustSurfaceHit]`,
  `admitArtifactPreBind(certPath, headSha): Option[CertificateContinuityFacts]` —
  and, if still over 50 SLOC, group the remaining sequential fetches behind one
  internal `gatherAdmissionSnapshot` fan-out. No signature change to
  `collectAdmissionFacts`; callers unchanged.
- Frozen contracts each change must not alter (all documented in the proc's own
  header, :1887–1917): the **event-frozen base anchor** — `eventBaseSha` is the ONLY
  base recorded; the live `pulls/N` base.sha is deliberately never read (STALE_BASE
  false-deny regression, measured 2026-10-04 ≈247 min wasted CI); the **ADR-0032
  preflight venue switch** (`effectiveCertRequired(preflight)`, canonical path keeps
  `certRequired = true` fail-closed); the **ADR-0022 §4 artifact handoff** — a
  pre-bind verified against THIS head replaces the ledger scan, any pre-bind failure
  falls back to the scan, denial stays fail-closed at `bindCertificateSource`;
  phase-attribution stays stderr-only (never enters dry-run JSON/journal/certificate);
  each logical fact source fetched exactly once; run-level input failures RAISE
  (fail-closed), verdict-level facts bind UNKNOWN.
- Pinning regression tests: `tests/cli/test_merge_cli.nim` (fact-shape and predicate
  pins), `tests/cli/test_merge_admission_candidate.nim`, plus the e2e dry-run gate
  (`make verify-contract` family) for the journal projection. Validation = suites
  green + V2 resolved in diff mode.

## 3. V3 — external_ir_materializer.nim: materializeExternalIR 61 SLOC (new)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/infrastructure/external_ir_materializer.nim:272 function materializeExternalIR spans 61 effective SLOC (max 50)`. No baseline predecessor (post-baseline growth fingerprint; last touch 6d016b5be).
- Read verification: `proc materializeExternalIR*` :272–:403 — a 6-phase pipeline
  (resolver→content :303–308; parse :311; discovery + fail-closed unsupported check
  :316–328; ambiguity :330–331; canonical IR + axiom-spec ingestion :334–357;
  binding-inventory observation + completeness evidence :359–392) ending in artifact
  persistence `saveEvidenceArtifact` / `saveInstantiationWitnesses` :387–392.

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** The pipeline core is pure and
deterministic (parse → discover → translate → observe), but the proc mixes in I/O
persistence (`evidence_artifact_io` saves at :388–392) and the I/O-adjacent resolver
call. Extracting the persistence to the caller (or to a thin I/O wrapper around a pure
`materializeExternalIRCore`) both fixes the SLOC surface and restores the module's
declared contract ("this module performs NO disk I/O" — :279–281 refers to source
location; the evidence-artifact saves are the actual disk I/O present).

### Trust-surface status
**TRUST-SURFACE MEMBER — ROT ceremony required.** Closure pin
`b62146641789bde1dca8425373565bd47dbfa509`; derive_checker_closure `--tree` confirms
membership; 0 drift at this base.

### Proposed remediation sketch (design only)
- Slice S2 (§13): split into pure `materializeExternalIRCore(symRef, source): tuple[outcome, entry, evidence, irDigest]` (phases 2–6 computation) + a thin I/O shell that resolves content and persists artifacts. Persistence ORDER must stay: artifact key computed from `serializeIRFuncDef` digest, save BEFORE returning `moMaterialized` (replay depends on it, WP4-j.4).
- Frozen contracts each change must not alter: the `MaterializationOutcome` enum
  semantics — `moUnsupportedDeclKind` is distinct from `moNotFound` (an existing
  symbol must never be reported absent); fail-closed ordering: unsupported-kind check
  BEFORE ambiguity check (:320–331); resolver owns source location, **no CWD fallback**
  (WP4-a B-5b, :302–308); ambiguity is fail-closed (first-match never adopted);
  artifact key MUST equal the runner cache scheme `computeDeterministicCasKey(serializeIRFuncDef(...))` (:385–387); lossy spec translation → existing-but-untranslatable, never a silently spec-less candidate (:340–357).
- Pinning regression tests: `tests/unit/external_ir_materializer_test.nim` T1–T9 —
  T1 materialize→`moMaterialized`; T2 overloads→`moAmbiguousOverload`; T4
  **digest equality** with registered-style IR; T5 resolver cache vs subject-rooted
  disk resolver → identical `irSerialized`, no CWD fallback; T8 determinism/order
  independence. Validation = suite green + V3/V4 resolved.

## 4. V4 — external_ir_materializer.nim: solid-ocp (7 case branches, 0 registry calls)

### Evidence
- Tool: `[warning] SOLID — [solid-ocp] src/infrastructure/external_ir_materializer.nim has 7 case branches but 0 calls to registry functions [register, registerImpl]; consider using registry/dispatch pattern for OCP compliance`.
- Read verification: the module dispatches over closed syntactic sets via `case`:
  `findAllFuncDefsP` name-extraction `case head.kind` of `{nkIdent, nkSym, nkPostfix}`
  (:132–138) and `extractAxiomSpecP` `case name` of `{"smt","lean","pre","post"}`
  (:198–207) — together the 7 branches the tool counts. The SSOT comment
  (:66–73) documents WHY `ProcDefKinds` is inlined (import-encapsulation:
  `core/parsers/` is an InternalPath; the `src/infrastructure/` exemption list covers
  only core/contracts, core/topology, core/trusted).

### Root-cause class
**dependency-direction violation (inversion candidate).** The module owns a private
copy of a taxonomy it does not control (the SSOT lives in the encapsulated
`core/parsers/`), and new declaration kinds require editing this module — the OCP
failure mode. The inversion is NOT "import the InternalPath" (that would trade an OCP
warning for an encapsulation violation); it is a registry seam: a per-kind handler
table (kind → translator/reasoner) that the kinds-aware layer populates, with this
module consuming the registry instead of hard-coding branches.

### Trust-surface status
**TRUST-SURFACE MEMBER** (same pin as V3) — ROT ceremony required.

### Proposed remediation sketch (design only)
- Slice S2 (§13, same PR as V3 — same file, same regression suite): introduce a
  minimal handler registry in an allowed layer (e.g. `core/trusted/`), register
  per-`TNodeKind` name-extraction and per-pragma-tag spec extraction; keep
  `DefKindOrder` canonical ordering so reason strings stay deterministic; the
  inlined-set SSOT comment is updated to point at the registry as the sync point.
- Frozen contracts: identical set as V3 (outcome enum, fail-closed ordering, digest
  scheme, no-CWD-fallback) — T1–T9 must stay green unchanged; in particular T4 digest
  equality pins that registry dispatch does not perturb translation output.
- Regression risk: MEDIUM — touches discovery, the module's core function; mitigated
  by the module being explicitly non-canonical ("experiment-only: not canonical
  execution path", :5), so blast radius is the external proof candidate pipeline only.

## 5. V5 — loop_depth_scheduler.nim: processOneNodeParallelBody 200 SLOC (196→200)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/verification/batch_uap/loop_depth_scheduler.nim:133 function processOneNodeParallelBody spans 200 effective SLOC (max 50)`; baseline 196 @:129.
- Read verification: :133–:364 — the 9-stage parallel worker body: S1 request match
  (:142), S2 node-id parse (:152), S3 summary cache (:155–176), S4 type-directed proof
  (:179–202), S5 pre-sieve interceptor (:205–227), S6 UAP request build (:230–240),
  S7 gas/entropy/per-unit budget (:248–280), S8 spacer bypass (:286–316), UAP pipeline
  run + S9 final report (:319–364).

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** The stage *engines* are already
delegated (tryTypeDirectedProof, runPreSieveStage, buildUapRequestWithDeps,
trySpacerBypass, runUniversalAcceptancePipeline); what bloats the body is inline
result-assembly — every stage hand-constructs `OrchestrationNodeReport` /
`FinalReportCertInput` / `FunctionVerificationSummary` literals with the fail-closed
status semantics embedded as literals. Extracting per-stage verdict→report assembly
into pure helpers (`blockedReport`, `cachedReusedReport`, `candidateTypeDirectedReport`,
`preSievedReport`, `budgetExhaustedReport`, `spacerCertInput`, …) collapses the body
below the limit without touching stage order or semantics.

### Trust-surface status
**TRUST-SURFACE MEMBER — ROT ceremony required.** Closure pin
`14b14a3ce6b4827fa435cca08825238b182acd60` (derive_checker_closure `--tree`
confirms; 0 drift).

### Proposed remediation sketch (design only)
- Slice S6 (§13): pure report-assembly extraction, stage order untouched.
- Frozen contracts each change must not alter (the comments are the pins): **P3b
  fail-closed candidate-vs-kernel boundary** — cache hits and type-directed proofs are
  candidate evidence, never kernel acceptance (`orchestrationProofFailed` status even
  on cache hit, :162–176, :183–196); DEBT#459 `(status, cacheHit=true)` → REUSED
  satisfaction interpretation in `run_accounting.nim`; deterministic gas/rlimit
  exhaustion → `orchestrationProofFailed` vs wall-clock hang-guard →
  `orchestrationTimedOut` (:268–280); spacer path sets status `orchestrationVerified`
  with `certInput.kernelVerified = false` (:295–314) — the C0.4 accounting pair.
- Pinning regression tests: `tests/unit/selection_independence_test.nim` (scheduler
  consumer pins), `tests/unit/batch_uap_orchestrator_test.nim` (orchestration-level),
  `tests/unit/phase_x10_accounting_test.nim` (DEBT#459 cache-hit REUSED attribution,
  :35). Validation = suites green + V5/V6 resolved.

## 6. V6 — loop_depth_scheduler.nim: runParallelDepthBatchUap 196 SLOC (194→196)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/verification/batch_uap/loop_depth_scheduler.nim:398 function runParallelDepthBatchUap spans 196 effective SLOC (max 50)`; baseline 194 @:390.
- Read verification: :398–:594 — 5 phases: pending-item filtering with the DEBT#415
  stampede guard (:419–447), sequential transitive-fingerprint pre-computation
  W3-F (:449–456), read-only context assembly W3-E (:458–477), thread+Channel parallel
  execution vs sequential fallback (:479–527), deterministic index-ordered merge and
  report application. 19-parameter signature.

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** Pure planning (filtering,
fingerprint pre-computation, context assembly) is interleaved with concurrency
mechanics (thread spawn, shared-heap channel allocation, join). Extract the pure
planning phase into a `DepthBatchPlan` builder and the mechanics into a small
parallel-executor helper; the orchestrator proc reduces to plan → execute → merge.

### Trust-surface status
**TRUST-SURFACE MEMBER** (same pin as V5) — ROT ceremony required.

### Proposed remediation sketch (design only)
- Slice S6 (§13, same PR as V5): `buildDepthBatchPlan(...): DepthBatchPlan` (pure) +
  `runDepthBatchWorkers(plan): seq[ParallelNodeResult]` + index-ordered merge. A
  parameter object replaces the 19-parameter signature internally; the public proc
  signature is preserved (loop_driver imports it).
- Frozen contracts: W3-F — fingerprints computed once on the main thread; shared
  state/Tables/caches are NOT handed to workers under `--mm:arc --threads:on`;
  W3-E source-content cache pre-seed; deterministic merge by taskIndex (arrival order
  never leaks into results); cert writes NEVER happen in workers (only `certInput`
  returns; main thread writes); DEBT#415 guard `pendingItems.len >= requests.len`
  break; workerCount ≤ 1 → sequential fallback, identical results.
- Pinning regression tests: same family as V5
  (`tests/unit/selection_independence_test.nim`, `tests/unit/batch_uap_orchestrator_test.nim`).
  Validation = suites green under default AND `AXIOM_PROVE_WORKERS>1` where the suite
  supports it, plus V6 resolved.

## 7. V7 — loop_driver.nim: 59 imports (58→59, max 30)

### Evidence
- Tool: `[warning] SoC — [soc-surface-area] src/verification/batch_uap/loop_driver.nim has 59 imports (layer verification max 30)`; baseline 58. (Separately, the baseline-anchored ERROR
  `[soc-layer-imports] loop_driver.nim:3:11 imports from forbidden layer cli:
  cli/selection_state` remains — it is a pre-existing anchored item, not one of the
  12, but its remediation is the same slice S5 and it is the dependency-direction
  component of this import surface.)
- Read verification: :3–61 — 59 import statements spanning std, core, sieve,
  infrastructure, verification, and engine layers, plus two re-exports (:63–64). The
  breadth is the monolith's shadow: the module hosts IR acquisition, budget, spacer,
  UAP dispatch, parallelism, counters, and cert promotion wiring simultaneously.

### Root-cause class
**dependency-direction violation (inversion candidate).** The one materially
direction-violating edge is `import cli/selection_state` (:3) — a verification-layer
module importing a presentation-layer (`axiomLayer "presentation"`) module. Grep
verification: loop_driver uses exactly **one** symbol from it,
`computeRelaxedThreshold(stallCount)` at :872 — a pure
`func computeRelaxedThreshold*(stallCount: int): float`. The import breadth beyond
that edge shrinks mechanically as S7 (V8/V9 decomposition) lands and phase modules
take their imports with them.

### Trust-surface status
**TRUST-SURFACE MEMBER — ROT ceremony required.** Closure pin
`48137e29f6f1185f924e98294aacf5d59bbab919` (derive_checker_closure `--tree` confirms;
0 drift).

### Proposed remediation sketch (design only)
- Slice S5 (§13): move the pure stall-threshold math to a core-layer module (e.g.
  `core/sorter/` or a small `core/selection/` math module); `cli/selection_state.nim`
  re-exports it for its cli consumers (`wf_runners`, `wf_planning`,
  `axiom_engine` — all cli-layer, unaffected); loop_driver imports the core module.
  This removes the forbidden edge (the anchored ERROR) and does not increase import
  count (net −1 import). Optionally fold `computeRelaxedThreshold`'s remaining cli
  consumers onto the new home in the same slice.
- Frozen contracts: `computeRelaxedThreshold` semantics (stall-count → relaxed
  threshold float) are pinned by `tests/unit/selection_*_test.nim`
  (`selection_engine_test.nim`, `selection_independence_test.nim`,
  `selection_report_determinism_test.nim`, `selection_digests_test.nim`); the layer
  boundary itself is enforced by the import-encapsulation/layer gates
  (`check-layer-enforcement`, `check-layer-negative`). Validation = those suites +
  layer gates green + V7 resolved.

## 8. V8 — loop_driver.nim: stage2Budget 267 SLOC (252→267)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/verification/batch_uap/loop_driver.nim:356 function stage2Budget spans 267 effective SLOC (max 50)`; baseline 252 @:349.
- Read verification: :356–:646 — Stage 2 of the typestate pipeline: IR-result
  short-circuit classification (:370–415+ — canonical-success terminal branch
  S2 rev.4, no-obligation skip, obligation-verdict branches), Stage 2a gas/budget
  (:543), Stage 2b spacer bypass (:584), Stage 2c UAP pipeline with timeout guard
  (:596). Each branch hand-builds a full `BudgetedPayload` literal.

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** The short-circuit
classification (given an `IrPipelineResult`, decide terminal-skip vs proceed, and
which `skipReason`/`obligationVerdict`/`evidence` to carry) is a pure decision
function embedded in the I/O stage; each decision's `BudgetedPayload` construction is
pure assembly. Extracting `classifyStage2ShortCircuit(irResult): Option[BudgetedPayload]`
(pure) and the payload builders collapses the body; Stage 2a/2b/2c remain as the
I/O orchestration.

### Trust-surface status
**TRUST-SURFACE MEMBER** (same pin as V7) — ROT ceremony required.

### Proposed remediation sketch (design only)
- Slice S7 (§13): pure short-circuit classifier + payload-builder extraction.
- Frozen contracts each change must not alter: **S2 rev.4 forward-only canonical
  success** — verified=true derives ONLY from the existence of the typed
  `CanonicalLeanEvidence` created inside `executeCanonicalVerification` (never
  re-derived from backend/provenance tag patterns; no Z3 fabrication — smtTrack stays
  empty on this path, :376–393); `rkNoObligation` vs `ogrNoApplicableObligation` map
  to `osrNoObligation` and stay out of the bmc_skipped group so VKD telemetry
  distinguishes "no property" from "encoding failed" (:394–410); deterministic
  budget-exhaustion vs wall-clock timeout statuses (mirror of V5).
- Pinning regression tests: `tests/unit/batch_uap_orchestrator_test.nim`;
  obligation-verdict semantics are pinned by the obligation suites
  (`tests/unit/` obligation tests consuming `obligation_types`/`obligation_ir`).
  Validation = suites green + V8 resolved.

## 9. V9 — loop_driver.nim: runBatchUapOrchestration 588 SLOC (566→588)

### Evidence
- Tool: `[warning] SOLID — [soc-surface-area] src/verification/batch_uap/loop_driver.nim:729 function runBatchUapOrchestration spans 588 effective SLOC (max 50)`; baseline 566 @:707.
- Read verification: :729–:1363 — preflight + PBT registry (:744–755), IR-pipeline
  acquisition with three modes skip/precomputed/fresh (:763–829), P6 OGR/PAR counter
  aggregation (:831–854), R8 persist-failure axis separation (:856–869), budget +
  circuit-breaker init (:870–894), Phase-2 worker env parsing (:896–902), parallel
  createThread+Channel execution (:962+), per-node typestate loop Stage 1
  (:1019) → Stage 2 (:1101) → Stage 3 (:1167), stats wiring (:1365).

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate).** The proc is the orchestration
monolith: pure aggregation/planning (counter walk, promotion-status folding,
IR-failure folding, threshold computation) is interleaved with I/O orchestration.
Extract: `aggregateOgrParCounters(irResultMap)` (pure), `foldIrFailuresIntoPromotion(...)`
(pure), `initBatchRuntime(gasLimit, stallCount, requests): BatchRuntime` (pure init),
and per-node loop bodies already delegate to stage1CacheCheck/stage2Budget/stage3Proof
after S7. The 588→≤50 target realistically requires ALSO splitting the IR-acquisition
phase into `verification/batch_uap/` (an `ir_acquisition.nim` sibling) — a move, not
new logic.

### Trust-surface status
**TRUST-SURFACE MEMBER** (same pin as V7) — ROT ceremony required.

### Proposed remediation sketch (design only)
- Slice S7 (§13, staged: 7a pure extractions, 7b IR-acquisition module move) — this is
  the highest-risk slice and lands last.
- Frozen contracts each change must not alter: **R8 persist-failure axis separation**
  — IR pipeline failures are verification failures of their own kernel units
  (`promoFailedCount`, `report.irPipelineFailures`), NEVER reclassified onto the
  persist axis (persistFailed=true/exit 2 INTERNAL_ERROR contamination defect,
  :848–868); P6 counter semantics (OGR generated/attempted/eligible walk, :831–841);
  circuit-breaker deterministic step thresholds (≤4→2, ≤20→5, else 10, :884–886);
  AXIOM_PROVE_WORKERS env parsing default 1 (:896–902); parallel execution preserves
  deterministic order; `verifyInfrastructure()` preflight fail-closed (:744–750).
- Pinning regression tests: `tests/unit/batch_uap_orchestrator_test.nim` (empty
  requests → empty report; unmatched requests graceful; budget info), engine/gateway
  suites for promotion classification. Validation = suites green + V9 resolved.

## 10–12. V10/V11/V12 — engine/profiler.nim: purity (new procs at :26, :36, :47)

### Evidence (common to all three)
- Tool: `[warning] PURITY-new-code-must-be-func — src/engine/profiler.nim:{26,36,47} new proc declaration in non-I/O module. Use 'func' instead of 'proc'. AGENTS.md §0.6`. The module has ZERO baseline entries (entirely new since the 2026-10-14 snapshot; last touch 297128b82).
- Read verification (whole 124-line module):
  - V10 `proc gitHeadCommit()` :26–:33 — `execCmdEx("git rev-parse HEAD")`, best-effort
    provenance commit ref ("" when git unavailable; never compared by the gate).
  - V11 `proc leanToolchainRef()` :36–:41 — `readFile("lean-toolchain")`, "unknown" on
    absence (the verbatim value IS env-compared by the gate).
  - V12 `proc existingMeasurements(path)` :47–:55 — `parseJson(readFile(path))`, fresh
    map on unreadable prior latest (the gate fails closed on an invalid latest file,
    so the heal cannot mask a comparison — `tools/perf_checker.nim` paths ②/④).
  - The pure core is already correct: `func stableMetricKey` :8; the writes live in
    the `emitProfileData` template :57–:94 (`writeFile` :92) — templates are not
    proc declarations and are not flagged.

### Root-cause class
**impure-logic-mixed-in (pure extraction candidate) — with the direction inverted
relative to the rule's literal text.** All three procs are irreducibly I/O
(subprocess execution, file reads); "convert to func" is not available without hiding
I/O behind a lie (and §0.6 assigns I/O to `proc` + `{.axiomEffect: IoEffect.}` at the
boundary, not to `func`). The honest design: the module mixes environment-probing I/O
helpers into a non-I/O module classification. Extract the three probes to an
I/O-boundary module; keep `src/engine/profiler.nim` pure computation + templates.

### Trust-surface status
**NOT a trust-surface member** — `src/engine/profiler.nim` is ABSENT from the
876-member `trustedCheckerTreeClosure` (verified in both
`config/trusted_writer_set.json` and `tools/ci/derive_checker_closure.nim --tree`).
**No ROT companion ceremony is required**; NORMAL landing path.

### Proposed remediation sketch (design only)
- Slice S1 (§13): new `src/infrastructure/perf_provenance_io.nim` (I/O layer,
  `{.axiomEffect: IoEffect.}` procs) hosting `gitHeadCommit`, `leanToolchainRef`,
  `existingMeasurements`; `profiler.nim` imports it; `emitProfileData` template body
  unchanged in behavior. All three best-effort exception comments
  (`axiom:best-effort(...)`) move verbatim.
- Frozen contracts each change must not alter: `perf_latest.json` schemaVersion 2
  shape (environment.nim/lean/profileMode/cacheState, provenance.commit/generatedAt/
  repetitions/aggregation, measurements map keyed by `stableMetricKey`); the gate's
  fail-closed contract (`tools/perf_checker.nim`: invalid/missing latest → fail);
  provenance.commit is never gate-compared; the fresh-map heal never masks a
  comparison-relevant failure.
- Pinning regression tests: `tests/test_profiler.nim` (profileBlock
  expression/statement/threshold-exceeded), `tests/unit/perf_checker_test.nim`
  (gate-side fail-closed paths). Validation = both suites green +
  `bin/nimtry src/ --diff-baseline` shows V10–V12 resolved.

---

## 13. Slice partition proposal (independent slices, ordered by risk × independence)

Explicitly NOT one big refactor: seven slices, each independently landable, each with
its own validation set and its own rollback boundary. Files inside one slice are
cohesive (same root-cause family or same file); no slice depends on another's landing
except where noted.

| Slice | Violations | File(s) | Root-cause family | Trust-surface ceremony | Risk | Independence | Validation set |
|---|---|---|---|---|---|---|---|
| **S1** | V10–V12 | src/engine/profiler.nim (+ new infrastructure perf I/O module) | impure-logic-mixed-in (I/O extraction) | **NONE (non-member)** | lowest | fully independent | tests/test_profiler.nim, tests/unit/perf_checker_test.nim, nimtry diff |
| **S2** | V3+V4 | src/infrastructure/external_ir_materializer.nim | pure-pipeline/I-O split + registry inversion | ROT (member) | low-medium (non-canonical module) | fully independent | tests/unit/external_ir_materializer_test.nim T1–T9, nimtry diff |
| **S3** | V1 | src/cli/merge_cli.nim | export reduction (visibility only) | ROT (member) | low (mechanical) | fully independent | tests/cli/test_merge_cli*.nim (123+ tests), trailers, admission-candidate |
| **S4** | V2 | src/cli/merge_cli.nim | fact-collector decomposition + pure extraction | ROT (member) | medium (admission path) | after S3 preferred (same file, smaller diffs) | test_merge_cli.nim, test_merge_admission_candidate.nim, verify-contract dry-run |
| **S5** | V7 | src/verification/batch_uap/loop_driver.nim + core/ new pure home + cli re-export | dependency inversion (forbidden layer edge) | ROT (member) | low (tiny diff) | fully independent | selection_* tests, check-layer-enforcement/negative |
| **S6** | V5+V6 | src/verification/batch_uap/loop_depth_scheduler.nim | stage-assembly pure extraction + plan/execute/merge split | ROT (member) | medium (parallel semantics) | independent of S7's landing (shares suite) | selection_independence, batch_uap_orchestrator tests |
| **S7** | V8+V9 | src/verification/batch_uap/loop_driver.nim (+ sibling ir_acquisition move) | stage-2 classifier extraction + orchestration monolith split | ROT (member) | **highest** (orchestration core) | last; 7a→7b staged | batch_uap_orchestrator, obligation suites, phase_x10_accounting |

Ordering rationale: S1 first — zero ceremony, smallest surface, immediate −3; S2 next
— self-contained, non-canonical module, T1–T9 pins are unusually strong; S3 before S4
— shrinking the export surface first makes S4's diffs reviewable; S5 is a one-symbol
inversion with its own test family and can land anytime; S6 and S7 share the
batch_uap regression suite, so they are sequenced 6→7 to let the scheduler split
stabilize the suite before the monolith split; inside S7, pure extractions (7a)
precede the module move (7b). Amendment E (ADR-0027, 2026-10-15) bounds every slice's
landing: the retry budget is ≤2 verification attempts per PR head
(`rearmed@<head12>` durable label; TRANSIENT classifier is a closed set), so a slice
whose verification keeps failing must be split further, not retried into the budget —
this is why S7 is staged. ADR-0025 Amendment E's 2-context required-checks model
(`admission-check` + `bsec-integrity`, D2 verdict protocol) applies to every landing
unchanged.

ROT ceremony per member slice (S2–S7): any edit to a closure member changes its blob
→ the PR's candidate delta changes `derived(M)` vs `derived(B)` → `adjudicateRotation`
classifies `rqRotation` (merge_cli.nim:801–838) → the landing must follow
docs/spec/admission-generation.md §4.2 path (b): **ROT_ALLOWLIST pre-registration**
(the changed paths must be allowlisted under ADR-0025 A2: pin@B keys ∪ ADR glob ∪
pin path ∪ A2 companions) **before** the PR is opened, and the **ROT_NEW_PIN
self-reference lock** ceremony for the closure re-anchor (set(pin@H) == set(H),
enforced by Pass 2.75 (H2) in `MergeAdmissible`; the manual-merge route exists only
because `trustSurfaceOutcome` fail-closes with `TRUST_SURFACE_MODIFIED` /
`ROT_UNSPECIFIED`, merge_cli.nim:1113–1143). `rotationAllowlistOk` consumes the SAME
constants as the error message (post-#306/#702 drift fix, merge_cli.nim:823–837).
Actuator-side, a rotation landing is `maAdmitted` only via the full native-MERGE
sequence (enum merge_cli.nim:2948–2961).

## 14. Frozen-contract index (cross-slice)

Contracts NO slice may alter (each pinned by the tests cited in its section):

1. `MergeAdmissible` / `adjudicateRotation` / `dryRunExit` verdict vocabulary and
   Amendment F failure ladder (S3, S4).
2. Event-frozen base anchor; ADR-0032 preflight switch; ADR-0022 §4 `--cert` artifact
   pre-bind-or-fallback (S4).
3. `MaterializationOutcome` enum + fail-closed ordering + no-CWD-fallback +
   `computeDeterministicCasKey(serializeIRFuncDef)` digest identity (S2).
4. P3b candidate-vs-kernel-acceptance fail-closed statuses; DEBT#459 REUSED
   accounting pair; deterministic-budget vs wall-clock timeout statuses (S6, S7).
5. W3-F/W3-E parallel-contract (main-thread fingerprints; deterministic taskIndex
   merge; no cert writes in workers); DEBT#415 stampede guard (S6).
6. S2 rev.4 canonical-success forward-only evidence propagation; rkNoObligation
   telemetry split; R8 persist-axis separation; circuit-breaker step thresholds;
   AXIOM_PROVE_WORKERS default (S7).
7. perf_latest.json schemaVersion 2 + perf_checker fail-closed gate + best-effort
   heal-not-mask comments (S1).
8. `computeRelaxedThreshold` pure semantics + cli↔core layer boundaries (S5).

## 15. Sequence rule — fixture-7 absorption remains BLOCKED

**The 7 class-(i) fixture items (`SAFETY-language-ban` ERRORs:
tests/fixtures/workflow_lane_guard/lane_with_emission.yml,
lane_without_emission.yml @3fb37fd12/PR #851; tests/fixtures/workflow_poison/
boundary_20999_tokenized.yml, control_30000_token_free.yml, boundary_21000_tokenized.yml,
poison_21001_tokenized.yml, poison_regression_25954.yml @a35708fb5) must NOT be
absorbed via `nimtry --update-baseline` until ALL 12 class-(ii) production items are
dispositioned** (fixed via S1–S7, or separately anchored with registry entries per
the DEBT#505 pattern).

This is the exact trap PR #857 avoided (classification doc, "Decision" §; PR #857
TASK B): the gate's fail surface is ONLY the 7 class-(i) ERRORs — a full
`--update-baseline` today would make `bin/nimtry src/` exit 0 and pass `make
check-arch` while silently anchoring the 12 class-(ii) production warnings as
accepted debt. Concretely, until the 12 are dispositioned: no
`nimtry --update-baseline`, no `debt_engine --sync-budget`, no codegen-side budget
change; ledger record BUDGET#004 stays open (its `current: 23` is a superseded
N2-generation snapshot; reconciliation is reserved for the slice where absorption is
legitimate). This manifest makes no registry, baseline, budget, or ledger changes.

## 16. Out of scope of this manifest

Implementation of any slice; baseline/budget/ledger mutation; changes to any
`.github/workflows/` file; new debt-registry entries. Each slice requires its own
contract-first slice definition (AGENTS.md §0.12) referencing this manifest.
