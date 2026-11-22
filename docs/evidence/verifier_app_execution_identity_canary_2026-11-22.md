# Admission verifier App: execution-identity repair and live canary (2026-11-22)

> Scope: the external `axiom-admission-verifier` GitHub App (id `5795152`), which publishes the
> required `admission-check` check-run bound in ruleset `27097366`.
> Recorder is not approver: the author is an agent, the approver is the user (wintrover).
> This document records one repair and its observed deployment effect. It does not edit the
> ruleset, a required context, a workflow, or a pin.

## Section 0. Defect

The App could attach a completion to whichever check-run already existed for the PR head,
without binding that check-run to the completing execution identity `(run_id, run_attempt)`.

Measured on 2026-11-22 (check-run `137119562181`, PR #345 head
`5b63e0b9bf13b0314610fef737e0d2996d75cecd`):

| Field | Value |
|---|---|
| `status` / `conclusion` | `completed` / `success` |
| `external_id` | `v1p\|1454952493\|5b63e0b9…\|ee0c5abc…\|run=44993525406#2` |
| `output.summary` | `run=44993525406 status=in_progress attempt=2` |
| `completed_at` | `2026-11-22T06:29:21Z` (attempt 1 completion) |

The completion PATCH did not update `external_id`, and the guard compared `run_attempt`
alone, so attempt 1 of an older run compared equal to attempt 1 of a newer run. Because
`admission-check` is the required context bound to integration `5795152`
(`integration_id` in ruleset `27097366`), a stale success is not a display defect: it is a
merge-authority defect.

Measured platform constraint: GitHub does not reopen a completed check-run. A PATCH with
`status: in_progress` on a completed run leaves `status=completed` (observed on the same
check-run). Rewriting only the identity of a completed run would therefore publish the
previous execution's verdict under the new execution's name.

## Section 1. Repair (external, App-owned)

Source: Cloudflare Worker `~/.config/axiom-verifier-app/worker/src/index.js` (not in this
repository; the App is externally owned).

- Execution identity is the total order `(run_id, run_attempt)`. A late completion of an
  older execution is ignored.
- A completion rewrites `external_id` and `output.summary` in one PATCH; both name the same
  execution.
- A new execution's start does not rewrite a completed verdict
  (`completed_verdict_held`). Its completion replaces identity and verdict together.
- A completion is authoritative even when `external_id` already names it. The PATCH is
  suppressed only when the recorded `conclusion` and summary already match that completion
  (`verdict_unchanged`), which keeps redelivery idempotent without suppressing a heal.
- A PR run whose head is not the PR subject publishes nothing (`run_head_not_subject`).
- `merge_group` keeps one check per G; a rebuild on a new G is a new subject.

## Section 2. Tests

`node test/run.mjs` → **PASS 45/45**, including:

- a late completion of an older run cannot overwrite a newer verdict;
- a mixed completed record (`success` + `external_id` #2 + in-progress summary) is healed to
  `failure` by #2's completion, in place, without creating a second check-run;
- redelivery of a healed verdict is a no-op;
- `merge_group` start, completion, duplicate, requeue, and rebuild.

## Section 3. Deployment

| Field | Value |
|---|---|
| Worker version | `dc3e280c-e997-4394-a720-86a0dcceb342` |
| Health rev | `2026-11-22.2-verdict-heal` |
| Source sha256 | `3b8a89380e0bf3edafa1d417641a5bd728c84dd007c30e1e965ae94a1d4413bd` |
| Endpoint | `https://axiom-admission-verifier.wintrover.workers.dev/health` |
| Previous versions | `e00984c0…` (superseded: same-execution no-op), `4d15fd0b…` (pre-repair) |

## Section 4. Live observation (production)

Run `44993525406` attempt 1 completed `success` (06:29:17Z). Attempt 2 was a rerun and
completed `failure` at 06:43:29Z, fail-closed: a rerun reuses the original test-merge SHA
(`github.sha` `3e36bfa…`) while the run-scoped anchor re-resolved the moved base
(`0193156e…`), so `CANDIDATE_TREE_MISMATCH` rejected the candidate. That is the ancestry
contract working, not an App defect.

The attempt-2 completion delivery `3855441412015259648` was redelivered against the repaired
Worker:

| Observation | Before | After |
|---|---|---|
| check-run `137119562181` conclusion | `success` (attempt-1 verdict under attempt-2 identity) | `failure` |
| `external_id` | `…run=44993525406#2` | `…run=44993525406#2` |
| `output.summary` | `run=44993525406 status=in_progress attempt=2` | `run=44993525406 attempt=2 conclusion=failure` |
| `completed_at` | `06:29:21Z` (stale) | `06:51:23Z` |

A second redelivery of the same delivery left `completed_at` at `06:51:23Z`: the completed
verdict and its execution identity were unchanged (idempotent no-op).

## Section 5. Authority boundary

- The ruleset was not edited; `bypass_actors` remains empty and `enforcement` remains `active`.
- The seven required contexts in ruleset `27097366` are unchanged.
- The App is externally owned. This record claims the observed check-run state only; it does
  not claim repository-side control over the App or its deployment.
- The fresh PR run and the merge-group observation that exercise the repaired App are the
  landing run of the PR that carries this file; their run IDs are recorded in that PR.