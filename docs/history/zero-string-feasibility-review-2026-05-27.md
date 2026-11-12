# 3-Step OOM Eradication Plan — Feasibility Review

**Date**: 2026-05-27
**Reviewer**: Axiom Orchestrator Agent
**Subject**: User-proposed Zero-String Pipeline + Process-Level Isolation + Compiler Bug Suppression
**Standard**: AGENTS.md §0.3 First-Principles Elegance (Ideal, Elegant, Fundamental, Deterministic)

---

## Executive Summary

| Phase | Proposal | Feasibility | Risk Level | Verdict |
|-------|----------|-------------|------------|---------|
| P0 | `-d:useMalloc` + MaxStdoutPerGate | **Immediately applicable** | Low | ✅ APPROVED |
| P1 | Zero-String Pipeline (GateResult refactoring) | **High** | Medium (breaking change) | ✅ APPROVED with migration plan |
| P2 | malebolgia → `std/osproc` execProcesses | **Medium** | High (internal gate split required) | ⚠️ CONDITIONALLY APPROVED — requires architectural prerequisite |

---

## Phase 1: Zero-String Pipeline (Zero-Allocation Data Struct)

### Proposal
Remove the `stdout: string` and `stderr: string` fields from `GateResult`, and immediately append process output to `logs/gates/{gateId}.log` files. Worker threads only return lightweight objects (containing only `success`, `exitCode`, `logPath`).

### Feasibility Analysis

**Impact Surface Audit** (`code-index` verification):
- `GateResult` definition location: `src/cli/procedure_gate.nim:7` and `src/gate/types.nim` (estimated)
- `scripts/gate_hook.nim`'s `runNimCheckForFilesImpl`, `runGatewayTestsImpl` — directly use the `allOutput: string` accumulation pattern
- `scripts/gate_replay.nim` — possible `GateResult.stdout` reference
- `src/gate/gate_utils.nim` — converts `execCmdEx` results to `GateResult` in `runSingleGateImpl`
- `tests/features/steps/gate_steps.nim` — possible `stdout` reference when verifying gate output in BDD steps

**Migration Complexity**: **Medium-High**
- Changing the `GateResult` type affects the entire `src/gate/` directory
- 10+ existing gate binaries may return results based on stdout
- BDD spec's `Then gate output contains "..."` steps need to be rewritten to be file-based
- Logic changes needed in `ax report` TUI to display gate logs in real-time or post-hoc

**First-Principles Score**:
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| **Ideal** | ✅ | Compile-time prevention: large string heap allocation becomes impossible |
| **Elegant** | ✅ | File I/O is a basic feature of Nim's standard library (`std/streams`, `std/os`) |
| **Fundamental** | ✅ | The architecture itself is the solution, not a hardcoded exception |
| **Deterministic** | ✅ | File SSOT guarantees same input → same file path/content |

**Verdict**: ✅ **APPROVED**. Since this is a breaking change, a migration plan and deprecation window are required.

---

## Phase 2: malebolgia → `std/osproc` execProcesses

### Proposal
Completely remove the malebolgia thread pool and execute gate binaries in parallel at the OS process level using `std/osproc.execProcesses`. Shift the concurrency subject from Nim runtime threads → OS processes.

### Feasibility Analysis

**Critical API Constraint** (per `std/osproc` official docs):
```nim
proc execProcesses*(cmds: openArray[string], options = {poStdErrToStdOut},
                   n = countProcessors(),
                   beforeRunEvent: proc(idx: int) = nil,
                   afterRunEvent: proc(idx: int, p: Process) = nil): int
```

**Constraint ① — Cannot execute internal gates**:
- `execProcesses` only accepts **external command strings**
- Currently, internal gates (`nim-check`, `gateway-test`) in `gate_hook.nim` are identified by `GateConfig.entry == ""` and are **Nim proc internal calls** (`runNimCheckForFilesImpl`, `runGatewayTestsImpl`)
- To execute them via `execProcesses`, **separate binary extraction is mandatory**:
  - `scripts/nim_check_gate.nim` → `bin/nim_check_gate`
  - `scripts/gateway_test_gate.nim` → `bin/gateway_test_gate`

