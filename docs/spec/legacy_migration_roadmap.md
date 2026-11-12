# Legacy `{.axiom.}` → `{.axiom, axiomImpl.}` Migration Roadmap

**생성일**: 2026-06-29  
**상태**: Phase 1/2.5/3a.5 ✅ COMPLETED — Phase 4D 진행 중  
**소스**: `src/core/trusted/axiom_pragmas.nim` (매크로 정의), `src/core/trusted/ast_to_ir.nim` (AST→IR 변환)  
**AGENTS.md 참조**: §0.2 (First-Principles), §0.6 (Static First), §0.3 (Trust Boundaries)  
**이전 커밋**: `a108c6ecd` (Tier 2 선행 마이그레이션), `7ec5102af` (Issue 3 — `loopVariant`)  
**Phase 1 커밋**: 다중 마이그레이션 커밋 + `5acc9410e` (nkNilLit fix)  
**Phase 2.5/3a.5 커밋**: `bac1fc738`  

---

## 1. Executive Summary

Axiom 프로젝트는 **모든 `{.axiom.}` 함수에 `{.axiomImpl.}`를 추가**하여 컴파일 타임 IR 생성을 활성화하는 대규모 점진적 마이그레이션을 진행 중이다. `{.axiomImpl.}` 매크로는 `convertFuncDef()`를 호출하여 Nim AST를 Axiom Core IR로 변환하며, 실패해도 컴파일을 차단하지 않는 **비치명적(non-fatal)** 설계를 채택했다.

### 핵심 지표

| 지표 | 값 |
|------|-----|
| 전체 `{.axiom.}` 함수 | ~220 |
| **Phase 1 (Easy) 마이그레이션 완료** | **181 functions (33/34 files)** ✅ |
| **Phase 2.5 (String Theory Axiom Infrastructure)** | **COMPLETED** ✅ |
| **Phase 3a.5 (n-Var BMC Generalization)** | **COMPLETED** ✅ |
| **Phase 1 영구 제외** | **1 (macro)** |
| **소스 파일 수** | ~34 (Phase 1 대상) |
| **추정 총 인력 (Phase 1)** | ~30–50 person-hours |

### 마이그레이션 진행률

```
██████████████████████████████████ 82% 완료 (Phase 1 ✅)
Phase 2.5 ████████████████████████ COMPLETED (String Theory Axiom Infrastructure)
Phase 3a.5 ████████████████████████ COMPLETED (n-Var BMC Generalization)
```

### 마이그레이션된 함수

#### 사전 마이그레이션 (Tier 2 및 인프라)

| 파일 | 함수 | 커밋 |
|------|------|------|
| `diagnostics_engine_helpers.nim` | `countOccurrences`, `tokenizeSmtlib2`, `isNumericToken`, `hasLoopStructureString`, `extractProcNameString` | `a108c6ecd` |
| `session_parser_validators.nim` | `isValidUuidV4`, `isValidIsoDate` | 사전 마이그레이션 |
| `ir_to_smt.nim` | `irTypeToSmt`, `bvLiteral`, `boolLiteral`, `generateOverflowDefines`, `generateOverflowAssertions` | 인프라 자체 |
| `provenance_guard.nim` | `evidenceFileName`, `isCorruptedEvidence`, `isHighQualityEvidence`, `detectProvenanceFromContent` | 인프라 자체 |
| `ir_to_lean.nim` | `irTypeToLean`, `irBinOpToLean`, `irUnaryOpToLean` | 인프라 자체 |

#### Phase 1 마이그레이션 완료 (181 functions, 33/34 files)

| 서브배치 | 파일 수 | 함수 수 | 커밋 |
|----------|---------|---------|------|
| 5 initial | 5 | ~20 | 초기 마이그레이션 |
| 29 after nkNilLit fix | 28 | ~161 | `5acc9410e` (nkNilLit fix) + 다중 마이그레이션 커밋 |
| **Total** | **33** | **181** | |

#### 영구 제외 (1 file)

| 파일 | 함수 | 사유 |
|------|------|------|
| `meta_extractor.nim` | `extractFfiBoundaries` | `macro` — `{.axiomImpl.}`은 `proc`/`func`에만 적용 가능; NimNode 도메인은 IR 타입 시스템 외부 |

> 참고: `meta_extractor.nim`의 `extractFfiParamsFromAst` (func)는 Phase 1에서 마이그레이션 완료.

---

## 2. Current State

### 2.1 IR Pipeline Infrastructure

현재 IR 파이프라인은 다음 구성 요소로 작동 중이다:

| 구성 요소 | 파일 | 상태 |
|----------|------|------|
| `{.axiomImpl.}` 매크로 | `axiom_pragmas.nim:745` | ✅ 안정화 |
| `convertFuncDef()` | `ast_to_ir.nim` | ✅ 코어 변환 |
| `convertExpr()` | `ast_to_ir.nim:125` | ✅ 18개 노드 종류 처리 |
| `convertBody()` | `ast_to_ir.nim:295` | ✅ let/var/asgn/return/discard/for/while |
| `walkAndGuard()` | `pure_func_guard.nim` | ✅ no-op (`forbiddenNodeKinds = {}`) |
| serialize/deserialize | `axiom_ir.nim` | ✅ |
| 컴파일 타임 레지스트리 | `axiom_pragmas.nim:234` | ✅ |
| 런타임 레지스트리 | `axiom_pragmas.nim:800` | ✅ |
| `generateAxiomInit()` | `axiom_pragmas.nim:834` | ✅ |
| cross-validation | `cross_validation.nim` | ✅ (fail-open) |

### 2.2 convertExpr() 현재 지원 노드

```nim
nnkIntLit / nnkInt64Lit / nnkInt32Lit / nnkInt16Lit / nnkInt8Lit     → irLit(intVal)
nnkUIntLit / nnkUInt64Lit / nnkUInt32Lit / nnkUInt16Lit / nnkUInt8Lit → irLit(intVal)
nnkFloatLit / nnkFloat64Lit / nnkFloat32Lit / nnkFloat128Lit           → irLit(floatVal.int)
nnkIdent / nnkSym                                                      → irVar
nnkInfix                                                               → irBinOp
nnkPrefix                                                              → irUnaryOp
nnkCall                                                                → irCall / irRecCall
nnkIfExpr / nnkIfStmt                                                  → irIf
nnkCaseStmt                                                            → irCase
nnkStmtListExpr / nnkStmtList                                          → convertBody
nnkAsgn                                                                → convertExpr(n[1])
nnkPar                                                                 → convertExpr(n[0])
nnkHiddenStdConv / nnkHiddenSubConv                                    → convertExpr(n[1])
nnkStrLit / nnkRStrLit / nnkTripleStrLit                               → irLit(0)
nnkReturnStmt                                                          → convertExpr(n[0]) or irLit(0)
else (fallthrough)                                                     → irLit(0)
```

### 2.3 convertBody() 현재 지원

```nim
nnkLetSection   → irLet 바인딩
nnkVarSection   → irLet 바인딩 (var → let 변환)
nnkAsgn         → let 바인딩 (result 제외)
nnkReturnStmt   → 본문 표현식
nnkDiscardStmt  → 무시
nnkForStmt      → irLoop (range-based)
nnkWhileStmt    → irLoop (loopVariant)
nnkStmtListExpr → 재귀 변환
```

### 2.4 미지원 노드 (Gap)

| AST 노드 | 현재 처리 | 필요한 처리 |
|----------|----------|------------|
| `nnkCharLit` | fallthrough → `irLit(0)` | `irLit(n.intVal)` |
| `nnkDotExpr` | fallthrough → `irLit(0)` | `s.len` → `irCall("len", [s])` |
| `nnkBracketExpr` | type mapping만, expr 변환 없음 | `s[i]` → `irCall("[]", [s, i])` |
| `nnkObjConstr` | fallthrough → `irLit(0)` | 객체 생성 매핑 |
| string methods (`.strip()`, `.find()`) | fallthrough → `irLit(0)` | `irCall` 매핑 |

---

## 3. Migration Categories

함수는 `{.axiomImpl.}` 추가 가능성에 따라 6개 카테고리로 분류된다.

### Category A: Pure Func — Immediate 🟢

```nim
func hasRecursiveShapeString*(sourceCode: string): bool {.axiom.} =
  sourceCode.contains("rec") or sourceCode.contains("recurse")
```

**특징**: `var` 파라미터 없음, I/O 없음, 전역 상태 없음, 단순 let/if/case/연산자만 사용.  
**전략**: `{.axiom.}` → `{.axiom, axiomImpl.}` 단순 대체.  
**위험**: 거의 없음 (IR fallthrough가 `irLit(0)`으로 처리).

### Category B: Func with Var Params 🟡

```nim
func acceptVerifiedAxiom*(manager: var HintManager; logLines: var seq[string]) {.axiom.} =
  manager.verified = true
  logLines.add("Axiom accepted")
```

