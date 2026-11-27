# Merge wall budget model — wall is the DAG critical path, not the sum of check counts (2026-11-27)

> **Kind**: measurement report (Reporter). This document **creates no verdict** — merge-admission verdicts, policy, and invariants keep their existing authority (`docs/spec/`, `config/policy/`) plus the GitHub ruleset and the App.
> **Measurement source**: the runs/jobs/steps API for **12** merge_group `admission-gate` runs (2026-11-26T03:27:30Z – 23:48:05Z, all success), plus the raw job logs of run `45911585676` (job `140220991383` = `attest / build-base-artifacts`, job `140221285921` = `attest / go-critical-lane (1)`).
> **Scope**: docs only. Workflow, code, and policy changes: **0**. `required_status_checks` (7), the App trust surface (17 paths), the `FROZEN` 3-class layout, and `frozenExceptions` are all **unchanged**.
> **Language**: added lines must satisfy `compliance/policy/script-scan-policy.yml` (Unicode Script must be within Latin/Greek/Common/Inherited), so this document is written in Latin script.

---

## 1. Verdict summary

1. **Merge wall is the DAG critical path.** It is not the sum of checks (required contexts, jobs, steps). So adding verification does **not** grow the wall as long as the new work lands in a lane that is off the critical path.
2. **The 10-minute ceiling already holds.** Over the n=12 window: p50 **381 s (6.35 min)**, mean 405 s (6.75 min), max 713 s. Eleven of twelve are **under 8 minutes**.
3. **The only run above 10 minutes (713 s) was a platform checkout stall, not accumulated verification** — `[build] Checkout B only` spent **307 s** instead of the normal 3–6 s. In the same batch the toolchain step took 44 s, i.e. normal.
4. **There is at least 106 s of slack in lanes that are off the critical path.** New verification should be placed only there (section 7).
5. **The single largest non-verification fixed cost is the toolchain cache transfer at 49.6 s = 15.3% of the wall**, because two jobs each receive the same 1.06 GiB payload (section 5).

---

## 2. Wall distribution (merge_group `admission-gate`, n=12)

| Metric | Value |
|---|---|
| Sample | 12 (2026-11-26T03:27:30Z – 23:48:05Z, all success) |
| Min | **314 s** |
| p50 | **381 s (6.35 min)** |
| Mean | 405 s (6.75 min) |
| Max | **713 s (11.9 min)** — one run |
| Over 500 s | **1 / 12** |

Raw values (seconds, newest first): `334, 324, 362, 713, 362, 450, 348, 314, 416, 418, 417, 400`.

**Attribution for the 713 s run**: in that batch (run `45863436934`) `attest / build-base-artifacts` went from 47 s to **374 s**, and nearly all of the excess is `[build] Checkout B only` = **307 s** (normal 3–6 s). `setup-axiom-toolchain` in the same job stayed at 44 s, inside the normal range. The wall is therefore **not a function of the number of checks**.

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

The `A-cache` entry is the **same a-key and the same ≈ 1.06 GiB** in both jobs, and both report `exact-hit=true`.

---

## 4. Slack calculation — why adding verification does not grow the wall

| Point | Finish / start | Basis |
|---|---|---|
| `gateway/select` finish | **141 s** | closure-deriver 80 + 61 |
| `mint-prepare` start | **≈ 247 s** | 53 + 108 + 62 + gaps |
| **Idle** | **≈ 106 s** | verification added inside this window leaves the wall unchanged |
| `verdict` finish | ≈ 281 s | 247 + 58 (parallel with publish, so it does not dominate) |
| `go-critical-lane (0)` finish | 91 s | sharded in parallel; the 108 s shard dominates |
| Off-wall lanes (same batch) | bsec 99 / debt 78 / observer 64 / generation 34 / probe 15 | all finished before 141 s |

**So the claim "adding verification pushes CI upward" holds only for the critical path.** As long as an added check finishes inside the idle window in section 4, the wall does not move.

---

## 5. Non-verification fixed-cost inventory (can it be reduced?)

| Item | Amount | Critical-path contribution | Verdict |
|---|---|---|---|
| toolchain A-cache transfer (2 jobs x 1.06 GiB) | 1,136,276,758 B x2 | **49.6 s (15.3%)** | **Not reducible** — payload is `~/.nimble`+`~/.choosenim`+`~/.elan`+`~/.local/bin`. Both jobs need it: `lean --version` (go-critical) and `lake build` (build-base, on supply MISS). The org is on the **free plan with a public repo**, so larger runners, custom images, and self-hosted runners are not available, and `jobs.<id>.container` runs a `docker pull` before the steps per job, which adds wall time. |
| B-cache transfer | 53,422,937 B x2 | 1.2 + 2.7 s | Not reducible (the B payload is itself the supply) |
| `evidenceId contract check` | 35 s | 35 s | **Not reducible** — it runs **exactly once** across the whole pipeline (`admission-check.yml:4479`). Not a duplicate: it is pure verification. Standalone profile: [vs_t3_evidenceid_battery_profile_2026-11-16.md](vs_t3_evidenceid_battery_profile_2026-11-16.md). |
| checkouts | 6 + 7 + 2 s | 15 s | Not reducible (contract: one job sees two trees) |
| artifact upload | 10 s | 10 s | Not reducible (consumed downstream) |
| attest → mint envelope | job-boundary gap ≈ 15 s | 15 s | Not reducible (GitHub job scheduler) |

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

**R5 (where to add).** The largest current slack is the **≈ 106 s** between `closure-deriver` (80 s) and `mint-prepare` (247 s). Place new lanes so they finish inside that window.

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
2. The sample is **12 runs from a single date**. Platform network variance (the 713 s run in section 2) can recur regardless of sample size.
3. A-cache transfer time varied between **19.4 s and 30.2 s** for the same payload (two jobs, one run). That spread is a property of the cache service and the network, not of repository code.
4. The defect where `recipe_hash` (`action.yml:350`) reads `Makefile config.nims config/effects.nims src/gate/config.nims` from the **working tree** is only **reported** here (a separate matter that moves the B key generation).
5. The "not reducible" verdicts in section 5 depend on this repository's platform conditions (free plan, public repo, hosted runners). They must be re-evaluated if those conditions change.