# gh CLI Org-Required-Workflow Run Quirks

**Discovered**: 2026-09-29 (CI Phase 0 probe)
**Class**: external tool (GitHub CLI) behavior with organization-level
required workflows (ruleset `workflows` rule; YAML owned by `Archright/.github`)

## Symptom

`gh run watch <id>`, `gh run view <id>`, and `gh run list --workflow=<name>`
fail with HTTP 404 when the target run belongs to an ORGANIZATION required
workflow (e.g. `admission-gate`), even though the run is listed in this
repository's Actions tab:

```
GET /repos/Archright/Axiom/actions/workflows/367727531 → 404
```

## Cause

`gh` resolves the run's `workflow_id` against the CURRENT repository. The
required workflow's YAML lives in the org `.github` repository, so that
workflow id does not exist under `Archright/Axiom/actions/workflows/*` and
the lookup 404s. In-repo workflows are unaffected.

## Sanctioned workarounds

1. **PR-required checks** (the authoritative merge gate): use
   `gh pr checks <n> --watch` — check-unit observation, no workflow-id
   resolution. This is the sanctioned observation path for admission-gate
   runs while this gh limitation persists.
2. **Raw run objects**: REST `GET /repos/{owner}/{repo}/actions/runs/{id}`
   (returns the run regardless of workflow ownership).

This narrows—but does not override—AGENTS.md §2.3: `gh run watch` remains the
mandate for in-repo workflows; the two workarounds above are the documented
substitute for org-required-workflow runs until the gh defect is addressed
upstream.

---

## Quirk: `gh run watch` / `gh run view` 404 on org-required-workflow runs

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks must live in
> `docs/spec/` and be referenced from AGENTS.md. Record linked from
> `docs/spec/github_delegation_residuals.md` R8.

**Discovered**: 2026-09-30 (live admission-gate merge_group incident)
**Class**: external tool (GitHub CLI) — run-by-id resolution still enumerates
the current repository's own workflows endpoint

## Symptom

`gh run watch <id>` and `gh run view <id>` fail with HTTP 404 for runs of
ORGANIZATION required workflows even when invoked with the exact run id:

```
GET /repos/Archright/Axiom/actions/workflows/367727531 → 404
```

Observed live 2026-09-30 on the admission-gate `merge_group` run **36667874946**,
while `gh api repos/Archright/Axiom/actions/runs/36667874946` returned the run
status fine.

## Root cause

`gh` resolves a run by id through `shared.GetRun` (`pkg/cmd/run/shared/shared.go`),
then **unconditionally** looks the run's `workflow_id` up against the **current
repository's own** workflows endpoint — `getWorkflowByID` issues
`GET /repos/{owner}/{repo}/actions/workflows/{id}`
(`pkg/cmd/workflow/shared/shared.go`). A required workflow's YAML is owned by
the org `.github` repository (ruleset `workflows` rule — the REST
WorkflowFileReference schema pins the `repository_id` of the source
repository), so that workflow id does not exist under
`Archright/Axiom/actions/workflows/*` and the lookup 404s — even though the
run is listed in this repository's Actions tab. gh's own source acknowledges
this for the list path: the 404 "is likely a organization or enterprise
ruleset workflow … it is nonetheless in the workflow run list"
(`preloadWorkflowNames`). In-repo workflows are unaffected.

## Sanctioned workaround

- **REST-by-run-id status polling** — the AGENTS.md §2.3 bootstrap/exception
  pattern: poll `gh api repos/{owner}/{repo}/actions/runs/{run_id}` (`.status`
  / `.conclusion`) at **≥30s intervals** until `completed`. The REST endpoint
  `GET /repos/{owner}/{repo}/actions/runs/{run_id}` returns the run regardless
  of workflow ownership — "Gets a specific workflow run. Anyone with read
  access to the repository can use this endpoint." (docs.github.com, REST
  workflow runs). Used exactly once during the 2026-09-30 incident,
  bootstrapping-style. **Never** a hand-rolled multi-endpoint polling loop.

