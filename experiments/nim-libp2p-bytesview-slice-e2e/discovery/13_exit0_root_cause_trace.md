## Summary

The parallel path is **not** the divergence. Both the sidecar and d2 precedents used the identical pre-computed ("parallel path") branch and both exited 1. Our lane diverges because the **subject symbol is a Nim `template`**, which the pre-sieve treats as a fatal "non-routine" block — so the node is terminated as `PRE-SIEVED` *before* the IR verdict is ever consumed.

---

## 1. The three paths

### (a) P4 `vsDisproved` → FAILED node → `failedCount`/`statusCounts.failed` → exit 1

Only one terminal in the whole engine consumes `vsDisproved`:

- `src/verification/batch_uap/loop_driver.nim:474-492` — `stage2Budget` returns `BudgetedPayload(verified: false, skipReason: osrNone)` for `irResult.verification.status == vsDisproved` (P4-promoted, `cvConfirmed`).
- `src/verification/batch_uap/loop_driver.nim:1112` (`stage2Budget` call) → `:1131-1140` (`not budgeted.verified` → `orchestrationProofFailed`) → `:1149-1160` (node report) → `:1161-1169` (log `"— failed"`).
- `src/cli/wf_render.nim:398-406` (`orchestrationProofFailed` → `failedCount++`) and `:423-427` (`statusCounts["failed"]++`).
- `src/verification/accounting/run_accounting.nim:226-231` (`"failed"` → `voUnsatisfied`), `:767-771` (`unsatisfiedCount++`), `:811` (count invariant) → `proofFailedCount`.
- `src/cli/axiom_engine.nim:650-653` → `src/cli/wf_runners.nim:46-72` (`axProofShortcutExitCode`) → `src/core/utils/decision_algebra.nim:213-220` (`failedCount > 0` → `OutcomeBlock`) → `src/cli/cli_outcome.nim:43-51` (`VERIFICATION_FAILURE` → exit 1).

**A failed node row is the only route to exit 1** — the exit rule reads `summary.failedCount` alone.

### (b) Certificate file with `.counterExample` — **this path does not exist**

`writeCertificateFromUapResult` (`src/verification/cert_writer.nim:238-258`) has **no `counterExample` parameter**, and is invoked only for *verified* nodes: `loop_driver.nim:1196-1215` (sequential) and `loop_depth_scheduler.nim:563-570` (worker>1). So no `<vault>/<irHash>.json` with a payload is ever produced — **not in our run, not in the d2 lane, not in the sidecar run** (their evidence dirs contain only `manifest.json`).

Where the payload *is* persisted (and it is — the premise "persisted nowhere" is wrong):
- `src/cli/axiom_engine.nim:630-648` — `r.counterExample` → `reportJson["unitEvidenceRefs"]["libp2p/utils/bytesview.nim::toOpenArray"]["counterExample"]`. Confirmed present in `/tmp/libp2p_bv_smoke2/state/logs/ax_prove_trajectory.jsonl` (line 2, `extra.unitEvidenceRefs`) with all 13 records and `claimOutcome: clDisproved`.
- Manifest row: `src/cli/axiom_engine.nim:439-448` (`psFail` → `"certRed"`, `mergeResult(cert.functionName, …)`).

### (c) Journal entry — exists, but it is the **manifest** journal

`src/verification/vault_manifest.nim:105-135` — `atomicWriteManifest` writes a `tcVerifiedProof` TrustCommit of the manifest into `data/trusted/journal/`. Our vault has 6 such entries; the last one contains our `libp2p/utils/bytesview.nim::toOpenArray / certRed / irHash 7f3aa1ae…` row. A *certificate* journal (`cert_writer.nim:159-180`) only occurs on the certificate-write path (verified nodes).

---

## 2. The parallel (pre-computed) path — equivalent terminal, one asymmetry

`src/verification/batch_uap/loop_driver.nim:771-790` (parallel) vs `:791-832` (sequential):

