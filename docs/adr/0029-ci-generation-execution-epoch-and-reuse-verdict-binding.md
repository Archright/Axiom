# ADR-0028: 세대·epoch 용어 분리, 재사용↔재현 구분, 캐시 파생 witness 승격 차단 (정정 기록)

## Status

**PROPOSED (2026-10-04)** — Workstream C 정정 기록. **범위: 용어·계약 정정 3건과
red-team 기각 기록.** 구현 변경을 승인하지 않으며, 어떤 산출물 authority도 새로 세우지
않는다. 변경된 계층은 `docs/spec/execution_accounting_contract.md` §15.0·§15.1·§15.4,
`docs/spec/verification_dag_contract.md` §3·§5·§12,
`docs/spec/merge_admission_controller.md` §2b, 그리고 L1 관측 절차
(`docs/agents/merge_admission_observation.md`)다.

> 번호: `0028`은 기존 `docs/adr/`에 없으므로 충돌하지 않는다(최고 기존 번호 `0027`).
> 저장소에 ADR 색인 파일이 없다 — 본 ADR이 색인을 만들지 않는다.

## Context

authority/identity/DAG 구조 개선 계획에 세 개의 독립 red-team이 검토했고, 각각 **구체적으로
인용 가능한 결함**이 확인되어 채택된 정정 3건이 있다. 세 건은 공통으로 **성능 개선이 아니라
correctness 수정**이다 — 각각은 잘못된 결론을 유발하는 구조적 혼동 자체를 제거한다.

기록 근거: `docs/evidence/ci_epoch_record_2026-10-04.md`(freeze tag
`ci-epoch-pre-authority-structure-2026-10-04`, HEAD `959b1fd8`).

## Decision 1 — `ciGeneration`과 `executionEpoch`을 분리한다

**결정**: 무관한 두 양을 "epoch"로 부르지 않는다.

| 이름 | 정의 | identity 역할 |
|---|---|---|
| **`executionEpoch`** | `validatedAtEpoch == ctx.currentEpoch`, `currentEpoch = sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)` | **identity 성분** |
| **`ciGeneration`** | `.github/workflows/` 토폴로지 세대 (AGENTS.md §2.5 컷오버 산출물) | **절대 identity 성분 아님** |

**왜 correctness인가**: 계획은 이 두 축을 한 이름 아래 두었다. 결과적으로 (a) CI 세대 번호가
identity digest에 결합될 여지가 생기고, (b) 실행 closure의 실제 변화가 CI 세대 변화로 오독될
여지가 생긴다. 둘 다 identity/verdict를 **오염**시키므로 성능 문제가 아니다.

**wire 필드 안정성**: `currentEpoch` / `validatedAtEpoch` 이름은 유지한다. 이는 용어 정정이지
스키마 변경이 아니다 — 별도의 명시적 결속 마이그레이션 없이는 이름을 바꾸지 않는다.

**셋째의 의미**: `docs/spec/merge_admission_controller.md` §2b의 queue-journal epoch
(ADR-0020 D7)와 `docs/spec/cache_policy.md`의 gate-memo namespace epoch는 또 다른 축이다.
`merge_admission_controller.md` §2b에 무기호 "epoch" = queue-journal epoch로 고정하는 문단을
두었다.

정본: `execution_accounting_contract.md` §15.4 · `verification_dag_contract.md` §3·§12 ·
`merge_admission_controller.md` §2b.

## Decision 2 — 캐시 적중은 "재현"이 아니라 "재사용"이다

**결정**: 캐시 적중은 **prior result의 재사용**이며, 현재 문맥에 대해 **재검증된** 경우에만
**authoritative reuse**가 된다.

- per-read 재도출이 근거다: condition (d)는 artifact 바이트를 **다시 읽고** 매 read마다 SHA-256을
  **재계산**한다(recorded claim 신뢰 아님).
