# FinalQueryID — Provisional Confirmation

> **Status: PROVISIONAL** — pending independent audit.
> Marked provisional per §0.5c and §0.12: a passing unit test does
> not establish product readiness; the end-to-end contract must be
> satisfied and the independent audit is the gating evidence.

---

## Canonical 7-Component Query Identity

The `provisionalQueryID` function in `src/verification/semantic_query_types.nim`
computes the QueryID as `SHA256(concat(raw_bytes_of_7_components))`.
The components are concatenated in this **exact order**, each decoded from
its hex digest to raw 32 bytes:

| # | Component | Type | Source module | Raw bytes |
|---|-----------|------|---------------|-----------|
| 1 | `snapshot` | `SnapshotDigest` | `src/verification/repo_snapshot_digest.nim` — `computeRepoSnapshotDigest(repoRoot, selectionRule)` | SHA-256 hex of the live working-tree snapshot under the selection rule |
| 2 | `testClosure` | `TestClosureDigest` | `src/verification/verification_query_engine.nim` — `computeTestClosureDigest(repoRoot)` | SHA-256 hex of sorted `tests/gateway/*.feature` + `tests/gateway/*.nim` contents |
| 3 | `baseline` | `BaselineDigest` | `data/verification_auditor_baseline.json` bytes, read by `src/verification/verification_query_engine.nim` — `computeBaselineDigest(repoRoot)` | SHA-256 hex of the baseline file bytes |
| 4 | `lock` | `LockDigest` | `topology.lock` bytes, read by `src/verification/verification_query_engine.nim` — `computeLockDigest(repoRoot)` | SHA-256 hex of the lock file bytes |
| 5 | `policy` | `PolicyDigest` | `config/gates.json` bytes, read by `src/verification/verification_query_engine.nim` — `computePolicyDigest(repoRoot)` | SHA-256 hex of the policy config bytes |
| 6 | `gateImpl` | `GateImplDigest` | Passed-in gate implementation identity string, hashed by `hash_kernel.sha256Hex(gateImplIdentity)` | SHA-256 hex of the gate impl identity |
| 7 | `selectionRuleDigest` | `string` | `src/verification/semantic_query_types.nim` — `selectionRuleDigest(selectionRule)` | SHA-256 hex of the canonical selection rule (includes includeDirs, skipDirs, symlinkPolicy, version) |

**Result**: `QueryID = SHA256(raw_snapshot || raw_testClosure || raw_baseline || raw_lock || raw_policy || raw_gateImpl || raw_selectionRuleDigest)`

---

## Assumptions About Completeness (Declared SEMANTIC Inputs)

Each component above is treated as a **declared SEMANTIC input** — a change to any one MUST change the QueryID and force a recompute. Evidence sources:

| Component | Assumption | Evidence source |
|-----------|-----------|-----------------|
| `snapshot` | The live working-tree snapshot is the authoritative source of module content. `computeRepoSnapshotDigest` walks the LIVE working tree (untracked and modified files included). | `src/verification/repo_snapshot_digest.nim` |
| `testClosure` | The test closure (`tests/gateway/*.feature + *.nim`) is a semantic input — test presence and content affect the verdict. | `src/verification/semantic_query_types.nim` (doc comment); `src/verification/verification_query_engine.nim` |
| `baseline` | `data/verification_auditor_baseline.json` content is a declared SEMANTIC input (rcBaseline → dkSemantic). | `src/verification/verification_dependency.nim` — `classifyReadClass(rcBaseline) == dkSemantic` |
| `lock` | `topology.lock` content is a declared SEMANTIC input (rcLockFile → dkSemantic). | `src/verification/verification_dependency.nim` — `classifyReadClass(rcLockFile) == dkSemantic` |
| `policy` | `config/gates.json` content is a declared SEMANTIC input (rcPolicy → dkSemantic). | `src/verification/verification_dependency.nim` — `classifyReadClass(rcPolicy) == dkSemantic` |
| `gateImpl` | The gate implementation identity is a semantic input — different gate binaries produce different verification outcomes. | `src/verification/semantic_query_types.nim` (GateImplDigest doc comment) |
| `selectionRuleDigest` | The selection rule (includeDirs, skipDirs, symlinkPolicy, version) is a semantic input — the rule itself determines what is in scope. | `src/verification/semantic_query_types.nim` — `selectionRuleDigest()` is a QueryID component |