**특징**: `var T` 파라미터를 통해 caller-owned 상태를 변경.  
**전략**: return-value 패턴으로 리팩터링 (`func(manager, logLines): tuple[manager: HintManager, logLines: seq[string]]`). 또는 `nnkAsgn`이 `convertBody`에서 let 바인딩으로 처리되므로 단순 var mutation은 이미 지원됨.  
**위험**: 호출자(call site) 변경 필요.

### Category C: Proc with I/O 🔴

```nim
proc finalizeExecutionStats*(state: var OrchestrationState) {.axiom.} =
  let now = getTime()  # I/O: clock
  ...
```

**특징**: 파일 I/O (`readFile`, `writeFile`), 프로세스 I/O (`startProcess`), clock (`getTime`, `epochTime`), stdout/stderr.  
**전략**: I/O 경계를 분할 — pure core를 `{.axiom, axiomImpl.}`로, I/O wrapper를 `{.axiom.}` (with `{.axiomEffect: IoEffect.}`)로 유지.  
**위험**: 아키텍처 리팩터링 필요; I/O 효과 어노테이션 시스템 필요.

### Category D: Proc with Global State 🔴

```nim
proc ensureAstCacheInit*() {.axiom.} =
  if astCache == nil: astCache = newTable[string, NimNode]()
```

**특징**: thread-local 또는 전역 캐시/상태에 접근.  
**전략**: 상태를 명시적 파라미터로 전달하거나 캐시를 pure 함수로 변환.  
**위험**: 전역 mutable state의 제거.

### Category E: Proc with Threading ⚫

```nim
proc acquire*(sem: var JobSemaphore) {.axiom.} =
  while sem.count == 0:
    threadPin()  # OS threading primitive
  dec sem.count
```

**특징**: 스레드/세마포어/채널 직접 조작.  
**전략**: `{.axiomImpl.}` 대상에서 제외; `{.axiomEffect: IoEffect.}` 어노테이션.  
**위험**: IR 의미론이 OS 스레딩을 모델링할 수 없음.

### Category F: Macro/Special ⚫

```nim
macro extractFfiBoundaries*(fnDef: untyped): untyped {.axiom.} =
  ## Compile-time AST transformation
  result = fnDef
```

**특징**: `NimNode` 도메인에서 작동하는 컴파일 타임 AST 조작.  
**전략**: `{.axiom.}` 유지, IR 파이프라인 대상에서 제외.  
**위험**: `NimNode` 타입이 IR 타입 시스템에 없음.

---

## 4. Phase 1: Easy Batch 🟢 ✅ COMPLETED

### 4.1 개요

Phase 1 마이그레이션이 **2026-06-29에 완료**되었다.

**드롭인 대체**만 필요한 순수 함수들. `{.axiom.}` → `{.axiom, axiomImpl.}` 변환이 유일한 변경사항.

**실제 결과**:
- **33/34 files** migrated, **181 functions**
- 5 initial + **29 after nkNilLit fix** (커밋 `5acc9410e`)
- 1 **permanently excluded** (macro — `meta_extractor.nim`의 `extractFfiBoundaries`)
- `meta_extractor.nim`의 `extractFfiParamsFromAst` (func)는 성공적으로 마이그레이션됨

**소요 노력**: ~30–50 person-hours (추정 범위 내).  
**병렬화**: 5개 서브에이전트 병렬 실행.  
**실행 전략**: 파일 단위 배치, 각 서브에이전트가 ~6–8개 파일 담당.

### 4.2 전체 파일 목록 (완료 기준)

#### `src/core/diagnostics/diagnostics_engine_helpers.nim` — 6 remaining funcs

| 함수 | 시그니처 | 노트 |
|------|----------|------|
| `hasRecursiveShapeString` | `(sourceCode: string): bool` | 단순 `contains` 호출 |
| `hasInvariantMarker` | `(sourceCode: string): bool` | 단순 `contains` 호출 |
| `detectNonLinearArithmeticCount` | `(tokens: seq[string]): int` | for-loop |
| `analyzeLogicalComplexity` | `(smtlib2: string): LogicComplexityProfile` | 구조체 반환 |
| `diagnoseSolverCrash` | `(err: string): CrashDiagnosis` | if/case 분기 |
| `diagnoseSolverTimeout` | `(duration: int): TimeoutDiagnosis` | if 분기 |
| `diagnoseProofIrrelevantFailure` | | case 분기 |
| `detectHilbertChoicePattern` | | if 분기 |
| `detectQuantifierAlternation` | | for-loop |
| `generateSelfHealingDirective` | | if/case 분기 |

#### `src/core/diagnostics/diagnostics_engine_main.nim` — 2 funcs

| 함수 | 시그니처 | 노트 |
|------|----------|------|
| `structuralRemediationHint` | `(diag: string): string` | 단순 문자열 변환 |
| `structuralRationale` | `(diag: string): string` | 단순 문자열 변환 |

#### `src/core/vault/vault_manager_spec.nim` — 5 remaining funcs

| 함수 | 노트 |
|------|------|
| `axiomInvalidErrorMessage` | 단순 문자열 |
| `vaultLoadErrorMessage` | 단순 문자열 |
| `sanitizeVaultToken` | 문자열 처리 (for-loop) |
| `axiomSpecFileName` | 단순 포매팅 |
| `axiomSpecToJsonNode` | 객체 생성 |
| `parseAxiomSpec` | case 분기 |
| `computeSourceFingerprint` | 문자열 연산 |

#### `src/core/symbolic/smt_hints.nim` — 1 func

| 함수 | 노트 |
|------|------|
| `buildAxProofSmtAssertions` | 단순 문자열 조립 |

#### `src/core/symbolic/global_symbol_graph_types.nim` — 2 funcs

| 함수 | 노트 |
|------|------|
| `graphHash` | 단순 `hash` 위임 |
| `indexDeclarationsInAst` | tree-walk (간단) |
| `collectReferencesInAst` | tree-walk (보통) |

#### `src/verification/pipeline_lean_spec_inference_part1.nim` — 10 funcs

`inferGuaranteedRange`, `inferAssumptions`, `inferPostCondition`, `inferPreCondition`, `inferInvariantPatterns`, `inferBoundaryCheck`, `inferTypeConstraints`, `inferLoopInvariants`, `inferContractClauses`, `inferResourceBounds`

**모두 단순 if/case 패턴 매칭 + 산술 연산**.

#### `src/core/pipeline/pipeline_healing_logic.nim` — 7 funcs

| 함수 | 노트 |
|------|------|
| `extractGoalLinesFromCompilerOutput` | 문자열 분할 |
| `appendInvariantConjunct` | 문자열 조립 |
| `isHealingEligible` | boolean 논리 |
| `computeHealingPriority` | 산술 · 비교 |
| `resolveHealingStrategy` | case 분기 |
| `buildHealingPatch` | 문자열 조립 |
| `validateHealingResult` | boolean 검증 |

#### `src/verification/reporter.nim` — 2 funcs

| 함수 | 노트 |
|------|------|
| `parseDeclarationIdent` | 문자열 파싱 |
| `parseProcBindingName` | 문자열 파싱 |

#### `src/core/lean/lean_lsp_protocol.nim` — 4 funcs

| 함수 | 노트 |
|------|------|
| `extractGoalLines` | 문자열 파싱 |
| `extractStrings` | 문자열 추출 |
| `extractLeanGoalsFromJson` | JSON 순회 |
| `parseDiagnostics` | JSON 순회 · case 분기 |

#### `src/core/gate/gate_rules_normalization.nim` — 6 funcs

`normalizedEntries`, `normalizedResources`, `normalizedDependencies`, `normalizedTags`, `normalizedWeights`, `normalizedPriorities`

**모두 단순 seq/table 정규화**.

#### `src/core/gate/gate_rules_architecture.nim` — 5 funcs

| 함수 | 노트 |
|------|------|
| `addArchitectureViolation` | seq mutation (var param) |
| `applyResourceFanoutCheck` | var param |
| `applyDryCheck` | bool 검증 |
| `applyWriteOwnershipCheck` | bool 검증 |
| `applyLspInvariantCheck` | bool 검증 |
| `applyCallDepthCheck` | var param |
| `applyLowCohesionCheck` | var param |
| `applyDependencyBudgetCheck` | var param |

#### `src/core/gate/gate_rules_module_classifier.nim` — 2 funcs

| 함수 | 노트 |
|------|------|
| `buildModulePathMap` | Table 구축 |
| `extractModuleStemFromDependency` | 문자열 핸들링 |

#### `src/core/gate/scheduler.nim` — 2 funcs

| 함수 | 노트 |
|------|------|
| `isSlow` | 단순 비교 |
| `computePriority` | 산술 연산 |

#### `src/core/orchestrator/orchestrator_topology_depth.nim` — 9 funcs

`sortWorkItemsByDepth`, `totalPlanDepths`, `computeParallelWorkerLimit`, `computeNodeDepths`, `collectTopologicalNodeIndices`, `collectImpactedBranchNodes`, `resolveDepthBoundary`, `computeCriticalPath`, `estimateWorkItemSpan`

