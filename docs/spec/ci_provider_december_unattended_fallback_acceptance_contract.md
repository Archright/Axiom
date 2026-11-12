# CI Provider — 12월 무인 폴백 복귀 Acceptance 사전계약 (판정 기준 사전 고정)

> **종류**: 운영 acceptance 사전계약(pre-contract) — 2026-12-01 이후 청구주기에서
> Ubicloud 폴백 → (가용 시) GHEC 복귀가 **무인으로** 발생해야 함을 검증하기 위한
> 판정 기준을 **사건 이전에** 고정한다. 본 문서는 관측 대상·판정 어휘·증거 세트의
> 정의만 규정하며, 실 관측·판정 수행은 12월 사건 이후의 **별도 작업**이다
> (AGENTS.md §2.2 — 관측 전 완료 주장 금지).
> **상태**: 사전계약 확정(2026-11-02). 판정 기준은 §2가 유일 정본이며, 12월
> 결과 이후의 기준 변경은 §2.4의 금지 조항에 묶인다.
> **선행 문서**: `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md`
> (GHEC 복귀 acceptance 8항목 증거 세트 — §6 잔여에 "12월 자동 무인 폴백 경로
> 최종 확인은 다음 폴백 주기의 자동 발화로만 종결 가능"이 기록돼 있다),
> `docs/evidence/ci_provider_canary_fix_epoch_2026-11-01.md`(canary 검증 술어
> 수리 epoch), `docs/spec/ci_provider_failover_quirks.md`(Q1–Q18),
> `docs/evidence/ci_provider_monthly_trial_2026-10-24.md`(월간 trial 런북).

## 1. 대상 경로와 메커니즘 (기존 정본 참조)

무인 폴백 복귀는 다음 4단계 사슬이며, 각 단계의 구현체는 이미 main에 착지해
검증돼 있다 — 본 계약은 새 메커니즘을 만들지 않고 기존 메커니즘의 **무인 발동
결과**를 판정한다.

1. **스케줄 발화** — `ci-provider-router.yml`의
   `schedule: cron '7,37 * * * *'`(30분 재조정 계약). UBICLOUD_ACTIVE 상태에서
   월간 trial 창(매월 1–3일 UTC, 주기당 최대 3회, same-day 재시도 금지, 직전
   시도 후 20h gap, reserve-then-dispatch) 안에서만 `ghec-canary`를
   dispatch한다. schedule은 Q10 실측상 **늦고 불규칙한 best-effort 차량**이다
   (30분 cron이 시간 단위 간격으로 발화) — 이것이 판정 기준 1의 "발화 확인"
   범위를 규정한다(§2.1 각주).
2. **canary dispatch → 실제 실행·판정** — `ghec-canary.yml`
   (`workflow_dispatch`, inputs `nonce`+`period`)이 GitHub-hosted 러너에
   실제 배정돼 identity 판별식을 판정한다: `runner_id > 0 ∧ runner_group_id
   == 0 ∧ runner_group_name == "GitHub Actions" ∧ runner_name 접두어 +
   identity-verify step 성공`(M9/M12 — 이 저장소 전용 실측 predicate,
   quirks Q7/Q12). canary는 CI_RUNNER_MAP을 절대 읽지 않는다(M6).
3. **Router 전이** — canary 성공 시 라우터가 CI_RUNNER_MAP을 GHEC로 전이한다
   (`mode=ghec / GHEC_ACTIVE / generation++ / last_transition_reason=
   GHEC_TRIAL_SUCCESS` 계열). 라우터는 **단일 writer**다(concurrency group
   `ci-provider-router` + `cancel-in-progress: false` + `queue: max` —
   quirks Q5).
4. **복귀 수용 기록** — 전환 이후 **생성된** required run 관측에서
   `executed > 0 ∧ blocked = 0 ∧ all_ghec`이면 라우터가
   `return_acceptance=confirmed` + `return_acceptance_run_id`를 기록한다.
   이것은 **공급자 수용**(실제 required 잡이 GHEC에서 실행됐다는 identity
   증명)이며, 병합 수용(PR의 required checks + native MERGE)과 별개 판정이다
   (복귀수용 문서 §4). 실행된 failure도 `GHEC_RETURN_EXECUTION_FAILURE`로
   confirm한다. **rerun은 증거 아니다**(quirks Q12 rerun 의미론).

## 2. 사전 고정 판정 기준

### 2.1 성공

아래 3요소가 **전부** 관측될 때만 성공이다. 하나라도 빠지면 성공이 아니다.

| # | 요건 | 관측 대상 |
|---|---|---|
| S1 | **스케줄 무인 발화 확인** | 12월 관측 창(§3) 내 `ci-provider-router`의 `event=schedule` run 존재(run ID·GitHub-clock created_at) + 잡 로그 decision line이 trial 발동을 기록 |
| S2 | **canary 실제 실행·판정 결과 확인** | dispatch된 canary run(`run-name: ghec-canary <nonce>` 결속 — quirks Q6/H20)이 실제 실행됐고(0-step 차단 아님 — `runner_id > 0 ∧ steps > 0`), identity 판별식 판정 결과(성공)가 step 로그로 관측됨 |
| S3 | **Router 승인 전이 + 증거 기록** | CI_RUNNER_MAP GET(전이 후 byte-compare 원문): `mode=ghec, state=GHEC_ACTIVE, generation 증가, return_acceptance=pending` → 이후 `return_acceptance=confirmed` + `return_acceptance_run_id`(전환 이후 generation에 속하며 GHEC 실행을 입증한 run — 복귀수용 문서 §4 조건) + 라우터 run 로그의 전이·수용 발화 + 수동 PATCH 부재(단일 writer 관측, §5) |

**S1 각주(발화 범위)** — schedule은 Q10 실측상 늦거나 불규칙하므로, "발화
확인"의 기준은 nominal 30분 cadence가 아니라 **관측 창(§3) 내 schedule event
run의 존재**다. 지연 자체는 성공 판정을 무효화하지 않는다.

### 2.2 실패 (canary 실패 → escalation)

- canary가 실제 실행됐으나 identity 판별식을 통과하지 못했거나(WRONG_PROVIDER,
  exit 1), 0-step 예산 차단(Q1/Q11)으로 실행에 도달하지 못한 경우 — 라우터는
  fail-closed로 Ubicloud를 유지하고 `last_trial_result=failed`를 기록한다.
  **이것은 자동 전이 금지가 정상 동작인 상태다.**
- 창 내 자동 재시도는 월간 trial 계약(같은 날 재시도 금지 · 직전 시도 후 20h
  gap · 주기당 최대 3회)에 따른다. 시도가 소진됐는데도 복귀가 없으면
  **운영자 escalation**으로 이동한다: 수동 진단 경로
  (`workflow_dispatch` `force_trial` — 창/same-day/gap/횟수 상한 우회,
  시도 counter 미소비, UBICLOUD_ACTIVE 전용)를 사용할 수 있으나, 전이는
  라우터의 승인 경로로만 기록된다. 런북:
  `docs/evidence/ci_provider_monthly_trial_2026-10-24.md`.
- canary 실패 원인이 검증 술어 결함(Q16류)이면 — 11월 선례(PR #1160 수리 +
  force_trial 수용)와 동일하게 — 수리 PR과 별개 수용 기록으로 종결한다.
  수리 이후의 무인 재검증은 다음 발화 기회에 따른다.

### 2.3 UNKNOWN (증거 불충분 → Ubicloud 보수 유지, 성공 취급 금지)

S1·S2·S3 중 **하나라도 관측 불가·불충분**이면 결과는 UNKNOWN이며, Ubicloud
보수(fail-closed)를 유지하고 **성공으로 취급하지 않는다**. "일부 증거가
좋아 보인다"는 나머지 요건의 갚음이 되지 않는다(AGENTS.md §4 — 검증 불가/
오래된 증거 = fail closed; 복귀수용 문서 §3의 "관측 불가 = 일치 아님" 원칙).

