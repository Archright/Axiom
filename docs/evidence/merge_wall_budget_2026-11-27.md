# Merge wall budget model — wall is the DAG critical path, not the sum of check counts (2026-11-27)

> **Kind**: measurement report (Reporter). This document **creates no verdict** — merge-admission verdicts, policy, and invariants keep their existing authority (`docs/spec/`, `config/policy/`) plus the GitHub ruleset and the App.
> **Measurement source**: the runs/jobs/steps API for **12** merge_group `admission-gate` runs (2026-11-26T03:27:30Z – 23:48:05Z, all success), plus the raw job logs of run `45911585676` (job `140220991383` = `attest / build-base-artifacts`, job `140221285921` = `attest / go-critical-lane (1)`).
> **Scope**: docs only. Workflow, code, and policy changes: **0**. `required_status_checks` (7), the App trust surface (17 paths), the `FROZEN` 3-class layout, and `frozenExceptions` are all **unchanged**.
> **Language**: added lines must satisfy `compliance/policy/script-scan-policy.yml` (Unicode Script must be within Latin/Greek/Common/Inherited), so this document is written in Latin script.

---

## 1. Verdict summary

1. **Merge wall is the DAG critical path.** It is not the sum of checks (required contexts, jobs, steps). So adding verification does **not** grow the wall as long as the new work lands in a lane that is off the critical path.
2. **The 10-minute ceiling already holds.** Over the current generation (n=67, 2026-11-24T12:01:09Z – 2026-11-27T00:48:25Z): p50 **399 s (6.65 min)**, p90 **470 s**, max 713 s, and **zero runs above 720 s**. Averaging in the superseded earlier regime produces a p50 of 544 s that describes no real run (section 2).
3. **The only run above 10 minutes (713 s) was a platform checkout stall, not accumulated verification** — `[build] Checkout B only` spent **307 s** instead of the normal 3–6 s. In the same batch the toolchain step took 44 s, i.e. normal.
4. **There is at least 106 s of slack in lanes that are off the critical path.** New verification should be placed only there (section 7).
5. **The single largest non-verification fixed cost is the toolchain cache transfer**, because the same 1.06 GiB payload is restored **seven times per run** (about 7.95 GB of egress). The portion that lands on the serial critical path measured 31.5 s / 44.6 s / 59.4 s in three runs (10.1% / 12.4% / 17.3% of the wall). An earlier revision of this document counted two restores and reported 49.6 s; that count was wrong (section 5).

---

## 2. Wall distribution — a regime change splits the history

The full run history is **not one population**. There is a sharp, sustained regime change at **2026-11-24T12:01:09Z**: walls go `582, 627` → `427, 406, 360, 358, 400, 359, 386`. The job graph is byte-identical on both sides of the boundary (same 26 jobs, same `go-critical-lane` shards, same `mint-prepare` / `mint-publish`, same skips), so this is a behavioural change, not a job-count change. Averaging across the boundary produces a p50 of 544 s that describes no real run.

| Cohort | Window (UTC) | n | min | p50 | p90 | mean | max | >500 s | >600 s |
|---|---|---|---|---|---|---|---|---|---|
| Full history (all conclusions) | 11-17T05:34:19 → 11-27T00:48:25 | 478 | 247 | 544 | 1369 | 718.1 | 4920 | 285 | 188 |
| Full history (success only) | same | 326 | 277 | 503 | 1216 | 656.5 | 4920 | 171 | 102 |
| **Current generation** (all conclusions) | 11-24T12:01:09 → 11-27T00:48:25 | **67** | 247 | **399** | **470** | **405.8** | **713** | **5** | **3** |
| Current generation (success only) | same | 56 | 312 | 396 | 451 | 399.4 | 713 | 2 | 1 |
| Last 40 successes (baseline re-test) | 11-25T04:38 → 11-27T00:48 | 40 | 312 | 373 | 435 | 387.8 | 713 | 1 | 1 |

