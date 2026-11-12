# BSS Segment Architecture — v26 Static Project Matrix

> SSOT for the BSS-anchored PipelineContext singleton design in the v26 verification
> pipeline. Covers memory layout, compile-time page sizing, copy/sink guards,
> branchless DFA dispatch, mmap I/O, status reduction, and MPHF lookup.

**Date:** 2026-06-19 (updated 2026-07-25)
**Supersedes:** `docs/spec/pipeline_ctx_inventory.md` (defunctionalization inventory)

> **STATUS: DESIGN ASPIRATION — NOT THE CURRENT IMPLEMENTATION**
>
> The BSS-anchored global singleton described below is a planned architecture
> target (v26). **The current implementation** uses `PipelineContext {.acyclic.} = ref object`
> (heap-allocated, GC-tracked) defined at
> `src/core/orchestration/pipeline_types.nim:29`. This document is preserved as
> the architectural guide for future migration. All `[DEPRECATED]` source paths
> have been replaced with `[PLANNED]` markers.

---

## 1. Overview

The v26 pipeline **aspires** to replace the current mutable `PipelineContext`
ref-object (33 fields, heap-allocated, GC-tracked at
`src/core/orchestration/pipeline_types.nim:29`) with a **BSS-anchored global
singleton** backed by a fixed-size memory page. The design goals:

| Goal | Mechanism |
|------|-----------|
| Zero GC pressure | `.bss` segment allocation, no heap `ref` |
| Deterministic layout | Compile-time `PageSize`, no `sysconf` |
| Compile-time copy prevention | `{.error.}` pragma on copy/sink |
| Branchless state dispatch | Table-driven DFA in `.rodata` |
| Zero-copy I/O for large files | `mmap` path gated by `MmapThreshold` |
| O(1) gate result aggregation | `StatusMask` monoid with OR-reduction |
| O(1) symbol lookup | MPHF (FNV-1a + displacement table) |

### Relationship to pipeline_ctx_inventory.md

The defunctionalization inventory (§Defunctionalization Migration Order)
identified 6 extraction categories: Guard → Terminal → Config → Artifact →
State → Loop-control. The BSS architecture **supersedes** that design by
flattening all categories into a single memory page with offset-based access
instead of named fields. The inventory's classification table remains valid
as a field-to-offset mapping guide.

### Source Files

| Component | Path |
|-----------|------|
| PipelineContext definition | `src/core/orchestration/pipeline_types.nim:29` (actual: `ref object`) |
| BSS page allocator | [PLANNED] — not yet implemented |
| DFA transition table | [PLANNED] — not yet implemented |
| StatusMask type | `src/core/orchestration/pipeline_types.nim:282` (GateResult enum — not BSS-based) |
| MPHF implementation | [PLANNED] — not yet implemented |
| mmap I/O adapter | [PLANNED] — not yet implemented |
| Copy/sink guard pragma | [PLANNED] — not needed for `ref object` (GC handles lifecycle) |

---

## 2. v26 Compile-Time Page Size

### Pattern

```nim
const PageSize {.intdefine.} = 4096
```

The `{.intdefine.}` pragma makes `PageSize` overridable via `-d:PageSize=N` at
compile time while defaulting to the x86-64 page size. No runtime `sysconf()`
or OS query is performed.

### Rationale

| Approach | Problem |
|----------|---------|
| `sysconf(_SC_PAGESIZE)` | Runtime dependency, non-deterministic, prevents static BSS sizing |
| `constexpr` with `#define` | Non-portable, C interop leakage |
| `{.intdefine.}` const | Compile-time overridable, Nim-idiomatic, zero runtime cost |

### Platform Variants

| Target | Override |
|--------|----------|
| x86-64 Linux (default) | none (4096) |
| ARM64 Linux | `-d:PageSize=16384` |
| WASM (future) | `-d:PageSize=65536` |

### Enforcement

The BSS allocator asserts at compile time that the struct fits within a single
page:

