# Token Scheduler for Gate Concurrency (OOM Mitigation)

**Date**: 2026-05-28  
**Intent**: Prevent kernel OOM during pre-push by replacing multiplicative parallelism with a deterministic, compile-time token-budget scheduler.  
**BDD Spec**: `tests/features/gate_runner.feature` — "Heavy gates respect global token budget" scenario  
**Test**: `tests/unit/gate_hook_scheduler_test.nim` — deterministic dispatch order, token release, edge cases  
**Code**: `src/gate/domain_types.nim`, `src/gate/manifest.d/_index.json`, `scripts/gate_hook.nim`

---

## 1. Problem

The 2026-05-28 OOM forensic analysis (`docs/history/oom-forensic-analysis-2026-05-28.md`) showed 83 Axiom processes holding 28.8 GB anon RSS at OOM. Root cause: `4 L2 slots × 8 AXIOM_JOBS = 32+ concurrent workers` with no cross-gate memory coordination.

## 2. Solution

### 2.1 Compile-Time Deterministic Token Budget

- `const GlobalMaxTokens = 8` (overridable via `-d:axiomGlobalMaxTokens`)
- Replaces runtime `countProcessors() div 2` which violated GUARDIAN.md §-1 Deterministic.

### 2.2 Type-Driven Gate Weights

- `GateWeight` enum: `gwLight=1`, `gwMedium=2`, `gwHeavy=4`
- Mandatory `weight` field on `GateConfig` — compiler rejects unclassified gates.

### 2.3 Token Scheduler Algorithm

Orchestrator allocates `gate.weight.int` tokens per dispatch; insufficient tokens → gate waits in queue. Tokens released on completion or timeout.

### 2.4 L3 cgroups Enhancement (Per Kernel Docs)

- Added `--property=MemoryHigh=6G` (soft throttle) before existing `--property=MemoryMax=8G` (hard limit).
- Justification: Linux kernel cgroup-v2 docs state `memory.high` reclaims without OOM killer; `memory.max` invokes OOM killer only when reclaim fails.

## 3. Official Documentation References

| Source | Finding |
|---|---|
| Nim Language Manual | `const` evaluated at compile time → deterministic across hardware |
| Linux Kernel cgroup-v2 Admin Guide | `memory.max` hard limit vs `memory.high` soft throttle |
| systemd CONTROL_GROUP_INTERFACE.md | Scope encapsulates fork()/exec() children; `--collect` cleans transient units |

## 4. Verification

- `nim check` passes on all modified files.
- `bin/gate_hook pre-commit` shows variable `jobs=N` per gate (heavy=4, medium=2, light=1).
- Unit test confirms deterministic dispatch order with budget 8.