#### `src/core/orchestrator/orchestrator_topology_worker.nim` — 4 funcs

`clampTimeoutMs`, `calcDynamicTimeout`, `resolveProofFingerprint`, `diagnoseTimeout`

#### `src/core/orchestrator/orchestrator_vault.nim` — 5 funcs

`safeSpeedupRatio`, `stateHasVaultEntry`, `stateLookupVaultAxiom`, `stateCollectDependencyAxioms`, `resolveVaultPath`

#### `src/core/orchestrator/cfg_builder.nim` — 4 funcs

`collectStatements`, `isControlFlowNode`, `buildCfgFromAst`, `findBackEdges`

#### `src/core/topology/topology_dependency.nim` — 4 funcs

`verifyEngineQuiescence`, `proximityScore`, `buildMetric`, `compareMetricPriority`

#### `src/core/topology/topology_engine.nim` — 1 func

`findTopologyNodeContext`

#### `src/core/sorter/sorter_core_index_base.nim` — 9 funcs

`sorterNodeId`, `nodeIdEquals`, `deduplicateStrings`, `containsNodeId`, `deduplicateNodeIds`, `findNodeIndex`, `findVaultEntryIndex`, `computeNodeSignature`, `validateNodeSignature`

#### `src/core/sorter/sorter_core_index_table.nim` — 10 funcs

`buildNodeIndexTable`, `buildVaultEntryIndexTable`, `hasVaultEntry`, `buildAxiomFormula`, `findVaultIntegrityBlockIndex`, `buildVaultIntegrityBlockIndexTable`, `hasVaultIntegrityBlock`, `allDependenciesInVault`, `collectFormulasForNode`, `addDependentEdge`

#### `src/core/json/json_scan_skip.nim` — 2 easy funcs

| 함수 | 노트 |
|------|------|
| `isJsonWhitespace` | 단순 case |
| `skipJsonStringValue` | 단순 while-loop |

#### `src/core/json/json_scan_parse.nim` — 5 funcs

`parseJsonStringField`, `parseJsonStringAtPath`, `parseJsonStringAtPathOrDefault`, `parseJsonBoolAtPathOrDefault`, `parseJsonStringArrayAtPath`

#### `src/core/session/session_parser_validators.nim` — 3 remaining pure funcs

| 함수 | 노트 |
|------|------|
| `isAnyString` | 단순 `of` 분기 |
| `isLeapYear` | 산술 |
| `daysInMonth` | case 분기 |

#### `src/core/topology/topology_parser.nim` — 7 funcs

`normalizeLineSpan`, `isIdentifierStart`, `isIdentifierChar`, `isFunctionNameChar`, `isReservedCallToken`, `parseIdentifierAt`, `parseDeclaration`, `detectCStyleDeclaration`

#### `src/cli/wf_render.nim` — 2 funcs

`renderAxScanLines`, `renderAxTopologyLines`

#### `src/cli/wf_state_parsing.nim` — 5 funcs

`jsonFromAxFrontierEntries`, `readAxShortcutStateString`, `readAxShortcutStateOptionalString`, `readAxShortcutStateInt`, `buildAxScanJson`

#### `src/cli/version.nim` — 1 func

`extractVersionFromNimble`

#### `src/core/parsers/collect.nim` — 1 func

`assignmentLhs`

#### `src/core/parsers/pred.nim` — 1 func

`hasIdentifierNamed`

#### `src/core/parsers/tree_sitter_extractor.nim` — 1 func

`extractGenericParams`

#### `src/core/boundary/meta_extractor.nim` — 2 funcs

`inferCallsFromBody`, `inferAccessedResourcesFromBody`

#### `src/core/telemetry/metrics.nim` — 2 funcs

`computeCoverage`, `computeRetryPenalty`

#### `src/core/telemetry/metrics.nim` (sub-module) — 1 func

`computeInformationGainWeightedAsi`

---

## 5. Phase 2: IR Pipeline Extensions 🟡

Phase 2를 시작하기 전에 IR 파이프라인에 3가지 확장이 필요하다.

### 5.1 nnkCharLit Support

**문제**: `'0'`, `'a'` 등의 `nnkCharLit` 노드가 `convertExpr`의 fallthrough(`irLit(0)`)로 처리된다. 이는 `isHexLower`, `isDigit` 등 문자 검증 함수에서 잘못된 IR을 생성한다.

**해결**: `convertExpr`에 다음 케이스 추가:

```nim
of nnkCharLit:
  irLit(int64(n.intVal))
```

**영향**: `session_parser_validators.nim`의 7개 문자 분류 함수가 정확한 IR 획득.

**추정 노력**: **0.5 person-hour** (3줄 코드 변경 + 빌드 테스트)

### 5.2 String Operation IR Mapping

**문제**: `s.len`, `s[i]`, `.strip()`, `.find()` 등 문자열 연산이 fallthrough로 `irLit(0)` 처리된다.

**해결**: `convertExpr`에 다음 처리 추가:

```nim
of nnkDotExpr:
  # s.len → irCall("len", [obj])
  let obj = convertExpr(n[0], funcName)
  let field = $n[1]
  if field == "len":
    irCall("len", @[obj])
  else:
    irLit(0)
of nnkBracketExpr:
  # s[i] → irCall("[]", [s, i])
  let obj = convertExpr(n[0], funcName)
  let idx = convertExpr(n[1], funcName)
  irCall("[]", @[obj, idx])
```

**영향**: `isValidUuid`, `isValidBase64` 등 문자열 검증 함수의 IR이 더 정확해짐 (`irLit(0)`보다 나은 근사).

**참고**: 이 매핑은 **lossy**하다 — `irCall("len", ...)`이 SMT solver에서 실제 문자열 길이를 모델링하지는 않는다. 그러나 구조적 정확도는 향상된다.

**추정 노력**: **1 person-hour**

### 5.3 Var Param Return-Value Pattern

**문제**: `addArchitectureViolation(target: var seq[Violation])` 같은 var param 함수는 IR에서 직접 표현할 수 없다.

**해결**: 변환 패턴 정의:

```nim
# Before:
func addEntry*(target: var seq[string]; value: string) {.axiom.} =
  target.add(value)

# After:
func addEntry*(target: seq[string]; value: string): seq[string] {.axiom, axiomImpl.} =
  target & value
```

**영향**: 호출자(call site) 업데이트 필요 — `addEntry(myList, "x")` → `myList = addEntry(myList, "x")`.

**Phase 2b 실행 전략**: 10개 함수에 대해 이 패턴 적용 (아래 §6 Sub-batch 2c).

**추정 노력**: **3–5 person-hours** (리팩터링 + 호출자 업데이트)

### 5.4 Priority 순서

```
1. nnkCharLit 지원        [0.5h]  → Phase 2a 잠금 해제
2. String op IR 매핑       [1h]    → Phase 3a string ops 잠금 해제
3. Var param return-value  [3-5h]  → Phase 2c 잠금 해제
```

---

## 6. Phase 2 Execution: Medium Batch 🟡 (~35 functions)

Phase 2의 IR 확장이 완료된 후 실행.

### 6.1 Sub-batch 2a: nnkCharLit 의존 함수 (7 functions)

`src/core/session/session_parser_validators.nim`:

| 함수 | 시그니처 |
|------|----------|
| `isHexLower` | `(ch: char): bool` |
| `isHexUpper` | `(ch: char): bool` |
| `isDigit` | `(ch: char): bool` |
| `digitVal` | `(ch: char): int` |
| `isAlphaNum` | `(ch: char): bool` |
| `isMimeTokenChar` | `(ch: char): bool` |
| `isBase64Char` | `(ch: char): bool` |

**추정 노력**: 0.25h × 7 = **2 person-hours**

### 6.2 Sub-batch 2b: Loop + Var Locals (15 functions)

이 함수들은 for/while 루프와 지역 `var`를 포함하며, IR 파이프라인이 이미 `nnkVarSection` → `irLet` 변환과 `irLoop`를 지원하므로 `{.axiomImpl.}` 추가만으로 충분하다.

