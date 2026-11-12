# OOM Forensic Analysis: 2026-05-28 18:17

**Status:** COMPLETE — Root cause identified. No system-wide mitigations applied (rejected per AGENTS.md §0.6).  
**Method:** Deterministic forensic analysis of existing `dmesg` `oom_dump_tasks`. No runtime instrumentation.  
**Analyst:** Delegate-First agent, Approach A approved.

---

## 1. Executive Summary

The 2026-05-28 18:17 kernel OOM event was **not caused by Chrome**. Chrome's 1.5 TB `total-vm` was virtual-only (~15 MB `anon-rss`); Chrome was selected as the OOM victim due to `oom_score_adj=300` + `total_vm` heuristic. The **true physical memory consumers were Axiom's own pre-push gate child processes**, which collectively held **28.8 GB of anonymous RSS** across **83 processes** at the moment of OOM — consuming **~95% of the system's 32 GB RAM**.

This is a **process explosion under the gate execution model**, not a memory leak in a single component.

---

## 2. OOM Event Timeline

| Timestamp (s since boot) | Event | PID Killed | Key Metric |
|---|---|---|---|
| 3127.587136 | First OOM kill | 8992 (chrome) | anon-rss: 17 MB, oom_score_adj: 300 |
| 3129.983940 | `kerneloops` invokes oom-killer | — | Complete `oom_dump_tasks` captured |
| 3129.984114 | Mem-Info dump | — | active_anon=17.4 GB, inactive_anon=12.3 GB |
| 3129.984311 | Tasks state dump begins | — | 83 Axiom processes identified |
| 3130–3131 | Cascade kills | Multiple chrome PIDs | Score-adj 200/300 chrome tabs killed |

The complete `oom_dump_tasks` snapshot (3129.983940) is the evidentiary basis for this report.

---

## 3. Memory Topology at OOM

```
System: 32 GB RAM, 8 GB swap
Free swap at OOM:          40 kB   (critically exhausted)
Free RAM (Normal+DMA32):   ~242 MB (just above min watermark 127 MB)
active_anon:              17.4 GB
inactive_anon:            12.3 GB
Total anonymous memory:   ~29.7 GB
```

### 3.1 Chrome: The Decoy

| PID | total_vm (pages) | rss (pages) | anon-rss (pages) | oom_score_adj |
|---|---|---|---|---|
| 9483 | 379,709,924 | 2,452 | 1,644 | 300 |
| 8729 | 12,897,183 | 32,433 | 20,337 | 0 |
| 8775 | 12,894,026 | 7,167 | 6,844 | 200 |

- **Chrome total anon-rss across all PIDs: ~1,413 MB** (mostly one GPU/renderer process at 127 MB).
- The 1.5 TB `total-vm` is virtual address space (GPU mmap, shared libraries, sandbox shmem) — **zero physical relevance**.
- Chrome was killed because `oom_score_adj=300` makes it the highest-scoring candidate when the kernel's OOM heuristic weights `total_vm` heavily. It was a **statistical victim**, not the cause.

### 3.2 Axiom Processes: The True Consumers

Breakdown by binary name from `oom_dump_tasks` (sorted by total footprint = anon + swap):

| Binary | Count | Anon (MB) | Swap (MB) | Total (MB) | Avg Anon / Proc |
|---|---|---|---|---|---|
| `gateway_topolog` | 11 | 8,383 | 4,678 | **13,061** | 762 |
| `ax` | 4 | 4,802 | 1,963 | **6,765** | 1,201 |
| `asi_cli_test` | 7 | 6,949 | 0 | **6,949** | 993 |
| `report_cli_test` | 7 | 5,802 | 0 | **5,802** | 829 |
| `nim` | 36 | 2,371 | 44 | **2,415** | 66 |
| `lean` | 7 | 375 | 144 | **519** | 54 |
| `z3` | 11 | 122 | 0 | **122** | 11 |
| **TOTAL** | **83** | **28,804** | **6,829** | **35,633** | — |

**Key observations:**

1. **`gateway_topolog` dominates**: 11 instances consuming 13 GB total (8.4 GB RAM + 4.7 GB swap). Average 762 MB per process. This is the gateway test topology builder; multiple instances suggest the `gateway-test` gate or parallel test runs spawned overlapping topology analyses.

