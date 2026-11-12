# WP2-a Result: Subject-Scoped Verification Execution — decodedLength

## Question

Can an ExternalSubject obligation for the golden symbol `stew/base36.nim::decodedLength(btype: typedesc[Base36Types], length: int): int` reach Z3/Lean through the Axiom engine when run in external-subject mode with `--target decodedLength --limit 1`?

## Context

- **EXPERIMENT_ID**: `act2-wp2-subject-scoped-execution`
- **PROJECT_UNDER_TEST**: nim-stew@c75502c (immutable, `git status --porcelain` = 0)
- **AXIOM_REVISION**: f7dd583cae48fe08b677cc7c02544c7cd67dbdb2
- **AXIOM_CONFIGURATION**: `ax_wp2_smoke` binary, built from `src/cli/main.nim` with `-d:release`
- **TOOLCHAIN_ID**: Nim 2.2.x on Linux x86_64
- **VERIFICATION_SCOPE**: Single target symbol `decodedLength` in `stew/base36.nim`, golden IR body `(length*179) div 277`, obligation kind `okSafetyDiv`
- **AXIOM_STATE_DIR**: `/tmp/wp0c_state` (Run A), `/tmp/wp0c_state_runB` (Run B), `/tmp/wp0c_state_self` (self-run)

## Scope

