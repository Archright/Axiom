# Rotation allowlist prereg -- obligation-count rotation companions, 5 paths (ADR-0025 Amendment A8)

> **Status**: prereg. This document fixes the basis, scope, and non-expansion argument of a rotation companion-set expansion **before it lands**.
> **Created**: 2026-11-21
> **Target PR**: #287 (`fix(batch-uap): keep obligation counts and rank the declared projection (DEBT#423/#487)`, head `a130d0b`)
> **Measured verdict**: merge_group run `44882710554` (2026-11-21T08:07Z), `reasonCode=ROT_ALLOWLIST`
> **Amended document**: ADR-0025 Amendment A8 (`docs/adr/0025-gateway-landing-authority.md`)

## Section 1. Measured facts (observed before landing)

The `rotationCheck` observed in the PR #287 merge_group verdict:

```json
{
  "closureChange": true,
  "changed": [
    "config/trusted_checker_closure.json",
    "data/architecture_debt.json",
    "data/debt_reduction_baseline.json",
    "data/nimtry_baseline.json",
    "src/generated/type_registry_metadata.json",
    "src/verification/batch_uap/ir_pipeline_runner.nim",
    "tests/unit/test_hotspot_ranker.nim",
    "tests/unit/test_ir_pipeline_theaterguard.nim",
    "tools/ci/proof_unit_consistency_gate.nim",
    "tools/hotspot_ranker.nim"
  ],
  "allowlistOk": false,
  "subjectDeltaZero": false,
  "oldAnchorOk": true,
  "newAnchorOk": true,
  "delegatedToPlatform": true
}
```

Paths already inside the allow set (4): `config/trusted_checker_closure.json`, `data/architecture_debt.json`, `data/nimtry_baseline.json`, `src/generated/type_registry_metadata.json`.
Path allowed as a closure member (pin@B key) (1): `src/verification/batch_uap/ir_pipeline_runner.nim`.
**Paths outside the allow set (5)** -- the objects this amendment registers:

1. `tests/unit/test_ir_pipeline_theaterguard.nim`
2. `tests/unit/test_hotspot_ranker.nim`
3. `tools/ci/proof_unit_consistency_gate.nim`
4. `tools/hotspot_ranker.nim`
5. `data/debt_reduction_baseline.json`

## Section 2. Rotation subject and product defect (why this PR is a rotation)

The rotation is caused by a change to `src/verification/batch_uap/ir_pipeline_runner.nim` (a closure member). That change fixes the actual defect behind DEBT#423:

- The canonical-success path records `obligationCount: generatedObligationCount` at `:740`, but that variable is assigned at `:761`. A canonical-success path therefore reports **always 0**.
- The TheaterGuard cited by DEBT#304 (`:1316`) does not cover this early-return path, so the stale-close statement in #304 is false for the canonical-success path.
- PR #287 pins the count at the generation boundary (`runIrPipelineCore(..., generatedCount: var int)`) and stamps it in the public wrapper.

## Section 3. Companion-path classification (all are rotation-member contract/data companions)

| Path | Class | Basis |
|---|---|---|
| `tests/unit/test_ir_pipeline_theaterguard.nim` | rotation-member unit contract | test (g) asserts the count survives a real canonical-success return. The old test asserted only the non-blocking path, so the rotation turns red without this companion (same class as `test_judgment_cas.nim`/`wf_runners_test.nim`) |
| `tests/unit/test_hotspot_ranker.nim` | projection read-back contract test | DEBT#487 -- fix that the P1 projection `generateProjections` actually emits is read through the `DebtRowFields` declaration table |
| `tools/ci/proof_unit_consistency_gate.nim` | rotation-machinery contract companion | Debt role line pin registration for the new test (`tests/unit/test_hotspot_ranker.nim:50`) (same class as `tools/merge_ruleset_drift_monitor.nim`) |
| `tools/hotspot_ranker.nim` | a tool, not non-member production `src/` | downstream projection reader. Replaces the positional 6-column assumption with `DebtRowFields`/`parseMarkdownRows` declaration consumption |
| `data/debt_reduction_baseline.json` | gate baseline data | the reduction baseline read by `src/gate/runners/debt_integrity_gate.nim:27` and `src/gate/in_process_gates.nim:265`. nimtry 4374 -> 4275 (same class as `data/nimtry_baseline.json`/`data/quality_gate_baseline.json`) |

