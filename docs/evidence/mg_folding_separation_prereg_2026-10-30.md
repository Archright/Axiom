# Pre-registration — merge_group folding separation (attest → ci-cache-publisher base-seed)

> **Status**: PRE-REGISTERED, fixed before landing. This document was committed in the
> same PR as the change it governs and was not edited after measurement began.
> **Date**: 2026-10-30 · **Branch**: `feat/cache-carrier-separation` · **Scope**: single
> change — the 4 cache-preparation steps leave the required `attest / admission-check`
> job; no other step, gate, or required-check surface changes.
> **Measured context** (recent merge_group runs): the 4 steps occupy ~155s inside the
> 306s attest job — "[check] Merge base nimcache carrier" ~64s, "[check] Merge lane-0
> nimcache" ~52s, "[check] Merge lane-1 nimcache" ~39s, "[check] Upload folded
> nimcache" ~8s. (The serial-tail problem and the SLO wall P95 480s goal are separate
> programs; this slice's single threshold is §6.)

## §1. Hypothesis

**The fold is per-future-run cache investment, not a current-run judgment input.**
Moving it out of the required job removes ~155s from the `attest / admission-check`
critical path without changing any judgment outcome.

Step-1 verification evidence (file:line, at the pre-change tree):

- The 4 steps lived at `.github/workflows/admission-check.yml:1091–1120` (comment block
  1068–1090): download job1's `admission-check-base-nimcache` carrier (1096) + lane
  artifacts `go-nimcache-lane-{0,1}-<head>-<attempt>` (1103, 1110) into `build/nimcache`,
  then re-upload the union as `admission-check-base-nimcache` (1116, `overwrite: true`).
  All four are `uses:` actions or `continue-on-error` downloads — no `run:` judgment
  logic.
- **(b) No consumer in the current run**: after line 1120, no step of the attest job
  reads `build/nimcache` (repo-wide grep at the pre-change tree: the only later
  `nimcache` hits are the go-critical-lane header comment, the lane jobs' own
  restore-check at ~3480 and the lane upload at ~3701 — all outside the attest job).
  The judgment chain (identity re-derivation at 1140, D9 staging, subject register,
  attest witness, admission predicate) consumes judgment artifacts (downloaded at
  1055–1066), never the folded cache. The original fold comment itself stated:
  "cache is acceleration, never evidence … The judgment itself is untouched: EXECUTED
  still runs all four tests; only their compile supply warms" (1068–1090).
- **(c) Who consumes the folded carrier**: the only consumer of
  `admission-check-base-nimcache` outside the fold itself is the ci-cache-publisher
  base-seed — `.github/workflows/ci-cache-publisher.yml:618–627` (pre-change), a
  **cross-run** download (`run-id: ${{ github.event.workflow_run.id }}`, `actions: read`)
  that fires only after the whole gate run concludes success (trigger
  `workflow_run` at 170–173, job filter at 199). The publisher saves the B-cache
  (sole writer, `actions/cache/save` at 696–712 pre-change) under the base b-key;
  that cache is restored in **FUTURE** runs by the restore-only B-layer restore
  (`.github/actions/setup-axiom-toolchain/action.yml:395–410`, 9-path list including
  `build/nimcache`). This is exactly the expected future-run investment pattern —
  nothing in the current run's verdict needs the folding to have completed.

## §2. Change

1. `.github/workflows/admission-check.yml` — the 4 folding steps and their comment
   block are DELETED from the `admission-check` (attest) job; a short pointer comment
   remains (post-change ~1068–1075). The judgment-artifact downloads (1055–1066) and
   every other step, permission, name, and condition are untouched. job1 still uploads
   the (unfolded) carrier — the artifact name `admission-check-base-nimcache` continues
   to exist in every gate run.
2. `.github/workflows/ci-cache-publisher.yml` — the fold is absorbed into the
   base-seed path: two degrade-tolerant lane-nimcache downloads
   ("Base seed: fold lane-0/lane-1 nimcache", post-change :659, :669, ids
   `base-lane{0,1}-nimcache-dl`) inserted between the carrier download (:618–627) and
   the single-flight base lookup/save, plus one verdict-log observability line (:765).
   No new job, no new workflow, no new gate, no key/path-list change.

