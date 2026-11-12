# procedure-gate 4-Step Deterministic Enforcement Regression Fix

## Intent
The `procedure-gate` 4-Step Integrity Rule (Intent → Specification → Test → Code) was no longer deterministically enforced. A single `tests/gateway/*_test.nim` file could satisfy both `hasSpecification` and `hasTest`, allowing BDD feature files to be skipped.

## Root Cause
Commit `4af63fbe` (May 13, 2026) renamed `isFeatureEvidence` to `isFeatureEvidenceFile` and changed the check from **path-based** (`contains("tests/features/")`) to **extension-based** (`endsWith("_test.nim") or endsWith(".feature")`). This caused `tests/gateway/*_test.nim` to falsely match as Specification evidence.

## Specification
Restore path-based discrimination with zero overlap between layers:
- `isFeatureEvidenceFile`: `tests/features/*.feature` only (Spec SSOT)
- `isBddEvidence`: `tests/features/steps/` only (BDD step files)
- `isTestEvidence`: `tests/gateway/` or `tests/unit/` only (Test SSOT)

## Test
- `tests/unit/procedure_gate_test.nim`: Updated predicates + regression tests
- `tests/features/procedure_gate_4step.feature`: BDD specification for the fix itself

## Code
- `src/core/file_utils.nim`: Fixed `isFeatureEvidenceFile`, `isBddEvidence`, `isTestEvidence`
- `tests/unit/procedure_gate_test.nim`: Synced tests with corrected predicates
- `tests/features/procedure_gate_4step.feature`: New BDD feature file