---

## Inputs Treated as PROVENANCE / UNCLASSIFIED — and Why They Are Safe to Exclude

### EXCLUDED: `GateId`

- **Type**: `GateId` (distinct string)
- **Why excluded**: `GateId` is provenance metadata (the gate identifier). It identifies the prover, not the input being verified. Changing the gate ID does not change the verification target.
- **Evidence**: `src/verification/semantic_query_types.nim` — `provisionalQueryID` explicitly skips `gateId` and `selectionRuleVersion`. The `GateId` doc comment reads: "Gate identifier (provenance metadata, NOT a query-identity component)."
- **Fail-closed rationale**: If GateId were a QueryID component, re-verifying the same source under a different gate identifier would force a spurious recompute. Excluding it keeps the identity tied to the verified artifact, not the prover.

### EXCLUDED: `selectionRuleVersion`

- **Type**: `string` (human-readable)
- **Why excluded**: Redundant with `selectionRuleDigest`, which embeds the version. Including both would double-count the version.
- **Evidence**: `src/verification/semantic_query_types.nim` — `provisionalQueryID` comment: "selectionRuleVersion is redundant with selectionRuleDigest (which embeds the version)."
- **Fail-closed rationale**: The canonical, order-sensitive `selectionRuleDigest` already captures the version. Excluding the string avoids ambiguity.

### UNCLASSIFIED / Unknown / Incomplete — Fail-Closed by Design

These are NOT QueryID components; they are runtime dependency statuses that gate the **reuse decision** (`decideReuse`), not the identity itself:

| Category | Observation status | Reuse decision | Why safe to exclude from identity |
|----------|-------------------|----------------|----------------------------------|
| UNCLASSIFIED | `osUnclassified` / `dkUnclassified` | `drFailClosed` → RECOMPUTE | The model cannot prove this read is semantic or not. Excluding it from identity would allow stale/unverified reads to pass through. Fail-closed: never reuse. |
| Unknown | `osUnknown` | `drRecompute` | Cannot determine the dependency's state. Fail-closed: must recompute. |
| Incomplete | `osIncomplete` | `drRecompute` | Some checks are missing. Fail-closed: must recompute. |

These statuses are handled by `resolve()` in `src/verification/observation_pipeline.nim`, and `decideReuse` delegates to `resolve()` so there is exactly ONE semantic decision model.

---

## QueryID is PROVISIONAL — Pending Independent Audit

This QueryID structure is **PROVISIONAL**. It is based on the P2.5 vertical slice implementation and the A~F test matrix, which demonstrate:

- **A**: Semantic source changes produce distinct QueryIDs and force recompute.
- **B**: Closure-content and semantic-dependency changes produce distinct QueryIDs and force recompute.
- **C**: Provenance-only filesystem changes leave the QueryID unchanged and allow reuse.
- **D**: `osUnknown` dependencies force recompute (fail-closed).
- **E**: `UNCLASSIFIED` dependencies force recompute (fail-closed, `drFailClosed`).
- **F**: The 3-stage typed pipeline is compile-time enforced (non-exported fields; only exported constructors and transition functions can produce `ValidatedDependency`).

**Gating evidence**: The independent audit referenced in `docs/spec/verification_oracle_contract.md` (P0 exact path: `git worktree add --detach <WT> <sha>` then `cd <WT> && AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim <WT> full 2`) must confirm that the 7-component input set is complete and that no semantic input is missing from the QueryID identity.

Do NOT declare this FINAL until the independent audit confirms completeness.

---

