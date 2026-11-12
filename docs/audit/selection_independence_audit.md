# 선택 독립성 감사 (Selection-Independence Audit)

> **목적**: 단위 semantic 입력이 동일할 때, 어떤 Plan(선택 집합)에 포함되든 결과가 동일한지 확인.
> **불변식(Project)**: `Result(U, Plan_A) == Result(U, Plan_B)` — 단, `U ∈ Plan_A ∩ Plan_B`이고, Plan 파생 실행 상태가 단위 판정에 영향을 주지 않아야 함.
> **감사 범위**: S0b 선택 독립성 하위 시스템의 8개 경로.
> **일자**: 2026-09-04

---

## 불변식 (Invariant)

선택 독립성(Selection-Independence)이란, 동일한 단위 `U`에 대해 Plan A(U만 포함)와 Plan B(U + 다른 단위들 포함)가 동일한 단위 semantic 입력 하에 동일한 판정(verdict)·동일한 증거·동일한 실행 정체성을 산출해야 한다는 속성이다.

형식적으로: `U`의 실행 환경이 Plan의 크기·구성·순서에 의존해서는 안 된다.

---

## 경로별 증거 표 (Per-Path Evidence Table)

| # | 경로 | 상태 | 파일:라인 | 증거 |
|---|------|------|-----------|------|
| 1 | **공유 가스 예산 (Shared Gas Budget)** | **LEAK** | `src/cli/axiom_engine.nim:812-813` | `gasLimit = frontier.len × MaxGasCostPerNode` (line 812: `targetNodeCount = max(1, frontier.len)`, line 813: `initAxiomEngine(..., task.budgetGas, targetNodeCount)` → line 247: `expectedNodeCount * MaxGasCostPerNode`). 공유 `ProofBudget` (`src/verification/batch_uap/loop_driver.nim:745`: `var budget = if gasLimit > 0: initProofBudget(gasLimit = gasLimit) else: initProofBudget()`). 고갈 시 `orchestrationTimedOut` 오버라이드 (`loop_driver.nim:871-882`, `loop_depth_scheduler.nim:390-397`). **Plan B가 더 많은 노드를 포함하면 더 많은 가스를 할당받아 U의 판정이 달라질 수 있음.** |
| 2 | **배치 메모리 캐시 (memoCache)** | **CLEAN** | `src/verification/batch_uap/ir_pipeline_runner.nim:1217-1234` | CAS 키 = `computeDeterministicCasKey(serializeIRFuncDef(funcDef))` (line 1224). `computeDeterministicCasKey`는 `src/core/deterministic_cas_key.nim:17-23`에서 SHA-256 기반 순수 함수. 캐시는 **per-worker** `var memoCache: var Table[string, IrPipelineResult]` (line 1219, 1374)로 격리되어 다른 Plan의 worker와 공유되지 않음. |
| 3 | **summaryCache** | **CLEAN** | `src/verification/batch_uap/private/types.nim:18` | 키 = `modulePath#functionName` (`makeCacheKey` at `src/core/types/function_verification_summary.nim:28-29`). 값에 `checksum` 필드 포함 (`FunctionVerificationSummary.checksum` at `function_verification_summary.nim:22`)으로 지문(fingerprint) 일치 검증. Plan과 무관한 순수 키-값 조회. |
| 4 | **배치 순서 (Batch Ordering)** | **CLEAN** | `src/verification/batch_uap/loop_depth_scheduler.nim:467-470` | 결과는 `taskIndex` 기준으로 결정적으로 재정렬: `for collectIdx in 0..<pendingItems.len: let res = channelPtr[].recv(); results[res.taskIndex] = res` (line 467-470). 단위 검증은 순서와 독립적 (예산 제외). |
| 5 | **랭킹/선택 상태 (Ranking/Selection State)** | **CLEAN** | `src/cli/selection_state.nim:48-60` | `NodeSelectionState` (line 48-52)는 `counts`, `asiHistory`, `stallCount`만 관리. `computeScore` (line 56-60)는 선택 횟수에 기반한 우선순위 계산이며, **검증 매개변수(verification parameters)에 전혀 영향을 주지 않음**. |
| 6 | **프론티어/스코프 (Frontier/Scope)** | **CLEAN** | `src/core/topology/verified_frontier.nim:40-96` | `computeVerifiedFrontier` (line 40-96)은 **적격성(eligibility) 필터링만** 수행. 의무 내용(obligation content)은 단위 로컬(unit-local)이며, 프론티어는 `sorterNodeId` 목록만 반환. |
| 7 | **솔버 세션 (Solver Sessions)** | **CLEAN** | `src/verification/solver/z3_pool.nim:649-664` | `zmRaw` 모드에서 모든 쿼리 전에 `(reset)` 삽입 (line 649-650) + 고유 sentinel 매칭 (`AXIOM_Z3_EOF_<id>`, line 664). `fixedpoint_engine.nim:153`에서 호출 시마다 신규 `Z3PoolProver()` 생성 (line 153: `let prover = Z3PoolProver()`). Plan 간 세션 상태 누적 없음. |
| 8 | **의무 생성 (Obligation Generation)** | **CLEAN** | `src/verification/obligation/canonical_obligation_generator.nim:147` | `generateCanonicalObligations(funcDef, policy)`는 `{.raises: [].}` 순수 함수 (line 147-150). `funcDef` + `policy`(단위 로컬 스코프 정책)의 함수이며, Plan 크기·구성에 의존하는 입력 없음. |

