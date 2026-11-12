# Build Loop Guardrails

## Overview

This document defines deterministic rules to prevent multi-hour edit-compile cycles that waste developer time. These guardrails are enforced by the build system and documented here as the single source of truth.

## 1. Batch Error Collection

**Rule**: Run `nim check` ONCE, collect ALL errors, fix in ONE batch, then compile.

**Rationale**: 18+ round-trips for individual error fixes waste ~6h24m (observed in pre-refactor session). The compiler reports errors in dependency order; fixing later errors first may cascade into new earlier errors.

**Procedure**:
```bash
nim check src/cli/precompile_gates.nim 2>&1 | tee /tmp/errors.txt
# Read ALL errors, group by category
# Fix all related errors in one edit session
# Re-run nim check once
```

**Exception**: Critical type errors that block other fixes (e.g., missing import).

## 2. Nim API Verification Before Editing

Verify standard library APIs against Nim 2.2.10 documentation before assuming signatures.

### 2.1 `std/typedthreads` (NOT `std/threads`)

`typedthreads` provides typed thread support. `threads` is deprecated in Nim 2.x.

```nim
# CORRECT
import std/typedthreads

# WRONG (deprecated)
import std/threads
```

### 2.2 Exception Handling

Use `except CatchableError:` not `as e:` pattern when catching is unnecessary.

```nim
# CORRECT - no variable needed
except CatchableError:
  discard

# WRONG - allocates exception object when not used
except CatchableError as e:
  if e.msg.contains("permission"): discard
```

### 2.3 Named-Argument vs Positional Signature Checks

`execCmdEx` in Nim 2.2.10 takes a single command string:

```nim
# CORRECT
let result = execCmdEx("nim c --hints:off " & args)
let output = result.output
let code = result.exitCode

# WRONG (tuple unpacking not supported for named fields in Nim 2.2.10)
let (outp, code) = execCmdEx(cmd)  # Error: expression '' has no type
```

### 2.4 `countProcessors` Import Ambiguity

`countProcessors` is in `osproc`, not `cpuinfo`.

```nim
# CORRECT
import std/osproc
let n = countProcessors()

# WRONG
import std/cpuinfo  # No such module
```

## 3. Round-Trip Cap

**Rule**: After 3–5 consecutive compile failures, STOP and write a diagnosis memo.

**Procedure**:
1. Stop editing
2. Write `docs/evidence/diagnosis_<timestamp>.md` with:
   - Error pattern observed
   - Suspected root cause
   - Proposed fix or workaround
3. Create GitHub issue or ask architect

**Rationale**: Repeated failures indicate systemic issues (type mismatch, missing dependency, or API change) that individual fixes cannot resolve.

## 4. Never Silently Defer Parallelism

**Rule**: Any deferral of parallel execution must be logged as a design decision.

**Example**:
```nim
# BAD - silent deferral
# TODO: parallelize later
for item in items: process(item)

# GOOD - logged design decision
logInfo("build", "[parallel] Sequential processing: parallelism deferred for simplicity")
for item in items: process(item)
```

## 5. Manifest Field Discipline

**Rule**: Gate manifest fields are SSOT. Do not hardcode gate lists.

```nim
# CORRECT - dynamic filter
for gate in allGates():
  if gate.executionMode == "interpreted":
    logInfo("Skipping " & gate.id)
    continue
  # compile...

# WRONG - hardcoded list
let ignored = ["gate-a", "gate-b", "gate-c"]
if gate.id notin ignored: compile...
```

## 6. Effect System Pragmas

**Rule**: Every `proc` at I/O boundary must have `{.axiomEffect...}` pragma.

```nim
# CORRECT
proc readFile(path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =

# WRONG - missing pragma
proc readFile(path: string): string =
```

## 7. Precompile Gate Filtering (Pillar 3)

**Rule**: Exclude gates with `"execution_mode": "interpreted"` from AOT precompilation.

```nim
# In precompile_gates.nim main()
for gate in gates:
  if gate.executionMode == "interpreted":
    logInfo("[precompile] Skipping interpreted gate " & gate.id & " (no AOT)")
    continue
  # add to compilableGates...
```

**Verification**: Gate count for "compilable source entries" drops by ~28 (from 56 to 28).

## 8. Architectural Decisions — Precompile Pipeline

### 8.1 cgroup Role Separation: Query vs Sandbox

**Build-worker query**: `configuredCompileWorkers()` (`precompile_gates.nim:227`) uses an inline read-only reader for `/sys/fs/cgroup/cpu.max` to determine worker count. Pure query — the OS is the resource authority; Axiom consumes its values and runs no resource controller.

**Runtime sandbox**: none in-process — gate execution inherits OS process/resource boundaries. The former cgroup sandbox module was removed (2026-10-03 decision-authority unification; resource control is not an Axiom-owned fact).

### 8.2 `--skipUserCfg:on` Self-Injection