Rejected design (recorded for the audit trail): a sibling job inside the callee
`admission-check.yml`. The required check `admission-check` is NOT a callee job — it is
the org caller's top-level gate job (§3), so a callee sibling would still have delayed
the caller's `attest` conclusion and the required check. Discarded before any landing.

## §3. Placement rationale (why the publisher, not a callee job)

`Archright/.github` `.github/workflows/admission-gate-v2.yml` (org repo, read-only
cited): the required check context `admission-check` is produced by the gate's
top-level job `admission-check` (:671) with `needs: [anchor-resolve, closure-deriver,
attest, mint-prepare, mint-publish, verdict, gateway]` (:673) and the fail-closed step
"[verdict] Every needed job must be success (skipped -> FAILURE, never green)" (~:683).
The caller job `attest` (:430) invokes the Axiom callee
`Archright/Axiom/.github/workflows/admission-check.yml` (:440). GitHub reusable-workflow
semantics: a `uses:` caller job **concludes only when every job of the callee run
concludes**. Any new sibling job inside the callee therefore extends `attest`'s
conclusion → the gate job's `needs` chain → the required check → the merge queue. The
callee is structurally incapable of hosting non-critical work. The publisher is
outside the gate run entirely: it is triggered by the gate run's completion
(`workflow_run`), is not a required check of any kind, and already owns the sole
B-cache write authority. The publisher's base-seed path already downloads the carrier
artifact cross-run, so the lane artifacts (same run scope, same `actions: read`) are
reachable by the same mechanism.

## §4. Fold-input analysis (equivalence inputs, incl. the B-restore contributor resolution)

Exact inputs of the old attest fold, in order: (1) job1's
`admission-check-base-nimcache` carrier (job1's post-build `build/nimcache`);
(2) `go-nimcache-lane-0-<head>-<attempt>`; (3) `go-nimcache-lane-1-<head>-<attempt>`;
downloaded in that order into `build/nimcache`, then uploaded verbatim.

- **Input (1)** is unchanged: job1's upload remains, and the publisher's existing
  carrier download (:618–627) receives it exactly as before.
- **Inputs (2)/(3)** are reconstructed from server truth in the `workflow_run`
  payload: the gate-side lane upload name embeds
  `github.event.pull_request.head.sha || github.event.merge_group.head_sha ||
  github.sha` + `github.run_attempt` (callee-inherited event); the publisher's
  `github.event.workflow_run.head_sha` / `github.event.workflow_run.run_attempt` are
  the same values for the triggering run (head_sha = merge-group head G on
  merge_group runs). On PR-venue runs the lanes legitimately skip and publish no lane
  artifacts → the new downloads degrade (continue-on-error) and the fold union is
  exactly what the old pipeline produced there too (the old fold steps were
  landing-gated and also skipped).
- **B-restore contributor — resolved as content-neutral, not reproduced.** The attest
  stage ran the toolchain composite restore-only (`cache-save-enabled: 'false'`,
  admission-check.yml:872–877), so its exact-key B-layer restore could pre-populate
  `build/nimcache` before the old fold, contributing a fourth input. That contributor
  is non-empty **only when the exact b-key already exists** in the cache service. The
  publisher saves under that same exact b-key **only when the single-flight lookup
  MISSES** (`base-lookup` lookup-only, same key, same 9-path list ⇒ same cache
  version ⇒ identical HIT/MISS semantics). Key HIT ⇒ save withheld (restored bytes
  never reach any save); key MISS ⇒ a hypothetical restore would also have missed
  (contributed nothing). Therefore reproducing the b-restore in the publisher is
  provably content-neutral for the saved cache in every reachable case, and no
  restore step is added. Residual edge (accepted, J3): if the key exists at gate-fold
  time and is evicted before the publisher's lookup (~minutes later — same key, LRU),
  the saved entry lacks the restored contribution; this is a warmth delta on an entry
  that already existed, never a trust input.

## §5. Timing trade-off (honest cost)

The fold now completes after the gate run concludes (publisher lead time), so the
**first** run following a landing-cycle change may restore a B-cache without the fresh
test-supply subtree (or an older one) — cold `nim c` recompiles in the lanes, the
largest attest cost class. This is **performance degradation only, never trust**: the
restore is exact-key, the consumer b-verify discards unverifiable payloads
(fail-closed), and absence degrades to partial warmth (J3 fail-open, documented at the
publisher header and consumer probe). Each successful seeding cycle re-publishes the
full union; the steady-state cadence is unchanged (one fold per gate cycle), only its
position moves.

## §6. Primary metric and guards

- **Primary metric**: per-run merge_group wall-time reduction **≥ 120s** (the ~155s
  the 4 steps occupied inside attest, minus parallel-job overlap slack), observed on
  **≥ 5 post-landing merge_group runs** vs the pre-window baseline.
- **Baseline**: wall p50 968s / p95 1346s (n=144, window 2026-10-16..24).
- **Guard 1 (no harm)**: wall p95 must NOT worsen vs baseline (fail the slice if
  post-landing p95 > 1346s on the measurement window).
- **Guard 2 (cost)**: total job-minutes increase ≤ +10% (extra runner startup for any
  additional job accounted; the chosen design adds zero new jobs/runners — only two
  cross-run artifact downloads inside the existing publisher run).
- Verdict vocabulary: PASS / FAIL per metric, no partial credit; measured numbers only.

## §7. Equivalence criteria

1. **Folded-cache equivalence**: the b-key entry saved by the publisher is
   content-identical to the pre-change pipeline's save (same exact key — keygen
   formula and inputs untouched; same 9-path save list ⇒ same cache version; same
   union order carrier → lane-0 → lane-1; §4 resolves the only extra contributor as
   content-neutral).
