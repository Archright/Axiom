# ADR-0017: 증분 검증 엔진 (Incremental Verification Engine)

## Status

**Accepted.** 이 ADR는 P2 증분 검증 엔진의 설계 방향을 수락하며, `docs/spec/incremental_ci_contract.md`에 기술된 계약의 ADR-0017 참조본이다. P3에서 구현을 개시한다. **Amendment A1(2026-09-23)**이 main 착지 실행 정책을 `provenRequired(Δ)만 실행(UNCERTAIN → full L2)`으로, release tag는 full L2 필수로 확정하고, 티어 소거 금지(≠ 개별 착지 전체 실행)를 명문화한다. nightly 백스톱은 비도입, L2(M10)는 MUST가 아닌 POLICY로 재분류된다. **Supersede (2026-09-26, ADR-0024 결정 #15 — release-boundary authority)**: A1.3의 release tag 경로 — "태그 push → CI 발화"와 수동 `git push origin <v*>` 절차 — 는 **폐기**된다. v* tag는 release-authority App이 검증(full L2)·확인(environment) 후에만 생성하며, 출하 발화 경로는 release-ship → runner-pool workflow_call(force_full + target_sha) 위임으로 이전된다. A1.3의 full L2 의무·A1.4 티어 소거 금지·A1.2 main 착지 규칙은 유지된다. **Amendment A2(2026-09-30)**: 독립 오라클 evidence 계약(`axiom/oracle-evidence/v1` — 5축·`derivedEmpty`·`derivationDigest`, 셀렉터는 소비·검증만) 비준과 landingFloor 조건부식 전환(`lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty` — "영향-공집합 후보는 floor 면제")을 A2 절로 추가한다 — SL-09 승격 전 선행 조건(DEBT#470), Epoch 기록 `docs/evidence/epoch_record_oracle_select_2026-09-30.md`.

## Context

Axiom CI 파이프라인은 단일 CX23 호스트에서 `needs` 체인으로 serialized되며, **모든 변경에 대해 전체 재계산**(약 74분, 사전 최적화 73m49s / 사후 최적화 69m53s)을 수행한다. 이 벽-clock 시간은 개발자 피드백 루프의 결정성을 저해하며, 작은 변경(README 수정, 단일 테스트 파일 변경, `debt_registry.json` 한 줄 수정)에도 전체 74분 세트를 지불하게 한다.

P1은 두 가지 관찰 보고서를 생산했다:

- **`docs/reports/ci_observed_dag_p1_2026-08-28.md`**: 11개 Work Unit(W1–W11)과 verify-contract의 G1/G2/G4/G6/G7 서브 스테이지를 포함하는 관찰된 CI DAG.
- **`docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`**: Δ×work-unit AFFECTED/REUSABLE 행렬로, README 변경(Δ5)은 0m 영향(src/core 변경 Δ3은 ≈72m 영향)까지 **0%–98% savings**의 분산을 보였다.

핵심 문제: Makefile은 CI의 보편적 인보크 메커니즘이므로, 레시피 변경은 W1–W9를 전체 실행한다. 그리고 **normative 문서 변경은 캐시 키에 자동 무효화되지 않는다** (갭 G4) — `readiness_start_gate.nim`의 `filesPattern`이 `docs/spec/`을 나열하지 않기 때문이다.

현재 `data/decisions_graph.json`은 `tools/sync_decisions.nim`이 생성하며, `DecisionSpec`에 하드코딩된 ADR 목록과 `src/`의 `{.axiomDecision.}` pragma를 스캔한다. 이 ADR은 마크다운 파일만으로는 trivially 재생성되지 않으므로 `data/decisions_graph.json`은 수동 편집하지 않는다 (§아래 참조).

## Decision

P2 증분 검증 엔진을 채택하며, 다음을 포함한다:

### 1. Work Unit 모델

관찰된 DAG에서 유도된 11개 Work Unit(W1–W11)과 verify-contract의 G1/G2/G4/G6/G7 서브 스테이지를 first-class 객체로 정의한다. 각 Work Unit은 `{id, inputClosure, contract, toolchainFingerprint, command/recipe, producedArtifacts, canonicalOutputDigest}`를 가진다. 상세한 열거와 provenance는 `docs/spec/incremental_ci_contract.md` §2에 있다.

### 2. 종속성 폐쇄(Dependency Closure)

파일→모듈→빌드 타겟→gate→아티팩트→결과 추적 체인을 따른다. **보수적 과대추정(conservative over-approximation) 규칙**: 불확실한 모든 경계는 더 넓은 단위로 해결하며, under-approximation은 금지된다. 파일 수준과 시맨틱 종속성 수준 모두에서 계산한다.

### 3. 두 핵심 불변식

- **affected(U, Δ)**: `closure(Δ) ∩ inputClosure(U) ≠ ∅`이면 U는 AFFECTED. Skip은 `affected(U, Δ) == false`가 **provably**일 때만 허용.
- **reusable(U)**: `Fingerprint(U.inputs, U.contract, U.toolchain) == CachedFingerprint(U)`이면 U는 REUSABLE. **정확한 일치**만 재사용 허용; 캐시 미스 → 실행.

안전 속성: skip은 provably false일 때만, reuse는 exact fingerprint match일 때만. 동일 커밋+동일 그래프+동일 계약 → 동일 작업 단위 선택(결정성). Fail-closed.

### 4. 안전 Skip 사다리 L0/L1/L2

- **L0 (즉시)**: 문법/정적/타겟 로컬 — **초 단위**. Δ5(README), Δ7(단일 테스트 파일) — 95–100% savings.
- **L1 (변경 영향 검증)**: 일상 개발 반복 — **초~분 단위**. Δ2(debt_registry.json, ≈78%), Δ4(gate, ≈16%), Δ6(normative 문서, 캐시 키 wiring 후 ≈73–100%).
- **L2 (전체 인증)**: 병합/릴리스 경계 — **74분도 적절**. L2는 소거되지 않고 최종 인증으로 남음. 소거되는 것은 작은 변경이 L2 비용을 지불하는 것.

### 5. 캐시 키/지문 Wiring

`src/verification/obligation/identity.nim`의 기존 `CanonicalExecutionBundleFingerprint`(axiomExecutableDigest, axiomSourceDigest, lean/z3/lake/nimVersion, dependencyDigests, runtimeDigest, evaluationImplementationDigest) + `ExecutionContract`(platform, workdir, allowedEnv, fsBoundary, networkPolicy, mountedInputs, resourcePolicy) + `ExecutionIdentity = H(InputIdentity + ExecutionContractDigest + BundleFingerprint)`를 기반으로 다음을 확장:

- **Normative spec content hash**를 BundleFingerprint 또는 InputIdentity에 추가.
- **Per-sub-step fingerprints** within verify-contract (G1/G2/G4/G6/G7).
- **Per-gate `filesPattern` → content hash** in `GateRunRecord.executionFingerprint`.
- **ci-lake-build duration 측정** (G1 갭 해결).
- **호스트명/런너 식별자**는 지문에서 **명시적 제외**.

### 6. 문법적 역할 분류

Normative 문서(`docs/DEBT_REGISTRY.md`, `docs/agents/{architecture,core_rules,rules_workflow}.md`, `docs/spec/` 계약, `docs/history/audit_baseline_*`)는 해당 유닛을 AFFECTED로 만든다. Non-normative 문서(`README.md`, 마케팅, 변경 로그, 튜토리얼)는 0개 유닛을 영향. P1 발견(G4): normative-spec → cache-key invalidation이 **미연결**이며 P3에서 반드시 wiring해야 한다.

### 7. 범위 밖/연기

- `src/core` 전체 per-module import-graph 증분 컴파일 (Δ3/Δ8 hard long-tail) → **P3에서 연기**.
- 러너 upsize → **P7로 연기**.
- Authoritative-promotion 의미론 → **P4/review로 연기**.

## Alternatives Considered

- **전체 재계산 유지 (현재 상태)**: 매 변경에 대해 74분 대기. Rejected — 개발자 피드백 루프의 결정성을 저해하며, README 변경에 74분을 지불하는 것은 낭비.
- **경로 필터만 사용하는 coarse incremental**: `ci.yml`의 `paths-ignore`에 의존. Rejected — coarse filter만으로는 비-normative 문서(0영향)와 normatrive 문서(시맨틱 영향)의 구분이 불가능하며, Makefile 레시피 변경 시 W1–W9 전체가 재실행됨.
- **비결정적(판단 기반) skip**: 인간 판단에 의해 skip 대상을 결정. Rejected — §4에서 요구한 "provably false" 조건을 위반하며, theater의 온상이 됨.
- **last-build-existed 재사용**: "이전에 빌드가 존재했으므로 재사용". Rejected — `reusable(U)`는 **provable cache**(동일 입력/계약/도구체인 → 동일 결과)여야 하며, "마지막 빌드가 존재했다"는 조건이 아님.

## Consequences

### 구조적 결과

- **Work Unit 모델**: §2의 W1–W11 + G1/G2/G4/G6/G7이 first-class 객체가 되며, 입력 폐쇄와 측정 소요시간이 P1 보고서에 기반하여 문서화됨.
- **종속성 폐쇄**: §3의 파일→모듈→빌드 타겟→gate→아티팩트→결과 추적 체인이 결정적 함수로 구현됨.
- **불변식**: §4의 `affected(U, Δ)`와 `reusable(U)`가 모든 skip/reuse 결정에 적용됨.

### 안전 사다리 결과

- **L1이 일상 개발의 기본**: 작은 변경은 L1(초~분)만 지나야 하며, 이는 P2의 주된 가치 제안.
- **L2는 소거되지 않음**: 병합/릴리스 시 전체 인증이 유지됨.
- **과대추정 원칙**: 불확실한 경계는 넓은 단위로 해결 — under-approximation 금지.

### 캐시 키 결과

- **Normative-spec → cache-key wiring (G4)**: `readiness_start_gate.nim`과 contract-preservation gate가 normative 문서 변경을 자동 무효화.
- **Per-sub-step fingerprints**: Makefile 변경이 G1/G2/G4/G6/G7를 재실행하지 않음.
- **Per-gate filesPattern → content hash**: ci-gates가 변경되지 않은 gate를 건너뜀.
- **호스트명/런너 식별자 제외**: 동일 입력/계약/도구체인이면 동일 결과 산출.

### 프로세스 결과

- `data/decisions_graph.json`: 이 ADR은 마크다운 파일만으로는 `tools/sync_decisions.nim`이 trivially 재생성하지 않음 (이 도구는 `DecisionSpec`의 하드코딩된 ADR 목록과 `src/`의 `{.axiomDecision.}` pragma를 스캔하여 생성). **수동 편집하지 않음** — ADR-0017은 `DecisionSpec`에 추가되고 관련 소스에 `{.axiomDecision.}` pragma가 추가된 후 `nim r tools/sync_decisions.nim`으로 재생성되어야 함.
- 극장적 패턴 없음: 모든 skip/reuse 주장이 provably false여야 하며, `data/debt_registry.json`에 theater 마커로 등록.

## Amendment A1 (2026-09-23): 착지 실행 정책 확정 — main 착지 provenRequired(Δ)만, release tag full L2, 티어 소거 금지 명문화

> 사용자 확정 결정(2026-09-23)에 근거한다. **Ratified 2026-09-23, 사용자 확정 결정(AI 세션 승인 — AskUserQuestion 2채택 기록).**
> 본 Amendment는 `docs/spec/incremental_ci_tiers_scheduling.md` §3.2("L0 단독 실행 → L1/L2 스킵")와
> §5("Release tag / merge-to-main → L2 전체") 사이의 내부 긴장을 해소하며,
> 그 해석을 "merge-to-main 개별 착지 = provenRequired(Δ)만 실행, UNCERTAIN → full L2"로
> 확정한다. **L2 티어 소거 금지는 유지된다(티어 소거 금지 ≠ 개별 착지 전체 실행).**
> ADR-0019 §1·§5·Consequences, `docs/spec/certification_continuity_contract.md`
> §0·§7·§10(§10 nightly 불변), `docs/spec/productization_contract.md` §1(:21, ADR-0020
> carve-out)과 정합한다. 본 Amendment는 §-1 불변 파일(`AGENTS.md`,
> `src/gate/runners/import_encapsulation_gate.nim`, `config.nims` importEncapsulation
> block — AGENTS.md §-1)을 변경하지 않으며, 문서·계약 개정만을 포함한다. 구현 착지는
> 별도 승인 게이트를 따른다.

### A1.1 용어 확정 — `provenRequired(Δ)`

```
provenRequired(Δ) := { U | affected(U, Δ) == provably true } ∪ L0-baseline
                     (equiv. DependencyClosure(Δ, ContractGraph) ∩ {L0, L1})
```

- `affected(U, Δ)`는 ADR-0017 §3(`closure(Δ) ∩ inputClosure(U) ≠ ∅`)과 §4(안전 skip:
  provably false일 때만)에 따른다. L0 baseline(W3, W4/G7, W10, W11)은 영향 폐쇄와
  무관하게 항상 포함한다(`incremental_ci_tiers_scheduling.md` §2.1 유지).
- **UNCERTAIN**: 어느 Work Unit의 affected 판정이 provably 산출 불가능한 경우
  (ContractGraph/inputClosure 불완전, Makefile 레시피 변경, G4 normative-spec 캐시 키
  미연결 등으로 과대추정 경계가 전체 파이프라인으로 확산, 변경 지문 산출 실패)에는
  provenRequired(Δ) 집합이 결정적·완전하게 성립하지 않으므로 **Tier(C) = L2 전체**로
  fail-closed한다(ADR-0017 §2 보수적 과대추정의 극단 — under-approximation 금지 유지).
  UNCERTAIN은 결코 L1/L0으로 강등되지 않는다.

### A1.2 main 착지(merge-to-main) = provenRequired(Δ)만 실행

> **[AMEND 2026-09-29 — ADR-0025 Amendment B]**: push@main 트리거 폐기 — main 착지의 Actions 실행 = 0. 본 절의 `provenRequired(Δ)` 의무는 candidate(PR 게이트)가 승계(A1.2bis 연속)하며, 씨딩은 workflow_run `ci-cache-publisher`가 담당한다.

- main 착지(merge-to-main)는 `SelectedWorkUnits(Commit) = provenRequired(Δ)`만 실행한다.
- 판정이 **UNCERTAIN이면 full L2(전체 파이프라인, W1–W11 + W9)를 실행**한다.
- 이로써 기존 §5 표의 "merge-to-main → L2 전체" 적용 해석이 **"개별 착지 전체 실행"이
  아니라 "provenRequired(Δ)만"**으로 확정된다(ADR-0019 §5와 동시 정합 수정).
- `incremental_ci_tiers_scheduling.md` §3.2 "L0 단독 실행(비-normative 문서/캐시 히트 →
  L1/L2 스킵)" 규칙은 **PR 브랜치 푸시(개발 반복)에만** 적용되며, main 착지·릴리스
  경계에는 적용되지 않는다.

