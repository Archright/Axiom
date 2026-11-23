# CI admission wall — first cross-workflow measurement (2026-11-24)

Status: MEASURED, n=2 observed candidates. No performance claim is made.

## What was measured

`tools/ci/ci_admission_observe.nim` (new, `axiom.ci_admission_observe.v1`) measures the
seven required contexts of ONE merge-group candidate and partitions the interval from
queue entry to merge. It consumes the cohort that `tools/ci/ci_acceptance_collect`
already selected (`--cohort-from`), so both tools describe the SAME candidates.

The four phases are non-overlapping by construction:

    T_queue       = first required context started_at - queue entry
    T_verify      = last general context completed_at - first required context started_at
    T_publication = max(all 7 completed_at) - last general completed_at
    T_merge       = merged - max(all 7 completed_at)
    T_ready       = T_queue + T_verify + T_publication
    T_admission   = T_ready + T_merge

`T_exec` is deliberately NOT reported. It equals `T_verify + T_publication`, so summing it
again would double-count. The earlier claim that #420 was `439 = T_exec` is consistent with
this: 436 + 3 = 439, and 439 is `T_verify + T_publication`, not a fifth phase.

`T_landing` and `T_admission` are the same interval (queue entry to merge). Only
`T_admission` is reported.

## Authority

Policy `config/policy/merge_admission.json` and live ruleset 27097366 agree exactly:

| context | producer |
|---|---|
| `admission-check` | app 5795152 (axiom-admission-verifier) |
| `axiom-operational-slice`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `publication-integrity`, `readiness-verdict` | app 15368 (GitHub Actions) |

The observer refuses to publish if the policy set and the live ruleset set differ (exit 1).
Both runs reported `context_sets_equal: true`.

## Baseline cohort

`bin/ci_acceptance_collect --boundary a759f2da --window 20 --mode initial`:

    status=INCOMPLETE window=8/20 shortfall=12 excluded_before_boundary=32
    counts: success=4 internal_defect=0 unclassified=1 external_dependency_blocked=3
    latency canonical n=8 p50=759.5s mean=733.9s min=423s max=1114s
    accepted=false

8 post-boundary candidates exist; 2 of them merged. The other 6 never merged their
candidate SHA, so `T_admission` is UNKNOWN for them by construction, not by tool failure:

| pr | head_sha | reason |
|---:|---|---|
| 407 | `40b06a1712de` | the PR merged commit `75c6d8d4`, not this candidate's head_sha |
| 402 | `aa59d327333f` | not merged yet |
| 402 | `31bcff29246d` | not merged yet |
| 400 | `0bb7a803e344` | not merged yet |
| 400 | `5a0761c4b58b` | not merged yet |
| 400 | `b9e38a51fe90` | not merged yet |

## Observed admission wall

| phase | n | p50 | p90 | min | max |
|---|---:|---:|---:|---:|---:|
| T_queue | 2 | 13.0 | 17.8 | 7s | 19s |
| T_verify | 2 | 559.0 | 577.4 | 536s | 582s |
| T_publication | 2 | 0.0 | 0.0 | 0s | 0s |
| T_ready | 2 | 572.0 | 585.6 | 555s | 589s |
| T_merge | 2 | 23.0 | 31.0 | 13s | 33s |
| T_admission | 2 | 595.0 | 600.6 | 588s | 602s |

p50 is the canonical collector's estimator (identical to R-7 at p=0.5); p90 is Hyndman-Fan
type 7 on the same sorted integer-second array. Nearest-rank is not used: mixing estimator
families would allow p90 < p50.

Per-candidate:

| pr | queue | verify | publication | merge | ready | admission | last finisher |
|---:|---:|---:|---:|---:|---:|---:|---|
| #416 | 7s | 582s | 0s | 13s | 589s | 602s | `readiness-verdict` |
| #415 | 19s | 536s | 0s | 33s | 555s | 588s | `readiness-verdict` |

## What this refutes

