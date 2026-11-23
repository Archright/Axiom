# Rotation allowlist prereg -- ax help SSOT companion, 1 path (ADR-0025 Amendment A9)

> **Status**: prereg. This document fixes the basis, scope, and **authorization delta** of a rotation companion-set expansion **before it lands**.
> **Created**: 2026-11-23
> **Target PR**: #326 (`fix(cli): align ax help table with parser-accepted subcommands`, head `b675d8d8`)
> **Measured verdict**: merge_group `admission-gate` run `45102830835` (2026-11-23T03:02:16Z), `reasonCode=ROT_ALLOWLIST`
> **Amended document**: ADR-0025 Amendment A9 (`docs/adr/0025-gateway-landing-authority.md`)

## Section 1. Measured facts (observed before landing)

The verdict emitted by the landing venue for the PR #326 merge group
(`baseSha=759b87367f76b78ed5fe1f80628bd2c9cec6ce8f`,
`headSha=b675d8d8cb997138c6d46fd841c21eba112c55a7`), quoted from the
`admission-gate` job log:

```json
{"prNumber":326,
 "headSha":"b675d8d8cb997138c6d46fd841c21eba112c55a7",
 "baseSha":"759b87367f76b78ed5fe1f80628bd2c9cec6ce8f",
 "qualification":"NONE",
 "reasonCode":"ROT_ALLOWLIST",
 "rotationCheck":{"closureChange":true,
   "changed":["Makefile",
              "config/trusted_checker_closure.json",
              "src/cli/action_plan_cli.nim",
              "tests/cli/test_ax_help.nim"],
   "allowlistOk":false,
   "subjectDeltaZero":false,
   "genesis":false,
   "oldAnchorOk":true,
   "newAnchorOk":true,
   "delegatedToPlatform":true},
 "judge":{"source":"9ab6c025026326fe323f15751872862218b2389a0b90c36a529d1967f6ad4ef6"}}
```

Paths already inside the allow set (3):

| Path | Class |
|---|---|
| `Makefile` | A2 companion (registered in `RotationAllowlistExtra`) |
| `config/trusted_checker_closure.json` | A2 companion -- the pin file itself |
| `src/cli/action_plan_cli.nim` | closure member (pin@B key) |

**Paths outside the allow set (1)** -- the object this amendment registers:

1. `tests/cli/test_ax_help.nim`

**Venue asymmetry (measured, not argued).** The same head `b675d8d8` is `success`
at the `pull_request` venue (`admission-check`) and `failure` at the landing venue
(`admission-gate`). The rotation predicate is evaluated on the landing venue only.
A8 recorded the same asymmetry.

**Anchor state.** `oldAnchorOk=true` and `newAnchorOk=true`, so neither anchor
condition is involved: the deny is (1) alone, not (3) or (4).

## Section 2. Rotation subject and product defect (why #326 is a rotation)

The rotation is caused by a change to `src/cli/action_plan_cli.nim`, a closure member:

- The `axCommandHelpEntries` table (the `ax --help` SSOT) advertised subcommands that
  `parseAxSubcommandKind` does not accept, and omitted ones it does.
- PR #326 aligns the table with the parser-accepted set, so the help surface stops
  describing a CLI that does not exist.
- A closure member changed, so `closureChange=true` and the landing venue classifies
  the delta as ROTATION (ADR-0025 A2 (ii)).

## Section 3. Companion-path classification

| Path | Class | Basis |
|---|---|---|
| `tests/cli/test_ax_help.nim` | rotation-member unit contract | `staticRead`s `src/cli/action_plan_cli.nim` and asserts the help-table key set equals the parser-accepted key set. The rotation turns red without the companion by construction -- same class as `tests/cli/test_axiom_status.nim` / `test_cert_cli.nim` / `test_config_cli.nim` in A8 (ii). |

**Not production `src/`**: the registered path is not under `src/`. It is unrelated to
the A2 (i) "non-member production src/ prohibited" class.

## Section 4. Authorization delta -- stated as an expansion, not as a non-expansion

