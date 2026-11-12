# IR Pipeline Integration (Phase 4D)

**생성일**: 2026-06-29
**상태**: Phase 4D — Compile-time IR generation + runtime cross-validation wiring
**소스**: `src/core/trusted/axiom_pragmas.nim`, `src/core/trusted/ast_to_ir.nim`,
        `src/verification/cross_validation.nim`, `src/cli/axiom_engine.nim`,
        `src/verification/batch_uap/loop_driver.nim`
**AGENTS.md 참조**: §0.1 (프로젝트 목적), §1 (아키텍처 v31)
**이전 사양**: `docs/spec/axiom_core_ir_spec.md` (IR 타입 시스템 + 백엔드 매핑)

---

## 1. 개요

Phase 4D는 Axiom Core IR 파이프라인의 **컴파일 타임 생성**과 **런타임 교차 검증**을
`ax prove` 워크플로우에 통합하는 단계이다. 세 가지 핵심 통합 지점이 존재한다:

1. **컴파일 타임 IR 생성** — `{.axiomImpl.}` 매크로가 `convertFuncDef()`를 호출하여
   Nim AST를 Axiom Core IR로 변환한다.
2. **런타임 교차 검증** — `cross_validation.nim`이 `axiom_engine.nim`에 임포트되어
   batch UAP와 lean verify 사이에 배치된다 (fail-open).
3. **레거시 경로 격리** — `--legacy-uap` 플래그가 레거시 batch_uap 경로를 보존한다.

---

## 2. 컴파일 타임 IR 생성

### 2.1 `{.axiomImpl.}` 매크로 흐름

**소스**: `src/core/trusted/axiom_pragmas.nim` — `axiomImpl` 매크로 (라인 730-769)

```
{.axiomImpl.} 매크로 호출
  │
  ├─ Step 1: {.axiom.} 프래그마를 정의에 추가
  │
  ├─ Step 2: walkAndGuard(def[^1], funcName) — 구문 경계 검사
  │          (pure_func_guard에서 import)
  │          → var/while/for/assignment 발견 시 컴파일 에러
  │
  ├─ Step 3: convertFuncDef(def) — Nim AST → IRFuncDef 변환
  │          (ast_to_ir에서 import)
  │          → try/except로 감싸서 비치명적 에러로 처리
  │          → echo "[axiomImpl] IR: {name} params={n} recursive={bool}"
  │          → 실패 시: echo "[axiomImpl] IR generation failed for: {name} (non-fatal)"
  │
  └─ result = def  (변경된 정의를 컴파일러에 반환)
```

### 2.2 비치명적 설계 (Non-Fatal)

컴파일 타임 IR 생성은 **비치명적(non-fatal)**이다:

- `try/except CatchableError` 블록으로 감싸져 있다.
- IR 변환이 실패해도 컴파일이 차단되지 않는다.
- `echo`로 메타데이터를 출력하여 컴파일 로그에서 IR 생성 상태를 확인할 수 있다.
- **근거**: Phase 4D는 점진적 통합이다. IR 파이프라인이 완전히 구현되기 전에도
  기존 워크플로우가 중단되어서는 안 된다.

### 2.3 컴파일 타임 IR 생성 시나리오

**Scenario: 정상적인 IR 생성**

```nim
func add(a, b: int): int {.axiomImpl.} =
  a + b
```

컴파일 로그 출력:
```
[axiomImpl] IR: add params=2 recursive=false
```

**Scenario: 복잡한 재귀 함수**

```nim
func factorial(n: int): int {.axiomImpl.} =
  if n == 0: 1
  else: n * factorial(n - 1)
```

컴파일 로그 출력:
```
[axiomImpl] IR: factorial params=1 recursive=true
```

**Scenario: IR 생성 실패 (비치명적)**

지원되지 않는 AST 패턴이 포함된 경우 IR 생성이 실패하지만 컴파일은 계속된다:
```
[axiomImpl] IR generation failed for: complexFunc (non-fatal)
```

### 2.4 지원되는 AST 노드

