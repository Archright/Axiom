# PR #518 — venue execution measurement and skip audit (2026-11-27)

Status: **MEASURED**, one PR/merge-group pair (n=1). No performance claim is made and no
SLO is re-derived. The contract this evidence supports is a draft held on the proposal
branch `docs/venue-split-proposal-2026-11-27`, not on canonical main: it is not adopted,
and the venue split it would constrain cannot be executed before the external App contract
is confirmed. References to it below are to that draft.

Subject: PR #518 `docs(evidence): record the PR #517 trust-surface landing`, PR head
`1f688ae8a71b5e502b5ab326c37371688f90f3f7`; the single-entry merge group that landed it,
group commit `a6805fc4b122a4d8468fca17a68e522eb7bc7409` (= the resulting `main` tip,
`merge_method: MERGE`). All timestamps are 2026-11-27 UTC.

## §1. Method

Three quantities, each with one definition:

- **job duration** = `job.completed_at - job.started_at`.
- **run wall** = the run's last non-skipped `job.completed_at` minus the run's
  `run_started_at`. A skipped job carries a zero/negative interval and contributes nothing.
- **venue wall** = the completion time of the **last of the seven required contexts to
  report**, minus that venue's first `run_started_at` (04:24:29Z at PR, 04:30:44Z at
  landing). Six of the seven contexts are jobs inside five workflow runs;
  `admission-check` is a check-run record published by the App (producer 5795152), so the
  maximum is taken across both record types rather than assumed to come from the workflows.

Every value is computed here from the GitHub Actions REST API (`/actions/runs/{id}` and
`/actions/runs/{id}/jobs`). Nothing is read from the UI and no duration is borrowed from a
different venue's run.

**A skipped job is not verification time.** It contributes 0 s to every number below and
is counted only in §5. This is the rule the audit turns on: the question about a skip is
not how long it took but what conclusion GitHub published for it.

## §2. Objects

PR venue — all `pull_request` on head `1f688ae8`, every run started 04:24:29Z:

