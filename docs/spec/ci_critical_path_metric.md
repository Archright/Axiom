# CI critical-path metric — canonical definitions (VS-1a)

> **Status**: measurement definitions frozen — **v2 revision (2026-11-24)**.
> **Created**: 2026-11-20 · **Revised**: 2026-11-24
> **Baseline**: `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json`
> **Evidence**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md`, `docs/evidence/ci_admission_measurement_2026-11-24.md`
> **Revision basis**: v1 excluded the workflow that actually defines the admission wall from the measured set (§0.1). v2 repairs the cohort, the attribution, and the graph authority, and splits the measured object in two (§3).
> **Language**: this revision is authored in English per [ADR-0045](../adr/0045-english-only-canonical-main.md). The Korean text of the prior revision remains the historical record in git. This document is not a translation batch and makes no translation-lineage claim.
> **Protection grade**: this document belongs to neither the trust surface manifest, `trustSurface`, nor the checker closure — a revision requires no trust rotation.

## §0. Purpose

A CI optimization decision must rest on a **reproducible attribution** of "what is slow". This document freezes the formulas for the metrics computed from GitHub Actions' existing REST records alone. No new observation service, SaaS, or instrumentation code is introduced.

These definitions are **for performance measurement only**. No metric here is evidence for an admission verdict, for evidence, or for cache trust.

### §0.1 The defect v2 repairs

v1 §1 fixed the measured target to `admission-gate` (`admission-gate-v2.yml`). Across the five merge queue cycles observed, **the last context to finish was `readiness-verdict` in four of them**, and `admission-gate` was not the last finisher in any cycle. v1's default cohort was therefore **measuring a workflow that does not define the admission wall** — a blind spot over the dominant path.

| item | v1 | v2 |
|---|---|---|
| default target | `admission-gate` only | `axiom-operational-slice` (primary) + `admission-gate` (secondary, comparison) |
| `criticalPathSeconds` | backtracking chain over the declared `needs` graph with a 2-second tolerance | per-workflow longest path over the `needs:` DAG (§2.5) |
| `queuedSeconds` | a single sum that assumed `created_at` was authoritative | two distinct phenomena + `NO_LOG_SOURCE` (§2.3) |
| job → node attribution | unspecified (assumed record name = job id) | prefix attribution contract (§7.1) |
| `needs` graph authority | source unspecified | YAML at the candidate SHA + recorded blob SHA (§7.4) |
| measured object | workflow wall and admission wall mixed in one table | separated (§3) |

Numbering contract: §4–§6 and §2.x are referenced by existing documents and code, so **they are not renumbered**. §3 is where v1 had an authoring gap (§2.6 was followed by §4); v2 uses that number for the separation of the measured objects.

## §1. Cohort contract

### §1.1 Measured workflows — two tiers

| tier | workflow | path | role |
|---|---|---|---|
| **primary (default)** | `axiom-operational-slice` | `.github/workflows/axiom-operational-slice.yml` | the target that defines the admission wall. Unless stated otherwise, every `criticalPath` report is about this workflow. |
| secondary (comparison) | `admission-gate` | `.github/workflows/admission-gate-v2.yml` | for comparison and regression watch. It never replaces the primary target's metric. |

Two reasons make the primary target the default, and both are derived from policy.

- **2 of the 7** required contexts declared by `config/policy/merge_admission.json` (`axiom-operational-slice`, `readiness-verdict`) come from this single workflow. The two jobs are **serial**: `readiness-verdict: needs: [axiom-operational-slice]`.
- Of those, `readiness-verdict` is the **last finisher** in a majority of the observed cycles. The last finisher's completion is the end of the admission wall, so omitting this workflow means the dominant segment of the wall is never measured.

The claim is **not** that the primary target is *always* the last finisher. Some cycles ended with `admission-check`, so the per-candidate last finisher is recorded separately (§3.2). The secondary target expands its 8 top-level jobs into 26 records that mostly run in parallel, and in observation it finished before the primary target — it carries slack, so improving its metric does not move the wall.

### §1.2 Event, attempt, exclusions, minimum size

| item | contract |
|---|---|
| event | `merge_group` (naturally occurring merge queue runs only) |
| attempt | **terminal attempt** of each run only (maximum `run_attempt`) |
| excluded | `workflow_dispatch`, manual re-runs, synthetic benchmarks |
| minimum size | n≥5 to make an optimization **decision**, n≥20 to make an **SLO claim** |

### §1.3 `skipped` records

`skipped` job records are removed from **neither** the cohort **nor** the buckets. Removing them deletes nodes from the `needs:` graph (§7.3) and moves the start of the wall, which breaks reproducibility. `skipped` is excluded **from contributed time only**.

## §2. Metric definitions

Every timestamp uses the ISO-8601 UTC value from the GitHub jobs API verbatim. Rounding happens at output only; computation uses second-resolution reals.

### §2.1 `wallSeconds` — the merge wait a user experiences

```
wallSeconds = max(completed_at) - min(started_at)
```

Computed over **all jobs** of the terminal attempt (including `skipped`, for every job that has both timestamps).

- The authority for this definition is `docs/spec/ci_acceptance_contract.md` §6. This document does not redefine it.
- The value is an **observation interval** that includes runner wait, queue wait, and job execution.
- `created_at` is not used (the workflow creation instant additionally includes the delay before the first job starts).
- `wallSeconds` is **per workflow**. `wallSeconds` values from different workflows are not added or max-folded into an admission wall (§3.3).

### §2.2 `runnerSeconds` — accumulated compute

```
runnerSeconds = Σ max(0, completed_at - started_at)   (per job)
```

- The `max(0, …)` clamp turns the abnormal negative span of a `skipped` job (`completed_at < started_at` by one second, for example) into zero.
- On this sample the definition yields the same value as "exclude `skipped`" (measurement §3.2). The clamp exists to pin the definition for future samples too.
- **Caution**: taking a raw sum without the clamp lets the negative spans of `skipped` jobs subtract from the total, understating each run by 4–6 seconds. The per-run values in the 2026-11-19 document are raw sums, so they differ from this document's values by 4–6 seconds (§4).

### §2.3 `queuedSeconds` — assignment wait and handoff wait (v2 redefinition)

For a record `j` let `g(j) = started_at(j) − created_at(j)`. The gap `g(j)` carries **two different phenomena**. It is not reported as one sum.

| aggregate | scope | meaning | normal size |
|---|---|---|---|
| `queueSeconds.firstBatch` | jobs whose `needs` is empty | runner assignment and VM provisioning wait | seconds; minutes during a burst |
| `handoffSeconds` | jobs that have `needs` | from predecessor completion to this job's start | 2–3 seconds |

Rules:

1. **A missing field is not zero.** `created_at` is absent from the documented Jobs REST response schema (it is present in observed responses — `docs/spec/gh_run_observation_quirks.md` Q18). A record whose field is missing or null produces no value and is reported as `NO_LOG_SOURCE`. If the number of usable records is smaller than the total, **the aggregate itself** is reported as `NO_LOG_SOURCE`; a partial sum over the usable subset is never emitted as that aggregate's value. The sentinel name reuses the existing `NO_LOG_SOURCE`.
2. **The two aggregates are not summed.** The first batch is genuine queueing; the handoff is dependency-release latency. A sum says nothing about which side is the bottleneck, so it is never reported as a single scalar.
3. **Report per batch plus a distribution.** Each aggregate is emitted per batch (first batch, then each dependency level) and as a cohort distribution (p50/p90/min/max). It is reported independently of `wallSeconds`.
4. **`g(j)` is not called "queue wait".** The internal split of `g(j)` (concurrency queue wait versus runner assignment and VM provisioning) is not exposed by the API (Q18 decision rule). A measurable gap does not imply a decomposable one.

### §2.4 `stepSeconds` — step attribution

```
stepSeconds(stepName) = Σ max(0, step.completed_at - step.started_at)
```

- Steps sharing the same `name` are summed across the cohort. GitHub does not expose nested steps of a composite action as separate steps.
- The `stepSeconds` total can be smaller than the `runnerSeconds` total. The difference is job time not recorded as any step.
- **provisioning family** = the sum of every step whose name contains `setup-axiom-toolchain`.
- `stepSeconds` is **per workflow**. Step totals from different workflows are not added to read as an admission segment.

### §2.5 `criticalPathSeconds` — the longest path of the per-workflow `needs:` DAG (v2 redefinition)

**Scope**: one workflow run attempt. Jobs from different workflows are never placed in one graph. `criticalPathSeconds` is defined only with respect to the **same attempt** as `wallSeconds`.

**Input**: the attempt-exact job record set of that attempt (`skipped` included per §1.3) plus the `jobs:` and `needs:` read from the workflow YAML at that run's `head_sha` (§7.4).

**Graph**:

- Nodes are the **top-level job ids** attributed by §7.1. The node set must match the YAML `jobs:` key set exactly.
- Node weight is the bucket interval: `w(n) = max(completed_at | bucket n) − min(started_at | bucket n)`.
- Edge weight `p → n` runs from predecessor completion to consumer creation: `e(p→n) = min(created_at | bucket n) − max(completed_at | bucket p)`.
- `e < 0` is **clamped to 0 and recorded as an anomaly**. Measured basis: a `skipped` record can have `completed_at` earlier than `created_at` (the original observation `gateway / proof-reconcile` was −2 s; the reproduction sample in this document was −1 s). The clamp does not erase that fact — it survives as an anomaly count.
- `criticalPathSeconds = max(path) [ Σ w + Σ clamp(e) ]`, where a path runs from a source to a sink.

**Determinism**: the same value must come out regardless of input record order. Ties on `completed_at` are broken by the **total order** of `(job id, record id)`, so two executions over the same snapshot are byte-identical.

**Invariant `criticalPathSeconds ≤ wallSeconds`** (same attempt). When every edge is non-negative the inequality follows by telescoping: the path sum folds into `maxComp(n_k) − minStart(n_1) + Σ_{i≥2}(minCreated(n_i) − minStart(n_i))`, each term is non-positive because `started_at ≥ created_at`, and `maxComp(n_k) − minStart(n_1) ≤ wallSeconds`.

The clamp can break that folding (raising a negative edge to zero increases the sum). The inequality is therefore **a checked item, not an assumption** — exceeding it means the attempt, the job set, or the clocks are wrong, and it is a **hard error** (§8 #6).

**Path decomposition is mandatory**: report the node-time total and the edge-time total **together**. An edge into a gather node (`admission-check` holds all 7 predecessors as `needs`) carries "the entire wait after whichever predecessor finished", so the longest path can collapse into a **wait chain**. Reporting a single share without the node/edge split cannot distinguish "serial work" from "serial waiting".

### §2.5.1 `criticalPathShare` — per-workflow diagnostic (v2 relocation)

```
criticalPathShare = criticalPathSeconds / wallSeconds   (same workflow, same attempt)
```

`criticalPathShare` is a ratio **against that workflow's own wall** and is a per-workflow diagnostic. It is not a ratio of `T_admission`, and it is never summed with another workflow's value (§3).

### §2.6 `mergesPerHour` — throughput

```
mergesPerHour = |{c : c ∈ main commits, |parents(c)| ≥ 2, c.committer.date ∈ (t−W, t]}| / W(hours)
```

- **The commit's `committer.date` is used, not `mergedAt`.** That counts merge commits created by the GitHub merge queue and local or direct merges under one rule.
- Commits with fewer than 2 parents (squash, rebase, direct push) are not merges and are excluded.
- The window boundary is the half-open interval `(t−W, t]`. A commit on the boundary is never double-counted across windows.
- This metric is **throughput**, not latency. It is reported alongside `wallSeconds` (§2.1) and PR-to-main TOT, and none of them substitutes for another.
- **The denominator is wall-clock time, not runner time.** The value alone therefore cannot locate the bottleneck; it must be read together with `queuedSeconds` and `runnerSeconds`.
- The theoretical ceiling is `3600 / wallSeconds p50`. If measured throughput approaches that ceiling, capacity is the bottleneck. If it falls far short, the bottleneck is not throughput but **input (PR arrivals)**.

## §3. Two measured objects — per-workflow critical path versus `T_admission`

This document measures **two different objects**. They are never merged into one table or one ratio.

| | **per-workflow critical path** | **`T_admission`** |
|---|---|---|
| unit | one workflow run attempt | one merge_group candidate (SHA) |
| interval | first job start to last job completion of that attempt | queue entry to merge |
| denominator | that workflow's `wallSeconds` | `T_admission` |
| input | that attempt's job records + the YAML at that SHA | check-runs of the 7 required contexts |
| question answered | "what is serial inside this workflow" | "how long did the user wait" |
| question not answered | this workflow's share of the whole admission | the serial structure inside a workflow |

### §3.1 per-workflow critical path

§2.5 and §2.5.1. It states only how that attempt's time serializes over one workflow's `needs:` graph. Other workflows proceed **in parallel** and are not included in this value.

### §3.2 `T_admission`

`T_admission` is the wall until the point where all 7 required contexts have **completed**. The 7 are declared by `config/policy/merge_admission.json` and span different workflows. The dominant segment of `T_admission` is therefore decided by **the context that finishes last among the 7**, and which workflow that context belongs to can differ per cycle.

- The 4-phase split (`T_queue` / `T_verify` / `T_publication` / `T_merge`) and the `reconcile` identity (**the parts sum to the total**; residuals are never absorbed) keep the v1 contract unchanged. **This revision does not alter them.** The authoritative definition of each phase is a pure function in `tools/ci/ci_admission_observe.nim`, and `docs/evidence/ci_admission_measurement_2026-11-24.md` records the measurement.
- If any one phase value is unobservable, the whole partition is left empty — a partial partition is never presented as a complete one.
- Record the **name of the last finisher context** per candidate. Which workflow defined the wall is the premise for reading the cohort.

### §3.3 Forbidden readings

| forbidden statement | why it is wrong |
|---|---|
| "the slice's `criticalPathShare` is 0.9, so 90% of admission is the slice" | the share's denominator is **that workflow's** wall. The admission wall is the max over 7 contexts, and other workflows run in parallel. |
| "`criticalPathShare` is 1.0, so there is no room to optimize" | the share speaks only to serialization **inside** the attempt. When the path is a wait chain (§2.5), the serial work is smaller than the share suggests. |
| "the sum of per-workflow `criticalPathSeconds` equals `T_admission`" | intervals overlap across workflows. The sum double-counts. |
| "the average of per-workflow `criticalPathShare` values is the admission serialization" | an average of ratios with different denominators is not the ratio of any interval. |
| "the workflow with the largest `wallSeconds` defines the wall" | what defines the wall is the **last finisher**. A long-running workflow can finish earlier. |

## §4. Reconciliation with previously cited values (mandatory)

The 2026-11-19 baseline (`docs/evidence/ci_performance_baseline_2026-11-19.md`) recorded **wall p50 574 s / runner-seconds p50 979 s**. Those values came from a **different 5-run cohort A**. The two cohorts share 4 runs and differ in the fifth.

| cohort | run IDs | wall p50 | runner p50 |
|---|---|---|---|
| A (2026-11-19) | 44519217624, 44521587339, 44542633420, 44548437642, 44553449785 | 574 s | 979 s |
| B (this document, 2026-11-20) | 44521587339, 44542633420, 44548437642, 44553449785, 44561019095 | 555 s | 931 s |

The p50 difference is therefore a **sample difference**, not a formula difference. Both values are valid within their own cohort and neither replaces the other.

A separate, smaller difference: per-run runner-seconds differ by 4–6 seconds between the raw sum (2026-11-19 document) and the clamped sum (this document), for example 1282 versus 1286 for run 44521587339. The raw sum adds the abnormal negative span of `skipped` jobs (`completed_at < started_at`) as-is.

**v2 addition**: every `criticalPathSeconds` and `criticalPathShare` published before v2 was computed with the v1 §2.5 backtracking-chain rule (2-second tolerance, single predecessor choice). Its **definition differs** from the v2 DAG longest path, so the two values are never compared as one series and never combined into a ratio. v1 values are cited only as historical record.

Rules:

- **The authoritative definition of the canonical wall is `docs/spec/ci_acceptance_contract.md` §6.** This document cites it and does not redefine it.
- The authoritative definition of runner-seconds is `docs/evidence/ci_performance_baseline_2026-11-19.md` §1, and this document pins it by stating the per-job 0-clamp.
- A before/after comparison uses **one cohort and one definition** only. Ratios are never built from p50 values of different cohorts.

## §5. Before/after comparison protocol

An optimization is judged an "improvement" only when every condition below holds.

1. **Equivalent workload**: same event (`merge_group`), same workflow path, same runner label, same job DAG.
2. **Separate cohort**: before = a pre-registered set of run IDs (already finished), after = runs that occur for the first time after the change commit. **The same run ID is never re-measured** — the duration of a finished run does not change.
3. **Identical definition**: the §2 formulas and clamp conventions are applied identically to both sides.
4. **Absolute values plus ratios, reported together**: `wallSeconds`, `runnerSeconds`, and the **per-target-workflow** `criticalPathShare`. That ratio is against that workflow's wall and is not a ratio of `T_admission` (§3.3).
5. **Invariant-preservation evidence**: show separately that the Z3/Lean evidence, the required contexts, the App provenance, and the fail-closed verdict are identical before and after.
6. **A DAG change needs a new baseline**: if the change alters the target workflow's `jobs:` or `needs:`, `criticalPathSeconds` is by definition not comparable. Register a new baseline and never report the difference as an "improvement".
7. **Admission impact is claimed through `T_admission` only.** Claiming that a per-workflow improvement reduced `T_admission` requires before/after `T_admission` values over the same cohort.

p95 is not declared for a sample with n<20. If n<20, mark it `INCOMPLETE` and report only the maximum and the median.

## §6. Non-goals

- No admission verdict is derived from these metrics.
- Caches and artifacts are never treated as an evidence store (acceleration and proof stay separate).
- An optimization is never achieved by skipping a check or proof step. Only "removing duplicate computation" is permitted.
- **A per-workflow `criticalPathShare` is not used as an admission ratio** (§3.3).
- **Workflow superiority is not decided by `criticalPathSeconds`.** Each workflow has its own wall and DAG, and whether slack remains must be measured separately.
- **`criticalPathSeconds` is not used to choose the optimization target.** The target is chosen by the last-finisher observation (§1.1).

## §7. Attribution contract and graph authority

This section specifies how the input to §2.5 is produced. The rules here are **normative**; a violation is `UNKNOWN` or a hard error (§8).

### §7.1 bucket attribution — prefix rule

A job record name `N` is attributed to the top-level job id `I` as follows.

```
own(N, I)  ⟺  N == I  ∨  N.startsWith(I & " / ")  ∨  N.startsWith(I & " (")
```

The separators are `space-slash-space` (` / `), and a matrix instance carries a ` (k)` tail (for example `attest / go-critical-lane (0)`).

**Suffix inference is forbidden.** A reusable workflow's job names also appear as suffixes of the top-level id, and such a suffix **can equal another top-level job id**. Measured counterexample: the suffix `admission-check` of `attest / admission-check` and of `verdict / admission-check` is itself a top-level job id. Suffix parsing silently misattributes those two records into the `admission-check` bucket and mixes them with `admission-check`'s own record. **The parent id is never derived from a suffix, under any circumstance.**

Observation anchor (non-normative, run `45329393421` attempt 1 — `gh api repos/Archright/Axiom/actions/runs/45329393421/jobs?per_page=100`):

| bucket | records | composition |
|---|---:|---|
| `attest` | 6 | `admission-check`, `admission-independents`, `build-base-artifacts`, `go-critical-lane (0)`, `go-critical-lane (1)`, `go-critical-rollup` |
| `gateway` | 8 | `sl09-scope`, `select`, `ci-bootstrap`, `candidate-build-arm`, `gateway-shard`, `gateway-identity-gate`, `proof-reconcile`, `executed-jobs` |
| `verdict` | 5 | `admission-check`, `admission-independents`, `build-base-artifacts`, `go-critical-lane`, `go-critical-rollup` |
| `mint-prepare` | 2 | `prepare` + `publish` of `certificate-mint.yml` |
| `mint-publish` | 2 | `prepare` + `publish` of `certificate-mint.yml` |
| `anchor-resolve` | 1 | — |
| `closure-deriver` | 1 | — |
| `admission-check` | 1 | — |
| **total** | **26** | 0 residual, 0 ambiguous |

`mint-prepare` and `mint-publish` **each** expand into both `prepare` and `publish` (one of the two is always `skipped`). The expansion is a property of the **called workflow's declared job set**, not of any stage input — observing only one of them is not a reason to trim the other.

### §7.2 bucket completion time = `max(completed_at)`

A bucket completes at the **`max(completed_at)` of its constituent records**. Not `min`, and not "any member". A bucket has exactly one completion instant, and that instant is the origin of consumer edges.

Observation anchor: in the run above, the `attest` bucket's max `completed_at` is `04:57:41Z` and the consumer `mint-prepare / prepare` has `created_at` `04:57:41Z` — an edge weight of 0. Using `min` breaks this match.

### §7.3 `skipped` records are retained

`skipped` records are not filtered out **before** buckets are built. Filtering removes expanded jobs from the graph nodes — the `mint-prepare` bucket would shrink to a single `prepare`, and the graph would become "what actually ran" rather than "the declared job set". `skipped` is excluded **from contributed time only** (§2.2) and stays in the node and edge sets.

### §7.4 graph authority — YAML at the candidate SHA plus a recorded blob SHA

- The `needs:` graph is built **only** from the workflow YAML read at **that run's `head_sha`**. Never from the default branch or a working-tree copy — that reconstructs a past attempt's graph as the current graph.
- The YAML's **blob SHA** is recorded in the report: run id, `run_attempt`, and `head_sha` are kept **alongside** it in the same record. A report with only a run id and no blob SHA is not reproducible.
- The blob SHA is the blob id from the contents response at that SHA (`GET /repos/{owner}/{repo}/contents/{path}?ref={head_sha}` → `.sha`). Measured example: `axiom-operational-slice.yml` @ `e2d35ccd…` → `5ace57c21aaf56427bc5e02b716072258a940cf2`.
- **The parse scope is `jobs:` and `needs:` only.** Triggers, `with:`, and expressions are not read.
- Reusing an existing YAML reader: `tools/ci/publication_yaml.nim` deliberately accepts only a **restricted subset** (quoted scalars only, no flow style). GitHub workflow YAML is outside that subset (compare `needs: [a, b]` and unquoted scalars), so it **cannot be reused** for this purpose. The repository has no general-purpose reader that can be reused.
- If the YAML cannot be read at that SHA (missing file, API failure), that attempt's `criticalPath` is `UNKNOWN`. It is never substituted with a default-branch copy.

### §7.5 `parent_job_id` does not exist

The reusable-workflow expansion relation is **not expressed by the API**. Neither a job object nor a check-run object carries `parent_job_id` (or an equivalent parent-job pointer) — the union of keys of the two object types was checked empirically (2026-11-24: 26 jobs of run `45329393421` and 58 check-runs at the same `head_sha`, all absent).

The graph is therefore reconstructed **only** from the YAML plus the naming convention (§7.1). An implementation that assumes "the API must have a parent link" is fail-open.

## §8. Fail-closed rules

Unobservability is never filled in with an estimate. If any condition below holds, the corresponding metric for that attempt (or candidate) is a state, not a value.

| # | condition | verdict |
|---|---|---|
| 1 | a job record name attributes to **no** top-level job id | `UNKNOWN` — no speculative attribution. Do not continue with a partial bucket set. |
| 2 | the YAML's job-level `name:` replaced the record names so that none of the remaining names matches the `jobs:` key set | **hard error** — an unattributable bare name means the graph itself cannot be reconstructed. |
| 3 | a job record exists in the API but not in the `needs:` graph (§7.4) | **hard error** — the YAML and the attempt do not describe the same object. |
| 4 | a graph node has no corresponding record | `UNKNOWN` |
| 5 | any node on the critical path has a missing or null `started_at` / `completed_at` / `created_at` | `UNKNOWN` — **never substitute 0** |
| 6 | `criticalPathSeconds > wallSeconds` (same attempt) | **hard error** (§2.5 invariant) |
| 7 | a job record's `head_sha` ≠ the run's `head_sha` | **reject** — a job from another commit is never counted into this attempt |
| 8 | `run_attempt` mismatch (the record's attempt ≠ the selected terminal attempt) | **reject** |
| 9 | `conclusion` is `skipped`, `cancelled`, or null | **not counted as success**. Time contribution follows the §2.2 clamp and the record stays as a graph node (§7.3). |
| 10 | `queuedSeconds` cannot be computed because `created_at` is absent | `NO_LOG_SOURCE` (§2.3) |
| 11 | the workflow YAML cannot be read at that SHA | `UNKNOWN`; never substitute a default-branch copy (§7.4) |
| 12 | edge weight < 0 | clamp to 0 plus an anomaly record (§2.5) |

**Determinism requirement**: two executions over the same snapshot must produce identical reports regardless of input record order. Ties on `completed_at` are broken by the total order of `(job id, record id)` (§2.5).

**`UNKNOWN` is not success.** A cohort containing any `UNKNOWN` never fills p50/p90 with those values — doing so is fail-open. Mark it `INCOMPLETE` and report the observed count alongside.