### A1.3 release tag = full L2 의무 + 운영 재정의 (현행 CI 9-job) — **[SUPERSEDED 2026-09-26 — ADR-0024 결정 #15]**

> **SUPERSEDED 2026-09-26 (ADR-0024 결정 #15 — release-boundary authority)**: 본 절의 발화 트리거(태그 push)와 수동 push 절차(:151-153)는 폐기된다 — 출하 경로는 release-ship.yml dispatch → freeze → full L2(runner-pool workflow_call, force_full) → environment 확인 → App의 v* tag 생성으로 이전된다. **full L2 의무 자체는 유지**(release 경계 = full L2)되며, 본 절은 역사 기록으로 보존한다.

- **release tag 생성 경로는 반드시 Tier(C) = L2 전체 파이프라인을 실행한다.**
  예외·생략·판정 의존 없음. release tag는 A1.2의 provenRequired(Δ) 경로가 적용되지
  않는다 — main 착지와 릴리스 경계는 구분된 별개의 정책 축이다.
- **full L2의 운영 재정의**: 계약의 W1–W11+W9 격자를 그대로 강행하지 않고,
  **"release tag full L2 = 현행 CI 전체 실행 9 jobs(ci-bootstrap + gateway-shard×8 +
  gateway-identity-gate, `.github/workflows/runner-pool-acceptance.yml`)"**로 운영
  재정의한다. 미실행 격자 **W1·W3–W7·W9–W11은 DEBT#466**으로 명시적 등재되어,
  격자 강행을 주장하는 허위 주장(M4 theater)을 차단한다. W2(ci-bootstrap)·W8(test-gateway)만
  현행 9-job에 근사 대응하며, 이는 계약상 격자 실행이 아닌 운영 정의다. 격자 실행은
  미래 CI 플랫폼에서의 설계 계약으로 유지된다.
