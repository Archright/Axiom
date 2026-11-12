# Landing-latency cutover — org DAG stage split (2026-10-05)

## What was cut over

`Archright/.github/.github/workflows/admission-gate.yml` — the org execution
authority for merge admission — was rewired around the Axiom
`admission-check.yml` callee's new two-stage contract, and the callee pin was
rotated.

| | before | after |
|---|---|---|
| callee pin | `admission-check.yml@87df2df5d997cdd15a9c72dbc5db8d87ba53e417` | `admission-check.yml@410b56da9b16a76d599c9776adf73c88850e0e0b` |
| callee invocations | 1 (`admission`, no inputs) | 2 (`attest` = `stage: attest`, `verdict` = `stage: verdict`) |
| aggregate MUST-chain | 4-way | 5-way |

Chain that produced this state:

- Archright/Axiom#466 — `ci(admission-check): split the callee into attest and
  verdict stages`, merge `410b56da9b16a76d599c9776adf73c88850e0e0b`
- Archright/.github#48 — `fix(ci): rewire the org admission DAG around the
  callee stage split`, org commit `c51877a`, merged
  2026-10-04T16:34:36Z as `31478a3fb39bb12e902021a397c5433f19738241`

## Job graph

```
gateway ─────────────────────────────────────────────┐
                                                     │
attest ──▶ mint-prepare ──▶ mint-publish ──▶ verdict │
                                                     │
   └──── all five success ───────────────────────────┴──▶ admission-check
                                                            (required check)
```

| job | needs | if | callee | job-level permissions |
|---|---|---|---|---|
| `attest` | — (head) | — | `admission-check.yml@410b56da` `stage: attest` | `contents: read`, `pull-requests: read` |
| `mint-prepare` | `[attest]` | `!cancelled()` | `certificate-mint.yml@db9afe5a1` `stage: prepare` | `contents: write`, `actions: read`, `pull-requests: read` |
| `mint-publish` | `[mint-prepare]` | `!cancelled()` | `certificate-mint.yml@db9afe5a1` `stage: publish` | same three |
| `gateway` | — | — | `runner-pool-acceptance.yml@7b14e5c63` | `contents: read` |
| `verdict` | `[mint-publish]` | `!cancelled()` | `admission-check.yml@410b56da` `stage: verdict` | `contents: read`, `pull-requests: read` |
| `admission-check` | `[attest, mint-prepare, mint-publish, verdict, gateway]` | `always()` | aggregate shell verdict | — |

## Why

The single `admission` job both produced the witness **and** evaluated
`MergeAdmissible`. The predicate reads the subject-continuity certificate, but
the mint chain was scheduled *after* that job, so the predicate always read the
certificate before it existed:

```
admission ──▶ mint-prepare ──▶ mint-publish ──▶ admission-check (required)
   ▲                                                              │
   └── produces the witness the certificate is minted from ───────┘
        certRequired cannot be satisfied yet → NO_CERT
