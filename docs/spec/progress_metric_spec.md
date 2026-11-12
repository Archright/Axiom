# Progress Metric Specification

> Deterministic convergence metric for the universal acceptance pipeline.
> Replaces probabilistic stagnation heuristics with a mathematically
> guaranteed monotonic progress indicator.
>
> Version: 0.1.0
> Date: 2026-06-04

---

## 1. Overview

The `ProgressMetric` is a **deterministic, computable tuple** evaluated at the end of every UAP round. It replaces the ad-hoc `consecutiveFailures` counter with a structured measure that guarantees monotonic improvement or deterministic halting.

---

## 2. Metric Definition

```nim
type
  ProgressMetric* = object
    unsatCoreSize*: int           ## |unsat core vars| from Z3 (primary)
    invariantCount*: int          ## |InvariantRegistry.entries| (secondary)
    leanKernelVerified*: bool     ## Lean 4 kernel approval (terminal)
    proofDepth*: int              ## max tactic depth in Lean replay (auxiliary)
    roundIndex*: int              ## 0-based round number (metadata)
```

### 2.1 Primary Indicator: `unsatCoreSize`

- **Source**: `detective.nim` → `parseUnsatCore`
- **Semantics**: Number of variables in the minimal unsatisfiable core.
- **Monotonicity rule**: `unsatCoreSize_{n+1} ≤ unsatCoreSize_n`
- **Terminal condition**: `unsatCoreSize == 0` → proof is contradiction-free → Lean kernel check may pass.

### 2.2 Secondary Indicator: `invariantCount`

- **Source**: `integrity_refinement_loop.nim` → `InvariantRegistry.count`
- **Semantics**: Number of tracked invariants that have survived pruning.
- **Monotonicity rule**: `invariantCount_{n+1} ≥ invariantCount_n` (registry only grows or stays same; evicted invariants are still counted as "attempted").
- **Purpose**: Distinguishes "no progress because no new invariants were tried" from "no progress because all new invariants were rejected".

### 2.3 Terminal Flag: `leanKernelVerified`

- **Source**: `judge.nim` → `runLeanProofRefinement`
- **Semantics**: Lean 4 kernel accepted the proof term.
- **Effect**: Immediately breaks the UAP loop regardless of other metrics.

### 2.4 Auxiliary: `proofDepth`

- **Source**: `lean_replay.nim` → tactic trace depth
- **Semantics**: Maximum nesting depth of tactics used in the successful (or attempted) proof.
- **Purpose**: Diagnostic only. A decreasing depth with unchanged unsat core size may indicate simplification progress.

---

## 3. Halting Conditions

The UAP loop terminates deterministically when **any** of the following conditions is met:

| # | Condition | Interpretation |
|---|-----------|----------------|
| H1 | `leanKernelVerified == true` | **Success** — proof accepted. |
| H2 | `unsatCoreSize` unchanged for 3 consecutive rounds | **Stagnation** — engine cannot reduce defects. Escalate to human architect. |
| H3 | `unsatCoreSize` increased for 2 consecutive rounds | **Regression** — new invariants introduced new contradictions. Escalate immediately. |
| H4 | `roundIndex >= maxRounds - 1` | **Budget exhaustion** — hard round limit reached. Report best-effort result. |

### 3.1 Stagnation vs Regression

- **Stagnation**: The engine is trying but not improving. The invariant set may be complete but insufficient.
- **Regression**: The engine is actively making things worse. Usually indicates a bug in `legislateWithFeedback` or `mergeInvariantClauses`.

---

## 4. Refactoring Stagnation Integration

`core/refactoring_engine.nim::RefactoringStagnation` is updated to use `ProgressMetric` instead of a plain failure counter:

```nim
proc recordProgress*(stagnation: var RefactoringStagnation; metric: ProgressMetric) =
  stagnation.metricsHistory.add(metric)
  let recent = stagnation.metricsHistory[max(0, stagnation.metricsHistory.len - 3) .. ^1]

  # H2: Stagnation
  if recent.len >= 3 and
     recent[^1].unsatCoreSize == recent[^2].unsatCoreSize and
     recent[^2].unsatCoreSize == recent[^3].unsatCoreSize:
    stagnation.escalated = true
    stagnation.escalationReport = "STAGNATION: unsatCoreSize frozen for 3 rounds"

  # H3: Regression
  if recent.len >= 2 and
     recent[^1].unsatCoreSize > recent[^2].unsatCoreSize:
    stagnation.escalated = true
    stagnation.escalationReport = "REGRESSION: unsatCoreSize increased"
```

---

## 5. Determinism Proof Sketch

**Theorem**: The UAP loop halts in at most `maxRounds` iterations.

**Proof**:
1. `unsatCoreSize` is a non-negative integer.
2. By construction, the loop breaks immediately if `unsatCoreSize` does not strictly decrease for 3 rounds (H2).
3. If `unsatCoreSize` strictly decreases every round, it can decrease at most `initialUnsatCoreSize` times before reaching 0.
4. `maxRounds` is an upper bound that dominates both cases.
5. Therefore the loop always terminates in finite time. ∎

---

## 6. Future Extensions

- **Weighted unsat core**: Assign different weights to variables based on AST depth or dependency count.
- **Multi-property metric**: Track separate `unsatCoreSize` per property kind (overflow, bounds, race, null).
- **Predictive halting**: Use the slope of `unsatCoreSize` over rounds to estimate convergence and pre-emptively allocate budget.