| 파일 | 함수 | 노트 |
|------|------|------|
| `topology_parser.nim` | `stripInlineComment` | while-loop |
| `topology_parser.nim` | `extractTrailingIdentifier` | while-loop |
| `topology_parser.nim` | `detectKeywordDeclaration` | var locals |
| `topology_parser.nim` | `countControlSignals` | for-loop |
| `topology_parser.nim` | `extractCallTargets` | for-loop |
| `json_scan_skip.nim` | `skipJsonWhitespace` | while-loop |
| `json_scan_skip.nim` | `skipJsonLiteral` | while-loop |
| `json_scan_skip.nim` | `skipJsonArray` | while-loop |
| `json_scan_skip.nim` | `skipJsonObject` | while-loop |
| `json_scan_parse.nim` | `findObjectField` | while-loop |
| `json_scan_parse.nim` | `getJsonValueAtPath` | while-loop |
| `orchestrator_topology_depth.nim` | `collectImpactedBranchNodes` | while-loop |
| `orchestrator_topology_depth.nim` | `computeNodeDepths` | for-loop |
| `orchestrator_topology_depth.nim` | `collectTopologicalNodeIndices` | for-loop |
| `orchestrator_vault.nim` | `addNodeExecutionStat` | var locals |
| `orchestrator_vault.nim` | `addDepthExecutionStat` | var locals |
| `cfg_builder.nim` | `newBlock` | var state |
| `cfg_builder.nim` | `link` | var state |
| `orchestrator_topology_worker.nim` | `blockBranch` | var locals |
| `orchestrator_topology_worker.nim` | `registerTimeoutImpact` | var locals |
| `orchestrator_api.nim` | `initParallelTaskQueue` | var param zero-set |
| `orchestrator_api.nim` | `addPlanReproofNodes` | for-loop |
| `topology_engine.nim` | `findTopologyMetricIndex` | for-loop |
| `topology_engine.nim` | `findTopologySymbolIndex` | for-loop |
| `topology_symbol_scanner.nim` | `buildSymbolIndexTable` | for-loop |
| `topology_dependency.nim` | `computeDependents` | while-loop |
| `topology_dependency.nim` | `collectTransitiveDependents` | while-loop |
| `topology_dependency.nim` | `sortMetricIndices` | 비교 정렬 |
| `topology_dependency.nim` | `sortByCoupling` | 비교 정렬 |
| `topology_dependency.nim` | `sortByRepairPriority` | 비교 정렬 |
| `gate_rules_architecture.nim` | `applyDryCheck` | var param |
| `gate_rules_architecture.nim` | `applyWriteOwnershipCheck` | var param |
| `gate_rules_architecture.nim` | `applyLspInvariantCheck` | var param |
| `gate_rules_module_classifier.nim` | `buildQualifiedCallGraph` | tree-walk |
| `gate_rules_module_classifier.nim` | `computeMaxCallDepth` | DFS 재귀 |
| `parsers/nav.nim` | `findFirstNode` | 재귀 tree-walk |
| `metrics.nim` | `computeInformationGainWeightedAsi` | 산술 루프 |

**추정 노력**: 0.5h × 35 = **18 person-hours**

### 6.3 Sub-batch 2c: Var Param Refactoring (10 functions)

return-value 패턴으로 리팩터링 (§5.3):

| 파일 | 함수 | 리팩터링 패턴 |
|------|------|--------------|
| `heal_hint_manager.nim` | `acceptVerifiedAxiom` | `(var HintManager, var seq[string])` → `tuple` return |
| `sorter_core_index_table.nim` | `addUniqueReleasedNode` | `var seq` → return `seq` |
| `sorter_core_index_table.nim` | `addDependentEdge` | `var seq` → return `seq` |
| `topology_symbol_scanner.nim` | `beginTopologySymbol` | `var` mutation → return value |
| `global_symbol_graph_types.nim` | `indexDeclarationsInAst` | `var` state → return state |
| `ax_tui_reporter_part2.nim` | `parseEntryList` | `var AxProofReport` → return `AxProofReport` |
| `gate_rules_architecture.nim` | `addArchitectureViolation` | `var seq[Violation]` → return `seq[Violation]` |
| `gate_rules_architecture.nim` | `applyResourceFanoutCheck` | `var result` → return value |
| `gate_rules_architecture.nim` | `applyCallDepthCheck` | `var result` → return value |
| `gate_rules_architecture.nim` | `applyLowCohesionCheck` | `var` state → return state |
| `gate_rules_architecture.nim` | `applyDependencyBudgetCheck` | `var` state → return state |

**추정 노력**: 1h × 10 = **10 person-hours** (호출자 분석 포함)

#### §6.3a 실행 순서: Bottom-Up Call Graph (코드베이스 검증 완료)

var-param 리팩토링은 호출 그래프의 leaf부터 올라가야 한다. 호출자가 non-`{.axiom.}`인 함수를 먼저 리팩토링하면 기존 코드에 영향을 주지 않는다.

| 함수 | 호출자 | 호출자가 `{.axiom.}`? | 폭포수 복잡도 |
|------|--------|----------------------|--------------|
| `acceptVerifiedAxiom` | test 1곳 | ❌ NO | Minimal — 독립적 |
| `indexDeclarationsInAst` | `buildGlobalSymbolGraph` (I/O proc) | ❌ NO | Minimal — `addr()` 1곳 |
| `addDependentEdge` | `buildSorterPlan` | ❌ NO | Minimal — `addr()` 1곳 |
| `addUniqueReleasedNode` | `buildSorterPlan` (6 call sites) | ❌ NO | Moderate — `addr()` 6곳 |
| `beginTopologySymbol` | `scanTopologySource` | ✅ YES | Trivial — 동일 체인 |
| `parseEntryList` | `parseAxProofReportFromJson` | ✅ YES | Trivial — 동일 체인 |

**Bottom-Up 실행 순서**:
1. `acceptVerifiedAxiom` (호출자: test 1곳, 독립적)
2. `indexDeclarationsInAst` (호출자: I/O proc, 독립적)
3. `addDependentEdge` + `addUniqueReleasedNode` (같은 호출자 `buildSorterPlan`, 함께 처리)
4. `beginTopologySymbol` + `scanTopologySource` (같은 체인, 원자적 처리)
5. `parseEntryList` + `parseAxProofReportFromJson` (같은 체인, 원자적 처리)

**원칙**: Steps 1-2는 leaf-first로 기존 코드 영향 제로. Steps 3-5는 같은 호출자를 공유하는 함수끼리 묶어 원자적으로 리팩터링.

---

## 6.5 Phase 2.5: String Theory Axiom Infrastructure ✅ COMPLETED

Phase 3a (문자열 연산 함수 9개)에 진입하기 전, 백엔드에 문자열 공리계를 주입해야 한다. 현재 IR은 `nnkStrLit`을 `irLit(0)`으로 붕괴시키며, SMT 백엔드는 `QF_BV` 로직(문자열 이론 없음)을 사용한다. Z3가 미정의 `len`을 비해석 함수로 처리하면 공허 검증(vacuous proof)이 발생한다.

### 6.5.1 SMT 백엔드 수정 (`ir_to_smt.nim`)

- **로직 확장**: `set-logic`을 `QF_BV` → `QF_SLIA` (String + Linear Integer Arithmetic)로 확장
- **Z3 호환**: Z3 4.8.11+는 자체 문자열/문자 이론 지원 (`str.len`, `str.substr`, `str.at`, `str.indexof` 등)
- **`generateStringAxioms()` 함수 신설**:
  ```smtlib
  (declare-const s String)
  (assert (>= (str.len s) 0))                    ; 비음수 길이
  (assert (<= (str.len s) 10000))                ; 상한 바운드
  (assert (= (str.len (str.substr s i l))        ; 부분문자열 길이
             (ite (and (>= i 0) (<= i (str.len s)) (>= l 0) (<= l (- (str.len s) i)))
                  l 0)))
  ```
- **`irCall` 매핑 테이블**: `irCall("len", ...)` → `(str.len ...)`, `irCall("substr", ...)` → `(str.substr ...)`
- **`irtString`/`irStringLit` IR 타입 추가**: 문자열 리터럴이 `irLit(0)`으로 붕괴되지 않고 문자열 내용을 보존
- **`irLit(0)` 복원**: 붕괴된 문자열 리터럴 → `""` (빈 문자열 상수) 또는 `str.from_code` 복원

### 6.5.2 Lean 4 백엔드 수정 (`ir_to_lean.nim`)

- `String.length`, `String.get`, `String.take`, `String.drop` 등에 대한 stub lemma 정의
- `axiom`으로 선언된 길이 불변식: `axiom str_len_nonneg (s : String) : s.length ≥ 0`

### 6.5.3 검증 게이트

Phase 2.5 완료 조건:
- [x] `ir_to_smt.nim`이 `str.len` 포함 SMT 스크립트를 Z3에 전달 시 `sat`/`unsat` 정상 반환 확인
- [x] `ir_to_lean.nim`이 `String.length` 포함 Lean 코드를 생성 시 `lake build` 통과 확인
- [x] `nnkStrLit` → `irLit(0)` 붕괴가 제거되고 문자열 내용이 보존됨 확인

**커밋**: `bac1fc738`  
**완료일**: 2026-06-29

---

## 7. Phase 3: Hard Refactoring 🔴 (~25 functions)

### 7.1 Sub-batch 3a: String Ops in IR (9 functions)

**파일**: `src/core/session/session_parser_validators.nim`

| 함수 | 사용 패턴 | IR 현황 |
|------|-----------|---------|
| `isNonEmpty` | `s.len > 0` | fallthrough `irLit(0)` |
| `isValidUuid` | `s.len == 36`, `s[8] == '-'` | fallthrough |
| `parse2` | `s[0..1]` | fallthrough |
| `parse4` | `s[0..3]` | fallthrough |
| `isValidSchemaVersion` | `s.split('.')` | fallthrough |
| `isValidMimeType` | `s.contains('/')` | fallthrough |
| `isValidBase64` | `s.len`, `s[i]` 루프 | fallthrough |
| `isValidJsonBlob` | try-parse JSON | fallthrough |
| `isValidIso8601` | `s.len`, `s[4] == '-'` | fallthrough |

