# LFS Smudge in Credential-Free Isolation Steps Quirk

**Discovered**: 2026-11-07 (Axiom PR #6, generation-acceptance run 42351952953, job
`generation-acceptance`, step `[L4-iso] isolated — the candidate's own monitor must
also reject the known-bad fixture`)
**Class**: git-lfs × GitHub Actions credential isolation × private repository
**Invariant**: a step that deliberately strips every credential (`GH_TOKEN`,
`GITHUB_TOKEN`, `ACTIONS_RUNTIME_TOKEN`, `AXIOM_DIAG_TOKEN` all empty) must not
invoke a command whose success requires repository authentication. `git worktree
add` on a tree containing LFS pointers is such a command in a private repository:
the smudge filter resolves each pointer against the LFS HTTP endpoint and needs
auth. The 2026-11-07 first-ever `monitor_changed` run failed by construction with
`fatal: could not read Username for 'https://github.com': No such device or
address` while smudging `docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`
(10 MB). The `actions/checkout` of `candidate/` does not populate the local LFS
object store (checkout without `lfs: true` leaves pointers), so the smudge cannot
be served from cache either.

## Symptom

`git -C candidate worktree add --detach <path> HEAD` fails inside the isolated
step with the "could not read Username" fatal; the L4-iso result is
`REJECTED:SELF_TEST_FAILED` ("후보 트리를 격리 위치에 materialize하지 못했다")
for every PR that changes `tools/merge_ruleset_drift_monitor.nim`, regardless of
the change's content.

## Cause

The isolation design (correctly) removes credentials so the candidate-built
monitor cannot reach the network during its self-test. `git worktree add`
performs a full checkout, and each LFS pointer in the checked-out tree triggers
the smudge filter, which — with no local object and no credential — attempts an
authenticated HTTPS fetch to the LFS endpoint and dies. The LFS payload is never
a judgment input for L4-iso (the isolated step only compiles Nim sources and
compares generated JSON fixtures), so requiring it is an environment defect, not
a security property. The security property — no credential, no network reach
from the candidate monitor — is unaffected by skipping the smudge.

## Resolution

Set `GIT_LFS_SKIP_SMUDGE=1` for the `worktree add` in the L4-iso step
(`.github/workflows/generation-acceptance.yml`). Pointer files are materialized
as-is; the isolated build and fixture comparison are unaffected. The isolation
(no credentials) is preserved exactly — the smudge simply no longer needs
network access.

## Scope

Any future step that pairs (a) deliberately stripped credentials with (b) a git
operation that materializes an LFS-pointer tree (`worktree add`, `checkout` of a
tree containing pointers, `git archive` post-processing) in a private repository.
Local worktrees of the main clone do not hit this: the shared object store
already contains the LFS objects, so the smudge is cache-served without network.