## Deterministic rule

Watch by run-id via REST (`GET /repos/{owner}/{repo}/actions/runs/{run_id}`,
status polling ≥30s) **until gh's `run watch`/`run view` implementation
supports org required workflows upstream** (`cli/cli`).

---

## Merge-group (`gh-readonly-queue`) runs of org-hosted workflows — same 404 class, re-verified

> AGENTS.md §0.5 Quirk Mandate — batch-2 documentation entry (2026-10-08).
> Extends, does not replace, the sections above; no code or registry change.

**Live observation**: admission-gate merge_group run **37428943334** on queue
branch `gh-readonly-queue/main/pr-498-b2a979b4…` (event `merge_group`):
`gh run watch` and `gh run view` both fail with HTTP 404. First recorded
2026-10-06 (the ~46-minute blind-wait incident —
`docs/evidence/merge_admission_observation_blindspot_incident_2026-10-06.md`,
"Verified tool-surface facts"; also
`docs/agents/merge_admission_observation.md`). **Re-measured 2026-10-08**:

```
$ gh run view 37428943334 -R Archright/Axiom
failed to get run: HTTP 404: Not Found
  (https://api.github.com/repos/Archright/Axiom/actions/workflows/367727531)
$ gh api repos/Archright/Axiom/actions/workflows/367727531   → 404 Not Found
$ gh api repos/Archright/Axiom/actions/runs/37428943334      → 200 (run JSON:
    event=merge_group, conclusion=failure, workflow_id=367727531)
$ gh api repos/Archright/Axiom/actions/workflows             → in-repo ids resolve
    (first id 361840406 → 200)
```

The failure message itself names the mechanism: gh re-resolves the run's
`workflow_id` (367727531 — the workflow FILE is owned by the org `.github`
source repository) against the HOST repository's workflows endpoint. The class
is **org-hosted (required/reusable) workflow runs**, not merge_group-specific;
merge_group is the recurring operational case because the queue phase's runs —
and only those — live on `gh-readonly-queue/*` branches and carry the
merge-admission verdict.

**Scope narrowing of workaround 1 above**: `gh pr checks` binds to the PR head
SHA only; merge_group check runs attach to the queue merge commit, so the queue
phase is invisible to `gh pr checks` (incident record, "Verified tool-surface
facts"). The committed merge_group-phase adapter is
`tools/ci/landing_observe.sh` — GraphQL `mergeQueueEntry` + REST
`/actions/runs?event=merge_group` filtered by
`head_branch ~ ^gh-readonly-queue/main/pr-<N>-`. REST run-id polling remains
the manual fallback per the Deterministic rule above.

**Official documentation basis** (docs.github.com REST reference / rulesets
docs / gh CLI manual, via GitHub docs mirror + live API, 2026-10-08):

- REST endpoints under `/repos/{owner}/{repo}/actions/workflows/{workflow_id}`
  are repository-scoped by contract (REST reference, Actions workflow
  endpoints). A workflow whose file is owned by another repository has no id in
  this repository's namespace. Required-workflow rulesets document exactly this
  ownership model: "in your organization settings, you specify the **source
  repository** and the workflow you want to enforce" (rulesets — available
  rules). The 404 on the workflow id is therefore GitHub's documented
  repo-scoping, not data loss and not a visibility restriction on the run.
