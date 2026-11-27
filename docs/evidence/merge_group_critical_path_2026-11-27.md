# merge_group critical-path measurement - where the wall-clock is spent on main @ a6805fc4

> **Status**: measurement record (reporter). This document **creates no authority of any kind**: it
> changes no policy, workflow, ruleset, gate, or pin, and no gate consumes its values. The normative
> rules for admitting CI work stay with `docs/spec/ci_admission_budget_contract.md`; this record only
> preserves the per-run observations on which an admission decision can later be argued.
> **Created**: 2026-11-27
> **Measured commit**: `main` @ `a6805fc4`
> **Measured cycle**: merge_group run window opens `2026-11-27T04:30:44Z`
> **Observation method**: GET-only REST reads through native `gh` authentication (AGENTS.md section 2.4).
> No local timer, no instrumentation, no added workflow step. Every number below is a subtraction of two
> platform-recorded timestamps (`run_started_at`, `updated_at`, `started_at`, `completed_at`).
> **ASCII note**: the quotation in section 7 is reproduced word for word with its typographic dashes
> rendered as ASCII `-` on this page, so that the file stays 7-bit clean.

---

## 0. Purpose, and the two outcome classes that must not be mixed

**Scope.** Measure where merge_group wall-clock is spent on `main` @ `a6805fc4`, and separate two
outcome classes that are routinely conflated in CI-savings discussions:

- **Class A - correctness slices.** Wall-clock expectation: **0 s**. Completion is defined by
  *re-run determinism* (`run_attempt > 1` reproduces the attempt-1 artifact set) and by
  *declared == executed* (the thing the repository says it runs is the thing the run record shows it
  ran). A correctness slice is complete when those two properties are observed, **not** when a timer
  moves.
- **Class B - speed slices.** Completion is defined by an **observed merge_group wall-clock change**
  in the run records. A speed slice is complete only when a later cycle's tail shrinks; the code
  change alone is not completion.

**Judgment rule.** Each slice is judged only on the completion criterion of its own class. A
correctness slice that moves no timer is a **success**, not a weak result; a speed slice that ships
with no observed wall-clock delta is **not done**, even if every test is green. This document exists
because both failure modes were available at the same commit, for the same lane.

---

## 1. The measured cycle

All three runs below were created by the same merge-queue event at `2026-11-27T04:30:44Z`.

| workflow | run id | window (UTC) | wall | note |
|---|---|---|---|---|
| `admission-gate` | `45940366569` | `04:30:44` -> `04:36:52` | **368 s** | tail of the cycle |
| `publication-integrity` | `45940366345` | `04:30:44` -> `04:36:40` | **356 s** | second finisher, 12 s behind the tail |
| `axiom-operational-slice` | `45940366417` | `04:30:44` -> `04:35:41` | **297 s** (4:57) | contains `readiness-verdict` as a **sequential** job |

The other required contexts in the same event finished earlier: `debt-registry-gate` `04:31:58`,
`bsec-integrity` `04:31:54`, `observer-manifest-consistency` `04:31:52`, `generation-acceptance`
`04:31:07`, `probe-merge-queue` `04:30:56`. None of them is within 3 minutes of the tail, so none of
them is on the cycle's critical path today.

---

## 2. `admission-gate`: the 368 s tail, decomposed

Job spans on the admission chain (timestamps are job `started_at`/`completed_at`; "on chain" is the
`needs` path that determines the tail - `attest / admission-check` needs the lanes, **not**
`go-critical-rollup`, so the rollup is off-chain):

| job | on chain | window (UTC) | span | elapsed at completion (from `04:30:44`) |
|---|---|---|---|---|
| `attest / build-base-artifacts` | yes | `04:30:47` -> `04:32:05` | 78 s | 81 s |
| `attest / admission-independents` (parallel) | no | `04:32:06` -> `04:33:30` | 84 s | 166 s |
| `attest / go-critical-lane (1)` (parallel, slower) | yes | `04:32:07` -> `04:34:04` | **117 s** | 200 s |
| `attest / go-critical-rollup` | no | `04:34:07` -> `04:34:12` | 5 s | 208 s |
| `attest / admission-check` (attest) | yes | `04:34:06` -> `04:35:11` | 65 s | 267 s |
| `mint-prepare / prepare` | yes | `04:35:13` -> `04:35:33` | 20 s | 289 s |
| `mint-publish / publish` | yes | `04:35:35` -> `04:36:44` | **69 s** | 360 s |
| `admission-check` (final context) | yes | `04:36:47` -> `04:36:52` | 5 s | 368 s |