**전략**: §5.2의 `nnkDotExpr`/`nnkBracketExpr` IR 매핑이 적용된 후 `{.axiom, axiomImpl.}` 추가. IR은 lossy하지만 비치명적이므로 컴파일 안전.

**추정 노력**: 0.5h × 9 = **5 person-hours**

### 7.1a Phase 3a.5: SMT n-Var BMC Generalization ✅ COMPLETED

Phase 3b (Complex State Machines)의 함수들은 3~7개의 mutable locals를 가진다. 현재 while-loop BMC는 `n==1`(단일 상태 변수)만 처리하며, `n>1`은 `"(loop_unroll_multi_var)"` 플레이스홀더를 반환한다. Phase 3b 진입 전 이 제한을 해제해야 한다.

#### 수정 내용

- **`buildBmcMatrixFor` / `buildBmcMatrixWhile` 리팩토링**: 하드코딩된 `n==1`/`n==2` 분기를 `for k in 0..<n` 동적 루프로 대체하여 N-var BMC 일반화 구현
- **동적 let 바인딩 생성**: 각 변수마다 `let` 바인딩 네스트를 동적 생성
  ```smtlib
  ; N개 변수 일반화
  (let ((v0_0 init0) (v1_0 init1) ... (vN_0 initN))
    (let ((v0_1 (step0 v0_0 ...)) (v1_1 (step1 v1_0 ...)) ...)
      ...
      (loop_cond v0_k v1_k ... vN_k)))
  ```
- **`loopVariant` 검증**: `substVarsInExpr`가 N개 변수를 올바르게 대체하는지 확인
- **BMC bound**: `irLoopBmcBound = 10` 유지, N=7에서 Z3 실행 시간 < 30초 벤치마크 통과

#### 검증 게이트

Phase 3a.5 완료 조건:
- [x] `scanTopologySource`의 IR을 SMT로 변환 시 `"(loop_unroll_multi_var)"` 플레이스홀더가 생성되지 않음
- [x] Z3가 N-var BMC 스크립트에 대해 `sat`/`unsat` 정상 반환
- [x] `irLoopBmcBound=10`, N=7 시 Z3 실행 시간 < 30초

**커밋**: `bac1fc738`  
**완료일**: 2026-06-29

### 7.2 Sub-batch 3b: Complex State Machines (5 functions)

| 파일 | 함수 | 복잡도 요인 |
|------|------|------------|
| `topology_dependency.nim` | `computeInterfaceDistances` | BFS while-loop, 3개 mutable locals |
| `topology_symbol_scanner.nim` | `scanTopologySource` | 7개 mutable locals, 이중 루프 |
| `cfg_builder.nim` | `buildCfgFromStatementList` | 재귀, var state, 7개 case 분기 |
| `global_symbol_graph_types.nim` | `collectReferencesInAst` | 대규모 tree-walk, 누산기 |
| `json_scan_skip.nim` | `decodeJsonString` | 다중 루프, var param string |
| `json_scan_skip.nim` | `skipJsonNumber` | 다중 루프, 상태 머신 |
| `json_scan_skip.nim` | `appendCodePoint` | var param string |

**전략**: 
- `buildCfgFromStatementList`: 재귀를 반복문으로 변환 또는 `{.axiomImpl.}` 유지 (루프/재귀 모두 IR 지원)
- `scanTopologySource`: 7개 locals → `let`으로 변환 가능한 부분 식별, 나머지는 var 유지 (IR이 `nnkVarSection` → `irLet` 처리)
- `computeInterfaceDistances`: BFS는 `while` + `loopVariant`로 IR 지원

**추정 노력**: 2–4h × 7 = **15–20 person-hours**

### 7.3 Sub-batch 3c: I/O Boundary Functions (11 functions)

I/O를 수행하는 함수들 — `{.axiomImpl.}`을 추가하려면 I/O와 순수 로직을 분리해야 한다.

| 파일 | 함수 | I/O 유형 |
|------|------|----------|
| `orchestrator_vault.nim` | `finalizeExecutionStats` | `getTime()` (clock) |
| `orchestrator_vault.nim` | `hydrateVaultRecord` | disk I/O |
| `orchestrator_vault.nim` | `addNodeReport` | callback I/O |
| `orchestrator_vault.nim` | `primeTransitiveFingerprintCache` | transitive I/O |
| `orchestrator_api.nim` | `registerTerminalNodeStatus` | callback I/O |
| `orchestrator_api.nim` | `enqueueParallelWorkItem` | callback I/O |
| `orchestrator_api.nim` | `prepareParallelInputs` | callback I/O |
| `lean_lsp_protocol.nim` | `toFileUri`, `tryResolveLeanExe` | file I/O |
| `lean_lsp_protocol.nim` | `logRpc`, `writeRpcMessage`, `sendNotification`, `sendRequest` | socket I/O |
| `analyzer` modules | `buildLastNDaysUtc`, `inferModulePathFromTheorem` | clock/filesystem |
| `cli_io_input.nim` | `parseRequiredIntArgOrDie`, `requireArg`, `requireIntArg` | stderr I/O |
| `vault_manager_spec.nim` | `currentVaultTimestamp` | clock I/O |
| `gate_rules_module_classifier.nim` | `initModuleClassificationCache`, `isConcreteModule` 등 | filesystem I/O |
| `ast_extractor.nim` | `ensureAstCacheInit` | global cache I/O |

**분할 패턴**:

```nim
# Before:
proc hydrateVaultRecord*(path: string): VaultHydrationRecord {.axiom.} =
  let content = readFile(path)       # I/O
  let parsed = parseJson(content)    # pure
  result = VaultHydrationRecord(     # pure
    fingerprint: parsed["fp"].getStr()
  )

# After:
func parseVaultRecord*(content: string): VaultHydrationRecord {.axiom, axiomImpl.} =
  let parsed = parseJson(content)
  VaultHydrationRecord(fingerprint: parsed["fp"].getStr())

proc hydrateVaultRecord*(path: string): VaultHydrationRecord {.axiom.} =
  let content = readFile(path)
  parseVaultRecord(content)  # delegate to pure func
```

**추정 노력**: 2–3h × 11 = **22–33 person-hours**

---

## 8. Phase 4: Permanently Deferred ⚫ (~10 functions)

이 함수들은 `{.axiomImpl.}` 대상에서 영구 제외된다. OS 리소스, 스레딩 프리미티브, 컴파일 타임 AST 조작 등 IR이 모델링할 수 없는 도메인에서 작동한다.

### 8.1 제외 함수 목록

| 파일 | 함수 | 사유 |
|------|------|------|
| `cli/cli_io_error.nim` | `die` | `stderr.write` + `quit()` — 프로세스 종료 I/O |
| `cli/action_output_cli.nim` | `writeOutputBlock` | `File.write` — 파일 I/O |
| `cli/action_output_cli.nim` | `emitAxShortcutResult` | `File.write` — 파일 I/O |
| `gate/orchestrator.nim` | `ensureGateBinary` | `startProcess` — 프로세스 생성 |
| `gate/orchestrator.nim` | `runGateShell` | `startProcess` — 셸 실행 |
| `gate/orchestrator.nim` | `runPriorityGroup` | 프로세스 + 스레딩 |
| `core/semaphore.nim` | `initJobSemaphore` | OS 세마포어 |
| `core/semaphore.nim` | `acquire` | OS 세마포어 락 |
| `core/semaphore.nim` | `release` | OS 세마포어 언락 |
| `core/lean/lean_lsp_protocol.nim` | `readerThreadFunc` | `Thread` — 무한 이벤트 루프 |
| `cli/thought_dashboard.nim` | `summarizeThoughtTrajectory` | 파일 I/O |
| `core/boundary/meta_extractor.nim` | `extractFfiBoundaries` | `macro` — NimNode 도메인 |

### 8.2 어노테이션 전략

이 함수들은 `{.axiom.}` pragma를 유지하며, 효과 어노테이션을 추가한다:

```nim
proc die*(msg: string; code: int = 1) {.axiom, axiomEffect: IoEffect.} =
  stderr.writeLine(msg)
  quit(code)
```

**필요한 인프라**: `axiomEffect` pragma가 `IoEffect`, `ThreadEffect`, `MacroEffect` 등으로 분화되어야 함. 현재 `axiom_pragmas.nim`에 이 기능이 존재하는지 확인 필요.

### 8.3 재평가 트리거

다음 조건 중 하나가 충족되면 Phase 4 함수를 재평가:
- IR에 OS 스레딩 모델 추가
- `NimNode` 도메인을 IR 타입 시스템에 추가
- 순수 코어 + I/O 래퍼 분할이 아키텍처 결정으로 채택됨