- `merge_group` is a documented first-class trigger for merge queues
  ("Required status checks needed by a merge queue must include the
  `merge_group` trigger") — queue-phase runs are ordinary, expected run
  objects of the repository.
- "Get a workflow run" — `GET /repos/{owner}/{repo}/actions/runs/{run_id}` —
  "Anyone with read access to the repository can use this endpoint" (quoted in
  the Sanctioned workaround above): run retrieval by id does not depend on
  workflow ownership. Re-verified live 2026-10-08 on run 37428943334.
- gh CLI manual (`cli.github.com/manual/gh_run_view`, `gh_run_watch`): `gh run
  view` is documented as "View a summary of a workflow run" by `<run-id>` and
  `gh run watch` as "Watch a run until completion and display progress" — **no
  org-workflow limitation is documented**.

**Verdict**: the observation contradicts no GitHub REST contract — the run
remains retrievable through the documented run-id endpoint while the
workflow-id re-resolution 404s under documented repo scoping. It stands in
tension only with gh's own manual, which documents no limitation; recorded as
a gh defect. Upstream: **cli/cli#9228** (OPEN, verified 2026-10-08) tracks
exactly this class — "`gh run list` and `gh run view` fails when the run's
workflow is defined via Organization ruleset". No fix applied here (external
tool; recorded as-is per §0.5).

**Deterministic rule** (unchanged, plus the committed adapter): watch by
run-id via REST (`GET /repos/{owner}/{repo}/actions/runs/{run_id}`, status
polling ≥30s) until gh's `run watch`/`run view` implementation supports org
required workflows upstream (`cli/cli#9228`); for the merge_group queue phase,
use the committed `tools/ci/landing_observe.sh`.

---

## Ghost `push`-event runs of a `workflow_call`-only callee on `gh-readonly-queue/*` refs during a required-workflow parse outage

> AGENTS.md §0.5 Quirk Mandate — batch-3 documentation entry (2026-10-13).
> Extends, does not replace, the sections above; no code or registry change.
> Observation record only — the dispatch mechanism is UNKNOWN (docs silent;
> recorded as-is — cause unknown → UNKNOWN, no speculation).

**Discovered**: 2026-10-12 (required-workflow parse-poison incident window; registered 2026-10-13)
**Class**: GitHub Actions platform behavior — org required workflow × merge
queue × reusable (`workflow_call`) dispatch; observed on REST run data, cause
not documented upstream

## Symptom

During the 2026-10-12 required-workflow parse-poison outage (org caller
`Archright/.github` `admission-gate.yml` pinned a callee blob that failed to
load with 0 jobs — incident record:
`docs/evidence/emergency_evaluate_window_2026-10-12.md`), the in-repo callee
`.github/workflows/admission-check.yml` produced **`push`-event** runs on
merge-queue temporary refs. The file's `on:` block declares ONLY
`workflow_call:` — verified at pre-incident ref `81bd6c608` (no `push`,
`pull_request`, or `merge_group` trigger; unchanged on post-recovery `main`).
Every observed ghost run carries the 0-job parse-failure signature: run name =
the file path (`.github/workflows/admission-check.yml`), `conclusion=failure`,
and `GET /actions/runs/{id}/jobs → total_count 0`.

Observed 2026-10-13 against live REST data (query:
`gh api "repos/Archright/Axiom/actions/workflows/admission-check.yml/runs?event=push&created=2026-10-12..2026-10-12&per_page=100"`,
paged; the workflow-file path endpoint resolves in-repo, unlike the
org-hosted 404 class above):

| metric | value |
|---|---|
| push-event runs of the path on 2026-10-12 | **123** (all `failure`, all name = file path) |
| window (UTC) | 06:57:49Z (38215154419) → 15:44:35Z (38272448370) |
| on `gh-readonly-queue/main/pr-*` refs | 111 (first 07:26:31Z → last 12:59:47Z) |
| on named branches | 7 (`main` ×1, `fix/closure-candidate-delta` ×3, `bisect/h6` ×1, `ci/admission-dispatch-token` ×1, `probe/s2-gate-oracle-ax` ×1) |
| `head_branch: null` (ref deleted at observation time) | 5 |

Example queue-ref ghost runs (0 jobs each, verified via `/jobs`):

| run id | created_at (UTC) | head_branch |
|---|---|---|
| 38233242593 | 09:57:36Z | `gh-readonly-queue/main/pr-791-c4dbd4f7…` |
| 38248903398 | 12:25:12Z | `gh-readonly-queue/main/pr-787-3d64a7af…` |
| 38251477656 | 12:49:31Z | `gh-readonly-queue/main/pr-786-18bb145e…` |
| 38252599119 | 12:59:47Z | `gh-readonly-queue/main/pr-791-18bb145e…` |

