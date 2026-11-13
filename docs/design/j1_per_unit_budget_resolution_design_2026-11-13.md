# J1 Per-Unit Budget 위반 해소 설계 — 구현 승인 대기

상태: **DRAFT — 아키텍트 승인 대기.** 본 문서의 저장소 착지(MERGE)는 구현 승인이 아니며, 승인 요청 사항(§8)이 별도 판정 지점으로 명시된다.

작성 근거: 현행 main 코드 전수 추적(위반 생성→전파→소비→판정 체인) + TCB 게이트 결속 전수 탐색 + §8.3 규범 대조. 관측 시점 원격 main 923633f(해당 리비전에서 인용 전 라인 실측 재확인 — 분석 유효).

## 1. 위반 실체 (반증 교정 — 종전 서술의 정정)

**종전 서술(TCB §1.4, 2026-09-25 작성)의 "동일 유닛이 실행 계획에 따라 PASS/TIMEOUT이 갈린다"는 시나리오는 현행 main에 존재하지 않는다.** S0b 작업 스트림이 유닛 판정의 plan 의존 경로를 폐쇄했다:

- `docs/audit/selection_independence_audit.md:52` "수정 완료" + `src/verification/batch_uap/loop_driver.nim:583-618`·`loop_depth_scheduler.nim:708-710` — 공유 예산 소비는 집계 리포트 전용이고 반환 판정을 폐기한다.
- 유닛 판정은 per-unit 예산(`src/core/proof/proof_budget.nim:270-280`, 유닛 고유 신호 — "independent of run-global frontier size")과 per-node wall-clock(120s, :16)으로만 결정된다.

**잔여 위반은 3종이며 실체가 좁다**:

| # | 잔여 표면 | 위치 | 성격 |
|---|---|---|---|
| R1 | frontier 전체 크기의 예산 스케일링 잔존 | `axiom_engine.nim:5727-5728`(`initAxiomEngine(getMonoTime().ticks, task.budgetGas, max(1, prepared.frontier.len))`)·`:274-281`(expectedNodeCount × MaxGasCostPerNode=4) | §8.3 요구 #4 "targetNodeCount 기반 스케일링은 제거된다"의 **문자적 미충족**. 판정에는 비영향(소비 결과 폐기) |
| R2 | ci-cd 게이트 관측값의 plan 의존 | `axiom_engine.nim:566-568`(budgetHealthy·budgetRemaining) — exitCode 무영향(:658-661) | 리포트 표면(`reportJson["gates"]`)의 비결정성 |
| R3 | TCB §1.4의 규범적 blocker | `docs/spec/ci_optimization_tcb_judgments.md:71-78, 256` — 위반 존재를 전제로 계획/셀렉터 후보를 J1 FAIL로 판정 | **B5의 주효과가 여기에 있다: SL-09(gateway shard 8-way)의 J1 잠금 해제** |

부가 교정: 비례하는 것은 gas(솔버 호출 반복) 예산이지 wall-clock이 아니며, 공유 예산의 `wallDeadlineMs`(600s)은 어디서도 검사되지 않는 죽은 필드다.

## 2. §8.3 규범-코드 갭

| §8.3 요구(canonical_execution_semantics.md:350-357) | 현행 |
|---|---|
| 1) 각 unit 고유 unitBudget | ✅ loop_driver.nim:602-605·scheduler:334-337 |
| 2) ExecutionPlan 입력 유도·frontier/shared 무관 | ✅ (단 `checkBudget(unitBudget)`이 생성 직후 fresh 예산에 수행 — 사실상 항상 통과하는 도달 불능 게이트: 잔여 구조 문제) |
| 3) orchestrationTimedOut = unitBudget의 결과 | ✅ (공유 부족→unit 실패 경로는 S0b로 제거) |
| 4) targetNodeCount 스케일링 제거 | ⛔ **R1이 유일한 미충족** |

§8.2/§8.4의 인용 라인 4곳은 전부 스테일(:812-813→:5728, :871-882→ 코드 부재) — §5에서 처우.

## 3. 설계 옵션 A/B/C — 전체 비교 (선택은 유보)

> **Option C는 조사 에이전트의 권고 방향이다. 본 설계는 아키텍트 승인 시점의 선택을 유보한다** — 세 옵션의 변경 범위와 증명 비용을 동일 기준으로 제시한다.