Conclusions over the current generation: **56 success / 11 failure / 0 cancelled**. All 11 failures are policy rejections (`admission verdict NOT-ADMIT (reasonCode=ROT_ALLOWLIST)`); **zero timeouts**.

The earlier n=12 sample in this document quoted p50 381 s. That figure reproduces on a wider success-only slice (last 40 successes: p50 373 s, max 713 s, exactly 1 of 40 over 500 s), so it was a fair sample of the **current** generation — it simply could not see the older regime. The current generation is the only cohort relevant to the ceiling.

**Every run over 500 s in the current generation** (5 of 67), with attribution:

| Run | Date (UTC) | Wall | Conclusion | Attribution | Evidence |
|---|---|---|---|---|---|
| 45415238812 | 11-24T14:32:31 | 557 | failure | platform (queue) | no dominant step; longest job 152 s |
| 45415241102 | 11-24T14:32:32 | 653 | failure | platform (cold bootstrap) | `gateway / ci-bootstrap` **180 s** (normally 0) |
| 45415708596 | 11-24T14:35:01 | 536 | success | platform (queue) | longest job 149 s; same 4-way burst |
| 45415710888 | 11-24T14:35:01 | 651 | failure | platform (cold bootstrap) | `gateway / ci-bootstrap` **160 s** |
| 45863436934 | 11-26T16:57:12 | 713 | success | platform (checkout stall) | `[build] Checkout B only` = **307 s**; toolchain in the same job = **44 s** |

**5 of 5 outliers are platform or infrastructure; 0 of 5 are verification growth.** The four 11-24 runs launched within 2.5 minutes of each other (a merge-queue batch) and two of them fell onto a cold `ci-bootstrap` path. The wall is therefore **not a function of the number of checks**: the check graph is constant across the window and p90 is 470 s.

---

## 3. Full decomposition of one batch (run `45911585676`, wall 324 s)

| Job | Seconds | On critical path |
|---|---:|---|
| `closure-deriver` | 80 | no (parallel, idle at 141 s) |
| `attest / build-base-artifacts` | **53** | **yes** |
| `attest / admission-independents` | 81 | no |
| `attest / go-critical-lane (0)` | 91 | no (matrix parallel) |
| `attest / go-critical-lane (1)` | **108** | **yes** |
| `attest / go-critical-rollup` | 4 | no |
| `attest / admission-check` | **62** | **yes** |
| `gateway / select` | 61 | no |
| `mint-prepare / prepare` | **24** | **yes** |
| `mint-publish / publish` | **59** | **yes** (parallel with verdict) |
| `verdict / admission-check` | 58 | no (parallel with publish) |
| `admission-check` (required context) | 3 | **yes** (binding only) |
| **Critical path total** | **309** | 53 → 108 → 62 → 24 → 59 → 3 |
| **Total wall** | **324** | scheduler gap between jobs ≈ 15 |

### 3-1. `attest / build-base-artifacts` = 53 s

| Step | Seconds |
|---|---:|
| Set up job | 2 |
| `[build] Checkout B only` | 6 |
| `setup-axiom-toolchain` | **30** |
| └ keygen (`git archive` + closure digest) | 0.6 |
| └ **A-cache restore (1,136,276,758 B ≈ 1.06 GiB)** | **19.4** |
| └ B-cache restore (53,422,937 B) | 1.2 |
| └ a-verify / a-probe / save-auth and the rest | ≈ 8.8 |
| `[build] Compile derived-closure deriver from B` | 3 |
| upload base-built artifacts / nimcache | 5 + 3 |
| history record x2, Post checkout | 2 + 1 |

This batch had supply-mode **HIT**, so `nimcache functional probe`, `Lake build smoke`, and `Build bin/ax` were **skipped**. The job therefore spends 30 s on provisioning and most of the remainder on upload.

### 3-2. `attest / go-critical-lane (1)` = 108 s