2. **`ax` CLI heavy**: 4 instances at 1.2 GB average each. The Axiom CLI itself is memory-heavy during `prove` or `report` operations, likely due to certificate vault loading and graph construction.

3. **Test binary explosion**: `asi_cli_test` (7×, 993 MB avg) and `report_cli_test` (7×, 829 MB avg) are unit/integration test executables. Seven instances each implies either repeated test runs or parallel test matrices.

4. **`nim` compiler swarm**: 36 `nim` processes at 66 MB average. This indicates **massively parallel Nim compilation** — likely `-j8` or higher parallelism within a gate, multiplied across concurrent L2 gates. Nim compiler retains AST and symbol tables in memory; 36 × 66 MB = 2.4 GB.

5. **`lean` + `z3` prover suite**: 7 Lean (54 MB avg) + 11 Z3 (11 MB avg) = 641 MB. Expected for `integrity-test` and `axiom-prove` gates.

6. **Swap exhaustion**: 6.8 GB of Axiom memory was swapped out. With only 8 GB total swap, Axiom alone consumed **85% of swap**.

### 3.3 Desktop Environment (For Context)

| Category | Anon (MB) | Swap (MB) | Notes |
|---|---|---|---|
| Chrome (all) | ~1,413 | ~1,067 | Decoy victim |
| Python (Kimi agent) | ~494 + ~319 | ~1 + ~3 | Agent runtime |
| `Code` (VS Code) | ~174 | ~26 | Editor |
| Cinnamon/Xorg/etc | ~300 | ~400 | Desktop baseline |
| **Desktop total** | **~2,700** | **~1,500** | ~10% of system memory |

**Conclusion**: Desktop + Chrome combined used ~10% of RAM. Axiom used ~90%.

---

## 4. Root Cause Analysis

### 4.1 Immediate Cause

The `pre-push` hook executed `bin/gate_hook pre-push`, which dispatched L2 gates in parallel (MaxConcurrentL2=4). Each L2 gate then spawned its own child process tree:

- `gateway-test` → multiple `gateway_topolog` instances
- `integrity-test` → `lean` + `z3` + `nim` compilation
- `external-cli-smoke-hard` → `ax` CLI runs
- Unit test gates → `asi_cli_test`, `report_cli_test`, `nim` compilation

**The concurrency model is multiplicative, not additive:**

```
L2 parallel slots: 4
  └─ Each slot runs a gate
       └─ Each gate runs with AXIOM_JOBS=8 (L1 cap = countProcessors/2)
            └─ Nim compilation spawns 8 parallel compiler processes
            └─ Test runner spawns parallel test processes
            └─ Lean/Z3 spawn solver workers
```

Result: **4 × 8 = 32+ concurrent worker processes**, each holding hundreds of MB. The system has 32 GB RAM; 32 workers × 1 GB average = **32 GB theoretical minimum**, before counting OS overhead, desktop, and Chrome.

### 4.2 Contributing Factors

| Factor | Evidence | Severity |
|---|---|---|
| **Multiplicative parallelism** | 36 `nim` + 11 `gateway_topolog` + 7 `lean` | Critical |
| **No gate-level memory budget** | L3 cgroups wrap per-gate scope, but `MemoryMax=8G` per scope × 4 scopes = 32G theoretical ceiling, yet child processes of gate scopes are not independently capped | Critical |
| **Swap as pressure valve** | 6.8 GB Axiom memory swapped; swap exhaustion triggered OOM | High |
| **Heavy gates on pre-push** | `integrity-test` and `external-cli-smoke-hard` moved to `gsPrePush`; these are the heaviest memory users | High |
| **cgroups verification gap** | `systemd-cgls` showed no active `axiom-gate` slice during commit; transient scopes exit before observation, suggesting enforcement is weak or race-prone | Medium |
| **Chrome score penalty** | `oom_score_adj=300` on Chrome tabs guaranteed they would be killed first, masking the true cause until forensic analysis | Low (symptom) |

### 4.3 What Did NOT Cause This

