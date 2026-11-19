# CI Acceptance Contract v2 — merge_group admission acceptance

**Status**: pre-registered 2026-11-19 (this document is the contract; the collector
`tools/ci/ci_acceptance_collect.nim` is its only implementation).
**Revision 2026-11-19b**: canonical job-span latency with labeled legacy clock,
full-window acceptance with `INCOMPLETE`/shortfall, the certificate rule for
`NO_CERT`/`SUBJECT_MISMATCH`, `run_head_mismatch`, `admission-check` App
authority (`5795152`), and the artifact download allowlist.
**Authority**: REPORTER ONLY. This contract and its collector have **no merge
authority**, do not modify policy, do not add or remove required checks, and do
not re-run workflows. They observe `admission-gate` `merge_group` runs with
read-only `gh api` GET calls and render an acceptance report.
**Supersedes**: the v1 practice of counting *workflow runs*. One candidate
exercises roughly eight workflows, so a run count is not an entry count.

---

## §1. Scope and vocabulary

- **Candidate** — a merge-queue trial-merge commit `G` (the `merge_group` event's
  `head_sha`).
- **Entry** — one unique `merge_group` `head_sha` of the `admission-gate`
  workflow (`name: admission-gate`, `.github/workflows/admission-gate-v2.yml`).
  All workflow runs sharing that `head_sha` are the same entry.
- **Attempt** — one `run_attempt` of one run. A re-run increments the attempt
  number; it does **not** create a new entry. A fresh `checks_requested` run for
  the same `head_sha` is also an attempt of the same entry, not a new entry.
- **Boundary** — the canonical `main` merge commit **after** #145, #186, and
  this contract have all landed. It is always supplied by the operator; there
  is no default and no compiled-in SHA.
- **Observation gap** — any condition under which the collector cannot see the
  complete evidence for an entry (API error, missing artifact *and* log,
  unparsable timestamp, unknown ancestry, missing base/PR identity, truncated
  run list, missing terminal-attempt jobs, unobservable check-runs, missing
  canonical wall). A gap is always `unclassified` and always exit 2.
- **Admission App (authority)** — the check-run producer of the
  `admission-check` context: app id `5795152` (`axiom-admission-verifier`).
  GitHub Actions (app id `15368`) can publish a check with the same name; that
  check is **not** admission authority.

The historical run `44481531363` is the first observed entry and is recorded as
an observation only. It is outside the acceptance window because it predates
the boundary. The collector contains **no special case** for it; the boundary
filter excludes it like any other pre-boundary entry.

---

## §2. Entry construction

1. Fetch `GET /repos/{repo}/actions/runs?event=merge_group` (paginated) and keep
   only runs whose workflow name is `admission-gate` or whose path is
   `.github/workflows/admission-gate-v2.yml`. `pull_request` and `push` runs are
   never entries.
2. Group the kept runs by `head_sha`. `run_ids` and `attempt_ids` of an entry are
   the union over its runs, sorted deterministically.
3. Derive the entry's `base_sha` from `head_branch`
   `gh-readonly-queue/main/pr-<N>-<base_sha>` (the canonical queue record),
   falling back to `pull_requests[0].base.sha`. `pr_number` comes from
   `pull_requests[0].number` or the same branch spelling. Missing identity is an
   observation gap.
4. The **terminal attempt** is the attempt with the greatest
   `(run_started_at, run_attempt, run_id)` among the entry's attempts. The
   entry's reported `conclusion` and `run_id` are the terminal attempt's; the
   entry's wall clock is measured from the terminal attempt (§6).
5. Fetch every run's attempts with
   `GET /repos/{repo}/actions/runs/{run_id}/attempts`. If that call fails, the
   entry keeps the run-row attempt but carries an observation gap; a successful
   latest attempt must **never** hide an earlier failed attempt.
6. Fetch the terminal attempt's jobs with
   `GET /repos/{repo}/actions/runs/{run_id}/jobs?per_page=100&filter=latest`.
   The jobs are the canonical wall input (§6). A failed jobs call leaves the
   canonical wall unobservable (observation gap), never a guessed duration.
