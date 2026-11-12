# GHEC 월간 복귀 시험 cadence + 복귀 확정 운영 런북 (2026-10-24)

> 문서 성격: 실행 증거·운영 계약 기록(docs/evidence — §5 SSOT 표). GHEC↔Ubicloud
> failover 제어기(`ci-provider-router`)의 **월간 GHEC 복귀 시험**(monthly
> trial) 운영 cadence와, 복귀 확정 후의 운영 런북을 계약으로 고정하고, 그
> 근거가 되는 2026-10-24 시점 라이브 관측을 함께 기록한다.
> 선행 문서: `docs/evidence/ci_provider_failover_2026-10-23.md`(Stage 0–3,
> M3 예산 불변식), `docs/evidence/ci_provider_return_path_acceptance_2026-10-24.md`
> (복귀 경로·push 트리거·#1063/#1068 쿨다운 계열).
> quirk 본문: `docs/spec/ci_provider_failover_quirks.md`(Q1–Q13 — 본 문서는
> Q11·Q12·Q13에 근거한다).
>
> 측정 주체 구분: **[live]** = 본 문서 작성 세션에서 `gh api`로 관측한 값(모든
> 시각 UTC). **[documented]** = 공식 문서 인용 — URL·인용문은 quirks Q11–Q13에
> 고정돼 있다. **[derived]** = 위 관측과 문서 계약에서 도출한 판정.
> **[policy]** = 본 문서가 정의하는 운영 계약(측정이 아니라 규정이다).

## 1. 배경과 현재 상태 [live]

- 2026-10-23T03:10Z 예산 hard-stop으로 Ubicloud 전환된 이후 GHEC 복귀는 canary
  시험으로만 판단한다(복귀수용 문서 §8). 작성 시점 라이브 변수(2026-10-24
  `gh api`):

  ```json
  {"mode":"ubicloud","state":"UBICLOUD_ACTIVE","billing_period":"2026-10","generation":9,"last_ghec_success_period":"2026-09","last_transition_at":"2026-10-23T23:58:35Z","last_transition_reason":"GHEC_TRIAL_FAILED","last_trial_at":"2026-10-23T23:58:35Z","last_trial_result":"failed","last_trial_run_id":40042591688,"group":"GitHub Actions","x64":"ubicloud-standard-2","slim":"ubicloud-standard-2","arm64":"ubicloud-standard-2-arm"}
  ```

  실패 trial의 6h cooldown 재시도 경로가 활성 상태다(복귀수용 문서 §9의 guard
  통과 발화 — canary run 40042591688, 0-step 차단).
- 청구 주기 리셋은 고정 달력월(매월 1일 00:00:00 UTC, quirks Q11 [documented])
  이고, 리셋 전용 플래그·웹훅이 없으며 usage API는 라우터 App 권한
  (`actions_variables:write`+`metadata:read`) 밖이다(같은 항). 따라서 복귀
  시험의 발화 판정은 **달력월 경계의 계산적 판정 + 자격식**이고, 그 성공 판정은
  canary의 실측뿐이다 — 판독 가능한 서버측 "리셋됐다" 신호는 존재하지 않는다.
- **포함량 소진의 실측 확정** [live 2026-10-24, owner 토큰 `GET
  /orgs/Archright/settings/billing/usage`]: `Actions Linux` **49,502.33분** +
  `Actions Linux Slim` **2,609분** = **≈52,111분 > 포함 50,000분**. "제공량 소진"은
  이제 추론이 아니라 회계 관측값이다. 이 API는 `Administration: read`를 요구하므로
  라우터 App 권한(`actions_variables:write`+`metadata:read`) 밖이고, 따라서
  라우터 판정식에 쓰지 않는다 — 회계 사실(이 수치)과 운영 상태(`runner_id=0` ∨
  `steps=0` 실행 증거)는 서로 다른 관측이며, 전환 트리거는 후자다(quirks Q11).
- 같은 조회에서 무파라미터 기본값을 재확인했다: `/usage/summary` → **현재 월**
  (`timePeriod {month:10, year:2026}`), `/usage` → **전월+현재월** 행
  (2026-09-01, 2026-10-01). 문서 기본값과의 차이는 quirks Q11에
  `[documented ↔ measured mismatch]`로 기록되어 있다.
- 위 JSON 스냅샷 이후 push 발화 trial이 1건 더 있었다 [live 2026-10-24T07:04Z,
  PR #1070 머지 직후 `push`]: `{"action":"trial","reason":"canary_failed",
  "canary_run_id":40072684018,"generation":10}` — 창(1–3일) 밖에서도 발화했고
  canary는 다시 `runner_id=0`/`steps=0`으로 차단됐다. 이 월중 발화가 §2의
  창 자격식이 제거하는 대상이다.

## 2. 월간 시험 cadence [policy]

- **창(window)**: UTC 매월 **1–3일**. **하루 1회**(UTC 날짜 기준), 시도 간격
  **≥20시간**, **최대 3회**. 실패해도 창 안에서만 재시도하고, 창이 닫히면
  **다음 청구 주기**까지 대기한다 — 월중 무기한 재시도 아니다.
- 근거 [derived]: ① hard-stop의 해제 시점은 "until the next billing cycle"
  (Q11)이므로 시험은 주기 초두 창에서만 의미가 있다 — 창 밖 재시도는 예산이
  이미 소진된 월중 상태에서 실행 가능성을 재확인하는 것일 뿐이다. ② GHEC가
  가용해진 뒤의 시험은 포함량 분을 소모한다 — 차단 중 0-step canary는 분
  소모 0이지만(복귀수용 문서 §5) 복귀 창의 canary는 실제 실행되므로, 시도
  횟수 상한(3회)이 비용 경계다. ③ "하루 1회 ∧ ≥20시간"의 교집합은 같은 UTC
  날짜의 재시도를 구조적으로 막고, 1–3일 창 안에서 최대 3회를 수용한다.
- **예약-우선(reserve-then-dispatch)**: canary dispatch **전에** 시험 예약을
  먼저 기록한다(`last_trial_period`·`trial_attempts_period`·`last_trial_at`·
  `generation`의 선기록 — 변수가 단일 진실 원천), 그 다음
  dispatch한다. 이유 [derived]: 발화 경로가 push/schedule/dispatch 3종으로
  같은 자격식을 공유하므로(복귀수용 문서 §2·§9), "판정 → 실행 → 기록" 순서면
  동시 도래 트리거들이 모두 자격 있음을 보고 canary를 중복 dispatch한다 —
  실측된 다중 발화(§9: main 병합 1건당 canary 1건, 44분 동안 4건)가 바로 그
  실패 모드다. 예약 선기록이면 두 번째 도래 트리거는 예약을 보고 skip하며,
  쓰기 직렬화는 `concurrency` 단일 writer(Q5)가 보장한다.
- **production 관측 상태**: 현행 라우터(#1068 시점)의 시험 발행은 월내 6h
  cooldown 재시도이고, 본 cadence는 월간 시험의 상위 운영 계약이다. 이 cadence를
  따르는 첫 관측 가능 시점은 **2026-11-01 00:00:00 UTC 이후 첫 자격 발화**다 —
  관측 전까지 이 cadence는 계약(규정)이지 달성 기록이 아니다.

## 3. 기록 계약 — `return_acceptance`와 `last_required_outcome`의 분리 [policy]

- `return_acceptance` = **공급자 실행 가능성**(provider executability):
  canary가 GHEC 러너에서 **명명된 identity 스텝까지 성공**했는가 — quirks Q12
  predicate(`runner_group_id==0` ∧ `runner_group_name ∈ {"", "GitHub
  Actions"}` ∧ `runner_id>0` ∧ 명명 스텝 성공). `confirmed` / `provider_regression` / `inconclusive` / `pending`(미확정).
  구현 enum은 `"" | pending | confirmed | provider_regression | inconclusive`이며,
  `confirmed`는 **executed job ≥1**을 요구한다 — 전 job이 skipped/미배정인 run은
  all-GHEC 조건이 공허 참(vacuous truth)이 되므로 복귀 증거로 쓰지 않는다
  (2026-10-24 수정: 세 confirm 지점 모두 `ACC_EXECUTED>0` 가드).
- `last_required_outcome` = **CI 결론**: 전환 이후 **새로 생성된** required
  run이 실행됐을 때의 결론(통과 / 실패 / 미관측).
- **분리 기록**한다 [derived]: canary 성공은 "GHEC에서 실행 가능"만 증명한다 —
  required checks가 논리적으로 통과하는지는 별개 사건이며(실행된 뒤 실패할 수
  있다), 두 값을 합치면 provider 복귀 판정과 CI 건강이 서로 오염된다.
  acceptance는 rerun으로 만들지 않는다(Q12 — vars 재평가 침묵): 전환 이후
  새로 생성된 run만 증거고, 재실행은 증거가 아니다.

## 4. 운영 런북 [policy] — 복귀 확정 후 수순

1. **복귀 확인** = canary의 명명 스텝 성공 + `mode=ghec` +
   `return_acceptance=confirmed`. 이 셋이 모두 성립해야 복귀다 — canary run의
   conclusion 단독은 아니다(0-step 차단 실패도 `failure` conclusion을 내놓는다,
   Q1/Q12).
2. **필수 검사 5종 + 조직 공통 2종이 GHEC에서 실행되는지 확인** — 전환 후
   **첫 required run** 기준으로:
   main ruleset required checks 5종 — `admission-check`, `bsec-integrity`,
   `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`
   [live 2026-10-24, `GET /repos/Archright/Axiom/rules/branches/main`,
   ruleset `main`] + 조직 공통 `admission-gate`(ruleset `axiom-admission-gate`)
   와 `landing-integrity` [live 2026-10-24, 두 ruleset 모두
   `enforcement: active`]. 이 run들은 전환 이후 새로 생성된 것이어야 한다
   (rerun 불가 — §3).
3. **자동 복귀는 이미 실패한 required check를 치유하지 않는다** [derived]:
   차단으로 0-step 실패한 체크는 GitHub가 자동으로 재평가하지 않는다 —
   **재실행으로만 재평가**된다(Q4: 0-step 실패도 `rerun-failed-jobs` 대상;
   Q12: rerun 한도 50회/30일). 수동 복구 절차: 해당 run 재실행
   (`rerun-failed-jobs`) 또는 새 push. **분류 불가 실패는 의도적으로 재실행하지
   않는다** — 분류 없는 재실행은 증거를 덮어쓴다(fail-closed).
4. **실패 원인 분류**(복귀 후 required run이 실패했을 때):
   - `runner_id=0 ∧ steps=0` → **공급자 문제**(hard-stop 서명, Q1/Q2) — 자동
     복귀 경로(ubicloud 전환)가 처리한다. 수동 조치 없음.
   - 실행됐는데 실패(`runner_id>0 ∧ steps>0`) → `last_required_outcome`에
     기록**만** 하고 **라우팅은 불변** — provider 건강과 CI 결론의 분리(§3).
   - 불명 → **`inconclusive`, fail-closed** — 복귀 acceptance로 세지 않는다.

## 5. 수용 리스크 — Ubicloud 지출 상한은 시스템이 다루지 않는다 [documented]

- Ubicloud에는 hard spending cap이 없다(Q7: `UsageAlert` email-only — "no
  action is taken automatically"; `ProjectQuota`는 동시 러너 수 상한이지 지출
  상한이 아니다). 게다가 usage/billing API 자체가 없다(Q11: `openapi/openapi.yml`
  경로 0건, `ubi` CLI에도 없음 — 웹 콘솔 전용). 따라서 **시스템(라우터)은
  Ubicloud 지출을 상한 설정하거나 관측할 수 없다** — 이것은 미구현이 아니라
  제공자 측 기능 부재에 의한 구현 불가다.
- 완화: **월 1회 콘솔/인보이스 수동 확인**(인간 handoff 항목). 자동 비용
  추정 엔진을 만들지 않는 것은 의도다 — 권위 없는 두 번째 제어계가 된다(Q11).
- 참고 단가 [documented, Q7]: `standard-2` $0.00125/min, per-job ceil 최소
  1분 — 제어 평면 run(라우터/canary)은 짧지만 전 required checks가 Ubicloud에
  머무는 기간의 월 지출은 콘솔에서만 확정 가능하다.

## 6. 라우팅 전환 후 관측된 별건 결함 — drift monitor의 관찰점 해석 [live 2026-10-24]

PR #1074(`admission-ssot-drift`·`drift-signal`을 `CI_RUNNER_MAP`으로 라우팅,
merge `31d0458de`)의 post-merge 수용 측정에서 **라우팅은 정상, 모니터의 관찰점
선택이 원인인 red 1건**이 나왔다. 이 절은 그 사실만 기록한다 — 라우팅 변경의
결함이 아니다.

| run | 발화 | runner | 결과 |
|---|---|---|---|
| [40075113086](https://github.com/Archright/Axiom/actions/runs/40075113086) | `workflow_dispatch` (입력 없음) | `ubicloud-standard-2`, group 1, `grcp0cvd8…`, steps 11 | **failure** — `DRIFT producer observation: no check-run named "admission-check" at the observed SHA` |
| [40075514851](https://github.com/Archright/Axiom/actions/runs/40075514851) | `workflow_dispatch` (`observe_sha`=랜딩 커밋 `31d0458d`) | `ubicloud-standard-2`, group 1, `grvmz1580…`, steps 11 | **success** |
| [40075207815](https://github.com/Archright/Axiom/actions/runs/40075207815) | `workflow_run`(위 40075113086 자동 연쇄) | `ubicloud-standard-2`, group 1, `grafd6d523…`, steps 6 | success + 실신호 발행(issue **#1078**) |

- 원인 [derived]: 모니터의 기본 관찰점은 "최신 completed+success merge_group run의
  `head_sha`"인데, 그 값이 **랜딩 머지 커밋이 아니라 큐 평가 헤드**(`6b0ebb46…`)를
  가리켰다. 평가 헤드는 `admission-check` 컨텍스트를 만들지 않으므로 monitor는
  fail-closed red(`missing != clean`)를 낸다 — 규칙은 설계대로 작동했고, 관찰점
  해석이 병목이다.
- 교차 증명: 같은 코드·같은 러너 풀에서 관찰점을 실제 랜딩 커밋으로 주면 success
  (표 2행). 즉 워크플로 본체·라우팅은 정상이다.
- 후속(범위 밖, 별도 slice): 기본 관찰점을 랜딩 merge commit으로 고정하거나, 평가
  헤드에서는 `attest / admission-check` 등가 컨텍스트를 인정하도록 판정식을
  개정한다. 그 전까지 `drift-signal`은 같은 이유로 red 신호를 반복 발행할 수
  있다 — 신호 자체는 진짜다(관측점이 관측 불가 상태).