**Constraint ② — Cannot set individual environment variables**:
- `execProcesses` executes all processes in the **same environment**
- Currently `runAllGatesParallel` sets `gate.envVars` per gate using `putEnv`:
  ```nim
  for gate in active:
    for (k, v) in gate.envVars:
      putEnv(k, v)
  ```
- To preserve this functionality, a wrapper script or `env` command prefix is required (e.g., `env KEY=VALUE bin/gate`)

**Constraint ③ — No built-in stdout file redirect**:
- `execProcesses` can specify `options` like `poParentStreams`, `poStdErrToStdOut`, etc.
- But there is no feature to **redirect each process to a different log file**
- To combine with Phase 1 (Zero-String), each process must be executed directly via `startProcess` and pipe `poStdErrToStdOut` + `outputStream` directly to a file
- In this case, the advantage of `execProcesses` (simplicity) disappears and becomes no different from `startProcess` batching

**Constraint ④ — No real-time progress monitoring**:
- `execProcesses` blocks until all processes complete
- `beforeRunEvent`/`afterRunEvent` callbacks provide the index and `Process` object, but **access to output content is limited**
- Currently `runAllGatesParallel` provides UX that outputs `PASS`/`FAIL` to stderr immediately upon gate completion
- To maintain this UX, `startProcess` + `poll` loop is more suitable

**Architecture Prerequisite**:
> To completely remove malebolgia, **all gates must be unified as external binaries**. The prerequisite is extracting internal gates (`nim-check`, `gateway-test`) into separate `.nim` files and compiling them to `bin/`.

**First-Principles Score**:
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| **Ideal** | ✅ | OS processes reclaim 100% of memory upon termination |
| **Elegant** | ⚠️ | `execProcesses` is language-native, but API constraints require mixing with `startProcess` batching |
| **Fundamental** | ⚠️ | Extracting internal gates into external binaries = major structural change. This itself is fundamental, but the distance to realization is far |
| **Deterministic** | ✅ | OS processes are deterministic |

**Alternative Recommendation**:
> Instead of completely removing malebolgia, **unify gate-level parallelism with `startProcess` batching**:
> - External gates: `startProcess(gate.entry, ...)` → stdout file redirect
> - Internal gates: `startProcess("bin/nim_check_gate", ...)` → internal gates also become external binaries (prerequisite)
> - Using `startProcess` + `waitForExit` loop instead of `execProcesses` allows environment variable setting, file redirect, and real-time monitoring
> - This approach maintains the "Process-Level Isolation" philosophy while avoiding API constraints

**Verdict**: ⚠️ **CONDITIONALLY APPROVED**. Internal gate external binary extraction must precede. Extending `startProcess` batching is more practical than `execProcesses` itself.

---

## Phase 3: Compiler Bug Suppression (-d:useMalloc + MaxStdoutPerGate)

### Proposal
- Permanently include `-d:useMalloc` when compiling `scripts/gate_hook` and `scripts/gate_replay`
- Hard cap `MaxStdoutPerGate = 2MB` in `runNimCheckForFilesImpl` etc.

### Feasibility Analysis

**`-d:useMalloc`**:
- The only workaround verified by GitHub nim-lang/Nim #23361 and Forum #13322
- Bypass Nim's mimalloc default allocator and use OS `malloc` directly
- **Performance impact**: Negligible (gate hook is I/O bound)
- **Trade-off**: Some Nim heap optimizations (deterministic destructor, fast path) are disabled
- **AGENTS.md §0.3 Assessment**: Not an ideal solution (fallback). Documentation mandatory:
  - (a) Ideal: Remove after Zero-String Pipeline completion
  - (b) Why impossible now: Nim 2.0 ORC official bug, no upstream patch confirmed
  - (c) Trade-offs: Slight allocator performance degradation, minor impact on deterministic destructor
  - (d) Timeline: Planned for removal after Zero-String Pipeline deployment

