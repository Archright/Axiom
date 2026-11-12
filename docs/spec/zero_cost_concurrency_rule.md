# Zero-Cost Concurrency Rule

> **AGENTS.md §0.6 / §0.6a implementation specification.**
> Defines when and how concurrent code is permitted in Axiom, ensuring zero heap overhead for value-type message passing.
>
> **Parent documents**: [concurrency_policy.md](concurrency_policy.md) (decision tree + forbidden patterns),
> AGENTS.md §0.6 (Static First Enforcement), AGENTS.md §0.6a (Concurrent Code Policy).

---

## 1. Purpose

Define when and how concurrent code is permitted in Axiom, ensuring zero heap overhead for value-type message passing through `Channel[T]`. This rule complements the concurrency decision tree in `concurrency_policy.md` by specifying the memory-level guarantee that makes thread-safe message passing efficient.

## 2. Core Principle

`Result[T, E]` where `T` and `E` are value types (no `string`/`seq`/`ref` fields) can be sent through `Channel[T]` with **ZERO heap allocation**. This is guaranteed by Nim's ARC/ORC memory model for value types: when all fields are plain data types (`int`, `float`, `enum`, fixed-size `object`, `tuple`), the compiler performs a bitwise copy — no reference counting, no heap indirection.

The project exploits this property to build a concurrency model where inter-thread communication carries **no allocator tax**.

### 2.1 What counts as a value type

| Category | Examples | Heap alloc on Channel send? |
|----------|----------|-----------------------------|
| Scalar | `int`, `float`, `bool`, `enum` | No |
| Fixed object (no ref/ptr/seq/string fields) | `object { x: int, y: float }` | No |
| Tuple of value types | `(int, float, bool)` | No |
| `seq[ValueT]` where ValueT is value type | `seq[int]`, `seq[MyEnum]` | **Yes** (seq body is heap) |
| `string` | any string | **Yes** (string body is heap) |
| `ref object` | any ref | **Yes** (pointer + RC) |
| `ptr`, `pointer` | any raw pointer | N/A (unsafe, forbidden) |

**Rule**: A type is "zero-cost" for Channel transfer only when **every field** is a value type with no heap-managed components. `seq` and `string` are **not** zero-cost despite being copyable — they allocate on the heap.

### 2.2 The `Result[T, E]` constraint

For `Result[ProofCert, ProofError]` to achieve zero-cost Channel transfer:

- `ProofCert` must contain only value-type fields
- `ProofError` must be an enum (or fixed object with only value-type fields)
- **String/seq/ref error types are FORBIDDEN in channel messages** — enforced by the `supportsCopy` guard in `results.nim` (SA-2.4)

```nim
# ✅ ZERO-COST: enum error, value-type payload
type
  ProofError = enum
    ioError, parseError, timeout, internal

  ProofCert = object
    gateId: int
    hash: array[32, uint8]  # fixed-size array = value type
    passed: bool

  ProofResult = Result[ProofCert, ProofError]

# ❌ NOT ZERO-COST: string error allocates on heap
type
  BadResult = Result[ProofCert, string]  # string = heap alloc
```

## 3. Rules

### 3.1 Value-Type Channel Transfer

- `Channel[Result[T, E]]` where T, E are value types → `{.bycopy.}` semantics, 0 heap alloc
- Enum error types (`IoError`, `ParseError`, `Timeout`, etc.) satisfy this constraint
- String/seq/ref error types are **FORBIDDEN** in channel messages (enforced by supportsCopy guard in results.nim)
- When returning results from spawned workers, always use the `Result[ValueObject, EnumError]` pattern — never `Result[ValueObject, string]`

**Existing project precedent**: `src/core/observer/types.nim` uses `{.bycopy.}` on `PipelineContext` for this exact reason — zero-copy transfer across module boundaries.

### 3.2 Concurrency Backend Selection

| Pattern | Backend | Use Case | Project example |
|---------|---------|----------|-----------------|
| CPU-bound parallel | malebolgia | BMC batch, proof generation, gate scanning | Future: batch_uap |
| I/O-bound async | asyncdispatch | Network, file I/O, subprocess management | `lean_lsp.nim`, MCP server |
| Process isolation | startProcess | Hermetic build, solver invocation | `runner_process_pool.nim` |
| Message passing | `Channel[T]` | Inter-worker result aggregation | `lean_lsp_types.nim` (msgChannel) |

**Selection criteria**:
1. Is it CPU-bound or I/O-bound? → See `concurrency_policy.md` §1 decision tree
2. Do spawned workers need to return results? → If value types, use `Channel[T]`
3. Do workers need OS isolation (untrusted code, solver)? → Use `startProcess` with bounded concurrency (`MaxConcurrentL2 = 4`)

### 3.3 Forbidden Patterns

