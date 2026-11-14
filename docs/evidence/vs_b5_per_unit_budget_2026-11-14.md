# VS-B5 — J1 per-unit budget 해소 (Option C) 실행 증거

상태: 코드·사양 동일 세대 착지 증거. 관측 시각은 로컬(Asia/Seoul) 2026-11-14, 기준 커밋 `origin/main@4073514d` + 본 브랜치.
선택: **Option C**(공유 budget 경로 축소·제거). 근거는 `docs/design/j1_per_unit_budget_resolution_design_2026-11-13.md` §3 —
A(상수 8)는 N>2에서 `gasRemaining` 음수 → 영구 실패 게이트, B(Σ per-unit)는 §8.3 #4의 "frontier 비례 스케일링 제거"를 문자적으로 미충족.

## 변경 요지

| 표면 | 변경 전 | 변경 후 |
|---|---|---|
| `AxiomEngine` | `budget: ProofBudget` | `startMono: int64` (전역 gas 풀 없음) |
| `initAxiomEngine` | `(startMono, budgetGas, expectedNodeCount)` | `(startMono)` |
| 오케스트레이션 전달 | `gasLimit = engine.budget.gasTotal` 2곳 | 전달 없음 |
| ci-cd 게이트 | `budgetHealthy and depthCoverage` | `depthCoverage` |
| `ProofTask.budgetGas` / `axiom.toml [prove].budget_gas` | 소비됨(전역 스케일링 입력) | 소비 경로 제거 |
| `runBatchUapOrchestration` | `gasLimit: int = 0` | 파라미터 없음; 집계 budget은 telemetry |

## 검증 (명령 → 관측)

1. **엔진 계약 + 음성 통제**
   `nim c -r --hints:off tests/cli/test_axiom_engine.nim`
   관측: 전 suite `[OK]`. 신규 suite "initAxiomEngine — plan-independent engine (canonical_execution_semantics §8.3 #4)"의
   `check not compiles(initAxiomEngine(startMono = 1_000_000, expectedNodeCount = 5))` 및 `(…, budgetGas = 200)` 통과
   → 파라미터 재도입 시 이 파일이 컴파일되지 않는다(구조적 회귀 차단).

2. **오케스트레이터 회귀**
   `nim c -r --hints:off tests/unit/batch_uap_orchestrator_test.nim` → **exit 0**. 출력의 `Error: 2`는 loop_driver의 proof summary 로그(노드 2건 IR FAIL 픽스처)이며 unittest 실패가 아니다.

3. **per-unit 독립성**
   `nim c -r --hints:off tests/unit/selection_independence_test.nim` → **exit 0**.
   `per-unit budget is independent of frontier size` / `verdict is consistent across plans` / `gasTotal matches calculateAdaptiveGas` 3건 `[OK]`.

4. **제품 바이너리 빌드**
   `nim c --hints:off --warnings:off -d:release -o:bin/ax src/cli/main.nim` → **exit 0** (12.9MB 산출).

## 판정

- `Result(U, Plan_A) == Result(U, Plan_B)`: 유닛 판정 입력은 `checkBudget(unitBudget)`(`loop_driver.nim:606`)과 per-node wall-clock(120s)뿐이며, 둘 다 유닛 고유 신호다.
- 리포트 결정론(R2): ci-cd 게이트가 전역 예산을 관측하지 않으므로 `gates` 배열이 plan 크기에 의존하지 않는다.
- 미해소 잔여(수정하지 않음): `checkBudget(unitBudget)`이 생성 직후 fresh 예산에 수행되는 도달 불가 경로. DEBT 미등록 — 이를 다루는 별도 슬라이스의 착수 조건으로 기록한다.