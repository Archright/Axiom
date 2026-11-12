# Proof Budget Specification

## Overview

The proof budget system enforces deterministic resource control for the ax prove pipeline.

## Dual Budget Model

### Primary: Gas Limit (Deterministic)

| Constant | Value | Purpose |
|----------|-------|---------|
| `scribeMaxRounds` | 3 | LLM (Leanstral) max feedback rounds |
| `cegarMaxIterations` | 20 | CEGAR refinement max iterations |
| `judgeMaxAttempts` | 5 | Lean kernel replay max attempts |
| `maxTotalSolverInvocations` | 8 | Total gas units (scribe + judge) |

**Invariant**: `gasRemaining + gasUsed = gasTotal` at all times.

**Deterministic guarantee**: Given identical input, the pipeline produces identical output regardless of CPU scheduling, because termination is controlled by iteration counts, not wall-clock time.

### Secondary: Wall-Clock Safety Net

| Constant | Value | Purpose |
|----------|-------|---------|
| `orchestrationWallClockTimeoutMs` | 600,000 (10 min) | Global orchestrator limit |
| `nodeWallClockTimeoutMs` | 120,000 (2 min) | Per-node limit |

**Purpose**: Handles OS scheduling variance in parallel environments. Wall-clock timeout is a safety net, not the primary termination mechanism.

## Verdict Types

| Verdict | Meaning | Deterministic? |
|---------|---------|----------------|
| `pbvContinue` | Budget remaining | N/A |
| `pbvGasExhausted` | Gas limit reached | **Yes** |
| `pbvTimeout` | Wall-clock exceeded | No (OS-dependent) |

## Integration Points

- [DEPRECATED] `batch_uap_orchestrator.nim`: Per-node budget tracking
- `orchestrator.nim`: Per-depth wall-clock deadline
- `cegar_engine.nim`: CEGAR loop budget (30s + maxIter=20)
- `proof_synthesis_engine.nim`: Leanstral round cap (3)