| Nim AST 노드 | IR 노드 | 설명 |
|-------------|---------|------|
| `nnkIntLit` | `irLit` | 정수 리터럴 |
| `nnkIdent` | `irVar` | 변수 참조 |
| `nnkInfix` | `irBinOp` | 이항 연산 (+, -, *, <, == 등) |
| `nnkPrefix` | `irUnaryOp` | 단항 연산 (-, not) |
| `nnkCall` | `irCall` / `irRecCall` | 함수 호출 (자기 재귀 감지) |
| `nnkIfExpr`/`nnkIfStmt` | `irIf` | 조건 분기 |
| `nnkCaseStmt` | `irCase` | 패턴 매칭 |
| `nnkLetSection` | `irLet` (중첩) | let 바인딩 |
| `nnkStmtList` | `convertBody` | 본문 (let + 최종 표현식) |

---

## 3. 런타임 교차 검증 (Cross-Validation)

### 3.1 통합 위치

**소스**: `src/cli/axiom_engine.nim` — `runProofPipeline` (라인 401-416)

교차 검증은 `ax prove` 파이프라인의 다음 두 단계 사이에 배치된다:

```
runBatchVerification()  ← batch UAP 완료
  │
  ├─ crossValidationBlock  ← 교차 검증 (fail-open)
  │   ├─ cross_validation.nim import (라인 39)
  │   ├─ cvsBothFailed 상태 (플레이스홀더)
  │   └─ reportJson["crossValidation"] = %*{...}
  │
  └─ runLeanVerify()  ← Lean 검증 시작
```

### 3.2 Fail-Open 설계

교차 검증은 **fail-open**이다:

- 검증 실패가 파이프라인을 차단하지 않는다.
- `crossValidationBlock` 내부에서 상태를 로깅하고 `reportJson`에 기록한다.
- `lean verify`는 교차 검증 결과와 독립적으로 실행된다.

**근거**: 교차 검증은 현재 플레이스홀더 단계이다. 향후 Phase에서 IRFuncDef 추출이
완료되면 실제 검증으로 승격될 때까지 fail-open으로 유지한다.

### 3.3 `cross_validation.nim` API

**소스**: `src/verification/cross_validation.nim`

| 함수 | 설명 |副作用 |
|------|------|-------|
| `crossValidate(f: IRFuncDef)` | IR → SMT + IR → Lean 변환 후 구조적 일관성 검증 | 없음 (func) |
| `validateCrossResult(z3Success, leanSuccess, f)` | 외부 성공 플래그와 IR 정의로 교차 검증 수행 | 없음 (func) |
| `computeIrDigest(f: IRFuncDef)` | IR 구조의 결정론적 SHA-256 다이제스트 계산 | 없음 (func) |
| `checkStructuralConsistency(f, z3, lean)` | 두 백엔드 출력의 구조적 일관성 확인 | 없음 (func) |
| `crossValidationStatus(r)` | `CrossValidationResult`를 열거형 상태로 변환 | 없음 (func) |

### 3.4 교차 검증 상태 열거형

```nim
type
  CrossValidationStatus* = enum
    cvsConsistent    ## 양쪽 백엔드가 유효하고 일치하는 출력 생성
    cvsZ3Failed      ## SMT-LIB2 생성 실패 또는 빈 출력
    cvsLeanFailed    ## Lean 4 생성 실패 또는 빈 출력
    cvsBothFailed    ## 양쪽 모두 실패 (현재 기본값 — 플레이스홀더)
    cvsDiverged      ## 양쪽 모두 출력했지만 구조적 검사 불일치
```

### 3.5 구조적 일관성 검사 항목

`checkStructuralConsistency`는 다음 항목을 검증한다:

1. **非空 확인**: SMT 출력과 Lean 출력이 모두 비어있지 않은지
2. **함수명 확인**: SMT에 `(define-fun {name})`, Lean에 `def {name}`이 포함되어 있는지
3. **파라미터 확인**: 모든 파라미터 이름이 두 출력에 나타나는지

---

## 4. 레거시 경로 격리 (Legacy Path Isolation)

### 4.1 `--legacy-uap` 플래그

**소스**: `src/verification/batch_uap/loop_driver.nim` (라인 43-45, 432-441)