**`T_publication` is 0, not 3s.** In both observed candidates the App verdict
(`admission-check`, app 5795152) completed BEFORE the last general context. #416: verdict
`14:12:10`, `readiness-verdict` `14:12:13`. The App publication tail is therefore not a
current bottleneck, and the "publication is a 3s phase" reading of #420 does not generalize.

**The critical workflow is not `publication-integrity`.** Non-skipped job counts and the
longest job span per workflow, both candidates:

| workflow | #416 jobs / max span | #415 jobs / max span |
|---|---:|---:|
| `axiom-operational-slice.yml` | 2 / **356s** | 2 / **304s** |
| `publication-integrity.yml` | 10 / 319s | 10 / 268s |
| `admission-gate-v2.yml` | 15 / 159s | 15 / 159s |
| `debt-registry-gate.yml` | 1 / 99s | 1 / 70s |
| `bsec-integrity.yml` | 1 / 66s | 1 / 80s |
| `observation.yml` | 1 / 61s | 1 / 100s |
| `generation-acceptance.yml` | 1 / 13s | 1 / 16s |
| `probe-merge-queue.yml` | 1 / 11s | 1 / 8s |

`axiom-operational-slice.yml` reaches the wall through a **two-job serial chain in one
workflow** (`readiness-verdict: needs: [axiom-operational-slice]`). Its dominant step is
`Prove, replay the same certificate ...` (277s in #416, 205s in #415) inside the first job,
followed by `Readiness decision test suite` (81s / 85s) in the second.

`publication-integrity.yml` has 10 parallel jobs and finishes EARLIER. Optimizing it cannot
move `T_admission` while the serial slice chain is longer. The earlier plan targeted the
wrong workflow.

**"Environment setup is ~83s" does not reproduce.** Measured `setup-axiom-toolchain` spans:
26s in the slice producer job, 60s in `readiness-verdict`, 53s and 61s in the #415 pair.
Those two jobs total 86s and 114s of provisioning, but they are SERIAL, and the pre-built
evaluator idea would remove only the two Nim compiles inside them (`build the release
verifier` 9s/5s, `build the Lean reference extractor` 1s/0s) — about 5s of a 588-602s wall,
while requiring an artifact that the trust-surface contract forbids executing
(`src/gate/slice_catalog.nim:362`).

## What this does NOT establish

- **n=2.** Both observations are single-PR queue cycles. p90 over n=2 is arithmetic, not a
  distribution. No SLO claim follows.
- **The canonical job span and this admission wall are different quantities.** The canonical
  `p50=759.5s` (n=8) is the `admission-gate` job span; the admission wall here is `595s` over
  a DIFFERENT, smaller cohort (n=2). They must never be compared as one series.
- **`readiness-verdict` finishing last is an observation, not a causal finding.** Its `needs:`
  edge plus the per-step spans are consistent with it being on the critical path, but a
  step-level attribution of the 277s `Prove, replay ...` step has not been done.
- **No optimization has been applied.** This change adds a measuring instrument only.

## Reproduce

```bash
nim c -d:release --hints:off --path:src -o:bin/ci_acceptance_collect tools/ci/ci_acceptance_collect.nim
./bin/ci_acceptance_collect --repo Archright/Axiom \
  --boundary a759f2da1770e51bd4dd6569df01ae65c7152351 \
  --window 20 --mode initial --out build/ci_acceptance

nim c --hints:off --path:src -o:build/bin/ci_admission_observe tools/ci/ci_admission_observe.nim
./build/bin/ci_admission_observe --repo Archright/Axiom \
  --cohort-from build/ci_acceptance/ci_acceptance_report.json \
  --ruleset 27097366 --out build/ci_admission
```

`--ruleset` is required. A policy/ruleset context mismatch exits 1 without publishing.
Any UNKNOWN candidate exits 2. Determinism is "the same snapshot yields the same numbers":
two consecutive runs over the same cohort produced byte-identical `phase_stats`,
`candidates`, `authority` and `last_finisher_counts`.

Exit codes: 0 OBSERVED (all candidates bound and reconciled), 1 FAILED (authority mismatch
or reconciliation residue), 2 INCOMPLETE (at least one candidate UNKNOWN).

## Binding rules the fixtures pin

Measured against the live API, and enforced by `tests/ci/test_ci_admission_observe.nim`
(50 assertions; 8 deliberate mutations, 8 killed):

- A general context binds ONLY through the attempt-exact edge
  `GET /actions/runs/{id}/attempts/{n}/jobs` -> `job.check_run_url`. "Newest check-run with
  that name" is never a fallback; a same-name run outside the attempt set is UNKNOWN.
- `check_suite.id` identifies the RUN but spans every attempt, so it cannot identify the
  producing attempt. `run_attempt` reports the run's CURRENT counter (an attempt-1
  check-run reports 2 after a re-run) and is never used as the producing attempt.
