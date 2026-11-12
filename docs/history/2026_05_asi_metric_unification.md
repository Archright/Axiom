# ASI Metric Unification (AMU) — Wave 10.1

## Problem

`proof_universe.lock` reported `asiFixed4: "1.0000"` while the actual engine ASI
was `0.1156`. Root cause: `calculateAsiFixed4` in `proof_state_builder.nim`
used certificate file count (277) as the denominator instead of total source
functions (2414), producing `277/277 = 1.0000`. This was a **SSOT violation** —
multiple ad-hoc ASI formulas existed across the codebase.

## Solution

### Phase 1: SSOT Centralization (`metrics.nim`)
- Introduced `ValidatedAsi = distinct string` — type-level proof that an ASI
  string was produced by `metrics.nim` SSOT. Cannot be constructed from raw
  string literals outside this module.
- Added `validateUniverse()` panic-level guard: `totalFunctions < 500`
  triggers `quit(1)` with diagnostic message.
- Deprecated 6 legacy functions: `computeAsi`, `computeSplitAsi`,
  `computeSubstantiveAsi`, `computeWeightedAsi`, `computeEntropyWeightedAsi`,
  `computeFormalProofIntegrity`, `computeAxiomaticIntegrity`.

### Phase 2: Type-Level Enforcement
- Changed `exportAsiFixed4()` return type from `string` to `ValidatedAsi`.
- Added `asString()` extractor for JSON/lock serialization.
- Changed `computeProofUniverseLock` signature: `asiFixed4: ValidatedAsi`
  (was `string`).
- Removed `hasRuntimeAsi` fallback / else hydration logic from
  `computeProofUniverseLock` — ASI is now INJECT-ONLY.

### Phase 3: Call Site Migration
- `wf_runners.nim`: `asString(getUnifiedAsiFixed4(...))`
- `state_manager.nim`: `asString(metrics.exportAsiFixed4(...))`
- `wf_state.nim`: same pattern
- `wf_state_vacuity.nim`: same pattern
- `report_cli.nim`: same pattern
- `pipeline_fingerprint_engine.nim`: same pattern

## Verification

```bash
$ bin/ax prove src --no-graph-cache
$ python3 -c "import json; d=json.load(open('proof_universe.lock')); print(d['asiFixed4'])"
0.1321
```

Before fix: `1.0000`. After fix: `0.1321` (matches `ax report --json` engineAsiFixed4).

## Files Modified

- `src/core/metrics.nim`
- `src/core/proof_state_builder.nim`
- `src/core/proof_universe_lock.nim`
- `src/verification/proof_universe_commit.nim`
- `src/verification/state_manager.nim`
- `src/cli/wf_runners.nim`
- `src/cli/wf_state.nim`
- `src/cli/wf_state_vacuity.nim`
- `src/cli/report_cli.nim`
- `src/core/logic/pipeline_fingerprint_engine.nim`
- `src/verification/analyzer/stages/stage_08_reporter.nim`

## Impact

- **ASI Shock Value**: External observers may misinterpret 1.0000 → 0.1321 as
  quality degradation. This is metric normalization, not code quality loss.
- **Breaking**: Any external tool parsing `proof_universe.lock` will see
  corrected (lower) ASI values.
- **Security**: `ValidatedAsi` prevents forged ASI injection at compile time.