```

Measured 2026-10-04 before the cutover: 17 wasted full runs, ~202 minutes
(`NO_CERT`, `reasonCode` recorded on Axiom #466). Splitting producer and
consumer into separate jobs makes the DAG `attest → mint → verdict`, so the
predicate reads a certificate this run already published.

## What was NOT changed

- **No MUST was weakened.** The aggregate went from a 4-way to a 5-way
  conjunction; every previous assertion is still present and `skipped` still
  fails it. `mint-prepare ∧ mint-publish` remain mandatory, so GREEN still
  requires a published certificate.
- The required check context `admission-check` (job **name**) is unchanged —
  Axiom ruleset `20303214` still matches it.
- `if: ${{ !cancelled() }}` on both mint jobs is **kept**: it is what lets the
  certificate reach the ledger even when the upstream stage denied.
- `if: ${{ always() }}` on the aggregate is kept: it is what turns a skipped
  need into a red check rather than a vacuous pass.
- No cycle. `verdict → mint-publish` is the only new edge and it points
  forward. A cyclic `needs` graph is rejected by GitHub at plan time with a
  zero-job run, so the acyclicity was checked locally before pushing.
- `attest`/`verdict` grant **exactly** the callee's top-level declaration
  (`contents: read`, `pull-requests: read`). The old `admission` job also
  granted `actions: read` and `checks: write`; both were P12-deletion
  leftovers (`checks: write` served a Check Run POST the callee no longer
  makes) and every `GITHUB_TOKEN` use in the callee is a `commits`/`pulls`
  read.

## Wiring validation — probe PR #469

An empty-commit probe branch (`ci/dag-rewire-probe-2026-10-05`, head
`a39ad0b122e7d58b86e5b761fdf74952a34fe36f`, base
`410b56da9b16a76d599c9776adf73c88850e0e0b`) was pushed purely to make the org
gate execute. No file is touched by it. It was **closed without merging**.

`admission-gate` run **37217761235** — event `pull_request`, run number 500,
**attempt 1**, conclusion `success`, created 2026-10-04T16:42:31Z, completed
2026-10-04T16:52:50Z (10 min 19 s wall clock, one attempt, no re-run).

| job id | job | attempt | conclusion | started → completed (Z) |
|---|---|---|---|---|
| 111481665701 | `gateway / select` | 1 | success | 16:42:35 → 16:43:41 |
| 111481665502 | `attest / build-base-artifacts` | 1 | success | 16:43:10 → 16:48:03 |
| — | `gateway / candidate-build-arm` · `ci-bootstrap` · `gateway-shard` · `proof-reconcile` · `gateway-identity-gate` | 1 | skipped | — |
| 111482657914 | `attest / admission-check` | 1 | success | 16:48:05 → 16:48:57 |
| 111482821668 | `mint-prepare / prepare` | 1 | success | 16:49:00 → 16:49:25 |
| 111482822827 | `mint-publish / prepare` | 1 | skipped | 16:48:58 → 16:48:57 |
| 111482902696 | `mint-publish / publish` | 1 | success | 16:49:28 → 16:49:53 |
| 111482992632 | `verdict / build-base-artifacts` | 1 | skipped | 16:49:55 → 16:49:55 |
| 111482992812 | `verdict / admission-check` | 1 | success | 16:49:58 → 16:52:44 |
| 111483504944 | `admission-check` (aggregate) | 1 | success | 16:52:46 → 16:52:50 |

Ordering is the DAG's: `attest` completes at 16:48:57, both mint jobs run
inside it, and only then does `verdict / admission-check` start at 16:49:58.

Verdict, verbatim from job 111482992812 at 2026-10-04T16:52:42Z:

```json
{"prNumber":469,"headSha":"a39ad0b122e7d58b86e5b761fdf74952a34fe36f","baseSha":"410b56da9b16a76d599c9776adf73c88850e0e0b","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base freshness bound to main 410b56da9b16; GitHub re-binds at merge time)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

The mechanism, verbatim from the same job at 2026-10-04T16:50:43Z:

```
[check] certificate source = ARTIFACT subject-certificate-1 (--cert /home/runner/work/Axiom/Axiom/.subject-certificate/certificate.json)
```

The predicate consumed the certificate **published by this run's own
`mint-publish`**, not a ledger entry from a previous attempt. That is the
specific state the old ordering could not reach on a `pull_request` run.

Aggregate, verbatim from job 111483504944 at 2026-10-04T16:52:48Z:

```
[verdict] OK — attest ∧ mint-prepare ∧ mint-publish ∧ verdict ∧ gateway callee succeeded
```

Artifacts — `GET /repos/Archright/Axiom/actions/runs/37217761235/artifacts`,
`total_count = 6`:

| id | name | created (Z) | size |
|---|---|---|---|
| 11308893762 | `tested-tree-digest` | 16:42:54 | 185 B |
| 11308398799 | `ci-select-decision` | 16:43:37 | 2703 B |
| 11308514950 | `ci-select-verifier` | 16:43:38 | 207265 B |
| 11308819361 | `admission-check-base-artifacts` | 16:48:01 | 86329469 B |
| 11308239553 | `admission-check-a39ad0b122e7d58b86e5b761fdf74952a34fe36f-1` | 16:48:55 | 1510 B |
| 11308234413 | `subject-certificate-1` | 16:49:23 | 3544284 B |

Exactly one witness artifact
(`admission-check-a39ad0b12…-1`, attempt-scoped) and exactly one
`subject-certificate-1`. No unsuffixed twin, no legacy name.

One content change to note. The witness artifact is now **smaller** (1510 B
against 2750 B under the old single-invocation shape) because it holds only
`witness.json` + `witness.sha256`. Its `path:` list still names
`admission-verdict.log` and `admission-gate-history.txt`, but both are written
by the **verdict** stage's predicate step, which by construction runs after the
upload — so on an attest invocation they are absent and
`if-no-files-found: warn` applies. This is not a contract break: the mint's sole
inputs are `witness.json` + `witness.sha256`, `MINT_ART: OK` holds, and the
verdict log is now obtainable from the `verdict / admission-check` job itself.
Recorded because it is an observable difference from the pre-cutover artifact,
not because it blocks anything.

## Contrast with the pre-cutover shape — Axiom #466

`#466` landed through the **old** pin and DAG. Its `merge_group` run
**37216206898** was also `success` on attempt 1, but for a different reason:

```
[check] certificate source = SIDE-REF LEDGER scan (subject-certificate-1 not published in this run — pre-gate/ordering, ADR-0022 §D5-3 bootstrap path)
```

Its `pull_request` run (37214773132) needed two attempts — attempt 1 closed
`admission / admission-check` with `failure` and attempt 2 succeeded — and only
that second attempt published a certificate into the ledger. The
`merge_group` run then found it there.

So attempt-1 green is not, by itself, evidence of the DAG fix: a
`merge_group` run could already be green on attempt 1 through ledger
convergence. The discriminating observation is the **certificate source line**:
`ARTIFACT` (same run) under the new DAG versus `SIDE-REF LEDGER` (a previous
attempt) under the old one, on a `pull_request` run that was previously unable
to be green on attempt 1 at all.

## Acceptance measurement — a merge_group landing under the new DAG

Probe PR #469 stopped at the `pull_request` path. The terminal outcome of this
cutover is a `merge_group` landing, so the acceptance measurement is taken from
one: Axiom PR #468 (`chore/tmp-org-dag-smoke`, empty commit — the tree delta is
zero, which is what makes it a usable probe).