7. Fetch the entry's check-runs with
   `GET /repos/{repo}/commits/{head_sha}/check-runs` (paginated) and record
   every `admission-check` producer app id. The required App `5795152` must be
   among them (§4.7). This is an identity observation, not a re-run of
   admission.

---

## §3. Boundary filter

- `--boundary <sha>` is required and must be a 40-hex commit SHA. The collector
  exits 2 with a clear message when it is absent.
- The boundary's commit timestamp bounds the run-list query; the authoritative
  test is ancestry: an entry is **post-boundary** iff the boundary is an ancestor
  of the entry's `base_sha` (`compare/{boundary}...{base_sha}` status `ahead` or
  `identical`). `base_sha == boundary` counts as post-boundary.
- A pre-boundary entry is excluded from the acceptance window and is not counted.
  If the run list is truncated before the boundary's date, observation is
  incomplete and the collector exits 2.
- If ancestry cannot be observed for an entry, that entry is `unclassified` with
  an observation gap; it is not silently dropped.

---

## §4. Classification

Each attempt is classified, then the entry is the **worst** attempt class.
Retries never erase an incident: an identity divergence, soundness failure, or
projection failure observed in any attempt keeps the entry in that class even
when a later attempt succeeds.

Severity order (highest first): `internal_defect` > `unclassified` >
`legitimate_policy` > `success` > `cancelled_superseded`.

### §4.1 `success`

`status == completed` and `conclusion == success` for every observed attempt.
Success requires that the attempt list was observed; if the attempts API failed,
the entry is `unclassified` with a gap even when the run row says success.

### §4.2 `legitimate_policy`

A failed attempt whose evidence carries one of:

| Signature | Meaning |
|---|---|
| `TRUST_SURFACE_MODIFIED` | The PR touches the admission trust surface; manual merge lane required by policy. |
| `ROT_ALLOWLIST` | Rotation companion path outside the allowlist; policy refusal. |
| `INVALID_INPUT` + an explicit refusal marker | Subject-pin/document refusal (exit 3): `SUBJECT_REGISTRY_UNAVAILABLE`, `SUBJECT_PIN_REJECTED`, `DOCUMENT_INVALID`, `DOCUMENT_ABSENT`, `C_OUT_OVERLAY_REFUSAL`, `CARRIER_UNCONSTRUCTIBLE`, `SIZING_REFUSAL`, `REM_REFUSAL`, or the words `subject-pin` / `subject pin` / `document invalid` / `document absent` / `refusal` in the same evidence. |

`legitimate_policy` is accepted-by-policy behavior: it is counted and reported
but does not fail acceptance. If the same evidence also carries an
identity-divergence signature, the identity classification wins (§4.3).
`NO_CERT` and `SUBJECT_MISMATCH` are **not** legitimate policy refusals; they are
adjudicated by the certificate rule in §4.3 and never by this table.

### §4.3 `internal_defect`

A failed attempt whose evidence carries a pre-registered internal signature, or
whose `admission-check` authority is substituted. Subtypes and their precedence
(highest first: `authority_substitution` > `soundness_failure` >
`identity_divergence` > `failure_projection`):

| Subtype | Pre-registered signatures | Class origin |
|---|---|---|
| `authority_substitution` | The entry's check-runs carry `admission-check` but no check from App `5795152` (§4.7) | Observed 2026-11-19: GitHub Actions (app `15368`) also publishes an `admission-check` context; a same-name check is not admission authority. |
| `identity_divergence` | `PLAN_COMPONENT_MISMATCH`; `judgment_cas: decision file key` together with `freshly re-derived`; `EVIDENCE_SUBJECT_DIVERGENCE`; `MINT_IDENTITY_DIVERGENCE`; `run_head_mismatch` | 2026-11-18/19 audit of 40 `merge_group` admission runs — 7 of 14 failures were plan/attest closure divergence on an unchanged subject. `run_head_mismatch` observed 2026-11-19 on PR #208 (run `44490143040` head `e4fafea` vs PR head `e9ee0f3`); transient and re-adjudicated later, but counted when recorded. |
| `soundness_failure` | `SOUNDNESS_FAILURE`; `false clProved`; `missing dependency supply`; `dependency supply missing` | #145 class (false `clProved` / missing subject-declared dependency supply). Normally proven by its own regression test, not by admission artifacts; the collector matches only explicit evidence and never infers soundness from absence. |
| `failure_projection` | `FAILURE_PROJECTION`; `refusal class lost` (also spelled `refusal-class lost`); an empty `canonical_digest` value (`canonical_digest=`, `canonical_digest: ""`, `"canonicalRunDigest": ""`); `INTERNAL_ERROR` together with a refusal marker | #186 class (a prepare-phase refusal projected as exit 2 / empty canonical digest instead of `INVALID_INPUT` exit 3). |

