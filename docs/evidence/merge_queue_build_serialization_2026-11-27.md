# Merge queue build serialization -- applied change record (2026-11-27)

> **Status**: applied change record. This document records a ruleset parameter change that
> was already applied. It changes no workflow, no gate, no required context, and no policy.
> **Applied**: 2026-11-27T22:57:05+09:00 (`ruleset 27097366.updated_at`)
> **Field**: `rules[type=merge_queue].parameters.max_entries_to_build`
> **Before**: `100` -> **After**: `1`
> **Reversible**: yes, one API call (see section 8)

## 0. What this records, and an ordering defect

This record documents the transition of the merge queue build fan-out from `100` to `1` on
ruleset `27097366` (`main`).

**Ordering defect, stated plainly**: the parameter was applied *before* this record was
written. `AGENTS.md` section 0.5 requires the documentation to precede a system-level change.
That order was not followed here. The record is therefore retrospective, and it does not
pretend to have authorized the change. What it fixes is the audit trail, not the sequence.

## 1. Authority chain

| Item | Value |
|---|---|
| Authoritative owner of `main` merge allow/deny | GitHub repository ruleset `27097366` |
| Authoritative owner of merge queue build dispatch | GitHub merge queue (`max_entries_to_build`) |
| Operator (human architect) | `wintrover` |
| Operator instruction | blanket authorization for permission-gated steps, granted 2026-11-27 |
| Executor | agent, via `PUT /repos/Archright/Axiom/rulesets/27097366` |
| Independent review | none. This record does not claim one. |
| Agent authority used | repository `admin` (ruleset write). No workflow, gate, or App change. |

The merge authority itself was not touched: the merge is still decided by the ruleset and by
App `5795152`. This change only controls how many merge-queue entries GitHub dispatches
concurrently for verification.

## 2. The change

The `PUT` body was the previous ruleset with exactly one leaf changed. A recursive leaf diff
of the read-back before and after the call shows one non-metadata difference:

| Leaf | Before | After |
|---|---|---|
| `/rules/4/parameters/max_entries_to_build` | `100` | `1` |

Every other leaf was identical, including the metadata-only keys that the API returns but does
not accept on write (`id`, `node_id`, `source`, `source_type`, `created_at`, `updated_at`,
`_links`, `current_user_can_bypass`).

Full parameter read-back after the change:

| Parameter | Value |
|---|---|
| `max_entries_to_build` | **1** |
| `max_entries_to_merge` | 1 |
| `min_entries_to_merge` | 1 |
| `min_entries_to_merge_wait_minutes` | 0 |
| `grouping_strategy` | `ALLGREEN` |
| `merge_method` | `MERGE` |
| `check_response_timeout_minutes` | 120 |

## 3. Invariants preserved

| Invariant | State after the change |
|---|---|
| Required contexts (ruleset `27097366`) | 7, identical: `admission-check` (App `5795152`), `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`, `readiness-verdict` |
| `bypass_actors` (ruleset `27097366`) | `[]` (0), unchanged |
| Enforcement | `active`, unchanged |
| Rule set | 5 rules, unchanged: `deletion`, `non_fast_forward`, `pull_request`, `required_status_checks`, `merge_queue` |
| Sibling ruleset `27525972` (`main-admission`) | not touched. `bypass_actors` 0, requires `admission-check` only |
| `current_user_can_bypass` | `never` both before and after |

No verification was removed, weakened, or made skippable. Every merge-queue entry still runs
the full required context set. The change alters *how much speculative work is dispatched at
once*, not *what is verified*.

## 4. Why this was considered: the structural argument

The previous configuration combined two parameters that pull against each other:

- `max_entries_to_build = 100` -- GitHub may dispatch up to 100 merge-queue entries for
  verification in parallel.
- `max_entries_to_merge = 1` with `grouping_strategy = ALLGREEN` and
  `min_entries_to_merge = 1` -- at most one entry merges per batch, so entries are verified
  one at a time and each new entry is verified against a *new* base once the previous entry
  lands.

