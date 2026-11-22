# Rearm wake-up canary — 2026-11-22

**Status**: Functional-acceptance canary for ADR-0027 Amendment F. This PR is not
intended to merge; it is closed after the wake-up observations are recorded.

**What it exercises**: the two wake-up paths of
`.github/workflows/merge-queue-rearm.yml` — `pull_request_target[dequeued]` and
`workflow_run[completed]` for the `admission-gate` workflow. The decision function
must re-read GitHub state on either signal, bind the run to
(repository, PR, head, merge-group SHA, run_id, run_attempt), and emit `no-arm`
for an ineligible PR.

**Expected outcome**: at least one `workflow_run` rearm run whose log carries this
PR number and the merge-group SHA, plus one `dequeued` run; `action=no-arm` in
both; zero `rearm-intent@`/`rearmed@` labels; zero auto-merge registrations. With
`REARM_APP_PRIVATE_KEY` unprovisioned, any arm path is fail-safe `token-missing`.

**Cross-reference**: `docs/adr/0027-queue-delegation.md` Amendment F,
`docs/spec/rearm_recovery_status.md` section 4, and the PR that landed the
workflow.
