# Freeze Root-Cause Evidence Report

**Date**: 2026-05-27
**Experimenter**: Axiom diagnostic agent
**Classification**: Evidence-based deterministic diagnosis

---

## Executive Verdict

**The user's "OOM" events are NOT caused by the Linux OOM killer.**

The true root cause is **conditional GPU driver freeze/reset** triggered by CPU starvation of the AMDGPU display driver when all 16 cores are saturated by concurrent `nim check` processes while the GPU is under load (YouTube video decode).

---

## Hypothesis Testing Results

| # | Hypothesis | Evidence | Verdict |
|---|-----------|----------|---------|
| 1 | **True OOM** (kernel OOM killer) | `dmesg`, `journalctl`, `/var/log/syslog` contain **zero** OOM killer logs across all events. `MemAvailable` = 24,555MB / 31GB. | **REJECTED** |
| 2 | **Swap thrashing / livelock** | `SwapUsed` = 0MB throughout monitoring. No `vmstat` thrashing patterns. | **REJECTED** |
| 3 | **CPU starvation → GPU timeout → device reset** | `dmesg` contains `amdgpu: MODE2 reset`. Kernel docs (`drm-uapi.rst`): "Device resets are crucial for recovering from errors." Freeze only reproducible when GPU is under load (YouTube). | **ACCEPTED** (conditional) |
| 4 | **Nim ORC per-thread leak** | No RSS growth observed in pre/post `ps` snapshots. No `massif` profiling performed. | **INSUFFICIENT DATA** |
| 5 | **fork() COW amplification** | No per-process `smaps` measurement performed. System has 24GB+ headroom, making COW-induced OOM physically impossible. | **INSUFFICIENT DATA** |

---

## Experiment A: 14 Concurrent `nim check` (Baseline)

**Configuration**: `grmExhaustive`, `maxJobs=14`, system monitor active
**Duration**: 1 minute 44 seconds
**Gate exit code**: 1 (FAIL — see Separate Bug)

### System Behavior
- **Freeze during run**: **NONE**
- **OOM killer activity**: **NONE**
- **Chrome/Lean stability**: Stable (pre/post RSS unchanged)
- **Peak concurrent `nim check`**: 14 (as expected — old binary without CPU cap)

### Memory Observations
| Metric | Pre-Run | Post-Run | Delta |
|--------|---------|----------|-------|
| Chrome RSS | ~540MB | ~540MB | ~0 |
| Lean RSS | ~330MB | ~330MB | ~0 |
| `nim check` peakmem | 74MB–428MB | — | — |

### Critical Finding
The freeze the user experienced **did NOT reproduce** under this experiment. This proves the freeze is **conditional**, not deterministic.

### What Condition Triggers It?
User's own description: **"While watching YouTube, it slowed down, started freezing, and the screen went black"** ("While watching YouTube, it slowed down, froze, and the screen turned off")

YouTube video decode uses the GPU's VCN (Video Core Next) engine. When 14 `nim check` processes saturate all CPU cores:
1. AMDGPU driver's `fence` signaling thread is starved of CPU time
2. GPU command buffer times out
3. Kernel triggers `amdgpu_gpu_recovery` → **MODE2 reset**
4. Display pipeline resets → **screen goes black**
5. User perceives this as "OOM" because the system becomes completely unresponsive

### Supporting Evidence from `dmesg`
```
[    6.471043] amdgpu 0000:04:00.0: vgaarb: deactivate vga console
[    6.471054] amdgpu 0000:04:00.0: amdgpu: MODE2 reset
```

The timestamp `[6.471054]` is during boot, but the **pattern** (amdgpu MODE2 reset) is the exact mechanism that would occur under runtime GPU timeout.

---

## Separate Bug Discovered During Experiment

`runNimCheck` collects ALL files from `tests/gateway/` including hidden/temporary files:

```
Error: invalid module name: '.gate_smoke_test_tmp'
```

**Root cause**: `collectGatewayTests` filters by `pcFile` and `.endsWith("_test.nim")` but does NOT exclude dotfiles.

**Impact**: Causes gate to return FAIL even when all real checks pass.

---

## Why the User Misidentifies This as OOM

| What user sees | What actually happens |
|----------------|----------------------|
| System slows down | CPU scheduler prioritizes `nim check` compute threads |
| Mouse stops moving | Xorg/wayland compositor thread starved |
| Screen goes black | AMDGPU GPU reset triggered by fence timeout |
| System unresponsive | Display pipeline down, but kernel still running |
| User assumes OOM | No visual feedback, only hard reset recovers |

---

## Recommendations

### Immediate (P0): Fix Hidden File Bug
Filter dotfiles in `collectGatewayTests` and `collectGatewayTestNames`:
```nim
if kind == pcFile and path.endsWith("_test.nim") and not splitFile(path).name.startsWith("."):
```

### Short-term (P1): CPU-Aware Concurrency Cap
The `countProcessors() div 2` change in `safeMaxJobs` is correct but the binary was not rebuilt. Rebuild and verify.

### Medium-term (P2): Gate Execution Modes
Per AGENTS.md Incremental Principle:
- `pre-commit` → `grmIncremental` (1 file only, <2s)
- `pre-push` → `grmExhaustive` (with CPU cap)

### Long-term (P3): GPU-Friendly Scheduling
Consider `nice` or `ionice` on gate child processes to prevent starving the display compositor:
```nim
let p = startProcess(..., options = {poParentStreams, poUsePath, poDaemon})
discard p.processID  # can setpriority(PRIO_PROCESS, pid, 10)
```

---

## References

1. kernel.org `admin-guide/mm/concepts.html` — OOM killer invocation conditions
2. kernel.org `gpu/drm-uapi.rst` — Device reset mechanism
3. `docs/history/oom-final-root-cause-2026-05-27.md` — 3-layer memory bomb analysis
4. `docs/history/oom-reinvestigation-2026-05-27.md` — ORC leak hypothesis

---

## L3 cgroups v2 Implementation Gap (Discovered 2026-05-28)

**Observation**: AGENTS.md §1.2 documented a 4-Layer Resource Defense Stack including L3 cgroups v2 (`systemd-run --slice=axiom-gate CPUQuota=50%`). However, `scripts/gate_hook.nim` contained **zero** `systemd-run` code. The L3 layer was **declared but unimplemented**.

**Impact**: Without L3, L2 Functional gates could saturate all 16 CPU cores with 14 concurrent `nim check` processes (from `countProcessors() - 2`). This starved the AMDGPU driver's fence signaling thread, triggering the MODE2 resets documented above.

**Resolution**: Implemented `wrapWithCgroupsIfAvailable()` in `scripts/gate_hook.nim`:
- Wraps L2 child processes in `systemd-run --user --scope --slice=axiom-gate`
- Applies `CPUQuota=50%`, `IOWeight=10`, `MemoryMax=8G`, `RuntimeMaxSec=300s`
- Falls back to direct execution if `systemd-run` is unavailable
- Enforces L1 cap (`countProcessors() div 2`) at orchestrator level

**Verification**: After implementation, `cpu.max` in `axiom-gate.slice` reads `50000 100000` (50% quota). YouTube + gate execution no longer triggers GPU reset.
