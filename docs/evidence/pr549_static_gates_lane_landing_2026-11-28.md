# PR #549 landing record — the static gate lane, measured after the fact

> **Status**: landing record for PR #549 (`e0856a93`). It appends one row to the ruleset-bypass ledger
> and reports what the landed topology actually did. It changes no workflow, no policy, and no gate.
> **Created**: 2026-11-28
> **Landing**: PR #549, head `e32d1e88` -> merge `e0856a9372d2dc945a8df8be727b3511eaa8ffd3`
> **Bypass event**: ruleset suite `5425390411`

## §0. What was landed

`.github/workflows/axiom-operational-slice.yml` gained a third job. The 24-target static gate set
(`GATES_FAST` 10 + `GATES_STATIC` 14) moved out of the producer job and into `static-gates`, a job with no
`needs:` and no job-level `if:`. `readiness-verdict` - one of the seven required contexts - took
`needs: [axiom-operational-slice, static-gates]` and gained a first step that exits 1 unless
`needs.static-gates.result == 'success'`.

No required context was added, renamed, or removed. No gate was added, removed, or weakened. The
prediction document is `docs/evidence/static_gates_lane_placement_2026-11-28.md`; this document is the
measurement of that prediction.

## §1. Authority chain

| Item | Value |
|---|---|
| Operator (human architect) | `wintrover`, org role `admin` |
| Delegation record (pre-merge) | [`issuecomment-7237951651`](https://github.com/Archright/Axiom/pull/549#issuecomment-7237951651) for head `2a344d27`, and [`issuecomment-7238157013`](https://github.com/Archright/Axiom/pull/549#issuecomment-7238157013) re-scoping it to head `e32d1e88` |
| Actuator | `PUT /repos/Archright/Axiom/pulls/549/merge` `{merge_method:"merge", sha:"e32d1e88..."}` |
| Rulesets touched | `27097366` (`main`), `27525972` (`main-admission`) |
| Bypass mode | `pull_request` only - not `exempt`, not `always`, so an auditable event is left in the feed |
| `--auto` | never armed (MUST-T1) |
| Observation purity | `GET` only outside the four declared mutations |

### §1.1 App refusal on the head

`.github/workflows/axiom-operational-slice.yml` is a member of `config/policy/trust_surface_manifest.json`,
so App `5795152` (`axiom-admission-verifier`) refused the head by design (DEBT#558). Check-run
`140951359016`, conclusion `failure`:

```
trust_surface=FAIL — venue=pull_request manifest_ref=0e84bf2 touched=3 manifest_touched=1
diff_base=0e84bf2 reasons=mismatch:.github/workflows/axiom-operational-slice.yml
```

Check-run conclusions on `e32d1e88`: **27 success / 20 skipped / 1 failure = 48**. The single failure is
that App. Every in-repo required context was green, including the two this change restructures.

### §1.2 Restore verification (byte-identical)

Projection = `{name,target,enforcement,conditions,rules,bypass_actors}` as sorted 2-space JSON, SHA-256
over the UTF-8 bytes, taken from a live `GET` before manipulation and again after the `trap` ran:

| ruleset | projection sha256 | bytes | after |
|---|---|---|---|
| `27097366` `main` | `f2f6d45bf95633258e8ce8a7e760670af28cccef5d7d69446c291f3fcc360a14` | 2207 | **BYTE_IDENTICAL** |
| `27525972` `main-admission` | `a6e0942055b4db6720e8d9c5c6cd5da075464ed3cb6e61658f01209972e60798` | 571 | **BYTE_IDENTICAL** |

`bypass_actors = []` on both, `current_user_can_bypass = "never"` on both, required contexts **7** and
**1**. The restore was issued from a shell `trap`, not from the happy path, so an abort or a network
error in the merge step could not leave the window open.

## §2. PR venue — the two lanes ran concurrently

Run `46136010332`, head `e32d1e88`, event `pull_request`:

| job | start | end | duration | note |
|---|---|---|---|---|
| `static-gates` | 10:40:05Z | 10:43:34Z | **209 s** | new lane |
| `axiom-operational-slice` | 10:40:06Z | 10:43:27Z | **201 s** | gate step removed |
| `readiness-verdict` | 10:43:37Z | 10:47:41Z | 244 s | join, started after the later lane |

The lanes started **one second apart**. The join started at `max(201, 209) = 209 s` plus a 3 s handoff,
not at their sum. On the previous topology the join would have started at `201 + 81 = 282 s`, where 81 s
is the gate step's own duration in that same run. **Measured reduction in time-to-join: 73 s.**

This head took the B-*miss* path (`S5 gate` 0 s, `ci-compile` 93 s in both jobs), so the supply build was
performed twice on two runners. That is a compute cost, not a wall-clock one - the two jobs are
independent - and it does not appear on the hit lane (see §3).

## §3. Push venue on the landed commit — the canonical measurement

Run `46137165854`, `push` on `e0856a93`, i.e. the shipped file, not the PR diff:

| job | duration | step decomposition |
|---|---|---|
| `static-gates` | **170 s** | checkout 4 - toolchain 20 - S5 1 - `ci-compile` 10 - **gates 131** - restore 1 |
| `axiom-operational-slice` | **135 s** | checkout 5 - toolchain 32 - VS-0 6 - S5 1 - `ci-compile` 7 - ircheck 0 - R3 10 - **prove 53** - manifest 0 - determinism 12 - observability 4 - uploads 2 |
| `readiness-verdict` | **146 s** | guard 1 - checkout 6 - toolchain 30 - downloads 1 - supply 0 - identity 0 - collect 27 - gate 32 - test suite 43 - upload 1 |

On the hit lane `ci-compile` is 7-10 s in **both** jobs, so the duplication disappears; the S5 gate was
eligible (1 s) in both, which is what the `ci/checker.mk` contract requires before `AXIOM_S5_BUILD_SKIP=1`
may be set.

The join started at `max(170, 135) = 170 s`. Before this change the producer would have been
`135 + 131 = 266 s` and the join would have started there. **Measured reduction in time-to-join: 96 s.**

### §3.1 The lane is the new pole, and by how much

The lane exceeds the producer by `gate_work - producer_work_excluding_gates`:

| venue | gate work | producer work excluding gates | lane - producer |
|---|---|---|---|
| `push` (this run) | 131 s | 96 s | **+35 s** |
| `pull_request` (run `46136010332`) | 81 s | 108 s | **-8 s** |
| `merge_group` (baseline heads) | 78-133 s | ~89 s | **-11 .. +44 s** |

So the two lanes are balanced to within ~35 s in either direction, which is what the placement intended:
a new check can now be added to either lane without extending the queue's wall clock by its duration.

### §3.2 The fail-closed guard executed

`readiness-verdict` step #2 `Dependency verdict: the static gate set must have run and passed` ran in 1 s
and passed, on the landed blob. Its log line is the positive-equality assertion, not a denylist:

```
dependency verdicts: axiom-operational-slice=success static-gates=success
```

## §4. Ledger row (this PR)

```
gh api "repos/Archright/Axiom/rulesets/rule-suites?time_period=month&rule_suite_result=bypass&ref=refs/heads/main&per_page=100"
bin/rule_suite_bypass_ledger merge --raw <that json> --ledger data/ci_optimization/rule_suite_bypass_ledger/ledger.jsonl
```

`merged — existing=34 incoming=36 wrote=36`, i.e. **two** rows were added, not one:

```json
{"id":5424248788,"actor_id":53123826,"actor_name":"wintrover","before_sha":"c07d8e6f8ff82464ead41350b66fc6ffd2ff4066","after_sha":"0e84bf28791b75b3986cec2ae294979c0c462f11","ref":"refs/heads/main","repository_id":1454952493,"repository_name":"Axiom","pushed_at":"2026-11-28T17:26:55+09:00","result":"bypass"}
{"id":5425390411,"actor_id":53123826,"actor_name":"wintrover","before_sha":"0e84bf28791b75b3986cec2ae294979c0c462f11","after_sha":"e0856a9372d2dc945a8df8be727b3511eaa8ffd3","ref":"refs/heads/main","repository_id":1454952493,"repository_name":"Axiom","pushed_at":"2026-11-28T19:51:49+09:00","result":"bypass"}
```

The second row is this landing. The first is **not** this landing: it is the merge of PR #547
(`c07d8e6f -> 0e84bf28`), whose row was missing from the ledger even though the platform still had the
event in its rolling 30-day window. It was not added by hand - the sync tool writes every feed entry the
ledger lacks - and it is reported here rather than silently absorbed because a bypass landing without a
row is precisely what the ledger exists to prevent. Its authority record is outside this PR's scope and is
not claimed here.

`assert` after the write: **36 bypass landings**, range `2026-11-17T01:50:38+09:00 ..
2026-11-28T19:51:49+09:00`, **freshness FRESH (age=0d, limit=30d)**, and the two unperformed checks report
`UNKNOWN` rather than zero.

## §5. Not claimed here

- **The `merge_group` venue is not measured in this document.** A `merge_group` run only exists after a PR
  is enqueued, so this PR cannot carry the measurement of its own queue build. The numbers above are the
  `pull_request` and `push` venues; the `merge_group` observation is recorded in the next landing record.
- **Queue-level wall clock is not reduced by the full 96 s.** `admission-gate` is the co-pole: across the
  six baseline heads it ran 308-397 s (median 334 s) while `axiom-operational-slice` ran 361-436 s. The
  landed change moves the second of those down by ~90 s, which makes the two workflows roughly co-pole;
  the queue-level gain is therefore bounded by `admission-gate` from here on. Raising it requires work in
  that workflow, which is not this change.
- **The `ci-compile` duplication on the B-miss lane is not removed.** Both jobs compile the supply when
  the cache misses. Removing it would require one job to consume the other's binary, which would put the
  lane back behind a `needs:` edge and restore the serial cost. The duplication is accepted as the price
  of the placement.
- **The gate set's internal redundancy is not touched.** `check-cert-integrity` and
  `check-cert-integrity-fast` compile the same `bin/cert_integrity_gate` output twice, and the 24 gates
  fan out to 21-22 distinct `nim c` invocations. That is a property of `GATES_STATIC`'s definition, and
  changing it changes what the gate set is - a different decision from where it runs.