```nim
var useLegacyUap* = false          # 기본값: IR 기반 경로
proc setLegacyUapMode*(enabled: bool) = useLegacyUap = enabled
```

### 4.2 경로 분기

`runBatchUapOrchestration`의 시작 부분에서 라우팅이 결정된다:

```nim
if useLegacyUap:
  stderr.writeLine("batch-uap: using LEGACY path (--legacy-uap)")
else:
  stderr.writeLine("batch-uap: using IR-based path (default)")
```

### 4.3 설계 의도

| 경로 | 상태 | 설명 |
|------|------|------|
| **IR 기반 경로** (기본) | 플레이스홀더 | 향후 ast_to_ir → ir_to_smt → Z3 → cross_validation 체인을 구현할 경로 |
| **레거시 경로** (`--legacy-uap`) | 보존 | 기존 batch UAP 오케스트레이션 로직을 그대로 유지 |

### 4.4 레거시 경로 은퇴 일정

레거시 경로는 Phase 6A-6D에서 점진적으로 은퇴한다:

| Phase | 내용 |
|-------|------|
| Phase 6A | IR 기반 경로에서 실제 ast_to_ir 호출 활성화 |
| Phase 6B | ir_to_smt → Z3 실행 통합 |
| Phase 6C | cross_validation이 실제 IRFuncDef로 검증 수행 |
| Phase 6D | `--legacy-uap` 플래그 deprecated 경고 추가 |

---

## 5. IR 파이프라인 체인 (Pipeline Chain)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPILE TIME (nim c)                             │
│                                                                     │
│  Nim Source Code                                                    │
│    │                                                                │
│    ▼                                                                │
│  {.axiomImpl.} macro                                                │
│    │                                                                │
│    ├─► pureFuncGuard (syntactic guard)                              │
│    │     └─ walkAndGuard: var/while/for/assignment → compile error   │
│    │                                                                │
│    └─► ast_to_ir.convertFuncDef (compile-time IR generation)        │
│          └─ Nim AST → IRFuncDef (try/except, non-fatal)             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    (IRFuncDef in memory)
                              │
┌─────────────────────────────────────────────────────────────────────┐
│                    RUNTIME (ax prove)                                │
│                                                                     │
│  ax prove                                                           │
│    │                                                                │
│    ▼                                                                │
│  Topology Analysis                                                  │
│    │                                                                │
│    ▼                                                                │
│  Batch UAP Orchestration                                            │
│    │  (loop_driver.nim — useLegacyUap routing)                      │
│    │                                                                │
│    ├─► [IR-based path] — TODO: actual IR pipeline                   │
│    │     ├─ ast_to_ir.convertFuncDef  (Nim AST → IR)                │
│    │     ├─ ir_to_smt.irToSmtScript   (IR → SMT-LIB2)              │
│    │     ├─ solver_runner.runZ3        (SMT-LIB2 → result)          │
│    │     └─ cross_validation.crossValidate (structural check)       │
│    │                                                                │
│    └─► [Legacy path (--legacy-uap)] — existing batch UAP            │
│                                                                     │
│  Cross Validation (fail-open)                                       │
│    └─ cross_validation.nim: structural consistency check            │
│                                                                     │
│  Lean Verify (sandbox)                                              │
│    └─ lean_verify_cmd: lake build + sorry detection                 │
│                                                                     │
│  Report + Certificate                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. 현재 상태 (Current Status)

### 6.1 통합 완료 (Integrated)

| 구성 요소 | 소스 | 상태 |
|-----------|------|------|
| `pureFuncGuard` | `src/core/trusted/pure_func_guard.nim` | 완료 — 컴파일 타임 구문 경계 검증 |
| `ast_to_ir` | `src/core/trusted/ast_to_ir.nim` | 완료 — Nim AST → IRFuncDef 변환 (Phase 2C) |
| `ir_to_smt` | `src/core/trusted/ir_to_smt.nim` | 완료 — IR → SMT-LIB2 변환 |
| `ir_to_lean` | `src/core/trusted/ir_to_lean.nim` | 완료 — IR → Lean 4 변환 |
| `cross_validation` | `src/verification/cross_validation.nim` | 완료 — 교차 검증 로직 (Phase 4B) |
| `{.axiomImpl.}` 매크로 | `src/core/trusted/axiom_pragmas.nim` | 완료 — 통합 진입점 |
| `lean_verify_cmd` | `src/cli/lean_verify_cmd.nim` | 완료 — Lean sandbox 검증 |
| `--legacy-uap` 플래그 | `src/verification/batch_uap/loop_driver.nim` | 완료 — 경로 격리 |