The chain - `build-base-artifacts`, the slower lane, `attest / admission-check`, `mint-prepare`,
`mint-publish`, the final context - sums to **354 s** of job spans (78 + 117 + 65 + 20 + 69 + 5).
The remaining **14 s is dispatch/queue latency across 6 gaps** (3 + 2 + 2 + 2 + 2 + 3), not work: the
run envelope is 368 s. The cost after `build-base-artifacts` is two long hops - `go-critical-lane (1)`
at 117 s and `attest / admission-check` at 65 s - then the mint pair (`prepare` 20 s + `publish` 69 s
= 89 s).
`mint-publish` is the single largest post-attest block; in this cycle it starts 2 s after
`mint-prepare` completes (`04:35:33` -> `04:35:35`), so its binding predecessor here is
`mint-prepare`, not the gateway (section 5).

Note on the overlap: `attest / admission-check` starts at `04:34:06`, one second before
`go-critical-rollup` starts (`04:34:07`), because it needs the lanes, not the rollup. Its 65 s
therefore overlaps the rollup's 5 s; the segment from the slower lane's end (`04:34:04`) to
attest completion (`04:35:11`) is 67 s, and the naive sum 5 + 65 = 70 s overcounts it by 3 s.

---

## 3. `publication-integrity`: the 356 s runner-up

| job | window (UTC) | span |
|---|---|---|
| `license-scan-shards (0)` | `04:30:46` -> `04:34:31` | 225 s |
| `license-scan-shards (1)` (slowest shard) | `04:30:46` -> `04:35:39` | **293 s** |
| `license-scan-shards (2)` | `04:30:46` -> `04:35:09` | 263 s |
| `license-scan` (aggregate, `needs` all shards) | `04:35:41` -> `04:36:14` | 33 s |
| `publication-integrity` (final context) | `04:36:15` -> `04:36:39` | 24 s |

The three shards are already parallel. Their spread is 225 / 263 / 293 s: the split is **not balanced**,
so the aggregate waits on the slowest shard, and shard (1)'s 293 s is 68 s above shard (0)'s 225 s.
The aggregate step is 33 s and the final context step is 24 s; neither is the lever.

**Preceding cycle, same day, for reference** - run `45931370303` (`02:57:52` -> `03:04:54`, 422 s):
`license-scan-shards (0)` spent 35 s in `[tool] scancode-toolkit 32.5.0 + pluggy 1.5.0 (venv, pinned)`
(`02:57:57` -> `02:58:32`) and 316 s in `[scan] license + copyright detection`
(`02:58:32` -> `03:03:48`); its aggregate `license-scan` job was 35 s. The scan work is the shard's
cost, and it is intrinsic to the shard's input slice - provisioning (35 s) is not the driver here.

---

## 4. `axiom-operational-slice` -> `readiness-verdict`: sequential, 297 s

Run `45940366417` holds two jobs in sequence:

| job | window (UTC) | span |
|---|---|---|
| `axiom-operational-slice` | `04:30:47` -> `04:33:11` | 144 s |
| `readiness-verdict` | `04:33:13` -> `04:35:41` | **148 s** (2:28) |

`readiness-verdict` starts 2 s after the operational slice completes; it is **sequential after** the
slice, not parallel to it. The workflow's tail is therefore the sum of the two hops, 297 s, and it
lands 71 s before the admission tail. Neither of its jobs is the cycle's critical path in this cycle.

---

## 5. Gateway lane: 54 s of slack at its consumer's binding point

| job | window (UTC) | span |
|---|---|---|
| `gateway / select` | `04:31:15` -> `04:33:28` | 133 s |
| `gateway / sl09-scope` | `04:31:16` -> `04:31:32` | 16 s |
| `gateway / ci-bootstrap` | `04:33:31` -> `04:34:34` | 63 s |
| `gateway / proof-reconcile` | `04:34:34` -> `04:34:34` | 0 s |
| `gateway / executed-jobs` (lane end) | `04:34:36` -> `04:34:39` | 3 s |

The gateway chain finished at **`04:34:39`**. `mint-publish` declares
`needs: [mint-prepare, gateway, anchor-resolve]`; in this cycle the gateway was satisfied at
`04:34:39` while `mint-prepare` completed at **`04:35:33`**, so the **binding predecessor was
`mint-prepare`**, and `mint-publish` started 2 s later at **`04:35:35`**. Measured slack on the
gateway is therefore **54 s** (`04:35:33` - `04:34:39`).

Consequence, measured rather than argued: **parallelizing `select` -> `ci-bootstrap` yields 0 s
today.** The pair is 133 s + 63 s serial, but removing it entirely still leaves the gateway finished
before `mint-prepare` completes, so no downstream start moves. This stays 0 s after the scancode
reduction of section 3, because that reduction shortens `publication-integrity`, which is not what
binds `mint-publish` either.

---

## 6. Critical-path arithmetic and the L-W consequence