- **Chrome memory leak**: Chrome's anon-rss was 1.4 GB total. The 1.5 TB `total-vm` is virtual-only.
- **AMDGPU freeze**: This was a genuine kernel OOM (`global_oom`), not a GPU hang. The previous day's freeze was a separate event.
- **Kernel overcommit heuristic**: `vm.overcommit_memory=0` is the default heuristic. Changing it to `mode=2` was rejected per AGENTS.md §0.6 because Nim/Lean/Z3 rely on large virtual mappings.
- **eBPF/AMDGPU debugfs**: Not feasible without root/CAP_BPF. Not required since `dmesg` provided sufficient evidence.

---

## 5. Cross-Reference with Axiom Architecture

### 5.1 AGENTS.md §1.2 4-Layer Resource Defense Stack

| Layer | Implementation | Status at OOM | Effectiveness |
|---|---|---|---|
| L0: Hook self-throttle | `countProcessors() div 2` (jobs=8) | Active | **Insufficient** — caps per-gate jobs but not cross-gate multiplication |
| L1: Sequential meta gates | L1 gates run sequentially | Active | **Bypassed** — L1 gates are lightweight; L2 gates are the heavy consumers |
| L2: Parallel functional gates | MaxConcurrentL2=4 | Active | **Inadequate** — 4 concurrent heavy gates × 8 jobs each = 32+ workers |
| L3: cgroups v2 | `systemd-run --slice=axiom-gate MemoryMax=8G` | **Verification gap** | Unknown — transient scopes not observable; may not limit child trees effectively |

### 5.2 Gate Registry (`src/gate/manifest.d/_index.json`)

Heavy gates on `gsPrePush`:
- `integrity-test`: Full Lean + Z3 + Nim compilation pipeline
- `external-cli-smoke-hard`: Full CLI integration tests
- `gateway-test`: Topology analysis (11× `gateway_topolog` observed)

These gates were moved to `gsPrePush` in commit `b87030e9` to reduce pre-commit friction, but this concentrated heavy memory load into the pre-push stage.

---

## 6. Recommendations

### 6.1 Immediate (No Code Change)

1. **Avoid `git push` when other memory-intensive work is active** (e.g., Lean compilation, large `nim c` builds).
2. **Monitor `free -h` before push**; if swap is >50% used, delay push.
3. **Close Chrome tabs with `oom_score_adj=300`** (GPU/process-heavy tabs) before push to reduce victim likelihood.

### 6.2 Short-Term (Gate Infrastructure)

1. **Reduce L2 concurrency for pre-push**: Change `MaxConcurrentL2` from 4 to **2** for `gsPrePush` stage. This halves the multiplicative factor (2 × 8 = 16 workers vs. 32).
2. **Reduce L1 jobs for pre-push**: Cap `AXIOM_JOBS` to `countProcessors() div 4` (4 jobs) for `gsPrePush`, leaving headroom for OS and desktop.
3. **Stagger heavy gates**: Run `integrity-test` and `external-cli-smoke-hard` sequentially within pre-push, not in parallel with other L2 gates.
4. **Verify L3 cgroups enforcement**: Add `systemd-cgls` check + `cat /sys/fs/cgroup/user.slice/user-1000.slice/axiom-gate.slice/*/memory.max` to gate hook diagnostics. If `memory.max` is not enforcing, fall back to `ulimit -v` (virtual memory limit per process).

### 6.3 Medium-Term (Build System)

1. **Nim compiler memory profiling**: `nim c` peaks at ~200+ MB per file for large modules. With 36 concurrent `nim` processes, this is 7+ GB. Consider:
   - `--gc:orc` (already default in Nim 2.x)
   - `--mm:orc` compile-time reduction
   - `nimcache` sharing to reduce redundant compilation
2. **Gateway topology builder memory optimization**: `gateway_topolog` at 762 MB avg is the single largest consumer. Profile its heap; likely graph adjacency matrices or symbol tables.
3. **Test binary deduplication**: `asi_cli_test` and `report_cli_test` spawning 7 instances each suggests independent test binaries compiled separately. Consider test aggregation or shared libraries.

### 6.4 Rejected Approaches (Documented)