| | **A — 유닛당 고정(상수/명시 전용)** | **B — Σ per-unit 집계** | **C — 공유 예산 경로 축소·제거** |
|---|---|---|---|
| 내용 | `:5728`에서 `max(1, frontier.len)` 제거 — engine 예산은 budgetGas(명시) 또는 상수 `maxTotalSolverInvocations`(=8)만 | gasTotal := Σ 유닛별 `calculateAdaptiveGas(u)`(균일 N×4를 유닛 신호 합으로 교체) | `:5728`을 시계 주입용으로 축소; `engine.budget.gasTotal`의 오케스트레이션 전달(:391/:535)과 ci-cd 게이트(:566-568)를 판정·게이트 경로에서 제거(집계 회계는 telemetry로 격리·문서화) |
| **변경 범위** | `axiom_engine.nim:5728`, `:274-281`(파라미터 제거), `src/generated/type_registry_metadata.json`(exported API 재생성), ci-cd 게이트 의미 조정 | `:5728`(+유닛 신호 접근 경로), `loop_driver.nim:910` | `:5728, :391, :535, :566-568`, `loop_driver.nim:776, :910`, `BatchUapReport.budget` 소비자 점검 |
| 판정 이동 | 유닛 판정 무변동. gasTotal 4N→8: N>2에서 집계 gasRemaining 음수화 → `budgetHealthy=false` **게이트 이벤트 표면 회귀**(report-only) | 유닛 판정 무변동. budgetRemaining이 유닛 회계 정합(Σ예산−Σ소비) — R2 경계 시나리오도 소거. 단 **§8.3 #4 문자 미충족 잔존**(frontier 크기에 비례하는 합) | 유닛 판정 무변동 + R2 관측 자체 소거. 판정 반전 가능성 없음(이미 폐쇄) |
| **증명 비용** | 공통 ①-⑤ + gates 표면 회귀 고정 — 검증 6종 | 공통 ①-⑤ + ⑥ 잔액 회계 어설션 — 검증 7종 | 공통 ①-⑤ + ⑦ gates 배열 제거 확인 + ⑧ 판정 경로 grep(0참조) — 검증 8종 + 문서 슬라이스 대형화(TCB §1.4 + §8.2-8.4 + 감사 문서) |
| 리스크 | gates 하위 소비자 미확인분; API 메타데이터 재생성 동반; "집계 음수" 시맨틱 오염 | TCB 재판정에서 "frontier 비례 잔존" 이의 가능 — 문서 개정(집계 회계는 plan-합성 허용, 판정 입력 금지) 명문화 필수 | 문서 갱신 부담이 주된 작업량; `ProofReport.gateEvents` 소비자·`BatchUapReport.budget` 하위 호환 점검; S0b 서술과의 정합화 |

**공통 검증(①-⑤, 어느 옵션이든 필수)**: ① engine-level 어설션 신설(`initAxiomEngine(t,0,1)` vs `(t,0,5)` → gasTotal 동일 — 현재 `selection_independence_test.nim`에 부재, 감사 문서 :73 "포함" 서술과 드리프트) ② 동일 subject에서 `--limit`/`--target`로 frontier만 다른 2플랜 → 공통 유닛 `canonicalProjectionHash` 동일(`ax report --canonical-digest`) ③ `tools/ci/tcb_judgments.nim --judgment parity` exit 0 ④ golden §7.3 `Project(FULL, Selected) == PRUNED` 회귀 ⑤ gates 배열 스냅샷 고정.

## 4. TCB·사양 개정 계획 — 이원 분리 (핵심)

**(a) 인용 라인 근거 갱신 = 저위험 문서 수선.** 게이트 결속 전수 탐색 결과 **기계적 결속 0건**(적중 3곳 전부 마크다운: TCB 사양 :75-76·canonical_execution_semantics §8.2-8.4·selection_independence_audit :22,61. `tcb_judgments.nim`은 canonical projection 비교만, `config/repository_surface.json:104`는 TCB 문서 경로 기반 — 내용 수정 시 서피스 불변). 따라서 스테일 라인 인용(:844-845→:5728 등)의 갱신은 문서 수선이다. 단 (i) TCB 문서는 규범 사양이므로 개정은 **architect 승인 경유**(TCB §0.3), (ii) 갱신은 **라인 근거에 한정** — 위반 문장은 :5728 잔존(R1)으로 여전히 참이므로 판정 본문·J1 FAIL 규칙은 불변.

