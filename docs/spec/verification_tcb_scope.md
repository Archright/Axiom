# Verification TCB Scope

## Formal Verification Trust Computing Base

### In-Scope (TCB)

| Layer | Component | Testing Status |
|-------|-----------|----------------|
| L0 | Verification engine (IR→Lean/SMT) | Fully tested — 285 cases |
| L1 | Metrics/analysis (complexity, certificates) | Tested — McCabe-corrected |
| L2 | Verification gates (theater/debt/decision detection) | Negative test matrix |

### Out-of-Scope (Non-TCB)

| Layer | Component | Rationale |
|-------|-----------|-----------|
| L3 | CLI (user interface) | Output formatting/layout only — 0% impact on proof verdict soundness. Minimal routing ping test only. |

**Rationale**: B2B formal-verification customers purchase "zero false negatives." CLI presentation does not affect verdict correctness.

**Reference**: [4-Tier Verification Pipeline](./4_tier_verification_pipeline.md)