```nim
static:
  assert sizeof(PipelineContext) <= PageSize,
    "PipelineContext (" & $sizeof(PipelineContext) &
    " bytes) exceeds PageSize (" & $PageSize & ")"
```

---

## 3. Memory Layout

### PipelineContext in .bss (~155 KB)

The flattened `PipelineContext` occupies a contiguous region in the `.bss`
segment. The OS maps `.bss` as zero-initialized pages backed by physical
memory on first touch (demand paging). No explicit `calloc` or `memset` is
required.

```
  .bss layout (155 KB = 39 pages x 4096 bytes)
  +------------------------------------------+
  | Offset 0x0000: PipelineContext header     |
  |   (iteration, stagnation, loop control)  |
  | Offset 0x0100: Config region (R/O after) |
  |   (req, translation, maxIterations, ...) |
  | Offset 0x1000: State region (R/W)        |
  |   (currentSource, detected, ...)         |
  | Offset 0x8000: Artifact region           |
  |   (swatArt, caseArt, draftArt, ...)      |
  | Offset 0xC000: Guard region              |
  |   (stageHistory, terminalStatus, ...)    |
  | Offset 0xF000: Terminal region           |
  |   (result, error)                        |
  +------------------------------------------+
```

Each region offset is defined by `const` values computed at compile time from
`sizeof` of the preceding regions. Access uses `cast[ptr T](base + offset)`.

### DfaMatrix in .rodata (~2 KB)

The DFA transition table is a compile-time constant array stored in `.rodata`
(read-only data segment):

```nim
type
  DfaMatrix* = array[DfaState, array[DfaInput, DfaState]]

const DfaTransitions*: DfaMatrix = [
  # state 0: initial
  [s1, sErr, sErr, ...],
  # state 1: token received
  [s2, s1, s0, ...],
  ...
]
```

Being in `.rodata`, the table shares cache lines with code and cannot be
mutated at runtime. This is the **zero-branch** dispatch mechanism (§5).

---

## 4. Copy/Sink Guards

### Problem

Nim's copy elision and sink semantics can silently duplicate or destroy BSS-backed
values. A `PipelineContext` copy would create a dangling pointer into `.bss`; a
sink would invalidate the singleton.

### Solution

```nim
# In src/core/trusted/axiom_pragmas.nim

template noCopyGuard*(T: typedesc) =
  proc `=copy`(a: var T; b: T) {.error: "copy of BSS-anchored type forbidden".}
  proc `=sink`(a: var T; b: T) {.error: "sink of BSS-anchored type forbidden".}
```

### Application

```nim
# [PLANNED] — BSS allocation not yet implemented; uses ref object (pipeline_types.nim)

type
  PipelineContext* {.noCopyGuard.} = object
    iteration: uint16
    stagnation: uint8
    # ... 33 fields flattened ...
```

### Compile-Time Detection

Any attempt to copy or move `PipelineContext` produces a **compile-time error**:

```text
Error: copy of BSS-anchored type forbidden
```

This catches accidental copies in:
- Function return values
- Assignment expressions
- Collection inserts
- Closure captures

---

## 5. Branchless DFA

### Design

The DFA (Deterministic Finite Automaton) replaces the multi-branch `case`
dispatch in the gate orchestrator with a table lookup:

```nim
func advance*(state: DfaState, input: DfaInput): DfaState {.noSideEffect.} =
  ## O(1) branchless state transition.
  ## Two array index operations, zero conditionals.
  result = DfaTransitions[state][input]
```

### Benefits

| Metric | Branching `case` | Table-driven DFA |
|--------|------------------|------------------|
| Instruction count | 8-15 (branch prediction) | 2 (index + load) |
| Branch misprediction | ~5% on random input | 0 |
| Code size | Grows with states | Constant (2 KB table) |
| L1 cache impact | Code cache pressure | Single cache line hit |

### State Machine

The gate orchestrator DFA has 8 states and 6 input types, yielding a
`8 x 6 = 48` entry table (192 bytes at 4 bytes/entry). The `.rodata` placement
ensures the table is always hot in L1.

