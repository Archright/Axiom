# merge_group wall-clock after S1 and S2 - five cycles on main, three warm samples

> **Status**: measurement record (reporter). This document **creates no authority of any kind**: it
> changes no policy, workflow, ruleset, gate, or pin, and no gate consumes its values. The normative
> rules for admitting CI work stay with `docs/spec/ci_admission_budget_contract.md`; this record only
> preserves the per-run observations that an admission decision can later be argued from.
> **Created**: 2026-11-27
> **Measured commits**: `main` @ `a6805fc4` (cycle 1), `dd1ddb93` (cycle 2), `f21e9ec1` (cycle 3),
> `87c480f4` (sample 2, section 13), `64c3edf0` (sample 3, section 14)
> **Measured cycles**: five merge_group windows on the same day - `2026-11-27T04:30:44Z`,
> `2026-11-27T08:15:56Z`, `2026-11-27T08:54:20Z`, `2026-11-27T09:49:48Z`, `2026-11-27T10:38:30Z`
> **Observation method**: GET-only REST reads through native `gh` authentication (AGENTS.md section
> 2.4). No local timer, no instrumentation, no added workflow step. Every number below is a
> subtraction of two platform-recorded timestamps (`run_started_at`, `updated_at`, `started_at`,
> `completed_at`), or a verbatim quotation of a log line. The Class A test results in section 7 were
> produced by running the in-tree tests on the measured tree, not read from a prior record.
> **ASCII note**: this page is 7-bit clean. Quoted log text that contains a typographic dash
> (U+2014) is reproduced with an ASCII `-` and says so at the quotation site.
> **Elision note**: in the quoted cache-marker lines, the long cache-key bodies are replaced with
> `<A>` and `<B>`. This is a secret-scan constraint, not a redaction of meaning: the repository's
> secret-scan gate classifies a full key body as a `generic-api-key` finding, and this record is a
> documentation-only change that must not require a baseline edit. Every elision is marked, the
> markers around it (`exact-hit`, `skip-a-restore`, the absence of an A-restore line) are verbatim,
> and section 4.5 preserves the one key distinction the argument depends on. The full values are
> reproducible with section 10's commands.

---

## 0. Purpose, and the two outcome classes that must not be mixed

**Scope.** Measure whether the two changes that landed on 2026-11-27 between cycle 1 and cycle 3 -
S1 (PI license-scan 5-shard split) and S2 (`mint-publish` skip-A-restore) - moved merge_group
wall-clock on `main`, and separate that from the correctness question, which a wall-clock number
cannot answer.

The two outcome classes are the same two this repository already uses
(`docs/evidence/merge_group_critical_path_2026-11-27.md` section 0), repeated here so this page
stands alone:

- **Class A - correctness slices.** Wall-clock expectation: **0 s**. Completion is defined by
  *re-run determinism* and *declared == executed*. A correctness slice is complete when those
  properties are observed, **not** when a timer moves.
- **Class B - speed slices.** Completion is defined by an **observed merge_group wall-clock change**
  in the run records. A speed slice is complete only when a later cycle's tail shrinks; the code
  change alone is not completion.

**Judgment rule.** Each slice is judged only on the completion criterion of its own class. A
correctness slice that moves no timer is a **success**, not a weak result; a speed slice that ships
with no observed wall-clock delta is **not done**, even if every test is green.

The judgment is in section 8, with the steady-state sample added in section 13. Stated up front so it
cannot be read as a hedge: **Class A holds on the evidence quoted here, and Class B's target was not
met on the cycle measured in section 4** - the one warm sample is **400 s** against a 345 s target.
The second warm sample (section 13) is **312 s**, which is below the target but does not demonstrate
it, because the contract is on a median and two samples give 356 s (section 13.5). **A third warm
sample (section 14) is 346 s**, which fixes the median of three at **346 s** - still 1 s above the
target, so the target remains **not demonstrated** while the mechanism gains behind it are real
(section 14.5).

---

## 1. The three measured cycles

All nine runs below were created by a merge-queue event on `main`. Cycle 1 is the baseline already
decomposed in `docs/evidence/merge_group_critical_path_2026-11-27.md`; cycles 2 and 3 are new here.