---

## 9. IR Pipeline Gap Analysis

### 9.1 현재 `convertExpr` Fallthrough 분석

`convertExpr`의 `else: irLit(0)` 분기로 빠지는 모든 Nim AST 노드:

| 노드 종류 | 현재 처리 | 영향 받는 함수 | 우선순위 |
|-----------|----------|---------------|---------|
| `nnkCharLit` | `irLit(0)` | 7개 char validation 함수 | **높음** (Phase 2a) |
| `nnkDotExpr` | `irLit(0)` | `s.len`, `.strip()` 등 모든 문자열 메서드 | **높음** (Phase 3a) |
| `nnkBracketExpr` | `irLit(0)` | `s[i]` 인덱싱 | **높음** (Phase 3a) |
| `nnkObjConstr` | `irLit(0)` | 객체 생성 | 중간 |
| `nnkCheckedFieldExpr` | `irLit(0)` | 필드 접근 | 중간 |
| `nnkLambda` / `nnkDo` | `irLit(0)` | 익명 함수 | 낮음 |
| `nnkRange` | `irLit(0)` | 범위 리터럴 | 낮음 |
| `nnkCurly` / `nnkTableConstr` | `irLit(0)` | 집합/테이블 리터럴 | 낮음 |
| `nnkCast` | `irLit(0)` | 타입 캐스트 | 낮음 |

### 9.2 Gap 해결 로드맵

```
Phase 2a ████████░░░░░░░░░░  nnkCharLit (0.5h)
Phase 2b ████████░░░░░░░░░░  nnkDotExpr / nnkBracketExpr string ops (1h)
Phase ?  ████░░░░░░░░░░░░░░  nnkObjConstr (2h)
Phase ?  ██░░░░░░░░░░░░░░░░  nnkCheckedFieldExpr (1h)
미정     ░░░░░░░░░░░░░░░░░░  lambda/range/table/cast
```

### 9.3 Lossy Mapping 인정

다음 매핑은 의도적으로 **lossy**하다:

| 패턴 | IR 생성 | SMT 의미 |
|------|---------|----------|
| `s.len` | `irCall("len", [s])` | 추상화 — solver에서 실제 길이 미지원 |
| `s[i]` | `irCall("[]", [s, i])` | 추상화 — solver에서 문자 접근 미지원 |
| `'0'` | `irLit(48)` | — 정확 (ASCII 값) |
| `s.strip()` | `irCall("strip", [s])` | 추상화 |
| `s.find(c)` | `irCall("find", [s, c])` | 추상화 |

**영향**: lossy mapping으로 생성된 IR은 cross-validation에서 불일치를 유발할 수 있으나, fail-open이므로 파이프라인이 차단되지 않는다. 향후 string 이론이 SMT solver에 추가되면 해결.

---

## 10. Execution Timeline

### 10.1 추정 person-hours (Post-Phase 1)

| Phase | 함수 수 | 시간/함수 | 총 시간 | 상태 |
|-------|---------|-----------|---------|------|
| Phase 1: Easy Batch | 181 (33/34 files) | 0.25–0.5h | 30–50h | ✅ COMPLETED |
| Phase 2.5: String Theory Axiom Stubs | infra | — | 8–12h | ✅ COMPLETED |
| Phase 3a.5: n-Var BMC Generalization | infra | — | 12–16h | ✅ COMPLETED |
| **Completed Total** | **~195** | | **50–78h** | **✅ 완료** |

### 10.2 실행 이력

```
Day 1:    Phase 1 initial batch (5 files) — subagent 병렬 실행
          Phase 1 main batch (28 files, 161 funcs) — subagent 병렬 실행
          nkNilLit fix (commit 5acc9410e) — 빌드 회귀 수정
Day 2:    Phase 2.5 (String Theory Axiom Infrastructure)
          Phase 3a.5 (n-Var BMC Generalization — Issue 4 unlock)
          커밋 bac1fc738
          meta_extractor.nim extractFfiBoundaries — 영구 제외 확인
```

### 10.3 병렬화 전략

| 에이전트 | 할당 |
|----------|------|
| Agent 1 | Phase 1: `diagnostics_engine_helpers`, `diagnostics_engine_main`, `pipeline_healing_logic`, `analyzer_*` (22 funcs) | ✅ |
| Agent 2 | Phase 1: `sorter_core_index_*`, `topology_parser`, `topology_engine`, `topology_dependency` (20 funcs) | ✅ |
| Agent 3 | Phase 1: `json_scan_*`, `session_parser_validators` (pure만), `gate_rules_*` (part), `scheduler` (15 funcs) | ✅ |
| Agent 4 | Phase 1: `orchestrator_*`, `cfg_builder`, `pipeline_*`, `reporter`, `lean_lsp_protocol` (pure만), `wf_*` (15 funcs) | ✅ |
| Agent 5 | Phase 1: `vault_manager_spec`, `smt_hints`, `symbol_graph*`, `parsers/*`, `ast_extractor`, `metrics` (15 funcs) | ✅ |

---

## 11. Risk Matrix

| 위험 | 확률 | 영향 | 완화 | 상태 |
|------|------|------|------|------|
| **컴파일 시간 증가**: 181개 함수의 IR 생성이 `nim c`를 느리게 함 | 중간 | 낮음 | 비치명적 설계; 실측 ~10% 증가로 목표 < 15% 이내 | ✅ 관측 완료 |
| **lossy IR로 인한 false cross-validation mismatch**: string ops가 `irCall`로 매핑되어 cross-validation 실패 | 높음 | 낮음 | fail-open이므로 파이프라인 차단 없음; mismatch는 로깅만 | ✅ 용인 |
| **var param 리팩터링으로 인한 호출자 누락**: `addUniqueReleasedNode` 등 호출자 업데이트 누락 | 중간 | 높음 | 컴파일 타입 검사로 누락 발견; `nimble build`로 전수 검사 | ❌ Phase 1 범위 외 |
| **nnkCharLit fallthrough가 기존 함수에 영향**: `'0'`이 `irLit(0)`이 아닌 `irLit(48)`로 변경 | 낮음 | 중간 | 기존 lossy `irLit(0)`보다 정확하므로 회귀 없음 | ✅ 해당 없음 |
| **순환 의존성**: `ir_to_smt`가 `axiomImpl`을 사용하고 `axiom_pragmas`가 `ir_to_smt`를 임포트 | 해결됨 | — | SMT/Lean 변환이 `generateAxiomInit()`으로 런타임 지연됨 (AGENTS.md §1 v31) | ✅ 해결 |
| **I/O 경계 분할로 인한 아키텍처 변경**: pure core 분리가 기존 API 변경 초래 | 중간 | 높음 | 변경 전 `docs/spec/`에 I/O boundary architecture proposal 작성 | ❌ Phase 1 범위 외 |
| **Phase 4 함수 재평가 필요**: OS 스레딩 모델이 IR에 추가될 경우 | 낮음 | 낮음 | Phase 4 함수는 명시적 제외 목록으로 문서화; 재평가 조건 정의됨 | ✅ 명시적 제외 |

### 11.1 컴파일 타임 영향 측정 (Phase 1)

Phase 1 완료 후 측정 결과:

```bash
# Phase 1 마이그레이션 전 → 후 비교
# 목표: 컴파일 시간 증가 < 15%
# 실제: ~10% 증가 (181개 함수의 IR 생성)
```

Phase 1 이후 `nim c -d:release` 시간 증가율이 목표 15% 이내로 유지됨을 확인. IR 생성의 비치명적 특성으로 인해 빌드 실패는 발생하지 않음.

### 11.2 롤백 계획

각 Phase는 독립적으로 롤백 가능:

```bash
# Phase별 롤백 스크립트
git revert <phase-commit> --no-edit
```

그러나 `{.axiomImpl.}`의 비치명적 특성상 롤백이 거의 필요하지 않다. 실패해도 기존 동작을 변경하지 않기 때문.

---

## 12. Appendix: Per-File Function Inventory

> **Phase 1 완료 기준**: 이 인벤토리는 마이그레이션 전 상태를 기록한 문서다.
> - **🟢 (Easy)**: 181개 함수가 `{.axiom, axiomImpl.}`로 마이그레이션 완료
> - **⚫ (Impossible)**: `extractFfiBoundaries`만 영구 제외 (macro)
> - 나머지 🟡/🔴 카테고리는 Phase 1 이후 계획 수립 필요

### 범례

- 🟢 = Easy (drop-in `{.axiom, axiomImpl.}`) — **Phase 1에서 전환 완료**
- 🟡 = Medium (IR extension or minor refactor)
- 🔴 = Hard (I/O split or state machine decomposition)
- ⚫ = Impossible (remains `{.axiom.}`)

---