### 2.4 사후 기준 변경 금지 (명문화)

12월 결과를 **보고 나서** 본 기준(§2)을 고쳐 결과를 성공으로 만드는 것을
금지한다. 기준 개정은 12월 결과와 무관한 사전 개정(별도 PR + 개정 사유 기록)
으로만 가능하며, 결과 관측 이후의 개정은 그 결과의 판정에 소급 적용될 수
없다. 특히:

- push(main) 활동 이벤트가 같은 무인 판정식으로 trial을 수행한 경우(Q10/rule
  5의 재조정 계약 — 라우터 계약상 전이 자체는 유효), 그 사실은
  "발화 차량 = push"로 기록한다. 이 경우 S1의 차량 요건(schedule)은
  미충족이므로 **본 사전계약의 성공 판정은 내리지 않는다** — 사후에
  "push도 무인이므로 성공"으로 기준을 고치는 것은 §2.4 위반이다. 그 결과는
  11월 force_trial 수용과 같은 계열의 **별개 종결 기록**으로 남는다.
- 관측 창이 지나도 Ubicloud 폴백이 없었다면(11월 GHEC 유지) 본 계약은
  **발동되지 않은 상태**로 유지된다 — 성공도 실패도 아니다(§3). 목표 상태는
  "GHEC가 소진되지 않으면 발화할 필요 없음"이다(복귀수용 문서 §6 잔여).

## 3. 관측 창

- **관측 창 = 2026-12-01 이후의 실제 청구주기**다. 구체적으로
  UBICLOUD_ACTIVE 상태에서 맞이하는 첫 고정 달력월 경계(Q11 — 매월 1일
  00:00:00 UTC 리셋)가 발화 기회이며, 예상 창은 2026-12-01이다. 12월 중에
  폴백 전이가 발생했다면 다음 달력월 경계(2027-01-01)가 창이 된다.
