# Shallow Checkout Graft Quirk (actions/checkout fetch-depth)

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks live in
> `docs/spec/`. This file documents the GitHub Actions `actions/checkout`
> shallow-fetch semantics that silently truncate parent visibility in git
> object computations, and the fail-closed contract adopted for
> `tools/ci/verify_landing_recomputed.sh` (ADR-0022 Revision, Slice 5).

## Scope

The canonical-main bind recomputes landing shape (L0) from git objects:
`git rev-list --parents -n 1 H` must yield exactly `H H^1 H^2` for a valid
merge landing. This depends on parent objects of H being present in the
runner's clone.

## The Quirk

### Q1 — `fetch-depth` defaults to 1 (shallow), silently

`actions/checkout` fetches **only the single commit** for the requested ref
unless `fetch-depth: 0` is set explicitly (actions/checkout README: "The
`fetch-depth` input specifies the number of commits to fetch, with `0`
indicating all history ... It defaults to `1`").

### Q2 — shallow graft truncates `rev-list --parents` to H alone

On a shallow clone, the commit H listed in `.git/shallow` is grafted: its
parents are not downloaded and `rev-list --parents -n 1 H` returns **only H**
(parent count 0), with **exit code 0**. A real 2-parent merge commit is
therefore indistinguishable from a 1-parent commit by parent count alone in
that environment.

Observed 2026-09-14: landing `f7818d6a066840d8a9909cd5f55c4bebd2902700` (a
real merge of `17bb90c7e` + `05f20500d`, PR #79) failed canonical-main bind
with `L0_NOT_MERGE_COMMIT — parent count = 0` because the bind job's
checkout used the default depth.

Locally reproduced: `git clone --depth 1` of a repo whose HEAD is a merge
commit returns 1 word (`H` itself) from `rev-list --parents -n 1 H`.

### Q3 — `rev-parse H^1` also fails under the graft, so it is the discriminator

Because the parent objects are absent, `git rev-parse -q --verify "H^1"`
fails in the shallow clone but succeeds in a full clone. This gives the
bind an environment-vs-verdict distinction:

- parents unreadable **and** H is in `.git/shallow` → `L0_PARENTS_UNREADABLE`
  (environment defect, fail-closed; not a merge-shape verdict)
- parents countable and != 2 → `L0_NOT_MERGE_COMMIT` (genuine verdict)

## The Contract

- `canonical-main.yml` bind job checkout sets `fetch-depth: 0`.
- `verify_landing_recomputed.sh` L0 never reports an unreadable environment
  as a merge-shape verdict: shallow-graft detection produces
  `L0_PARENTS_UNREADABLE` and exits non-zero (fail-closed).
- Golden case (k) in `tools/ci/test_verify_landing_recomputed.sh` pins this:
  a depth-1 clone of a repo whose HEAD is a genuine merge commit must fail
  with `L0_PARENTS_UNREADABLE`, never `L0_NOT_MERGE_COMMIT`.