- The App verdict requires the declared producer app AND uniqueness inside the queue cycle.
  Two verdicts from that app are UNKNOWN, not a pick. `admission-check` is published by BOTH
  app 15368 and app 5795152 on the same SHA, so `(name, head_sha)` is ambiguous by itself.
- The App verdict window is the QUEUE CYCLE, not the Actions run. Measured #416: verdict
  started `14:02:31`, its run was created `14:02:32`. Bounding on run creation rejects the
  real verdict; an App verdict cannot predate queue entry.
- Merging binds by `commit_id == head_sha`. The same PR number can appear several times in
  one cohort with different SHAs (measured: 402 and 400 each appear twice), so "the last
  merged event for this PR" is not a valid binding.
- GitHub returns run/suite/app ids as JSON NUMBERS. Reading them as strings produces
  `.../runs//attempts/1`; every id goes through a numeric-capable reader.

## Deferred, with reasons

- `#417b` (ScanCode transitive bytes): the byte-pinning mechanism does not exist in the
  policy SSOT and the scanner's runtime is unpinned. A trust-surface change, not a
  measurement task.
- `#419` (PR-scope cache writers): `docs/spec/github_delegation_residuals.md` forbids
  reimplementing seeding suppression or self-expiry (R11/R12), and cache deletion is
  explicitly out of scope. A policy change, not a measurement task.
- `#421` (critical path): reclassified **UNKNOWN — measure first**. The measurement above
  shows the target it named (`publication-integrity`) is not the longest chain; the serial
  `axiom-operational-slice` -> `readiness-verdict` chain is. Both files are trust-surface
  entries, so shortening them is an architect decision, not an agent edit.

## Addendum — step-level attribution (2026-11-24, post-landing)

