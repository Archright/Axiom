# GitHub Actions artifact — run attempt quirks

> Quirk Mandate record (AGENTS.md §0.5). Platform behavior observed live;
> consumers must not depend on the undocumented half of it.

## Q1. Same-name `upload-artifact` across run attempts: replace-or-coexist is NONDETERMINISTIC

Attempts of one workflow run share a `run_id`. `actions/upload-artifact@v4`
(pinned `ea165f8d`, v4.6.2) documents artifacts as immutable and offers
`overwrite: true` for explicit replacement. Without `overwrite`, uploading a
**name that already exists in the run** is documented to fail — but across
attempts of the same run the observed behavior is neither guaranteed replace
nor guaranteed failure. Two live observations of the same pinned workflow
(`admission-check.yml @ 0a7ca6b4e2c2`, same upload step, same action SHA):

| run | head | attempt 1 witness | attempt 2 witness | list state |
|---|---|---|---|---|
| `37176994649` (PR #456) | `869fce2e8…` | id `11293288192` 04:33:59 | id `11293223687` 04:40:12 | **1** artifact — attempt 1's id later `404` (deleted) |
| `37183851918` (PR #457) | `813bee6b7…` | id `11296620650` 06:56:03 | id `11296456614` 07:01:38 | **2** artifacts — both `expired=false` |

Both attempt-2 upload step logs are structurally identical (no delete/overwrite
message; both finalize a new artifact ID). The deletion of
`11293288192` in run `37176994649` is not attributable to any step in the
workflow — it happened in the artifact service around the second upload.

Consumer impact: an exactly-one check over `GET /actions/runs/{run_id}/artifacts`
(e.g. `certificate-mint.yml` `MINT_ART`) is therefore **not deterministic**
under re-runs when the artifact name lacks an attempt component. Observed
failure: `MINT_ART: FAIL — expected exactly one artifact named
'admission-check-<head>', found 2 (fail-closed)` (run `37179209673` attempt 2
and run `37183851918` attempt 2).

Rule: **name must carry `run_attempt` for evidence/handoff artifacts**
(ADR-0027 P2 as amended; debt464 §9(ii) trusted-name layer). Never rely on
same-name replacement. For non-evidence payloads (cache seeding), a stable
name plus `overwrite: true` is the explicit, deterministic option.

## Q2. `run_attempt` is an identity component of the witness manifest

The witness provenance records `run_attempt`; the mint's 3-layer attempt
binding cross-checks it against the run object. A witness produced by
attempt *k* is therefore only consumable at attempt *k*: "re-run failed jobs"
that re-runs the consumer without the producer fail-closed at the manifest
layer even if exactly-one holds. Combined with Q1, any attempt > 1 on the
old un-suffixed name was doubly doomed (stale manifest or name collision) —
which is why the two-attempt `NO_CERT` bootstrap deadlocked until names were
attempt-scoped.

## Q3. Org-required-workflow `gh` CLI 404s (already recorded)

See `docs/spec/gh_org_required_workflow_run_quirks.md` — `gh run watch/view/rerun`
404 on org-hosted required workflow runs (`workflow_id` resolved through the
repo's workflows endpoint). Sanctioned: `gh pr checks <N> --watch`, direct
REST (`gh api -X POST …/runs/{id}/rerun`, `…/rerun-failed-jobs`). Artifact
deletion uses `DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id}`
— note **no** `runs/{run_id}` segment in that path; the run-scoped path 404s.
