# Z3 FFI Architecture Specification

> **STATUS: REMOVED (v30)**
> Z3 FFI bindings have been removed from the Axiom project.
> All Z3 solver interactions now use the CLI subprocess path via `src/verification/solver/z3_pool.nim`.
> See AGENTS.md §1 for rationale and §10 below for removal details.

> Phase 4D — Z3 C-API FFI bindings with move-only lifecycle, thread-local pool, and CLI fallback.
> AGENTS.md §1 architecture decision v30. This document is the SSOT for Z3 FFI design.
> **Historical reference only** — the FFI path described below is no longer active.

---

## §1. Overview

> **REMOVED**: The FFI path described in this section is no longer active. All Z3 interactions now use the CLI subprocess path only. This section is preserved for historical reference.

Axiom **used to** support Z3 (the SMT solver) via two complementary paths:

| Path | Module | Mechanism | Status |
|------|--------|-----------|--------|
| ~~**FFI** (in-process)~~ | ~~`src/verification/solver/z3_bindings.nim`~~ | ~~Nim `{.importc.}` + `{.dynlib.}` against `libz3.so`~~ | **REMOVED** (v30) |
| **CLI** (subprocess) | `src/verification/solver/z3_pool.nim` | `startProcess("z3", ["-smt2", "-in"])` + pipe I/O | **Active** — sole Z3 path |

The **Interactive Stream** (`src/core/solver/z3_interactive.nim`) provides persistent Z3 sessions with sync-marker-based deadlock elimination for incremental k-induction.

The CLI subprocess path is the **only** active Z3 path. The FFI path was removed due to hang vulnerability, theory mismatch, no async cancellation, and TCB bloat (see §10).

---

## §2. Thread-Local Isolation Architecture

> **HISTORICAL**: The FFI types and thread-local pool described below are removed. Preserved for reference on move-only type patterns in Nim.

### 2.1 Move-Only Types

Z3 is **not thread-safe**. A `Z3_context` must not be accessed from multiple threads simultaneously. Axiom enforces this at compile time through move-only semantics on the Nim wrapper types.

**Source**: `src/verification/solver/z3_bindings.nim`

```nim
type
  Z3ContextObj = object
    raw: Z3ContextRaw     # pointer to Z3 C-API context
    closed: bool          # idempotent close guard

  Z3Context* {.acyclic.} = ref Z3ContextObj
    ## RAII Z3 context — move-only, single-owner.
    ## NOT thread-safe (Z3 requirement). Use one per thread.

  Z3SolverObj = object
    ctx: Z3Context        # keep parent alive (prevent premature destroy)
    raw: Z3SolverRaw
    closed: bool

  Z3Solver* {.acyclic.} = ref Z3SolverObj
    ## RAII Z3 solver — move-only, single-owner.
```

#### Move-Only Hooks (per Nim 2.2.10 requirement: hooks attach to *object* types, not ref types)

```nim
# Z3ContextObj
proc `=destroy`(o: var Z3ContextObj) =
  if not o.closed:
    z3_del_context(o.raw)
    o.closed = true

proc `=copy`(dest: var Z3ContextObj; source: Z3ContextObj)
  {.error: "Z3Context cannot be copied; use move semantics".}

proc `=dup`(source: Z3ContextObj): Z3ContextObj
  {.error: "Z3Context cannot be duplicated; use move semantics".}

# Z3SolverObj
proc `=destroy`(o: var Z3SolverObj) =
  if not o.closed:
    if o.ctx != nil and not o.ctx.closed:
      z3_solver_dec_ref(o.ctx.raw, o.raw)
    o.closed = true

proc `=copy`(dest: var Z3SolverObj; source: Z3SolverObj)
  {.error: "Z3Solver cannot be copied; use move semantics".}

proc `=dup`(source: Z3SolverObj): Z3SolverObj
  {.error: "Z3Solver cannot be duplicated; use move semantics".}
```