---

## 판정 (Verdict)

| 경로 | 판정 |
|------|------|
| memoCache (2) | ✅ CLEAN — 결정적 CAS 키, per-worker 격리 |
| summaryCache (3) | ✅ CLEAN — Plan-독립적 키-값 조회 |
| Batch ordering (4) | ✅ CLEAN — taskIndex 기반 결정적 재정렬 |
| Ranking/selection state (5) | ✅ CLEAN — 순위 계산만 영향, 검증 매개변수 무영향 |
| Frontier/scope (6) | ✅ CLEAN — 적격성 필터링만, 의무 내용은 단위 로컬 |
| Solver sessions (7) | ✅ CLEAN — per-query reset + fresh prover |
| Obligation generation (8) | ✅ CLEAN — 순수 함수, Plan 무관 |
| **Shared gas budget (1)** | ⛔ **LEAK** — frontier 크기에 비례하여 가스 할당이 변하며, Plan B가 Plan A보다 더 많은 가스를 가져 Plan A 단위 U가 예산 고갈로 `orchestrationTimedOut` 판정을 받을 수 있음 |

---

## 잔여 위험 (Residual Risk)

### 1. 가스 예산 누출 (Gas Budget Leak)

위 경로 1에서 확인된 대로, `gasLimit = frontier.len × MaxGasCostPerNode`로 Plan 크기에 따라 가스가 변한다. 이는 선택 독립성 불변식을 위반한다. **S0b 예산 작업 스트림에서 수정 완료**: 공유 `ProofBudget`의 verdict 제어를 제거하고, unit 자체 complexity 신호(`calculateAdaptiveGas`)에서 유도한 per-unit budget(`initPerUnitBudget`, `proof_budget.nim`)으로 대체했다. 공유 budget은 집계 보고용으로만 유지된다(verdict 비영향). 회귀 테스트 `tests/unit/selection_independence_test.nim`의 "Per-Unit Budget Independence" suite(3건)가 이를 검증한다. S4 이전에 재감사(re-audit)는 유지한다.

### 2. 이후 추가 상태 (New State Added Later)

새로운 상태(state)가 추가될 때마다 선택 독립성이 훼손되지 않는지 재검증해야 한다.

### 재감사 절차 (Re-Audit Procedure)

1. `docs/audit/selection_independence_audit.md`의 8개 경로를 모두 재확인
2. `src/cli/axiom_engine.nim:812-813`의 가스 계산 로직 변경 여부 확인
3. `src/verification/batch_uap/loop_driver.nim:745`의 `ProofBudget` 초기화 경로 변경 여부 확인
4. 8개 경로 각각에 대해 `git diff`로 수정 범위 확인 후 표 갱신
5. 변경 사항이 있으면 `docs/audit/selection_independence_audit.md` 갱신 + `data/debt_registry.json`에 새로운 DEBT 항목 등록

---

## 회귀 테스트 (Regression Test)

`tests/unit/selection_independence_test.nim` — 선택 독립성 불변식을 검증하는 회귀 테스트.

- **CLEAN 경로**: 7개 경로(2-8)에 대한 결정적 동일성 어설션 포함
- **예산 경로**: `initAxiomEngine`의 `expectedNodeCount` 매개변수가 가스 한도에 영향을 미침을 검증하여 누출을 감지하는 어설션 포함 (현재 실패 — 이는 실제 발견 사항)
- **실행 방법**: `nim c -r --hints:off tests/unit/selection_independence_test.nim`