- 창의 trial 발화 하한은 월간 trial 계약(1–3일 UTC, 3회 상한, 20h gap)이
  규정한다. schedule 지연(Q10)에 의한 창 초과 발화는 §2.1 S1 각주의 범위로
  수용한다 — 단, 다음 청구주기로 넘어간 발화는 이번 창의 증거가 아니다.
- 시계 기준: 모든 GitHub API 타임스탬프는 **GitHub-clock 단독**으로 비교하고,
  라우터 변수값 타임스탬프(`last_transition_at`)는 라우터 clock으로 병기한다
  (복귀수용 문서 §2 — Northflank 제어면 러너 시계 −1h 관측 기록 유의).

## 4. 관측 항목 (증거 세트)

실 관측은 12월 사건 이후의 **별도 작업**이며, 본 문서는 관측될 증거의 항목만
사전 고정한다.

| # | 항목 | 방법 (기존 관례 재사용) |
|---|---|---|
| 1 | 스케줄 무인 발화 | `GET /actions/workflows/ci-provider-router.yml/runs?event=schedule` — 창 내 run 존재·created_at·conclusion; 잡 로그 decision line(`{"router":{"event":"schedule",...}}`) |
| 2 | canary 실행·판정 | canary run ID + nonce/display_title 결속 + job의 runner identity(`runner_id`, `runner_group_id`, `runner_group_name`, `runner_name`, labels) + identity-verify step 결과 — M9/M12 predicate |
| 3 | Router 전이 기록 | CI_RUNNER_MAP GET byte-compare 원문(`mode/state/generation/last_transition_at/last_transition_reason/last_trial_result/last_trial_run_id/return_acceptance/return_acceptance_run_id`) + 라우터 run 로그 전이 발화 + 수동 PATCH 부재 |
| 4 | 복귀 수용 | `return_acceptance=pending → confirmed` 전이 발화 관측(라우터 로그 `executed>0 ∧ blocked=0 ∧ all_ghec`) + `return_acceptance_run_id`의 소속·identity 조건 검증(복귀수용 문서 §4) |
| 5 | 전환 후 delta census | 기존 census 관례 재사용(복귀수용 문서 §5 — 모집단 `created_at ≥ T`, 6h 서브윈도 완전 페이지네이션, `jobs?per_page=100&filter=all`, 403 오염 재조회·스키마 검증 Q18): 전환 시점 T 이후 `runner_group_id == 1`(Ubicloud) 신규 잡 0건 — GHEC 전이 이후 폴백 잡이 새로 생기지 않았다는 모집단 정의상의 0 주장 |
| 6 | 병합 수용(별개) | 복귀 후 첫 required run 관측 + 관련 PR의 `landing_observe.sh` L1–L3/L4 — 본 판정과 병합 수용은 서로를 대체하지 않는다(복귀수용 문서 §4) |

## 5. 단일 writer — 수동 CI_RUNNER_MAP 변경 금지

라우터는 CI_RUNNER_MAP의 유일 writer다(concurrency 직렬화 — quirks Q5;
App token 유일 변수 쓰기 경로 — Q3/Q9). 12월 관측 창을 포함해 어떤 경우에도
**수동 변수 PATCH로 전이를 만들거나 흉내 내지 않는다**. 수동 값 변경이
관측됐다면 그 결과는 본 계약의 성공 증거가 될 수 없다 — S3의 "수동 PATCH
부재" 요건이 이를 사전에 배제한다. 운영자가 개입할 수 있는 경로는 §2.2의
수동 진단(force_trial)까지며, 전이 write는 언제나 라우터의 발화다.

## 6. 본 계약의 위치 (범위 명시)

이 문서의 착지는 **계약 정본화**이며, 실제 운영 검증 — 12월 관측·판정·증거
세트 완결 — 은 별도 작업이다. 본 문서는 "12월 폴백 복귀가 검증됐다"는 주장을
포함하지 않으며, 포함해서도 안 된다(AGENTS.md §2.2, §0.9 — 관측 전 성공
주장은 극장이다). 11월 force_trial 경로의 수용 종결은
`ci_provider_ghec_return_acceptance_2026-11-01.md`가 보유하며, 본 계약은 그
잔여(무인 경로)만을 대상으로 한다.

## 참조

- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` — 8항목
  증거 세트, return_acceptance 의미 구분(§4), census 모집단 계약(§5), §6 잔여
- `docs/evidence/ci_provider_canary_fix_epoch_2026-11-01.md` — canary 검증
  술어 v2(세대 전환 10단계), 12월로 밀린 무인 경로 배경
- `docs/evidence/ci_provider_monthly_trial_2026-10-24.md` — 월간 trial
  cadence + 복귀 확정 운영 런북
- `docs/spec/ci_provider_failover_quirks.md` — Q1/Q3/Q5/Q6/Q7/Q9/Q10/Q11/Q12/
  Q16/Q18 + Deterministic rules 5·7·11
- `.github/workflows/ci-provider-router.yml` — 스케줄·trial 창·단일 writer·
  return_acceptance 판정 구현
- `.github/workflows/ghec-canary.yml` — canary identity 판별식(nonce 결속,
  map 미사용 하드코딩)