2. **Judgment equivalence**: attest judgment logs and the required-check conclusions
   are identical pre/post (no judgment step consumed the fold — §1(b)); the required
   check name set and its semantics are untouched; no requiredValidations /
   trustSurface / merge_cli binding changes in this PR.

## §8. Measurement method

Same definitions as the existing merge-latency measurement program:
wall = run `updated_at − run_started_at` (E3 contract §7.1; attempt-fresh), lane =
per-instance spans, job-minutes = per-job duration sum (`tools/ci/merge_latency_audit.sh`
conventions; regime/decision grammar per
`docs/evidence/merge_latency_decision_prereg_2026-10-13.md` §5.2; percentile method
Hyndman–Fan R-7 per `go_matrix_parallelization_prereg_2026-10-16.md` §4.1). Post
window = the first ≥5 merge_group gate runs after the landing commit; every run in the
window counts (no cherry-picking); failures are reported as failures.

## §9. Failure / rollback

- **Revert**: revert PR of this change (both files return to their pre-change form;
  the fold returns to the attest job; no data migration exists to undo).
- **If trustSurface closure demands** (post-landing verification tooling flags a stale
  pin): re-anchor `config/trusted_writer_set.json` / the admission-check blob
  reference in the policy mirror as the rotation companion, per the later-landing
  convention.
- **Org ruleset re-pin restoration**: if the org ruleset's workflow rule is affected
  by the callee identity change (it should not be — the callee path and required
  contexts are unchanged), restore the previous ruleset pin and take an API readback
  as evidence (drain queue → change ruleset → snapshot → resume ordering per
  rules_workflow.md Mid-queue ruleset mutation ban).
- Rollback trigger: any §6 guard failure or any §7 equivalence violation.

## §10. Landing lane

`.github/workflows/admission-check.yml` is a `trustSurface` member
(`config/policy/merge_admission.json` trustSurface array). Per MUST-T2
(`docs/agents/rules_workflow.md`), this PR lands via the **human manual merge lane** —
it MUST NOT be armed for auto-merge (MUST-T1). Post-landing operator steps if closure
tooling demands: trusted-writer-set/policy re-anchor + org ruleset re-pin with API
readback (§9).