**Guarantees**:
- `=destroy` ensures `z3_del_context` / `z3_solver_dec_ref` are called exactly once via the `closed` flag.
- `=copy{.error.}` and `=dup{.error.}` produce **compile-time errors** if anyone attempts to copy a context or solver.
- `sink` parameters on constructors (`newZ3Solver*(ctx: sink Z3Context)`) enforce single-owner transfer at the call site.

### 2.2 Sink Parameter Ownership Transfer

```nim
proc newZ3Solver*(ctx: sink Z3Context): Z3Solver {.axiomEffect: IOEffect.} =
  ## Takes ownership of ctx via move (sink param).
  let rawCtx = ctx.raw
  let rawSlv = z3_mk_solver(rawCtx)
  # ...
  result = Z3Solver(ctx: ctx, raw: rawSlv, closed: false)
```

The `sink` annotation means the caller **gives up** ownership of `ctx`. After this call, the original variable is consumed and must not be used. This prevents double-free by design.

### 2.3 Thread-Local Context Pool

**Source**: `src/verification/solver/z3_context_pool.nim`

```nim
const MaxPoolSize* = 4  # Max contexts cached per thread

type
  Z3PoolSlot = object
    ctx: Z3Context
    inUse: bool

  Z3ContextPool* = object
    slots: array[MaxPoolSize, Z3PoolSlot]
    count: int
    created: int   # total contexts created (for metrics)

# Thread-local pool — one per thread, no cross-thread contention
var threadZ3Pool* {.threadvar.}: Z3ContextPool
```

**Lifecycle**:

1. **Acquire**: `pool.acquire()` returns a `Z3Context` from the pool (or `nil` if empty — caller creates new).
2. **Use**: Caller operates on the context (loads formulas, checks satisfiability).
3. **Release**: `releaseToThread(ctx)` returns the context to the thread-local pool.
4. **Destroy**: When the thread exits or pool is destroyed, `=destroy` hooks chain: pool → slot → `Z3ContextObj` → `z3_del_context`.

```nim
proc acquire*(pool: var Z3ContextPool): Z3Context =
  if pool.count > 0:
    dec pool.count
    result = move(pool.slots[pool.count].ctx)  # move, not copy
  else:
    result = nil  # Caller must create new via newZ3Context()

proc release*(pool: var Z3ContextPool, ctx: sink Z3Context) =
  if pool.count < MaxPoolSize and not ctx.isNil:
    pool.slots[pool.count] = Z3PoolSlot(ctx: ctx, inUse: false)
    inc pool.count
  # If pool is full, sink parameter consumed → =destroy frees it
```

### 2.4 RAII Lifecycle via ARC Destructor Hooks

The destruction chain is:

```
Thread exit / scope end
  └─ Z3ContextPool =destroy
       └─ Z3PoolSlot =destroy
            └─ Z3Context =destroy (ARC refcount → 0)
                 └─ Z3ContextObj =destroy
                      └─ z3_del_context(raw)  ← Z3 C-API cleanup
```

No manual cleanup is required. The `closed: bool` flag on each object ensures idempotent destruction even if `close()` was called explicitly before scope exit.

---

## §3. Error Handling

> **HISTORICAL**: The FFI error handling patterns described below are removed. The CLI subprocess path handles errors via process exit codes and timeout mechanisms.

### 3.1 Z3_set_error_handler Callback Pattern

By default, Z3 calls `exit()` on internal errors (invalid AST, type mismatch, etc.). This is unacceptable for a library — it kills the host process without recovery.

**Solution** (Phase 2D): Register a custom error handler on every new context that captures the error code instead of aborting.

```nim
var z3LastError {.threadvar.}: Z3ErrorCode   # thread-local

proc z3ErrorHandler(ctx: Z3ContextRaw, ec: Z3ErrorCode) {.cdecl, used.} =
  ## Z3 error handler callback — stores error code for post-call check.
  z3LastError = ec

# Registered per-context:
proc newZ3Context*(): Z3Context =
  let raw = z3_mk_context(nil)
  z3_set_error_handler(raw, cast[pointer](z3ErrorHandler))
  result = Z3Context(raw: raw, closed: false)
```

**Pattern origin**: Z3 Java JNI binding uses the same approach.