- **태그 push는 수동 경유 — [SUPERSEDED 2026-09-26, ADR-0024 결정 #15]**: (기존) `ax release`의 로컬 annotated tag 생성과 수동 `git push origin <version>` 경로는 **폐기**된다 — v* tag 생성은 release-authority App 전용이며, release-ship이 검증·확인(release-authority environment) 후에만 태그를 생성한다. full L2는 태그 생성 **전**에 release-ship이 runner-pool workflow_call(force_full)로 위임 실행한다.

### A1.4 티어 소거 금지 명문화 (이 행위 ≠ 개별 착지 전체 실행)

- **L2 티어 자체는 소거되지 않는다.** 티어 모델(L0/L1/L2)과 L2의 최종 보증 지위는
  계약상 유지된다.
- **"티어 소거 금지"와 "개별 착지 전체 실행"을 구분**한다:
  - 티어 소거 금지 = L2 등급과 병합/릴리스 경계의 final-certification 지위 유지.
  - 개별 착지 실행 범위 = main 착지는 A1.2(provenRequired(Δ)만, UNCERTAIN → full L2),
    release tag는 A1.3(full L2 필수) — 이는 실행 정책의 축이며 티어 존재성과 독립적이다.
- 기존 금지 문구 **무효화 없음**: ADR-0017 §4("L2는 소거되지 않고 최종 인증으로 남음"),
  ADR-0019 Alternatives Considered("이진 L0/L1만 사용 (L2 제거): Rejected … L2는
  소거되지 않는다")는 그대로 유효하다.

### A1.5 nightly 백스톱 비도입

- 본 Amendment는 일반 착지(PR·main 착지)에 **nightly full-L2 backstop을 추가하지 않는다.**
- `docs/spec/certification_continuity_contract.md` §0(:31)·§7(:242-244)·§10(:345, :378,
  :394)의 nightly full L2 backstop(Phase 5c, 2026-09-11 적용, schedule 트리거 기반
  독립 backstop)은 **변경·확장되지 않으며** 그대로 잔존한다. 이는 본 Amendment와 독립적
  메커니즘이다.
- `incremental_ci_tiers_scheduling.md` §5 스케줄링 표에 "nightly" 행을 추가하지 않는다.
  일반 착지 시점의 보증은 A1.2(provenRequired(Δ) + UNCERTAIN→full L2)가 유일하다.

### A1.6 L2(M10) 재분류 — MUST → POLICY

- M10으로 식별된 "L2 필수 실행" 항목은 본 계약의 **MUST가 아닌 POLICY**로 재분류한다.
- 근거: `docs/spec/productization_contract.md` §1은 v1 non-goal로 "CI platform 자체
  (CI 실행·오케스트레이션 플랫폼)"를 명시하며(:21, ADR-0020 carve-out), L0/L1/L2 CI-tier
  스케줄링·착지 규정을 포함하지 않는다(동 문서 L2/landing/nightly/incremental 0건 — 본
  Amendment 조사로 확인). 따라서 일반적인 L2 실행은 제품 계약의 MUST가 아니라 미래 CI
  플랫폼 채택 시의 설계 방향(POLICY)이다.
- 예외 유지: A1.3의 release 경계 full L2는 POLICY가 아닌 **계약 MUST**다 —
  CI 플랫폼이 재개되면 릴리스 경계는 반드시 full L2를 수행한다 (발화 경로만
  ADR-0024 결정 #15로 이전 — release-ship → runner-pool workflow_call, force_full).

### A1.7 정합 개정 대상 (동시 번들)

- `docs/spec/incremental_ci_tiers_scheduling.md` §2.3 · §3.2 · §5 · §5.1
- ADR-0019 §1(L2 행) · §5 · Consequences
- ADR-0017 Status(본 Amendment 역참조 추가)
- ADR-0024(결정 #15 — A1.3 supersede) 착지 시 본 ADR(Status·A1.3·A1.6)을 포함한
  연쇄 문서(ADR-0019 §1·§5, `docs/spec/incremental_ci_tiers_scheduling.md`,
  DEBT#466, `docs/spec/repository_surface_contract.md` 결정 #15·#12(b),
  `docs/spec/certification_continuity_contract.md` §10.2, canonical_run_graph:72,
  rules_workflow:211)를 동시 정합한다 — 대상·문구는 ADR-0024 본문을 따른다.
- `docs/evidence/certification_continuity_production_2026-09-10.md:66,80,250`은 point-in-time
  증거 기록이므로 **수정하지 않는다**(5c cutover 적용 2026-09-11은
  `certification_continuity_contract.md` §10에 기록됨).
- 승인·ratification 흔적(Status 갱신, 근거 인용)은 §0.10/Decision Binding 준수 절차에 따라
  부가한다.

### 참조

- `docs/spec/incremental_ci_contract.md` — P2 계약 SSOT (전체 세부사항).
- `docs/reports/ci_observed_dag_p1_2026-08-28.md` — 관찰된 CI DAG (W1–W11 + G1/G2/G4/G6/G7 provenance).
- `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md` — Δ×work-unit 행렬 + §5.3 cache-key wiring 요구사항.
- `src/verification/obligation/identity.nim` — `CanonicalExecutionBundle`, `ExecutionContract`, `ExecutionIdentity`.

---

## Amendment A2 (2026-09-30): 독립 오라클 evidence 계약 비준 + landingFloor 조건부식 전환 (PR-B — "검증 비용 = 증명 필요 집합" 3-PR 계획)

> 본 Amendment는 계획 "검증 비용 = 증명 필요 집합"(PR-B 문서 트랙)의 오라클 도입·floor 조건부식
> 전환을 비준한다. 코드 결속: `tools/ci/impact_closure_selector.nim`(병렬 구현 — `loadOracleEvidence`,
> `DECISION-CPV-01/02` pragma, `oracleEvidence` envelope 필드). Epoch 기록: `docs/evidence/epoch_record_oracle_select_2026-09-30.md`.

### A2.1 oracle-evidence 계약 (schema `axiom/oracle-evidence/v1`)

- **형태**: select job의 독립 오라클이 작성하는 evidence 파일. 셀렉터는 **소비·검증만** 수행하며 verdict를 스스로 도출하지 않는다(자기참조 금지 — AGENTS.md §0.9).
- **필수 필드**: `schema`(= `axiom/oracle-evidence/v1`) · `axes`(5축 **전부** 객체로 존재: `executionClosure`·`productSurface`·`gateScanRoots`·`envHashInputs`·`identity`) · `derivedEmpty`(boolean) · `derivationDigest`(파일 정확한 바이트의 sha256).
- **검증 규칙**(셀렉터): JSON 파싱 · schema 일치 · 5축 존재 · `derivedEmpty` boolean · `derivationDigest` == `sha256sum` 재계산. 검증 실패 = **fail-closed — exit 2(full fallback)**, mode=none 절대 허용 안 됨.
- **∅ 허용(스키마 공집합)**: `derivedEmpty=true`(검증된 evidence)일 때만 선택 파생이 공집합으로 인정된다 — C15 반영 ①(`docs/spec/canonical_execution_semantics.md` 부록 D).
- **decision-text binding**: literal 토큰 `oracleEvidence` — `proof_unit_consistency_gate.nim:76-81` 패턴으로 본 Amendment와 코드가 동일 토큰을 공유한다(§0.10).

### A2.2 축의 정직한 열거 (C15 반영 ②)

`docs/spec/canonical_execution_semantics.md` 4계약 문장 1(:14)의 3축 규정 중 — ① 수기 `expectedAffected` 축(`data/selector_soundness/mutation_catalog.json`) 실존, ② "계약 §4.5" Makefile 의존 축은 **dangling 참조**(동 문서 §4.5 = InstantiationWitness 직렬화), ③ 독립 참조 구현 축은 **저장소에 부재** — 를 명시적으로 기록한다(DEBT#468). 본 Amendment는 오라클 계약의 실현 범위를 **현재 실존하는 evidence 경로(5축 evidence 파일)로 한정**하며, ②·③의 미실현은 정직하게 미실현으로 둔다.

### A2.3 CERTAIN-사유 분류 `derivedEmpty` (C15 반영 ③) + L0-baseline carve (C15 반영 ④)

- **③**: `planStatus=CERTAIN`의 사유 분류에 `derivedEmpty`를 추가한다 — 검증된 oracle evidence의 `derivedEmpty=true`로 선택 파생이 공집합임이 증명된 경우, CERTAIN 판정의 사유로 `derivedEmpty`를 기록한다(UNCERTAIN 사유 U1/U2(`canonical_execution_semantics.md` §5.2)의 대칭 분류 — 부록 D).
- **④**: L0-baseline carve — L0 단위(ADR-0019 §4·tiers §6.3 — 선택에 항상 포함되는 baseline)는 오라클 예측 대상 밖 carve로 기록한다. 단, **현행 CI에서 L0 격자 실행 자체가 미실현**(DEBT#466, DEBT#469)임을 병존 기록한다.

### A2.4 landingFloor 조건부식 전환 비준

- `tools/ci/impact_closure_selector.nim:1414`의 `let landingFloor = true`(무조건 착지-잡 실행)를 **`lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty`** 조건부식으로 교체한다 — 검증된 evidence의 `derivedEmpty=true`만이 floor를 해제하는 유일 조건.
- 비준 공백 기록: 기존 하드코딩에 대한 비준 의사결정 0건(2026-09-30 ADR·waiver grep 0 hits) — ADR-0025 Amendment C §(1).
- "영향-공집합 후보는 floor 면제" — 두 게이트 표면(`ci/checker.mk:191,:204-205` EMPTY=FAIL vs `runner-pool-acceptance.yml:661-666` EMPTY=PASS)의 정합은 **SL-09 승격 전 선행 조건**(DEBT#470).

### A2.5 Known-branch witness · L0 문장 불일치 역참조

- DEBT#466 (b+ 2026-09-30): Known-branch witness — 현행 9-job CI의 witness는 known branch 한정, 격자 프로젝션 밖 W4 클래스 미실현.
- DEBT#469: "영향 폐쇄가 공집합이어도 L0은 항상 실행" 문장(`docs/spec/incremental_ci_tiers_scheduling.md:28`)은 계약(설계)과 현행 CI(실행) 사이 불일치 상태로 기록.

### 참조 (A2)

- `docs/evidence/epoch_record_oracle_select_2026-09-30.md` — Freeze(`ci-frozen-2026-09-30`)/Record/Tombstone
- `docs/adr/0025-gateway-landing-authority.md` Amendment C(2026-09-30) — floor 비준·EMPTY 모순·mint [B2](c)·잔존 신뢰 경계
- `docs/spec/canonical_execution_semantics.md` 부록 D(2026-09-30 Amendment) — C15 4항목
- `docs/spec/incremental_ci_tiers_scheduling.md` Amendment(2026-09-30) — L0 문장 불일치·Known-branch witness
- `data/debt_registry.json` — DEBT#466(b+), DEBT#467–470

---

*작성일: 2026-08-28. P2 증분 검증 엔진 ADR. P1 관찰 보고서에 기반. 모든 Work Unit, 소요시간, 종속성은 P1 보고서에서 유도되었으며 UNKNOWN 항목은 정직하게 미기재됨.*