### Enforcement

The `nimtry` gate validates that the gate runner dispatch contains no `case`
or `if` chains with > 2 branches for state transitions. Violations are flagged
as architecture debt.

---

## 6. mmap Zero-Copy I/O

### Hybrid Strategy

The pipeline uses two I/O strategies based on file size:

```nim
const MmapThreshold* {.intdefine.} = 65536  # 64 KB

func readSource*(path: FilePath): SourceView =
  let fileSize = getFileSize(path)
  if fileSize >= MmapThreshold:
    result = mmapFile(path)       # Zero-copy, page-fault driven
  else:
    result = bufferedRead(path)   # stdlib streams, faster for small files
```

### mmap Path

```nim
# [PLANNED] — mmap I/O not yet implemented

func mmapFile*(path: FilePath): SourceView =
  let fd = openRead(path)
  let size = getFileSize(fd)
  let mapped = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
  # SourceView wraps mapped pointer + length
  # No copy occurs -- downstream sees raw file bytes
```

### Buffered Path

Files below `MmapThreshold` (most gate configuration JSONs, short Nim sources)
use `streams` for better cache locality and no page-fault overhead.

### Threshold Justification

| File Type | Typical Size | Strategy |
|-----------|-------------|----------|
| Gate config JSON | 1-5 KB | Buffered |
| Short `.nim` source | 2-20 KB | Buffered |
| Large `.nim` source | 50-200 KB | mmap |
| Proof vault JSON | 10-100 KB | mmap |
| Test fixtures | 1-50 KB | mmap |

---

## 7. StatusMask Monoid

### Definition

```nim
type
  StatusMask* = distinct uint32

  GateResult* {.pure.} = enum
    grPass    = 0x00000001
    grWarn    = 0x00000002
    grFail    = 0x00000004
    grSkip    = 0x00000008
    grTimeout = 0x00000010
    grError   = 0x00000020
```

### Monoid Properties

The `StatusMask` forms an algebraic monoid under bitwise OR:

| Property | Proof |
|----------|-------|
| **Closure** | `OR` of two `uint32` values is `uint32` |
| **Associativity** | `(a OR b) OR c = a OR (b OR c)` (bitwise) |
| **Identity** | `0'u32` is the identity element |

### OR-Reduction

Gate results are aggregated without branching:

```nim
func reduce*(results: openArray[GateResult]): StatusMask {.noSideEffect.} =
  var acc: uint32 = 0
  for r in results:
    acc = acc or uint32(r)
  result = StatusMask(acc)
```

### Extraction

```nim
func hasPassed*(mask: StatusMask): bool =   (uint32(mask) and uint32(grFail)) == 0
func hasWarnings*(mask: StatusMask): bool = (uint32(mask) and uint32(grWarn)) != 0
func anyTimedOut*(mask: StatusMask): bool = (uint32(mask) and uint32(grTimeout)) != 0
```

### Gate Integration

The pipeline orchestrator accumulates `StatusMask` across all gate runs:

```nim
var gateMask = StatusMask(0)
for gate in allGates():
  gateMask = gateMask or StatusMask(runGate(gate))
```

The final mask is checked once at pipeline termination, not per-gate.

---

## 8. MPHF O(1) Lookup

### Algorithm

The Minimal Perfect Hash Function uses FNV-1a hashing with a displacement
table to achieve O(1) lookup with zero collisions for the fixed gate name set.

### Implementation

```nim
# [PLANNED] — MPHF not yet implemented

const GateCount* = 47  # Number of registered gates

type
  MphfTable* = object
    seeds: array[GateCount, uint32]
    displacements: array[GateCount, uint32]

func fnv1a(data: openArray[char]): uint32 {.noSideEffect.} =
  result = 2166136261'u32
  for b in data:
    result = result xor uint32(b)
    result = result * 16777619'u32

func lookup*(table: MphfTable, name: string): uint32 {.noSideEffect.} =
  let h1 = fnv1a(name)
  let idx = h1 mod GateCount
  let disp = table.displacements[idx]
  result = (h1 + disp) mod GateCount
```