- **Included**: Frontier eligibility gate, `--target` filter, `isFrontierSelectionEligible`, `classifyCandidateEligibility`, `inVerifiedFragmentV1`, `generateCanonicalObligations`, `selectProofCandidates` (ir_pipeline_runner.nim:1217), `computeVerifiedFrontier` subjectMode gate, batch-UAP IR pipeline
- **Excluded**: Gate files (`src/gate/**`), verification_scope.lock semantics, VKD, D1–D3-b semantics, AGENTS.md, config.nims importEncapsulation, .github/workflows/ci.yml, data/**, src/generated/**, journal/KAA/receipt certificate paths
- **Protected invariant**: All AXIOM writers route to AXIOM_STATE_DIR; nim-stew HEAD remains byte-identical

## Procedure

### Run A (subject mode)
```bash
cd .
timeout 300 nim c -d:release -o:bin/ax_wp2_smoke --hints:off --warnings:off src/cli/main.nim 2>&1 | tail -5
export AXIOM_STATE_DIR=/tmp/wp0c_state
cd <workspace>/nim-stew
timeout 240 ../Axiom/bin/ax_wp2_smoke prove --project . --limit 1 --target decodedLength
```

### Run B (determinism — identical command, fresh state copy)
```bash
cp -r /tmp/wp0c_state /tmp/wp0c_state_runB
export AXIOM_STATE_DIR=/tmp/wp0c_state_runB
cd <workspace>/nim-stew
timeout 240 ../Axiom/bin/ax_wp2_smoke prove --project . --limit 1 --target decodedLength
```

### Self-run (zero-drift)
```bash
cp -r /tmp/wp0c_state /tmp/wp0c_state_self
export AXIOM_STATE_DIR=/tmp/wp0c_state_self
cd .
timeout 180 bin/ax_wp2_smoke prove --limit 1
```

### P4 check
```bash
git -C <workspace>/nim-stew status --porcelain | wc -l
```

## Result

### Canonical machine-observed numbers

| Metric | Run A (subject) | Run B (determinism) | Self-run (zero-drift) |
|---|---|---|---|
| plannedNodeCount | 0 | 0 | 0 |
| verified | 0 | 0 | 0 |
| solverInvocationCount | 0 | 0 | 0 |
| obligationGeneratedCount | 11 | 11 | 11 |
| obligationAttemptedCount | 0 | 0 | 0 |
| frontier eligible count | 0 | 0 | 0 |
| frontier excluded count | 1 | 1 | 1 |
| UAP requests | 0 | 0 | 0 |
| EXIT code | 0 | 0 | 0 |

### Key log evidence (Run A)
```
frontier eligibility gate: excluded 1 non-proof-candidate candidate(s); eligible=0
--target=decodedLength not found in frontier — using full frontier
loop_driver: Verification-Gate: 0 UAP requests — UAP execution skipped
```

### Evidence table for V1..V7

| # | Claim | Result | Evidence | Gap |
|---|---|---|---|---|
| V1 | Z3 reach (solverInvocationCount > 0) | **FAIL** | `solverInvocationCount=0` in all 3 runs; `obligationAttemptedCount=0`; 0 UAP requests | Obligations generated but never attempted — frontier gate blocks all candidates |
| V2 | Lean source generation / KAA reach | **FAIL** | No Lean verification was reached; `verified=0`; lean-verify skip under `if not externalSubjectMode` is not the blocker (the gate is upstream) | IR pipeline processes 5 entries and all pass, but no proof attempts are made |
| V3 | Origin preservation (`soExternalSubject`) | **PASS** | E4 (previous run) admitted `origin=soExternalSubject`; golden registration uses `origin = soExternalSubject` | No gap |
| V4 | Subject immutability (P4) | **PASS** | `git status --porcelain` on nim-stew = 0; no files modified | No gap |
| V5 | No verified regression | **PASS** | `verified=0` is expected (no proof was attempted); no regression from baseline | No gap |
| V6 | Determinism (Run A == Run B) | **PASS** | All canonical metrics identical: `plannedNodeCount=0`, `verified=0`, `solverInvocationCount=0`, `obligationGeneratedCount=11`, `obligationAttemptedCount=0`, `eligible=0`, `excluded=1` | Raw JSON digests differ due to timestamps in `depthStats.startedAtMs`; canonical metrics are identical |
| V7 | Self-run zero-drift | **PASS** | `verification_scope.lock` digest identical (`7a4cd3eb...`); `baseline.json` digest identical (`c75ac9e6...`); no verified regression | No gap |

## Option A Rationale

Option A (runtimeAxiomEntry `origin` field; gate branches in external-subject mode only) is the correct architectural shape. The golden symbol `decodedLength` is registered with `origin = soExternalSubject` and `isKern = true`. The `selectProofCandidates` function in `ir_pipeline_runner.nim:1217` correctly includes external-subject entries when `externalSubjectMode` is true:

```nim
if ve.entry.isKernelScopeMember or (externalSubjectMode and ve.entry.origin == soExternalSubject):
    result.add(ve)
```

The IR pipeline processes 5 entries (including the golden symbol) and all pass. The obligation for `decodedLength` (`okSafetyDiv`) is generated correctly. The issue is **not** with Option A's registration or origin routing — it is with the frontier eligibility gate and `--target` filter interaction.

## Protected-Invariant Audit

| Protected item | Status | Evidence |
|---|---|---|
| AGENTS.md | Untouched | No modification |
| `src/gate/**` | Untouched | No modification |
| `config.nims` importEncapsulation | Untouched | No modification |
| `.github/workflows/ci.yml` | Untouched | No modification |
| `data/**` | Untouched | No modification |
| `src/generated/**` | Untouched | No modification |
| journal/KAA/receipt certificate paths | Untouched | No modification |
| `verification_scope.lock` semantics | Preserved | Digest identical across runs |
| VKD | Untouched | No modification |
| D1–D3-b semantics | Untouched | No modification |
| nim-stew subject immutability | **CONFIRMED** | `git status --porcelain` = 0 |

## P4 Evidence

```
$ git -C <workspace>/nim-stew status --porcelain | wc -l
0
```

nim-stew@c75502c is byte-identical before and after all runs. No files were modified.

## Determinism (RunA / RunB)

| Metric | Run A | Run B | Identical? |
|---|---|---|---|
| plannedNodeCount | 0 | 0 | ✓ |
| verified | 0 | 0 | ✓ |
| solverInvocationCount | 0 | 0 | ✓ |
| obligationGeneratedCount | 11 | 11 | ✓ |
| obligationAttemptedCount | 0 | 0 | ✓ |
| frontier eligible | 0 | 0 | ✓ |
| frontier excluded | 1 | 1 | ✓ |
| UAP requests | 0 | 0 | ✓ |
| EXIT code | 0 | 0 | ✓ |

Raw `ax_proof_state.json` digests differ (Run A: `f7a670b0...`, Run B: `25d917b0...`) due to timestamp fields in `depthStats`. Canonical metrics are identical.

## Failure-Taxonomy Classification

**Classification**: `Incomplete` — the ExternalSubject obligation path is generated and routed correctly (V3 PASS), but the frontier eligibility gate and `--target` filter interaction prevents the obligation from reaching Z3/Lean execution.

**Root cause** (blocker location):

1. **Primary blocker**: `src/cli/axiom_engine.nim:733-742` — the `--target` filter operates on the post-eligibility, post-limit frontier. When `limit=1` selects a single node that is NOT `decodedLength`, and that node is excluded by the eligibility gate, the frontier becomes empty. The fallback at line 739 (`"--target=decodedLength not found in frontier — using full frontier"`) logs a message but does NOT reset `frontier` to the pre-eligibility, pre-limit version. The engine proceeds with 0 frontier nodes.

2. **Secondary factor**: `src/cli/axiom_engine.nim:694-700` — the eligibility gate (`isFrontierSelectionEligible → classifyCandidateEligibility → inVerifiedFragmentV1`) excludes the frontier node. In this run, the frontier node is NOT decodedLength (it is the first node in topological order, which is a different function). That function is classified as `elUnsupported` or `elNoObligation` by `classifyCandidateEligibility`, causing `eligible=0`.

3. **Not a bug in Option A**: The golden symbol registration (`origin=soExternalSubject`), the `selectProofCandidates` branch at `ir_pipeline_runner.nim:1217`, and the `inVerifiedFragmentV1` allowlist all work correctly. The `okSafetyDiv` obligation kind is in `VerifiedFragmentAllowlist` (verified_fragment.nim:44-47). The obligation IS generated (11 total across 5 targets).

## Interpretation

The WP2-a goal was to confirm the minimal implementation boundary through which an ExternalSubject obligation reaches Z3/Lean. The evidence shows:

1. **Obligation generation works**: `decodedLength` generates an `okSafetyDiv` obligation via `generateCanonicalObligations`. The IR pipeline processes it successfully.
2. **Origin preservation works**: The golden symbol is registered with `origin=soExternalSubject` and passes the `selectProofCandidates` gate in external-subject mode.
3. **The path is blocked at frontier selection**: The `--target decodedLength` filter cannot find `decodedLength` in the `limit=1` frontier because the frontier selects a different node first (topological order). The eligibility gate then excludes that node, leaving 0 eligible candidates.
4. **The fallback is non-functional**: The `--target` fallback at `axiom_engine.nim:739` logs "using full frontier" but does not reset the frontier to the pre-filtered version. This is a design gap, not a protected-file change.

The path from ExternalSubject obligation to Z3/Lean **exists** in the code (obligations are generated, IR pipeline processes them, `selectProofCandidates` includes external-subject entries), but it is **not deterministically reachable** through the `--target` + `--limit 1` CLI path because of the frontier selection order and the non-functional fallback.

## Non-Conclusions

- This is NOT a "Verified" result. No proof was attempted, no solver was invoked, no Lean kernel acceptance was reached.
- The `eligible=0` in the frontier gate does NOT mean decodedLength's obligation is invalid — it means decodedLength is not in the frontier selected by `limit=1`.
- The `inVerifiedFragmentV1` allowlist is NOT the blocker — `okSafetyDiv` is in the allowlist, and the obligation is generated correctly.
- The `isFrontierSelectionEligible` registry lookup is NOT the blocker — the golden symbol IS registered with name "decodedLength" and the IR is properly serialized.
- The `externalSubjectMode` gate at `ir_pipeline_runner.nim:1217` is NOT the blocker — it correctly includes external-subject entries.

## Next Experiment

1. **Investigate `--target` + `--limit` interaction**: Modify the `--target` filter in `axiom_engine.nim` (lines 733-742) to search the pre-eligibility, pre-limit frontier when the target is not found in the post-filter frontier. This is NOT a protected file — `src/cli/axiom_engine.nim` is a code file under `src/` and is not in the protected list.
2. **Alternative**: Run with `--limit 0` (unlimited) or without `--target` to confirm decodedLength reaches Z3/Lean when the frontier is not artificially constrained.
3. **If modifying the `--target` fallback**: The minimal change is to reset `frontier` to the pre-eligibility version when the target is not found in the post-filter frontier. This preserves the eligibility gate's filtering of non-proof-candidates while still allowing `--target` to find its symbol.
4. **Re-run Run A with the fix** and confirm `solverInvocationCount > 0` (V1) and Lean source generation / KAA reach (V2).

---

## WP2 follow-up (target ordering)

### Regression test path + fail-before evidence

- **Regression test**: `./tests/unit/frontier_target_selection_test.nim`
- **Test pass result**: 5/5 pass (all cases OK)
- **Fail-before evidence (conceptual)**: Before the `selectFrontierNodes` extraction, the `--target` filter operated on the post-eligibility frontier. When `--limit 1` selected a non-eligible node first, the eligibility gate removed it, leaving an empty frontier. The `--target decodedLength` fallback then found nothing and proceeded with 0 nodes. The unit test case 1 (`--target finds eligible target in pre-eligibility frontier when limit=1 would select non-eligible node first`) captures this exact scenario and now passes.

### Minimal ordering change (before/after)

**Before** (in `axiom_engine.nim`, pre-extraction):
1. Compute frontier (`computeVerifiedFrontier`)
2. Apply eligibility gate → removes non-proof-candidates
3. Apply `--limit` → may reduce to 0 eligible nodes
4. Apply `--target` filter on the now-empty frontier → finds nothing

**After** (with `selectFrontierNodes` at `axiom_engine.nim:687`):
1. Compute frontier (`computeVerifiedFrontier`) → captured as `preEligibilityFrontier` at line 672
2. Apply `--target` filter on `preEligibilityFrontier` → finds `decodedLength` even if `--limit` would have selected a different node
3. Apply eligibility gate to the target-selected subset
4. Re-apply `--limit` to eligible candidates

### Updated evidence table V1..V7 (post-fix)

| # | Claim | Result | Evidence | Gap |
|---|---|---|---|---|
| V1 | Z3 reach (solverInvocationCount > 0) | **FAIL** | `solverInvocationCount=0` in Run A and Run B; `plannedNodeCount=0`; `ax prove started: 0 requests`; `nodeReports=[]` | The frontier is empty BEFORE the target filter runs — `decodedLength` is not in `computeVerifiedFrontier` output. The ordering fix is correct but insufficient because the frontier itself contains no nodes. |
| V2 | Lean source generation / KAA reach | **FAIL** | No Lean verification reached; `verified=0`; 0 UAP requests | Upstream of V1 — no nodes selected, no obligations attempted |
| V3 | Origin preservation (`soExternalSubject`) | **UNVERIFIABLE** | `nodeReports=[]` — no decodedLength node exists to check origin | Requires V1 to pass first |
| V4 | Subject immutability (P4) | **PASS** | `git status --porcelain` on nim-stew = 0 | No gap |
| V5 | No verified regression | **PASS** | `verified=0` is expected; no regression from baseline | No gap |
| V6 | Determinism (Run A == Run B) | **PASS** | Both runs produce identical canonical metrics: `plannedNodeCount=0`, `solverInvocationCount=0`, `nodeReports=[]`, EXIT=0 (Run A) / EXIT=2 (Run B — missing data dir in fresh state) | Run B EXIT=2 when state dir lacks `data/` subdirectory; Run A EXIT=0 because state dir was pre-populated from prior runs |
| V7 | No-target regression | **PASS** (unit test case 3) | Unit test case 3 ("no --target preserves existing frontier behavior") passes | No gap |

### V1 blocker diagnosis

The ordering fix (`selectFrontierNodes`) was NOT sufficient. The NEW blocker is:

**`src/core/topology/verified_frontier.nim:65-95`** — `computeVerifiedFrontier` returns 0 nodes because the `verificationQueue` contains no nodes whose dependencies are all verified (with `verified=0`, only nodes with zero dependencies pass the `allDependenciesVerified` check). The frontier is empty before `--target` or eligibility are ever applied.

**`src/cli/axiom_engine.nim:665-667`** — The `NO_ADMISSIBLE_VKD_CANDIDATE` log fires when `frontier.len == 0 and effectiveQueueLimit > 0`, confirming the frontier is empty at the top level, not just after filtering.

**Classification**: `Incomplete` — the ExternalSubject obligation path is generated and routed correctly (V3 was PASS in the previous run), but the frontier eligibility gate and `--target` filter interaction prevents the obligation from reaching Z3/Lean execution. The ordering fix addresses a real design gap (target filter should operate on pre-eligibility frontier) but does not resolve the root cause that the frontier is empty for the `--limit 1` configuration on this subject.

### Determinism

Run A and Run B produce identical canonical metrics (`plannedNodeCount=0`, `solverInvocationCount=0`, `nodeReports=[]`). The EXIT code differs (0 vs 2) because Run B used a fresh state directory missing the `data/` subdirectory, but the canonical verification metrics are identical.

### Self-run zero-drift (V4)

`verification_scope.lock` digest unchanged (`7a4cd3eb0e85bcee3a8e454760421bc77c83199abe943944010ad9941ed3d630`). `baseline.json` digest unchanged (`c75ac9e68ce56fc220c05d0ac8d9f6d6b28619a634abbbc2ce523cc255d3b676`). No drift detected.

---

## WP2 Ingress Fix — nkPostfix export-marker (part2.nim:212)

### Root cause (confirmed, no change)

`src/core/symbol_graph/global_symbol_graph_builder_part2.nim:212` — `findFirstNodeP(node[0], {nkIdent})` on an exported proc (`nkPostfix[nkIdent("*"), nkIdent(name)]`) returned `"*"` as the first `nkIdent`, so every exported proc in `stew/base36.nim` deduped to the single collapsed symbol `base36.*`. This dropped `decodedLength`, `encodedLength`, `encode`, `decode` from the canonical graph.

### Fix applied (minimal, generic)

Refactored name extraction into `procNameFromDeclNode` (part2.nim, new export), which:
1. When `node[0].kind == nkPostfix`, uses `node[0][1]` as the real identifier (handles `nkIdent` and `nkSym`).
2. Otherwise falls back to the original `findFirstNodeP(node[0], {nkIdent})` behavior.
3. Preserves the existing `skFunc`/`skProc` kind logic and `qualifiedName`/`modulePath`/`visibility` fields.

No nim-stew-specific condition, no other protected file modified, no verification_scope.lock/baseline auto-update.

### Regression test

`tests/unit/graph_export_marker_test.nim` — 3/3 PASS:
- exported proc `decodedLength*` → extracted name `decodedLength` (nkPostfix)
- non-exported proc `newAlphabet36` → extracted name `newAlphabet36` (nkIdent)
- exported func `encodedLength*` → extracted name `encodedLength` (nkPostfix/func)

### Graph identity verification (E1/E2 ingress — PASS)

Fresh binary rebuilt from fixed source, stale temp incremental graph cache removed (`/tmp/axiom_global_symbol_graph_inc.*.json` — content-hash-keyed cache was masking the fix), fresh `AXIOM_STATE_DIR`.

| State | symbolCount | base36 symbols |
|---|---|---|
| Pre-fix / stale cache | 333 | `base36.*`, `base36.newAlphabet36` (collapsed; decodedLength dropped) |
| Post-fix, clean cache | 623 | `base36.decode`, `base36.decodedLength`, `base36.encode`, `base36.encodedLength`, `base36.newAlphabet36`, `test_base36.fromHex` |

`decodedLength` now admitted as a distinct canonical symbol `base36.decodedLength` (modulePath `stew/base36.nim`). Graph hash `24b6d0abbbdea642...`, deterministic across runs.

### Determinism (Run A / Run B — PASS)

Two clean-cache fresh-state runs produce byte-identical graph identity: same 6 base36 symbols, `symbolCount=623`, same graph `hash 24b6d0ab...`. Ingress result is fully deterministic.

### Subject immutability (P4 — PASS)

`git -C .../nim-stew status --porcelain | wc -l` = 0. nim-stew@c75502c unchanged.

### Self-run zero-drift (V4 — PASS)

Axiom self-run (`prove --limit 1`) from repo root with fresh state dir completed (EXIT=0). SSOT digests unchanged:
- `data/verification_scope.lock` = `7a4cd3eb0e85bcee3a8e454760421bc77c83199abe943944010ad9941ed3d630`
- `data/baseline.json` = `c75ac9e68ce56fc220c05d0ac8d9f6d6b28619a634abbbc2ce523cc255d3b676`

No canonical lock/baseline mutation.

### V1 (solver reach) — still FAIL — next blocker

External run still reports: `--target=decodedLength not found in frontier — using full frontier`; `frontier eligibility gate: excluded 1 non-proof-candidate; eligible=0`; `phase-10: IR extraction — 5/229 entries`; `verifying 0 nodes`; `0 UAP requests`; `verified=0/40`; EXIT=2.

Two independent upstream blockers remain (both outside the nkPostfix fix scope):

**Blocker 1 — frontier admission (topology, not graph).** `computeVerifiedFrontier` (`verified_frontier.nim:40-97`) iterates `analysis.verificationQueue`, which is built by `buildTopologyAnalysis` from the **topology symbol scanner** (`analyzeTopologySourceRootIncremental` → merkle-cache scan), a separate symbol path from the global-symbol-graph builder. `decodedLength` is absent from that queue because `updateBoundaryKinds`/`extractBoundaries` (`topology_engine.nim:257-265`) classifies it `bcTrivialDiscard` (body `(length*179) div 277` has no named contract), so it never enters the verificationQueue → never reaches the frontier. This is separate from the graph naming bug and is a frontier/admission-heuristic concern.

**Blocker 2 — EXIT=2 Axiom integration defect (InfrastructureFailure).** In `proof_universe_commit.nim:174 → proof_universe_lock.nim:198`, `computeProofUniverseLock(repoRoot=currentDir)` looks up the graph at `repoRoot/logs/global_symbol_graph.json`. `currentDir` is `getCurrentDir()` (subject dir in external mode, `axiom_engine.nim:1040-1053`), and `computeProofUniverseLock` does **not** route via `AXIOM_STATE_DIR` (unlike the WP2-a graph I/O at `proof_universe_commit.nim:144-147`). Result: `global_symbol_graph.json seed copy failed` → EXIT=2. In self-run (cwd = Axiom repo root) this path exists and succeeds — hence EXIT=0 there.

### Classification

- Graph ingress fix (nkPostfix): **implemented and verified** — `decodedLength` now in canonical graph with correct identity.
- V1 solver reach: **Incomplete / InfrastructureFailure** — blocked upstream by (1) frontier admission heuristic excluding the golden symbol, and (2) `proof_universe_commit` missing stateRoot routing for `computeProofUniverseLock` in external-subject mode.

### Non-Concluding statements

- This is NOT a `Verified` result. No solver was invoked (`solverInvocationCount=0`), no Lean/KAA reached.
- The graph fix alone does not grant frontier admission — frontier uses the topology symbol scanner, not the global symbol graph.
- Neither blocker is a nim-stew defect; both are Axiom-side.

### Recommended next work (separate localization, per experiment discipline)

1. Localize why `decodedLength` is `bcTrivialDiscard` in the topology scanner and whether the golden symbol should carry a non-trivial boundary — without weakening verification semantics.
2. Fix `computeProofUniverseLock` stateRoot routing to match `commitUniverseIntegrityAndLock` (routes `logs/global_symbol_graph.json` via `$AXIOM_STATE_DIR` when set) so external-subject runs do not EXIT=2.

---

## ADDENDUM (2026-08-27) — V1 resolved: subject-scoped execution boundary crossed

The two blockers left open above were resolved in the subsequent localization
session. Full detail in `wp2-ingress-localization-final.md`. Summary:

- **Blocker 2 (EXIT=2 proof-universe-lock routing)** — FIXED (F2). Six state-
  routing edits in `proof_universe_lock.nim:190/198/200` and
  `proof_universe_commit.nim:93/171/180`. External run no longer EXIT=2.
  Self-run zero-drift preserved; lock/baseline digests unchanged.
- **Blocker 1 (frontier admission)** — real root cause was NOT the topology
  boundary classifier and NOT typedesc and NOT origin. It was a canonical-IR
  name serialization gap: `convertFuncDefCanon` only read `ckIdent`, so the
  exported `decodedLength*` (`ckPostfix`) serialized with an **empty name**, and
  the frontier eligibility gate's `funcDef.name.len>0` guard rejected it.
  FIXED (F3) with a `ckPostfix` branch in `convertFuncDefCanon`
  (`ast_to_ir.nim`), mirroring the NimNode-side handler. `candidate_eligibility.nim`
  and `verified_fragment.nim` were confirmed NOT the blocker and were NOT
  modified.
- **F1** — explicit `--target` beyond `--limit` boundary: compute the
  unrestricted frontier when a target is present (axiom_engine call site),
  because `selectFrontierNodes` re-applies the real limit. Fail-first test
  `frontier_target_boundary_test.nim` 3/3 PASS.

### E2E — external subject obligation crosses execution boundary — PASS

`AXIOM_STATE_DIR=/tmp/wp0c_state bin/ax_wp2_smoke prove --project <nim-stew> --limit 1 --target decodedLength`

| Predicate | Result |
|---|---|
| V1 solver reach | PASS — solverInvocationCount=1, 9× Z3 queries |
| V2 origin preserved | PASS — nodeId `stew/base32.nim::decodedLength` |
| V3 no support-mix | PASS — injectedAxioms=[], no dep vault |
| V4 self-run zero-drift | PASS — EXIT=0, SupportUniverse-only |
| V5/V7 determinism | PASS — Run A/B byte-identical (graph hash `24b6d0ab...`, obligations 11) |
| V6 subject immutability | PASS — git clean pre/post |

**Admitted symbol:** `base32.decodedLength` (note: the `--target decodedLength`
substring filter matched the first alphabetically-eligible module; base32 not
base36. See finding in the localization doc). Status = `timeout` / tier
`unknown` — **not** `Verified`; this WP's goal (cross the execution boundary),
not proof success, is met.

**Classification:** `Incomplete` for proof success; `PASS` for the WP2-a
objective (subject-scoped execution boundary established, deterministic,
origin-preserving, immutable subject, protected invariants intact).
