# ADR-0019: Verification Tiers & Deterministic CI Scheduling (L0/L1/L2)

## Status

**ACCEPTED (2026-09-23, Ratified — 사용자 확정 결정(AI 세션 승인 — AskUserQuestion 2채택 기록)).** 이 ADR은 P2 증분 검증 엔진(ADR-0017, P2 계약 참조본)의 안전 Skip 사다리(§5)를 구체적 검증 등급(L0/L1/L2)으로 세분화하고 결정적 스케줄링 불변식을 정의하는 설계를 승인한다. CI wiring(`.github/workflows/ci.yml`, §-1 불변) 연기는 **CI=0 cutover(2026-09-20)로 종료**되어 더 이상 연기 대상이 아니며, tier·스케줄링 모델은 **설계 계약**으로 유지된다(`docs/spec/incremental_ci_tiers_scheduling.md` 범위 선언과 정합). main 착지·release tag의 실행 정책과 티어 소거 금지 명문화는 **ADR-0017 Amendment A1(2026-09-23)**이 확정하며, 본 ADR §1·§5·Consequences는 이를 참조한다. **2026-09-26 (ADR-0024 결정 #15)**: release **tag push 발화 트리거** 경로는 폐기되어 §1·§5의 "Release tag" 행은 release 출하(release-ship dispatch) 경로로 갱신된다 — full L2 의무·A1.2(main 착지 provenRequired)·티어 소거 금지는 유지되며, A1.3의 발화·수동 push 절차만 ADR-0024가 supersede한다. **2026-09-29 (ADR-0025 Amendment B)**: push@main 트리거 폐기 — main 착지 Actions 실행 0(의무는 candidate 승계, A1.2bis 연속), 씨딩 = workflow_run `ci-cache-publisher`; 본 ADR의 "main 착지: provenRequired(Δ)" 발화는 발화 주체가 candidate(PR 게이트)임을 뜻한다. **2026-09-30 (PR-B epoch cutover 문서 트랙)**: §1·§4·Consequences의 "L0는 항상 실행" 문장(:25·:66·:92)은 **계약(설계)**이며 현행 CI(9-job)에서 미실현(DEBT#466)임을 명시한다 — `docs/spec/incremental_ci_tiers_scheduling.md` Amendment(2026-09-30)·DEBT#469가 계약-실행 불일치 상태를 병존 기록하고, Known-branch witness(격자 프로젝션 밖 W4 클래스 미실현 — DEBT#466 b+)를 등록하며, selector 잔존 신뢰 경계(런타임 후보-트리 빌드 — B-pin 범위 밖, DEBT#467)를 등록한다. Epoch 기록: `docs/evidence/epoch_record_oracle_select_2026-09-30.md`.

## Context

Axiom CI 파이프라인은 단일 CX23 호스트에서 `needs` 체인으로 serialized되며, 모든 변경에 대해 전체 재계산(약 74분, 사전 최적화 73m49s / 사후 최적화 69m53s)을 수행한다(`docs/reports/ci_observed_dag_p1_2026-08-28.md` §1). P2 계약(`docs/spec/incremental_ci_contract.md`)은 Work Unit 모델(W1–W11 + G1/G2/G4/G6/G7), 종속성 폐쇄 규칙(§3), 두 불변식(§4), 그리고 안전 Skip 사다리 L0/L1/L2(§5)를 정의했다.

P2 계약 §5는 사다리의 **설계 방향**만 정의했지, 각 Work Unit의 **구체적 등급 멤버십**, **결정적 스케줄링 불변식의 정밀한 형태**, 그리고 **impact-closure selector가 L1을 어떻게 피딩하는지**를 명시하지 않았다. 이 ADR은 이 세 가지 공백을 채운다.

핵심 설계 의도:

1. **L0**는 초 단위의 즉시 피드백(문법/정적/타겟 로컬)이며, **L1**은 변경 영향 폐쇄 기반의 선택적 재실행(초~분), **L2**는 병합/릴리스 경계의 전체 인증(1h 이하)이다.
2. **결정성**: 동일 커밋 + 동일 그래프 + 동일 계약 → 동일 작업 단위 선택. 인간 판단(judgment)이 개입하지 않는다.
3. **impact-closure selector** (`tools/ci/impact_closure_selector.nim`)는 L1의 결정적 엔진으로, `DependencyClosure(Change, ContractGraph)`를 구현한다.

## Decision

### 1. Tier 정의

| Tier | 대상 | 소요시간 | 실행 조건 |
|---|---|---|---|
| **L0** | 문법/정적 검증 + 타겟 로컬 테스트 | 초 단위 (≤ 3m) | 변경이 비-normative 문서이거나 캐시 히트인 경우. L0 단위는 영향 폐쇄와 무관하게 항상 실행. |
| **L1** | 변경 영향 검증 | 초~분 단위 | `DependencyClosure(Δ, ContractGraph)`가 비어있지 않은 Work Unit만 선택. 대부분의 개발 반복이 여기 착지. |
| **L2** | 전체 인증 | 1h 이하 적절 | release 출하(release-ship): full 12-job workflow / N legs(ci-bootstrap + gateway-shard×8 + gateway-identity-gate) — ADR-0024 결정 #15(A1.3 supersede, tag push 트리거 제거). 미실행 격자 W1·W3–W7·W9–W11은 DEBT#466. main 착지: `provenRequired(Δ)`만, UNCERTAIN → 전체 (ADR-0017 Amendment A1). |

### 2. Tier Membership of W1–W11

**결정 요지**: W1–W11 각 Work Unit은 L0(즉시, 타겟 로컬)·L1(변경 영향 검증)·L2(전체 인증) 중 하나에 배정한다. 멤버십 값의 **유일 권위 = `src/gate/proof_unit_catalog.nim`** (`ProofUnit.tier` + `subunits`, 2026-09-23) — 이 ADR은 값을 재선언하지 않는다(결정 기록의 요지 + 참조만). W4의 G1/G2/G6/G7 서브유닛(G7은 L0)은 Catalog `subunits` 필드로 표현된다.

역사적 결정 값 (2026-08-28, 참고용 — 값이 필요하면 Catalog를 읽을 것): L0 = {W3, W4/G7, W10, W11}, L1 = {W1, W2, W4(컨테이너), W4/G1, W4/G2, W4/G6+G4, W5, W6, W7, W8}, L2 = 전체 파이프라인(W1–W11 + W9).

### 3. 결정적 스케줄링 불변식

> **SelectedWorkUnits(Commit) = DependencyClosure(Change, ContractGraph)**

```
SelectedWorkUnits(C) ≡ { U | closure(Δ_C) ∩ inputClosure(U) ≠ ∅ ∧ tier(U) ≤ Tier(C) }
```

여기서:
- `C` = 커밋 (base + head + repo state)
- `Δ_C` = C의 변경 집합 (git diff에서 결정적 산출)
- `closure(Δ_C)` = Δ_C의 전이적 종속성 폐쇄 (§3 추적 체인)
- `inputClosure(U)` = Work Unit U의 입력 폐쇄 (`docs/spec/incremental_ci_contract.md` §2.1)
- `tier(U)` = Work Unit U의 등급 (§2)
- `Tier(C)` = 커밋 C에 적용할 최대 등급 (§5 스케줄링 정책)

**결정성 보장 조건**:
1. `impact_closure_selector.nim` §6의 `computeFingerprint`는 변경 파일의 `(path, blobHash)` 쌍을 정렬하여 SHA256을 산출. 동일한 변경 → 동일한 지문.
2. `impact_closure_selector.nim` §7 `mapToWorkUnits`는 결과를 `unit.id` 기준 정렬 (`result.sort(proc(a, b: AffectedUnit): int = cmp(a.unit.id, b.unit.id))`). 동일 입력 → 동일 순서.
3. `Tier(C)`는 CI 트리거 유형(push-to-main vs PR vs release)에 의해 결정되며, 이 ADR §5에서 정의.

### 4. Impact Closure Selector의 L1 피딩

`tools/ci/impact_closure_selector.nim`은 L1 스케줄링의 결정적 엔진이다:

1. `git diff --name-status base..head`로 변경 파일 목록 취득 (§5, `getChangedFiles`)
2. 각 변경 파일에 대해 `pathPatterns` 기반 직접 매칭 + `semanticRules` 기반 의미적 매칭 수행 (§7 `mapToWorkUnits`)
3. `computeFingerprint`로 변경 지문 결정적 산출 (§6, SHA256 of sorted `path blobHash` lines)
4. 영향받는 Work Unit 목록을 정렬하여 출력 (§7, `result.sort` by `unit.id`)
5. `ShadowReport` JSON으로 출력 (§9 `reportToJson`)

L0 Work Unit(W3, W4/G7, W10, W11)은 selector의 출력에 **항상 포함**된다(impact 폐쇄와 무관하게 baseline으로 실행). L1 선택은 L0 baseline 위에 추가되는 영향받은 Work Unit들이다.

### 5. 스케줄링 정책 (Tier(C) by Trigger)

| CI 트리거 | Tier(C) | SelectedWorkUnits |
|---|---|---|
| PR branch push (비-normative 문서) | L0 | L0만 실행 |
| PR branch push (일반 변경) | L1 | `DependencyClosure(Δ, ContractGraph)` ∩ {L0, L1} |
| Push to main | L1 (provenRequired) · L2 fallback | `provenRequired(Δ)`만; 판정 **UNCERTAIN → Tier(C)=L2 전체** (ADR-0017 Amendment A1) |
| Release 출하 (release-ship dispatch, 태그 생성 전) | L2 | full 12-job workflow / N legs(ci-bootstrap + gateway-shard×8 + gateway-identity-gate) — **필수, 예외 없음** (ADR-0024 결정 #15 — A1.3 supersede, v* tag push 트리거 제거); 미실행 격자 W1·W3–W7·W9–W11은 DEBT#466 |
| Manual `ax prove --full` | L2 | 전체 파이프라인 |

**Finding (2026-09-23 acceptance)**: shard 부분집합 미표현 — 선택 판정은 W8 단위이고 matrix는 static [0..7]이므로 0 < selectedShardCount < 8은 구조적으로 불가; A3의 demand reduction은 W-unit 레벨(legs 0/1/9)까지 달성, shard 레벨은 미달성(후속 확장 대상).

## Alternatives Considered

- **전체 재계산 유지 (현재 상태)**: 매 변경에 대해 74분 대기. Rejected — 개발자 피드백 루프의 결정성을 저해하며, README 변경에 74분을 지불하는 것은 낭비(`docs/adr/0017-incremental-verification-engine.md` Alternatives Considered 참조).
- **비결정적(판단 기반) skip**: 인간 판단에 의해 skip 대상을 결정. Rejected — `docs/spec/incremental_ci_contract.md` §4에서 요구한 "provably false" 조건을 위반하며, 극장의 온상이 됨.
- **이진 L0/L1만 사용 (L2 제거)**: L2를 제거하고 L0/L1만 사용. Rejected — 병합/릴리스 경계에서 전체 인증이 필요하며, L2는 소거되지 않는다(`docs/spec/incremental_ci_contract.md` §5.4).
- **Equal-tier 모든 Work Unit 실행**: L1에서 영향받지 않는 Work Unit도 실행. Rejected — L1의 목적은 영향 폐쇄에 의한 선택적 재실행이며, 전체 L1 실행은 L2와 구별 불가.
- **비교적 과소추정(under-approximation)**: 불확실한 경계를 좁은 단위로 해결. Rejected — `docs/spec/incremental_ci_contract.md` §3.2에서 under-approximation은 금지되며, 과대추정(over-approximation)만이 안전하다.

## Consequences

### 구조적 결과

- **Tier 멤버십**: W1–W11이 L0/L1/L2 중 정확히 하나에 배정됨. L0는 항상 실행, L1은 영향 폐쇄 기반 선택, L2는 전체 실행.
- **결정적 스케줄링**: `SelectedWorkUnits(Commit) = DependencyClosure(Change, ContractGraph)` 불변식이 모든 CI 트리거에 적용됨. 동일 커밋+동일 그래프+동일 계약 → 동일 작업 단위 선택.
- **Impact closure selector**: `tools/ci/impact_closure_selector.nim`이 L1의 결정적 엔진으로 역할. P3 shadow mode에서 동작하며, CI wiring은 아키텍트 승인 제안에 의해 연기됨.

### 안전 사다리 결과

- **L1이 일상 개발의 기본**: 작은 변경은 L1(초~분)만 지나며, 이는 P2의 주된 가치 제안.
- **L2는 소거되지 않음**: 병합/릴리스 시 전체 인증이 유지됨.
- **L0는 자동화**: 캐시 히트로 즉시 처리. 비-normative 문서 변경은 L0만 통과.

### CI wiring 연기

- `.github/workflows/ci.yml`은 §-1에 의해 불변. CI에 Tier(C) 스케줄링과 impact-closure selector를 연결하는 것은 별도의 아키텍트 승인 제안으로 연기됨.
- `impact_closure_selector.nim`은 현재 shadow mode(P3)에서만 동작하며, CI integration은 이 ADR의 범위 밖.

### 극장적 패턴 없음

- 모든 skip/reuse 주장이 `docs/spec/incremental_ci_contract.md` §4의 provably false 조건을 만족해야 함.
- `data/debt_registry.json`에 theater 마커로 등록된 패턴은 이 ADR의 범위에 포함되지 않음(기존 theater 레지스트리 준수).

### 참조

- `docs/spec/incremental_ci_contract.md` — P2 계약 SSOT (전체 세부사항).
- `docs/spec/incremental_ci_tiers_scheduling.md` — L0/L1/L2 tier & scheduling spec (§3 멤버십 값은 Catalog 참조).
- `src/gate/proof_unit_catalog.nim` — W1–W11 catalog SSOT (id/name/pathPatterns/duration/tier, 2026-09-23 cutover).
- `docs/reports/ci_observed_dag_p1_2026-08-28.md` — 관찰된 CI DAG (W1–W11 + G1/G2/G4/G6/G7 provenance).
- `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md` — Δ×work-unit 행렬 + §5.3 cache-key wiring 요구사항.
- `tools/ci/impact_closure_selector.nim` — L1 impact-closure selector 구현 (P3 shadow mode).
- `src/verification/obligation/identity.nim` — `CanonicalExecutionBundle`, `ExecutionContract`, `ExecutionIdentity`.
- `docs/adr/0017-incremental-verification-engine.md` — ADR-0017 (P2 증분 검증 엔진 수락).
- `.github/workflows/ci.yml` — CI 파이프라인 정의 (§-1 불변).

---

*작성일: 2026-08-28. ADR-0019: Verification Tiers & Deterministic CI Scheduling. ADR-0017(P2 수락)에 이어 다음 순서. CI wiring은 아키텍트 승인 제안에 의해 연기됨.*