### 6.2 와이어링 완료 (Wired, Placeholder)

| 구성 요소 | 위치 | 상태 |
|-----------|------|------|
| `cross_validation` import | `axiom_engine.nim` 라인 39 | 와이어링 완료 |
| 교차 검증 호출 사이트 | `axiom_engine.nim` 라인 401-416 | 플레이스홀더 — `cvsBothFailed` 반환 |
| `reportJson["crossValidation"]` | `axiom_engine.nim` 라인 410-414 | 구조만 존재 — 데이터 없음 |

### 6.3 보류 중 (Pending)

| 구성 요소 | 설명 | 예상 Phase |
|-----------|------|-----------|
| IRFuncDef 추출 | batch UAP 결과에서 IRFuncDef를 추출하는 메커니즘 | Phase 5A |
| `ir_to_smt` → Z3 실행 | IR에서 생성한 SMT-LIB2를 Z3로 실행하는 경로 | Phase 5B |
| `crossValidate` 실제 호출 | `crossValidate(funcDef)`를 각 노드에 대해 호출 | Phase 5B |
| 레거시 경로 은퇴 | `--legacy-uap` deprecated 경고 | Phase 6D |

## W1 Triage: {.axiom.} Coverage Analysis

### Background
`{.axiom.}` is used as both a pure-function marker (IR registration candidate) and a
validation/guard annotation (non-IR-registerable). The `{.axiomImpl.}` macro enforces
purity at compile time via `walkAndGuard` (src/core/trusted/pure_func_guard.nim),
which rejects the following node kinds: `nnkForStmt`, `nnkWhileStmt`,
`nnkVarSection`, `nnkAsgn`, `nnkVarTuple`, and `nnkIteratorDef`.

> **Note (restored guard):** `walkAndGuard` was previously a no-op (early-return stub)
> that silently allowed impure functions through. It has been **restored** with the full
> `forbiddenNodeKinds` set above. Any function annotated with `{.axiomImpl.}` that
> contains one of these patterns will now produce a **compile-time error**.

### Compile-Time Enforcement: `AXIOM_BOUNDARY_VIOLATION`

When a function containing forbidden node kinds is promoted to `{.axiomImpl.}`,
`walkAndGuard` emits a structured compile error:

```
AXIOM_BOUNDARY_VIOLATION: <pattern> detected in function '<funcName>'.
REFACTOR_GUIDE: Replace <pattern> with <suggestion> to achieve pure-function compliance.
```

