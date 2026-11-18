# Ruleset A/B split — measurement record (VS-1 T3)

Date: 2026-11-18
Operator transaction: rulesets API only. No source change, no PR, no bypass.

## Why

T2 established, by measurement rather than inference, that a branch ruleset's
`bypass_actors` does **not** apply to the merge queue venue — in either
`pull_request` or `always` mode. The queue removed merge groups whose required
checks failed even while a bypass actor was configured.

That fact made a different shape possible: put the merge controls that must
never be relaxed in one ruleset, and the judgement that a human architect may
sometimes need to rotate in another. The two are then independently
enforceable.

## Before

One ruleset, `main` (27097366), active, `bypass_actors: []`, carrying all five
rules — `deletion`, `non_fast_forward`, `pull_request`, `required_status_checks`
(7 contexts) and `merge_queue`.

Required contexts and their producers, as configured:

| Context | integration_id | Producer |
|---|---|---|
| admission-check | 5795152 | `axiom-admission-verifier` (independent App) |
| bsec-integrity | 15368 | GitHub Actions |
| debt-registry-gate | 15368 | GitHub Actions |
| generation-acceptance | 15368 | GitHub Actions |
| axiom-operational-slice | 15368 | GitHub Actions |
| publication-integrity | 15368 | GitHub Actions |
| readiness-verdict | 15368 | GitHub Actions |

## After

**A — `main` (27097366), active, `bypass_actors: []`, unchanged rules, 6 contexts.**
`deletion`, `non_fast_forward`, `pull_request`, `merge_queue` and the six
Actions contexts remain. This is the invariant merge control: no bypass actor
exists on it in any mode, and the queue enforces it.

**B — `main-admission` (27525972), active, `bypass_actors: []`, one context.**
`admission-check` with `integration_id: 5795152` only, so the rule cannot be
satisfied by the same-named Actions check run.

## Readback (not a claim — the API's answer)

`GET /repos/Archright/Axiom/rules/branches/main` returns, in the same response:

```
deletion             27097366
non_fast_forward     27097366
pull_request         27097366
required_status_checks 27097366   (6 Actions contexts)
required_status_checks 27525972   (admission-check @ 5795152)
merge_queue          27097366
```

Raw responses: `raw/A_before.json`, `raw/A_after.json`, `raw/B_created.json`,
`raw/branch_rules_after.json`.

## What this does and does not guarantee

It guarantees that the invariant controls live on a ruleset with no bypass
actor, and that App judgement lives on a separate one. It does **not** yet
prove that disabling B leaves A's enforcement intact for a real merge — that
requires an observed transaction, and is recorded separately when performed.

## Adjacent fact found while reading the rulesets

`repository-surface` is not among any ruleset's required contexts. The
repository surface guard therefore reports a verdict that does not block a
merge. The declared FROZEN class is merge-enforced only where the independent
App's own trust-surface list covers the path; for other FROZEN paths the guard
is advisory. This is recorded here because it changes what "protected" means in
this repository, and it is not visible from the guard's own output.

Of the 17 paths in `config/policy/trust_surface_manifest.json`, 16 are FROZEN
with no exception registered and one (`config/trusted_writer_set.json`) is
CONTROLLED. The App published `failure` on commit `2dfc314`
("policy(surface): register fresh-prove-observation workflow (v103)") — a
surface-policy self-amendment — and that commit is in main. The self-amendment
channel satisfies the repository guard but not the App, which is the concrete
shape of DEBT#558.