**`MaxStdoutPerGate = 2MB`**:
- Immediately applicable defense in depth
- 2MB covers most `nim check` output while preventing OOM
- **AGENTS.md §0.3 Assessment**: May appear as a hardcoded magic number, but this is a defense mechanism and can avoid fundamental violation by making it configurable in `axiom.toml`

**First-Principles Score**:
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| **Ideal** | ❌ | Runtime workaround. Ideal is Zero-String |
| **Elegant** | ✅ | Compiler flag is language-native |
| **Fundamental** | ⚠️ | Can be justified as a magic number or defense mechanism. Improvable with `axiom.toml` configuration |
| **Deterministic** | ✅ | `-d:useMalloc` is deterministic |

**Verdict**: ✅ **APPROVED** as emergency fallback. Must be documented and the ideal solution timeline must be specified.

---

## Recommended Execution Order

### Phase 0 (Immediate, Today)
1. Add `-d:useMalloc` to `scripts/gate_hook.nim` and `scripts/gate_replay.nim` build commands
2. Hardcode `MaxStdoutPerGate = 2MB` into `scripts/gate_hook.nim` (or read from `axiom.toml`)
3. Commit and recompile binaries

### Phase 1 (This Week)
1. Refactor `GateResult` type: remove `stdout`/`stderr`, add `logPath: string`
2. Convert `runNimCheckForFilesImpl`, `runGatewayTestsImpl`, `runSingleGateImpl` to file-based output
3. Create `logs/gates/` directory and establish file naming conventions
4. Update existing gate consumers (`gate_replay.nim`, BDD steps, `ax report`)
5. Update BDD spec (verify gate log file existence)
6. Commit

### Phase 2 (Next Week, After Phase 1 Completion)
1. Extract internal gates (`nim-check`, `gateway-test`) into external binaries:
   - `scripts/nim_check_gate.nim` → `bin/nim_check_gate`
   - `scripts/gateway_test_gate.nim` → `bin/gateway_test_gate`
2. Remove malebolgia from `runAllGatesParallel`
3. Implement gate-level parallelism with `startProcess` batching (unify external + internal gates)
4. Redesign environment variable passing mechanism (`env` prefix or wrapper script)
5. Commit

### Phase 3 (After Phase 2 Stabilization)
1. Verify whether `-d:useMalloc` can be removed (confirm Zero-String completely bypasses the ORC bug)
2. Performance benchmark: useMalloc vs native allocator
3. Update documentation

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Phase 1 breaks BDD steps | High | Medium | Update BDD spec first, implement step stubs, then parallel development |
| Phase 1 breaks `ax report` TUI log display | Medium | Medium | Replace TUI loader with `logPath`-based file reading |
| Phase 2 fails to separate internal gate binaries | Medium | High | Add `nimble` task, extend `bin/` build chain |
| `-d:useMalloc` performance degradation | Low | Low | Negligible since I/O bound, removed in Phase 3 |
| Debug information loss due to `MaxStdoutPerGate` | Low | Medium | 2MB covers most error output, truncation marker at file end if exceeded |

---

## Conclusion

**The 3-step plan is strategically sound and architecturally correct.**

- **Phase 0** is an emergency mitigation that must be executed immediately.
- **Phase 1 (Zero-String)** is the ideal solution, fundamentally guaranteeing memory safety regardless of the ORC bug.
- **Phase 2 (malebolgia removal)** is feasible, but extending `startProcess` batching is more practical due to `execProcesses` API constraints. Internal gate external binary extraction is a mandatory prerequisite.

Per AGENTS.md §0.3, `-d:useMalloc` is classified as a fallback, and should be removable upon Zero-String Pipeline completion.
