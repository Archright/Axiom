# merge_queue `max_entries_to_build` — candidate lever rejected and restored (2026-11-24)

> **Verdict**: **REJECTED — rejected for lack of evidence; the live value was restored (`100`)**.
> **Nature**: a review record for a platform-parameter candidate. No repository file, trust surface, or required context was changed.
> **Target**: `rules[type=merge_queue].parameters.max_entries_to_build` of repository ruleset `27097366` (`main`)
> **Final live value**: `100` (identical to before the change; readback diff 0)

## §1. The rejected hypothesis

`max_entries_to_build` is the ceiling on merge_group builds the merge queue dispatches at once. At 100, up to 100 entries waiting in the queue are built simultaneously. Axiom's merge_group runs 8 workflows and 44 job records per entry, and a Free organization's standard runner concurrency limit is 20 jobs — so **lowering this ceiling would reduce runner contention and shorten the wall** was the hypothesis under review.

## §2. Observations that supported the hypothesis (measured during this revision)

Across 300 `merge_group` executions of `axiom-operational-slice` (2026-11-20 05:35 to 11-24 04:59), each run's duration was compared against **the number of other slice runs whose time interval overlapped it**.

| overlapping runs | n | p50 (s) | mean (s) | min | max |
|---|---|---|---|---|---|
| 0 | 82 | 391 | 481 | 317 | 1738 |
| 1 | 54 | 452 | 477 | 328 | 686 |
| 2 | 164 | 594 | 632 | 335 | 1295 |
| 3–9 | 84 | 650–1112 | — | — | 1295 |

`Pearson r(overlap, duration) = 0.473`. Over the most recent 30 runs in time order, overlap fell 9 → 0 while duration fell 1123 s → 389 s.

The same direction holds per merge group. Across the 13 most recent merge groups, the group span was **476–615 s at concurrency 1 (median 550 s)** and **962–1548 s at concurrency ≥2 (median 1095 s)**.

On this observation alone, lowering the ceiling would be correct.

## §3. Why the hypothesis was rejected

### §3.1 The prior change is not unverified drift

`max_entries_to_build` moved `2 → 1 → 100` (`data/ci_optimization/merge_queue_concurrency_2026-11-21/summary.json:12-17`, `provenanceCorrection`). The `1 → 100` step is an intended change carrying all of the following.

- stated purpose: "remove the ceiling on verification-candidate supply and measure the effect"
- application time and provenance recorded (`ruleset.updated_at`)
- invariance diff: `requiredStatusChecksDiff: IDENTICAL`, `nonMergeQueueRulesDiff: IDENTICAL`, `bypassActors 0 → 0`
- readback and a rollback path (`reversible: true`)
- a follow-up measurement `_after_n10/summary.json` — the same arm extended to n=32 (`status: APPLIED_AFTER_ARM_OBSERVED_N34_COMPLETED_32`)
- a decision record: `STAY_FREE` / `NO_CAPACITY_SATURATION_EVIDENCE` / `AFTER_ARM_COMPLETE`

### §3.2 This hypothesis does not survive the falsification that measurement established

The conclusion of `_after_n10/summary.json`:

> `"configuredMaxEntriesToBuild": 100, "binding": false`
> "The dispatch ceiling 100 did not bind at all (peak 6). The maximum number of concurrently live merge_group workflow runs was 30. Raising the ceiling further would gain nothing."

And the same summary already records the following as **NOT SUPPORTED / REFUTED**.

| claim | prior verdict |
|---|---|
| `max_entries_to_build = 1` is the cause of merge delay | **NOT SUPPORTED** |
| `max_entries_to_build` is a security invariant | **REFUTED** |

`freeConcurrencyLimitReached` is `limit: 20, reached: true, timeAtOrAbove20Seconds: 111, fractionPercent: 0.693`, and it records that reaching the limit did not produce sustained queue growth.

### §3.3 An independent re-measurement confirms the ceiling does not bind

For the most recently completed merge_group (`45329393421`, head `c07b8354`, 04:52:38 → 05:00:48Z), the `[started_at, completed_at]` interval overlap was computed over the 44 job records of its 8 workflows (32 executed, 12 skipped).

| set | peak concurrent `in_progress` |
|---|---|
| `admission-gate-v2` alone | 5 |
| + `axiom-operational-slice` | 6 |
| all 8 workflows | **16** |

Average occupancy over the 488 s window is **5.3 / 20 (27%)**, and the time at `≥18` and `≥20` is **0 s**. The other four groups show the same shape, peaking at 14, 16, 16, and 15.

So **a single merge group does not saturate the 20 slots.** Lowering the ceiling to reduce the number of concurrent groups removes exactly that much parallelism, and the ceiling never bound in the first place.

### §3.4 The observed overlap correlation is not an effect of the ceiling

The §2 correlation is **not causation**. If the ceiling was not binding (§3.3), overlap is a function of **submission load**, not of the ceiling. Intervals with heavy load have both more overlap and longer waits — lowering the ceiling only lengthens the wait. This is also why the prior measurement's c100 arm, at `n=3`, declined to declare a distribution and reported only a structural inequality.

## §4. What was actually done and how it was undone

1. Captured a before-snapshot with `GET /repos/Archright/Axiom/rulesets/27097366`
2. Built and applied a PUT body that changed `max_entries_to_build` only, `100 → 1`
3. Verified the readback semantic diff = **1 field** (`100 → 1`), with the 7 required contexts, the `admission-check` App `5795152`, `bypass_actors: []`, and `can_bypass: never` unchanged
4. After confirming the §3 evidence, **PUT the before-snapshot back**
5. Restore readback semantic diff = **0 fields**, `max_entries_to_build = 100`

The final state is **exactly identical** to before this work.

## §5. Why this field is not touched

| item | verdict |
|---|---|
| Is it a drift target | **No** — `tools/merge_ruleset_drift_monitor.nim:135-144` declares it an explicit NOT expectation, and `tests/unit/test_merge_ruleset_drift_monitor.nim:394-409` asserts the monitor does not react to a value change |
| Is the value 100 a measured optimum | **No** — the prior record does not claim "100 is good" either. The claim is "the ceiling must not bind", and 100 is the implementation of that removal |
| Does lowering it improve anything | **No** — peak 16/20, 27% average occupancy, non-binding ceiling. Lowering it only reduces parallelism |
| Is it related to the verification contract | **No** — it changes no required context, issuing party, or verdict meaning |

## §6. What this rejection leaves behind

`max_entries_to_build` is **not a file, so it is unrelated to the trust surface** and can be manipulated under agent authority immediately. That made it the only lever where "we could not do it because of permissions" cannot hold, and after actually manipulating it the **measurement did not support the change, so it was reverted by the same actor**. In the Pareto-line verdict this item is **outside the evidence**, not outside the authority.

## §7. Reproduction commands

```bash
gh api repos/Archright/Axiom/rulesets/27097366 > rs_before.json
# after building rs_put.json with only max_entries_to_build modified
gh api -X PUT repos/Archright/Axiom/rulesets/27097366 --input rs_put.json
gh api repos/Archright/Axiom/rulesets/27097366 > rs_after.json   # verify by semantic diff
gh api -X PUT repos/Archright/Axiom/rulesets/27097366 --input rs_before.json   # restore
```