### 3.2 Post-call checkZ3Error Validation

After every critical Z3 API call, `checkZ3Error` inspects the error code and raises a `CatchableError` if non-OK:

```nim
proc checkZ3Error(ctx: Z3ContextRaw) =
  let code = z3_get_error_code(ctx)
  if code != Z3Ok:
    let msg = $z3_get_error_msg(ctx, code)
    raise newException(CatchableError,
      "Z3 error (code " & $cint(code) & "): " & msg)
```

**Where called**:
- After `newZ3Solver()` — catches context/solver creation errors
- After `loadSmtlib()` — catches formula parse errors
- After `check()` — catches satisfiability check errors

### 3.3 NULL Return Checks

Z3 API functions can return NULL on allocation failure. Both constructors check:

```nim
proc newZ3Context*(): Z3Context =
  let raw = z3_mk_context(nil)
  if cast[pointer](raw) == nil:
    raise newException(CatchableError,
      "Z3_mk_context returned NULL — Z3 library may be corrupted")

proc newZ3Solver*(ctx: sink Z3Context): Z3Solver =
  let rawSlv = z3_mk_solver(rawCtx)
  if cast[pointer](rawSlv) == nil:
    raise newException(CatchableError, "Z3_mk_solver returned NULL")
```

### 3.4 CLI Fallback When FFI Unavailable

When `z3FFIEnabled` is `false` (compile-time), stub types are compiled that raise `CatchableError("FFI not enabled at build time")` on every operation:

```nim
else:
  # CLI Mode: stubs
  proc newZ3Context*(): Z3Context =
    raise newException(CatchableError, "FFI not enabled at build time")

  proc check*(solver: Z3Solver): Z3SatResult =
    raise newException(CatchableError, "FFI not enabled at build time")

  proc isAvailable*(): bool = return false
```

Callers that need Z3 can catch this and fall back to the subprocess pool (`z3_pool.nim`).

---

## §4. FFI Auto-Detection

> **HISTORICAL**: The FFI auto-detection mechanism described below is removed. The CLI subprocess path is the sole Z3 path.

### 4.1 gorge()-based z3FFIEnabled Constant

**Source**: `src/verification/solver/z3_bindings.nim` lines 31–37

```nim
const Z3LibPath {.strdefine.} = "vendor/z3/lib/libz3.so"

# Compile-time auto-detection
const z3LibAutoDetected =
  gorge("test -f ../../../vendor/z3/lib/libz3.so && echo yes || echo no")
    .strip() == "yes"

const z3FFIEnabled* =
  defined(ffiEnabled) or (not defined(ffiDisabled) and z3LibAutoDetected)
```

### 4.2 Three-Way Priority

| Priority | Flag | Result | Use Case |
|----------|------|--------|----------|
| 1 (highest) | `-d:ffiDisabled` | `z3FFIEnabled = false` | Force CLI mode (debug, CI without Z3) |
| 2 | `-d:ffiEnabled` | `z3FFIEnabled = true` | Force FFI mode (skip detection) |
| 3 (default) | none | Auto-detect via `gorge()` | Production builds |

**Quirk**: `gorge()` returns empty string during `nim check` (see AGENTS.md §1 gorge() Z3 PATH Quirk). The auto-detect expression handles this: empty string ≠ "yes" → FFI disabled → safe fallback.

### 4.3 vendor/z3/lib/libz3.so Discovery

`findZ3Lib()` searches in priority order:

```
1. $AXIOM_Z3_LIB environment variable
2. Z3LibPath const ("vendor/z3/lib/libz3.so")
3. System paths:
   /usr/lib/libz3.so
   /usr/lib/x86_64-linux-gnu/libz3.so
   /usr/local/lib/libz3.so
4. Vendor paths:
   vendor/z3/lib/libz3.so
   vendor/z3/libz3.so
5. "" (not found)
```

The vendored copy at `vendor/z3/lib/libz3.so` is the primary target. It is tracked via Git LFS (see AGENTS.md §0.6b).

### 4.4 Z3 Binary Path Resolution (CLI mode)

