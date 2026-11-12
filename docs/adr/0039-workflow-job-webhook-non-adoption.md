# ADR-0039: workflow_job Webhook 미도입 — API census 관측 권위 유지

## Status

Accepted (2026-11-02)

## Context

Axiom의 CI 제공자·런타임 관측 권위는 **REST API census**다: 정의된 모집단
(`created_at ≥ T` 등)에 대해 workflow run을 전수 열거하고, run별 job을
`filter=all`로 전수 조회해 **assignment metadata**(`runner_group_id`,
`runner_name`, steps)로 분류한다. 이 관측 방식은 2026-11-01 GHEC 복귀
acceptance에서 이미 **종결 증거를 생산했다** — Ubicloud-0 전수조사
(48h lookback 3,090 run / 잡 전수, `runner_group_id==1` K=0,
api_failures=0)와 재관측 census(영구 원장
`data/ci_provider/census_20261101T125932Z/`)가 그 실측이다
(`docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` §3·§5·§6).

이 완결성 대비 **비용·실시성 최적화 후보**로 `workflow_job` webhook 기반
관측(잡 상태 전이의 push 수신)이 제기될 수 있다. 도입 판단에 앞서 플랫폼
팩트를 공식 문서(docs.github.com — Context7 `/github/docs` 소스 확인,
2026-11-02)로 고정한다.

### 플랫폼 팩트 (documented — 인용)

