# Evidence CAS pre-activation baseline — PR #493 landing latency (2026-10-06)

## What this record is

Wall-clock baseline of the PR→main landing cycle measured on the landing that
activated the identity-keyed evidence reuse slice (Axiom #493, SL-15
promotion). PR #493's own admission runs executed with SL-15 **NO-FIRE** (the
base B-manifest it ran against predated the promotion), so these numbers are
the honest pre-Evidence-CAS baseline that the Terminal Outcome target
(HIT-path wall ≤ 8 min, P95 of 3) is measured against.

The activation choreography (org callee SHA pins):

- Axiom main received the slice as merge commit `ac8abb407` (PR #493,
  merged 2026-10-06T03:44:12Z).
- `Archright/.github` PR #50 (merge commit `5e295ea3`, merged
  2026-10-06T03:49:00Z) rotated the 4 callee pins — `admission-check.yml`
  ×2 and `certificate-mint.yml` ×2 — from `692056d1`/`db9afe5a` to
  `ac8abb407`. Until that merge the new callees did not fire; PRs landing
  after it run against the new generation.

## Measurements (all times UTC, 2026-10-06, PR #493)

| phase | run | start | end | wall |
|---|---|---|---|---|
| pull_request admission (checks phase) | `37408386931` | 03:18:50 | 03:30:50 | 12m00s |
| merge_group admission (queue phase) | `37409364909` | 03:31:17 | 03:43:45 | 12m28s |
| enqueue → merge | — | 03:30:58 | 03:44:12 | 13m14s |
| PR opened → main | — | 03:18:50 | 03:44:12 | 25m22s |

Both admission runs concluded `success`; the merge landed 27s after the
merge_group run went green. The plan's measured precedent (PR 10m19s /
merge_group ~12m, `docs/evidence/` 2026-10-04 records) is consistent with
these walls.

## Production incident — first post-rotation run failed fail-closed (this PR)

The org pin rotation (`.github` #50) made SL-15 armed on every subsequent
PR. Axiom #494 was the first such PR, and its `pull_request` admission run
(`37411306727` attempt 1, `37413340194` attempt 2) failed exactly at the
armed CAS branch: the witness-only attest step has no `GITHUB_TOKEN` in its
env, and the orchestrator refuses the ledger side-ref READ fail-closed
(`evidence CAS enabled: GITHUB_TOKEN not set`). The fail-closed behavior is
correct — the wiring was incomplete, not the policy.

Two structural facts drove the recovery:

1. The org wrapper executes the callee from the SHA-pinned main commit, so
   the fix carried on #494's branch is inert for #494's own checks
   (chicken-and-egg; the DEBT#480 pin structure working as designed).
2. The epoch gate caught the fix commit's callee-blob change against the
   TWS/manifest pins and forced the atomic rebind
   (`EPOCH_TRANSACTION_INCONSISTENT` → rebind to blob `012afc4d82…`).

Recovery choreography (documented, reversible, no required-check bypass):

- `.github` PR #51 (merge commit `9e7af82f`, 04:37Z): temporary rollback of
  the 4 callee pins to the pre-SL15 generation, returning admission to the
  NO-FIRE state that held before 03:49Z.
- Axiom #494 re-runs NO-FIRE and lands the token wiring fix + pin rebind on
  main; a forward `.github` rotation to the fixed main re-activates SL-15.

## Not exercised here

- SL-15 HIT/MISS behavior: NO-FIRE on every run of this PR (promotion
  rollout defect above). The first post-re-rotation PR is the MISS/HIT
  observation vehicle: its `pull_request` run (new semantic identity →
  MISS) and its own `merge_group` run (same tree → HIT) are the two
  production paths the Terminal Outcome requires to be observed on main.
- Fail-closed tamper path in production: covered by the slice's local
  metamorphic and ledger tests (T1–T5, E1–E8, negative/positive key
  variations); no production side-ref was mutated to trigger it.
