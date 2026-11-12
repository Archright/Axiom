# Gate Cgroup Isolation

> **RETIRED 2026-10-03** (decision-authority unification): the native-cgroup sandbox
> module this spec describes was removed — resource constraint is the OS's authority,
> not an Axiom-owned fact. Kept as a historical contract record; see
> `docs/agents/operations.md` (resource boundary) for the current state.

## §13. Native Cgroup v2 Direct Control

### 13.1 Architecture

The primary cgroup isolation method has been migrated from `systemd-run --user --scope` (CLI-based, D-Bus IPC per call) to **native cgroup v2 sysfs writes** (O(1) per gate, zero D-Bus overhead).

```
[Before] gate_cmd → systemd-run (D-Bus IPC) → systemd daemon → kernel cgroup → execute
[After]  gate_cmd → mkdir cgroup_dir → writeFile(cgroup.procs, PID) → execute
```

### 13.2 Detection Priority

1. **Native cgroup v2** — `/sys/fs/cgroup/cgroup.controllers` exists and writable
2. **systemd-run fallback** — for containers / non-cgroup-v2 environments
3. **No isolation** — last resort with warning

### 13.3 Resource Limits (Direct Sysfs)

| Control File | Value | Purpose |
|-------------|-------|---------|
| `memory.max` | 4G (configurable via `AXIOM_CGROUP_MEMORY_MAX`) | Hard memory limit |
| `memory.high` | 2G (configurable via `AXIOM_CGROUP_MEMORY_HIGH`) | High watermark for reclaim |
| `cpu.max` | 80000 100000 (configurable via `AXIOM_CGROUP_CPU_MAX`) | 80% CPU quota |

### 13.4 Cleanup

- **Normal exit**: `writeFile(cgroupDir / "cgroup.kill", "1")` → `removeDir(cgroupDir)`
- **Timeout**: Same cleanup path via `killCgroup()` proc
- **Fallback** (kernel < 5.14): `p.kill()` + `p.close()`

### 13.5 Module

`src/infrastructure/native_cgroup.nim` — 215 lines, self-contained, `{.push raises: [].}`, `when defined(linux)` guard.