| Pattern | Reason | Alternative |
|---------|--------|-------------|
| `spawn` with `ref object` | Non-atomic RC corruption across threads | Convert to value type or use `startProcess` |
| Non-cyclic `ref object` without `{.acyclic.}` | ORC cycle collector overhead on known-acyclic types | Add `{.acyclic.}` pragma |
| `Thread[tuple[...]]` with ref fields | Same RC corruption risk as spawn with ref | Value-type tuple fields only |
| Global `var` in concurrent context | Data race | Use `ThreadLocal[T]` or message passing via Channel |
| Nested `createMaster()` | Unbounded thread explosion (OOM, 377-process incident) | Single-level `createMaster` + `awaitAll` only |
| `Channel[string]` for result passing | Heap allocation on every send | Use `Channel[Result[T, EnumError]]` |

### 3.4 malebolgia Integration

When re-introduced for CPU-bound work (e.g., BMC batch processing), malebolgia MUST follow the 6-point checklist in `concurrency_policy.md` §1. Key zero-cost pattern:

```nim
import malebolgia

type
  BatchResult = object
    cert: ProofCert       # value type
    error: ProofError     # enum = value type
    duration: float

proc processOne(item: TaskSpec): BatchResult {.gcsafe.} =
  ## Pure CPU work. No ref types, no startProcess.
  let start = cpuTime()
  let cert = runBmcVerification(item)
  let err = if cert.isOk: noError else: cert.error
  BatchResult(cert: cert.get(), error: err, duration: cpuTime() - start)

proc processBatch(items: seq[TaskSpec]): seq[BatchResult] =
  var results = newSeq[BatchResult](items.len)
  var m = createMaster()
  m.awaitAll:
    for i in 0..<items.len:
      m.spawn processOneInto(items[i], results[i])
  result = results
  # All value types — results[i] is a bitwise copy, zero heap alloc
```

**Why this is zero-cost**:
- `BatchResult` contains only value-type fields (`ProofCert`, `ProofError` enum, `float`)
- malebolgia's `spawn` copies value-type args bitwise — no RC, no heap, no GC pressure
- Results accumulate in pre-allocated `seq[BatchResult]` — no string concatenation

### 3.5 Channel-Based Aggregation Pattern

For inter-worker result aggregation where `malebolgia` is not suitable (e.g., heterogeneous worker types):

```nim
type
  WorkerResult = object
    gateId: int
    passed: bool
    proofHash: uint64

var chan: Channel[WorkerResult]
chan.open()

# Worker thread (value-type only through channel)
proc workerFn(spec: GateSpec) {.gcsafe.} =
  let result = evaluateGate(spec)
  chan.send(WorkerResult(
    gateId: spec.id,
    passed: result.ok,
    proofHash: result.hash
  ))

# Aggregator (main thread)
var received: seq[WorkerResult]
while received.len < expectedCount:
  var r: WorkerResult
  chan.recv(r)
  received.add(r)

chan.close()
```

**Key constraint**: `WorkerResult` must not contain `string`, `seq`, or `ref` fields. If a string is needed (e.g., diagnostic message), write it to a file and send only the file path as a fixed-size field, or use a separate `Channel[string]` with awareness that each send allocates.

## 4. Enforcement

| Layer | Mechanism | What it catches |
|-------|-----------|-----------------|
| **Compile-time gate** | `supportsCopy` guard in results.nim | Heap-allocated E types in Result used in channel contexts (SA-2.4) |
| **Nimtry static analysis** | SSOT queries | Detects `ref object` in `spawn` args, missing `{.acyclic.}` on non-cyclic refs |
| **Nim compiler** | `{.acyclic.}` enforcement via `axiomAcyclic` pragma | Cycle collector optimization for known-acyclic types |
| **Gate: structural_safety** | `structural_safety_gate.nim` | Detects forbidden concurrency patterns in source |
| **Gate: dag_enforcement** | `dag_enforcement_gate.nim` | Validates task DAG for spawn safety |
| **Process pool** | `runner_process_pool.nim` bounded concurrency | Enforces `MaxConcurrentL2 = 4`, memory-aware throttling |

## 5. Relation to AGENTS.md

| AGENTS.md section | This spec's coverage |
|-------------------|---------------------|
| **§0.6** Static First Enforcement | Value types enable `func`-default in concurrent workers (no side effects from RC management) |
| **§0.6a** Concurrent Code Policy | §3.2–3.4 expand the backend selection matrix with zero-cost constraints |
| **SA-2.4** supportsCopy constraint | §2.2 formalizes why enum errors are mandatory in channel Result types |
| **concurrency_policy.md** §1 | §3.4–3.5 provide zero-cost code patterns for the malebolgia and Channel backends |

## 6. Change History

| Date | Change | Reason |
|------|--------|--------|
| 2026-06-26 | Initial draft | Formalize zero-cost concurrency constraint per §0.6a |