`admission-gate` is the tail by **12 s** (`04:36:52` vs `04:36:40`). Per
`docs/spec/ci_admission_budget_contract.md` section 3, **L-W**: `T_admission` is bounded below by the
slowest required context, and work on a context that is not the slowest recovers
`min(internal saving, headroom)` - which is **0 whenever the lane is not the tail**. Applying the
contract's own definition, `recoverable = wall - max(lane after change, floor)`, with `wall = 368`:

- A change that shortens `publication-integrity` by any amount up to its 356 s wall leaves
  `max(356 - X, 368) = 368`. **Recovered wall-clock: 0 s** for every X that does not push it below
  the admission tail.
- The same holds for `axiom-operational-slice` (297 s) and for every gateway-lane change.

**Therefore the scancode shard split alone yields 0 s today.** It becomes payable only after the
admission tail drops **below 356 s** - that is, only once `publication-integrity` is the last
finisher. This is the same measurement the budget review recorded independently
(`docs/reports/ci_wall_budget_review_2026-11-26.md`: publication-integrity contributes 0 to the wall
because it is not the last finisher in any observed cycle).

Honest limit on the 12 s margin: the gap is **inside the runner-assignment noise this chain already
shows** (14 s of dispatch latency across 6 gaps in section 2). The tail identity is not a stable
property of the two workflows. In the immediately preceding cycle, run `45938733861` (`admission-gate`,
`04:14:03` -> `04:19:56`, 353 s) was beaten by run `45938733565` (`publication-integrity`,
`04:14:03` -> `04:20:38`, 395 s) by **42 s** - the order was reversed. Treat "admission-gate is the
tail" as a property **of this cycle**, not of the pipeline.

---

## 7. Pin drift in `admission-gate-v2.yml` - class A, wall-clock 0 s

`.github/workflows/admission-gate-v2.yml:650` pins the gateway callee at

```
uses: Archright/Axiom/.github/workflows/runner-pool-acceptance.yml@c021c33801455a481e05b75c396d95c84bbdc45d
```

`main`'s version of that callee is not that commit. Measured at `a6805fc4`:

```
git diff c021c33801455a481e05b75c396d95c84bbdc45d -- .github/workflows/runner-pool-acceptance.yml
 .github/workflows/runner-pool-acceptance.yml | 51 +++++++++++++++++++++++++---
 1 file changed, 46 insertions(+), 5 deletions(-)
```

**Composition of the 46/5** - counted line by line, not eyeballed: **9** `overwrite: true` additions on
`upload-artifact` steps + **1** changed step label + **36** added comment lines = 46. The 5 deletions are
**4** comment lines + the **1** old step label.

- The nine `overwrite: true` lines are the DEBT-CI#003 remedy (`severity: medium`, `status: closed`,
  `resolution: FIXED 2026-11-15`, `data/debt_registry.json`), each accompanied by a rationale comment
  block naming the artifact-collision quirk.
- The label change is `Load derived-closure sets (org gate artifact, soft)` ->
  `Load derived-closure sets (orchestrator artifact, soft)`.
- The four rewritten comment lines are the same org-gate -> orchestrator rename applied to prose.

Nothing else differs.

**What did not change** - checked by parsing both YAML documents and comparing fields, not by eye:

| surface | result |
|---|---|
| `on.workflow_call` (signature) | equal |
| job set | equal |
| per-job `needs` | equal |
| per-job `if` | equal |
| per-job `timeout-minutes` | equal |
| per-job `uses` / `with` / `secrets` | equal |
| `stepNamePattern` binding (`src/gate/slice_catalog.nim:52` - substring match) | still matches: `Load derived-closure sets` is a substring of the new label |

**No derived authority moved.** Checked, not assumed:

- `config/trusted_writer_set.json` `trustedAdmissionWorkflowSha` = `433be3c34c51cfc3fc6f8741009135cfa5906a03`,
  which is `git hash-object .github/workflows/admission-check.yml` at `a6805fc4` - the *pinned engine*,
  not this callee. `config/policy/epoch_manifest.json` `productionExecutionPin` holds the same value.
- `a_fp` = `sha256(a-key recipe)[:32]`, derived in `.github/actions/setup-axiom-toolchain/action.yml`
  from the toolchain action recipe; `B` keys are `axiom-b-<closure>-<recipe><a_fp>`. Neither reads a
  workflow `uses:` OID.
- Pin rotation machinery exists in the tree - `tools/ci/rotation_pin_anchor_check.nim`,
  `tools/ci/reanchor_pin.nim`, `tools/ci/golive_detect.sh` - but none of it observes this callee.
  `config/trusted_checker_closure.json` and `config/trusted_writer_set.json` contain no
  `runner-pool` / `admission-gate-v2` entry, and the TWS pin document's own keys are
  `trustedAdmissionWorkflowSha`, `trustedWriterWorkflow`, `pathSetDigest` - the closure covers the
  pinned engine, not the orchestrator's callee pins. **No check enforces declared == executed for
  this callee pin.**
