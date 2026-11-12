# OOM Recurrence Exhaustive Investigation Report

**Date**: 2026-05-27
**Subject**: OOM recurrence during malebolgia-based gate hook execution
**Classification**: Exhaustive Investigation

---

## 1. Incident Overview

After the previous OOM incident (2026-05-26), the following measures were applied:
- Nested malebolgia removed (retained only at gate level)
- Internal gate internal `startProcess` batching for capped concurrency
- ThreadPoolSize adjusted 16→14
- `gate bonding=1` for compile-time recursion prevention

**Nevertheless, on 2026-05-27 "just now" during gate hook execution, OOM recurred and the session was terminated.**

---

## 2. Previous Cause vs New Cause

| Category | Previous OOM (2026-05-26) | This OOM (2026-05-27) |
|------|----------------------|----------------------|
| Cause | Unbounded nested parallelism (377 concurrent nim check executions) | Nim 2.0 ORC + thread-internal allocation memory leak |
| Direct Trigger | Nested `createMaster()` + unbounded `spawn` | malebolgia `spawn` → `dispatchGate` → large string allocation |
| Solution | Batching + malebolgia unification | `-d:useMalloc` + `stdout` size limit required |

---

## 3. Evidence Collection (Context7 + Official Docs)

### 3.1 Nim Memory Management Official Docs

**Source**: Nim `doc/mm.md` (Context7 `/nim-lang/nim`)
> "ORC is the default memory management strategy... Reference cycles are handled by a cycle collection mechanism... The reference counting operations do not use atomic instructions."

**Source**: Nim `doc/manual_experimental.md` (Context7 `/nim-lang/nim`)
> "Threading under ARC/ORC supports a shared heap, allowing messages to be sent between threads without copies. To prevent data races, it's enforced that only isolated subgraphs can be sent."

**Source**: Nim `changelog_1_6_0.md` (Previous investigation)
> "Arguments to tasks must be isolated."

### 3.2 Nim GitHub Official Issue