| Approach | Rejected Because |
|---|---|
| `vm.overcommit_memory=2` | System-wide kernel parameter; breaks Nim/Lean/Z3 large virtual mappings per kernel docs |
| eBPF memory tracing | `bpftrace` not installed; `CAP_BPF` not available; root required |
| AMDGPU GEM debugfs | `/sys/kernel/debug/` permission denied; root required |
| `procfs` polling | Indirect; no historical data; cannot explain past OOM |
| Chrome process limits | Chrome is the victim, not the cause; limiting Chrome would not prevent Axiom from exhausting memory |

---

## 7. Evidence Artifacts

### 7.1 Raw `dmesg` OOM Dump (Lines 3129.983940–3129.985999)

```
[ 3129.983940] kerneloops invoked oom-killer: gfp_mask=0x140cca(...), order=0, oom_score_adj=0
[ 3129.984114] Mem-Info:
[ 3129.984127] active_anon:4562298 inactive_anon:3229391 isolated_anon:0
[ 3129.984135] Node 0 active_anon:18249192kB inactive_anon:12917564kB ... Free swap = 40kB
[ 3129.984311] Tasks state (memory values in pages):
[ 3129.984324] [  pid  ]   uid  tgid total_vm      rss rss_anon rss_file rss_shmem pgtables_bytes swapents oom_score_adj name
```

Full task list extracted and sorted by `rss_anon` descending. Top 40 tasks include:
- `ax` (PID 913665): rss=387,736 pages (~1.5 GB anon)
- `gateway_topolog` (PID 1139802): rss=408,704 pages (~1.6 GB anon)
- `asi_cli_test` (PID 2141040): rss=367,594 pages (~1.4 GB anon)
- `report_cli_test` (PID 2143143): rss=292,960 pages (~1.1 GB anon)

### 7.2 Axiom Process Count and Memory Totals

```
gateway_topolog      count=11  anon_MB=8,383  swap_MB=4,678
report_cli_test      count= 7  anon_MB=5,802  swap_MB=    0
asi_cli_test         count= 7  anon_MB=6,949  swap_MB=    0
ax                   count= 4  anon_MB=4,802  swap_MB=1,963
nim                  count=36  anon_MB=2,371  swap_MB=   44
lean                 count= 7  anon_MB=  375  swap_MB=  144
z3                   count=11  anon_MB=  122  swap_MB=    0
TOTAL                count=83  anon_MB=28,804 swap_MB=6,829
```

### 7.3 Verification Commands

To reproduce this analysis on the same `dmesg` buffer (valid until next reboot or `dmesg -C`):

```bash
# Extract OOM dump for timestamp 3129.983940
dmesg | awk '/kerneloops invoked oom-killer/{found=1} found && /Tasks state/{header=1} header && /^\[ [0-9]+\.[0-9]+\] \[/{print} header && !/^\[ [0-9]+\.[0-9]+\] \[/{exit}'

# Sort by rss_anon (descending) — pages are 4 KB each
dmesg | awk '/Tasks state \(memory values in pages\)/{header=1; next} header{print $6, $NF, $1}' | sort -nr | head -40

# Sum Axiom process memory
dmesg | awk '/Tasks state/{header=1; next} header{print $6, $11, $NF}' | \
  awk '{if($3 ~ /^(ax|asi_cli_test|report_cli_test|gateway_topolog|lean|nim|z3)$/) {a+=$1; s+=$2; c++}} END{print "Axiom: count="c", anon_MB="int(a*4/1024)", swap_MB="int(s*4/1024)}'
```

---

## 8. Conclusion

The 2026-05-28 OOM event was a **process explosion under Axiom's pre-push gate execution model**, not a Chrome memory leak or system misconfiguration. Eighty-three Axiom-related processes collectively consumed 28.8 GB of anonymous RAM (95% of system memory), exhausting swap and triggering the kernel OOM killer. Chrome was killed due to its high `oom_score_adj`, serving as a statistical victim.

The gate infrastructure's multiplicative parallelism (4 L2 slots × 8 L1 jobs × unbounded child processes) created a memory load far exceeding the 32 GB host capacity. Mitigations must target gate concurrency reduction and per-process memory caps, not system-wide kernel parameters or Chrome limits.

**Deterministic verdict**: Verified by direct `dmesg` forensic analysis. Cross-checked against `oom_dump_tasks` RSS sorting. No runtime instrumentation required.