**Certificate rule (`NO_CERT` / `SUBJECT_MISMATCH`)** — neither code is a
signature by itself. For a failed attempt whose verdict `reasonCode` is
`NO_CERT` or `SUBJECT_MISMATCH`, inspect the **same attempt's** jobs (job names
starting with `mint` or containing `certificate`):

- all such jobs completed `success` → `internal_defect` /
  `identity_divergence` with subtype detail
  `certificate_present_but_unbound` (the verifier refused a certificate the
  attempt produced);
- any such job failed, none is observable, or the attempt's jobs are
  unobservable → `unclassified` with subtype detail
  `mint_failed_unattributed`, never a guessed internal defect (jobs
  unobservable is also an observation gap).

`run_head_mismatch` is recorded whenever observed, including when the same head
is later re-adjudicated successfully: retries may explain an incident, but the
window counts what was recorded.

`unexpected_internal_defects` counts every `internal_defect` in the window. v2
has **no waiver mechanism**: all internal defects are unexpected. A future
waiver would require a new contract version and may not be applied
retroactively.

### §4.4 `unclassified`

Everything else, including:

- a failed attempt whose evidence carries no pre-registered signature;
- a failed attempt with no artifact and no log (observation gap);
- an attempt that is not terminal (`status != completed`);
- `NO_CERT` / `SUBJECT_MISMATCH` whose mint/certificate jobs did not all
  succeed or are unobservable (§4.3 certificate rule);
- missing ancestry, missing base/PR identity, missing terminal-attempt jobs,
  unobservable check-runs, unparsable timestamps, API errors;
- a cancelled attempt that is not proven superseded.

`unclassified` fails acceptance and, when caused by an observation gap, makes
the collector exit 2.

### §4.5 `cancelled_superseded`

A `cancelled` attempt is `cancelled_superseded` **only** when a replacement run
for the same PR exists in the same queue window. PR identity comes from the
queue branch `gh-readonly-queue/main/pr-<N>-<stack-base>`; the REST
`pull_requests` array of a `merge_group` run is empty and cannot be used.

A replacement is another entry with the same `pr_number`, a different
`head_sha`, a later terminal `run_started_at`, and a `base_sha` that is the
**same or a descendant** of the cancelled candidate's `base_sha` (the queue only
moves forward; a rebuild changes the speculative stack base, so exact equality
must not be required). Descent is observed with
`GET /repos/{repo}/compare/{old_base}...{new_base}` and accepted when `status`
is `ahead` or `identical`.

Without that proof — including when the PR identity is unavailable, or when the
ancestry relation is unobservable — the attempt is `unclassified` (a gap when
the replacement context is unobservable). `cancelled_superseded` does not count
as failure.

### §4.6 Evidence policy

Attempt evidence is the concatenated text of the attempt's downloaded artifacts
and, when no allowed artifact yields text, the attempt's downloaded log archive.
Artifacts are fetched before logs. Only text artifacts named by this allowlist
are downloaded:

| Selected | Name |
|---|---|
| prefix | `admission-verdict-` |
| prefix | `admission-check-` |
| prefix | `judgment-record-` |
| prefix | `evidence-record-` |
| prefix | `subject-certificate-` |
| exact | `derived-closure` |
| exact | `ci-select-decision` |

Every other artifact is **never** downloaded and never reaches the evidence
extractor — in particular `*nimcache*`, `*base-artifacts*`,
`*bootstrap-artifacts*`, `go-*`, and `tested-tree-digest`. The deny rules apply
before the allowlist, so a cache artifact that happens to share an allowed
prefix is still excluded. If neither the allowlist nor the log archive yields
text for a failed attempt, the attempt is `unclassified` with an observation gap
— never a guessed class.