**Source**: `src/core/types/z3_solver_config.nim`

```nim
proc resolveZ3Path*(): string =
  # 1. $AXIOM_Z3_PATH (explicit override)
  # 2. $HOME/.local/bin/z3 (known install location)
  # 3. "z3" (bare PATH lookup)
```

---

## §5. Safety Guarantees

> **HISTORICAL**: These guarantees applied to the FFI path, which has been removed. Preserved for reference on move-only type patterns in Nim.

### 5.1 Move-Only Prevents Double-Free

Nim's `{.error.}` pragmas on `=copy` and `=dup` produce **compile-time errors** if anyone attempts:

```nim
let ctx1 = newZ3Context()
let ctx2 = ctx1   # ❌ COMPILE ERROR: "Z3Context cannot be copied"
let ctx3 = =dup(ctx1)  # ❌ COMPILE ERROR: "Z3Context cannot be duplicated"
```

Only `move` (implicit via sink, explicit via `move()`) transfers ownership.

### 5.2 Sink Parameters Enforce Single-Owner Transfer

```nim
proc newZ3Solver*(ctx: sink Z3Context): Z3Solver
```

After calling `newZ3Solver(myCtx)`, `myCtx` is consumed. The compiler prevents any subsequent use of `myCtx`. This guarantees exactly one `Z3Solver` holds the context at any time.

### 5.3 {.acyclic.} Prevents Cycle Collector Overhead

Both `Z3Context` and `Z3Solver` are marked `{.acyclic.}`:

```nim
Z3Context* {.acyclic.} = ref Z3ContextObj
Z3Solver* {.acyclic.} = ref Z3SolverObj
```

This tells Nim's ARC/ORC that these types cannot participate in reference cycles, eliminating cycle-detection overhead. This is safe because:

- `Z3Solver` references its parent `Z3Context` (forward reference, not cyclic).
- `Z3Context` never references a `Z3Solver`.
- The destruction order is enforced: solver destroys before context (context holds the raw pointer; solver calls `z3_solver_dec_ref` in its own `=destroy`).

### 5.4 SIGSEGV Not Catchable — Mitigations

Z3 is a C library. Internal NULL dereferences or use-after-free in Z3 produce `SIGSEGV`, which cannot be caught as a Nim exception. Mitigations:

| Mitigation | Layer | Description |
|------------|-------|-------------|
| `z3_set_error_handler` | Pre-call | Prevents Z3 from calling `exit()` on API errors |
| NULL return checks | Post-construct | `z3_mk_context`/`z3_mk_solver` return → null check |
| `checkZ3Error` | Post-call | Reads `Z3_get_error_code` after every critical call |
| `closed: bool` flag | Destructor | Prevents double-free in `=destroy` |
| Move-only types | Compile-time | Prevents use-after-move at compile time |
| `{.acyclic.}` | ARC | Prevents premature collection of context while solver alive |
| `Z3Integrity` check | Runtime | SHA-256 verification of vendored `libz3.so` binary |

**Residual risk**: If Z3 has an internal bug (e.g., NULL dereference inside `z3_solver_check`), SIGSEGV will crash the process. This is an inherent limitation of FFI into C libraries. The subprocess fallback (`z3_pool.nim`) is immune to this — a Z3 crash only kills the worker process, not the host.

---

## §6. Architecture Diagram

### 6.1 FFI Path (In-Process)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Caller (e.g. solver_bridge.nim)         │
│                                                                 │
│   let ctx = newZ3Context()                                      │
│   let solver = newZ3Solver(ctx)    # sink: ctx consumed         │
│   solver.loadSmtlib(smt2)                                      │
│   let result = solver.check()                                   │
│   # ctx auto-freed when solver goes out of scope                │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   z3_bindings.nim (FFI)      │
              │                              │
              │  ┌─ z3_mk_context(nil)       │
              │  ├─ z3_set_error_handler()   │  ← Phase 2D
              │  ├─ z3_mk_solver()           │
              │  ├─ z3_solver_from_string()  │
              │  ├─ z3_solver_check()        │
              │  └─ checkZ3Error() after     │  ← post-call validation
              │       each API call          │
              └──────────────┬───────────────┘
                             │ {.dynlib: "vendor/z3/lib/libz3.so"}
              ┌──────────────▼──────────────┐
              │   libz3.so (Z3 C-API)       │
              │   vendor/z3/lib/libz3.so     │
              └─────────────────────────────┘
