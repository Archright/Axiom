# Admission, readiness, and release claim are three separate authorities

Status: contract. Applies to every decision Axiom publishes about a commit.

## Why this document exists

A single GO/NO-GO has been asked to answer three different questions:

1. May this change become part of canonical main?
2. Does the product meet the verification scope it claims?
3. May we tell a customer that this scope was verified?

These have different owners, different failure consequences, and different
legitimate answers. Collapsing them produces two opposite errors: blocking all
development because verification density is low, or advertising a verified
product because a PR merged.

## The three questions and their authorities

| Question | Authority | Venue | Failure consequence |
|---|---|---|---|
| Merge admission | GitHub rulesets + the independent App's required verdict | `PUT /pulls/{n}/merge` or the merge queue | the merge does not happen |
| Verification readiness | `tools/readiness_evaluator.nim` over collected R1–R8 evidence | CI run, artifact | a recorded verdict, no merge effect |
| Release / claim | release gate against the readiness verdict | release procedure | no release, no external claim |

Merge admission is **not** a statement that the product is verified, and a
successful merge is **not** permission to claim verification. Each row fails
closed on its own.

## CONDITIONAL GO

`CONDITIONAL GO` means: the required admission checks passed and the known
non-critical conditions are published. It **permits a merge** and **does not
permit a verified-scope claim**. It is not an unconditional merge allowance:
R7 items must be classified by actual risk, and any item that is a trust
invariant violation must be moved into the blocking set rather than carried as
a condition.

Measured on main `db20f176` (fresh, full-scope, run 44248226884):

| Quantity | Value |
|---|---|
| `runOutcome.verdict` | `FAIL` |
| `verificationComplete` | `false` |
| readiness projection | `UNKNOWN`, reasons include `vda-not-pass`, `scope-coverage-incomplete` |
| `verdict / admission-check` | `success` |

Both facts are true simultaneously and are not in tension: admission passed
while the proof did not. Reading the green check as "the product is verified"
would be a false claim; reading the red proof as "the merge must be blocked"
would halt work that the contract explicitly permits.

## VKD is a target, not a current score

`config/readiness_policy.json#/r7/vkdContract` defines:

```
VKD = |VKS ∩ certGreen| / |VKS|
VKS = kernel 40 − exempt 17 = 23
valueIsTargetOnly = true
```

Two distinct numbers are easy to confuse and must not be conflated:

- **23** — the VKD denominator (`vksSize`), derived as `kernel 40 − exempt 17`.
- **23** — the count of kernel symbols not accounted for in scope coverage
  (`data/verification_scope.lock` declares 40; the fresh run accounted 17,
  missing 23).

They arise from different computations. `vksDerivation` is a subtraction of
exempt symbols; coverage missing is the set difference between declared kernel
symbols and symbols observed in the run's accounting surfaces. Equal values
here are a coincidence of this snapshot, not an identity.

`valueIsTargetOnly: true` means the current VKD may not be presented as an
achieved score, and no VKD threshold may be introduced as a merge blocker
without a policy decision that defines the symbol set, per-symbol risk, and
target density.

## What may be claimed today

- Merged: yes, with the published non-critical conditions attached.
- "Axiom formally verified this kernel scope": **no**. Five units are
  classified, one is `UNSATISFIED` (`orchestrator_vault.nim::safeSpeedupRatioCore`,
  unsupported IR — DEBT#547), and 23 of 40 declared symbols are unaccounted.
- "Axiom's admission path is enforced by an independent judge": yes, when the
  App's `admission-check` (integration 5795152) is the required context — see
  `docs/evidence/ruleset_ab_split_2026-11-18/`.

## Enforcement reality, measured

Only the seven contexts registered in ruleset `main` (27097366) and
`main-admission` (27525972) block a merge. `repository-surface` is not among
them: a FROZEN verdict from that guard is advisory. Trust-surface protection
therefore holds exactly on the paths covered by the App's own list, not on
every FROZEN path in `config/repository_surface.json`.

This is recorded as a fact about the current system, not as a design
endorsement. Closing it is DEBT#558.