This error is raised via `{.error: msg.}` on the macro expansion site, halting
compilation immediately. The `REFACTOR_GUIDE` portion provides actionable guidance
for the specific violation detected (e.g., "Replace nnkForStmt with a recursive
helper" or "Replace nnkAsgn with a constructor pattern returning `result`").

### Triage Results (19 Functions)
All 19 `{.axiom.}`-annotated functions in `src/core/` fail `walkAndGuard` and **will
produce `AXIOM_BOUNDARY_VIOLATION` compile errors** if promoted to `{.axiomImpl.}`.
The axiom registry's purity is therefore already 100% guaranteed at compile time.

| # | Function | Blocker |
|---|----------|---------|
| 1 | `acceptVerifiedAxiom` | nnkAsgn (var-param mutation) |
| 2 | `computeInformationGainWeightedAsi` | nnkForStmt |
| 3 | `isValidUuid` | nnkForStmt + nnkAsgn |
| 4 | `isValidUuidV4` | nnkAsgn (`result =`) |
| 5 | `isValidIsoDate` | nnkAsgn (`result =`) |
| 6 | `isValidMimeType` | nnkForStmt |
| 7 | `isValidBase64` | nnkWhileStmt + nnkForStmt |
| 8 | `isValidJsonBlob` | nnkWhileStmt |
| 9 | `isValidIso8601` | nnkWhileStmt |
| 10 | `graphHash` | nnkForStmt |
| 11 | `hasIdentifierNamed` | nnkForStmt |
| 12 | `findFirstNode` | nnkForStmt |
| 13 | `extractGenericParams` | nnkForStmt |
| 14 | `assignmentLhs` | nnkForStmt |
| 15 | `extractFfiParamsFromAst` | nnkVarSection + nnkForStmt |
| 16 | `buildAxProofSmtAssertions` | nnkForStmt |
| 17 | `indexDeclarationsInAst` | var-param + nnkForStmt |
| 18 | `collectReferencesInAst` | nnkForStmt |
| 19 | `countOccurrences` / `tokenizeSmtlib2` | nnkWhileStmt / nnkForStmt |

### Conclusion
0/19 functions qualify for `{.axiomImpl.}` promotion. Attempting to promote any of them
will trigger `AXIOM_BOUNDARY_VIOLATION` at compile time. These functions serve as
guard/validation markers and are correctly excluded from the IR registry. The
`{.axiom.}` pragma is retained on all 19 functions for their original purpose.

---

## Dual-Transpiler Architecture (Post-Phase C3)

### Current State
Two transpilers coexist for Nim→Lean conversion:

| Transpiler | Module | Entry Point | Used By |
|------------|--------|-------------|---------|
| **IR-first** | `core/trusted/ir_to_lean.nim` | `irToLeanModule(IRFuncDef)` | `lean_skeleton.nim`, `universal_assembler.nim` (fast path) |
| **Legacy bridge** | `core/translator/ast_to_lean_bridge.nim` | `extractNimFunction` + `buildLeanFunctionDef` | `lean_skeleton.nim`, `universal_assembler.nim` (fallback) |

### Lookup Priority (leanSource-first)
1. `lookupAxiomLeanSource(nodeId)` — returns pre-computed Lean from registry (O(1) string return)
2. `lookupAxiomIR(nodeId)` → `deserializeIRFuncDef` → `irToLeanModule` — deserialize+convert
3. `extractNimFunction` → bridge functions — string-based Nim AST parsing (legacy)

### Dead Code Removed (C3-A)
- `buildLeanBridge*` — zero callers
- `buildLeanBridgeFromSource*` — zero callers

### Retained Bridge Functions
These functions remain as fallback for non-registry functions:
- `extractNimFunction` — parses Nim source string
- `buildLeanFunctionDef` — generates Lean def block
- `buildLeanTheoremSkeleton` — generates def + theorem
- `translateNimTypeToLean` — type name mapping
- `translateNimExprToLean` — expression translation

### Removal Criteria
The bridge can be removed when ALL verification targets have `{.axiomImpl.}` equivalents in the registry. Current blocker: 19 `{.axiom.}` functions contain forbidden node kinds and will produce `AXIOM_BOUNDARY_VIOLATION` compile errors if promoted (see W1 Triage section).

## IR Pipeline in Batch UAP (Post-Phase C1)

### Architecture
`loop_driver.nim` now branches on `--legacy-uap`:

- **Default (non-legacy)**: Calls `runAllIrPipelines()` which iterates `runtimeAxiomRegistry` and runs the 4-stage pipeline (Deserialize → SMT-LIB2 → Lean → Cross-validate + Z3 check-sat) for each entry. Results are logged; failures are fail-open.
- **Legacy (`--legacy-uap`)**: Skips IR pipeline, proceeds directly to existing UAP per-node pipeline.

### Pipeline Stages
1. `deserializeIRFuncDef(entry.irSerialized)` — parse serialized IR
2. `irToSmtScript(funcDef)` — generate SMT-LIB2 script
3. `irToLeanModule(funcDef)` — generate Lean 4 module
4. `crossValidate(funcDef)` — structural consistency check
5. `runZ3CheckSat(smtScript)` — Z3 satisfiability (FFI-first, CLI fallback)

### Module: `src/verification/batch_uap/ir_pipeline_runner.nim`
- `IrPipelineResult` — result object with all pipeline outputs
- `runIrPipeline(entry)` — single-entry pipeline
- `runAllIrPipelines()` — registry-wide pipeline
- `runZ3CheckSat(smtScript)` — Z3 invocation (FFI/CLI)

---

## 7. 참고 문서

- `docs/spec/axiom_core_ir_spec.md` — IR 타입 시스템 + 양방향 변환 사양
- `docs/spec/syntactic_guard_spec.md` — 구문 경계 사양
- `docs/spec/two_phase_verification.md` — 2단계 검증 파이프라인 개요
- `src/core/trusted/axiom_pragmas.nim` — `{.axiomImpl.}` 매크로 (SSOT)
- `src/core/trusted/ast_to_ir.nim` — Nim AST → IR 변환기
- `src/verification/cross_validation.nim` — 교차 검증 엔진
- `src/cli/axiom_engine.nim` — `ax prove` 통합 진입점
- `src/verification/batch_uap/loop_driver.nim` — 레거시/IR 경로 라우팅

## v5 — Type-Level Encoding Sieve (Stage 1.5)

Added in v5-planB. Introduces a pre-filter stage between IR construction (Stage 1) and Z3 BMC (Stage 2).

### Flow
```
Stage 1: IR Construction
  ↓
Stage 1.5: classifyTypeLevel(f)  ← NEW
  ├─ true  → irToLeanRefinedModule → LSP check
  │         ├─ pass → vpTypeLevelEncoding + early return
  │         └─ fail → fail-open → Stage 2
  └─ false → Stage 2 (Z3 BMC)
```

LSP failure (crashed/deadlocked Lean LSP server, hover timeout) is a documented
fail-open path: `checkLeanSource` returns an error Result (`err("lsp-hover-timeout")`,
`err("lsp-hover-barrier-exception")`, or `err("lsp-diagnostics-poll-failure")`),
the router logs a warning and falls through to standard Z3 BMC. This is NOT
silent — the error message is logged at WARN level and propagated in
`TypeLevelRouterVerdict.error`. In `ir_pipeline_runner.nim`, the `except CatchableError`
handler at the LSP route call site logs the error via `logWarn` with the exact
message before falling back to the standard SMT pipeline.

### Key Files
- `src/sieve/trivial_lean_router.nim` — classifyTypeLevel + routeToTypeLevel
- `src/core/trusted/ir_to_lean.nim` §2 — refinedExprToProp, irToLeanRefinedModule
- `src/verification/lean_lsp_protocol.nim` — checkLeanSource (EOF barrier)
- `src/verification/batch_uap/ir_pipeline_runner.nim` — Stage 1.5 wiring

### Trust Model
TCB = AST scanner + Lean kernel. Z3 is excluded from the type-level path.

## §9. Task-Injected Pipeline (v32)

### 9.1 Problem Statement

`runAllIrPipelines()` processed the entire `runtimeAxiomRegistry` (214 entries) regardless of the `--limit` CLI flag. The limit was only applied to topology ranking and UAP legacy path.

### 9.2 Architecture

**Data Flow**:
```
CLI --limit=N
  → computeVerifiedFrontier(limit=N)
    → requests: seq[OrchestrationProofRequest] (≤N entries)
      → selectEntriesFor(requests)  [O(1) Table lookup]
        → SelectionReport { selected, skippedNodes, skippedCount }
          → runIrPipelinesFor(selection.selected)  [bounded executor]
```

**Key Principle**: Upper layer slices, lower layer executes. The executor contains no limit/counter — it processes 100% of what it receives.

### 9.3 SelectionReport

| Field | Type | Description |
|-------|------|-------------|
| `selected` | `seq[RuntimeAxiomEntry]` | Successfully mapped entries (topology order preserved) |
| `skippedNodes` | `seq[string]` | Topology nodes with no @axiom IR registry entry |
| `skippedCount` | `int` | len(skippedNodes) — quick anomaly detection |

### 9.4 Structural Anomaly Handling

When a topology node has no corresponding `@axiom` IR registry entry:
1. The node is added to `SelectionReport.skippedNodes`
2. `stderr.writeLine()` emits a Structural Anomaly warning
3. Processing continues with available entries (fail-open)

This is NOT a silent skip — it is a deliberate transparency mechanism.

### 9.5 O(1) Lookup Table

`registryLookup: Table[string, RuntimeAxiomEntry]` is built once at startup via `initRegistryLookup()` (called after `generateAxiomInit()` in `axiom_engine.nim`). This replaces the O(N) linear scan in `findRegistryEntry`.

### 9.6 Topology Order Preservation

`selectEntriesFor` iterates `requests` in forward order and appends to `result.selected`. This preserves the topological ordering computed by the topology engine — a critical invariant for deterministic testing and future dependency-aware parallelization.

## §10. SMT-LIB Logic Selection Parameterization (P3c)

### 10.1 Goal

Parameterize the `(set-logic ...)` command emitted by `irToSmtScript` so callers can select a different SMT-LIB logic. **Zero default-behavior change**: `QF_BV` remains the default.

### 10.2 Enum Members

The `SmtLogic` enum (SSOT in `src/core/types/smt_types.nim`, re-exported via `domain_types`) gained two members alongside the existing `slQfLia`/`slQfBv`/`slHorn`:

| Member | SMT-LIB logic | Purpose |
|--------|---------------|---------|
| `slQfBv` | `QF_BV` (default) | Bit-vectors |
| `slQfLia` | `QF_LIA` | Linear integer arithmetic |
| `slHorn` | `HORN` | Constrained Horn Clauses / SPACER |
| `slQfSlia` | `QF_SLIA` | String + linear integer arithmetic |
| `slQfAx` | `QF_AX` | Arrays with extensionality |

### 10.3 `smtLogicName` Helper

`src/core/logic/smt_logic.nim` now defines `func smtLogicName*(logic: SmtLogic): string` returning the official SMT-LIB2 logic name (`"QF_BV"`, `"QF_LIA"`, `"HORN"`, `"QF_SLIA"`, `"QF_AX"`). `emitLogicHeader` delegates to it, and `irToSmtScript` uses it for the `(set-logic ...)` line.

### 10.4 Parameter Threading

`irToSmtScript(f, includeOverflowDefines, logic = slQfBv)` in `src/core/trusted/private/ir_to_smt_chunk3.nim`. The defaulted `logic` parameter means **all existing call sites compile unchanged**:

- `src/verification/cross_validation.nim:99` → `irToSmtScript(f)` → default `slQfBv`
- `src/verification/batch_uap/ir_pipeline_runner.nim:89` → `irToSmtScript(funcDef)` → default `slQfBv`
- `src/verification/batch_uap/ir_pipeline_runner.nim:255` → `irToSmtScript(funcDef, includeOverflowDefines = true)` → default `slQfBv`
- `tests/trusted/test_ir_to_smt.nim` / `tests/trusted/z3_validate_smt2.nim` → default `slQfBv`

`src/core/logic/smt_logic.nim` is imported by `src/core/trusted/ir_to_smt.nim` (the include-based parent of chunk3) so `SmtLogic` + `smtLogicName` are in scope.

### 10.5 Explicit Decision: String/List Skip Gates NOT Flipped

Activating `QF_SLIA`/`QF_AX` **routing is future work**. The string/list skip gates are deliberately **NOT** flipped in this change:

- `axiom_ir.nim::isBmcSkippable` — remains unchanged
- `ax_classify.nim::vtNonDecidable` branches — remain unchanged

Rationale: flipping these gates would alter which functions are routed to BMC verification — a behavioral change beyond P3c's zero-default-change mandate. This change only makes the logic *selection* parameterizable; no existing routing decision is modified.

### 10.6 SSOT rlimit Envelope

The SSOT rlimit envelope (`z3_pool.nim::buildZ3QueryEnvelope`) is applied at the **query level**, prepending `(set-option :rlimit <z3DeterministicBudget>)` based on the absence of an existing rlimit option — **independent of the `(set-logic ...)` command**. Therefore every emitted script receives the identical deterministic rlimit (plus `:timeout`, `:random-seed`, `(reset)`, sentinel) envelope **regardless** of the selected logic (QF_BV, QF_LIA, HORN, QF_SLIA, or QF_AX). Parameterizing `logic` does not weaken the resource budget envelope.

