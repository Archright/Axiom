# 2026-05-28 Layered Gate Architecture with Concurrency Cap

## Intent

Eliminate pre-commit freezes caused by CPU saturation from 15 concurrent L2 functional gates. Implement a layered gate architecture with L1 Meta sequential fail-fast and L2 Functional parallel dispatch capped at MaxConcurrentL2=4.

## Changes

### 1. Layered Architecture (Ideal)

- Added `GateLayer` enum with `glOrchestrator`, `glMeta`, `glFunctional`
- Assigned layers to all 20 gates: 4 L1 Meta, 16 L2 Functional
- `gate-self-check`, `sentinel`, `unstaged-guard`, `quality-gate-marker` → L1 Meta
- `cli-build` moved from `gsPreCommit` to `gsPrePush` only
- `unstaged-guard` extracted from `cli-build` as standalone L1 Meta gate
- Compile-time `static` assertions prevent Meta gates from referencing orchestrator entry points

### 2. Concurrency Cap (Deterministic)

- `MaxConcurrentL2 = 4` hard limit on simultaneous L2 gate processes
- `effectiveMaxJobs = max(1, maxJobs div min(l2Gates.len, MaxConcurrentL2))`
- Batch-pool dispatch with `peekExitCode` polling and `sleep(50)` backoff
- Verified: 15 L2 gates execute in 4 concurrent batches with 3 CPU cores each

### 3. Resource Stack (Elegant)

- L1 CPU cap: `countProcessors() div 2`
- L2 nice: `-n 10`
- L3 cgroups v2: `systemd-run --slice=axiom-gate`
- L4 memory: `RLIMIT_AS` 1536MB

### 4. Incremental Build (Fundamental)

- `cli-build` now accepts `passFilenames` for scoped hash calculation
- `refresh_cli_binaries.nim` filters tracked sources by changed files
- Pre-push parallelism verified: 3 L2 gates run simultaneously

## Files Changed

- `src/gate/types.nim` — `GateLayer` enum, `safeMaxJobs`, `setProcessMemoryLimit`
- `src/gate/manifest.d/_index.json` — layer assignments, compile-time assertions
- `scripts/gate_hook.nim` — `runAllGatesParallel` with L1/L2 split and concurrency cap
- `src/gate/runners/cli_build.nim` — stripped unstaged check, `passFilenames` support
- `src/gate/runners/unstaged_guard.nim` — new L1 Meta gate (< 100ms)
- `src/gate/runners/proof_universe_lock_gate.nim` — Merkle verification with fast/slow path
- `tests/features/gate_list.feature` — specification record
- `tests/features/unstaged_guard.feature` — specification record
- `tests/features/proof_universe_lock_gate.feature` — specification record
- `tests/unit/gate_list_test.nim` — test record
- `tests/unit/unstaged_guard_test.nim` — test record