When the base moves, a speculative verification performed against the previous base cannot
satisfy the required check for the new base. The speculative work is therefore discarded, and
while it is in flight it consumes concurrency slots that the entry actually being merged also
needs.

Per merge group this repository dispatches roughly 30 jobs across 8 `merge_group`-triggered
workflows. The plan's concurrent-job ceiling is 20. Two entries dispatched together therefore
demand roughly 60 jobs against 20 slots.

## 5. Measurement basis

The justification is **not** a p50 improvement claim. It is overlap-spike suppression,
measured inside a single regime (all runs below were under `max_entries_to_build = 100`, so no
configuration drift confound applies).

Population: 38 `admission-gate` merge-group runs, `2026-11-26T18:05Z` to `2026-11-27T13:47Z`.
Wall definition inherited from `docs/spec/ci_critical_path_metric.md` section 2.1.

| Statistic | Value |
|---|---|
| completed runs | 37 |
| min | 312 s |
| median | 364 s |
| max | 469 s |
| runs at or above 600 s | 0 |

The four slowest runs and their dispatch adjacency:

| merge group head | wall | started | seconds from another merge_group dispatch |
|---|---|---|---|
| `3aad783c` | 469 s | 06:00:43Z | 23 s |
| `f7e204a3` | 460 s | 12:18:25Z | 29 s |
| `59893805` | 453 s | 12:17:56Z | 29 s |
| `e3087364` | 453 s | 06:42:28Z | none within 6 minutes |

Three of the four slowest runs were dispatched within 30 seconds of another merge group.
One was not. This is a **correlation in the observed window, not a proven causal law** --
`e3087364` is a counterexample and is recorded as such.

The prior decomposition of `f7e204a3` attributed 127 of its 129 seconds of excess to runner
acquisition delay, with verification work 12 seconds *faster* than baseline. That
decomposition is the reason the lever was sought in dispatch fan-out rather than in gate
count.

## 6. Relationship to the committed decision record (issue #256)

This change does not supersede, reinterpret, or invalidate
`data/ci_optimization/merge_queue_concurrency_2026-11-21/summary.json` or its `_after_n10`
extension. Those files are immutable and remain the authority for what they measured.

What they measured, restated without alteration:

| Arm | `max_entries_to_build` | n | wall p50 | wall p95 |
|---|---|---|---|---|
| c2 | 2 | 110 | 576.5 s | 1127.1 s |
| c1 | 1 | 15 | 496.0 s | 572.4 s |
| c100 | 100 | 32 | 536.5 s | 944.1 s |

Two cautions that this record will not paper over:

1. **The arms are confounded by failure mix.** `c100` had 16 successes and 16 failures; the
   success stratum alone was p50 479.5 s. `c1` had 10 successes and 5 failures and no
   published success stratum. Failure runs are materially slower (p50 626.0 s against
   479.5 s), so the pooled p50 comparison between c1 and c100 is not a like-for-like
   comparison. On the available numbers, c1 and c100 are **not distinguishable on success
   p50**.
2. **The `_after_n10` verdict `STAY_FREE / NO_CAPACITY_SATURATION_EVIDENCE` is a statement
   about the plan**, not a statement that `c100` was the faster setting. Its own
   `throughputCeilingTest` recorded the c1 ceiling as 7.258 merges per hour against the c100
   ceiling as 6.710 merges per hour, and its `reopenConditions` are about a plan upgrade,
   none of which this record touches.

The reopen conditions for the plan question remain unmet to the extent they were before:
observed concurrency at the ceiling was 0.693 percent of the window against a 30 percent
threshold, and there were zero timeout discards.

## 7. What this record does not claim

- It does not claim a p50 wall-time improvement. The p50 improvement is unproven, and the
  available arms are confounded.