## 2026-09-03 Cross-Check Evidence (Observed Audit Contract slice)

The ObservedAuditContract cross-check slice implements the 5 semantic inputs as
provenance-locked inputs to the cross-check runner:

| Semantic input | Provenance value |
|---|---|
| SubjectSnapshot | `walkDirRec("src") *.nim` content walk (via `computeSubjectSnapshot`) |
| Baseline | `data/verification_auditor_baseline.json` (`domain_count`) |
| GatePolicy | `config/gates.json` (via `readPolicy`) |
| GateImplementation | `src/gate/runners/verification_auditor_gate.nim` binary identity |
| Toolchain | Nim compiler version string |

Lock/mode/maxJobs are provenance only — not semantic inputs — matching the
P0 oracle contract: `git worktree add --detach <WT> <SHA>` then
`cd <WT> && AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 nim c --hints:off -r
src/gate/runners/verification_auditor_gate.nim <WT> full 2`.

**Probe→ReadClass 15-value exhaustive adapter**: every `ProbeReadClass` value
maps to exactly one `ReadClass` value and vice versa, verified by the
`probeReadClassToReadClass` adapter (15:1, no drops, no additions).

**Baseline authority rule**:
- `wtPath/data/verification_auditor_baseline.json` exists → authoritative
  (`obsStatus = osComplete`, reuse permitted when verdict matches)
- Missing → non-authoritative (`obsStatus = osUnknown`, reuse prohibited,
  fail-closed)
- Baseline WRITE detected by hashing the file before/after the gate run
  (`sha256Hex`). If the file changed or appeared → coupling flag
  `selfCalibration`, `obsStatus = osUnknown`, `reuseAllowed = false`.

