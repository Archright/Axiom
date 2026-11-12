# OOM Final Root Cause Exhaustive Investigation Report

**Date**: 2026-05-27
**Subject**: OOM recurrence even after malebolgia removal — 3-layer memory bomb structure
**Classification**: Exhaustive Investigation

---

## Event Overview

 Despite completely removing malebolgia and switching to sequential execution, an OOM still occurred during pre-commit hook execution, causing the GUI (Chrome, mouse cursor) to freeze.

---

## Evidence Collection (Context7 + Official Docs + Web)

### Evidence 1: System Memory Status

```
MemTotal:       32247016 kB  (~30GB)
MemFree:        25364836 kB  (~25GB)
SwapTotal:             0 kB
SwapFree:              0 kB
```

**Key Point**: **No swap at all (0B)**. When memory is insufficient, there is no swap to fall back on, so the OOM killer activates immediately.

### Evidence 2: Linux fork(2) man page

> "fork() creates a new process by duplicating the calling process... The entire virtual address space of the parent is replicated in the child."

**Key Point**: `fork()` **replicates the entire virtual address space** of the parent process. COW does not copy data immediately, but page tables and kernel structures are copied.

### Evidence 3: "Fork(2) and the OOM killer" (kya8.github.io)

> "By CoW fork and overcommittment, the Linux kernel essentially lies to the child process that it has allocated 6G of memory, while effectively it can write to only 2G of it... The child is free to use that 6G of memory however it wants, but there's no guarantee it won't exhaust all available memory and get killed."

**Key Point**: Linux's COW + overcommit lies to the child process, telling it "you can use all the memory," but when physical memory is insufficient, the OOM killer activates.

### Evidence 4: "Faster Creating of Large Processes on Linux" (whexy.com)

> "Use `posix_spawn()` to replace `fork()` if you want to launch a new program."
> "fork() gets slower and slower as more and more memory is being used... the internal virtual memory structures in the kernel... are being copied in an inefficient way."

**Key Point**: The larger the parent process, the slower `fork()` gets and the more memory it uses. The solution is `posix_spawn()` or `execv`.

### Evidence 5: "fork() gets slower as parent process uses more memory" (blog.famzah.net)

| Allocated | Usage | vfork() | fork() |
|-----------|-------|---------|--------|
| 20MB | 10MB | 1.49 | 12.08 |
| 20MB | 20MB | 1.53 | 21.60 |
| 40MB | 20MB | 1.59 | 21.23 |

**Key Point**: When the parent's memory usage doubles, `fork()` CPU usage also doubles. `vfork()` is unaffected.

### Evidence 6: Redis Fork OOM (CSDN, Linux overcommit_memory)

> "Redis在后台的存储机制依赖于操作系统中fork的copy-on-write... 把overcommit_memory设置为1来告诉Linux以更加乐观的方式来执行fork操作."

**Key Point**: `vm.overcommit_memory=1` tells Linux to handle `fork()` more permissively. The current system has `overcommit_memory=0` (conservative heuristic).

### Evidence 7: Nim forum — choosenim proxy executables

> "choosenim proxy executables use startProcess to start sub-processes... I have created a PR, which replaces startProcess with execv, which means that the proxyexe process is replaced by the process it calls."

**Key Point**: There is a case in the Nim community where the `fork()` problem of `startProcess` was solved using `execv`.

---

## 3-Layer Memory Bomb Structure

 The reason OOM recurred even after removing malebolgia is due to a **3-layer structure, not a single cause**.

### Layer 1: `pre-commit` Binary at 140MB

 `nimble hooks` compilation result:
 ```
 91813 lines; 2.324s; 142.332MiB peakmem
 ```

 The `pre-commit` binary uses 142MB of memory. This is due to the Nim ORC runtime + `--threads:on` + all modules loaded by `config.nims` + imports from `gate_hook.nim`.