- fail-closed: 불확실(파일 부재·손상 JSON·스키마 불일치·digest 불일치) → **cache miss → 재실행**
  (`workunit_fingerprint_cas_contract.md` §6.1-§6.2).
- **negative half는 보존한다**: 캐시는 가속일 뿐 **증거가 아니며 판정 입력도 아니다**(J3,
  `docs/spec/github_delegation_residuals.md:7`). 단, "캐시가 실행-의미론 입력이 아니다"로
  과잉 교정하지 않는다 — 캐시가 검증 의미론을 바꾸는 경로가 판정 대상이다
  (`docs/spec/ci_optimization_tcb_judgments.md` §3.1).

**왜 correctness인가**: "reproduction"은 실행이 **다시 일어났음**을 함의하므로, 캐시 적중 행을
fresh execution 증거로 읽는 유일한 통로를 만든다. 그 통로를 명시적으로 차단한다.

정본: `execution_accounting_contract.md` §15.0 · `verification_dag_contract.md` §5 ·
`merge_admission_controller.md` §2b.

## Decision 3 — witness 차단 범위를 **캐시 파생 승격**으로 한정한다

**결정**: 금지되는 것은 **cache-derived state를 fresh-execution witness로 승격하는 것**이다.
`orchestrationVerified`나 `FreshExecutionObservedSet` 자체의 쓰기를 무조건 차단하지 않는다 —
**genuine fresh execution은 계속 `orchestrationVerified`를 설정하고
`FreshExecutionObservedSet`에 진입할 수 있어야 한다.**

범위 안(그리고 이것만): `SatisfactionSource = REUSED`인 행(§15.3 basis 미확립 REUSED 행 포함)은
(a) `orchestrationVerified`로 세어지지 않고, (b) `FreshExecutionObservedSet`에 진입하지 않고,
(c) TrustCommit verified set에 진입하지 않는다. 범위 밖: genuine fresh execution 행은
평소대로 두 필드를 모두 설정한다.

**왜 correctness인가**: 넓은 판독("witness 필드를 전부 차단")은 **실제 검증 결과를 기각**한다.
fresh execution을 우회해야만 PASS가 나오는 시스템은 계약이 아니라 theater다(AGENTS.md §0.9).
좁은 판독은 남는 유일한 부정은 "실행되지 않은 것을 실행된 것처럼 승격"이다.

정본: `execution_accounting_contract.md` §15.1 차단 범위 문단.

## Rejected — red-team에서 **기각**되어 재제안 금지

**(a) `ci-cache-publisher`를 producer post-step `actions/cache/save`로 대체.**
**기각. 근거 2가지:**
1. GitHub 캐시는 **branch-scoped**다. PR-scoped 저장은 다음 PR에서 보이지 않으므로 교차-PR
   재사용 목적이 성립하지 않는다.
2. 게이트 경계가 바뀐다. publisher는 **run 수준**에서 게이트하고, producer post-step은
   **job 수준**에서 게이트한다 — gate granularity 축소.
속도 개선처럼 보이지만 캐시 도달 범위와 gate 해석을 함께 바꾸므로 채택 불가.

