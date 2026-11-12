# Stub Test Inventory

## Generated: 2026-06-30

Per AGENTS.md 0.8, stub tests (>50% `check true` density) cause automatic gate FAIL.
This inventory identifies all test files containing literal `check true` stubs (no boolean expression).

## Summary

| Metric | Value |
|--------|-------|
| Total test files analyzed | 333 |
| Files with stub lines | 12 |
| Healthy files (no stubs) | 321 |
| Total `check` assertions | 6,597 |
| Total `check true` stub lines | 15 |
| Overall stub density | 0.23% |

## Threshold

- **STUB**: `check true` density >50% of all `check` statements in the file
- **OK**: any other case (including 0% stubs)

No files in the current inventory exceed the 50% threshold.

## Full Inventory

| File | Total Checks | check true | Density | Status |
|------|-------------|------------|---------|--------|
| `tests/gateway/axiom_defaults_feature_test.nim` | 4 | 2 | 50.0% | REVIEW |
| `tests/unit/axiom_pragmas_test.nim` | 6 | 1 | 16.7% | OK |
| `tests/unit/pipeline_orchestrator_test.nim` | 12 | 2 | 16.7% | OK |
| `tests/gateway/gate_safety_macro_feature_test.nim` | 7 | 1 | 14.3% | OK |
| `tests/gateway/doc_completeness_gate_feature_test.nim` | 10 | 1 | 10.0% | OK |
| `tests/solver/test_z3_bindings.nim` | 13 | 1 | 7.7% | OK |
| `tests/gateway/test_quality_guard_feature_test.nim` | 30 | 2 | 6.7% | OK |
| `tests/gateway/gate_hook_feature_test.nim` | 16 | 1 | 6.2% | OK |
| `tests/gateway/generated_feature_runner.nim` | 16 | 1 | 6.2% | OK |
| `tests/unit/static_contract_test.nim` | 27 | 1 | 3.7% | OK |
| `tests/verification/test_lean_sandbox.nim` | 27 | 1 | 3.7% | OK |
| `tests/engine/dag_executor_test.nim` | 48 | 1 | 2.1% | OK |

## Review Notes

### `tests/gateway/axiom_defaults_feature_test.nim` (50.0% — borderline)

- 2 of 4 `check` lines are `check true` stubs (lines 31, 41).
- The remaining 2 checks are real boolean assertions.
- **Verdict**: Borderline. The stubs guard branches with `echo` warnings that are not hard-failed. Should either be promoted to real assertions or the branches marked `skip()` with a TODO comment.

### `tests/unit/axiom_pragmas_test.nim` (16.7%)

- 1 stub at line 60: `check true  # compilation success is the real assertion`.
- This is intentional: the test verifies compile-time macro success by the fact that the test compiles at all. The `check true` is a placeholder so the test body is not empty.
- **Verdict**: JUSTIFIED. Compile-time enforcement tests cannot use runtime assertions. The comment explains the intent.

### `tests/unit/pipeline_orchestrator_test.nim` (16.7%)

- 2 stubs at lines 67, 80: `check true  # Registration succeeded without crash`.
- These test that a procedure call does not raise. The absence of exception IS the assertion.
- **Verdict**: JUSTIFIED. Negative tests (does not crash) are valid behavioral checks. Consider adding a `doAssert result.isSome` or similar if a return value exists.

### `tests/unit/static_contract_test.nim` (3.7%)

- 1 stub at line 32: `check true  # macro doAssert would fail at compile time if wrong`.
- Same pattern as `axiom_pragmas_test.nim`: compile-time macro verification.
- **Verdict**: JUSTIFIED. Documented compile-time assertion pattern.

### All gateway feature tests (6.2% — 10.0%)

Files:
- `tests/gateway/gate_safety_macro_feature_test.nim`
- `tests/gateway/doc_completeness_gate_feature_test.nim`
- `tests/gateway/test_quality_guard_feature_test.nim`
- `tests/gateway/gate_hook_feature_test.nim`
- `tests/gateway/generated_feature_runner.nim`
- `tests/gateway/axiom_defaults_feature_test.nim`

These are generated BDD-style feature tests. Each has a small number of `check true` stubs
alongside many real assertions. The stubs primarily appear in scenarios where:
1. The test body only does `echo` reporting (no hard failure)
2. The branch is marked "Warnings only — not a hard failure for now"

**Verdict**: MARGINAL. These are technical debt items. Each stub should be upgraded to a real
assertion or the scenario should be marked `skip()` until a real assertion can be written.

### `tests/solver/test_z3_bindings.nim` (7.7%)

- 1 stub at line 70: bare `check true` inside a loop.
- The surrounding code tests Z3 solver creation; the stub guards a branch where the
  solver context is destroyed.
- **Verdict**: MARGINAL. Should be replaced with a real assertion on solver state.

### `tests/verification/test_lean_sandbox.nim` (3.7%)

- 1 stub at line 115: bare `check true`.
- Rest of the file has 26 real assertions. The single stub is likely a placeholder for
  a missing negative test.
- **Verdict**: MARGINAL. Replace with real assertion or delete.

### `tests/engine/dag_executor_test.nim` (2.1%)

- 1 stub at line 254 in suite "cleanup": `check true` after removing a state file.
- The removal is guarded by `if fileExists(...)`, making the post-condition untestable
  without re-checking file existence.
- **Verdict**: MARGINAL. Could be replaced with `check not fileExists(...)`.

## Recommended Actions

1. **Replace technical debt stubs** in gateway feature tests with real assertions or mark
   scenarios `skip()` with a TODO comment referencing the debt registry.
2. **Document the "compile-time success is the assertion" pattern** in AGENTS.md to prevent
   false-positive stub detection.
3. **Add a lint rule** in the test runner that warns on `check true` without a `# reason:` comment.

## Methodology

- Scanned all `*.nim` files under `tests/`.
- `check total` counts any line matching `\bcheck\s+\S` (Nim unittest assertion pattern).
- `check true` counts lines matching `\bcheck\s+true(\s*#.*)?$` (literal stubs).
- Density = `check true` / `check total`.
- Non-test scripts in `tests/` (e.g., `architecture_constraints.nim`) have 0 `check` assertions
  and are excluded from this inventory.