### §4.7 `admission-check` authority

For every measured entry the collector observes the check-runs of the entry's
`head_sha` and records every app id that produced a check named **exactly**
`admission-check`. The required verifier App is `5795152`
(`axiom-admission-verifier`).

- Required App present → the entry has admission authority; classification
  proceeds from its attempts.
- Check-runs observable, but no `admission-check` from the required App (for
  example only a same-name check from GitHub Actions `15368`) →
  `internal_defect` / `authority_substitution`.
- Check-runs unobservable → `unclassified` with an observation gap.

The per-entry `admission_app_ids` array records every producer app id (unique,
deterministic). When both apps publish the context, both ids are recorded and
the required App satisfies the authority precondition. This is an identity
invariant: the collector does not re-run admission and never treats a same-name
Actions check as a substitute success.

The check-run list is paginated and its default page is smaller than the
observed population. On `907eba34` (measured 2026-11-19) the App's
`admission-check` was one of 48 check-runs; `GET
/repos/{repo}/commits/{sha}/check-runs` without an explicit `per_page` returned
only the first 30 and the App run was absent. The collector therefore requests
`per_page=100` and pages until the list is exhausted. A truncated list is an
observation gap, never an absence verdict: an unread page must not be
classified as `authority_substitution`.

---

## §5. Acceptance predicate

The window is exactly `N` post-boundary entries (default `N = 20`) ordered by
terminal `run_started_at` ascending:

- `--mode initial` (default) — the **first** N candidates in that order;
- `--mode rolling` — the **last** N candidates.

```
accepted  ⇔  observed_n                 == window
         ∧   unexpected_internal_defects == 0
         ∧   unclassified               == 0
         ∧   observation_complete
```

- `legitimate_policy` is counted and reported but does not fail acceptance.
- `success` and `cancelled_superseded` do not fail acceptance.
- Each `internal_defect` subtype is reported separately.
- `observation_complete` is the fail-closed precondition: any gap anywhere in
  the window means the predicate cannot be satisfied, even if a defect was also
  found. The report exposes `predicate_holds` (the count/coverage predicate
  alone) and `accepted` (predicate + complete observation) separately.

**Full window only.** Fewer than N post-boundary candidates is never evaluated
as a smaller window. When `observed_n < window` the report sets
`status = INCOMPLETE`, `accepted = false`, records `shortfall = window -
observed_n`, and the collector exits 2. When the window is full, the status is
`ACCEPTED` when the predicate holds and `FAILED` otherwise. `mode` and `status`
are always reported.

---

## §6. Latency

**Canonical per-entry wall (the only acceptance latency).** For the terminal
attempt, fetch its jobs with
`GET /repos/{repo}/actions/runs/{run_id}/jobs?per_page=100&filter=latest` and
compute

```
wall_seconds = max(job.completed_at) − min(job.started_at)
```

over jobs whose `started_at` and `completed_at` are both non-null. A job with
only one timestamp contributes nothing. If no job carries both timestamps, the
canonical wall is unobservable → observation gap. The report includes the value
and the number `n` of entries with an observed canonical wall.

**Legacy wall (non-canonical).** `run_started_at → updated_at` of the terminal
attempt, in integer seconds. GitHub does not document a per-attempt run wall, so
this clock is reported as `legacy_wall_seconds` / legacy p50 for continuity only;
it never decides acceptance and never substitutes for a missing canonical wall.

**p50** = sort the observed integer seconds; odd `n` → the middle value; even
`n` → the arithmetic mean of the two middle values (so `.5` is preserved). Both
canonical and legacy p50/mean are reported.

`--recompute-baseline <run-list.json>` computes the **same** canonical job-span
p50 from a supplied run list, plus legacy statistics. Accepted input: a top-level
array, or an object with `runs` (or `workflow_runs`) as an array. Each row uses
its own `jobs` array, or its terminal attempt's `jobs` when an `attempts` array
is present; a row without jobs is excluded from canonical p50 and makes the
baseline incomplete.

`--baseline-live [--window N] [--baseline-until <ISO8601>]` fetches the newest
`N` completed `admission-gate` `merge_group` runs (default `N = 40`) and prints
the canonical and legacy statistics. `--baseline-until` pins the reference set
to runs created at or before the timestamp, so a recorded snapshot stays
reproducible as the live queue advances.