**(b) producer/workflow identity를 artifact identity에 결속.**
**기각. 근거:** `docs/spec/provenance_contract_v3.md`와 identity 계약
(`src/verification/obligation/identity.nim` — "Identity digests exclude provenance
(observedAt, timestamps, randomness)")이 provenance의 identity digest 진입을 금지한다. 추가로
"재실행은 identity를 변동시키지 않는다"(AGENTS.md §2.6)를 위반한다 — 같은 산출물을 다시 만든
것뿐인데 identity가 바뀌면 reuse가 성립하지 않는다.

**(c) `orchestrationVerified` 쓰기를 전부 차단.**
**기각 → Decision 3으로 narrowing.** review가 지적한 대로 과다하다. genuine fresh execution을
차단하면 계약을 잘못 구현한다.

## 잔여 결함 — in scope (코드는 동시 작업자가 이미 착지, 2026-10-04 관측)

`platform = "linux-x86_64"`이 리터럴 하드코딩되어 있었다
(`src/cli/axiom_engine.nim`, `src/verification/obligation/canonical_verification.nim`).
CI는 `ubuntu-24.04-arm`에서 실행되므로 **arm 경로에서 `executionConfigDigest`의 arch 축이 판별
정보를 전혀 전달하지 않았다** — arm 산출물과 x64 산출물이 동일한 실행 정체성을 갖는다.

**불변식** (AGENTS.md §0.2 Fundamental — 하드코딩 예외 없음):
`ExecutionContract.platform`은 실제 실행 호스트의 os/arch를 반영해야 하며 고정 리터럴은
금지다. `identity.nim`은 이 필드를 os/arch identifier로 정의하고 `executionContractDigest`가
이를 해시 성분으로 쓴다 — 값이 고정되면 축 자체가 사라진다. **identity 축이 값을 잃는 것은
성능 손실이 아니라 identity 손실이다.**

**관측 (2026-10-04 08:36 KST)**: 동시 작업자가 착지시켰다 — 계약 조립이 단일 측정 지점
`src/verification/accounting/execution_context.nim`으로 모였고 `platform = identity.hostPlatformId`
(`identity.nim:115`, 컴파일 타임 `hostOs`/`hostCpu`)에서 온다. 리터럴 잔존 없음
(`grep 'platform = "linux-x86_64"'` → 0건). 동시에 wire 필드 `currentEpoch` / `validatedAtEpoch`는
그대로 유지되고 신규 식별자만 `executionEpoch` 계열로 명명되어, Decision 1의 호환성 단서를
지켰다. **본 ADR은 그 코드의 승인이 아니다** — 위 불변식과 기각 근거만 기록한다.

기록: `docs/evidence/ci_epoch_record_2026-10-04.md` §7.3.

## Consequences

- `execution_accounting_contract.md`에 §15.0(재사용≠재현)·§15.4(epoch 분리)가 신설되고
  §15.1에 차단 범위가 명시되었다. 기존 §15.2/§15.3 불변식은 변경·약화되지 않는다.
- `verification_dag_contract.md` §3 NodeIdentity 성분에 `ciGeneration` 비결속이 금지되고 §12
  금지 목록에 추가되었다.
- `merge_admission_observation.md` L1이 이름 검사에서 **바인딩 5종 검사**(workflow_id ·
  workflow_path · head_sha · 트리 독립 재도출 · 결론 정확 일치)로 확장되었다. 이는
  `merge_admission_controller.md` §2b/§3이 이미 요구하는 것을 관측 절차가 기계 판독하게
  만든 것이며, **불변식을 새로 정의하지 않는다**.
- `currentEpoch` / `validatedAtEpoch` wire 이름은 불변 — 본 ADR은 마이그레이션을 승인하지 않는다.

## Cross-references that still need updating (NOT edited here — outside this workstream)

1. `docs/agents/ci_epoch_cutover.md` — §2.5 절차 문서가 "epoch cutover"를 계속 사용한다.
   `ciGeneration` 명칭은 본 ADR이 정의했지만 해당 절차 문서는 소유 범위 밖이므로 수정하지
   않았다. 후속 작업 필요.
2. `docs/agents/operations.md` — dirty(타인 소유). merge-boundary 절차가 본 ADR의 용어를
   사용해야 하는지 확인 필요.
3. `src/verification/accounting/run_accounting.nim` — 동시 편집 중인 소유자 영역. wire 필드명
   `currentEpoch` / `validatedAtEpoch`는 **그대로 유지**해야 한다(위 안정성 단서).
4. `docs/spec/github_delegation_residuals.md` / `docs/spec/productization_contract.md` /
   `docs/spec/provenance_contract_v3.md` / `docs/spec/architecture_v2.md` /
   `docs/spec/decision_binding_framework.md` / `docs/DEBT_REGISTRY.md` — dirty(타인 소유).