- It does not claim the ten-minute bound was ever breached. No observed run in the population
  reached 600 s.
- It does not claim that overlap is the only cause of slow runs.
- It does not claim that throughput is improved. Throughput on this repository is
  input-limited, not capacity-limited: the `_after_n10` observation recorded 2.921 merges per
  hour against a 6.710 per hour ceiling, with queue supply recorded as the binding
  constraint.

What it does claim: with `max_entries_to_build = 1`, a merge group can no longer be slowed by
another merge group's speculative build consuming the same 20 slots. That mechanism is
removed structurally, by the platform, rather than by an operator choosing to enqueue only
when the queue is empty.

## 8. Rollback

```
PUT /repos/Archright/Axiom/rulesets/27097366
body: the same ruleset, with
  rules[type=merge_queue].parameters.max_entries_to_build = 100
```

The pre-change read-back was captured before the `PUT` and contains every rule and parameter
of the previous state. Rollback does not require reconstructing anything by hand. After any
rollback, re-read the ruleset and confirm that all 7 required contexts and `bypass_actors`
`[]` are unchanged.

## 9. Observation contract for the c1 arm

This change is an arm, not a conclusion. Its acceptance requires observation, and the
observation must not repeat the pooling error documented in section 6.

| Item | Requirement |
|---|---|
| Cohort | `event=merge_group`, `created_at` at or after the apply instant |
| Minimum n | 20 completed runs before any p50 or p95 is declared |
| Strata | success and failure reported separately, never pooled |
| Wall definition | `docs/spec/ci_critical_path_metric.md` section 2.1 |
| Overlap counting | for every run, the seconds to the nearest other `merge_group` dispatch in the population |
| Discard condition | zero required-check failures attributable to the change, and no entry discarded for verification timeout |
| Reversion trigger | if the c1 success-stratum wall p50 exceeds the c100 success-stratum p50 of 479.5 s by more than the p95 uncertainty at the declared n, revert per section 8 |

## 10. Where the wall clock actually sits

This section is a measurement, not a config change. It answers a question section 9 cannot
answer from inside its own cohort: when the bound is at risk, which part of the pipeline is
long.

### 10.1 Population

| Item | Value |
|---|---|
| Query | `event=merge_group`, four pages of 100 runs, de-duplicated by run id |
| Heads | 50 distinct merge-group heads with a completed `admission-gate` run |
| Window | `2026-11-26T03:27Z` to `2026-11-27T14:28Z` |
| Wall definition | min `created_at` to max `updated_at` across every workflow of that head |

| Statistic | `admission-gate` | Whole merge group |
|---|---|---|
| min | 312 s | 312 s |
| p50 | 368 s | 400 s |
| max | 713 s | 713 s |
| runs at or above 600 s | 1 | 1 |

The single breach is `7a307c32`, `2026-11-26T16:57:12Z` to `17:09:05Z`, 713 s. It is
decomposed in section 10.4, because it is the one datapoint that decides whether the bound
fails by accumulation or by one slow job.

Section 7 states that no observed run reached 600 s. That is true of the population declared
in section 9, which begins 68 minutes after `7a307c32` ended, and false of the wider window
measured here. The narrower sentence is not wrong, it just does not generalise, and this
record should not carry the ambiguity.

### 10.2 The pole moved

For each head the pole is whichever of `admission-gate` and `axiom-operational-slice` finished
last. That one decides the merge group's wall clock.

| Population | `admission-gate` is the pole | `axiom-operational-slice` is the pole |
|---|---|---|
| Before #535 (`n=47`) | 45 | 2 |
| After #535 (`n=3`) | 1 | 2 |

`axiom-operational-slice` is a two-job serial chain: `readiness-verdict` declares
`needs: [axiom-operational-slice]` (`.github/workflows/axiom-operational-slice.yml:319-320`),
so it cannot start until the producer job completes.