| # | 팩트 | 근거 |
|---|---|---|
| F1 | `workflow_job` webhook의 `action`은 잡 생애주기 4종 — `queued`/`in_progress`/`completed`/`waiting` — 이다. | Webhook events and payloads — workflow_job (docs.github.com/en/webhooks/webhook-events-and-payloads#workflow_job). 자동 스케일링 문서도 "contains an `action` key that corresponds to the stages of a workflow job's life-cycle; for example when jobs are `queued`, `in_progress`, and `completed`"로 서술(self-hosted-runners.md) |
| F2 | `queued` 시점에 runner 필드는 null일 수 있다. | REST "Get a job for a workflow run" 스키마 — `runner_group_id`: "The ID of the runner group to which this job has been assigned. (If a runner hasn't yet been assigned, this will be null.)" — quirks Q12 동일 근거 |
| F3 | "GitHub does not automatically redeliver failed deliveries." | Handling failed webhook deliveries (docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries) |
| F4 | 배달 실패 기준 타임아웃은 **10초**(fpt/ghec, 2XX 응답 필요; GHES는 30초) — 수신기가 10초 내 2XX로 응답하지 못하면 그 배달은 실패로 기록되고 재전달되지 않는다(F3). | 같은 페이지: "if your server is down or takes longer than 10 seconds to respond, GitHub will record the delivery as a failure" |
| F5 | 실패 배달의 수동 재전달(redelivery)은 유한 보존 창 내에서만 가능하다. 공식 문서는 보존 기간을 **템플릿 변수**로만 서술한다("all deliveries from the past {% data variables.webhooks.retention %} days will be listed"); 이 저장소 콘솔 관측값은 **3일**이며, 본 ADR은 이 값을 관측값으로 기록한다 — **실측 확정 필요**(다른 계정/시점에서 달라질 수 있는 값이다). | Recent deliveries 표기(webhooks 문서 reusables) + 콘솔 관측(2026-11-02) |
| F6 | GitHub App은 이벤트 구독에 해당 이벤트의 최소 권한(예: Actions read)을 요구하며, **App당 webhook은 1개**다. | Using webhooks with GitHub Apps (docs.github.com/en/apps/creating-github-apps/registering-a-github-app/using-webhooks-with-github-apps) — 구독은 앱 권한(예: Issues → Contents read 예시)과 연동 |
| F7 | 중복 식별은 `X-GitHub-Delivery` 헤더로 하고, **재전달 시 동일 ID**가 유지된다: "If you request a redelivery, the `X-GitHub-Delivery` header will be the same as in the original delivery." | Best practices for using webhooks (docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks) |
| F8 | 공식 주의 문구: "This approach relies on the timeliness of webhook delivery for making scaling decisions, which can introduce delays and reliability concerns. Consider using Actions Controller or the Scale Set Client for larger volume autoscaling scenarios." | Self-hosted runners — Webhooks for autoscaling (docs.github.com/en/actions/reference/runners/self-hosted-runners) |

## Decision

**`workflow_job` webhook을 도입하지 않는다. 기존 API census가 자기완결적
관측 권위로 유지된다.** 근거는 셋이다.

1. **census는 이미 검증된 종결 증거를 생산했다.** 2026-11-01 Ubicloud-0
   전수조사와 재관측 census는 "모집단 정의 + 전수 열거 + assignment
   metadata 분류 + 오염 fail-closed(Q18)"의 조합으로 관측 완전성을 증명한
   실측이다. 관측 권위를 검증 없는 새 차량으로 교체할 이유가 없다.
2. **webhook은 비용 최적화 후보일 뿐이다.** census가 사건 기반 일회성
   전수조사인 데 반해 webhook은 상주 수신기·URL·보안(서명 검증)·운영을
   요구하는 인프라다. "실시간성"은 이 저장소의 관측 목적(acceptance 종결
   증거)에 필수 조건이 아니며, 비용 절감 여부 자체가 실측 대상이다(재평가
   조건 ④).
3. **이벤트만으로 관측 완전성을 주장할 수 없다.** F3(자동 재전달 부재)·F4
   (10초 타임아웃)·F5(유한 보존 창)에 의해 배달은 최선 노력(best-effort)이고
   누락이 구조에 내장된다. F2에 의해 `queued` 시점 페이로드는 runner
   identity 결측을 허용한다 — provider identity 판별식(quirks Q7/Q12,
   `runner_group_id` 기반)의 수신 시점 적용 가능성이 페이로드만으로는
   보장되지 않는다. 또한 F8에서 GitHub 공식 문서 자체가 webhook 기반
   자동화에 delays/reliability concerns를 명시하고 더 큰 볼륨에는 다른
   차량(Actions Controller/Scale Set Client)을 권고한다. 이벤트 스트림을
   관측의 **전부**로 쓰는 설계는 "받지 못한 이벤트 = 없던 사건"이라는
   fail-open 함정이며, AGENTS.md §0.9(극장 금지)·§4(검증 불가 증거 =
   fail closed)와 정면 충돌한다.

재평가는 다음 **4개 조건이 모두 실측으로 충족될 때만** 연다 — 어느 하나라도
"가정"으로는 재개하지 않는다.

| # | 조건 | 실측 내용 |
|---|---|---|
| ① | **실 payload에 필요 runner identity 존재 실측** | 실제 `workflow_job` 페이로드(`completed` 시점 포함)가 provider identity 판별에 필요한 필드(`runner_group_id` 등)를 실제로 담는지를 수신 실측으로 확인한다. F2의 null 가능성과 별개의 측정이다 — 문서 스키마 추정이 아니다. |
| ② | **reconciliation 누락·중복 측정** | 일정 기간 webhook 스트림과 동일 기간 API census를 대조해 이벤트 누락·중복률(F3/F4/F5의 구조적 누락이 실제 얼마나 발생하는가)을 정량 측정하고, 그 차이를 메꾸는 reconciliation 경로가 성립함을 보인다. |
| ③ | **수신 기질 확보** | webhook 수신기는 어딘가 상주해야 한다. 수신 기질은 Northflank 전환 계약(`docs/spec/northflank_control_plane_transition_contract.md`)과 동일한 operator 기질 문제 — 제어기 배치 3제약(C1 자기참조·C2 폴백 공급자 위 배치·C3 GHEC 과금) — 를 그대로 상속한다. 기질 없는 수신기 설계는 재평가 대상이 아니다. |
| ④ | **실제 절감 > 수신기 유지 비용** | census의 실측 비용(전수조사 시 API rate 소진·실행 시간)과 수신기의 유지 비용(상주 인프라·운영·모니터링)을 실측 비교해 절감이 양수임을 보인다. census가 사건 기반 일회성인 현재 사용 패턴에서는 절감이 기본적으로 미확정이다. |

## Consequences

- **관측 권위 불변**: REST API census 관례(모집단 정의·전수 열거·id 기반
  분류·오염 fail-closed)가 유일 관측 권위로 유지된다. CI 제공자 관측·
  acceptance 종결 증거는 계속 census로 생산한다.
- **실행 경계 무변경**: 신규 워크플로·App·수신기 인프라를 만들지 않는다
  (AGENTS.md §0.12 — 계약과 무관한 서브시스템 미생성; §2.5/§2.6 — 실행
  경계 변경 없음).
- **재개 통제**: webhook 도입 논의는 위 4조건의 충족 실측 없이 재개하지
  않는다. 4조건은 이 ADR의 일부이며, 충족 관측은 별도 증거 기록으로 남긴다.
- **비용 문제의 정직한 보존**: 본 결정은 census의 비용(대규모 전수조사의
  rate 소진 등)을 부정하지 않는다 — 비용 최적화는 유효한 후보이며 ④가 그
  검증 경로다. F5의 관측값(보존 3일)은 실측 확정 필요 항목으로 남는다.
- **역사적 참조**: F1–F8의 문서 팩트는 도입 재검토 시 다시 fetch해
  확인한다 — 본 ADR의 인용은 2026-11-02 시점 스냅샷이다.

## References

- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` —
  census 종결 증거 실측(§3·§5·§6), Q18 오염 fail-closed 계약
- `data/ci_provider/census_20261101T125932Z/` — 재관측 census 영구 원장
- `docs/spec/ci_provider_failover_quirks.md` — Q7/Q12(provider identity
  실측 predicate — `runner_group_id` 기반), Deterministic rule 7
- `docs/spec/northflank_control_plane_transition_contract.md` — 수신 기질이
  상속하는 제어기 배치 3제약(C1–C3)
- docs.github.com — Webhook events and payloads(`workflow_job`), Handling
  failed webhook deliveries, Best practices for using webhooks,
  Using webhooks with GitHub Apps, Self-hosted runners(autoscaling),
  REST "Get a job for a workflow run" (전부 2026-11-02 Context7 `/github/docs`
  확인)