| run | workflow | path | wall | jobs (skipped) |
|---|---|---|---:|---|
| [45939753629](https://github.com/Archright/Axiom/actions/runs/45939753629) | `admission-gate` | `.github/workflows/admission-gate-v2.yml` | 251 s | 25 (12) |
| [45939753499](https://github.com/Archright/Axiom/actions/runs/45939753499) | `axiom-operational-slice` | `.github/workflows/axiom-operational-slice.yml` | **317 s** | 2 (0) |
| [45939753565](https://github.com/Archright/Axiom/actions/runs/45939753565) | `publication-integrity` | `.github/workflows/publication-integrity.yml` | 60 s | 8 (6) |
| [45939753467](https://github.com/Archright/Axiom/actions/runs/45939753467) | `bsec-integrity` | `.github/workflows/bsec-integrity.yml` | 103 s | 1 (0) |
| [45939753472](https://github.com/Archright/Axiom/actions/runs/45939753472) | `debt-registry-gate` | `.github/workflows/debt-registry-gate.yml` | 70 s | 1 (0) |
| [45939753538](https://github.com/Archright/Axiom/actions/runs/45939753538) | `generation-acceptance` | `.github/workflows/generation-acceptance.yml` | 20 s | 1 (0) |

Landing venue — all `merge_group` on head `a6805fc4`, every run started 04:30:44Z:

| run | workflow | wall | jobs (skipped) |
|---|---|---:|---|
| [45940366569](https://github.com/Archright/Axiom/actions/runs/45940366569) | `admission-gate` | 368 s | 26 (11) |
| [45940366417](https://github.com/Archright/Axiom/actions/runs/45940366417) | `axiom-operational-slice` | 297 s | 2 (0) |
| [45940366345](https://github.com/Archright/Axiom/actions/runs/45940366345) | `publication-integrity` | 355 s | 10 (0) |
| [45940366457](https://github.com/Archright/Axiom/actions/runs/45940366457) | `bsec-integrity` | 69 s | 1 (0) |
| [45940366319](https://github.com/Archright/Axiom/actions/runs/45940366319) | `debt-registry-gate` | 73 s | 1 (0) |
| [45940366360](https://github.com/Archright/Axiom/actions/runs/45940366360) | `generation-acceptance` | 23 s | 1 (0) |

The App-published `admission-check` check run (producer 5795152) brackets each venue end
to end: PR head **04:24:34 → 04:28:43 (249 s)**; group commit **04:30:43 → 04:36:56
(373 s)**.

**Run-id substitution, recorded rather than silently repaired.** Four ids supplied with the
request return HTTP 404 for this repository and cannot be observed: `45939753096`,
`45939753052`, `45939753035`, `45939752931`. Run ids are globally allocated, so their
neighbours in this repository being real says nothing about them. The ids in §2 are the
ones this repository actually recorded for `1f688ae8`.

## §3. Lane durations

`admission-gate` — the legs are not one chain: `go-critical-lane`,
`admission-independents`, and `gateway` all hang off `build-base-artifacts` /
`closure-deriver` and run concurrently, which is why the job durations sum past the wall.

| job | PR | landing |
|---|---:|---:|
| `anchor-resolve` | 5 s | skipped |
| `closure-deriver` | 31 s | 25 s |
| `attest/build-base-artifacts` | 43 s | 78 s |
| `attest/admission-independents` (`needs: [build-base-artifacts]`) | 61 s | 84 s |
| `attest/go-critical-lane` lane 0 / lane 1 (same need) | skipped | 104 s / 117 s |
| `attest/go-critical-rollup` | skipped | 5 s |
| `attest/admission-check` (callee) | 48 s | 65 s |
| `gateway/select` → `ci-bootstrap` → `executed-jobs` | 44 → 51 → 5 s | 133 → 63 → 3 s |
| `mint-prepare` | 20 s | 20 s |
| `mint-publish` | 39 s | 69 s |
| `verdict/admission-check` (callee) | 54 s | 51 s |
| `admission-check` (aggregate) | 4 s | 5 s |
| **run wall** | **251 s** | **368 s** |

`axiom-operational-slice` — a declared serial chain
(`readiness-verdict` `needs: [axiom-operational-slice]`,
`.github/workflows/axiom-operational-slice.yml:319-320`), and the two jobs sum to the wall:

| job | PR | landing |
|---|---:|---:|
| `axiom-operational-slice` | 162 s (04:24:31→04:27:13) | 144 s (04:30:47→04:33:11) |
| `readiness-verdict` | 151 s (04:27:15→04:29:46) | 148 s (04:33:13→04:35:41) |
| **run wall** | **317 s** | **297 s** |

`publication-integrity`:

| job | PR | landing |
|---|---:|---:|
| `secret-scan` (both venues) | 23 s | 41 s |
| `dependency-scan` | skipped | 30 s |
| `provenance` | skipped | 26 s |
| `sbom` | skipped | 29 s |
| `script-scan` | skipped | 28 s |
| `license-scan-shards` 0 / 1 / 2 | skipped | 225 s / 293 s / 263 s |
| `license-scan` | skipped | 33 s |
| aggregator `publication-integrity` | 33 s | 24 s |
| **run wall** | **60 s** | **355 s** |

## §4. Is the PR venue a repetition of the landing venue?

Yes on the critical path, and the repetition is nearly total.

| question | measurement |
|---|---|
| PR venue wall | **317 s** — the slice chain reports last (04:29:46); the App check closed at 04:28:43, i.e. 254 s after venue t0 |
| landing venue wall | **372 s** — the App check reports last (04:36:56); the `admission-gate` run closed at 368 s |
| venue wall ratio | 317 / 372 = **0.85** |
| the serial chain both venues pay | 162+151 = **313 s** (PR) vs 144+148 = **292 s** (landing), Δ 7 % |
| largest single work increase at landing | `publication-integrity` 60 → 355 s (**+295 s**): 5 of its 6 dimensions are landing-only, and it finishes **17 s before** the last context reports |
| largest work *removed* at landing | `bsec-integrity` 103 → 69 s (−34 s) |
| wall growth of the venue | **+55 s** |

The second-to-last row is the non-obvious part. Publication breadth is by far the largest
change in *work*, but in this sample it is not the binder: it reports 17 s before the App
check does, so its +295 s moves the venue wall by **0 s**. It becomes the binder the moment
any shard runs ~20 s slower. The venue wall grows 317 → 372 s because the admission chain
grows 251 → 368 s (+117 s — the GO lanes come in) while the slice chain shrinks 317 → 297 s
(−20 s — PR-only `anchor-resolve` goes out).

**So the PR venue spends ~85 % of the landing venue's wall re-executing the same serial
chain that the landing venue then re-executes.** It is not a cheaper projection of the
landing check; the only genuinely cheap part (publication's other five dimensions) is the
part that never appears on the critical path.

A **third** execution of the same two jobs follows the merge: on the resulting `main` tip
the `push` venue ran `axiom-operational-slice` (04:37:17) and `readiness-verdict`
(04:40:22). That run is evidence, not admission (draft contract §2), but it is a third
payment for the same work.

## §5. Skip audit — every unit that did not run, and its compensation

Counts are from the job listings in §2. `compensation` is a locus verified in the workflow
source at `a6805fc4`, not inferred from a green conclusion.

| unit | PR | landing | basis in source | compensation |
|---|---|---|---|---|
| `anchor-resolve` | ran 5 s | **skipped** | `admission-gate-v2.yml:210-211` — `github.event_name == 'pull_request'` | none needed: PR-only by design; the aggregate admits `skipped` **only** off-PR (`:761-766`, A2) |
| `attest/go-critical-lane` ×2, `attest/go-critical-rollup` | **skipped** | ran 104/117 s + 5 s | `admission-check.yml:3973,4782` — `always() && stage=='attest' && (merge_group \|\| workflow_call)` | landing venue executes all three; the PR venue pays `[preflight] Attest-leg static contrast` (`:1723`), `[preflight] Verdict-leg static contrast` (`:2199`), `[preflight] Rotation-pin H2 contrast` (`:2289`) — pin and policy posture, **not** the GO contract tests. The `verdict/` copies of these two jobs are skipped on **both** venues by the `stage=='attest'` conjunct, so they are not venue asymmetries |
| `[guard] Every direct need must be success` (step) | skipped | ran | `admission-check.yml:813-814` — `stage=='attest' && venue=='landing'` | **uncompensated by design** — §6 |
| `license-scan-shards` ×3, `license-scan` | **skipped** | ran | `publication-integrity.yml:204,306` — `event_name in (merge_group, schedule, workflow_dispatch)` | landing venue runs all four; at PR the aggregator is told the venue and requires only `secret-scan` (`tools/ci/publication_report.nim:58-65`), and a `success` for an unrequired dimension is a **BLOCKER** |
| `dependency-scan` | **skipped** | ran 30 s | `publication-integrity.yml:437` | as above |
| `provenance` | **skipped** | ran 26 s | `publication-integrity.yml:519` | as above |
| `sbom` | **skipped** | ran 29 s | `publication-integrity.yml:570` | as above |
| `script-scan` | **skipped** | ran 28 s | `publication-integrity.yml:642` | as above |
| `gateway/candidate-build-arm`, `gateway-shard`, `gateway-identity-gate`, `gateway/proof-reconcile` | **skipped** | **skipped** | `runner-pool-acceptance.yml` — `needs.sl09-scope.outputs.scope_sl09 == 'true'` | the callee's `executed-jobs` rollup runs on both venues and publishes `name=skipped(sl09_not_promoted)` only for this scope; any other skip fails closed. Scope, not venue |
| `generation-acceptance` steps 7–12 | skipped | skipped | data-derived (`NO_SURFACE_DELTA`), no `event_name` predicate | the `surface.py` verdict is the executed judgment on both venues |
| `axiom-operational-slice` `S5 gate` step | skipped | skipped | `steps.setup-tc.outputs.b-cache-hit == 'true'` | supply-reuse selection only; `make ci-compile` cold-builds and fails closed |
| the `stage`-dispatch sections of the three reusable calls: `verdict/build-base-artifacts`, `verdict/admission-independents`, `verdict/go-critical-lane`, `verdict/go-critical-rollup`, `mint-publish/prepare`, `mint-prepare/publish` | **skipped** | **skipped** | `inputs.stage` conjunct on each job (`admission-check.yml` job `if:`), and the `stage:` input on the two `mint-*` calls | Admissible because **the sibling section of the same call executes on the same venue**: `attest/*` and `mint-prepare/prepare` and `mint-publish/publish` all ran on both. The `stage` input is a required workflow input, so a call missing it fails at plan time rather than skipping |

**Is any required unit skipped at the landing venue?** Only `anchor-resolve`, and the
aggregate asserts that one inline under an event predicate. Every other venue-asymmetric
skip is a PR-venue skip whose compensation is the landing venue itself. The units skipped
at **both** venues are of two kinds, and each carries an executed basis: the `stage`
sections of the reusable calls (their sibling sections run on the same venue), the
`gateway` scope lanes (`skipped(sl09_not_promoted)` in the callee's `executed-jobs`
rollup), and the `generation-acceptance` fast path (a computed `NO_SURFACE_DELTA`).

### §5.1 What each compensation actually produces

- `[preflight] Attest-leg static contrast` — `git hash-object admission-check.yml` equals
  `trusted_writer_set.json .trustedAdmissionWorkflowSha`, plus
  `merge_admission.json .certRequired == true`. Real comparisons over the B tree; a
  mismatch exits 1.
- `[preflight] Verdict-leg static contrast` — policy SSOT plus the stage-dispatch
  structure (the required `stage` input exists).
- `[preflight] Rotation-pin H2 contrast` — the rotation pin at H versus the derived H.
- `publication_report --venue` — a required closed enum; the venue's required set is
  applied, so a skipped dimension cannot be claimed as credit.
- `executed-jobs` (callee) — a sorted `name=conclusion` basis string with the single
  admitted skip annotated `skipped(sl09_not_promoted)`.

## §6. The one gap this audit found

`admission-check.yml` already states the platform rule in the comment above the guard: "a
skipped job reports Success and does not block merges" (`:799-800`), and the guard exists
to convert that into an explicit judgment. But the guard carries
`if: inputs.stage == 'attest' && steps.venue.outputs.venue == 'landing'` (`:813-814`), so
**on the PR venue nothing asserts that the skipped GO lanes were skipped legitimately**.
The PR venue's green is the platform's F1 taken at face value, bounded only by the fact
that the landing venue re-runs those lanes with the guard active.

That is acceptable under the draft contract (proposal branch `docs/venue-split-proposal-2026-11-27`,
its §3.2 registers it as an uncompensated skip and states its boundary), but it is exactly
where a future edit — a second venue-gated lane, say — would produce a silent pass with no
local assertion to catch it. The draft's §5 Q4 exists for that reason.

## §7. Not verified

- **The App's PR-venue judgment set.** `docs/agents/axiom_admission_verifier_ops.md:38`
  says `admission-check` is published on the PR head and on `G`, and that the PR venue is a
  preflight; which predicates the App evaluates internally at the PR venue is not
  documented in this repository — **UNKNOWN**, and no claim above depends on it.
- **n=1.** One PR/merge-group pair. The 0.85 ratio and the ±20 s deltas are observations of
  this pair, not a distribution; `docs/spec/ci_critical_path_metric.md` is the authority for
  any statistical statement.
- **Queue-side timing** (`T_queue`, entry-to-start) is out of scope; it is measured by
  `tools/ci/ci_admission_observe.nim` and reported in
  `docs/evidence/ci_admission_measurement_2026-11-24.md`.