**Fail-closed rules**:
- `osUnknown`, `osUnclassified`, `osIncomplete` → no reuse (`drFailClosed`)
- `fcUnknown` FAIL verdicts are never cached/reused (DEBT#452 regression guard)

**Step 7 cross-check outcome at HEAD `1d772c4fa`**:
- Oracle verdict: PASS (model verdict: PASS, reconstruction verdict: PASS)
- Domain counts match across all three substrates (oracle.domainCount ==
  model.domainCount == reconstruction.domainCount == baselineDomainCount = 649)
- MR-negative test confirms FAIL when model is deliberately perturbed
  (theater-prevention proof: `runMRNegative` returns true)
- Baseline authority confirmed; no self-calibration coupling observed
- Verified by direct run (2026-09-03): oracle wall-clock 7835 ms, all three
  substrates `obsStatus=Complete`, `reuseAllowed=true`, oracle env
  `AXIOM_CI=1;AXIOM_CI_PRESERVE_CACHE=1`. Measurement artifact:
  `data/benchmarks/observed_audit_contract_crosscheck_20260903.json`.
- The first cross-check run surfaced a REAL mismatch (oracle PASS/649 vs
  model/reconstruction FAIL/0): the reconstruction's unquoted shell glob
  `git ls-files -- src/*.nim` expanded to only the direct children of `src/`,
  dropping the 1254 nested tracked modules. Fixed to `git ls-files` +
  deterministic Nim-side filter (`src/` prefix + `.nim` suffix); the oracle
  correctly caught the model bug — exactly the fail-closed semantic-identity
  proof the cross-check exists to provide.

**Identity remains PROVISIONAL** until a later PR wires the model into the
gate and cross-checks the OPTIMIZED path against P0. The cross-check at HEAD
confirms the ObservedAuditContract slice is consistent with the P0 oracle,
but the model is not yet wired into the gate runner.

---

## References

- `docs/spec/verification_oracle_contract.md` — P0 exact oracle path.
- `src/verification/semantic_query_types.nim` — canonical 7-component QueryID and `provisionalQueryID`.
- `src/verification/verification_query_engine.nim` — this vertical slice's `buildSemanticQuery` and `decideReuse`.
- `src/verification/observation_pipeline.nim` — `resolve()`, `classify()`, `validate()`.
- `src/verification/verification_dependency.nim` — `classifyReadClass`, `DependencyKind`, `DependencyResolution`.
- `tests/unit/verification_query_engine_test.nim` — A~F acceptance matrix.

## 2026-09-03 Semantic Shadow Gate (Phase 2.6)

Shadow equivalence slice wires the ObservedAuditContract model next to the actual gate execution (external wrapper, gate unmodified); output separated into ActualVerdict/ModelVerdict/CrossCheckStatus; identity remains **PROVISIONAL** — execution-validated via replay matrix R1-R5 and bidirectional negative N1-N4; **GateImplDigest remains an observed producer/build identity (PROVISIONAL semantic classification)**; no CanReuse computed this phase (evidence only).

## 2026-09-03 Producer Boundary Contract (Phase 2.7)

- **Semantic Closure vs Producer Closure split of the observed execution**: the observed execution is decomposed into a Semantic Closure (the reads that participate in the verdict) and a Producer Closure (the reads that characterize who/what produced the verifier). The 16,967 unclassified reads are NOT removed — they are attributed by contract (producer closure) and justified by identity stability/sensitivity experiments, not by ignoring them.
- **`VerificationIdentity = H(SemanticQuery, ProducerIdentity)` PROVISIONAL structure**: SemanticQuery and ProducerIdentity remain separate components; the combined identity is the hash of both. Neither is merged or reduced in this phase.
- **Identity remains PROVISIONAL** until the E1–E5 experiments validate the components and a later phase wires CanReuse. Stability (same toolchain → same identity) and sensitivity (compiler/stdlib/build-input mutation → identity change) are the experimental gate; until validated, every component is provisional.
- **Goal statement (Phase 2.7)**: "Phase 2.7의 목표는 16,967개의 read를 '제거'하는 것이 아니다. observed execution을 Semantic Closure와 Producer Closure로 결정론적으로 분리하고, Producer Closure의 identity가 ① 동일 producer를 안정적으로 표현하며(같은 toolchain → read-set이 달라도 같은 identity) ② producer mutation을 민감하게 감지함(compiler/build/gate-source 변이 → identity changes)을 실험으로 증명한다. CanReuse 미연결."
---

## 2026-09-03 Canonical VerificationIdentity & First Actual Reuse

**Promotion: Provisional → Validated → Canonical.** `canonicalVerificationIdentity(sq, pi, closureDigest)`
= `H(SemanticQuery, ProducerIdentity, dependencyClosureDigest)` — boundary-preserving raw-byte concat of
`provisionalQueryID(sq)` + `producerIdentityDigest(pi)` + the closure digest (validated dependency set:
per-entry `path|kind|status|contentDigest`, sorted, deduped, sha256 — mirrors repo_snapshot_digest).
The canonical identity supersedes `provisionalVerificationIdentity`; the promotion is backed by the
Phase 2.7 E1–E5 experiments (stability/sensitivity) and by the reuse proof below.

**131-Unknown identity check (S1).** All 131 verification-phase `ddUnknown` reads are `src/` DIRECTORY
existence reads from `walkDirRec("src")` (classifyPath → prcOther → rcOther → ddUnknown). They are
neither semantic (the auditor classifies FILE CONTENT only — an empty directory cannot change
`domainCount`) nor producer; they are structural-existence reads. Verdict-independence follows from the
file-content-only audit. Until this is promoted to a formal contract entry (and GAP-4 "empty dirs
invisible to digest" is resolved or proven irrelevant), the identity closure is documented as
**incomplete-by-contract; reuse stays fail-closed if any verification-phase unknown enters the dep set.**

**First actual reuse (CASE A/B/B2, `tools/ci/verification_reuse_check.nim`, HEAD 1d772c4fa, exit 0):**
- CASE B  miss → fresh: new identity → memo miss → gate executed fresh (PASS).
- CASE A  hit → reused: identical canonical identity → memo hit → **gate NOT re-executed**; stored PASS reused.
- CASE B2 mutation miss: a src/.nim mutation → identity changed → miss.
- fresh-vs-reused equivalence: `freshVerdict == reusedVerdict` (PASS == PASS).
- `strictDecision = Reuse(PASS)` via the EXISTING `decideReuseCanonical` (single consistent decision
  model) over 1,254 semantic-candidate deps, all resolved `drDeclared`; the 131 structural reads are
  excluded from the dep set per the S1 finding above.
- Storage is the EXISTING `gate_memo` epoch store (fcUnknown FAIL read-side fail-closed, DEBT#452
  regression green) — no new memo layer. Evidence: `data/benchmarks/verification_reuse_20260903.json`.
- **Existing-store limit surfaced (documented, not patched)**: `loadMemoIndex`'s `MemoIndex` keeps ONE
  entry per gateId per epoch (`entries[gateId] = entry`, last-walk-wins). Multiple canonical identities
  under one gateId collide; our save/lookup paths use distinct logical gateIds per entry. A multi-key
  index is a deferred infra decision.

**Still PROVISIONAL / deferred**: formal promotion of the 131 structural-read verdict-independence
argument into the contract; MemoIndex multi-key support; FAIL-verdict reuse cases; CI/pre-push wiring,
daemon, incremental DAG, build-artifact reuse (NOT in this phase).

---

## 2026-09-03 Deterministic Experiment Replay Harness (Phase 3.0)

**Two-level identity separation (formalized):**
- **ExperimentID** (definition addressing) = `H(fixtureSHA, canonicalMutationSpec, toolchainIdentity, policyDigest)` —
  identifies the *scenario definition*; never contains time/absolute-path/CWD. Used for evidence grouping and
  definition-determinism checks (`definitionIDStable`), NOT as a cache key.
- **Observed canonical VerificationIdentity** = `H(SemanticQuery, ProducerIdentity, dependencyClosureDigest)` —
  computed from the actually materialized substrate; it is the ground truth for reuse. The harness records both
  and asserts the mapping (definition → observed); drift would surface as non-determinism evidence.
- **MemoKey = (gateId, compositeLockHash)** where `compositeLockHash` is the canonical VerificationIdentity
  64-hex **byte-exactly** (no derivation); the same string is stored in `StoredVerificationResult.queryID`.

**gate_memo multi-entry normalization:** `loadMemoIndex` keys by `gateId & "\x1f" & compositeLockHash`;
`lookupMemo` does a direct compound lookup. Save format/CAS/`parseMemoEntry` fcUnknown guard/`pruneStaleEntries`/
`garbageCollectOldEpochs` and all orchestrator consumers unchanged. Multiple canonical identities for ONE gateId
now coexist in one epoch (previously last-walk-wins collision).

**Acceptance (measured, HEAD 1d772c4fa):** harness matrix `[base, base-again, semantic-mutation, neutral-comment,
base-again-2]` — RUN1 (fresh process): gates=2, hits=3 (base-again/neutral/base-again-2 gate-free);
**RUN2 (NEW process, same epoch): gates=0, hits=5** — A(base) and B(semantic-mutation) both replay from the
persistent multi-entry memo. `definitionIDStable=true`. Evidence:
`data/benchmarks/experiment_replay_20260903.json`.

**Found quirk (documented, worked around):** `existsOrCreateDirOpt` swallows ENOENT when the whole
`.axiom/cache/gate_memo` chain is absent → first save silently no-ops → all lookups miss. The harness pre-creates
`GateMemoBaseDir` (the repo's own test idiom). Not patched in gate_memo (infra decision), no behavior change.

**Remaining (honest):** identity closure is the *declared* semantic closure (gate-free deterministic); strace
observation deltas are evidence on fresh runs. Persistent fixture store deferred (482 ms worktree + hardlink-mutation
corruption risk). incremental DAG / daemon / build-artifact cache / CI wiring NOT in this phase.