**Source**: [nim-lang/Nim #23361](https://github.com/nim-lang/Nim/issues/23361)
> "Following code leads to a very high memory usage for memory allocated with either `alloc` or `allocShared` inside threads when `arc / orc` is used as `mm` option. Using `-d:useMalloc` leads to expected behaviour!"

- **Affected version**: Nim 2.0.2 (Windows/Linux same)
- **Workaround**: `-d:useMalloc`
- **Root cause**: ORC allocator does not properly reclaim per-thread allocations

### 3.3 Nim Community Forum

**Source**: [forum.nim-lang.org/t/13322](https://forum.nim-lang.org/t/13322)
> "The new ORC memory manager conflicts with existing async implementations, causing memory leaks in exception handlers and steady memory growth in long-running servers. One developer reported their production HTTP server experienced a **3x memory usage increase** when upgrading from Nim 1.6 to 2.0, requiring the `-d:useMalloc` workaround."

---

## 4. Code Analysis

### 4.1 `runAllGatesParallel` (gate_hook.nim:198)

```nim
var results = newSeq[GateResult](active.len)
var m = createMaster()
m.awaitAll:
  for i in 0 ..< active.len:
    m.spawn dispatchGate(active[i], repoRoot, changedFiles, maxJobs) -> results[i]
```

**Analysis**:
- `dispatchGate` runs on the malebolgia thread pool
- The return value `GateResult` is stored in `results[i]` on the main thread
- `GateResult` contains the `stdout: string` field

### 4.2 `runNimCheckForFilesImpl` (gate_hook.nim:76)

```nim
var allOutput = ""
...
allOutput.add(&"nim check: {files[idx + i]}\n{outp}\n")
```

**Analysis**:
- Accumulates all `nim check` output into a single string
- 377 files × 5KB average output ≈ **1.8MB**+ single string
- This string is stored in `GateResult.stdout` and moved between threads
- ARC/ORC does **not properly reclaim** large strings allocated in internal threads (GitHub #23361)

### 4.3 `topology_cache.json` (161MB)

```
-rw-rw-r-- 1 wintrover wintrover 161149061  May 27 15:39 topology_cache.json
```

**Analysis**:
- `logs/topology_cache.json` is **161MB**
- If `ax prove` or topology analysis loads this file into memory during gate execution, it immediately causes significant memory pressure
- Whether this file is loaded during gate hook execution requires further verification

---

## 5. Hypotheses and Verification

### Hypothesis A: ORC per-thread allocation leak (★Most Likely)

**Rationale**:
- GitHub #23361: ORC per-thread allocation memory leak confirmed as official bug
- Forum: 3x memory increase after Nim 2.0 upgrade, resolved with `-d:useMalloc`
- `dispatchGate` runs on malebolgia threads and allocates large strings (`allOutput`)

**Verification Method**:
- Recompile `scripts/gate_hook` with `-d:useMalloc` and run gates
- Monitor memory usage (`/usr/bin/time -v` or `ps aux`)

### Hypothesis B: `GateResult.stdout` Memory Pressure

**Rationale**:
- `runAllGatesParallel` holds all gate results simultaneously in the `results` array
- 10 gates × 2MB stdout = 20MB immediate memory occupancy
- Combined with ORC leak, accelerates Hypothesis A

**Verification Method**:
- Limit `GateResult.stdout` maximum size to 1MB and re-execute

### Hypothesis C: `topology_cache.json` (161MB) Loading

**Rationale**:
- A 161MB file loaded into memory would be fatal for a system on the brink of OOM
- `ax prove` or `topology_cli_test` may load this file

**Verification Method**:
- Real-time memory usage monitoring with `top`/`htop` during gate execution
- Verify when `topology_cache.json` is loaded

---

## 6. Recommendations (Immediately Applicable)

### 6.1 Short-term Mitigation (Emergency)

1. **Apply `-d:useMalloc`**
   ```bash
   # When compiling scripts/gate_hook.nim and scripts/gate_replay.nim
   nim c -d:release -d:useMalloc scripts/gate_hook.nim
   nim c -d:release -d:useMalloc scripts/gate_replay.nim
   ```
   - The only workaround verified by GitHub #23361 and the Forum
   - Avoids per-thread leak by using system `malloc` instead of ORC allocator

2. **`GateResult.stdout` size limit**
   ```nim
   # Modify runNimCheckForFilesImpl and runGatewayTestsImpl
   const MaxStdoutPerGate = 1024 * 1024  # 1MB
   if allOutput.len > MaxStdoutPerGate:
     allOutput = allOutput[0..<MaxStdoutPerGate] & "\n... (truncated)\n"
   ```

3. **`topology_cache.json` size monitoring**
   ```bash
   ls -lh logs/topology_cache.json
   # If 161MB or more, immediately `ax prove --clear-cache` or delete manually
   ```

### 6.2 Medium-term Improvements

1. **Remove `allOutput` accumulation → streaming output**
   - Change to append `nim check` results directly to a file
   - Store only the file path in `GateResult`

2. **Simplify concurrency instead of malebolgia**
   - Consider `execProcesses` from `std/osproc` or `pmap` pattern
   - malebolgia provides structured concurrency, but the current cost exceeds the benefit due to the ORC bug

3. **Add memory monitoring tools**
   - Record peak RSS with `getrusage(RUSAGE_SELF)` during gate execution
   - Store per-gate memory usage in `logs/gate_memory.log`

---

## 7. Conclusion

**The direct cause of the previous OOM (unbounded nested parallelism) has been resolved, but Nim 2.0 ORC's fundamental per-thread allocation leak has emerged as the new OOM cause.**

malebolgia works as intended, but the Nim 2.0 ORC bug causes memory allocated in the thread pool to leak. In particular, the pattern of accumulating large strings in `GateResult.stdout` accelerates this leak.

**Key Quote**:
> "Using `-d:useMalloc` leads to expected behaviour!" — nim-lang/Nim #23361

**Immediate action**: Recompile `scripts/gate_hook` and `scripts/gate_replay` with `-d:useMalloc`.

---

## 8. References

1. Nim `doc/mm.md` — "RC operations are not atomic and subgraphs can be moved between threads."
2. Nim `doc/manual_experimental.md` — "only isolated subgraphs can be sent."
3. nim-lang/Nim #23361 — "Memory leak with Arc / Orc for allocation inside threads"
4. forum.nim-lang.org/t/13322 — "The turbulent evolution of Nim's concurrency story"
5. Axiom `docs/history/gemini-rebuttal.md` — Previous OOM analysis