- The callee's blob at the pinned commit is `319df914...`; at `main` it is `35cfc3c7...`.

**Anti-overclaim.** The `overwrite: true` lines are a correctness-class change and buy no time. To
state it exactly:

> `overwrite: true` prevents nothing at `run_attempt == 1` (no same-named artifact exists yet) - wall-clock 0 s. Its effect is re-run (`run_attempt > 1`) determinism and declared==executed only; no upload-side 409 conflict has ever been observed.

The claim that would be false, and is not made here: that this drift is a speed or safety regression
in production today. The pinned commit predates the DEBT-CI#003 remedy, so a **re-run** of the gateway
lane under the pin still carries the attempt-collision class the debt describes; that is a
`run_attempt > 1` property.

**Cost of closing it, measured:** `admission-gate-v2.yml` is a trust-surface path
(`config/policy/trust_surface_manifest.json:8`), and a change to it is refused by App `admission-check`
by design - the normal merge-queue route is structurally unavailable, as PR #517 recorded for the same
file. A pin rotation is therefore class A at **0 s of wall-clock**, bought at the price of a
break-glass landing. That trade is the reason it is a follow-up and not part of this record.

---

## 8. Follow-ups, each with its trigger

| # | item | class | completion criterion | trigger / precondition |
|---|---|---|---|---|
| 1 | Rotate the callee pin to a commit containing the DEBT-CI#003 remedy | **A** (correctness) | declared == executed observed; re-run determinism holds under the pin | any time; expected wall-clock **0 s**, cost is a trust-surface landing (section 7) |
| 2 | Reduce the attest/mint block (epoch axis) and re-shard the scancode weights | **B** (speed) | observed merge_group wall-clock drop on the tail | admission tail must first come under 300 s, and the scancode split only pays once the tail is below 356 s (section 6). The shard aggregator must stay **fail-closed**: shard count != expectation -> FAIL |
| 3 | Parallelize `select` -> `ci-bootstrap` | **B** (speed) | observed wall-clock drop | **trigger: the gateway-shard lane lengthens (SL-09)**. Today this yields 0 s (section 5) - do not start it for its own sake |
| 4 | Same-commit references (`$/`) for workflow pins | outside this scope | - | requires an **ADR-0025 section 5 amendment**; section 5 currently mandates `@<40-hex>` for every `uses:` and zero branch/tag refs |

Follow-up 2's two halves are deliberately not merged: the epoch axis (attest/mint) and the shard
weights are separate levers with separate prerequisites, and both are class B, so neither is "done"
until a later run shows a shorter tail.

---

## 9. Honest limits of this record

- **n = 1 cycle.** One merge_group event, three workflows. The tail ordering flipped in the preceding
  cycle (section 6), so the 12 s margin is not a stable quantity and no p50/p90 is claimed here.
- **Second-granularity timestamps.** GitHub records whole seconds; a 5 s job (`go-critical-rollup`,
  final `admission-check`) has +-1 s of quantization. No conclusion in this record depends on a
  sub-5 s difference.
- **"Wall" is the run envelope**, from `run_started_at` to the last job's `completed_at`. It includes
  runner assignment. It is not a sum of step work, and per the metric contract a per-job step span is
  not an edge cost, so step spans here are used only to locate the tail, never summed into a budget.
- **Not measured**: queue wait before `04:30:44` (out of the run record), and the pre-run scheduling
  of the merge group itself. Neither affects the internal decomposition.
- **This record asserts nothing about other cycles' tails**; the observations are labeled with their
  run ids so any claim can be re-derived with section 10's commands.

---

## 10. Reproduction

```
gh api repos/Archright/Axiom/actions/runs/45940366569 --jq '.run_started_at, .updated_at'
gh api repos/Archright/Axiom/actions/runs/45940366569/jobs --paginate \
  --jq '.jobs[] | "\(.name) \(.started_at) -> \(.completed_at)"'
gh api repos/Archright/Axiom/actions/runs/45940366345/jobs --paginate \
  --jq '.jobs[] | "\(.name) \(.started_at) -> \(.completed_at)"'
gh api repos/Archright/Axiom/actions/runs/45940366417/jobs \
  --jq '.jobs[] | "\(.name) \(.started_at) -> \(.completed_at)"'
gh api repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-27 \
  --jq '.workflow_runs[] | "\(.id) \(.name) \(.run_started_at) \(.updated_at)"'

# pin drift (WSL git; the rev:path form is required)
git diff c021c33801455a481e05b75c396d95c84bbdc45d -- .github/workflows/runner-pool-acceptance.yml
git diff --stat c021c33801455a481e05b75c396d95c84bbdc45d -- .github/workflows/runner-pool-acceptance.yml
git hash-object .github/workflows/admission-check.yml   # == trustedAdmissionWorkflowSha
```