- Both merge into `irResultMap` keyed by `irResult.funcName` (`:775-780` vs `:826-832`) — identical.
- Both then feed the **same** node pipeline (`stage1CacheCheck` → `stage2Budget`), so the `vsDisproved` terminal at `:474` is reachable in the pre-computed path. Proven by the precedents: `experiments/sidecar-adoption-e2e/runs/d1_stderr.log:31` "using 6 pre-computed results (parallel path)" → `:47` "— failed"; `experiments/act2-wp-toml-b1-input-integrity/p0d2g/evidence/defect/e_defect.err:38` same line → `:54` "— failed".
- **One asymmetry:** only the sequential branch records `irPipelineFailures` (`:819-825`); the parallel branch only logs (`:782-789`). This channel is scope-observability only (`axiom_engine.nim:622`, `:4365-4372`) — it does **not** feed the exit axis, so it is not the cause of exit 0 (but it is a real pre-existing gap: our carrier's `psFail` was logged and never recorded as a verification failure in the parallel branch).
- Separate pre-existing gap: the multi-worker node path (`loop_depth_scheduler.nim`) never consults `irResultMap` at all → no `vsDisproved` terminal there (our run used workers=1).

---

## 3. Where our run diverges

Our wave-facing entry is **not** deficient — it is byte-identical in shape to the precedents: `src/cli/axiom_engine.nim:3282-3283` does `waveEntry.name = examinedFn` (same as d2 `:3098-3099`, sidecar `:3499-3500`). The manifest rows match too (ours: `toOpenArray/certRed` + `bvSliceLenControl/certZ3Candidate`; d2: `scanString/certRed` + `d2CommentGateReject/certZ3Candidate`).

The divergence is the **subject symbol kind**:

- `libp2p/utils/bytesview.nim::toOpenArray` is a `template` (`nim-libp2p/libp2p/utils/bytesview.nim:18`; topology `nodeType: "template"` confirmed in `state/.axiom/cache/topology_merkle.json`).
- `src/sieve/sieve_rules.nim:179-189` — `nodeType ∈ nonRoutineKeywords` → verdict `blocked_non_routine`.
- `src/verification/batch_uap/stages.nim:307-316` — `blocked_non_routine` is in the **fatal** list → `isPreSieveTerminalBlock = true`.
- `src/verification/batch_uap/loop_driver.nim:187-209` — fatal block → `CachedPayload(blocked: true)` (no carve-out; the carve-out at `:197-213` applies only to opinion-only blocks).
- `src/verification/batch_uap/loop_driver.nim:1088-1104` — `if cached.blocked:` → node report `orchestrationPreSievedUnverifiable` / `"PRE-SIEVED"` → **`continue` at `:1104`, i.e. before `stage2Budget` at `:1112`**. The carrier's `vsDisproved` is never read (`scopedIrResultForNode` at `:1045` would have matched: key `toOpenArray`, module `libp2p/utils/bytesview.nim`).
- `wf_render.nim:413-414, 440-441` → `pre_sieved` (not `failed`) → `failedCount = 0` → `decision_algebra.nim:219` not reached → `OutcomeContinue` → exit 0. Accounting: `run_accounting.nim:231` → `voPending` → `pendingCount=1`, `unsatisfiedCount=0` → verdict INCONCLUSIVE.

Precedents contrast:

| run | subject | pre-sieve | node | exit |
|---|---|---|---|---|
| sidecar d1 | `decodedLength` (func) | `[PRE-SIEVE CARVE-OUT] … overridden` (d1_stderr.log:46) | `— failed` (:47) | **1** (ACCEPTANCE.md:11,21,95) |
| d2 toml | `scanString` (proc) | admitted | `— failed` (e_defect.err:54) | **1** (`e_defect.exit` = 1; `ax_proof_state.json`: failedCount=1, unsatisfiedCount=1, verdict FAIL) |
| ours | `toOpenArray` (**template**) | fatal `blocked_non_routine` | `— pre-sieved` (smoke2:57) | **0** |

---

## 4. Verdict

**(i) — a gap in our lane's integration, but not "the entry lacks a field".** The wave-facing entry is identical to d2's; the lane's *subject* is a template, so the wave node is fatally pre-sieved before the IR verdict is consumed. The result is that a replay-confirmed disproof of an adopted claim (`clDisproved`, 13-record `rvAgree` payload) exists in the claim axis but has **no** verification-axis node, no `failedCount`, and exit 0 — the defect is structurally invisible to the exit rule. (ii) is ruled out (same parallel path produced failedCount=1/exit 1 in both precedents). (iii) is only half-true: pre-sieving a template is a correct sieve rule, but it must not swallow a P4-promoted disproof the engine itself wave-faced onto that node (the lane's own comment says "the disproof attributes to the frontier node whose eligibility this synthesis decided" — `axiom_engine.nim:3275-3278`).

**Minimal fix location: `src/verification/batch_uap/loop_driver.nim:1088-1104`** (the `if cached.blocked:` branch). The scoped IR result is already available at that point (`attemptIR = scopedIrResultForNode(irResultMap, nodeIdStr)`, `:1045`). Change: when the node's scoped IR result is a P4-promoted disproof (`verification.status == vsDisproved`), do not emit the PRE-SIEVED report and do not `continue` — fall through to `stage2Budget` (`:1112`), whose existing terminal (`:474-492`) produces `orchestrationProofFailed` → `failedCount=1` → exit 1. This keeps the exit rule, the sieve rules, and the summary schema untouched, and reuses the single existing `vsDisproved` terminal.

Two secondary items (not required for exit 1, but real):
- `loop_driver.nim:771-790` — the parallel branch drops `irPipelineFailures` (present only at `:819-825`); our carrier's `psFail` was logged but never recorded as a verification failure there.
- If a certificate **file** carrying the payload is required, that capability does not exist in the Nim lane at all (`cert_writer.nim:238-258` has no `counterExample` slot); the payload's canonical home is the trajectory claim map (`axiom_engine.nim:644-645`) plus the manifest `certRed` row and its manifest journal entry.