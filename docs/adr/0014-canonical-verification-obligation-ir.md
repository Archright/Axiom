# ADR-0014: Canonical Verification Obligation IR

## Status
Accepted

## Context
P7 introduced a canonical obligation IR layer (`src/verification/obligation/`) that bridges the IR pipeline and the proof state machine. Prior to this ADR, obligation semantics were ad-hoc: `psNoObligation` was used as a catch-all skip reason, `rkNoObligation` coerced targets into a no-op path, and the `ir_pipeline_runner` performed early-return bypasses that masked obligation-attempted counts. The product contract (`docs/spec/productization_contract.md`) requires that every eligible target either receives an obligation or is explicitly classified with a documented skip reason — no silent drops.

## Decision
Adopt a canonical obligation IR with the following invariants:

1. **Obligation generation is explicit.** Every symbol that passes the eligibility check (`eligibleTargets`) must produce an `ObligationGroundingResult` with a documented verdict (`ogrGenerated`, `ogrSkipped`, `ogrNotApplicable`). No implicit skip.
2. **Skip reasons are first-class.** `skipReason` values (`no_obligation`, `bmc_skipped`, `unsupported_target`, `not_encodable`) are defined in `ObligationSkipReason` and must be recorded in every skip path. Legacy `rkNoObligation` coerce is mapped to `skipReason = "no_obligation"` with a DEBT marker.
3. **The proof state machine is the single authority for obligation attempt tracking.** `obligationAttemptedCount` is incremented only when the state machine transitions to `proofAttempted`. The `ir_pipeline_runner` no longer performs early-return bypasses that would skip this count.
4. **TheaterGuard is not a bypass.** The `ir_pipeline_runner`'s `TheaterGuard` wrapper must not short-circuit obligation counting. If a target is classified as theater, it is recorded with `skipReason = "theater_detected"` and the count is preserved.

## Consequences
- `src/verification/obligation/obligation_ir.nim` is the canonical IR module; all obligation-related types flow through it.
- `src/verification/obligation/metrics.nim` computes `ogr`, `par`, `obligationGeneratedCount`, `targetsWithObligations`, `eligibleTargets`, `obligationAttemptedCount`.
- `data/baseline.json` now includes `ogr` and `par` keys in the `metrics` section.
- Legacy `rkNoObligation` coerce paths are DEBT-tracked (DEBT#421, DEBT#422).
- `ir_pipeline_runner` TheaterGuard bypass is DEBT-tracked (DEBT#423).
- `no_obligation`/`bmc_skipped` legacy skipReason mapping is DEBT-tracked (DEBT#424).