This addendum corrects one sentence in the section above and adds the step-level attribution
that the original measurement could not make. Everything here is measured from
`GET /actions/runs/{id}/jobs` `steps[]` on the two observed queue cycles (#416 run
`45189948196`, #415 run `45195134265`) and the paired `publication-integrity.yml` runs
(`45189948255`, `45195134581`).

### Correction: the ~83s environment setup DOES reproduce

The section above states that `"Environment setup is ~83s" does not reproduce`. That is
wrong, and the error matters because it understates the finding.

Measured `setup-axiom-toolchain` spans inside `publication-integrity.yml`:

| job | #416 | #415 |
|---|---:|---:|
| `license-scan` (serial, after the 3 shards) | 13s | **41s** |
| `publication-integrity` (serial, after `license-scan`) | 10s | **43s** |
| **serial tail total** | **23s / 50s wall** | **84s / 124s wall** |

In #415 the serial tail is 124s of which 84s — **68%** — is provisioning of the SAME
toolchain, twice, in two consecutive jobs. The ~83s figure was accurate. It is not in the
scans; it is in the two adjudication jobs that follow them.

### The correction does not rescue #421, and this is why

The 84s is real but it is not on the critical path, because `publication-integrity.yml`
finishes with slack:

| workflow | chain start | last job complete | chain wall |
|---|---|---|---:|
| `axiom-operational-slice.yml` (#415) | 14:31:35 | **14:40:28** | **533s** |
| `publication-integrity.yml` (#415) | 14:31:33 | 14:38:09 | 396s |

139s of slack (#415), 208s (#416). Removing all 84s of the tail provisioning moves that
workflow's completion to ~14:36:45 — still 223s before the last required context. Net effect
on `T_admission`: **zero**.

So #421's *measurement* was right and its *attribution* was wrong. It named a workflow that
has slack, while the same defect (the same toolchain provisioned twice in one serial chain)
sits inside the chain that has none.

### Where the time actually goes on the critical chain

`axiom-operational-slice.yml` is two jobs joined by `needs:`. Both provision from scratch.
#415, 533s total:

| | span | share |
|---|---:|---:|
| `axiom-operational-slice` job | 304s | 57% |
| — `Prove, replay the same certificate ...` | 205s | 38% |
| — `setup-axiom-toolchain` | 53s | 10% |
| `readiness-verdict` job | 227s | 43% |
| — `Readiness decision test suite` | 85s | 16% |
| — `setup-axiom-toolchain` | 61s | 11% |
| — `Run the readiness gate` | 34s | 6% |
| — `Collect R1–R8 evidence` | 29s | 5% |
| **serial provisioning, both jobs** | **114s** | **21.4%** |

#416 gives 86s of 579s (14.9%), with `Prove` at 277s (48%).

Two facts follow that the earlier text did not have:

1. **The removable block is 114s of duplicate provisioning, not 83s in the scanner**, and it
   is inside a trust-surface workflow.
2. **An exact cache HIT costs ~28s.** In #415 the A-layer restore reported
   `exact-hit=true` at `14:37:20.688` after starting at `14:36:52.354` — 28.3s to restore a
   payload it already matched. Raising hit rate past 100% cannot go below this floor, so
   the "restore is the win" model is already exhausted at the current hit rate.

### Reconciliation with the canonical collector

The canonical `wall_seconds` and the admission wall are different quantities, measured:

| quantity | #416 | #415 |
|---|---:|---:|
| collector `wall_seconds` (`admission-gate` job span) | 568s | 423s |
| `admission-check` check-run span (App 5795152) | 579s | 432s |
| observer `verify` (first required start → last required complete) | 582s | 536s |
| observer `ready` (queue entry → all 7 complete) | 589s | 555s |
| observer `admission` (queue entry → merged) | 602s | 588s |

The collector's number tracks the *verdict-issuing workflow* (568 vs 579 = 11s of
check-run framing), not admission. That is correct by its own contract and must not be
re-labelled; it simply cannot answer the admission question, which is why this instrument
exists.

### Cache inventory at measurement time

`GET /repos/Archright/Axiom/actions/caches`, all pages:

| family | entries | size |
|---|---:|---:|
| `axiom-b-` (build artifacts) | 103 | 5.24 GiB |
| `axiom-a-rt-` (runtime) | 118 | 1.55 GiB |
| `axiom-a-` full (single entry) | 1 | 1.05 GiB |
| `axiom-a-nim-` | 1 | 0.19 GiB |
| **total** | **223** | **7.91 GiB** |

By ref: 106 entries / 6.52 GiB on `main`, 117 entries / 1.57 GiB on `refs/pull/**`.

Two consequences for previously stated acceptance numbers:

- `PR-scope cache = 117 entries / 1573.6 MiB` reproduces exactly; the figure in the earlier
  plan was correct.
- A `≤ 2 GiB total` target is **not reachable** from hygiene alone: a single `A full` entry
  is 1.05 GiB and is the canonical supply for the merge-group lane. The target must be
  restated per family before it can be used as an acceptance gate.

### The `§3` gap in `docs/spec/ci_critical_path_metric.md`

The document numbers `§2.6` then jumps to `§4`. `git log -S"## §3"` over the file's three
commits returns nothing, so no content was lost — it is an authoring gap in the frozen
document. It is recorded here rather than silently renumbered, because that document is a
frozen metric contract and renumbering it would break references.