```

### 6.2 Thread-Local Context Pool

```
Thread 1                              Thread 2
┌─────────────────────┐              ┌─────────────────────┐
│ var threadZ3Pool    │              │ var threadZ3Pool    │
│   {.threadvar.}     │              │   {.threadvar.}     │
│                     │              │                     │
│ slot[0]: Z3Context  │              │ slot[0]: Z3Context  │
│ slot[1]: Z3Context  │              │ slot[1]: Z3Context  │
│ slot[2]: (empty)    │              │ slot[2]: (empty)    │
│ slot[3]: (empty)    │              │ slot[3]: (empty)    │
└─────────┬───────────┘              └─────────┬───────────┘
          │ acquire() / releaseToThread()       │ acquire() / releaseToThread()
          ▼                                     ▼
   No contention                        No contention
   (threadvar isolation)                (threadvar isolation)
```

### 6.3 CLI Fallback Path

```
┌──────────────────────────────────────────────────────┐
│                  z3_pool.nim                         │
│                  (Persistent Process Pool)            │
│                                                      │
│  Z3PersistentPoolManager                             │
│    ├─ pool: Z3PersistentPool                         │
│    │    ├─ workers: seq[Z3PersistentWorker]          │
│    │    │    └─ process: Process (startProcess)      │
│    │    │         stdin/out: Stream (pipe)           │
│    │    ├─ gate: Lock (round-robin selection)        │
│    │    └─ nextQueryId: int64 (sentinel tracking)    │
│    └─ bootstrapGate: Lock                            │
│                                                      │
│  z3ExecPersistent(query, timeoutMs)                  │
│    ├─ buildZ3QueryEnvelope()                         │
│    │    └─ prepend (reset), rlimit, timeout,         │
│    │       sentinel (echo "AXIOM_Z3_EOF_N")          │
│    ├─ write to stdin → read stdout until sentinel    │
│    ├─ on failure: restartZ3PoolWorker()              │
│    └─ appendZ3Telemetry()                            │
│                                                      │
│  Z3 Health Gate:                                     │
│    probeZ3Health() → sat + unsat canonical queries   │
│    initVerifiedZ3Pool() → VerifiedZ3Pool token       │
└──────────────────────────────────────────────────────┘
```

### 6.4 Complete Call Chain (ax prove)

```
ax prove
  │
  ├─ Z3 Health Gate (probeZ3Health)
  │    └─ returns Z3HealthProbeResult
  │
  ├─ Topology Analysis → Batch UAP
  │
  ├─ 4-Layer Pipeline
  │    ├─ Scout:  encode → SMT-LIB2
  │    ├─ Detective:  solve
  │    │    └─ CLI path:  z3_pool (subprocess) ← sole Z3 path
  │    │         └─ z3ExecPersistent(query)
  │    ├─ Scribe:  parse result (z3_result_parser)
  │    └─ Judge:  verdict (proved / counterexample)
  │
  └─ Telemetry: appendZ3Telemetry(record)
```

---

## §7. Module Dependency Graph

```
src/verification/solver/
  z3_bindings.nim          ← FFI types, move-only hooks, constructors
  z3_context_pool.nim      ← Thread-local context pool (imports z3_bindings)
  z3_pool.nim              ← Persistent subprocess pool (standalone, no FFI)

src/core/solver/
  z3_interactive.nim       ← Interactive stream with sync markers
  z3_result_parser.nim     ← Parse Z3 stdout → SolverBridgeResult
  solver_bridge.nim        ← High-level solver API (imports z3_result_parser, z3_interactive)

src/core/types/
  z3_solver_config.nim     ← resolveZ3Path() — binary path SSOT

src/core/integrity/
  z3_integrity.nim         ← Runtime SHA-256 verification of libz3.so