A8 Section 4 argued non-expansion from A2 (ii). **That argument does not carry for A9**,
and this section records why rather than repeating it:

- (1) A2 (ii) establishes that clause (1) is evaluated only on the ROTATION path, so
  NORMAL-path classification of `tests/cli/test_ax_help.nim` is unchanged. That is a
  statement about the NORMAL path only.
- It does **not** follow that the ROTATION approval scope is unchanged. Registering a
  path in `RotationAllowlistExtra` widens the set of paths a ROTATION candidate delta
  may carry. Within ROTATION, this registration admits exactly one new path.
- Two distinct contracts are involved and must not be conflated: the trust-surface
  18-path manifest (protected *identity* of files) and the rotation allowlist (which
  paths a *rotation* delta may carry). `pathSetDigest` staying constant is evidence
  about the manifest path set only; it is not evidence about the rotation allowlist.

A9 is therefore recorded as **an authorization expansion of exactly one path**.

### Section 4.1 The bound, proven by negative tests

The bound is proven, not asserted. Suite
`adjudicateRotation -- Amendment A9 rotation companion (ax help SSOT)` in
`tests/cli/test_merge_cli.nim` (4 tests, all green at head):

| Test | What it falsifies if it fails |
|---|---|
| `PR #326's candidate delta (4 paths) -> ROTATION (allowlist OK)` | the registration does not actually admit the measured delta |
| `A9 admits one enumerated path -- an unregistered test stays ROT_ALLOWLIST` | the registration would act as a glob (`tests/cli/**`) |
| `A9 is inert outside ROTATION -- a NORMAL delta gains no approval` | the registration would authorize NORMAL deltas (A2 (ii) violation) |
| `A9 leaves (4) untouched -- a stale pin@H is still annotated ROT_NEW_PIN` | the registration would suppress the new-anchor condition |

The fourth test pins the layer boundary: (4) is a classification-independent FACT that
never denies inside `adjudicateRotation`; its single policy deny site is Pass 2.75 in
`MergeAdmissible`. The test therefore asserts the annotation, and asserts that
re-anchoring pin@H is the only difference from a clean verdict.

## Section 5. Scope bound

- This amendment restores only the **landability** of #326. The product verdict of #326
  (the help table advertises exactly the parser-accepted subcommands) is a separate
  acceptance target.
- The expansion PR itself changes `src/cli/merge_cli.nim`, a trustSurface member
  (`config/policy/merge_admission.json` trustSurface index [9]). `dryRunExit` maps
  `TRUST_SURFACE_MODIFIED` to exit 0, so the queue can land it. A8's ADR text predicted
  the MUST-T2a manual lane; the observed record for the A6/A7/A8 expansions (#317,
  #245, #192) is `added_to_merge_queue -> merged` with `merged_by=wintrover`. The
  observation governs, and A9 states the mechanism instead of the prediction.
- The closure pin `config/trusted_checker_closure.json` is re-anchored for
  `src/cli/merge_cli.nim` in this same commit (ADR-0025 section 7, item 4 match). A
  partial re-anchor stays fail-closed (`ROT_NEW_PIN`).

## Section 6. What this document does not establish

| Item | Status |
|---|---|
| `App Owner` role for the out-of-tree `axiom-admission-verifier` | **UNKNOWN** -- not established by this repository and not claimed here |
| That #326 passes the other six required contexts | not claimed; the merge_group run is the authority |
| That the A2 allowlist is complete for future rotations | not claimed. A2-A9 have each repaired one measured omission; the recurrence is tracked as technical debt, not fixed here |

## Section 7. Approval record

| Item | Value |
|---|---|
| Approver | wintrover (owner, sole `@Archright/architect`) |
| Approval date | 2026-11-23 |
| Approval basis | session-level explicit authorization to resolve all six open PRs without weakening the trust contract (2026-11-23), plus the measured PR #326 merge_group verdict (`ROT_ALLOWLIST`, 1 of 4 changed paths blocked, run `45102830835`) |
| Executor | agent (per-PR explicit delegation). Not recorded as human keystrokes. |