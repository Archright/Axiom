# CI Acceptance Contract v2 — merge_group admission acceptance

**Status**: pre-registered 2026-11-19 (this document is the contract; the collector
`tools/ci/ci_acceptance_collect.nim` is its only implementation).
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
  run list). A gap is always `unclassified` and always exit 2.

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

### §4.3 `internal_defect`

A failed attempt whose evidence carries a pre-registered internal signature.
Subtypes and their precedence (highest first:
`soundness_failure` > `identity_divergence` > `failure_projection`):

| Subtype | Pre-registered signatures | Class origin |
|---|---|---|
| `identity_divergence` | `PLAN_COMPONENT_MISMATCH`; `judgment_cas: decision file key` together with `freshly re-derived`; `SUBJECT_MISMATCH`; `NO_CERT`; `EVIDENCE_SUBJECT_DIVERGENCE`; `MINT_IDENTITY_DIVERGENCE` | 2026-11-18/19 audit of 40 `merge_group` admission runs — 7 of 14 failures were plan/attest closure divergence on an unchanged subject. |
| `soundness_failure` | `SOUNDNESS_FAILURE`; `false clProved`; `missing dependency supply`; `dependency supply missing` | #145 class (false `clProved` / missing subject-declared dependency supply). Normally proven by its own regression test, not by admission artifacts; the collector matches only explicit evidence and never infers soundness from absence. |
| `failure_projection` | `FAILURE_PROJECTION`; `refusal class lost` (also spelled `refusal-class lost`); an empty `canonical_digest` value (`canonical_digest=`, `canonical_digest: ""`, `"canonicalRunDigest": ""`); `INTERNAL_ERROR` together with a refusal marker | #186 class (a prepare-phase refusal projected as exit 2 / empty canonical digest instead of `INVALID_INPUT` exit 3). |

`unexpected_internal_defects` counts every `internal_defect` in the window. v2
has **no waiver mechanism**: all internal defects are unexpected. A future
waiver would require a new contract version and may not be applied
retroactively.

### §4.4 `unclassified`

Everything else, including:

- a failed attempt whose evidence carries no pre-registered signature;
- a failed attempt with no artifact and no log (observation gap);
- an attempt that is not terminal (`status != completed`);
- missing ancestry, missing base/PR identity, unparsable timestamps, API errors;
- a cancelled attempt that is not proven superseded.

`unclassified` fails acceptance and, when caused by an observation gap, makes
the collector exit 2.

### §4.5 `cancelled_superseded`

A `cancelled` attempt is `cancelled_superseded` **only** when a replacement run
for the same PR exists in the same queue window. The queue window is defined as
the same `base_sha`; a replacement is another entry with the same `pr_number`,
the same `base_sha`, a different `head_sha`, and a later terminal
`run_started_at`. Without that proof — including when the PR identity is
unavailable — the attempt is `unclassified` (gap when the replacement context is
unobservable). `cancelled_superseded` does not count as failure.

### §4.6 Evidence policy

Attempt evidence is the concatenated text of the attempt's downloaded artifacts
(`admission-verdict-*`, `admission-check-*`, `judgment-record-*`,
`evidence-record-*`, `subject-certificate-*`) and, when artifacts are absent,
the attempt's downloaded log archive. Artifacts are fetched before logs. If
neither yields text for a failed attempt, the attempt is `unclassified` with an
observation gap — never a guessed class.

---

## §5. Acceptance predicate

Over the **latest N post-boundary entries** (default `N = 20`, ordered by
terminal `run_started_at` ascending and taking the last N):

```
accepted  ⇔  unexpected_internal_defects == 0
         ∧   unclassified               == 0
         ∧   observation_complete
```

- `legitimate_policy` is counted and reported but does not fail acceptance.
- `success` and `cancelled_superseded` do not fail acceptance.
- Each `internal_defect` subtype is reported separately.
- `observation_complete` is the fail-closed precondition: any gap anywhere in
  the window means the predicate cannot be satisfied, even if a defect was also
  found. The report exposes `predicate_holds` (the two-count predicate alone)
  and `accepted` (predicate + complete observation) separately.

The observed `n` is reported. If fewer than N post-boundary entries exist, the
predicate is evaluated over the observed entries; `n = 0` is an observation gap
and exit 2.

---

## §6. Latency

- **Per-entry wall** = `run_started_at → updated_at` of the **terminal attempt**,
  in integer seconds. The report includes the value and the number `n` of entries
  with an observed wall.
- **p50** = sort the observed integer seconds; odd `n` → the middle value; even
  `n` → the arithmetic mean of the two middle values (so `.5` is preserved).
- `--recompute-baseline <run-list.json>` computes p50 from a supplied run list
  with the **same** terminal-attempt rule and the **same** p50 formula. Accepted
  input: a top-level array, or an object with `runs` (or `workflow_runs`) as an
  array. Each row uses `run_started_at`/`updated_at`, or its terminal attempt's
  fields when an `attempts` array is present.
- The historical `546`, `560`, and `574.5` seconds are **inadmissible** unless
  re-derived by this command. No historical number is compiled into the tool.
- A negative or unparsable wall is an observation gap; the row is excluded from
  p50 and the collector exits 2 in recompute mode.

---

## §7. Report

The collector writes two files under `--out` (default `build/ci_acceptance/`):

- `ci_acceptance_report.json`
- `ci_acceptance_report.md`

Required per-entry fields: `run_id` (terminal run), `run_ids`, `attempt_ids`,
`head_sha`, `base_sha`, `conclusion` (terminal), `classification`, `subtype`,
`evidence` (pointer), `wall_seconds`, `gap`, `gap_reason`, `post_boundary`.

Report-level fields: contract/schema version, generated-at, repo, boundary,
requested window, observed `n`, counts per class, per-subtype counts,
`unexpected_internal_defects`, `unclassified`, `predicate_holds`, `accepted`,
`observation_complete`, gaps, and latency `{n, p50_seconds}`.

Evidence pointers are stable strings of the shape
`run:<run_id>/attempt:<n>/artifact:<artifact-name>` or
`run:<run_id>/attempt:<n>/log:<log-name>`; conclusion-only and gap pointers use
the same prefix. The report is deterministic for identical inputs except
`generated_at`.

---

## §8. Exit codes (fail-closed)

| Exit | Meaning |
|---|---|
| `0` | Report written; acceptance predicate holds over a complete observation. |
| `1` | Report written; acceptance predicate does not hold (internal defect or unclassified outcome). |
| `2` | Observation incomplete or input invalid: missing/invalid `--boundary`, API error, missing artifact *and* log, unparsable identity/timestamp, truncated run list, empty window. The report is still written so the gap is visible. |

`--help` exits 0. `--recompute-baseline` exits 0 when every supplied row is
observed and p50 is defined, 2 otherwise.

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