### Build Process

The MPHF is built at compile time from the sorted gate manifest
(`src/gate/manifest.d/*.json`, loaded via `slurp()` in `gate_codegen.nim`),
not at runtime:

1. Read manifest via `slurp` (per-gate JSON files from `manifest.d/`)
2. Extract gate IDs
3. Compute FNV-1a hashes
4. Resolve displacements via BFS on the hash graph
5. Emit as `const` array

### Performance

| Operation | Complexity | Actual Cost |
|-----------|-----------|-------------|
| Hash | O(n) where n = name length | ~20 ns for typical gate name |
| Displacement | O(1) | 1 array load |
| Final index | O(1) | 1 add + 1 modulo |

---

### Quirk Documentation

Known quirks encountered during design are documented in:

- `docs/spec/nim_effect_system_quirks.md` — `noSideEffect` false positives
- `docs/spec/declarative_effect_isolation_quirks.md` — `{.axiomIoBoundary.}`
  interaction with `mmap`
- `docs/spec/concurrency_policy.md` — BSS singleton thread-safety (single
  thread only; gate runners are sequential)

---

## Appendix A: Field-to-Offset Mapping

Derived from the inventory in `pipeline_ctx_inventory.md` (33 fields):

| Offset Range | Region | Fields | Access Pattern |
|-------------|--------|--------|----------------|
| `0x0000-0x00FF` | Header | iteration, stagnation, visitedStates | R/W |
| `0x0100-0x0FFF` | Config | req, translation, maxIterations, priorPromotion, guardNodeId, guardStartTime | R |
| `0x1000-0x7FFF` | State | loopReq, currentSource, currentInvariant, detected, useFeedback, globalRegistry, goalDeltas, leanstralLeanSource, kInduction*, bmcProven | R/W |
| `0x8000-0xBFFF` | Artifact | swatArt, caseArt, draftArt, scribeArt, judgeArt | R |
| `0xC000-0xEFFF` | Guard | guardCurrentStage, guardStageHistory, guardTerminalStatus, guardExitMessage | W |
| `0xF000-0xF0FF` | Terminal | result, error | W |

Exact offsets are `const` values computed from `sizeof` sub-types at compile
time. The field inventory (33 fields) maps the ref-based `PipelineContext` defined
in `src/core/orchestration/pipeline_types.nim`; the BSS-flattened singleton is
realized in `src/core/gate/static_project_matrix.nim`. Compile-time enforcement via
`static: assert` (like `topology_checker.nim`) is not yet wired — the layout contract is currently documented-only, not enforced.

---

## Appendix B: Build Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `-d:PageSize=N` | 4096 | Override compile-time page size |
| `-d:MmapThreshold=N` | 65536 | Override mmap/buffered I/O threshold |
| `` | (unset) | Skip gate bond verification (CI only) |

---

## Appendix C: Migration from Ref-Based PipelineContext (HISTORICAL)

> **NOTE:** This migration was planned for v26 but has NOT been executed.
> The `PipelineContext {.acyclic.} = ref object` at
> `src/core/orchestration/pipeline_types.nim:29` remains the current
> implementation. This appendix is preserved for reference.

The ref-based `PipelineContext` (heap-allocated `ref object`) is the current
implementation as of 2026-07-25. The migration to BSS-backed global singleton
would follow these steps:

1. All `ctx.fieldName` accesses become offset-based via accessor functions.
2. Guard fields are written through `GuardState` wrappers (no business logic).
3. Terminal fields (`result`, `error`) are stored in `Transition[T]`.
4. Artifact fields are no longer persisted in context -- they are consumed
   within the stage that produces them.

The defunctionalization migration order from `pipeline_ctx_inventory.md` remains
valid as the implementation roadmap for the BSS migration.