src/core/solver/
  z3_telemetry.nim         ← JSONL telemetry append
```

---

## §8. Configuration Reference

| Config | Type | Default | Description |
|--------|------|---------|-------------|
| `-d:ffiEnabled` | compile flag | — | Force FFI mode |
| `-d:ffiDisabled` | compile flag | — | Force CLI mode (stubs) |
| `Z3LibPath {.strdefine.}` | compile const | `vendor/z3/lib/libz3.so` | Z3 shared library path for `{.dynlib.}` |
| `$AXIOM_Z3_LIB` | env var | — | Runtime override for `findZ3Lib()` |
| `$AXIOM_Z3_PATH` | env var | — | Runtime override for CLI binary path |
| `MaxPoolSize` | compile const | `4` | Max contexts cached per thread |
| `Z3HealthProbeTimeoutMs` | compile const | `2000` | Health probe timeout per query |
| `z3ReadStepTimeoutMs` | compile const | `50` | Subprocess read polling interval |
| `z3ReadMinDeadlineMs` | — (REMOVED) | — | Per-query wall-clock read deadline. Superseded by sentinel-based I/O framing + `z3SafetyNetMs` liveness net. See `docs/spec/z3_pool_determinism.md`. |

---

## §9. Phase History

| Phase | Description | Status |
|-------|-------------|--------|
| 1A | Move-only semantics: `=destroy`, `=copy{.error.}`, `=dup{.error.}` on `Z3ContextObj`/`Z3SolverObj`. `sink` parameters. | **REMOVED** |
| 2C | Thread-local context pool: `{.threadvar.}`, `Z3ContextPool` with `MaxPoolSize = 4`, ARC-managed lifecycle. | **REMOVED** |
| 2D | Error handling: `z3_set_error_handler` callback, `checkZ3Error` post-call validation, NULL return checks. | **REMOVED** |
| 4D | FFI auto-detection: `gorge()`-based `z3FFIEnabled`, three-way priority (`ffiDisabled` > `ffiEnabled` > auto), `findZ3Lib()` search chain. | **REMOVED** |
| — | CLI subprocess pool: persistent Z3 workers, sentinel-based I/O, health gate, telemetry. | **Active** |
| — | Interactive stream: sync-marker deadlock elimination for incremental k-induction. | **Active** |
| — | Binary integrity: runtime SHA-256 verification of vendored `libz3.so`. | **REMOVED** |
| v30 | **Z3 FFI bindings completely removed** (see §10). All Z3 interactions now use CLI subprocess path. | **Current** |

---

## §10. Z3 FFI Removal (2026-07-02)

Z3 FFI (Foreign Function Interface) bindings have been completely removed from the Axiom project. All Z3 solver interactions now use the CLI subprocess path via `z3_pool.nim`.

### Reasons for removal
1. **Hang vulnerability**: FFI path had no timeout/rlimit — `Z3_solver_check()` could block indefinitely
2. **Theory mismatch**: FFI path received scripts with wrong logic declaration (QF_SLIA instead of QF_BV)
3. **No async cancellation**: `Z3_interrupt` was not bound — no way to cancel hanging solver
4. **TCB bloat**: Z3's C++ runtime was in-process, increasing attack surface
5. **Zombie processes**: Worker restart path was missing `waitForExit()` — created zombie processes

### What replaced FFI
- `z3_pool.nim`: Persistent CLI subprocess pool (`z3 -smt2 -in`) with sentinel-based output framing
- `buildZ3QueryEnvelope`: Automatic rlimit (30M) + timeout (60s) injection
- File-based fallback for payloads > 60KB (pipe buffer deadlock prevention)
- Proper zombie cleanup: `kill` → `waitForExit(500)` → `close`

### Deleted files
- `src/verification/solver/z3_bindings.nim`
- `src/verification/solver/z3_context_pool.nim`
- `tests/solver/test_z3_bindings.nim`
- `tools/test_z3_ffi.nim`
- `vendor/z3/lib/libz3.so`
- `vendor/z3/include/z3.h`, `z3_types.h`
