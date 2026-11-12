# Refactoring Engine Specification

## Overview

The refactoring engine maps complexity signals from diagnostics to machine-actionable refactoring templates.

## Signal → Pattern Mapping

| Signal | Pattern | Description |
|--------|---------|-------------|
| `rskQuantifierExcess` | `rpkExtractPureFunction` | Extract quantifier scope into pure func |
| `rskNonLinearArithmetic` | `rpkLinearizeVariables` | Replace nonlinear constraints with linear aux vars |
| `rskDeepDependency` | `rpkInsertCompositionNode` | Add intermediate composition node |
| `rskHighCoupling` | `rpkIsolateInterface` | Separate boundary contract |
| `rskMissingLoopInvariant` | `rpkAddLoopInvariant` | Add loop invariant annotation |
| `rskMissingDecreaseMeasure` | `rpkAddDecreaseMeasure` | Add termination measure |

## Escalation Strategy

```
RefactoringTemplate applied → Z3 equivalence check
  ├─ PASS → rvApplied (refactoring accepted)
  └─ FAIL → recordFailure()
       ├─ consecutiveFailures < 3 → try next template
       └─ consecutiveFailures >= 3 → rvEscalated
            └─ formatEscalationReport() → human architect handoff
```

**Key invariant**: After escalation, NO further LLM retries are attempted. This prevents probabilistic infinite loops.

## Z3 Equivalence Validation

Each refactoring is validated via `validateRefactoringEquivalence()`:
- Forward: `original → refactored` (Z3 unsat = OK)
- Backward: `refactored → original` (Z3 unsat = OK)
- Both must pass for `equivalent = true`