| Head | producer job | `readiness-verdict` | workflow total |
|---|---|---|---|
| `43464090` | 114 s | 164 s | 285 s |
| `4b5878c4` | 197 s | 165 s | 390 s |
| `d2b8c651` | 229 s | 169 s | 403 s |
| `c8b65051` | 265 s | 160 s | 434 s |

The consumer job is flat at 160 to 169 s across all four. The producer job is what moved.

### 10.3 #535 added one serial step, and it costs one for one

#535 (`ci/enforce-static-gates`, merged `2026-11-27T13:29:58Z`) inserted a step named
`Enforce the declared static gate set (GATES_FAST + GATES_STATIC)` into the producer job.
Step timings were read from the jobs API and are not inferred.

| Head | static gate step | producer job |
|---|---|---|
| `43464090` (before #535) | absent | 114 s |
| `97e874d7` | 110 s | not measured |
| `d2b8c651` | not measured | 229 s |
| `4b5878c4` | 78 s | 197 s |
| `c8b65051` | 132 s | 265 s |

Producer job duration before #535 was p50 303 s over 46 heads, with a maximum of 366 s. The
four producers observed after #535 are 390, 403, 412 and 434 s. The fastest post-#535 merge
group is slower than the slowest pre-#535 one. The step's own duration, 78 to 132 s, is the
same order as the whole shift.

This is the mechanism the bound has to be defended against. It is not the count of checks. It
is whether a check lands on a chain that already gates the finish.

### 10.4 The one breach was a single slow job

`7a307c32` decomposition, from the jobs API:

| Job | Duration | Same job on `4b5878c4` |
|---|---|---|
| `closure-deriver` | 100 s | 36 s |
| `attest / build-base-artifacts` | 374 s | 76 s |
| `attest / go-critical-lane (1)` | 134 s | 86 s |
| `attest / admission-check` | 58 s | 70 s |
| `mint-publish / publish` | 69 s | 52 s |
| rollup | 3 s | 4 s |

`build-base-artifacts` alone accounts for 374 of the 713 s, and every job after it waited. The
breach is one degraded job on the serial chain, not 713 s of accumulated verification.

### 10.5 Consequence for the bound

Merge-group wall clock is a maximum over a few serial chains, not a sum over the verification
inventory. Two consequences follow, and both are arithmetic rather than policy:

1. A check added to a parallel lane is close to free. It moves the maximum only if it becomes
   the longest pole.
2. A step added to an existing serial chain costs its own duration, once, on every merge.
   #535 is the demonstration: 78 to 132 s of step, 78 to 132 s of merge group.

At p50 400 s against a 600 s bound the headroom is 200 s. The maximum observed after #535 is
434 s, leaving 166 s. That is roughly three steps of #535's size, on the longest chain, before
the bound is reached. That headroom, not the number of checks, is the budget to spend
deliberately.

### 10.6 What this section does not claim

- It does not claim the `c1` change moved the pole. The pole moved because #535 lengthened a
  serial chain. The two changes are 15 minutes apart and this population cannot separate them.
- It does not claim a p50 improvement from `c1`. Section 6 stands unchanged.
- It does not claim `build-base-artifacts` is systematically slow. That is one observation.
- It does not propose a change. Reducing the serial depth of `axiom-operational-slice`, or
  moving the static gate set off the finish path, both require edits under `.github/workflows`,
  which is a trust surface. Neither is decided here.

## 11. Provenance

| Item | Value |
|---|---|
| Ruleset | `27097366` name `main`, target `branch` |
| Pre-change read-back | captured before the `PUT`; 5 rules, `bypass_actors` `[]` |
| Post-change read-back | 5 rules, `bypass_actors` `[]`, `max_entries_to_build` `1` |
| Sibling ruleset read-back | `27525972`, `bypass_actors` `[]`, `admission-check` only, untouched |
| Population window | `2026-11-26T18:05Z` to `2026-11-27T13:47Z`, 38 runs, 37 completed |