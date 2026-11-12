# Threadpool Migration Specification

> **Note**: For current concurrency policy and decision tree, see `docs/spec/concurrency_policy.md`.
> This document records the historical migration decision from `std/threadpool` to `malebolgia`.

## Background

`std/threadpool` is officially deprecated in Nim 2.0+ with ARC/ORC. The standard library explicitly recommends `malebolgia`, `taskpools`, or `weave` as replacements. Axiom previously used `FlowVar[T]`, `spawn`, `isReady` polling, and `^` (blocking read) in:

- `src/verification/orchestrator.nim` — parallel proof task execution
- ~~`src/cli/commands/heal.nim`~~ (deleted) — parallel heal node execution (historical: removed in CLI amputation; heal logic migrated to `src/cli/axiom_engine.nim`)

## Decision: malebolgia

### Why malebolgia

| Library | GC-ed Types | Blocking Tasks | Nim 2.0/ORC | Designer | Verdict |
|---------|-------------|----------------|-------------|----------|---------|
| **weave** | Untested | Forbidden | Unverified | Community | **Reject** |
| **taskpools** | Non-goal | Untested | Unverified | Status-im | **Reject** |
| **malebolgia** | Designed for ORC | Supported | Officially recommended | Andreas Rumpf (Nim creator) | **Adopt** |

- **weave**: HPC-optimized for trillions of fine-grained tasks. Explicitly untested with GC-ed types. Blocking tasks (e.g., SMT solver calls) break the work-stealing scheduler.
- **taskpools**: Lightweight but GC-ed string/seq support is a non-goal.
- **malebolgia**: Sub-300-line structured concurrency library designed for Nim 2.0 ORC. Built-in cancellation, timeout, and backpressure.

### Rejected Alternatives

#### Zero-Copy Ownership Transfer (Gemini Proposal)

Rejected because:
1. Nim lacks linear/affine type system → compile-time enforcement impossible.
2. ARC/ORC assumes thread-local heap semantics → arena ownership transfer incompatible.
3. `std/string` is Nim's stdlib foundation → ban requires total rewrite.
4. Nim `view`/`cursor` are experimental → unsuitable for production infrastructure.

Ideal preserved for future: If Axiom migrates to Rust or Nim gains stable borrow checking, zero-copy ownership transfer becomes viable. Transition condition: language-level linear type support + stable MM API.

## Implementation

### Pattern: `awaitAll` + `spawn ... -> result[i]`

malebolgia eliminates `FlowVar[T]` and `isReady` polling. Instead:

```nim
import malebolgia

var results = newSeq[ParallelTaskResult](inputs.len)
var m = createMaster()
m.awaitAll:
  for i in 0 ..< inputs.len:
    m.spawn executeParallelTask(addr inputs[i]) -> results[i]
```

### `ptr` Boundary Workaround

malebolgia's `spawn` macro uses `toTask`, which internally calls `isolate` on arguments. `isolate` rejects existing variables (e.g., `healInputs[i]`) unless they are created entirely within the spawn expression.

**Solution**: Pass `ptr T` instead of value `T`. Pointers are primitive values that `isolate` accepts without restriction. The callee immediately dereferences:

```nim
proc executeParallelTask(inputPtr: ptr ParallelTaskInput): ParallelTaskResult {.gcsafe.} =
  let input = inputPtr[]
  # ... rest of logic unchanged
```

This is safe because:
- `inputs` is read-only during `awaitAll`.
- `awaitAll` guarantees all tasks complete before the proc returns.
- No thread accesses `inputs` after `runParallelDepth` returns.

### File Changes

| File | Change |
|------|--------|
| `src/verification/orchestrator.nim` | Removed `std/threadpool`. Added `malebolgia`. `runParallelDepth` uses `awaitAll` batch pattern. `executeParallelTask` takes `ptr ParallelTaskInput`. |
| ~~`src/cli/commands/heal.nim`~~ (deleted) | **Historical**: removed in CLI amputation. Heal logic migrated into `src/cli/axiom_engine.nim`. Original change: Removed `std/threadpool`, added `malebolgia`, parallel loop uses `awaitAll` batch pattern. |
| `axiom.nimble` | Added `requires "malebolgia >= 1.0.0"` (already present). |

### API Compatibility Notes

- `runParallelDepth` still accepts `maxWorkers` and `wallDeadlineMs` parameters for backward compatibility and deterministic scheduling.
  - `maxWorkers`: enforced by chunking spawned Malebolgia tasks into bounded batches. The runtime solver semaphore remains the second guardrail inside each worker.
  - `wallDeadlineMs`: checked before each batch. A batch already submitted to `awaitAll` is allowed to finish so no worker is orphaned.

## Ideal vs Fallback

| Dimension | Ideal (POD + Serialization) | Current (malebolgia + ptr) |
|-----------|------------------------------|---------------------------|
| Memory model | Explicit (no GC ambiguity) | Implicit (ORC deterministic destruction) |
| Transfer cost | $O(N)$ canonical bytes | $O(N)$ deep copy (malebolgia internal) |
| Integrity guarantee | Structural (compile-time) | Runtime (scope-based `awaitAll`) |
| Determinism | Strong (zero-copy where possible) | Strong (ARC/ORC scope hooks) |

**Why ideal is currently impossible**:
- Nim does not have a stable linear type system or compile-time borrow checker.
- `std/isolation` + `threading/channels` exist but `isolate` only accepts expressions created inside the call, making batch processing of existing inputs impossible without `ptr` workaround.
- A full rewrite to manual memory management (`AxiomBuffer`) would break standard library interop (JSON, strutils, os, etc.).

**Transition condition to ideal**:
1. Nim `concept` reaches stable release AND supports thread-boundary contracts.
2. ORC provides explicit `moveToThread` primitive with compile-time use-after-move checking.
3. Phase 6 LiquidInference completion provides bandwidth for domain-wide memory model refactoring.

## Verification Checklist

- [x] `nim c src/cli/main.nim` compiles with zero `threadpool` warnings.
- [x] ~~`./bin/main gate run` passes all 12 gates.~~ *(Historical: `gate run` subcommand removed. Gates now run via `ax prove` pipeline.)*
- [x] `./bin/main ax prove` shows no certificate invalidation or new mismatch.
- [x] ~~`./bin/main ax heal --limit 5` shows no new `unverifiable` nodes.~~ *(Historical: `ax heal` removed. Heal verification is now part of `ax prove`.)*