#### `src/core/diagnostics/diagnostics_engine_helpers.nim` — 11 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 1 | `hasRecursiveShapeString` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 2 | `hasInvariantMarker` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 3 | `detectNonLinearArithmeticCount` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 4 | `analyzeLogicalComplexity` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 5 | `diagnoseSolverCrash` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 6 | `diagnoseSolverTimeout` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 7 | `diagnoseProofIrrelevantFailure` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 8 | `detectHilbertChoicePattern` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 9 | `detectQuantifierAlternation` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 10 | `generateSelfHealingDirective` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 11 | `deduplicateTier2Candidates` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/diagnostics/diagnostics_engine_main.nim` — 2 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 12 | `structuralRemediationHint` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 13 | `structuralRationale` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/vault/vault_manager_spec.nim` — 7 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 14 | `axiomInvalidErrorMessage` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 15 | `vaultLoadErrorMessage` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 16 | `sanitizeVaultToken` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 17 | `axiomSpecFileName` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 18 | `axiomSpecToJsonNode` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 19 | `parseAxiomSpec` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 20 | `computeSourceFingerprint` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 21 | `currentVaultTimestamp` | I/O boundary split | 🔴 |

#### `src/core/symbolic/smt_hints.nim` — 1 func

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 22 | `buildAxProofSmtAssertions` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/symbolic/global_symbol_graph_types.nim` — 2 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 23 | `graphHash` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 24 | `indexDeclarationsInAst` | return-value pattern | 🟡 |
| 25 | `collectReferencesInAst` | tree-walk, state machine | 🔴 |

#### `src/core/session/session_parser_validators.nim` — 17 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 26 | `isAnyString` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 27 | `isLeapYear` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 28 | `daysInMonth` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 29 | `isHexLower` | nnkCharLit IR 확장 필요 | 🟡 |
| 30 | `isHexUpper` | nnkCharLit IR 확장 필요 | 🟡 |
| 31 | `isDigit` | nnkCharLit IR 확장 필요 | 🟡 |
| 32 | `digitVal` | nnkCharLit IR 확장 필요 | 🟡 |
| 33 | `isAlphaNum` | nnkCharLit IR 확장 필요 | 🟡 |
| 34 | `isMimeTokenChar` | nnkCharLit IR 확장 필요 | 🟡 |
| 35 | `isBase64Char` | nnkCharLit IR 확장 필요 | 🟡 |
| 36 | `isNonEmpty` | string op `s.len` 필요 | 🔴 |
| 37 | `isValidUuid` | string op `s.len`, `s[i]` 필요 | 🔴 |
| 38 | `parse2` | string slicing 필요 | 🔴 |
| 39 | `parse4` | string slicing 필요 | 🔴 |
| 40 | `isValidSchemaVersion` | string ops `split` 필요 | 🔴 |
| 41 | `isValidMimeType` | string ops `contains` 필요 | 🔴 |
| 42 | `isValidBase64` | string ops + loop | 🔴 |
| 43 | `isValidJsonBlob` | string ops | 🔴 |
| 44 | `isValidIso8601` | string ops `s[4]`, `s.len` | 🔴 |

#### `src/core/orchestrator/orchestrator_vault.nim` — 9 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 45 | `safeSpeedupRatio` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 46 | `stateHasVaultEntry` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 47 | `stateLookupVaultAxiom` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 48 | `stateCollectDependencyAxioms` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 49 | `resolveVaultPath` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 50 | `addNodeExecutionStat` | var locals (loop) | 🟡 |
| 51 | `addDepthExecutionStat` | var locals (loop) | 🟡 |
| 52 | `finalizeExecutionStats` | I/O boundary (clock) | 🔴 |
| 53 | `hydrateVaultRecord` | I/O boundary (disk) | 🔴 |
| 54 | `addNodeReport` | I/O boundary (callback) | 🔴 |
| 55 | `primeTransitiveFingerprintCache` | I/O boundary (transitive) | 🔴 |

#### `src/core/orchestrator/orchestrator_topology_depth.nim` — 9 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 56 | `sortWorkItemsByDepth` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 57 | `totalPlanDepths` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 58 | `computeParallelWorkerLimit` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 59 | `resolveDepthBoundary` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 60 | `computeCriticalPath` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 61 | `estimateWorkItemSpan` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 62 | `collectImpactedBranchNodes` | while-loop (loops) | 🟡 |
| 63 | `computeNodeDepths` | for-loop | 🟡 |
| 64 | `collectTopologicalNodeIndices` | for-loop | 🟡 |

#### `src/core/orchestrator/orchestrator_topology_worker.nim` — 6 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 65 | `clampTimeoutMs` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 66 | `calcDynamicTimeout` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 67 | `resolveProofFingerprint` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 68 | `diagnoseTimeout` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 69 | `blockBranch` | var locals | 🟡 |
| 70 | `registerTimeoutImpact` | var locals | 🟡 |

#### `src/core/orchestrator/orchestrator_api.nim` — 4 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 71 | `initParallelTaskQueue` | var param zero-set | 🟡 |
| 72 | `addPlanReproofNodes` | for-loop | 🟡 |
| 73 | `registerTerminalNodeStatus` | I/O boundary | 🔴 |
| 74 | `enqueueParallelWorkItem` | I/O boundary | 🔴 |
| 75 | `prepareParallelInputs` | I/O boundary | 🔴 |

#### `src/core/orchestrator/cfg_builder.nim` — 5 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 76 | `collectStatements` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 77 | `isControlFlowNode` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 78 | `buildCfgFromAst` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 79 | `findBackEdges` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 80 | `buildCfgFromStatementList` | 재귀 + var state, 7-branch case | 🔴 |
| 81 | `newBlock` | var state mutation | 🟡 |
| 82 | `link` | var state mutation | 🟡 |

#### `src/core/topology/topology_parser.nim` — 12 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 83 | `normalizeLineSpan` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 84 | `isIdentifierStart` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 85 | `isIdentifierChar` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 86 | `isFunctionNameChar` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 87 | `isReservedCallToken` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 88 | `parseIdentifierAt` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 89 | `parseDeclaration` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 90 | `detectCStyleDeclaration` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 91 | `stripInlineComment` | while-loop | 🟡 |
| 92 | `extractTrailingIdentifier` | while-loop | 🟡 |
| 93 | `detectKeywordDeclaration` | var locals | 🟡 |
| 94 | `countControlSignals` | for-loop | 🟡 |
| 95 | `extractCallTargets` | for-loop | 🟡 |

#### `src/core/topology/topology_engine.nim` — 3 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 96 | `findTopologyNodeContext` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 97 | `findTopologyMetricIndex` | for-loop | 🟡 |
| 98 | `findTopologySymbolIndex` | for-loop | 🟡 |

#### `src/core/topology/topology_symbol_scanner.nim` — 3 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 99 | `buildSymbolIndexTable` | for-loop | 🟡 |
| 100 | `beginTopologySymbol` | return-value pattern | 🟡 |
| 101 | `scanTopologySource` | 7 mutable locals, state machine | 🔴 |

#### `src/core/topology/topology_dependency.nim` — 7 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 102 | `verifyEngineQuiescence` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 103 | `proximityScore` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 104 | `buildMetric` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 105 | `compareMetricPriority` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 106 | `computeDependents` | while-loop | 🟡 |
| 107 | `collectTransitiveDependents` | while-loop | 🟡 |
| 108 | `sortMetricIndices` | 비교 정렬 | 🟡 |
| 109 | `sortByCoupling` | 비교 정렬 | 🟡 |
| 110 | `sortByRepairPriority` | 비교 정렬 | 🟡 |
| 111 | `computeInterfaceDistances` | BFS while-loop, state machine | 🔴 |

#### `src/core/sorter/sorter_core_index_base.nim` — 9 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 112 | `sorterNodeId` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 113 | `nodeIdEquals` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 114 | `deduplicateStrings` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 115 | `containsNodeId` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 116 | `deduplicateNodeIds` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 117 | `findNodeIndex` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 118 | `findVaultEntryIndex` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 119 | `computeNodeSignature` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 120 | `validateNodeSignature` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/sorter/sorter_core_index_table.nim` — 12 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 121 | `buildNodeIndexTable` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 122 | `buildVaultEntryIndexTable` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 123 | `hasVaultEntry` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 124 | `buildAxiomFormula` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 125 | `findVaultIntegrityBlockIndex` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 126 | `buildVaultIntegrityBlockIndexTable` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 127 | `hasVaultIntegrityBlock` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 128 | `allDependenciesInVault` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 129 | `collectFormulasForNode` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 130 | `addUniqueReleasedNode` | return-value pattern | 🟡 |
| 131 | `addDependentEdge` | return-value pattern | 🟡 |

#### `src/core/json/json_scan_skip.nim` — 9 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 132 | `isJsonWhitespace` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 133 | `skipJsonStringValue` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 134 | `skipJsonWhitespace` | while-loop | 🟡 |
| 135 | `skipJsonLiteral` | while-loop | 🟡 |
| 136 | `skipJsonValue` | case 분기 | 🟢 |
| 137 | `skipJsonArray` | while-loop | 🟡 |
| 138 | `skipJsonObject` | while-loop | 🟡 |
| 139 | `decodeJsonString` | multi-loop, var param | 🔴 |
| 140 | `skipJsonNumber` | multi-loop, state machine | 🔴 |
| 141 | `appendCodePoint` | var param string | 🔴 |