`admission-gate` run **37218381038** — event `merge_group`, **attempt 1**,
conclusion `success`, queue ref
`gh-readonly-queue/main/pr-468-ed9ee842cdba4ddeab9a143f2fd767550857db4e`,
head `3779d5167616385e53b739190b6ede914cf471d0`.

| job id | job | conclusion | started → completed (Z) |
|---|---|---|---|
| 111483493460 | `attest / build-base-artifacts` | success | 16:52:43 → 16:57:36 |
| 111483493645 | `gateway / select` | success | 16:52:44 → 16:53:33 |
| 111483656218 · 111483656358 · 111483656638 · 111483656734 · 111483656748 | `gateway / ci-bootstrap` · `candidate-build-arm` · `gateway-identity-gate` · `gateway-shard` · `proof-reconcile` | skipped | — |
| 111484397238 | `attest / admission-check` | success | 16:57:39 → 16:58:36 |
| 111484575996 | `mint-prepare / prepare` | success | 16:58:40 → 16:59:12 |
| 111484577122 | `mint-prepare / publish` | skipped | — |
| 111484683368 | `mint-publish / publish` | success | 16:59:15 → 16:59:35 |
| 111484685031 | `mint-publish / prepare` | skipped | — |
| 111484753850 | `verdict / build-base-artifacts` | skipped | — |
| 111484753553 | `verdict / admission-check` | **success** | 16:59:38 → 17:04:28 |
| 111485687396 | `admission-check` (aggregate) | success | 17:04:32 → 17:04:35 |

The timestamps are the trust order, not a schedule: `attest` completes at
16:58:36, both mint jobs sit inside it, and `verdict / admission-check` cannot
start before 16:59:38 — which is after `mint-publish / publish` completed at
16:59:35.

Verdict, verbatim from job 111484753553:

```json
{"prNumber":468,"headSha":"8899921dbefc47b879892ca86fb5319c7db607e4","baseSha":"ed9ee842cdba4ddeab9a143f2fd767550857db4e","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base freshness bound to main ed9ee842cdba; GitHub re-binds at merge time)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

Certificate source, same job:

```
[check] certificate source = ARTIFACT subject-certificate-1 (--cert /home/runner/work/Axiom/Axiom/.subject-certificate/certificate.json)
```

Aggregate, verbatim from job 111485687396:

```
[verdict] OK — attest ∧ mint-prepare ∧ mint-publish ∧ verdict ∧ gateway callee succeeded
```

Artifacts — `GET /repos/Archright/Axiom/actions/runs/37218381038/artifacts`,
`total_count = 6`:

| id | name | created (Z) | size |
|---|---|---|---|
| 11309182001 | `tested-tree-digest` | 16:52:59 | 185 B |
| 11308909814 | `ci-select-decision` | 16:53:30 | 2647 B |
| 11309720183 | `ci-select-verifier` | 16:53:31 | 207265 B |
| 11309401236 | `admission-check-base-artifacts` | 16:57:34 | 86327962 B |
| 11309790599 | `admission-check-3779d5167616385e53b739190b6ede914cf471d0-1` | 16:58:34 | 1507 B |
| 11309202292 | `subject-certificate-1` | 16:59:09 | 3544085 B |

Exactly one attempt-scoped witness artifact and exactly one
`subject-certificate-1`. No unsuffixed twin, no legacy name.

### Criterion-by-criterion

| criterion | result | evidence |
|---|---|---|
| `admission-check` green on **attempt 1**, no `NO_CERT` re-run | met | run 37218381038 `run_attempt = 1`; `verdict / admission-check` success; `reasonCode: GO`, `mergeGo` |
| `merge_group` merges with **zero** `STALE_BASE` re-dances | met | exactly one `admission-gate` `merge_group` run exists for pr-468 (37218381038), attempt 1, no re-run; the queue ref's base `ed9ee842cdba` equals `origin/main` for the whole run |
| artifact list shows exactly ONE `admission-check-<head>-<attempt>` and ONE `subject-certificate-<attempt>` | met | `admission-check-3779d516…-1` and `subject-certificate-1`, `total_count = 6` |
| `git log origin/main` shows the merge commit landed via the queue | met | `3779d5167 Merge pull request #468 from Archright/chore/tmp-org-dag-smoke`, commit date `2026-10-04T16:52:21Z` — the merge_group head sha became the main tip |

### Second landing under the same DAG

Axiom PR #467 (`fix/freshness-authoritative-anchor`) was blocked on the old
DAG: its first `merge_group` run (37216694673) closed
`admission / admission-check` as `failure` at 16:34:12Z while `mint-prepare`
and `mint-publish` both succeeded — the mint published a certificate the
predicate had already finished looking for. Re-queued against the new
`admission-gate.yml`, run **37218154447** went green on attempt 1 across the
full five-job graph, and #467 merged as `ed9ee842cdba`. That is the same DAG
carrying a second real landing, and it is the direct before/after of the
ordering fault.

## The evidence record's own landing — Axiom #471

The acceptance above was taken on Axiom #468, a throwaway empty-commit probe.
The same queue path was then exercised by the landing of this record itself,
which is the stronger vehicle because its merge commit carries the content
being described.

`admission-gate` runs for #471 (`docs/landing-latency-cutover-2026-10-05-final`):

| run | event | attempt | conclusion |
|---|---|---|---|
| 37219478865 | `pull_request` | 1 | success |
| 37220214765 | `merge_group` | 1 | success |

Verdict, verbatim from `verdict / admission-check` (job 111490106225) at
2026-10-04T17:34:34Z:

```json
{"prNumber":471,"headSha":"c0585cc917d0b7750e5959f87bc646be1cfc8149","baseSha":"3779d5167616385e53b739190b6ede914cf471d0","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base freshness bound to main 3779d5167616; GitHub re-binds at merge time)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

Run 37220214765 was created 2026-10-04T17:21:39Z and completed
2026-10-04T17:34:43Z, `run_attempt = 1`. `GET …/runs/37220214765/artifacts`
returns `total_count = 6`:

| id | name | created (Z) |
|---|---|---|
| 11309971710 | `tested-tree-digest` | 17:21:58 |
| 11310042729 | `ci-select-decision` | 17:22:29 |
| 11309718298 | `ci-select-verifier` | 17:22:30 |
| 11309318197 | `admission-check-base-artifacts` | 17:26:37 |
| 11310158062 | `admission-check-66b3e12f1d107a7bc4088b9e5d20f636050a28a9-1` | 17:27:36 |
| 11310062192 | `subject-certificate-1` | 17:28:08 |

Exactly one witness artifact, exactly one `subject-certificate-1`, one
`merge_group` run, one attempt, and the merge commit landed as
`66b3e12f1d107a7bc4088b9e5d20f636050a28a9` on `main`.

## R4 residual measurement — does the PR path still deny `STALE_BASE` when main moves mid-run?

**Recorded as an observation, not a decision.** Whether the `STALE_BASE`
predicate should ever be relaxed is a separate question and is not answered
here.

The race was constructed deliberately. Axiom #471 was sitting in the merge
queue; probe PR #473 (`ci/r4-stale-base-probe-2026-10-05`, one empty commit)
was opened at 2026-10-04T17:26:40Z so that its `pull_request` admission-gate
run would reach its verdict stage after #471 landed.

`admission-gate` run **37220533061** — event `pull_request`, **attempt 1**,
conclusion `success`, created 17:26:43Z, completed 17:38:23Z.

| moment | UTC |
|---|---|
| probe #473 opened | 17:26:40Z |
| run 37220533061 created | 17:26:43Z |
| `verdict / admission-check` started | 17:34:13Z |
| **Axiom #471 merged into `main`** (`66b3e12f1`) | **17:35:09Z** |
| PR context resolved / certificate selected | 17:35:24Z |
| predicate evaluated | 17:38:12Z |
| `verdict / admission-check` completed | 17:38:14Z |
| aggregate `admission-check` | 17:38:18Z → 17:38:22Z, success |

`main` therefore advanced **56 seconds into** the verdict job, and the
predicate evaluated 3 min 03 s after the move.

Verdict, verbatim from `verdict / admission-check` (job 111491162686) at
2026-10-04T17:38:12Z:

```json
{"prNumber":473,"headSha":"94b26a32935e50ab52896a41421a4c03d787a214","baseSha":"3779d5167616385e53b739190b6ede914cf471d0","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base freshness bound to main 3779d5167616; GitHub re-binds at merge time)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

**Result: no `STALE_BASE`, no re-dance.** One attempt, one run, green, with a
concurrent main move inside the verdict job.

### What this observation does not establish

The pre-merge anchor and the post-merge anchor did not actually differ in this
instance, so the run does not isolate the event-frozen anchor as the reason for
the clean result.

`GET /repos/Archright/Axiom/pulls/473` reported `base.sha =
3779d5167616385e53b739190b6ede914cf471d0` before the merge, and still reported
the same value when re-read at 17:41:54Z — at which point `origin/main` was
already `66b3e12f1`. GitHub's `pulls/{n}.base.sha` is a snapshot that does not
track the base branch tip on this path, so a plain main move does not drive the
two candidate anchors apart on a `pull_request` run.

Consequences, stated plainly:

- **Exercised:** a main move landing inside the verdict job's execution window
  produces no spurious `STALE_BASE` and no re-run on the PR path.
- **Not exercised:** the deterministic re-run variant of this probe. A re-run
  replays the same frozen `pull_request` payload against the same
  non-divergent live `base.sha`, so it would have reproduced the same state;
  it was not run because it could not have measured anything the live race did
  not already measure.
- **Out of scope here:** the divergence Axiom #467 targets is reported on the
  `merge_group` path, where `merge_group.base_sha` advances with the queue
  while the PR snapshot lags. This probe does not speak to that path.

## Supersession — Axiom #465

Axiom #465 (`docs/mint-identity-cutover-2026-10-04`,
`docs/evidence/mint_identity_cutover_2026-10-04.md`) records the attempt-scoped
witness-identity cutover (Axiom #459 / #461 / #463, org #46). **It is left to
land, not folded in or closed.**

Its content is an independent observation of a different cutover, taken under
the **pre-split** DAG, and that state no longer exists — the runs it quotes
cannot be re-measured. Deleting it would remove the only record of the
intermediate state.

One of its claims is now historical rather than current: it describes the
two-attempt bootstrap as "the designed shape". That was accurate for the DAG
this record replaces and is not accurate now — attempt 1 is green, and the
mechanism is the certificate-source line (`ARTIFACT` same-run versus
`SIDE-REF LEDGER` from a previous attempt) recorded above. This section is the
correction of record; #465's text is left as written so the observation stays
faithful to the DAG it was taken on.