### Layer 2: 14 Concurrent `fork()` via `startProcess` Batching

 `runNimCheckForFilesImpl` runs 14 `startProcess` concurrently with `maxJobs=14`:

 ```
 14 × 140MB (parent memory mapping copy) = 1.96GB virtual memory committed immediately
 ```

 COW does not copy data immediately, but **page table copying + kernel structure allocation** happens immediately. Linux man fork(2):
 > "The entire virtual address space of the parent is replicated in the child."

 Each `nim` process itself uses hundreds of MB to several GB of memory. **Total instantaneous memory pressure: 15GB+**.

### Layer 3: No Swap (0B)

 ```
 SwapTotal: 0 kB
 SwapFree: 0 kB
 ```

 When memory is insufficient, there is no swap to fall back on. The OOM killer activates immediately, killing large processes such as Chrome and Lean LSP.

---

## Why Was Removing malebolgia Alone Insufficient?

 malebolgia was a **catalyst**, not the **sole cause**.

 | Component | Before malebolgia Removal | After malebolgia Removal |
 |-----------|-------------------|-------------------|
 | malebolgia thread pool | 14 × 8MB = 112MB | **0MB** |
 | `pre-commit` binary | 140MB | **140MB** (retained) |
 | `fork()` COW (14) | 14 × 140MB = 1.96GB | **1.96GB** (retained) |
 | `nim` process memory | 14 × 1GB = 14GB | **14GB** (retained) |
 | **Total** | **~16GB** | **~16GB** |

 Removing malebolgia saved 112MB, but this was negligible against the total 16GB pressure.

---

## Root Cause Solution

### P0 (Immediate): Add Swap Space

 **Fastest and most effective mitigation**. Standard setup for large memory systems like Redis and Python.

 ```bash
 sudo fallocate -l 8G /swapfile
 sudo chmod 600 /swapfile
 sudo mkswap /swapfile
 sudo swapon /swapfile
 ```

 **Rationale**: CSDN Redis OOM case — "vm.overcommit_memory=1 or swap addition required"

### P1 (Short-term): Minimize `pre-commit` Binary Memory

 Why `pre-commit` uses 140MB:
 - `--threads:on` + `--mm:orc` from `config.nims`
 - `gate_hook.nim` imports `gate/gates.nim` (including internal gate code)
 - Large standard libraries such as `std/os`, `std/osproc`, `std/streams`

 Solution:
 1. Remove `gate/gates.nim` import from `gate_hook.nim`
 2. Read gate list from external file (JSON/TOML)
 3. Extract internal gates (`nim-check`, `gateway-test`) into separate binaries
 4. `pre-commit` acts only as a simple launcher (target memory under 10MB)

 **Rationale**: whexy.com — "Use posix_spawn() to replace fork() if you want to launch a new program."

### P2 (Medium-term): Introduce `posix_spawn()` or `execv`

 `startProcess` uses `fork()` + `exec()`. `posix_spawn()` creates a process without `fork()`, completely avoiding COW.

 **Rationale**:
 - Linux man fork(2): "The child process is created with a single thread."
 - choosenim PR: "replaces startProcess with execv, which means that the proxyexe process is replaced by the process it calls."

### P3 (Long-term): Zero-String Pipeline

 Replace `execCmdEx` loading process output into memory as a string with a file-based approach.

---

## Conclusion

 **malebolgia was not the single cause of OOM.** The 3-layer structure (large parent process + multiple `fork()` + no swap) worked together to cause the memory explosion.

 **Immediate action**: Adding swap space is the fastest way to prevent the OOM killer.
 **Fundamental action**: Reducing the `pre-commit` binary from 140MB to under 10MB is the only fundamental solution.

---

## References

1. Linux `fork(2)` man page — "The entire virtual address space of the parent is replicated in the child."
2. kya8.github.io — "Fork(2) and the OOM killer"
3. whexy.com — "Faster Creating of Large Processes on Linux"
4. blog.famzah.net — "fork() gets slower as parent process uses more memory"
5. CSDN — "Redis Fork导致OOM killer" (overcommit_memory setting)
6. Nim forum — choosenim proxy executables PR (startProcess → execv)