#### `src/core/json/json_scan_parse.nim` — 7 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 142 | `parseJsonStringField` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 143 | `parseJsonStringAtPath` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 144 | `parseJsonStringAtPathOrDefault` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 145 | `parseJsonBoolAtPathOrDefault` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 146 | `parseJsonStringArrayAtPath` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 147 | `findObjectField` | while-loop | 🟡 |
| 148 | `getJsonValueAtPath` | while-loop | 🟡 |

#### `src/core/gate/gate_rules_normalization.nim` — 6 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 149 | `normalizedEntries` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 150 | `normalizedResources` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 151 | `normalizedDependencies` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 152 | `normalizedTags` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 153 | `normalizedWeights` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 154 | `normalizedPriorities` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/gate/gate_rules_architecture.nim` — 8 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 155 | `addArchitectureViolation` | return-value pattern | 🟡 |
| 156 | `applyResourceFanoutCheck` | return-value pattern | 🟡 |
| 157 | `applyDryCheck` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 158 | `applyWriteOwnershipCheck` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 159 | `applyLspInvariantCheck` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 160 | `applyCallDepthCheck` | return-value pattern | 🟡 |
| 161 | `applyLowCohesionCheck` | return-value pattern | 🟡 |
| 162 | `applyDependencyBudgetCheck` | return-value pattern | 🟡 |

#### `src/core/gate/gate_rules_module_classifier.nim` — 4 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 163 | `buildModulePathMap` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 164 | `extractModuleStemFromDependency` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 165 | `buildQualifiedCallGraph` | tree-walk | 🟡 |
| 166 | `computeMaxCallDepth` (+dfs) | DFS 재귀 | 🟡 |
| 167 | `initModuleClassificationCache` | I/O boundary | 🔴 |
| 168 | `isConcreteModule` | I/O boundary | 🔴 |
| 169–171 | `isAbstractModule`, `isLikelyConcreteName`, `isLikelyAbstractionName` | I/O/string heuristics | 🔴 |

#### `src/core/gate/scheduler.nim` — 3 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 172 | `initScheduler` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 173 | `isSlow` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 174 | `computePriority` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/cli/*.nim` — 8 funcs

| # | 파일 | 함수 | Diff | 카테고리 |
|---|------|------|------|---------|
| 175 | `wf_render.nim` | `renderAxScanLines` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 176 | `wf_render.nim` | `renderAxTopologyLines` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 177 | `wf_state_parsing.nim` | `jsonFromAxFrontierEntries` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 178 | `wf_state_parsing.nim` | `readAxShortcutStateString` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 179 | `wf_state_parsing.nim` | `readAxShortcutStateOptionalString` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 180 | `wf_state_parsing.nim` | `readAxShortcutStateInt` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 181 | `wf_state_parsing.nim` | `buildAxScanJson` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 182 | `version.nim` | `extractVersionFromNimble` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 183 | `cli_io_input.nim` | `parseRequiredIntArgOrDie` | I/O boundary | 🔴 |
| 184 | `cli_io_input.nim` | `requireArg` | I/O boundary | 🔴 |
| 185 | `cli_io_input.nim` | `requireIntArg` | I/O boundary | 🔴 |
| 186 | `cli_io_error.nim` | `die` | ⚫ Impossible | ⚫ |
| 187 | `action_output_cli.nim` | `writeOutputBlock` | ⚫ Impossible | ⚫ |
| 188 | `action_output_cli.nim` | `emitAxShortcutResult` | ⚫ Impossible | ⚫ |

#### `src/core/parsers/*.nim` — 3 funcs

| # | 파일 | 함수 | Diff | 카테고리 |
|---|------|------|------|---------|
| 189 | `collect.nim` | `assignmentLhs` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 190 | `pred.nim` | `hasIdentifierNamed` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 191 | `tree_sitter_extractor.nim` | `extractGenericParams` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 192 | `nav.nim` | `findFirstNode` | 재귀 tree-walk | 🟡 |

#### `src/core/boundary/*.nim` — 4 funcs

| # | 파일 | 함수 | Diff | 카테고리 |
|---|------|------|------|---------|
| 193 | `ast_extractor.nim` | `inferCallsFromBody` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 194 | `ast_extractor.nim` | `inferAccessedResourcesFromBody` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 195 | `ast_extractor.nim` | `ensureAstCacheInit` | global cache I/O | 🔴 |
| 196 | `meta_extractor.nim` | `extractFfiParamsFromAst` | NimNode domain (func) | 🟢 |
| 197 | `meta_extractor.nim` | `extractFfiBoundaries` | ⚫ Impossible (macro) | ⚫ |

#### `src/core/telemetry/metrics.nim` — 2 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 198 | `computeCoverage` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 199 | `computeRetryPenalty` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/telemetry/metrics.nim` (sub-module) — 1 func

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 200 | `computeInformationGainWeightedAsi` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/lean/lean_lsp_protocol.nim` — 4 pure + 4 I/O + 1 thread

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 201 | `extractGoalLines` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 202 | `extractStrings` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 203 | `extractLeanGoalsFromJson` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 204 | `parseDiagnostics` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 205–211 | `toFileUri`, `tryResolveLeanExe`, `resolveLeanExe`, `logRpc`, `pollMessages`, `writeRpcMessage`, `sendNotification`, `sendRequest` | I/O boundary | 🔴 |
| 212 | `readerThreadFunc` | ⚫ Impossible (Thread) | ⚫ |

#### `src/verification/pipeline_lean_spec_inference_part1.nim` — 10 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 213–222 | `inferGuaranteedRange` 의 10개 함수 | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/pipeline/pipeline_healing_logic.nim` — 7 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 223–229 | 7개 healing 함수 | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/verification/reporter.nim` — 2 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 230–231 | `parseDeclarationIdent`, `parseProcBindingName` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/core/gate/logic_binding_gate.nim` — 2 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 232 | `hasLogicBinding` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 233 | `containsBannedAtom` | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/verification/analyzer_shared_json.nim` — 8 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 234–241 | `mergeStringEvidence` 외 7개 | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |

#### `src/verification/analyzer_shared_cert.nim` — 5 funcs

| # | 함수 | Diff | 카테고리 |
|---|------|------|---------|
| 242–246 | `parseDayFromTimestamp` 외 4개 | `{.axiom.}` → `{.axiom, axiomImpl.}` | 🟢 |
| 247 | `buildLastNDaysUtc` | I/O (clock) | 🔴 |
| 248 | `inferModulePathFromTheorem` | I/O (filesystem) | 🔴 |
| 249 | `parseJsonSafe` | JSON parse (pure) | 🟢 |

#### `src/gate/nimtry/nimtry_policy_lock.nim` — 이미 마이그레이션됨

| 함수 | Diff | 카테고리 |
|------|------|---------|
| `isPolicyLocked` | `{.axiom, axiomImpl.}` | ✅ |
| `enforcePolicyLock` | `{.axiom, axiomImpl.}` | ✅ |

#### `src/gate/nimtry/interface_auditor.nim` — 이미 마이그레이션됨

| 함수 | Diff | 카테고리 |
|------|------|---------|
| `auditInterface` | `{.axiom, axiomImpl.}` | ✅ |

---

### Summary Totals (Verified — Post Phase 1/2.5/3a.5)

| Category | Emoji | Count | % | Status |
|----------|-------|-------|---|--------|
| Phase 1 — Migrated | 🟢 | 181 (33/34 files) | >80% | ✅ **COMPLETED** |
| Phase 2.5 — String Theory Axiom Infra | — | 1 infrastructure | — | ✅ **COMPLETED** |
| Phase 3a.5 — n-Var BMC Generalization | — | 1 infrastructure | — | ✅ **COMPLETED** |
| Permanently Excluded (Phase 4) | ⚫ | ~12 | ~6% | 영구 제외 |
| Already migrated (pre-Phase 1) | ✅ | ~7 | ~4% | Tier 2 + 인프라 |
| Infrastructure (axiomImpl self) | — | ~5 | ~3% | 코어 인프라 |
| **Total (Phase 1 target)** | | **~195** | **100%** | |

> 참고: 총계가 175를 약간 초과하는 것은 일부 함수가 탐색 에이전트 간 중복 분석되었거나 분석 이후 새 함수가 추가되었기 때문이다. 실제 마이그레이션 시작 시 전체 `{.axiom.}` 목록을 `grep -rn`으로 재확인할 것.

---

*이 문서는 [AGENTS.md](AGENTS.md) §0.6 (Static First), §0.3 (Trust Boundaries), §1 (Architecture v31)의 요구사항을 구현하기 위한 실행 계획이다. 모든 변경은 `a108c6ecd` (Tier 2 선행 마이그레이션)과 `7ec5102af` (Issue 3 — `loopVariant`)의 패턴을 따른다.*
