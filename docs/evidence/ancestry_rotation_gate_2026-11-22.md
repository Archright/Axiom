# Ancestry three-state repair: rotation gate and zero-observed-failure measurement (2026-11-22)

> Scope: whether the ancestry three-state repair (PR #333, head `e35af1fb6531a733b19c63ba9b14e286480e541e`)
> should be landed now, what blocks it, and what the measured failure rate of the current
> ancestry path actually is on each venue.
> Recorder is not approver: the author is an agent, the approver is the user (wintrover).
> This document records measurements and one decision. It does not change policy, a ruleset,
> a required context, a workflow, or a pin.

## Section 0. Decision

**DEFER_LANDING.** The ancestry three-state repair is not landed in this window. No ruleset
edit was performed and no bypass window was opened. The ruleset `27097366` remains `active`
with `bypass_actors` empty.

The decision rests on two measured facts, not on a preference:

1. The defect the repair addresses has **zero observed occurrences** in the sampled window
   on both venues (Section 2).
2. The repair **cannot land through the normal merge-queue path by design**, and the only
   documented lane is the audited break-glass lane, which requires temporarily editing the
   required-check rulesets (Section 3).

Fact 2 alone would still justify the lane. Fact 1 is what removes the justification, because
the governance cost of a bypass window is real and paid immediately, while the benefit is
currently unobserved.

The distinction this document preserves is the one that matters for authority:

| Claim | Status |
|---|---|
| The verifier's independence invariant is intact and enforced | **Verified** (Section 3) |
| The current verifier has an ancestry defect with measurable production impact | **Not verified, and measured at zero** |
| The repair is correct and tested | **Verified locally and in PR CI** (Section 4) |
| The repair is deployed | **No** |

## Section 1. What the repair is, and why it cannot be dismissed as two changed lines

The current verifier resolves the merge candidate by deepening history in a fixed loop:

- `admission-check.yml` performs `--deepen=64` up to eight times on two independent consumer
  paths (first candidate resolution, and candidate identity re-derivation).
- On exhaustion both paths fail with `CANDIDATE_MERGE_BASE_UNRESOLVED`.
- The unresolved state is indistinguishable from a proven-unrelated state, and both are
  indistinguishable from a fetch failure.

The repair (PR #333) replaces that loop with an explicit three-state contract:

| State | Meaning | Verdict |
|---|---|---|
| `RESOLVED` | required object graph obtained; merge base and tree confirmed | continue verification |
| `UNRELATED` | object graph is complete and the histories are genuinely unrelated | FAIL |
| `UNKNOWN` | objects unavailable, temporary ref gone, fetch failed | fail-closed |

Two details of the contract are load-bearing and were corrected before implementation:

- **Temporary-ref lifetime is not a judgement input.** Objects are fetched to fixed refs
  (`refs/axiom/ancestry/base`, `refs/axiom/ancestry/head`) before judgement, so a queue ref
  removed *after* acquisition does not change the verdict. A ref already gone *before*
  acquisition is `UNKNOWN`, not a silent success.
- **Exit code 128 is not a synonym for unrelated.** `git merge-tree --write-tree` returns
  0 for a clean merge, 1 for a conflict, and anything else for "could not complete". An
  unrelated verdict therefore requires positive discrimination
  (`--allow-unrelated-histories`), not an exit-code match.

The repair also removes the eightfold deepening entirely, so the failure mode "deepen more
and hope" is gone rather than tuned.

## Section 2. Measurement: how often does the ancestry path actually fail?

### 2.1 PR venue

Command (per subject, 60 most recently updated pull requests in any state):

```bash
gh pr list --state all --limit 60 --json number,headRefOid
# for each head SHA:
gh api "repos/Archright/Axiom/commits/<sha>/check-runs?per_page=100" \
  --jq '.check_runs[] | select(.app.id==5795152) | [.conclusion, .output.summary]'
```

Result: 60 subjects, 53 `success`, 7 `failure`. The seven failures decompose into
**6 `trust_surface=FAIL`** and **1 gate-run conclusion failure** (PR #314, which reported
`trust_surface=PASS` and `reasons=conclusion=failure`).

Occurrences of any `CANDIDATE_*` reason code: **0**.

### 2.2 Merge-group venue

Command (per subject, the 40 most recent first-parent merge commits on `main`):

```bash
git log --first-parent --merges -40 --format=%H origin/main
# for each SHA:
gh api "repos/Archright/Axiom/commits/<sha>/check-runs?per_page=100" \
  --jq '.check_runs[] | select(.app.id==5795152) | [.conclusion, .output.summary]'
```

Result: 38 subjects carried a check-run from app `5795152` (2 of the 40 did not), every one
reported `venue=merge_group`, and all 38 concluded `success`.

Occurrences of any `CANDIDATE_*` reason code: **0**.

### 2.3 Limits of this measurement

- The scan surface is the App-issued check-run summary. The callee job log for the sampled
  merge-group run returned no bytes on retrieval, so job-log-level scanning was not
  performed. A verdict whose reason code never reaches the summary would not be counted.
- The two denominators are different populations (recently updated PRs vs recent merge
  commits on main). They are reported separately and never pooled into a single `n`.
- Absence of observed failure is evidence that the current loop is **not currently
  load-bearing**. It is not evidence that the loop is sound, and it is not a prediction
  that it will stay unobserved: a queue ref that outlives the fetch, or a shallower clone
  policy, would change the input distribution without changing the verifier.

Machine-readable form: `data/ci_optimization/ancestry_three_state_gate_2026-11-22/measurement.json`.

## Section 3. Why the repair cannot land through the merge queue

PR #333 was submitted through the normal path. The independent verifier rejected it:

```text
venue=pull_request
head=e35af1fb6531a733b19c63ba9b14e286480e541e
base=1c935b3f84a7c1f2be83f1091d1078be42865305
evaluated_commit=e35af1fb6531a733b19c63ba9b14e286480e541e
run=44987541306 attempt=1 conclusion=success
trust_surface=FAIL -- venue=pull_request manifest_ref=1c935b3 touched=4 manifest_touched=3 diff_base=1c935b3
reasons=mismatch:.github/workflows/admission-check.yml,mismatch:config/policy/epoch_manifest.json,tws_protected_field:trustedAdmissionWorkflowSha
ledger=not-required(preflight venue)
```

This is not a defect and it is not a false positive. It is the independence invariant working:

> `config/policy/trust_surface_manifest.json` declares the execution surface that must be
> byte-identical between an evaluation commit and its base. A PR that alters any listed path
> cannot receive the independent verifier's `admission-check`.

The listed surface contains 18 paths, and the verifier upgrade necessarily moves three of
them in one commit:

- `.github/workflows/admission-check.yml` (the verifier itself),
- `config/policy/epoch_manifest.json` (`productionExecutionPin` is the verifier's blob),
- `config/trusted_writer_set.json` (`trustedAdmissionWorkflowSha` is the same blob).

The manifest is also on the list, so the loop cannot be opened by amending the manifest: that
amendment is a trust-surface change too. **The loop is closed by construction.** A verifier
change is self-authorizing by definition, which is exactly what the invariant forbids, so the
only way through is a lane that is authorized outside the artifact under change.

The documented lane is recorded in `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`
and was used twice, for PR #214 and PR #215: pre-register a MUST-T2a delegation record as a PR
comment, temporarily grant a bypass actor on **both** rulesets that require the check
(`27097366` and `27525972`), merge through the REST API, restore both rulesets, and verify
`bypass_actors` is empty afterwards. That lane is not entered here; Section 0 states why.

## Section 4. What is verified about the repair, and what is not

Verified (in the PR's own CI and locally):

- The two consumer paths call one byte-identical `ancestry_resolve` definition
  (40 lines, 2311 bytes).
- `nim c -r tests/ci/test_sl02_consumer_binding.nim`: exit 0, 14 tests, including the
  fixtures for queue-only base, genuinely unrelated history under a complete graph,
  objects-unavailable, and acquisition-then-ref-removal.
- `verify_trusted_writer_set.sh`: PASS. `git_access_scan.sh`: PASS, 0 breakers.
  `epoch_transaction_gate --diff`: exit 0. `check_nim_theater`: PASS.
- `[L3] promotion coherence` (epoch pin = TWS = verifier blob): success.
- Local script-scan evaluation over the candidate diff: PASS, 0 violations.

Not verified, and therefore not claimed:

- That the new verifier ever executes in production. It cannot, because it is not deployed.
- That the new verifier's `UNRELATED` state is reachable from real queue input. The positive
  discrimination is exercised by fixture, not by an observed production history.

## Section 5. The pin chain, stated precisely

The current production identities on `main` at `4c346b7e` are coherent:

| Fact | Value |
|---|---|
| verifier blob at `main` | `433be3c34c51cfc3fc6f8741009135cfa5906a03` |
| `uses:` pin (commit) at `admission-gate-v2.yml:486` and `:713` | `7f3424cca91f343aa55354b3084af97e30bf65d4` |
| verifier blob inside that pinned commit | `433be3c34c51cfc3fc6f8741009135cfa5906a03` |
| `trusted_writer_set.json:trustedAdmissionWorkflowSha` | `433be3c34c51cfc3fc6f8741009135cfa5906a03` |
| `epoch_manifest.json:productionExecutionPin` | `433be3c34c51cfc3fc6f8741009135cfa5906a03` |

Coherence is the **composition** of two equalities, not one:

```text
two uses pins  --(same commit)-->  7f3424c
                                       |
                                       +-- .github/workflows/admission-check.yml blob
                                       |
                                       +--> trustedAdmissionWorkflowSha
                                       +--> productionExecutionPin
```

The commit SHA and the blob SHA are different values by construction. A promotion procedure
that compares them directly will either fail spuriously or, worse, be "fixed" by writing the
commit SHA into the blob fields.

The verifier blob proposed by PR #333 is `7361f7969fde7456e806ab92e614b2eb4d7f9fb2`. It is a
candidate, not a production value.

## Section 6. The rotation procedure, for the authorization that has not been given

Recorded so the decision is executable later without redesign. Not executed.

1. Pre-register the MUST-T2a delegation record as a PR comment on the rotation candidate,
   before any merge. The record states operator, instruction, and the exact artifacts covered.
2. Confirm the merge queue is empty (`mergeQueue.entries.totalCount == 0`) and that no other
   PR has auto-merge armed. A bypass window is global, not scoped to the PR being landed.
3. Snapshot both rulesets (`GET /repos/Archright/Axiom/rulesets/{27097366,27525972}`) with
   recorded sha256, so restoration is comparable rather than remembered.
4. Add the bypass actor, perform one REST merge with an explicit head-commit match, and
   restore both rulesets immediately after the merge call returns.
5. Verify `bypass_actors == []` and `enforcement == active` on both rulesets by readback.
6. Verify the pin chain using the Section 5 composition, not commit-blob equality.
7. Land the `uses:` pin promotion as a separate PR (Phase B). This second PR does **not**
   change the verifier blob, so it does not require another bypass window.
8. Accept only when a real merge group on the new generation publishes all seven required
   contexts and a landing reaches `main`.

Steps 7 and 8 are the reason the repair is two PRs rather than one: the pin promotion is the
point at which the new verifier becomes the executed one, and that point must be observable
independently of the code change.

## Section 7. Bypass exception record (2026-11-21)

Two different claims must not be merged into one:

| Claim | Evidence class |
|---|---|
| Ruleset `27097366` is active and declares no bypass actor | current readback (Section 8) |
| PR #309 landed while its required `admission-check` was `failure` | durable check-run record |

The second claim, stated exactly:

- PR #309, head `41c02cf096a934cbe1d7e94b96e8adbb2feb0ae6`, merge commit
  `858710ae6f590d7dae06646142e79851dda10721`, `mergedAt 2026-11-21T07:58:46Z`.
- Its `admission-check` check-run from app `5795152` concluded `failure`, reason
  `trust_surface=FAIL`, `mismatch:.github/workflows/publication-integrity.yml,mismatch:config/policy/merge_admission.json`.
- The ruleset's required context set did not change and the check was still required, so the
  landing was not a normal admission.

The configuration timeline is platform-verified, not a session observation. Repository ruleset
history is readable at `GET /repos/{owner}/{repo}/rulesets/{id}/history` and
`GET /repos/{owner}/{repo}/rulesets/{id}/history/{version_id}`:

| version_id | updated_at (UTC) | `bypass_actors` |
|---|---|---|
| `58912954` | `2026-11-21T07:58:16Z` | `[{actor_id: null, actor_type: OrganizationAdmin, bypass_mode: pull_request}]` |
| `58913011` | `2026-11-21T07:59:24Z` | `[]` |

Both versions record `enforcement=active`, and the change actor on `58912954` is user id
`53123826` (`wintrover`). The window is therefore 68 seconds, and PR #309 merged 30 seconds
after it opened. This supersedes the earlier statement in this document that the timeline was
only a session observation: that statement was wrong about the API, and the correction is a
readback rather than a rewording. `docs/agents/axiom_admission_verifier_ops.md` records the
same two version ids independently.

This document does not re-derive any cohort-level bypass statistic. It records one subject
with its own identifiers and stops there.

## Section 8. Authority readback at observation time

```bash
gh api repos/Archright/Axiom/rulesets/27097366 --jq '{name,enforcement,target,bypass:(.bypass_actors|length)}'
```

Result: `name=main`, `enforcement=active`, `target=branch`, `bypass=0`, with seven required
contexts (`admission-check` bound to integration `5795152`, the other six to `15368`), and
merge queue `ALLGREEN`, `max_entries_to_build=100`, `max_entries_to_merge=1`, `MERGE`,
`check_response_timeout_minutes=120`. Unchanged by this work.

## Section 9. Residual state

| Item | State | Owner |
|---|---|---|
| PR #333 (three-state repair) | open, blocked by trust surface, not merged | repository, awaiting rotation authorization |
| `uses:` pin promotion | not started, depends on #333 landing | repository |
| Admission App verdict attribution (#256) | contract handed off, repair not delivered | App owner |
| Outcome-aware rearm | design only; the workflow is not on the trust surface, so it can land normally | repository |
| Job deduplication | closed: both candidates evaluated NOT_REMOVABLE | repository |

The repository can close everything above except the App repair and the rotation
authorization. Neither of those is reachable by a merge into `main`.