**Not production `src/`**: none of the 5 paths above is under `src/`. They are unrelated to the A2 (i) "NON-member production src/ prohibited" class.

## Section 4. Non-expansion argument

- (1) The allowlist is evaluated only on the ROTATION path where `closureChange=true` (ADR-0025 A2 (ii)). This registration changes the treatment of these 5 paths on the NORMAL path in no way.
- Enumeration only -- no globs (A4 rule). There is no prefix expansion of `tests/**`, `tools/**` or `data/**`.
- This registration minimally extends only the rotation approval scope; the freedom of non-rotation PRs is unchanged.

## Section 5. Scope bound

- This amendment restores only the **landability** of #287. The product verdict of #287 (DEBT#423 obligation count preserved, DEBT#487 projection read-back) is a separate acceptance target.
- The expansion PR itself changes trustSurface (`src/cli/merge_cli.nim`), so it takes the MUST-T2a manual merge lane rather than the merge queue (precedent: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`).

## Section 5b. Second rotation -- CLI fail-closed (#268, DEBT#225)

A second rotation of the same fix class: `src/cli/axiom_status.nim`, `src/cli/cert_cli.nim` and `src/cli/config_cli.nim` (three closure members) remove the "silent success" that returned exit 0 when state was absent. 6 of the 13 changed paths are outside the allow set:

| Path | Class | Basis |
|---|---|---|
| `tests/cli/test_axiom_status.nim` | rotation-member unit contract | no-history / `--allow-missing` exit assertions |
| `tests/cli/test_cert_cli.nim` | rotation-member unit contract | empty vault / absent vault / id-rejection exit assertions |
| `tests/cli/test_config_cli.nim` | rotation-member unit contract | strict/default matrix |
| `tests/features/axiom_status.feature` | section 0.7 business-scenario SSOT | fail-closed / opt-in scenario update |
| `tests/gateway/axiom_status_feature_test.nim` | gateway contract test | executes the feature scenarios |
| `data/feature_manifest.json` | feature registration data | registers the updated feature |

The rotation itself is caused by changes to the three closure members, so `closureChange=true`, and all 6 paths above are contract/data companions of the changed members (0 production `src/`).

## Section 5c. Third rotation -- generated metadata companion (this PR, A8 (iii))

The delta measurement of this amendment PR itself (6 paths) identified **1 self-blocking path**:

| Path | Class | Basis |
|---|---|---|
| `src/generated/build_metadata.json` | generated-data companion (same class as A6) | an artifact that `make build` regenerates deterministically via `tools/build_metadata_generator.nim`. `config.nims` staticReads it and `config/paths.nims`, `config/vendors.nims`, `src/gate/self_ref_detect.nim` consume it. Every rotation PR that runs a local build necessarily carries it, so excluding it makes rotation structurally impossible (A2 (1) self-contradiction). |

This is the **same fix class** as A6's registration of `src/generated/type_registry_metadata.json`, and it is not production `src/` (generated data). Enumeration only -- no globs (A4).

## Section 5d. Fourth rotation -- gate_hook gateway test companion (#285, A8 (iv))

The diff measurement of PR #285 (DEBT#520, head `03dc481`; 5 paths against origin/main) identified 1 path outside the allow set:

| Path | Class | Basis |
|---|---|---|
| `tests/gateway/gate_hook_feature_test.nim` | rotation-member gateway contract test | asserts the AOT pre-flight manifest `.nim` resolution of the rotation subject `src/gate/runners/gate_hook.nim` (a closure member). Same class as `axiom_status_feature_test.nim` in A8 (ii). |

The remaining 4 paths are already allowed: `src/gate/runners/gate_hook.nim` (closure member), `config/trusted_checker_closure.json` (pin), `data/architecture_debt.json`, `src/generated/type_registry_metadata.json` (allowlist extra).

## Section 6. Approval record

| Item | Value |
|---|---|
| Approver | wintrover (owner, sole `@Archright/architect`) |
| Approval date | 2026-11-21 |
| Approval basis | session-level explicit approval of 2026-11-21, plus the PR #287 merge_group verdict measurement (ROT_ALLOWLIST, 5 of 10 changed paths blocked, run `44882710554`) and the PR #268 diff measurement (6 of 13 changed paths blocked) |
| Executor | agent (per-PR explicit delegation). Not recorded as human keystrokes. |