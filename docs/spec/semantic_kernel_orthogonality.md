# BMC Kernel Orthogonality & Legacy Encoder Boundary

> **Status**: Diagnostic — Stage 7/8 assessment  
> **Date**: 2026-08-10  
> **SSOT**: This document records the approved orthogonality boundary and legacy encoder audit so future agents do not attempt incorrect refactors.

---

## 1. BMC Orthogonality Boundary

BMC (`src/core/bmc/`) is a **genuinely orthogonal domain** — an integer-state race-condition exploration engine. It does NOT consume `Transition`/`ParallelUpdate` post-state formulas and is NOT governed by the Semantic Kernel (`transition_formula_builder.nim`).

### BMC types (own domain)

| BMC type | File | Semantic role |
|----------|------|---------------|
| `TransitionRule` | `src/core/bmc/bmc_types.nim:30` | Delta/invariant integer transition (sub/add), NOT a `Transition` |
| `StepOwner` | `src/core/bmc/bmc_types.nim:41` | `ownerT1`/`ownerT2`/`ownerNone` — thread interleaving |
| `BmcTrace` | `src/core/bmc/bmc_types.nim:46` | Per-thread PC arrays (`pc1`/`pc2`), integer state `x`, registers `r1`/`r2` |
| `BmcVerdict` | `src/core/bmc/bmc_types.nim:55` | `raceDetected`, `raceFinalState`, `sequentialResults`, `bothWritePathExists` |
| `GenericBmcTrace` | `src/core/bmc/bmc_generic.nim:30` | Generic multi-thread trace with `GenericPcState` |

### Semantic Kernel types (canonical domain)

| SK type | File | Semantic role |
|---------|------|---------------|
| `Transition` | `src/core/trusted/verification_model_types.nim` | Domain transition with `ParallelUpdate` (assignments + havocs) |
| `TransitionFormula` | `src/core/trusted/private/transition_formula_builder.nim:28` | Guard + postArgs — the golden post-state semantics (C5.1) |
| `TransitionFormulaBuilder` | `src/core/trusted/private/transition_formula_builder.nim:32` | Builds per-transition formulas from `Transition` + state signature |

### Key evidence

- `bmc_engine.nim` uses `TransitionRule` (delta/invariant), NOT `Transition` or `ParallelUpdate`. Lines 9-97 operate on integer state `x`, thread PCs (`pc1`/`pc2`), and `StepOwner` — no `TransitionFormulaBuilder` import, no `buildTransitionFormula` call.
- `bmc_generic.nim` uses `GenericPcState` and `GenericBmcTrace` — entirely separate from the CHC/Evidence domain.
- `bmc_lower.nim` is an IR lowering pass for SMT BMC emission (`lowerToBmc`), transforming `IRFuncDef` for QF_BV SMT output. It does NOT use `transition_formula_builder`.
- `transition_formula_builder.nim` is consumed by `buildChcFromVerificationModel` (`ir_loop_to_horn.nim:333`) for canonical CHC post-state encoding — BMC never imports it.

### Stage 7 outcome

**BMC migration to the Semantic Kernel is NOT applicable.** BMC is an orthogonal domain (integer interleaving race exploration) that does not use `Transition`/`ParallelUpdate` post-state lowering. The correct Stage-7 outcome is **no migration** — this boundary is approved and documented to prevent future agents from attempting a wrong refactor.

---

## 2. Legacy CHC Boundary

### BackendPolicy / selectBackend governance

The IR pipeline runner (`src/verification/batch_uap/ir_pipeline_runner.nim`) gates all backend selection through `selectBackend` (line 121). The legacy encoder (`buildChcTransitionSystem`, `ir_loop_to_horn.nim:142`) is only reachable under `bpAllowFallback` policy after canonical CHC failure:

| Call site | File:Line | Policy required | selectBackend call |
|-----------|-----------|-----------------|-------------------|
| Canonical CHC success | `ir_pipeline_runner.nim:391` | any | `selectBackend(policy, true)` |
| Canonical CHC failed, bpRequire | `ir_pipeline_runner.nim:419` | `bpRequire` | `selectBackend(policy, false)` → vbCanonicalChc, no fallback |
| Canonical CHC declined, bpRequire | `ir_pipeline_runner.nim:447` | `bpRequire` | `selectBackend(policy, false)` → vbCanonicalChc, no fallback |
| Legacy encoder path | `ir_pipeline_runner.nim:469` | `bpAllowFallback` only | `selectBackend(policy, false)` at line 497 |

### Legacy encoder direct call (unused in production)

`irLoopToHornScript` (`src/core/trusted/private/ir_loop_to_horn.nim:243`) calls `buildChcTransitionSystem` directly at line 248 without going through `selectBackend`. However, this proc is **exported but not called from any production code** — it is currently unused externally.

### --legacy-uap flag

The `--legacy-uap` flag (`src/cli/axiom_engine.nim:823` → `loop_driver.nim:56`) bypasses the entire IR pipeline and uses the old batch UAP path. This is by design — it is a separate pre-IR-pipeline code path that predates `BackendPolicy`/`selectBackend`.

### Stage 8 outcome

**Stage 8 legacy retirement is safe to defer.** Within the production IR pipeline, the legacy encoder is properly gated by `bpAllowFallback` and `selectBackend`. The only latent concern is `irLoopToHornScript` (exported but unused) which could bypass `selectBackend` if ever called externally — this is a surface-level concern, not an active production bypass.

---

## 3. Machine-Consistent Summary

```yaml
bmc_orthogonality:
  verdict: orthogonal
  reason: BMC uses TransitionRule/StepOwner/BmcTrace, not Transition/ParallelUpdate/TransitionFormula
  semantic_kernel_consumers:
    - buildChcFromVerificationModel (ir_loop_to_horn.nim:333)
  bmc_consumers:
    - bmc_engine.nim (TransitionRule, StepOwner)
    - bmc_generic.nim (GenericBmcTrace, GenericPcState)
  migration_applicable: false
  stage_7_outcome: no_migration

legacy_encoder_boundary:
  selectBackend_governed: true
  production_bypass_exists: false
  latent_concern:
    symbol: irLoopToHornScript
    file: src/core/trusted/private/ir_loop_to_horn.nim
    line: 243
    issue: exported but unused; calls buildChcTransitionSystem directly
    active_in_production: false
  stage_8_outcome: defer_retirement
```