Absence / cessation checks (same query, `created=` filters):

- 2026-10-10 / 2026-10-11: `total_count = 0` — no push-event runs of the path
  before the incident day.
- 2026-10-12 after 15:44:35Z (15:44:36Z–23:59:59Z): `total_count = 0`;
  2026-10-13: `total_count = 0` — matches the incident record's "유령 push run은
  15:44:35Z 이후 소멸 관측"; final recovery was PR #795 + `.github` pin rotation
  (#184 → #188) (`docs/evidence/admission_parse_poison_oracle_2026-10-13.md`).

## Interpretation (observation, NOT explanation)

While the org-required-workflow graph was failing to parse (0-job load
failure), the service also dispatched `push`-event "ghost" runs of the
`workflow_call`-only callee on queue refs. The temporal correlation with the
incident window is an observation; no mechanism is asserted. Two window
details stay unexplained and are recorded as UNKNOWN below: the first ghost
run (06:57:49Z) precedes the incident record's 09:50:31Z caller-pin rotation,
and 12 of 123 ghost runs are on non-queue refs.

## Official documentation basis (docs.github.com, fetched 2026-10-13)

- Merge-queue temporary refs: "A merge queue creates temporary branches with a
  special prefix to validate pull request changes"; the prefix is documented as
  `gh-readonly-queue/{base_branch}` — "These are the temporary branches that
  are created on your behalf by a merge queue and contain a different sha from
  the pull request." [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- Queue-phase trigger semantics: the documented queue event is `merge_group`
  ("Runs your workflow when a pull request is added to a merge queue") and
  "The `merge_group` event is separate from the `pull_request` and `push`
  events." [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- Reusable workflow execution: "For a workflow to be reusable, the values for
  `on` must include `workflow_call:`"; execution is via a caller's `uses:`
  job. No `push`-event execution path for a callee is documented.
  [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- Required (ruleset) workflows: a ruleset references the enforced workflow by
  `WorkflowFileReference` — "A workflow that must run for this rule to pass",
  with `repository_id` = "The ID of the repository where the workflow is
  defined" (source-repository ownership; org rulesets require workflows to
  pass before merging pull requests).
  [REST: organization rulesets](https://docs.github.com/en/rest/orgs/rulesets),
  [Creating rulesets for repositories in your organization](https://docs.github.com/en/organizations/managing-organization-settings/creating-rulesets-for-repositories-in-your-organization)

## UNKNOWN (docs silent — recorded, not speculated)

1. **Dispatch mechanism**: no documented code path produces a `push`-event run
   of a workflow whose `on:` lacks `push`. Why a parse outage produced them on
   queue refs (and 12 runs on non-queue refs): UNKNOWN.
2. **Signature semantics**: whether "run name = file path + 0 jobs" is a
   defined platform state: UNKNOWN (docs define neither the signature nor its
   meaning).
3. **Onset mismatch**: the first ghost run (06:57:49Z) precedes the incident
   record's 09:50:31Z caller-pin rotation; which earlier state initiated the
   dispatch stream: UNKNOWN.
4. **Admission effect**: whether ghost runs create check runs or influence
   required-check admission (the incident record shows required check runs
   were not created during the outage). Per AGENTS.md §2.3, zero reported
   required checks is UNKNOWN / NOT READY — never SUCCESS.
5. **Null-ref runs**: whether the 5 `head_branch: null` runs (ref deleted
   before observation) were queue refs: UNKNOWN.

**Verdict**: observed platform behavior, bounded to the 2026-10-12 incident
window, with a hard stop coinciding with recovery. No GitHub-side action taken
or possible here (external platform; recorded as-is per §0.5). Treat any
future `push`-event runs of a `workflow_call`-only path as an incident
signature: query with `event=push&created=…` as above, and do not interpret
their absence of check runs as admission success (§2.3).