| Step | Seconds |
|---|---:|
| Set up job + checkout B + checkout M | 1 + 7 + 2 |
| `setup-axiom-toolchain` | **41** |
| └ keygen | 0.6 |
| └ **A-cache restore (same 1,136,276,758 B)** | **30.2** |
| └ B-cache restore | 2.7 |
| └ remainder | ≈ 7.5 |
| Download base-built artifacts | 4 |
| Candidate identity + Judgment CAS plan + Overlay M | 1 + 5 + 1 |
| **`[lane] evidenceId contract check` (self-check battery)** | **35** |
| GO-critical admission tests | 1 |
| upload judgment files + nimcache | 1 + 5 |

The `A-cache` entry is the **same a-key and the same ≈ 1.06 GiB** in both jobs, and both report `exact-hit=true`. Those two are only the critical-path pair: the same payload is in fact restored in **seven** jobs per run (section 5), under three different action-id namespaces, which is why a two-job count is easy to make and wrong.

---

## 4. Where the wall actually comes from — and what "slack" really means

An earlier revision of this document described the interval between `gateway/select` finishing and `mint-prepare` starting as **≈ 106 s of idle** and told new checks to hide inside it. Both halves of that were wrong.

Measured across four runs, that interval is **median 86 s (range 84–142 s)**, and it is **not idle**: `attest / admission-check` runs inside it on every run. `mint-prepare` is gated on the attest stage, not on `gateway/select`, so removing `gateway/select` would reclaim approximately nothing.