**(b) J1 FAIL 규칙·SL-09 blocker 해제 = 별도 아키텍트 승인.** R1 제거(코드) + §8.3 #4 충족 선언 + TCB §1.4 "KNOWN VIOLATION" 재판정 + §8.2-② "해소" 재기술은 **하나의 승인된 슬라이스**에서 코드와 동일 세대(§2.5)로 착지된다. 이것이 성공해야 SL-09의 J1 재판정(`slice_catalog.nim:205-222`, implemented:false)이 열린다.

(a)와 (b)를 혼동하지 않는다: (a)만 먼저 수행해도 J1 FAIL은 유지된다(위반이 코드에 잔존하므로 문장이 참이기 때문).

## 5. 파생 후속 (본 슬라이스와 분리)

- `checkBudget(unitBudget)` 생성 직후 호출의 도달 불능(항상 통과) 경로 — §0.9 감사 대상, 조용한 수정 금지, DEBT 등록 후 처우.
- 죽은·미연결 코드: `src/verification/batch_uap/spacer_chc_router.nim:426-448,525-546`의 `trySpacerInvariantSynthesisWithBudget`(호출자 0), `src/core/proof/proof_budget.nim:202,:220`의 `redistributeSurplus`·`isBudgetCritical`(프로덕션 호출자 0 — `tests/features/complexity_entropy_test.nim` 테스트 호출만 존재), 공유 예산 `wallDeadlineMs` 미검사 — §0.9 DEBT 등록 후보.
- 감사 문서 :73 "포함(현재 실패)" vs 실제 테스트 부재 드리프트 — ① 어설션 신설로 해소되는지 슬라이스에서 확인.
- `proof_budget.nim`은 ADR-0025 grandfathered waiver 아님 — `config/decision_binding.waiver.json:529` grandfathered(2026-12-31 만료) 대상이므로 해당 파일 수정 시 rationale 정리 동반.
- SL-09 J1 재판정(B2 전제, 별도).

## 6. 절차 요구사항 (슬라이스 필수 구성)

1. 사양 개정 선행(§0.5): canonical_execution_semantics §8.2-8.4 라인 갱신 + §8.3 #4 구현 계약 명시 + §8.2-② 해소 재기술(코드와 동일 커밋 세대).
2. 엔진 수정(§0.12 최소 변경): 선택 옵션의 변경 범위(§3) + API 변경 시 메타데이터 재생성.
3. 회귀 보강: engine-level 어설션 ① + gates 스냅샷 ⑤.
4. 기계적 동등성 검증 ①-⑤(+옵션별 ⑥-⑧) — 명령→관측→pass/fail 증거를 `docs/evidence/`에 기록.
5. 착지: 전용 workstream 브랜치(§2.1) → PR → 필수 게이트 → GitHub merge authority. **위반 해소 선언은 기계 관측 증거와 함께만**.
6. 수정 대상은 §-1 불변 파일 아님.

## 7. 영향 요약

- 유닛 판정(검증 의미론): 3 옵션 모두 무변동 — 동등성 검증 ②-④가 기계적으로 입증.
- 이동하는 것: R2 관측 표면(옵션 C 소거), TCB J1 판정(승인 (b) 후 SL-09 잠금 해제).
- 기대 효과: §8.3 #4 문자 충족 + 리포트 비결정성 제거 + **SL-09 승격의 선행 정확성 조건 충족**.

## 8. 승인 요청 사항 (판정 지점 — 본 문서 MERGE와 별개)

- **[승인-4] 옵션 A/B/C 선택** — §3 비교표 기준, 아키텍트 판정.
- **[승인-5] J1 해소 슬라이스 개시**(사양+엔진+검증 단일 세대) — §6 절차.
- **[승인-6] (a) 인용 라인 갱신의 문서 수선 진행** — 승인 [승인-5]와 동반 또는 선행 가능(판정 본문 불변 전제).

본 문서의 MERGE는 [승인-4/5/6] 중 어느 것도 의미하지 않는다.