| cycle | tree | queue group commit | window (UTC) | `admission-gate` | `publication-integrity` | `axiom-operational-slice` |
|---|---|---|---|---|---|---|
| 1 - baseline | `a6805fc4` | - (pre-split tip) | `04:30:44` | **368 s** (`45940366569`) | 356 s (`45940366345`) | 297 s (`45940366417`) |
| 2 - S1 only, S2 not landed | `dd1ddb93` (PR #527) | `dd1ddb93` | `08:15:56` | **421 s** (`45964332106`) | 258 s (`45964331956`) | 284 s (`45964332053`) |
| 3 - S1 + S2, warm | `f21e9ec1` (PR #528, docs-only) | `f21e9ec1` | `08:54:20` | **400 s** (`45969305727`) | 267 s (`45969305538`) | 289 s (`45969305608`) |

Cycle 3 is the sample that includes both changes. Its merge subject is a docs-only PR, which is what
makes it usable: a docs-only head changes no workflow, so cycle 3 runs the same workflow bytes as
cycle 2 while carrying S2 in the tree.

**Read this before the numbers.** Cycle 3 is the **first** cycle with both changes in the tree, and
it is **warm** - the toolchain caches were repopulated by a push run off the queue path (section 5).
It is **one sample**, not a controlled A/B, and a median cannot be computed from it.

**Added later.** A second warm sample - the landing of this document's own predecessor - is measured
in section 13. It is 312 s, and it is the first cycle in the series whose diff could not move any
judgement input.

---

## 2. Cycle 1 - baseline, 368 s

Already decomposed in `docs/evidence/merge_group_critical_path_2026-11-27.md` sections 2-4. The
spans re-derived from the run records for this page agree with that document, so it is cited rather
than duplicated:

- `admission-gate` chain: `build-base-artifacts` 78 s, `go-critical-lane (1)` 117 s,
  `attest / admission-check` 65 s, `mint-prepare` 20 s, `mint-publish` 69 s, final context 5 s.
- `publication-integrity`: three shards at 225 / 293 / 263 s, aggregate 33 s, final 24 s.
- `axiom-operational-slice`: slice 144 s, `readiness-verdict` 148 s (sequential).

The session record that set the target quotes **392 s as the median of 11 merge_group candidates**
for this lane. That median is the number the Class B target in section 8 is measured against; it is
a session-recorded aggregate, not re-derived here.

---

## 3. Cycle 2 - S1 landed, S2 not: 421 s

Group commit `dd1ddb93` (PR #527), window opens `2026-11-27T08:15:56Z`. S1 (PI 5-shard) is in this
tree; S2 (`mint-publish` skip-A-restore) is **not** - it lands later, in `c3433cd6` (PR #525).

### 3.1 `admission-gate` run `45964332106`, `08:15:56` -> `08:22:57` (421 s)

| job | window (UTC) | span |
|---|---|---|
| `attest / build-base-artifacts` | `08:15:59` -> `08:17:06` | 67 s |
| `attest / go-critical-lane (1)` (slower lane, on chain) | `08:17:08` -> `08:19:40` | **152 s** |
| `attest / go-critical-lane (0)` | `08:17:08` -> `08:19:01` | 113 s |
| `attest / admission-independents` | `08:17:08` -> `08:18:44` | 96 s |
| `attest / admission-check` | `08:19:42` -> `08:20:45` | 63 s |
| `mint-prepare / prepare` | `08:20:48` -> `08:21:23` | 35 s |
| `mint-publish / publish` | `08:21:26` -> `08:22:52` | **86 s** |
| `verdict / admission-check` (parallel to mint) | `08:21:24` -> `08:22:01` | 37 s |
| `admission-check` (final context) | `08:22:54` -> `08:22:57` | 3 s |

**Binding predecessor of the final context in this cycle is `mint-publish`**: it completes at
`08:22:52`, **51 s later** than `verdict / admission-check` (`08:22:01`). The final context starts
2 s after `mint-publish`. S2 exists to remove exactly this dependency (section 4.4).

### 3.2 `publication-integrity` run `45964331956`, `08:15:56` -> `08:20:14` (258 s)

| job | window (UTC) | span |
|---|---|---|
| `license-scan-shards (0)` | `08:15:58` -> `08:18:26` | 148 s |
| `license-scan-shards (1)` | `08:15:58` -> `08:18:22` | 144 s |
| `license-scan-shards (2)` | `08:15:58` -> `08:18:45` | 167 s |
| `license-scan-shards (3)` (straggler) | `08:15:58` -> `08:19:37` | **219 s** |
| `license-scan-shards (4)` | `08:15:58` -> `08:18:45` | 167 s |
| `license-scan` (aggregate) | `08:19:39` -> `08:19:53` | 14 s |
| `publication-integrity` (final context) | `08:19:55` -> `08:20:14` | 19 s |

S1 is visibly in effect: five shards instead of three, and the wall drops from 356 s (cycle 1) to
**258 s**. The spread is still unbalanced - 144 to 219 s - but the straggler is 219 s, not 293 s.

### 3.3 `axiom-operational-slice` run `45964332053`, `08:15:56` -> `08:20:40` (284 s)

| job | window (UTC) | span |
|---|---|---|
| `axiom-operational-slice` | `08:15:58` -> `08:18:06` | 128 s |
| `readiness-verdict` | `08:18:08` -> `08:20:40` | 152 s |

Still two sequential jobs; the shape did not change in this cycle.

---

## 4. Cycle 3 - S1 + S2, warm: 400 s

Group commit `f21e9ec1` (PR #528, docs-only), window opens `2026-11-27T08:54:20Z`. Both changes are
in the tree and the caches were repopulated before the cycle (section 5), so this is the cycle in
which S2's effect is visible if it has one.

### 4.1 `admission-gate` run `45969305727`, `08:54:20` -> `09:01:00` (400 s)

| job | window (UTC) | span | vs cycle 1 | vs cycle 2 |
|---|---|---|---|---|
| `attest / build-base-artifacts` | `08:54:23` -> `08:55:30` | 67 s | -11 s | 0 s |
| `attest / go-critical-lane (1)` (slower lane, on chain) | `08:55:32` -> `08:58:07` | **155 s** | **+38 s** | +3 s |
| `attest / go-critical-lane (0)` | `08:55:32` -> `08:57:37` | 125 s | +8 s | +12 s |
| `attest / admission-independents` | `08:55:32` -> `08:57:04` | 92 s | +8 s | -4 s |
| `attest / admission-check` | `08:58:08` -> `08:59:14` | 66 s | +1 s | +3 s |
| `mint-prepare / prepare` | `08:59:16` -> `08:59:49` | 33 s | **+13 s** | -2 s |
| `mint-publish / publish` | `08:59:51` -> `09:00:40` | **49 s** | **-20 s** | **-37 s** |
| `verdict / admission-check` (parallel to mint) | `08:59:52` -> `09:00:54` | 62 s | **+25 s** | **+25 s** |
| `admission-check` (final context) | `09:00:56` -> `09:00:59` | 3 s | -2 s | 0 s |

**The binding predecessor inverted in this cycle.** The final context now waits on
`verdict / admission-check`, which completes at `09:00:54`; `mint-publish` completes at `09:00:40`,
so at the point of consumption it carries **14 s of slack**. In cycle 2 that relation was reversed
and `mint-publish` was the binder by 51 s. That is the structural change S2 was aimed at, and it is
observed here - but see section 8 for why it did not produce a shorter tail.

**Current binding path** (the `needs` chain that determines this cycle's tail):

```
build-base-artifacts 67 s -> go-critical-lane (1) 155 s -> attest/admission-check 66 s
  -> mint-prepare 33 s -> verdict/admission-check 62 s -> admission-check (final) 3 s
```

### 4.2 `publication-integrity` run `45969305538`, `08:54:20` -> `08:58:47` (267 s)

| job | window (UTC) | span |
|---|---|---|
| `license-scan-shards (0)` (straggler) | `08:54:22` -> `08:58:07` | **225 s** |
| `license-scan-shards (1)` | `08:54:23` -> `08:58:00` | 217 s |
| `license-scan-shards (2)` | `08:54:22` -> `08:57:05` | 163 s |
| `license-scan-shards (3)` | `08:54:22` -> `08:56:51` | 149 s |
| `license-scan-shards (4)` | `08:54:23` -> `08:56:38` | 135 s |
| `license-scan` (aggregate) | `08:58:09` -> `08:58:25` | 16 s |
| `publication-integrity` (final context) | `08:58:27` -> `08:58:46` | 19 s |

The verdict string from this run's log, quoted verbatim:

```
publication_license_eval: PASS (files=7605 licenseDetections=72 copyrightDetections=46)
```

**PI is no longer anywhere near the tail.** Its wall is 267 s against the 400 s admission tail -
**133 s of margin** in this cycle, and 163 s against cycle 2's 421 s tail. Against cycle 1's 12 s
margin (368 vs 356) that is a change of an order of magnitude. Per the L-W rule this record already
cites (`docs/spec/ci_admission_budget_contract.md` section 3), a context that is not the slowest
recovers **0 s** of wall whatever is saved inside it. S1's 89 s of PI wall reduction (356 -> 267 s)
is therefore real internal work that is **not currently payable**, exactly as
`merge_group_critical_path_2026-11-27.md` section 6 predicted.

### 4.3 `axiom-operational-slice` run `45969305608`, `08:54:20` -> `08:59:09` (289 s)

| job | window (UTC) | span |
|---|---|---|
| `axiom-operational-slice` | `08:54:23` -> `08:56:46` | 143 s |
| `readiness-verdict` | `08:56:48` -> `08:59:09` | 141 s |

Still two sequential jobs, and still well off the tail (111 s of margin).

### 4.4 S2's application evidence in the run log

Quoted from run `45969305727`, job `mint-publish / publish`. Log text is reproduced verbatim with
its typographic dash rendered as ASCII `-`:

```
AXIOM_CACHE_A_PINS: skip-a-restore - native toolchain deliberately not provisioned (B supply verified); asserting z3/jq only
AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=<B> primary-key=<B> matched-key=<B>
```

That job has **no `AXIOM_CACHE_A_RESTORE` line at all** - the A restore step did not run, which is
what `skip-a-restore` means. Counted over the whole run: `skip-a-restore: true` appears **once** (in
this job) and `skip-a-restore: false` appears **seven** times (`attest / build-base-artifacts`,
`attest / go-critical-lane (0)`, `attest / go-critical-lane (1)`, `attest / admission-independents`,
`gateway / ci-bootstrap`, `attest / admission-check`, `mint-prepare / prepare`).

The `attest / *` jobs, by contrast, did **both** restores exactly, e.g. from
`attest / build-base-artifacts`:

```
AXIOM_CACHE_A_RESTORE: exact-hit=true requested-key=<A> primary-key=<A> matched-key=<A>
AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=<B> primary-key=<B> matched-key=<B>
```

### 4.5 One observation, cause not determined

`mint-prepare / prepare` in the same run requested a **different** B key from every other job:

```
Cache not found for input keys: <B-alt>
AXIOM_CACHE_B_RESTORE: exact-hit= requested-key=<B-alt> primary-key=<B-alt> matched-key=
```

Note the shape: `<B>` and `<B-alt>` are byte-identical up to and including their `...e692` segment
and diverge only in the final 32 hex characters - the `recipe_hash` + `a_fp` suffix that `b_key`
appends to the B identity (`.github/actions/setup-axiom-toolchain/action.yml:373`). Every job
except `mint-prepare / prepare` requests `<B>`; this job requests `<B-alt>`. The restore is a
**miss** (empty `exact-hit`). The span of that job across the three cycles is 20 s (cycle 1) ->
35 s (cycle 2) -> 33 s (cycle 3).

**The cause is not determined here.** What is recorded is the observation: a B-key miss in
`mint-prepare` on both cycles 2 and 3, and a `mint-prepare` span above baseline in both. Whether the
key divergence is deliberate (a different B identity for the prepare job) or a defect, and whether
it is responsible for the span delta, is **not established by this record**.

---

## 5. Cold-cycle accounting - where S2's rotation cost was paid

S2 changed `.github/actions/setup-axiom-toolchain/action.yml` (67 insertions / 10 deletions between
`a6805fc4` and `c3433cd6`), which **rotated the A/B cache keys once**. A rotation necessarily costs
a cold cycle somewhere. This section records where that cost fell, so it is not attributed to the
steady-state numbers in sections 3 and 4.

### 5.1 The push run off the queue path - `45966298981`

`event=push`, head `c3433cd6`, `08:31:11` -> `08:41:27Z`. This run is **not** a merge_group cycle; it
is the main push.

| job | window (UTC) | span |
|---|---|---|
| `axiom-operational-slice` | `08:31:14` -> `08:37:03` | 349 s |
| `readiness-verdict` | `08:37:05` -> `08:41:26` | 261 s |

The slice job paid the rotation:

```
AXIOM_CACHE_A_RESTORE: DISCARDED - non-exact restore (exact-hit=); native install runs (fail-closed: cache is acceleration, never evidence)
AXIOM_CACHE_A_SAVE: authority=true scope=full exact-hit=
```

with `Cache not found` lines naming both the A key and the B key, earlier in the same job. That job
is the **save authority** for the new A key (`authority=true scope=full`).

Then `readiness-verdict`, in the same run, already found A exact:

```
AXIOM_CACHE_A_RESTORE: exact-hit=true requested-key=<A> matched-key=<A>
AXIOM_CACHE_B_RESTORE: exact-hit= requested-key=<B> matched-key=
```

So A was warm within the same push run while **B was still a miss**. **The rotation cost was paid
off the merge-queue path**, which is why cycles 2 and 3 are not cold.

### 5.2 Cache publisher runs

`ci-cache-publisher.yml` is a `workflow_run` workflow. Two runs on head `c3433cd6`:

| run | window (UTC) | jobs | conclusion |
|---|---|---|---|
| `45968914880` | `08:51:21` -> `08:52:14` | `publish` 23 s, `seed-toolchain` 49 s | success |
| `45970194565` | `09:01:03` -> `09:02:06` | `publish` 28 s, `seed-toolchain` 60 s | success |

**Timing fact, stated as an observation.** At `08:31Z` the B key
`axiom-b-be2eda56...-...d4e29e6778...` was a `Cache not found` miss (`45966298981`). At `08:54Z` the
same key was an `exact-hit=true` in the cycle 3 gate run (`45969305727`, section 4.4). Between those
two observations, exactly **one** `ci-cache-publisher` run fired: `45968914880` at `08:51:21Z`. That
is consistent with the publisher being the **save authority for B** at that requested key.

It is **not separately proven here.** The publisher's own job log was not inspected for a save
marker naming this key - only its run window, job spans, and conclusion were read. The statement
this record supports is the weaker one: the timing is compatible with the publisher having produced
the B entry, and no other publisher run exists in the interval.

---

## 6. App main-venue check-suite, by landing mode

Observed `2026-11-27T09:07:33Z` via `GET /commits/{sha}/check-suites?app_id=5795152`, and
**re-observed for this record** (section 10 gives the command). The re-observation reproduces both
columns exactly, including `created_at == updated_at` on every bypass row.

### 6.1 Queue landings - `completed` / `success`

| merge SHA | PR | suite created | suite updated | status | conclusion |
|---|---|---|---|---|---|
| `86a8e9ed` | #523 | `06:15:03` | `06:21:09` | `completed` | `success` |
| `e3087364` | #524 | `06:42:27` | `06:50:06` | `completed` | `success` |
| `6444c116` | (queue) | `06:48:46` | `06:55:17` | `completed` | `success` |
| `dd1ddb93` | #527 | `08:15:55` | `08:23:01` | `completed` | `success` |
| `f21e9ec1` | #528 | `08:54:19` | `09:01:04` | `completed` | `success` |

### 6.2 Bypass landings (MUST-T2 rotation) - `queued`, `conclusion` null, never updated

| merge SHA | PR | suite created | suite updated | status | conclusion |
|---|---|---|---|---|---|
| `8b35a06d` | #521 | `06:10:35` | `06:10:35` | `queued` | null |
| `53359b1e` | #526 | `07:45:38` | `07:45:38` | `queued` | null |
| `c3433cd6` | #525 | `08:31:11` | `08:31:11` | `queued` | null |

**The split is by landing mode, and it is exact in this sample: 5 queue landings completed
`success`, 3 bypass landings stuck `queued` with a null conclusion and an `updated_at` identical to
`created_at`.** The pending state is a property of the **bypass** path, not of "every landing on
this repository". Section 7 of `docs/evidence/rule_suite_bypass_5404140486_2026-11-27.md` stated the
broader generalisation; it is corrected in the same change against this table.

---

## 7. Class A - correctness: the three suites, run on the measured tree

Executed on the worktree at `f21e9ec1` (= cycle 3's tree) with
`nim c -r --hints:off --warnings:off <path>`. Exit codes and result lines below are quoted from the
run logs, not from any prior record.

| test | exit | `[OK]` | `[FAILED]` | `[SKIPPED]` |
|---|---|---|---|---|
| `tests/ci/test_admission_venue_split.nim` | **1** | 20 | **2** | 1 |
| `tests/ci/test_setup_toolchain_skip_a_restore.nim` | **0** | 10 | 0 | 0 |
| `tests/ci/test_publication_shard_merge.nim` | **0** | 10 | 0 | 0 |

### 7.1 `test_admission_venue_split.nim` - 2 FAILED on `main`

```
  [FAILED] every slice-scoped step keeps the landing conjunct (both files)
    tests/ci/test_admission_venue_split.nim(302, 34): Check failed: s.guard.contains(Landing)
    tests/ci/test_admission_venue_split.nim(302, 34): Check failed: s.guard.contains(Landing)
  [FAILED] landing-gated guard counts are exact (34 admission + 16 mint)
    tests/ci/test_admission_venue_split.nim(344, 21): Check failed: nAdmission == 34
    nAdmission was 35
```

plus one `[SKIPPED]`:

```
  [SKIPPED] upload/download artifact names = exact freeze + sanctioned additions since ci-frozen-2026-10-09-venue-split
  [freeze-tag-missing] ci-frozen-2026-10-09-venue-split - freeze comparison SKIPPED.
```

**Cause, determined: a stale pin in the test, not a defect in the workflow.** The two failures the
first check reports are both steps in `.github/workflows/admission-check.yml` that carry a `scope_`
conjunct without the landing conjunct:

```
- name: "[check] [SL-20] Repository surface admission (B-built guard, base policy x changed paths)"
  if: inputs.stage == 'attest' && steps.slice-engine.outputs.scope_sl20 == 'true'
```
```
- name: "[check] [SL-21] Producer closure admission (B policy x G producer tuples)"
  if: inputs.stage == 'attest' && steps.slice-engine.outputs.scope_sl21 == 'true'
```

Both are **deliberately venue-ungated** - they are meant to run in PR preflight as well as in
landing, so that preflight produces their judgement - but the test's `UngatedByDesign` exception
list (`tests/ci/test_admission_venue_split.nim:294`) names only
`[check] Re-derive admission identity` and `(P0) Publish activation guard`. The two SL steps are not
in it. Independently, the landing-gate count pin is 34 while the tree measures **35** - one short,
not two.

**Attribution: not caused by today's landings.** The blob identity of both files is unchanged across
the whole day:

| commit | `admission-check.yml` blob | `test_admission_venue_split.nim` blob |
|---|---|---|
| `f1852b8b` | `433be3c34c51` | `68dad64a5deb` |
| `a6805fc4` | `433be3c34c51` | `68dad64a5deb` |
| `dd1ddb93` | `433be3c34c51` | `68dad64a5deb` |
| `c3433cd6` | `433be3c34c51` | `68dad64a5deb` |
| `f21e9ec1` | `433be3c34c51` | `68dad64a5deb` |

Byte-identical at every commit, so the failure is **pre-existing** and independent of S1 and S2. The
same two failures were observed on `main` at `c3433cd6` (S2's landing) before this record, and are
reproduced here at `f21e9ec1`.

**Is it enforced in CI?** The test is wired only into `make test-unit` (`Makefile:1592`). Whether a
required CI lane runs `test-unit` is **not established by this record** - it was not checked. The
suite is red on `main` regardless, and this change does not fix it.

**Not fixed here.** The repair is a test re-pin (add the two SL steps to `UngatedByDesign`, bring the
admission count pin to 35), following the `b1659ef16` precedent that this test's own comments cite
as the retroactive-correction pattern. It is a separate change with its own review; see section 11.

### 7.2 `test_setup_toolchain_skip_a_restore.nim` - 10 / 10 on `main`

Exit 0. All ten lines, including the one that pins S2's caller contract:

```
  [OK] input exists with default 'false' (existing callers unchanged)
  [OK] the input never enters the keygen step (key formula unchanged)
  [OK] keygen still derives keys from script_hash and a_fp -> b_key
  [OK] A-restore is gated on the input
  [OK] every step that reads a-restore.cache-hit is gated too
  [OK] native installers are suppressed only behind a verified B supply
  [OK] A-layer save authority is never granted on a skipped restore
  [OK] pins verify asserts z3/jq unconditionally and mirrors the B witness
  [OK] jq/z3 install steps are NOT gated (supply on every path)
  [OK] mint-publish sets skip-a-restore='true' without changing scope
```

### 7.3 `test_publication_shard_merge.nim` - 10 / 10 on `main`

Exit 0. All ten lines:

```
  [OK] valid five-shard set PASSES (dead-gate guard)
  [OK] one shard report missing FAILS with the count diagnostic
  [OK] zero shard reports FAILS with a diagnostic (no silent die)
  [OK] the same file in two shard reports FAILS (duplicate guard fires)
  [OK] a tracked file in no shard report FAILS the set comparison
  [OK] valid JSON with one file entry dropped FAILS (set, not count)
  [OK] directory entries shared by every shard PASS (dedup is legitimate)
  [OK] the three shard-count sites agree (currently 5)
  [OK] a mutated copy (awk n=4) is reported as drift
  [OK] a mutated copy (count assertion -eq 4) is reported as drift
```

This suite is green and still asserts the fail-closed shape S1 depends on: a missing shard fails, a
duplicate fails, and the three count sites must agree.

---

## 8. Judgment, per class

### 8.1 Class A (correctness) - **holds**

The evidence for Class A, and only this evidence, is:

- **S2 is applied, and observed applying.** Section 4.4: `skip-a-restore: true` on exactly one job
  (`mint-publish / publish`), that job has no A-restore line, and the seven other consuming jobs run
  both restores with `skip-a-restore: false`. That is declared == executed for S2's contract, at the
  granularity of the run log.
- **S2's safety properties are pinned by a green suite.** Section 7.2, 10 / 10 at `main`, including
  `native installers are suppressed only behind a verified B supply` and
  `A-layer save authority is never granted on a skipped restore` - the two properties whose violation
  would make the skip unsafe rather than fast.
- **S1's contract is pinned by a green suite.** Section 7.3, 10 / 10 at `main`, including the
  fail-closed cases.
- **The ruleset was restored and the bypass landings were recorded.** PR #524/#527/#528 each record
  the rotation and the restore; section 6.1 shows all five queue landings since with a `completed`
  / `success` App suite, which is consistent with a live, enforcing ruleset.
- **One suite is red on `main`, and it is reported as red.** Section 7.1. It is attributed by blob
  identity to a pre-existing stale pin, not to S1 or S2. **This record does not claim `main`'s test
  tree is green**, because it is not.

The red suite is a Class A finding in the negative: it is not a S1/S2 failure, and it is not waved
away. It is disclosed here and carried as a follow-up (section 11, item 1).

### 8.2 Class B (speed) - **target not met / not demonstrated**

The session contract for these two changes is: **merge_group wall-clock median `392 s` -> `<= 345 s`**.

The measured warm sample with both changes is **400 s** (section 4.1). That is:

- **55 s above** the 345 s target;
- **8 s above** the 392 s baseline median it was supposed to beat.

**Therefore Class B is not met.** One warm sample also cannot demonstrate a median at all, so the
stronger statement is that the target is **not demonstrated** as well as not met. Either reading
gives the same verdict.

What did change structurally is recorded separately, because it is fact and it is the mechanism the
next attempt would build on:

| property | cycle 1 (baseline) | cycle 2 (S1) | cycle 3 (S1+S2) |
|---|---|---|---|
| PI tail margin (tail - PI wall) | 12 s | 163 s | 133 s |
| `mint-publish` vs its consumer | binder (0 s slack) | binder, 51 s late | **14 s slack** |
| finisher of the mount chain | `mint-publish` 69 s | `mint-publish` 86 s | `verdict / admission-check` 62 s |

- **PI has left the critical path.** 356 s -> 258 s -> 267 s against tails of 368 / 421 / 400 s. It
  is not the binder in any of the three cycles.
- **`mint-publish` has left the critical path.** It was the binding predecessor in cycles 1 and 2
  and now finishes 14 s before its consumer needs it.
- **Neither exit shortened the tail**, because each job was replaced as binder by something else.
  The current binder set is `go-critical-lane (1)` at 155 s and `verdict / admission-check` at 62 s.

**And the offsets are the same size as the savings.** Jobs that were not targets moved up:

| job | cycle 1 | cycle 2 | cycle 3 | delta (c1 -> c3) |
|---|---|---|---|---|
| `attest / go-critical-lane (1)` | 117 s | 152 s | 155 s | **+38 s** |
| `mint-prepare / prepare` | 20 s | 35 s | 33 s | **+13 s** |
| `verdict / admission-check` | 37 s | 37 s | 62 s | **+25 s** |
| `mint-publish / publish` | 69 s | 86 s | 49 s | -20 s |
| `publication-integrity` (wall) | 356 s | 258 s | 267 s | -89 s |

The +38 s on `go-critical-lane (1)` alone is nearly twice the -20 s S2 bought on `mint-publish`.
**The cause of these increases is not determined.** They are within the range host variance and
runner assignment can produce, and this record has no controlled sample that separates variance from
regression. What can be said without speculation is the arithmetic: **the observed savings and the
observed increases are of the same magnitude, so the net is inside the noise this lane already
shows.**

**A correction, added with sample 2 (section 13.2).** The `go-critical-lane (1)` increase is now
**explained**, and it was not variance: cycle 3 **executed** a fresh judgement where cycle 1 had
**reused** a record, because S2's one-line `Makefile` change moved the judgement key. Sample 2
reused again and the lane fell back to 105 s - 12 s below cycle 1's 117 s. The +38 s was a
one-time cost of S2's own landing. Read the cycle-3 column above with that in mind: for this job it
compares a reuse cycle against a judgement cycle, not two steady states. The `mint-prepare` and
`verdict` increases in the same table remain unattributed.

`mint-prepare`'s increase has a recorded companion observation (section 4.5): a B-key miss on both
cycles 2 and 3. That is an observation, not an attribution.

---

## 9. Honest limits

- **Not a controlled A/B.** The three cycles are at three different trees, on one host class, on one
  day. S1 and S2 are not isolated from each other, from the docs-only landing in cycle 3, or from
  ordinary variance. The comparison is a before/after, not an experiment.
- **Two warm samples, still no median.** Cycle 3 is one cycle and sample 2 (section 13) is a second.
  The 392 s figure they are compared against is a session-recorded median of 11 candidates; a median
  of two is not a median. No p50, p90, or confidence interval is claimed.
- **Sample 3 is the next cycle's own merge_group run.** Sample 2 (section 13) is read here because it
  is a prior landing; sample 3 is the merge_group run of the PR that carried section 13, and was
  deliberately not in that revision, because a document cannot quote the run that created it.
  Section 14 now measures it from the run record; the run that creates section 14 is **sample 4** and
  remains a follow-up read of the same kind.
- **Not measured**: queue wait before each window opens (out of the run record), the internal
  scheduling of the merge group, and per-step costs inside each job (step spans are not edge costs
  under the metric contract, so they are used here only to locate the tail).
- **Second-granularity timestamps.** GitHub records whole seconds; a 3 s job (final
  `admission-check`) has +-1 s of quantization. No conclusion here depends on a sub-5 s difference -
  the smallest delta the judgment uses is 8 s.
- **The `mint-prepare` B-key divergence (section 4.5) is unexplained.** It is recorded as an
  observation. A document that later attributes a `mint-prepare` regression to a specific cause must
  not cite this record as having established one.
- **The App check-suite sample is 8 landings on one day.** It is enough to show that the split
  follows landing mode rather than being uniform, which is all section 6 claims. It is not a claim
  about the App's behaviour on any other day.

---

## 10. Reproduction

Run records (native `gh`, GET-only):

```
gh run view 45940366569 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45940366345 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45940366417 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45964332106 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45964331956 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45964332053 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45969305727 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45969305538 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45969305608 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45976958813 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45976958350 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
gh run view 45976958567 -R Archright/Axiom --json name,headSha,createdAt,updatedAt,jobs
```

Sample 2's lane reuse (section 13.2) - the REUSED/EXECUTED basis per lane job, both cycles:

```
for j in 140431436082 140406021566 140313449701; do
  gh api "repos/Archright/Axiom/actions/jobs/$j/logs" \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
    | grep -E 'AXIOM_JUDGMENT_CAS \[|PASS .* EXECUTED [0-9]+/'
done
```

The judgement closure digests that make the reuse attributable (section 13.2):

```
gh api "repos/Archright/Axiom/actions/jobs/140431436082/logs" \
  | sed -e 's/\x1b\[[0-9;]*m//g' \
  | grep -oE '(overlay_manifest_digest|TOOLCHAIN_DIGEST)=?[^ ]{0,20}'
git diff --name-only f21e9ec1 87c480f4 -- Makefile config.nims tests/config.nims config/effects.nims nimble.lock
git diff --name-only dd1ddb93 f21e9ec1 -- Makefile config.nims tests/config.nims config/effects.nims nimble.lock
```

Job spans only, per run:

```
gh api repos/Archright/Axiom/actions/runs/45969305727/jobs --paginate \
  --jq '.jobs[] | "\(.name) \(.started_at) -> \(.completed_at) \(.conclusion)"'
```

Cold-cycle accounting (section 5):

```
gh run view 45966298981 -R Archright/Axiom --json name,event,headSha,createdAt,updatedAt,conclusion
gh api "repos/Archright/Axiom/actions/runs/45966298981/jobs?per_page=100" \
  --jq '.jobs[] | "\(.name) \(.started_at) -> \(.completed_at)"'
gh api "repos/Archright/Axiom/actions/runs/45968914880/jobs?per_page=100" --jq '.jobs[].name'
gh api "repos/Archright/Axiom/actions/runs/45970194565/jobs?per_page=100" --jq '.jobs[].name'
```

Cache markers (sections 4.4, 4.5, 5.1) - download the run log and strip ANSI:

```
gh run view 45969305727 -R Archright/Axiom --log \
  | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
  | grep -E "skip-a-restore: '|AXIOM_CACHE_[AB]_RESTORE: |Cache not found|AXIOM_CACHE_A_PINS"
gh run view 45966298981 -R Archright/Axiom --log \
  | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
  | grep -E "AXIOM_CACHE_[AB]_(RESTORE|SAVE): |Cache not found"
```

PI verdict string (section 4.2):

```
gh run view 45969305538 -R Archright/Axiom --log \
  | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep publication_license_eval
```

App main-venue check-suites (section 6):

```
for sha in 86a8e9ed e3087364 6444c116 dd1ddb93 f21e9ec1 8b35a06d 53359b1e c3433cd6; do
  full=$(gh api "repos/Archright/Axiom/commits/$sha" --jq .sha)
  gh api "repos/Archright/Axiom/commits/$full/check-suites?app_id=5795152" \
    --jq '.check_suites[] | "\(.status)|\(.conclusion)|\(.created_at)|\(.updated_at)"'
done
```

Class A suites (section 7), on the measured tree:

```
nim c -r --hints:off --warnings:off tests/ci/test_admission_venue_split.nim
nim c -r --hints:off --warnings:off tests/ci/test_setup_toolchain_skip_a_restore.nim
nim c -r --hints:off --warnings:off tests/ci/test_publication_shard_merge.nim
```

Blob identity (section 7.1, requires WSL git and the `rev:path` form):

```
for c in f1852b8b a6805fc4 dd1ddb93 c3433cd6 f21e9ec1; do
  echo "$c $(git rev-parse $c:.github/workflows/admission-check.yml) $(git rev-parse $c:tests/ci/test_admission_venue_split.nim)"
done
```

---

## 11. Follow-ups, each with its trigger

| # | item | class | completion criterion | trigger / precondition |
|---|---|---|---|---|
| 1 | Re-pin `tests/ci/test_admission_venue_split.nim`: add `[check] [SL-20] ...` and `[check] [SL-21] ...` to `UngatedByDesign`, bring the admission count pin to 35 | **A** (correctness) | the suite exits 0 on `main`; the count pin equals the measured count | any time; wall-clock **0 s**; `b1659ef16` precedent. Independent of S1/S2 (section 7.1) |
| 2 | Determine whether the `mint-prepare` B-key divergence (section 4.5) is intentional | **A** (correctness) | declared == executed is stated for that job's B identity, either by fixing the key or by documenting the second identity | before any `mint-prepare` span work; a 13 s delta is currently unattributable |
| 3 | Make `go-critical-lane (1)`'s 155 s the next speed target | **B** (speed) | observed merge_group wall-clock drop on the tail | the growth question is **answered** (section 13.2): it was S2's one-time `Makefile` re-judgement, not variance, and the steady-state lane is 105 s. Target the 105 s steady-state span, not the 155 s judgement span |
| 4 | Re-appraise S2's 49 s result now that it is not the binder | **B** (speed) | observed tail drop | after item 3 lands; S2's gain is real but is currently absorbed by a slower neighbour |
| 5 | Collect a median over warm samples | **B** (speed) | a median over >= 3 warm cycles that is <= 345 s | **in progress** - sample 2 is 312 s (section 13), sample 3 is 346 s (section 14.1). Three warm samples (400 / 312 / 346) give a median of **346 s**, 1 s above the target, so the target is still undemonstrated. Sample 4 is this PR's own merge_group run (section 14.6) |

---

## 12. What this record does not assert

- It does **not** assert that `main`'s test tree is green. It is not (section 7.1).
- It does **not** assert that S1 or S2 improved merge_group wall-clock. They did not, on the samples
  available at the time of section 8 (see also section 13.5, which adds a below-target sample without
  converting it into a median).
- It does **not** assert that the `mint-prepare` or `verdict` increases are regressions. Their cause
  is not determined (section 8.2). The `go-critical-lane (1)` increase **is** attributed - to S2's
  one-time `Makefile` re-judgement, not to variance (section 13.2).
- It does **not** assert that the cache publisher saved the B key observed as a hit at `08:54Z`
  (section 5.2). It asserts only that the timing is compatible and that no other publisher run
  exists in the interval.
- It **creates no authority**. Nothing here is consumed by a gate, and no policy, workflow, ruleset,
  or pin is changed by it.

---

## 13. Sample #2 - steady state (the landing of this record's predecessor, `87c480f4`)

Section 9 promised a second warm sample read "from the run record after this PR lands". That sample
now exists, so it is recorded here rather than deferred again. It is the merge_group cycle of
`87c480f4` - the merge commit of PR #529, i.e. the landing of the previous revision of **this
document**. Window opens `2026-11-27T09:49:48Z`.

**What makes it a steady-state sample.** Its tree adds two files and changes one line, all under
`docs/evidence/`. It touches no source, no test, no golden fixture, no recipe surface and no
workflow. It is therefore the first cycle in this series whose diff cannot move any judgement input -
which is exactly why the reuse result in section 13.2 is measurable at all.

### 13.1 The three runs

| workflow | run | window (UTC) | wall |
|---|---|---|---|
| `admission-gate` | `45976958813` | `09:49:48` -> `09:55:00` | **312 s** |
| `publication-integrity` | `45976958350` | `09:49:48` -> `09:54:09` | 261 s |
| `axiom-operational-slice` | `45976958567` | `09:49:48` -> `09:54:34` | 286 s |

`admission-gate`, binding chain, with the cycle-3 column for comparison:

| job | window (UTC) | span | vs cycle 3 |
|---|---|---|---|
| `attest / build-base-artifacts` | `09:49:51` -> `09:50:46` | 55 s | -12 s |
| `gateway / select` | `09:50:20` -> `09:51:31` | 71 s | **+25 s** |
| `attest / admission-independents` | `09:50:48` -> `09:52:02` | 74 s | -18 s |
| `attest / go-critical-lane (1)` (slower lane, on chain) | `09:50:49` -> `09:52:34` | **105 s** | **-50 s** |
| `attest / go-critical-lane (0)` | `09:50:49` -> `09:52:30` | 101 s | -24 s |
| `attest / admission-check` | `09:52:36` -> `09:53:36` | 60 s | -6 s |
| `mint-prepare / prepare` | `09:53:39` -> `09:53:57` | 18 s | -15 s |
| `mint-publish / publish` | `09:54:00` -> `09:54:53` | **53 s** | +4 s |
| `verdict / admission-check` (parallel to mint) | `09:53:59` -> `09:54:52` | 53 s | -9 s |
| `admission-check` (final context) | `09:54:55` -> `09:55:00` | 5 s | +2 s |

`closure-deriver` ran 25 s (`09:49:51` -> `09:50:16`); the five gateway jobs that cycle 3 either ran
or skipped (`ci-bootstrap`, `gateway-shard`, `candidate-build-arm`, `gateway-identity-gate`,
`proof-reconcile`) are all `skipped` in this cycle. The reason is in the selection record: the
`gateway / select` job emitted `"ciBootstrap": false` with `"selectedWorkUnits": []`, because the
candidate diff is documentation only.

**Current binding path:**

```
build-base-artifacts 55 s -> go-critical-lane (1) 105 s -> attest/admission-check 60 s
  -> mint-prepare 18 s -> mint-publish 53 s -> admission-check (final) 5 s
```

That is 296 s of job spans plus 16 s of scheduling gaps = 312 s. `mint-publish` and
`verdict / admission-check` finish **1 s apart** (`09:54:53` and `09:54:52`), so the 14 s of slack
cycle 3 recorded has collapsed to 1 s and the final context again waits on `mint-publish`. At whole
second granularity these two are tied, not ordered; no conclusion below depends on which of them
"wins".

`publication-integrity` (261 s): shards `150 / 145 / 175 / 150 / 206 s`, aggregate 26 s, final 22 s.
Straggler is shard (4) at 206 s. PI margin to the admission tail is 51 s.

`axiom-operational-slice` (286 s): slice job 128 s (`09:49:50` -> `09:51:58`), `readiness-verdict`
152 s (`09:52:01` -> `09:54:33`). Margin to the admission tail is 26 s.

### 13.2 The lane job REUSED the cycle-3 record - this is the whole -50 s

This is the one structural difference between sample 2 and cycle 3, and it is visible in the logs.

Sample 2, job `attest / go-critical-lane (1)` (`140431436082`):

```
[admission-tests] SKIP - tests/unit/proof_integrity_test.nim (AXIOM_JUDGMENT_CAS basis=REUSED - record re-verified at plan time, re-verified again at attest; rootRecord provenance required)
[admission-tests] exec-record[proof_integrity] verdict=UNKNOWN basis=REUSED evidenceKey=05f84c0428e3 evidenceSha256=
[admission-tests] PASS - EXECUTED 0/0, REUSED(skip) 3 (lane=1: tests/unit/proof_integrity_test.nim tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim); every GO-critical judgment carries an outcome (EXECUTED or REUSED - never none)
```

Cycle 3, job `attest / go-critical-lane (1)` (`140406021566`):

```
AXIOM_JUDGMENT_CAS [proof_integrity] : EXECUTED - no record for the current closure (fresh judgment)
[admission-tests] exec-record[proof_integrity] verdict=PASS basis=EXECUTED evidenceKey=05f84c0428e3 evidenceSha256=9c08438f1342
[admission-tests] PASS - EXECUTED 3/3, REUSED(skip) 0 (lane=1: tests/unit/proof_integrity_test.nim tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim); every GO-critical judgment carries an outcome (EXECUTED or REUSED - never none)
```

Both lanes flipped, not just the on-chain one: lane (0) went from `EXECUTED 1/1` (125 s) to
`EXECUTED 0/0, REUSED(skip) 1` (101 s). The on-chain lane job span fell **155 s -> 105 s**, and that
-50 s is the largest single contributor to the **-88 s** by which the whole `admission-gate` wall fell
(400 s -> 312 s). Summed job spans on the binding path went 386 s -> 296 s, and the -90 s decomposes
exactly: lane -50, `mint-prepare` -15, `attest/admission-check` -6, `build-base-artifacts` -12, the
finisher swap `verdict` 62 s -> `mint-publish` 53 s -9, final context +2.

**The records are the same records.** The `evidenceKey` cycle 3 wrote (`05f84c0428e3`) is the
`evidenceKey` sample 2 read, per subject, for all three subjects (`05f84c0428e3`, `e71e28d5244b`,
`880e24cc66c5`). Reuse is not inferred from timings; it is the same key, read instead of written.

**Why cycle 3 had to judge and this cycle did not - determined, not hypothesised.** The working
hypothesis on entering this measurement was that the judgement key covers the executor surfaces
(`Makefile` / `config.nims` / `nimble.lock`), so S2's one-line Makefile change forced a one-time
re-judgement in `f21e9ec1` while `87c480f4` - touching none of those - reused it. The evidence
confirms that hypothesis on all three legs:

- **The source says so.** `src/verification/judgment_cas.nim` derives the key as
  `deriveJudgmentKey = H(canonical closure wire)`, and the closure wire includes component
  `recipe`, the chained digest over `JudgmentRecipePaths` - `Makefile`, `config.nims`,
  `tests/config.nims`, `config/effects.nims`, `nimble.lock` (`judgment_cas.nim:204`,
  `:786`, `:548`).
- **Only the recipe moved between cycle 2 and cycle 3.** `git diff --name-only dd1ddb93 f21e9ec1`
  over those five paths returns exactly one file: `Makefile` (S2's one-line change). Cycle 2's key
  was `a32f0e5357ba`; cycle 3's is `05f84c0428e3` - a different key, hence a fresh judgement.
- **Nothing in the closure moved between cycle 3 and sample 2.** The same diff over
  `f21e9ec1 87c480f4` returns empty, and the two digests that are printed into the log are
  byte-identical across both cycles: `overlay_manifest_digest=0aa6ea32cde6` (src + golden fixtures +
  the three test sources) and `TOOLCHAIN_DIGEST=adc187daa602`.

So the re-judgement was a **one-time cost of S2's own landing**, and it is not a recurring cost of
the steady state. A caveat belongs on the deduction: the proof is that every logged closure input is
identical except the recipe; a closure component that is neither logged nor in the five recipe paths
could in principle also have moved. Nothing in this record suggests one, and the key equality across
cycle 3 -> sample 2 is the direct observable.

Cycle 1 is a useful control: its lane also REUSED (`117 s`, keys `5eff89a06014` / `a783e09497` /
`2beebead50`). So reuse is the normal state of this lane, and cycles 2 and 3 - the two cycles that
landed code - are the exceptions. The 117 s baseline lane already had reuse in it.

### 13.3 `mint-publish`: S2 is still applied, and the restore is still skipped

Job `mint-publish / publish` (`140432904251`), step 4 `Restore trusted B supply`, ran
`09:54:10` -> `09:54:26` = **16 s** inside a 53 s job. Its log carries S2's skip on the A layer and
an exact B hit:

```
AXIOM_CACHE_A_PINS: skip-a-restore - native toolchain deliberately not provisioned (B supply verified); asserting z3/jq only
AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=<B> primary-key=<B> matched-key=<B>
```

with `skip-a-restore: true` as the step input, the A-restore action reported as
`outcome=skipped;conclusion=skipped;duration_ms=0`, and **no `AXIOM_CACHE_A_RESTORE` line anywhere in
that job** (count: 0). Across the whole `admission-gate` run, `skip-a-restore: true` appears once
(this job) and `skip-a-restore: false` appears **six** times (`attest / build-base-artifacts`,
`attest / admission-independents`, `attest / go-critical-lane (0)`, `attest / go-critical-lane (1)`,
`attest / admission-check`, `mint-prepare / prepare`).

Six, where section 4.4 counted seven in cycle 3, and the difference is explained rather than
unexplained: the seventh consumer was `gateway / ci-bootstrap`, which did not run in this cycle
(section 13.1, `ciBootstrap: false`).

### 13.4 Where the -56 s came from, and what it is not

| measure | value |
|---|---|
| cycle 1 baseline | 368 s |
| sample 2 | **312 s** |
| delta | **-56 s (-15.2%)** |
| session target | 345 s |
| sample 2 vs target | **-33 s (below target)** |

Attribution against the **cycle 1** baseline (that is what -56 s is measured from), job by job on the
binding path:

| component | cycle 1 | sample 2 | delta |
|---|---|---|---|
| `build-base-artifacts` | 78 s | 55 s | **-23 s** |
| `go-critical-lane (1)` | 117 s (REUSED) | 105 s (REUSED) | -12 s |
| `attest / admission-check` | 65 s | 60 s | -5 s |
| `mint-prepare / prepare` | 20 s | 18 s | -2 s |
| mint finisher (`mint-publish` in both) | 69 s | 53 s | **-16 s** |
| final `admission-check` | 5 s | 5 s | 0 s |

`build-base-artifacts` (-23 s) and `mint-publish` (-16 s) carry most of it. The table sums to **-58 s**
against a -56 s wall delta; the 2 s difference is scheduling gaps (14 s in cycle 1, 16 s here), not a
missing term. **The lane reuse does not appear in this table as a gain**, and that is the point:
cycle 1 already reused. Reuse is the steady state (section 13.2), so S2's one-time `Makefile`
re-judgement shows up as a cost in cycles 2 and 3, not as a saving in sample 2. Off the binding path,
`gateway / select` grew +25 s (46 -> 71 s) and `admission-independents` fell 18 s; neither moves the
wall, per the L-W rule section 4.2 cites.

Those residuals are the same phenomenon section 8.2 already recorded - in this lane, individual job
spans move by tens of seconds between cycles for reasons this record never controls for.

### 13.5 One steady-state sample is not a median - the target is still not demonstrated

312 s is 33 s below the 345 s target. **That does not meet the Class B contract**, and the reason is
arithmetic, not caution: the contract is written on a **median** (section 8.2: median `392 s` ->
`<= 345 s`), and the two warm samples now available are **400 s** and **312 s**. Their midpoint is
**356 s** - still **11 s above the target**. Two samples cannot produce a median that lands below
345 s at all; the mean has to. So sample 2 moves the estimate in the right direction and settles
nothing:

- n = 1 steady-state sample. No p50, p90, or interval is claimed (section 9 stands).
- The sample's -56 s **does not include a reuse gain** (section 13.4): cycle 1 reused too. What the
  sample 2 number does establish is that cycles 2 and 3 carried a one-time re-judgement cost that the
  steady state does not - so `400 s` overstates the steady-state tail, and `312 s` is a better point
  estimate of it, without being a median.
- It inherits every limit in section 9 - one host class, one day, no controlled A/B, second
  granularity.

### 13.6 Sample #3

Sample #3 is the merge_group cycle of the merge commit of the PR that carries this section. It is
deliberately not quoted here, for the reason section 9 gives: a document cannot observe the run that
creates it. It is read with section 10's commands against `gh pr view <n> --json mergeCommit`, then
`GET /actions/runs?event=merge_group&head_sha=<sha>`.

Three warm samples would permit a median of three in the sense the contract needs, but a three-sample
median of a variable quantity is still not a stable estimator; the honest threshold is that the
target number is reported alongside n every time it is compared.

**Added later.** That run now exists. It is `64c3edf0` (PR #530), it is measured in section 14, and
the median of three warm samples is 346 s - 1 s above the target, with the mechanism gains and the
variance-of-the-same-order caveat both stated there. The paragraph above is kept as written, as the
prediction it was.---

## 14. Sample #3 - the landing of `64c3edf0` (section 13's own cycle)

Section 13.6 promised this sample and left it unquoted, on the ground that a document cannot observe
the run that creates it. The promise is now payable: the PR that carried section 13 was **#530**, its
merge commit is `64c3edf0`, and the cycle that landing produced is measured here. Its gate window
opens `2026-11-27T10:38:30Z`; the PR merged at `10:44:43Z`, 27 s after the gate had finished.

**What makes it a comparable sample.** PR #530 changes one file - this document - with `+266 / -21`
lines, all under `docs/evidence/`. No source, test, golden fixture, workflow, `Makefile` or
`nimble.lock` byte moves, so the judgement recipe is sample 2's and the cycle is warm-and-reuse by
construction. Section 14.2 confirms that from the log rather than from the diff.

### 14.1 The three runs

| workflow | run | window (UTC) | wall |
|---|---|---|---|
| `admission-gate` | `45983808095` | `10:38:30` -> `10:44:16` | **346 s** |
| `publication-integrity` | `45983807567` | `10:38:29` -> `10:42:14` | 225 s |
| `axiom-operational-slice` | `45983807518` | `10:38:29` -> `10:43:49` | 320 s |

`admission-gate`, with the sample-2 column for comparison:

| job | window (UTC) | span | vs sample 2 |
|---|---|---|---|
| `closure-deriver` | `10:38:32` -> `10:39:04` | 32 s | +7 s |
| `attest / build-base-artifacts` | `10:38:32` -> `10:39:28` | 56 s | +1 s |
| `gateway / select` | `10:39:07` -> `10:40:09` | 62 s | -9 s |
| `attest / admission-independents` | `10:39:30` -> `10:40:42` | 72 s | -2 s |
| `attest / go-critical-lane (0)` | `10:39:30` -> `10:40:56` | 86 s | -15 s |
| `attest / go-critical-lane (1)` (slower lane, on chain) | `10:39:31` -> `10:41:17` | **106 s** | +1 s |
| `gateway / executed-jobs` | `10:40:18` -> `10:40:30` | 12 s | +8 s |
| `attest / admission-check` | `10:41:20` -> `10:42:40` | **80 s** | **+20 s** |
| `attest / go-critical-rollup` | `10:41:20` -> `10:41:24` | 4 s | +1 s |
| `mint-prepare / prepare` | `10:42:43` -> `10:43:15` | **32 s** | **+14 s** |
| `mint-publish / publish` | `10:43:18` -> `10:43:54` | 36 s | **-17 s** |
| `verdict / admission-check` (parallel to mint) | `10:43:18` -> `10:44:10` | **52 s** | -1 s |
| `admission-check` (final context) | `10:44:12` -> `10:44:16` | 4 s | -1 s |

`gateway / sl09-scope` ran 7 s. `gateway / ci-bootstrap`, `gateway / gateway-shard`,
`gateway / candidate-build-arm`, `gateway / gateway-identity-gate` and `gateway / proof-reconcile` are
`skipped`, the same selection sample 2 recorded (`ciBootstrap: false`, empty `selectedWorkUnits`).

**Current binding path:**

```
build-base-artifacts 56 s -> go-critical-lane (1) 106 s -> attest/admission-check 80 s
  -> mint-prepare 32 s -> verdict/admission-check 52 s -> admission-check (final) 4 s
```

That is 330 s of job spans plus 16 s of scheduling gaps = 346 s.

`publication-integrity` (225 s): shards `150 / 152 / 171 / 140 / 135 s`, aggregate 21 s, final 25 s.
Straggler is shard (2) at 171 s. PI margin to the admission tail is **121 s**.

`axiom-operational-slice` (320 s): slice job 146 s (`10:38:31` -> `10:40:57`), `readiness-verdict`
170 s (`10:40:58` -> `10:43:48`). Margin to the admission tail is 26 s.

### 14.2 The lane reused again

Job `attest / go-critical-lane (1)` (`140454596578`):

```
AXIOM_JUDGMENT_CAS [proof_integrity] : REUSED - record 05f84c0428e3 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)
[admission-tests] PASS - EXECUTED 0/0, REUSED(skip) 3 (lane=1: tests/unit/proof_integrity_test.nim tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim); every GO-critical judgment carries an outcome (EXECUTED or REUSED - never none)
```

Both lines carry a typographic dash (U+2014) in the log, reproduced as ASCII `-`. All three subjects
reused, at the keys sample 2 read (`05f84c0428e3`, `e71e28d5244b`, `880e24cc66c5` - section 13.2), and
lane (0) reused too (`EXECUTED 0/0, REUSED(skip) 1`, subject `s1a`, key `fb26806977ef`). This is the
second consecutive reuse and the third reuse in the series; cycles 2 and 3 remain the only cycles that
executed (section 13.2).

### 14.3 `mint-publish`: S2 still applied, and the B restore is now 8 s

Job `mint-publish / publish` (`140456409502`), step 4 `Restore trusted B supply`, ran
`10:43:22` -> `10:43:30` = **8 s** inside a 36 s job. The A layer was skipped again:

```
AXIOM_CACHE_A_PINS: skip-a-restore - native toolchain deliberately not provisioned (B supply verified); asserting z3/jq only
AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=<B> primary-key=<B> matched-key=<B>
```

with `skip-a-restore: true` as the step input and no `AXIOM_CACHE_A_RESTORE` line anywhere in that job
(count: 0). The step's arc across the series is the cleanest single mechanism reading in this record:
**42 s in cycle 1** (before S2, both restores run), **16 s in sample 2**, **8 s here**. The saving S2
bought on this step is real and it grew - and it buys no wall, because this job stopped being the
binder (section 14.4).

### 14.4 The tail binder is `verdict / admission-check` again

Sample 2's final context waited on `mint-publish`, which finished 1 s before `verdict` (section 13.1).
Sample 3 inverts that relation back: `mint-publish` completes `10:43:54`, `verdict / admission-check`
completes `10:44:10` - **16 s later** - and the final context starts 2 s after `verdict`. So the tail
binder this cycle is `verdict / admission-check` at 52 s, and `mint-publish` carries 16 s of slack at
the point of consumption, the structural position cycle 3 recorded (14 s).

| property | cycle 3 | sample 2 | sample 3 |
|---|---|---|---|
| PI margin to the admission tail | 133 s | 51 s | 121 s |
| finisher of the mount chain | `verdict` 62 s | `mint-publish` 53 s | **`verdict` 52 s** |
| `mint-publish` vs its consumer | 14 s slack | binder (1 s tie) | **16 s slack** |
| `admission-gate` wall | 400 s | 312 s | **346 s** |

### 14.5 Three warm samples: median 346 s, one second above the target

This is the first sample set that can produce the median the contract is written on (section 8.2:
median `392 s` -> `<= 345 s`).

| sample | tree | judgement | wall |
|---|---|---|---|
| cycle 3 | `f21e9ec1` | EXECUTED | 400 s |
| sample 2 | `87c480f4` | REUSED | 312 s |
| sample 3 | `64c3edf0` | REUSED | **346 s** |

**Median of three warm samples: 346 s. Target: 345 s. Class B is still not met**, by one second - and
the honest reading is narrower than either previous verdict:

- **On REUSED-only samples**, which is the steady state (section 13.2), the series is 312 / 346 s
  against a **single-sample REUSED baseline of 368 s** (cycle 1). Both samples are below that baseline:
  by 56 s and by 22 s.
- **The mechanism gains are proven.** `publication-integrity` is off the binding chain in every sample
  since cycle 2 (225-267 s against tails of 312-421 s, 121 s of margin here), and the `mint-publish`
  B-restore step went **42 s -> 8-16 s** (section 14.3). Those are structural and reproducible.
- **But run-to-run variance in steps nobody targeted is of the same order as part of the gain.** The
  chain spans went 296 s -> 330 s, and that +34 s is **exactly** two unmodified jobs:
  `attest / admission-check` **60 s -> 80 s** and `mint-prepare` **18 s -> 32 s** (+20 and +14), with
  every other on-chain job within +-1 s. Inside them the largest single term is the toolchain action
  step: 31 s -> 38 s in the former, 4 s -> 10 s in the latter. Neither job was a target of S1 or S2.
- **So the statement this record makes** is: the median over three warm samples is 346 s, 1 s above the
  target, with the mechanism gains proven and with variance of the same magnitude as part of them. The
  target is not claimed as met, and it is not claimed as missed for a determined cause.

Two observations belong with that, and neither is an attribution. First, `mint-prepare / prepare`'s B
restore is **again a miss** in this cycle (`Cache not found`, empty `exact-hit`), the shape section 4.5
recorded for cycles 2 and 3; the same miss is present in sample 2. Second, `attest / admission-check`
growing 20 s while `go-critical-lane (1)` moves +1 s is the opposite pattern from cycle 3's, where the
lane moved and this job did not - which is another way of saying that the movable cost in this lane is
not attached to a single job.

### 14.6 Sample #4

Sample #4 is the merge_group cycle of the merge commit of the PR that carries **this** section. It is
not quoted here, for the reason section 9 gives. It is read with section 10's commands against
`gh pr view <n> --json mergeCommit`, then `GET /actions/runs?event=merge_group&head_sha=<sha>`, and
the `[lane] evidenceId contract check` step span in each of the two lane jobs is read at the same
time - that span is the observable which says whether the in-progress probe speed-up, recorded as a
correction in the wall-budget record, has landed ahead of it.