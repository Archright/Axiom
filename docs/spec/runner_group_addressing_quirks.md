# Runner Group Addressing Quirks (GitHub Actions CI routing)

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks must live in
> `docs/spec/` and be referenced from AGENTS.md.
>
> **Discovered**: 2026-10-11 (CI runner-routing switch — org required
> workflow `admission-gate` re-addressed through the `CI_RUNNER_MAP`
> repository variable; workstream `feat/ci-runner-map-routing`, PR
> Archright/Axiom#729)
> **Class**: external platform (GitHub Actions scheduler, REST, GraphQL)
> behavior around organization required workflows. For the org-hosted run
> *observation* class (`gh run watch/view` 404), see
> `docs/spec/gh_org_required_workflow_run_quirks.md`.
>
> Tagging: **[documented]** = verified against official GitHub documentation
> (live docs.github.com fetch, the OpenAPI description, or the live GraphQL
> schema — URL + quoted sentence given). **[measured]** = observed live on
> the cited run/command. **[documented↔measured mismatch]** = live
> observation contradicts the documented contract.

---

## Q1 — `runs-on: {group: X, labels: [...]}`: the `group` key addresses SELF-HOSTED (or larger) runner groups ONLY; the standard GitHub-hosted pool is not group-addressable

### Symptom [measured]

Job `closure-deriver` in
`Archright/.github/.github/workflows/admission-gate.yml`, run
**38109479498**, failed before dispatch with the check annotation:

```json
{"annotation_level":"failure","message":"Required runner group 'GitHub Actions' not found","path":".github"}
```

The job object shows no runner was ever assigned, yet a runner group *name*
is present:

```json
{"labels":["ubuntu-24.04"],"runner_id":0,"runner_name":"","runner_group_id":0,"runner_group_name":"GitHub Actions","steps":[],"conclusion":"failure","started_at":"2026-10-11T03:46:49Z","completed_at":"2026-10-11T03:46:49Z"}
```

### Documented basis

- **[documented]** Workflow syntax, `jobs.<job_id>.runs-on`
  (https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idruns-on,
  fetched 2026-10-11): **"Runner groups can only have larger runners or
  self-hosted runners as members."** Group addressing therefore cannot select
  standard GitHub-hosted pool runners such as `ubuntu-24.04`.
- **[documented]** Same page, "Choosing GitHub-hosted runners": "If you use a
  GitHub-hosted runner, each job runs in a fresh instance of a runner image
  specified by `runs-on`. The value for runs-on, when you are using a
  GitHub-hosted runner, is a workflow label or the name of a runner group."
  (The "runner group" half is satisfied only by larger runners — per the
  previous quote, standard-pool runners are not group members, so for them
  the value is a workflow label.)
- **[documented]** Managing access to self-hosted runners using groups
  (https://docs.github.com/en/actions/hosting-your-own-runners/managing-access-to-self-hosted-runners-using-groups):
  "You can use policies to limit access to self-hosted runners that have been
  added to an organization." — runner groups are an access-control unit for
  self-hosted (and larger) runners, not a name for the standard hosted pool.
- **[documented↔measured mismatch]** The REST job schema documents all four
  runner fields as null-when-unassigned — OpenAPI description
  (`github/rest-api-description`, WorkflowJob; the source of the
  docs.github.com REST reference): `runner_name` — "The name of the runner to
  which this job has been assigned. (If a runner hasn't yet been assigned,
  this will be null.)"; same sentence shape for `runner_id`,
  `runner_group_id`, `runner_group_name`. We measured `""` and `0` (typed
  zero values, not `null`), and `runner_group_name: "GitHub Actions"` on a
  job whose `runner_group_id` is `0` — a pre-dispatch failure reports a group
  *display name* rather than `null`.

### Cause

`runner_group_name: "GitHub Actions"` in the job object is the display bucket
of the standard GitHub-hosted pool, not a runner group that exists in the org
(groups can only contain larger/self-hosted runners — documented above).
Writing `runs-on: {group: "GitHub Actions", labels: ["ubuntu-24.04"]}` makes
the scheduler resolve an actual org/enterprise runner group of that name,
which does not exist → `Required runner group 'GitHub Actions' not found` →
the job dies at template/scheduling time with `runner_id: 0`, `steps: []`.

### Sanctioned workaround

- Address GitHub-hosted runners by label only: `runs-on: <string>` or
  `runs-on: [<string>, ...]`.
- Use `{group:, labels:}` confinement only against real runner groups
  (larger/self-hosted), and verify confinement **post-hoc** via the job's
  `runner_group_id` — never via `runner_group_name` (display name, and
  non-null even when unassigned, per the mismatch above).
- Shipped fix in this workflow generation:
  `runs-on: [ "${{ fromJSON(vars.CI_RUNNER_MAP).x64 }}" ]` — **[documented]**
  `vars` is an allowed context for `jobs.<job_id>.runs-on`
  (https://docs.github.com/en/actions/learn-github-actions/contexts, context
  availability table: `github, needs, strategy, matrix, vars, inputs`).

---

## Q2 — org required workflow: `${{ vars.* }}` resolves against `github.repository` (the TARGET repo), not the repo owning the YAML

### Symptom [measured]

Probe step inside `Archright/.github/.github/workflows/admission-gate.yml`
running as an organization required workflow on `Archright/Axiom`
(2026-10-11):

```
github.repository   = Archright/Axiom
github.workflow     = admission-gate
github.workflow_ref = Archright/.github/.github/workflows/admission-gate.yml@main
vars.CI_RUNNER_MAP  = '[{"mode":"ghec",...,"group":"GitHub Actions","x64":"ubuntu-24.04",...}]'
vars.CI_RUNNER_MAP empty? = false
```

Control case **[measured]**: the same expression executed as
`Archright/.github`'s OWN `workflow_dispatch` produced a hard `fromJSON('')`
failure at template evaluation:

```
##[error]The template is not valid. … Error reading JToken from JsonReader. Path '', line 0, position 0.
```

The org `.github` repository defines no `CI_RUNNER_MAP` repository variable,
so `vars.CI_RUNNER_MAP` is `''` there.

### Documented basis

- **[documented]** Contexts reference
  (https://docs.github.com/en/actions/learn-github-actions/contexts),
  `vars` context: "The vars context contains custom configuration variables
  set at the organization, repository, and environment levels." The levels
  are those of the RUN's repository — `github.repository` — which for a
  required workflow is the enforcement target, not the YAML source repo.
- **[documented]** Same page: `github.repository` — "The owner and repository
  name. For example, octocat/Hello-World." and `github.workflow_ref` — "The
  ref path to the workflow. For example,
  octocat/hello-world/.github/workflows/my-workflow.yml@refs/heads/my_branch."
  The measured pair (`github.repository` = target repo while
  `workflow_ref` = org `.github` path) is exactly this split between run
  context and workflow-file identity.
- **[documented]** The cross-repo ownership of a required workflow is the
  documented ruleset model: REST rules — workflows rule parameter
  `repository_id` (integer, Required) — "The ID of the repository where the
  workflow is defined"
  (https://docs.github.com/en/rest/repos/rules). The YAML lives in
  `Archright/.github`; the run happens in each enforced repository.
- **[documented]** Same contexts page: "If a configuration variable has not
  been set, the return value of a context referencing the variable will be an
  empty string." — the control case's precondition (`vars.CI_RUNNER_MAP ==
  ''` in the source repo's own run).
- **[measured]** `fromJSON` of an empty value fails at TEMPLATE EVALUATION
  time, so the job never starts (control case error above; measured
  fail-closed property). No failure semantics for empty `fromJSON` input are
  documented in the references fetched 2026-10-11 — measured-only.

### Implication / Sanctioned workaround

- ONE repository-level variable (`CI_RUNNER_MAP` on the enforcement target
  repository) covers the org required workflow for every enforced
  repository's runs. Do NOT duplicate the mapping as a variable on the org
  `.github` source repo — required-workflow runs never read it (control
  case), and duplicated semantic state violates single-authority.
- `fromJSON(vars.X)` in `runs-on` is fail-closed: a missing/empty variable
  kills the job at template evaluation — the job never starts, so no partial
  or default routing occurs silently.

---

## Q3 — a branch whose PR is in the merge queue cannot be updated

### Symptom [measured]

`git push` to `feat/ci-runner-map-routing` while PR Archright/Axiom#729 was
queued (2026-10-11):

```
remote: error: GH013: Repository rule violations found …
remote: - A pull request for this branch has been added to a merge queue. Branches that
remote:   are queued for merging cannot be updated. To modify this branch, dequeue the
remote:   associated pull request.
```

`gh pr merge --disable-auto` did NOT dequeue the PR — it responded "already
queued to merge" **[measured]**. **[documented]** The gh manual defines the
flag narrowly — `--disable-auto` "Disable auto-merge for this pull request"
(https://cli.github.com/manual/gh_pr_merge) — with no merge-queue dequeue
semantics; do not reach for it as a dequeue primitive.

### Documented basis

- **[documented]** Managing a merge queue
  (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue):
  the removal reasons list includes "User requesting a removal via the API or
  merge queue interface" — dequeue is a first-class operation, via API or UI.
- **[documented]** GraphQL mutation `dequeuePullRequest` — "Removes a pull
  request from the merge queue"
  (https://docs.github.com/en/graphql/reference/mutations#dequeuepullrequest).
  Input object introspected from the live schema 2026-10-11
  (`gh api graphql`, `__type(name: "DequeuePullRequestInput")`): fields
  `clientMutationId` and **`id`** — "The ID of the pull request to be
  dequeued." The input field is `id` (the PR node id), NOT `pullRequestId`:
  `enqueuePullRequest` takes `pullRequestId` (introspected:
  `clientMutationId, pullRequestId, jump, expectedHeadOid`), `dequeuePullRequest`
  does not. Context7's rendered example for `dequeuePullRequest` shows
  `pullRequestId` — wrong against the live schema; introspection is
  authoritative.

### Sanctioned workaround

```bash
PR_ID=$(gh pr view 729 --json id --jq .id)
gh api graphql -f query='mutation($id:ID!){ dequeuePullRequest(input:{id:$id}){ mergeQueueEntry{ id } } }' -f id="$PR_ID"
```

After the entry is removed, `git push` to the branch succeeds; re-enter the
queue with `gh pr merge --auto` when ready (re-queuing is the documented
add path; `gh run rerun` is NOT a re-entry —
`docs/spec/gh_run_observation_quirks.md` Q5/Q6).

---

## Q4 — re-run endpoints: undocumented 403 on non-terminal runs; `rerun-failed-jobs` DOES re-run never-started (0-step) failures

### Symptom [measured]

`POST /repos/Archright/Axiom/actions/runs/38110128893/rerun-failed-jobs`
while the run was `in_progress` (2026-10-11):

```
403 {"message":"This workflow is already running"}
```

**[documented↔measured mismatch]** The REST reference documents ONLY `201`
for this endpoint — "HTTP response status codes for 'Re-run failed jobs from
a workflow run': 201 Created"
(https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28,
fetched 2026-10-11). `403` is documented only for the job-scoped `POST
/repos/{owner}/{repo}/actions/jobs/{job_id}/rerun` ("201 Created / 403
Forbidden"), not for the run-scoped rerun or rerun-failed-jobs endpoints.
The in-progress 403 is real but undocumented: treat non-201 as
retry-after-terminal, not as a permissions failure.

### Post-terminal behavior [measured]

After the run reached `completed`, the same call returned `201` and DID
re-run `closure-deriver` — a job whose attempt-1 object had `runner_id: 0`,
`steps: []` (never started; failure conclusion from Q1's template-time
failure). The re-run attempt executed it with `runner_id: 1000016520` and
9 steps.

- **[documented]** Endpoint contract: "Re-run all of the failed jobs and
  their dependent jobs in a workflow run using the id of the workflow run"
  (same REST page). That never-started (0-step) failed jobs count as "failed
  jobs" is consistent with, but not explicitly stated by, the docs — the
  inclusion property above is **[measured]**.
- **[documented]** Re-runs replay the original event identity: "Re-runs use
  the privileges of the actor who initially triggered the workflow … The
  workflow will also use the same GITHUB_SHA (commit SHA) and GITHUB_REF (git
  ref) of the original event that triggered the workflow run."
  (https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/re-running-workflows-and-jobs)
  — same semantics as `docs/spec/gh_run_observation_quirks.md` Q5.

### At-most-once attempt oracle — [documented↔measured match]

Measured: `run_attempt` advanced 1 → 2, and `previous_attempt_url` pointed at
`.../runs/38110128893/attempts/1`.

- **[documented]** Contexts reference, `github.run_attempt`: "A unique number
  for each attempt of a particular workflow run in a repository. This number
  begins at 1 for the workflow run's first attempt, and increments with each
  re-run."
- **[documented]** The REST run object carries both fields
  ("run_attempt": 1, "previous_attempt_url":
  ".../actions/runs/<run_id>/attempts/1" in the "Get a workflow run" response
  example). This is the sanctioned idempotence oracle: the run id is stable
  across attempts and `run_attempt` strictly increments, so at-most-once
  triggering is assertable per `(run_id, run_attempt)`.
- **[documented]** Bound: "A workflow run can be re-run a maximum of 50
  times. This limit includes both full re-runs and re-runs of a subset of
  jobs." (same re-running page).

---

## Deterministic rules

1. GitHub-hosted runners are addressed by label (`runs-on: <string|list>`);
   `runs-on: {group:}` is reserved for real larger/self-hosted runner groups
   and is verified post-hoc via `runner_group_id`.
2. Required-workflow configuration via `vars` is defined on the enforcement
   target repository (`github.repository`); one repo-level variable covers
   the org required workflow — no duplicated state in the org `.github` repo.
3. A queued PR's branch is frozen; the only API dequeue is GraphQL
   `dequeuePullRequest(input: {id: <PR node id>})`.
4. Rerun calls on a non-terminal run may return the undocumented
   `403 {"message":"This workflow is already running"}` — retry only after
   `status == completed`; `rerun-failed-jobs` re-runs all failed jobs
   including never-started ones; identity/at-most-once is asserted via
   `(run_id, run_attempt, previous_attempt_url)`.
5. `CI_RUNNER_MAP` label fields are pinned per mode by the router schema
   (provider policy table, `docs/spec/ci_provider_failover_quirks.md` Q14):
   `ghec` → `ubuntu-24.04`/`ubuntu-slim`/`ubuntu-24.04-arm`; `ubicloud` →
   `ubicloud-standard-2`/`ubicloud-standard-2`/`ubicloud-standard-2-arm`;
   `ovh` → `ci-axiom-x64`/`ci-axiom-x64`/`ubicloud-standard-2-arm` — the OVH
   control plane JIT-registers only the `ci-axiom-x64` x64 label, so `arm64`
   keeps the existing Ubicloud arm label. Consumers keep addressing runners
   via `fromJSON(vars.CI_RUNNER_MAP).x64`: a provider switch is a variable
   write, never a workflow edit.