`buildCompileCommand()` (`precompile_gates.nim:260`) injects `--skipUserCfg:on` into the `nim c` child command. This achieves hermetic build without modifying CI YAML or external config files. **§-1 scope invariant (drift correction 2026-10-15)**: CI YAML and external config files are **not** §-1-immutable — AGENTS.md §-1 protects only `src/gate/runners/import_encapsulation_gate.nim`, the `config.nims` importEncapsulation block, and `AGENTS.md` itself; workflow YAML is editable via the committed epoch-cutover path ([ci_epoch_cutover.md](ci_epoch_cutover.md); evidence: `2c94c9914`·`c2142ec37`·PR #829 edited `admission-check.yml` and landed).

### 8.3 28 Interpreted Gates: Permanent VM Isolation

Gates with `execution_mode: "interpreted"` are **permanent VM-isolated** (never AOT-compiled). The filter at precompile_gates.nim:450-455 reads manifest JSON directly (supports both `execution_mode` and `executionMode` spellings), logs "Skipping interpreted gate...", and skips compilation. **Do NOT attempt to fix their sources to convert to AOT** — that is the committed architectural decision (permanent VM isolation), not a §-1 protection. **§-1 scope invariant (drift correction 2026-10-15)**: interpreted gate sources are **not** §-1-immutable — AGENTS.md §-1 protects only `src/gate/runners/import_encapsulation_gate.nim`, the `config.nims` importEncapsulation block, and `AGENTS.md` itself; execution-boundary changes land via the committed epoch-cutover path ([ci_epoch_cutover.md](ci_epoch_cutover.md)).

## 9. Git Pager Policy

The repo has `core.pager = cat` configured. Do NOT add `--no-pager` flags.

```bash
# CORRECT
git status

# WRONG
git --no-pager status
```

## 10. DX 4계층 Build Loop (L0–L3)

### 10.1 계층 개요

| 계층 | 목적 | 명령 | 게이트 수 | 캐시 정책 |
|------|------|------|----------|-----------|
| **L0 Edit** | 소스 편집 — 변경 사항 작성 | 편집기에서 작업 | — | 캐시 해당 없음 |
| **L1 test-fast** | 반복 개발 — 빠른 증분 correctness 확인 | `make test-fast` | 6 (GATES_FAST) | reusable(persistent test/debug nimcache) |
| **L2 local-verify-static** | 로컬 최종 — 모든 local static gate 통과 여부 확인 | `make local-verify-static` | 16 (GATES_FAST + GATES_STATIC) | reusable(persistent test/debug nimcache) |
| **L3 CI** | 푸시·CI — hermetic full verification (source of truth) | `make ci-integration` (CI 파이프라인) | 18+ (GATES_FAST + GATES_STATIC + GATES_FULL + CI-only) | isolated + disposable (release/LTO nimcache) |

### 10.2 Hermetic(Incremental) vs Hermetic(CI)

| 구분 | 캐시 | 목적 | 증분성 | release-LTO | source-of-truth |
|------|------|------|--------|-------------|-----------------|
| **Hermetic(Incremental)** — L1 | reusable, persistent nimcache | 빠른 증분 개발 사이클 | Yes | No | 로컬 |
| **Hermetic(CI)** — L3 | isolated + disposable | hermetic full verification | No | Yes (release/LTO) | CI (hermetic) |

### 10.3 의사결정 규칙

- **반복 개발** = `make test-fast` (L1, 6게이트)
- **로컬 최종** = `make local-verify-static` (L2, 16게이트)
- **푸시·CI** = full (L3, 18+게이트)

### 10.4 L2 주의사항

L2는 **"모든 local static gate가 통과했는가"** 로만 표현한다. L2는 "CI에 보내도 되는가"와 동급으로 브랜딩하지 않는다. L2는 로컬 품질 게이트이며, CI hermetic 검증(L3)과는 분리된 개념이다.

- `nim check` failures block compilation
- CI pipeline enforces all rules
- Architect approval required for rule exceptions

### 10.5 캐시 정리 타겟 구분

| 대상 | 명령 | 범위 | 해당 계층 |
|------|------|------|----------|
| L1 reset | `make clean-test-cache` | test/debug nimcache만 제거 | L1 |
| 전체 캐시 | `make clean-cache` | hermetic + compiler + dep caches 전체 제거 | L0–L3 |

`clean-test-cache`는 L1(test-fast)의 nimcache만 리셋하여 증분 개발 사이클을 초기화한다. `clean-cache`는 모든 로컬 reusable 캐시를 일괄 제거하며, hermetic 빌드 환경을 완전히 초기화할 때 사용한다.

### 10.6 게이트 티어와 접점 계약

| 게이트 티어 | 게이트 수 | 접점 계약 | 사용 계층 | 설명 |
|------------|----------|----------|----------|------|
| FAST | 6 | 빠른 | L1 (test-fast) | 경량 결정론적 게이트 — 증분 개발 사이클 |
| STATIC | 10 | 로컬 | L2 (local-verify-static) | 정적 분석/아키텍처 게이트 — 로컬 최종 확인 |
| FULL | 2 | 로컬 | L2 full / L3 | 무거운 검증 (Lean vacuity 등) — CI 또는 로컬 전체 검증 |

FAST 티어는 "빠른" 접점 계약을 가진다 — `make test-fast`를 통해 L1에서 증분적으로 실행되며, persistent nimcache를 재사용한다. STATIC과 FULL 티어는 "로컬" 접점 계약을 가진다 — `make local-verify-static`(L2) 또는 `make local-verify-static-full`/CI(L3)에서 실행되며, 더 엄격한 검증을 수행한다.

## History

- 2024-07-25: Initial codification (6h24m loop incident)