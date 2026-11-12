# Tech Debt Resolution — 2026-05-29

## Context
Executed `killer-frost-jubilee-raven.md` plan to resolve 8 accumulated tech debt items blocking pre-commit gates.

## Changes

### 1. DRY `shouldRun` SSOT
- **Added** `shouldRun*` to `src/gate/gate_utils.nim` (sole definition).
- **Removed** duplicate `shouldRun` from `src/gate/orchestrator.nim` and `src/gate/orchestrator_hook.nim`.

### 2. SOLID-OCP `dispatchGate`
- **Added** `argsTemplate*: seq[string]` to `GateConfig` (`src/gate/domain_types.nim`).
- **Updated** `nim-check` and `gateway-test` entries in `src/gate/manifest.d/_index.json` to use `entry` + `argsTemplate` instead of empty `entry`.
- **Replaced** hardcoded `case gate.id` in `dispatchGate` with unified `runSingleGateImpl` call (`src/gate/orchestrator_hook.nim`).

### 3. XDeclaredButNotUsed Cleanup
- `src/gate/memory_policy_gate.nim`: removed unused `MpStatus` enum.
- `src/gate/runners/policy_validator.nim`: removed unused `AllowedImportLinePattern`.
- `src/gate/runners/procedure_gate.nim`: replaced unused `patchCode` with `_`.
- `src/gate/runners/test_coverage_gate.nim`: removed unused `allFeatures` / `collectFeaturesFromDir`.

### 4. Orphan Reference Fixes
- `src/core/tree_sitter_bridge.nim`: added `declarationTags*` const.
- `src/verification/thought_render.nim`: added `strutils` import, removed unused `json_utils` / `reporter`.

## Verification
- `nim check` on all modified files → Error 0, SuccessX.
- `src/gate/nimtry/nimtry_cli.nim` → PASSED (0 violations).

## Post-Condition
Pre-commit gates no longer require `AXIOM_EMERGENCY_NO_VERIFY=1` for merges from `core` to `main`.
