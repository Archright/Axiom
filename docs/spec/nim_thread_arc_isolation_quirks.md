# Nim 2.2 Thread Isolation (ARC/ORC) quirks

Status: documented 2026-08-04 (architect-approved; pairs with §0.6a Concurrent Code Policy and DEBT#415).

## 1. ARC/ORC model: shared heap + `Isolated[T]` boundary

Under ARC/ORC memory management (used for Nim 2.2, the Axiom toolchain), the managed
heap is **shared** across threads. Thread-local storage is not what guarantees safety;
instead the *compiler's isolation checker* enforces that only values reachable through
an `Isolated[T]` container may cross a channel/thread boundary.

Consequences:

- Value-type data is trivially transferable.
- Any `ref object` / `seq` / `string` field living on the shared heap must be wrapped
  in `Isolated[T]` (or the object must be kept entirely local) to pass the isolation
  check at `createThread` / `Channel.send`.
- Passing a plain heap-allocated value with nested `ref`/`seq` fields across a thread
  boundary triggers the Nim 2.2 isolation error at compile time — it is NOT a runtime
  hazard, it is a compiler-enforced diagnostic.

## 2. `{.cast(gcsafe).}` is forbidden

`{.cast(gcsafe).}` suppresses the compiler's thread-isolation checks. Doing so can
smuggle shared, mutable heap state across threads and produce data races /
use-after-free that ARC/ORC cannot guard against. Per GUARDIAN (Ideal/Elegant/
Fundamental), this is a hard non-goal: **never silence the isolation checker**. If the
isolation check rejects a valid scenario, restructure the data (e.g. `Isolated[T]`,
per-worker heap via `create`, or make it pure value-type) instead of casting.

## 3. malebolgia is value-type only (§0.6a)

malebolgia spawn tasks are CPU-bound and must be operand in value-type form only.
Per §0.6a, `spawn` with `ref object` is FORBIDDEN. Mixed/`ref` payloads cause the same
Nim 2.2 isolation rejection described above.

## 4. Canonical pattern: createThread + threadvar + Channel

The sanctioned concurrency pattern is:

1. `createThread(thread, proc, arg)` with a `{.thread.}` worker proc.
2. Heap-allocate the worker context via `create(T)` and pass a `ptr T` to the worker —
   this intentionally avoids the isolation check on `seq`/`ref` fields that must be
   read/written within a single worker, without bypassing cross-thread safety.
3. `threadvar` for per-thread state, and `Channel` for message passing.

### Reference precedent — `src/cli/axiom_engine.nim`

- `src/cli/axiom_engine.nim:104-115` — `ParallelIrContext` is allocated with
  `create(ParallelIrContext)`; comment records that this exists precisely to bypass
  malebolgia's Nim 2.2 isolation check on `seq`/`ref` fields (`IRFuncDef`/`IRExpr`
  are `ref object`). The worker writes results back into the shared context.
- `src/cli/axiom_engine.nim:255-258` — `irCtx = create(ParallelIrContext)` then
  `createThread(irThread, irPipelineWorker, irCtx)`; the `{.thread.}` proc
  `irPipelineWorker` consumes the pointer and emits results region-locally.

## 5. CI vCPU worker cap rule — DEBT#415

The worker fan-out must be capped: **AXIOM_PROVE_WORKERS ≤ vCPU**.

- CircleCI **Standard** class exposes 2 vCPU. Oversubscribing workers beyond that
  causes thread thrashing and sporadic SIGSEGV at runtime — tracked as **DEBT#415**.
- Until the scheduler is repaired, the safe default is **serial (1 worker)** fixed.
- The `--workers` flag wires AXIOM_PROVE_WORKERS via env (`src/cli/axiom_engine.nim:725-727`).
  Callers must not raise it above the detected CPU count, and CI dev/soft-skip mode
  must default to 1.