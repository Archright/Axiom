# 거버넌스 잔여 — 단독 운영·G3·#35·정책 설명 (2026-11-20)

> **Status**: 기록(record). 본 문서는 **이미 존재하는 잔여를 사실대로 고정**하며, 코드·워크플로·정책·ruleset을 변경하지 않는다.
> **Created**: 2026-11-20
> **선행 기록**: `docs/evidence/breakglass_trust_surface_landing_2026-11-20.md`, `docs/evidence/ci_critical_path_baseline_2026-11-20.md`

## §0. 목적

프로그램의 잔여 항목 중 **코드로 해결할 수 없는 것**과 **지금 변경하면 이득보다 위험이 큰 것**을 분리해 기록한다. 각 항목은 "현재 상태 / 왜 지금 바꾸지 않는가 / 어떤 조건에서 재검토하는가"로 닫는다.

## §1. 단독 운영 — 독립 인간 승인 부재

| 항목 | 사실 |
|---|---|
| operator | `wintrover` — sole `@Archright/architect` member |
| 독립 리뷰 | 없음. PR #230의 `reviews`는 빈 배열이다 |
| App 판정과 merge | PR #230은 required `admission-check`(App `5795152`)가 `failure`인 상태에서 수동 merge됐다 |
| 자동화의 한계 | agent를 늘리거나 App을 추가해도 동일 운영자 통제 아래에서는 독립 승인이 아니다 |

**결정**: Axiom은 현재 독립적인 두 번째 인간 승인을 **주장하지 않는다**. break-glass는 사람의 권한 행사로 기록하며, App 성공으로 표현하지 않는다. 독립 승인이 제품 필수 조건이 되는 시점에만 외부 권한자를 도입한다.

## §2. G3 — expected-source App `5795152` 유지

| 항목 | 값 |
|---|---|
| App | `5795152` (`axiom-admission-verifier`) |
| 근거 | ruleset `27097366`의 required context `admission-check` integration_id, `27525972`도 동일 |
| 현재 결함 증거 | 없음 |

**결정**: 교체하지 않는다. App 교체는 코드 PR이 아니라 **신뢰 앵커 이전**이다. 필요해지면 (1) 현재 ruleset·App 설정 기록, (2) 새 App의 동일 판정 계약 검증, (3) expected-source 변경, (4) 구 App이 required check를 충족할 수 없음 확인, (5) required checks·bypass 재확인 순서로 별도 수행한다.

## §3. #35 — `script_hash` 과잉 무효화 (WONT_FIX 유지)

`setup-axiom-toolchain/action.yml`의 주석만 바뀌어도 `script_hash`가 바뀌어 A/B 캐시가 무효화된다. 실행 의미는 변하지 않는다.

**결정**: WONT_FIX 유지. 캐시는 가속 수단이며 증거가 아니다(§0.9). 의미 부분만 해시하는 변경은 YAML 구조·shell·입력·조건의 분리를 요구해 신뢰 경계에 복잡성을 더한다. **반복 측정된 무효화 비용**이 확인될 때만 재검토한다.

## §4. `frozenExceptions` rationale 불일치 — 다음 정책 변경 때 정리

`config/repository_surface.json`의 `frozenExceptions` rationale에는 "setup action은 FROZEN"이라는 이전 상태 설명이 남아 있으나, 실제 정책은 전용 `trust-supply-path` 그룹을 우선 적용한다. 기계 판정에는 영향이 없다.

**결정**: 지금 수정하지 않는다. 이 파일은 보호 대상이며, 설명 한 줄을 고치기 위해 권한 절차를 여는 것은 과도하다. **다음 실제 정책 변경**에서 기계 판정 데이터와 사람 설명을 함께 정리한다. 장기적으로 기계 판정 데이터와 사람 설명의 분리는 별도 계약 개정으로 검토한다.

## §5. CI provisioning — 캐시 도입이 아니라 분해가 다음 단계

측정(5 merge_group runs): `setup-axiom-toolchain` 포함 step 2,574s = 4,669 step-seconds의 55.1%. 호출 36회/5 run, 6회는 0s, median 39.5s, p75 56s, max 253s.

`setup-axiom-toolchain/action.yml`은 이미 exact-key + digest + provenance probe의 **검증된 2-layer memo**를 구현한다(캐시 HIT도 verdict를 재계산). 따라서 "캐시가 없다"는 전제의 최적화는 성립하지 않는다.

**결정**: 다음 단계는 **action step 로그 수준의 구성요소 분해**(다운로드/설치/복원/검증)다. 분해 없이 캐시 키나 설치 경로를 바꾸지 않는다. 이 action은 trust surface이므로 어떤 변경이든 MUST-T2a 위임과 break-glass 기록을 요구한다.

## §6. 이 기록이 하지 않는 것

- ruleset·required check·App·정책 파일을 변경하지 않는다.
- 독립 승인이 있었다고 주장하지 않는다.
- `frozenExceptions` rationale을 이 PR에서 수정하지 않는다.
- #35를 재개하지 않는다.
- 캐시를 증거로 취급하지 않는다.