Recorded reference (2026-11-19, set ending at run `44481531363`):

```
$ bin/ci_acceptance_collect --baseline-live --window 40 \
    --baseline-until 2026-11-19T08:00:00Z
[ci_acceptance_collect] baseline-live canonical: n=40 p50=558.0s mean=708.4s min=378s max=2848s
[ci_acceptance_collect] baseline-live legacy: n=40 p50=560.5s mean=711.2s
```

The historical `546`, `560`, and `574.5` seconds are **inadmissible** unless
re-derived by this command. No historical number is compiled into the tool; the
numbers above are contract records, produced by the documented command.

A negative or unparsable legacy wall is a legacy gap only. A missing or
unparsable canonical wall is an observation gap; the row is excluded from p50 and
the collector exits 2 in baseline modes.

---

## §7. Report

The collector writes two files under `--out` (default `build/ci_acceptance/`):

- `ci_acceptance_report.json`
- `ci_acceptance_report.md`

Required per-entry fields: `run_id` (terminal run), `run_ids`, `attempt_ids`,
`head_sha`, `base_sha`, `pr_number`, `conclusion` (terminal), `classification`,
`subtype`, `subtype_detail` (e.g. `certificate_present_but_unbound`,
`mint_failed_unattributed`), `evidence` (pointer), `wall_seconds`,
`wall_observed`, `legacy_wall_seconds` (null when unobserved),
`legacy_wall_observed`, `admission_app_ids`, `admission_app_required`,
`admission_app_success`, `gap`, `gap_reason`, `post_boundary`.

Report-level fields: contract/schema version, generated-at, repo, boundary,
`mode`, `status` (`ACCEPTED` / `INCOMPLETE` / `FAILED`), requested window,
observed `n`, `shortfall`, counts per class, per-subtype counts (including
`authority_substitution`), `unexpected_internal_defects`, `unclassified`,
`predicate_holds`, `accepted`, `observation_complete`, gaps, and
`latency {n, p50_seconds, mean_seconds, min_seconds, max_seconds, legacy_n,
legacy_p50_seconds, legacy_mean_seconds, formula, legacy_formula}`.

Evidence pointers are stable strings of the shape
`run:<run_id>/attempt:<n>/artifact:<artifact-name>` or
`run:<run_id>/attempt:<n>/log:<log-name>`; conclusion-only and gap pointers use
the same prefix. The report is deterministic for identical inputs except
`generated_at`.

---

## §8. Exit codes (fail-closed)

| Exit | Status | Meaning |
|---|---|---|
| `0` | `ACCEPTED` | Report written; full N window observed and the predicate holds. |
| `1` | `FAILED` | Report written; full window observed but an internal defect or unclassified outcome fails the predicate. |
| `2` | `INCOMPLETE` | Observation incomplete or input invalid: shortfall (`observed_n < window`), missing/invalid `--boundary`, API error, missing artifact *and* log, missing jobs/check-runs, unparsable identity/timestamp, truncated run list. The report is still written so the gap is visible. |

`--help` exits 0. `--baseline-live` and `--recompute-baseline` exit 0 when every
row has an observed canonical job span and p50 is defined, 2 otherwise.

---

## §9. Pre-registration and non-goals

- Signature vocabulary comes from the **2026-11-18/19 audit of 40
  `merge_group` admission runs** (`docs/spec/runner_environment_closure_identity_quirk.md`),
  the #145 landing (`5edc018`, subject-declared dependency supply / false
  `clProved`), and the #186 landing (`f057bf5`, prepare-phase refusals projected
  as `INVALID_INPUT` exit 3). Signatures are frozen here **before** any
  post-boundary entry is classified.
- No tuning on post-boundary entries. A signature change requires a new contract
  version and cannot be applied retroactively to a completed window.
- Non-goals: merge authority, policy changes, workflow changes, required-check
  changes, re-runs, mutation of any kind. The collector issues `gh api` GET
  requests only and downloads artifacts/logs to a temporary directory.
- Soundness is normally proven by its own regression test; absence of a
  soundness signature in admission artifacts is not evidence of soundness.