| Run | Wall | `gateway/select` end | `mint-prepare` start | Interval | Occupied by `attest / admission-check`? |
|---|---|---|---|---|---|
| 45911585676 | 324 s | 147 s | 233 s | **86 s** | yes — 169→231 s |
| 45918881224 (PR #511) | 343 s | 177 s | 261 s | **84 s** | yes — 182→259 s |
| 45917004272 | 312 s | 137 s | 223 s | **86 s** | yes — 141→220 s |
| 45915810375 | 359 s | 122 s | 264 s | **142 s** | yes — 198→262 s |

The defensible statement is therefore structural, not a window: **the wall is the longest dependency chain, so a new check raises the wall only if it becomes the last term of that chain.** A check that runs in parallel with, or earlier than, the current last term costs nothing in wall time — but a check that merely *appears* to fit in a gap may still be occupying that gap for a reason.

| Point | Finish / start | Basis |
|---|---|---|
| `verdict` finish | ≈ 281 s | 247 + 58 (parallel with publish, so it does not dominate) |
| `go-critical-lane (0)` finish | 91 s | sharded in parallel; the 108 s shard dominates |
| Off-wall lanes (same batch) | bsec 99 / debt 78 / observer 64 / generation 34 / probe 15 | all finished before 141 s |

---

## 5. Non-verification fixed-cost inventory (can it be reduced?)

| Item | Amount | Critical-path contribution | Verdict |
|---|---|---|---|
| toolchain A-cache restore (**7 jobs x 1.06 GiB**) | 1,136,276,758 B x7 ≈ 7.95 GB egress/run | **31.5–59.4 s on the serial path (10.1–17.3%)**; ~160–178 s of total restore time across jobs, mostly parallel | **Not reducible by deleting a job** — six of the seven restores are parallel, so only the critical-path pair sets the wall, and both `lean --version` (go-critical) and `lake build` (build-base, on supply MISS) need the payload. The org is on the **free plan with a public repo**, so larger runners, custom images, and self-hosted runners are not available, and `jobs.<id>.container` runs a `docker pull` before the steps per job, which adds wall time. This is the largest identified fixed cost. |
| B-cache transfer | 53,422,937 B x2 | 1.2 + 2.7 s | Not reducible (the B payload is itself the supply) |
| `evidenceId contract check` | 35 s per lane (the span section 3-2 records) | that lane's span, on whichever lane is on the chain | **Duration reducible; the second execution is not removable.** It runs in **both** lanes of the `matrix: lane: [0, 1]` job (`admission-check.yml:3985`, step `:4479`), i.e. **twice per cycle**; per-lane independent execution is contractual, the run time is not. Not a duplicate: it is pure verification. Correction dated 2026-11-27 below. Standalone profile: [vs_t3_evidenceid_battery_profile_2026-11-16.md](vs_t3_evidenceid_battery_profile_2026-11-16.md). |
| checkouts | 6 + 7 + 2 s | 15 s | Not reducible (contract: one job sees two trees) |
| artifact upload | 10 s | 10 s | Not reducible (consumed downstream) |
| attest → mint envelope | job-boundary gap ≈ 15 s | 15 s | Not reducible (GitHub job scheduler) |

**Correction, 2026-11-27 - the `evidenceId` accounting.** The `evidenceId contract check` row above was wrong on two counts, and both are corrected here rather than silently edited.

1. **It does not run "exactly once across the whole pipeline".** The step sits inside the `go-critical-lane` job, which is a `matrix: lane: [0, 1]` job (`admission-check.yml:3985`; the step is at `:4479`, inside that job). Each lane therefore runs its own battery, so one cycle runs **two** executions, not one. Measured: **51 s in lane (1)** (job `140431436082`) and **36 s in lane (0)** (job `140431436099`) on run `45976958813`, head `87c480f4`. The double execution is also present in the batch that section 3 decomposes: run `45911585676`, lane (1) **35 s** (job `140221285921`) and lane (0) **53 s** (job `140221285964`). The "35 s" in section 3-2 is a correct **single-lane** span that was read here as a pipeline-wide single execution; the number stands, the reading of it does not. The repository's own battery profile already states both lanes (lane (0) 99.0 s, lane (1) 77.3 s) - [vs_t3_evidenceid_battery_profile_2026-11-16.md](vs_t3_evidenceid_battery_profile_2026-11-16.md), section 1.
2. **"Not reducible" is wrong for the duration.** What is contractual is the per-lane **independent execution**, not how long one execution takes. `docs/design/admission_gate_performance_cutover_design_2026-11-13.md` lists it as a preservation invariant (`:69`, item 2) and records sharing one battery across both lanes as explicitly **excluded** (`:58`, an "explicit exclusion" tier, section 0.9 adjacent) - so the second execution cannot be removed without amending the binding preregistration. Shortening the battery's own run time is, by contrast, the **sanctioned** lever: `:45` puts battery optimization in Tier 3, product/tool code, contract-preserving and landed as a separate slice. That the duration is reducible is measured, not assumed: the same design document's in-tree profile (`:140`) attributes the probe's 46 s to a single `sha256` pass over the 119,585,096 B `ircheck` binary in a debug build, with the identical digest reachable in 0.68 s at 114 MB/s in a release build. A speed-up of the probe is **in progress as a separate PR**; its result is not stated here.

**What this changes in the model, and what it does not.** The item's wall contribution is one lane's span - the on-chain lane's, 51 s at `87c480f4` - not the 36 + 51 s sum, because the other lane runs it in parallel off the path. Nothing else in this section moves: the battery is still pure verification rather than a duplicate, and the toolchain restore is still the largest identified fixed cost. The paragraph that follows ("the only large lever left") is about the non-verification fixed costs in the table and is unaffected; the battery's duration is a separate, in-progress lever.

**The only large lever left is the App's blob-equality protection contract (`DEBT#558`), which is App-owned authority.** Reimplementing it inside the repository would violate the trust boundary (section 0.3 of AGENTS.md).

---

## 6. Discarded optimization candidates — do not re-investigate

These are pinned with measured values so the same discussion does not reopen and create another bypass precedent.

| Candidate | Expected | Measured | Verdict |
|---|---|---|---|
| keygen `git archive` pathspec narrowing (`action.yml:307-308`) | 5–15 s per job | Reducing the tree from 6,895 files / 93,559,605 B to a closure of 1,478 files / 17,147,416 B moved **archive creation from 310 ms to 75 ms**. Measured keygen step: **0.6 s** | **Discarded** — worth about 0.4 s of wall, and `.github/**` is App trust surface, so it is not worth one bypass |
| `http.lowSpeedLimit/lowSpeedTime` on the B checkout | bounded tail | `lowSpeedLimit 1024` (1 KiB/s) does **not** fire on the observed stall (204 MB / 307 s ≈ 664 KiB/s). Raising the threshold to fire makes `actions/checkout` hard-fail after 3 retries x 120 s ≈ **390 s**, which is worse for developers than the slow 307 s success | **Discarded** |
| path filter / affected-only execution | skip | Official docs: if a required workflow is skipped by a path filter, its check stays **Pending** and the PR merge is **blocked**. The `merge_group` trigger has no `paths`/`paths-ignore` key | **Not possible** |
| `go-critical-lane` → `provision-scope: nim` | 30 s | `admission-check.yml:4486-4488` is **fail-closed** when `lean --version` fails. Lean is required | **Not possible** |
| move the supply verdict ahead of provisioning | 19.4 s | `[s5]` reads `build/nimcache`, which is an artifact of the **B-cache restore**. A data dependency forbids reordering | **Not possible** |
| merge `build-base` + `go-critical-lane` into one job | 41 s | `go-critical-lane` is a **2-shard matrix running in parallel** (91 s / 108 s). One job would serialize to ≈ 199 s, i.e. **worse** | **Discarded** |
| `FROZEN` / trust-surface pruning | — | Reduces local and push friction only; wall contribution ≈ 0. The two-step bypass rite is App-owned semantics | **Out of scope here** |

---

## 7. Placement rule for new verification (the practical output of this document)

**R1 (declare).** A new check declares (i) its lane and (ii) that lane's expected finish time.

**R2 (max, not sum).** Budget is `max(lane finish time)`, not `Σ(check duration)`. The number of checks is not a budget metric.

**R3 (exceeding the critical path = budget amendment).** If the finish time of the lane a new check joins exceeds the current critical-path finish (**309 s** for this batch), that is not "adding a check" but an **explicit amendment of the 10-minute budget**, and it requires separate approval and justification.

**R4 (do not skip).** Do not exempt a check through path-based skipping — the required check would stay Pending and block the merge. Keep the budget by **lane placement**.

**R5 (where to add, corrected).** There is no idle window to hide in — the interval between `gateway/select` and `mint-prepare` is occupied by `attest / admission-check` on every measured run (section 4). The usable rule is: place new work so it does **not** become the last term of the longest chain, and prefer attaching it to a lane that already finishes earlier than the last term. On current data the chain ends with `attest` → `mint-prepare` → `mint-publish`, so work attached to `build-base` or to a `go-critical-lane` shard costs nothing, while work appended after `mint-publish` costs all of its own duration. The only two levers that provably shorten the chain are the toolchain restore on the critical path (section 5) and the `evidenceId` battery that dominates the slowest `go-critical-lane` shard.

---

## 8. Reproduction commands

```bash
# 8-1. wall distribution (n=12)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" \
  --jq '[.workflow_runs[]|select(.name=="admission-gate")]|sort_by(.created_at)|reverse|.[0:12][]|[.id,.created_at,((.updated_at|fromdate)-(.created_at|fromdate))]|@tsv'

# 8-2. job timeline of one batch
gh api "repos/Archright/Axiom/actions/runs/45911585676/jobs?per_page=100" \
  --jq '.jobs[]|[.name,.conclusion,((.completed_at|fromdate)-(.started_at|fromdate))]|@tsv'

# 8-3. step decomposition (including inside the toolchain action)
gh api repos/Archright/Axiom/actions/jobs/140220991383/logs > /tmp/bb.log
awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+Z ##\[group\]/ {
  d=substr($0,1,19); gsub(/[-:T]/," ",d);
  t=mktime(d)+substr($0,20,8);
  title=$0; sub(/^[^ ]+ ##\[group\]/,"",title);
  if (n>0) printf "%6.1f  %s\n", t-prevt, prevtitle;
  prevtitle=title; prevt=t; n++ }' /tmp/bb.log
grep -n "Cache Size" /tmp/bb.log
```

**Expected observation for 8-3**: `Run ./.github/actions/setup-axiom-toolchain` → keygen **0.6 s** → `actions/cache/restore` **19.4 s** (`Cache Size: ~1084 MB (1136276758 B)`).

---

## 9. Limitations

1. This document is a **Reporter**. It is not a gate, and it adds no new `make` target, workflow job, or verdict producer.
2. The **ceiling** statement rests on the current generation (n=67 across 2026-11-24T12:01:09Z – 2026-11-27T00:48:25Z), not on the 12-run subset that revision 1 used. Platform network variance (the 713 s run in section 2) can recur regardless of sample size.
3. A-cache restore time varied between **15.5 s and 34.5 s per job for the same payload**, and the serial-path sum between 31.5 s and 59.4 s across runs. That spread is a property of the cache service and the network, not of repository code.
4. The defect where `recipe_hash` (`action.yml:350`) reads `Makefile config.nims config/effects.nims src/gate/config.nims` from the **working tree** is only **reported** here (a separate matter that moves the B key generation).
5. The "not reducible" verdicts in section 5 depend on this repository's platform conditions (free plan, public repo, hosted runners). They must be re-evaluated if those conditions change.
6. The sample now spans a **regime change at 2026-11-24T12:01:09Z**. Only the current generation (n=67) bears on the ceiling. The 411 pre-boundary runs contain 280 further runs over 500 s that were characterised statistically but not attributed individually, because they belong to superseded workflow behaviour.
7. The cause of that regime change is **UNCONFIRMED**: the job graph is byte-identical on both sides, and the workflow-file commit history was not inspected.
8. The tail is not fully domestic: a checkout stall and a cold `ci-bootstrap` can each add 100–390 s with no warning. With p90 at 470 s the headroom is about 130 s, thinner than p50 implies, and a coincidence of a stall and a cold bootstrap inside one 600 s window is plausible though not observed (0 of 67 above 720 s).

---

## 10. Revision record

**Revision 2 (2026-11-27).** Three numbers in revision 1 were wrong, and the error was in the direction of making the budget look more addressable than it is. They are corrected here rather than silently edited, because the placement rule R5 was derived from one of them.

| Claim in revision 1 | Measured | Effect on the rules |
|---|---|---|
| A-cache restored in **2** jobs, 49.6 s = 15.3% | restored in **7** jobs, ≈ 7.95 GB egress; 31.5–59.4 s on the serial path | R2 unchanged; section 5 inventory corrected upward |
| **≈ 106 s idle** between `gateway/select` and `mint-prepare` | median **86 s** (84–142), **occupied** by `attest / admission-check` | **R5 rewritten** — there is no idle window; the rule is now "do not become the last term of the chain" |
| n=12, p50 381 s, 1 of 12 over 500 s | reproduces on last-40 successes (p50 373 s); current generation is n=67, p50 399, p90 470 | R3's 309 s batch figure stands; the ceiling statement is now cohort-scoped |

R1, R2, R3 and R4 are unchanged. The finding that the wall is the DAG critical path rather than the sum of check durations is unchanged and is now supported at n=67 with per-outlier attribution.

**Revision 3 (2026-11-27).** One row of the section 5 inventory was wrong on two counts, both in the direction of making the item look untouchable. It is corrected in place with a dated note rather than silently edited, and nothing else in this document changes.

| Claim in revision 2 | Measured | Effect on the rules |
|---|---|---|
| `evidenceId` battery: **35 s**, "runs **exactly once** across the whole pipeline", **not reducible** | runs **once per lane** (`matrix: lane: [0, 1]`), i.e. **twice per cycle**: 35 s + 53 s at run `45911585676`; 36 s + 51 s at run `45976958813` (head `87c480f4`). Only the on-chain lane's span is on the critical path | R5 unchanged in direction and corrected in content: the lever is the battery's **run time** (contract-preserving, Tier 3), not the number of executions (contractual). R1-R4 unchanged; section 5 row and its correction note updated |