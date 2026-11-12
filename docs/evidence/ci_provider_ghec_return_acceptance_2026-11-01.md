# CI Provider — GHEC Return Acceptance 증거 기록 (2026-11-01)

> **종류**: 운영 acceptance 증거 기록 — `ci_provider_canary_fix_epoch_2026-11-01.md`
> 10단계 절차의 9단계(Production Acceptance) 종결 차량. 본 문서는 Reporter다 —
> 각 주장의 권위는 아래 표가 가리키는 GitHub API 관측·run·commit이며, 문서 병합
> 자체는 판정이 아니다(Authority ≠ Adapter, AGENTS.md §2.3).
> **상태**: 항목 1–4 실측 확정. 항목 5–8은 본 문서가 탑재된 PR-2 자신의 병합·
> 전수조사 **이후에만** 관측 가능하다(시간역학: PR-2의 check run이야말로
> return_acceptance의 관측 대상) — 병합 후 갱신 각주로 종결한다. 관측 전
> 완료 주장 금지(AGENTS.md §2.2).

## 1. 경로 요약

1. **PR #1160** (`fix/ghec-canary-labels-jq`, HEAD `ad977dcfe`): ghec-canary
   `:94` labels 검증 술어 수리(문자열 배열 평탄화) + Q16 quirk + epoch record.
   5 required checks 전부 pass → merge queue → **native MERGE
   `0ba17ad36dc407e15d1514885dbe8c187c9097c0`** (2026-11-01T09:31:26Z,
   mergedBy wintrover).
2. **force_trial dispatch** (설계된 수동 검증 경로 — 월간 창/same-day/20h/상한
   우회, 시도 counter 미소비, UBICLOUD_ACTIVE 전용 조건 충족 시점에 실행):
   router run **41289523004** (workflow_dispatch, head_sha=`0ba17ad36` —
   수리된 워크플로가 병합 커밋에서 실행됐다는 귀속 증거, conclusion=success,
   09:35:43→09:36:38Z GitHub-clock).
3. **canary 성공**: run **41289547761** (09:36:04Z 생성, conclusion=success).
4. **라우터 전이** (단일 writer — 수동 PATCH 없음): CI_RUNNER_MAP
   `mode=ghec / GHEC_ACTIVE / generation=15 / return_acceptance=pending`.

## 2. 시계 기준 병기

Northflank 제어면 러너 시계는 GitHub 정본 UTC 대비 **−1h** 관측:
CI_RUNNER_MAP `last_transition_at=2026-11-01T08:35:59Z`는 라우터 clock이며
GitHub-clock **≈2026-11-01T09:35:59Z**에 해당한다. 정합 근거: router run
GitHub `created_at=09:35:43Z`, canary run `created_at=09:36:04Z`, canary job
`started_at=09:36:09Z`. 본 기록의 GitHub API 타임스탬프는 전부 GitHub-clock,
변수값 타임스탬프는 라우터 clock임을 표기한다. **전수조사(항목 8) 모집단
기준 시각 T = GitHub-clock 2026-11-01T09:35:59Z** (라우터 clock +1h 보정).

## 3. 최종 증거 세트 (8-item — epoch record와 동일 항목의 실측 완결)

| # | 항목 | 실측값 | 상태 |
|---|---|---|---|
| 1 | PR-1 전후 workflow blob SHA + CI generation | pre `27eb01be956139218a96c7f174f8c35481106e87` → post `b86daffe4ec93e38bd4873f0e372eeb3abbdfc71` (main `0ba17ad36`의 `.github/workflows/ghec-canary.yml`); generation 14 → 15 | 확정 |
| 2 | force_trial router run ID + canary run ID | router **41289523004** (workflow_dispatch, success) / canary **41289547761** (success) | 확정 |
| 3 | canary job identity + step 결과 | job `ghec-canary`: `runner_id=1000035433`, `runner_group_id=0`, `runner_group_name="GitHub Actions"`, `runner_name="GitHub Actions 1000035433"`, `labels=["ubuntu-24.04"]`; steps 3/3 success — "Set up job" / "Verify GitHub-hosted provider identity (runner_group_id==0 + group name + API/local coherence)" / "Complete job"; 09:36:09→09:36:14Z | 확정 |
| 4 | 라우터 변수 write + GET 검증값 | GET(전이 후, byte-compare 원문): `mode=ghec, state=GHEC_ACTIVE, billing_period=2026-11, generation=15, last_ghec_success_period=2026-11, last_transition_at=2026-11-01T08:35:59Z(라우터 clock), last_transition_reason=GHEC_TRIAL_SUCCESS, last_trial_result=success, last_trial_run_id=41289547761, trial_attempts_period=1(미소비), return_acceptance=pending, return_acceptance_run_id=null, x64=ubuntu-24.04, fallback_provider=ubicloud` | 확정 |
| 5 | 새 generation 귀속 PR-2 required runs | pr-head: run 41290619850~41290619983(10 workflow run, head `1aee2835…`, run_attempt 1) — 30 체크 pass·의도된 조건부 skip(docs-only 빌드 레인), 실패 0. 전 실행 잡 `runner_group_id=0`(GitHub Actions `1000035434~1000035448`, 09:51:52~09:52:00Z 시작, 표시 체계) | 확정 |
| 6 | PR-2 merge_group GHEC identity + required check 결과 | merge_group 8 run(41291994322·41291994342·41291994360·41291994367·41291994383·41291994397·41291994417·41291994602, group_head `18e5602b…`): admission-check·axiom-operational-slice·bsec-integrity·debt-registry-gate·generation-acceptance·landing-integrity·observer-manifest-consistency·probe-merge-queue 전부 **success**. 전 실행 잡 `runner_group_id=0`(GitHub Actions `1000035461~1000035484`), probe-judge 등 skip은 조건부. L1-L3 landing_observe **TERMINAL_SUCCESS**(graphql↔rest consistent) | 확정 |
| 7 | merge SHA + `landing_observe.sh --main <sha>` | merge `18e5602b7e6c9a22ee9800826b6cf31a7e4125b9`, mergedAt 09:23:15Z, mergedBy wintrover, merge-commit parents=2. L4 `--main 18e5602b…` **OBSERVED_SUCCESS**(canonical-main slice-evidence artifact, run-manifest digest·head 귀속 검증 통과) | 확정 |
| 8 | 전환 후 전체 모집단 Ubicloud 신규 job 0건 | **ZERO-CONFIRMED**: lookback 48h(10/29~11/1) run 3,090 전수 열거(6h 서브윈도·완전 페이지네이션) → 잡 전수(`filter=all`): 1차 유효 2,840 run / 잡 5,362 + 403 오염 250 run 재조회(exit code 판별 worker, Q18) 전부 성공 → `started_at > T ∧ runner_group_id==1` **K=0**, api_failures=0, page_overflow=0. 스크래치: `/tmp/ax_nc/census_20261101T091231Z/` | 확정 |

## 4. return_acceptance 의미 구분 (공급자 수용 ≠ 병합 수용)

- **판정 계약**: 라우터는 전환 이후 **생성된** required run 관측에서
  `executed>0 ∧ blocked=0 ∧ all_ghec`이면 `return_acceptance=confirmed`를
  기록한다. 이것은 **GHEC 공급자 복귀·실행 경로의 수용**이다 — 개별 테스트
  성공이 아니라 "실제 required 잡이 GHEC에서 실행됐다"는 identity 증명이다.
  실행된 failure도 `GHEC_RETURN_EXECUTION_FAILURE`로 confirm한다(공급자
  identity는 잡 배정으로 이미 증명됨). rerun은 증거 아님(문서 계약).
- **병합 수용**은 별개 판정이다: PR-2의 required checks 성공 + merge_group
  착지 + native MERGE. 두 판정은 서로를 대체하지 않는다 — 본 기록은 둘 다
  각각의 증거로 종결한다(항목 5·6은 병합 수용, 항목 4의 confirmed 전이는
  공급자 수용).
- `return_acceptance_run_id`는 전환 이후 generation에 속하며 GHEC 실행을
  입증한 run이어야 한다 — 단순한 성공 run이 아니라는 조건이 확인 대상이다.
- **confirmed 기록 경로 결함 발견(2026-11-01, PR-3으로 수리)**: 위 판정
  계약 자체는 정상 발화했다 — 라우터 run 41296106985 로그가 전환 이후
  required run(41295610611, PR #1162 merge_group, 전 잡 GHEC)에서
  `executed=1 blocked=0 all_ghec=true` 관측을 기록했다. 그러나 관측 로그
  라인(`ci-provider-router.yml:464`)의 jq 배열 축약 결함(Q17)이 exit 5로
  잡을 죽여 `confirmed` write(:476-478) 직전에 차단했다 — 발화 3회(10:02·
  10:03·10:07Z) 전부 동일 지점. 수리·증거는
  `ci_provider_router_acceptance_fix_epoch_2026-11-01.md`가 보유하며,
  confirmed는 PR-3 병합 후 라우터의 다음 발화로 기록된다(아래 §6).

## 5. Ubicloud-0 모집단 정의 (전수조사 계약)

"조회한 일부 목록에서 0개"가 아니라 **정의된 모집단에서 0개**를 주장한다:

- 모집단: `created_at ≥ T`(§2의 T)인 repo 전체 workflow run(org required
  workflow 포함 — 이 repo run list에 포함됨 확인)에서 파생한 전체 잡.
- 절차(사전 검증됨 — 양성 대조군 T=2026-10-30T12:00Z에서 3,234 runs /
  6,109 jobs 전수 열거, Ubicloud group_id=1 K=1,882>0 검출): `created=W1..W2`
  6시간 서브윈도 `gh api --paginate …/actions/runs`(1000건 깊은페이징 상한
  회피) → 런별 `jobs?per_page=100&filter=all`(**filter=all 필수 — latest는
  rerun attempt 누락**) ×3 재시도(502 완화) → `select(.started_at > $T and
  .runner_group_id == 1)` 분류(group_name 대소문자 불일치하므로 **id로만**).
- 분류 규칙: `runner_group_id==1` = Ubicloud. skipped/미배정 잡은 모집단에서
  제외(배정 사실 없음). rerun은 attempt별 별도 row로 집계.
- 완전성 다이얼: 48h lookback(실측 최대 rerun lag 51분의 ~56배).

## 6. Terminal Outcome

- 증거 세트 항목 1–8: **전 항목 관측 확정** (§3 표 — 2026-11-01 갱신:
  PR-2 병합·L1-L3 TERMINAL_SUCCESS·L4 OBSERVED_SUCCESS·전수조사 K=0 포함).
- `return_acceptance=confirmed` + `return_acceptance_run_id` 관측
  (CI_RUNNER_MAP GET) — 판정 조건은 이미 충족 관측됐으나 기록 경로 결함
  (§4, Q17)으로 **PR-3(`ci_provider_router_acceptance_fix_epoch_2026-11-01.md`)
  병합 후 라우터의 다음 발화에서 기록·관측된다** — 이 갱신 각주로 종결.
- 잔여(본 슬라이스 밖, 별도 보고): 12월 자동 무인 폴백 경로 최종 확인은
  다음 폴백 주기의 자동 발화로만 종결 가능 — 목표 상태는 "GHEC가 소진되지
  않으면 발화할 필요 없음"이며 이번 달은 force_trial 경로로 수용을 종결했다.

### §6 종결 각주 (2026-11-01 — epoch record 9단계 이행 완결)

- **confirmed 기록·관측 완료(단일 writer — 수동 PATCH 없음)**: PR #1163
  native MERGE `7b41645e`(10:51:38Z) 후, 라우터 run **41299411602**
  (10:53:02Z, workflow_run, success)의 수리된 관측 경로가 acceptance run
  **41298669695**(admission-gate, merge_group, head=`aa155017` = PR #1164
  큐 — PR-3 merge 위 세대, created 10:42:37Z > 전환)에서 `[acceptance-job]`
  12행 전 잡 `runner_group_id=0` 관측 → `executed=12 blocked=0
  all_ghec=true` → **`return_acceptance=confirmed` write**(라우터 clock
  10:53:18Z / 변수 API updated_at 10:53:27Z). GET 실측(10:57:29Z·12:15Z):
  `mode=ghec, GHEC_ACTIVE, generation=15, return_acceptance=confirmed,
  return_acceptance_run_id=41298669695, last_required_outcome=success`.
- **PR-3 L4**: push run **41299314878**(completed/success, head=`7b41645e`)
  + artifact 13080688268(gitHead 귀속·sha256 검증, tier=dual-verified) →
  **OBSERVED_SUCCESS** — PR-3의 L1–L4 전 계층 관측 종료.
- **T 결속**: T=2026-11-01T09:35:59Z(GitHub clock) — force_trial run
  41289523004의 GitHub 실행 창 `[09:35:43Z, 09:36:38Z]` 내부(실측 GET).
  라우터 clock 기록(시험 08:35:59Z / confirmed 10:53:18Z)은 병기하되
  오프셋의 절대 정본은 미귀속(시험 기록은 GitHub 창과 약 +1h, confirmed
  기록은 변수 API updated_at와 근접 — 판정 경로 무영향 실측).
  created_at/started_at 비교는 GitHub API 시각 단독.
- **재관측 census — Ubicloud-0 종결 증거(원본 원장 소실 대체)**: 창
  `[T, t_final1=12:59:32Z]`. 모집단 (a) created≥T 242 runs/497 job 행 +
  (b) [T−2h, T) 107 runs/214 job 행(전환 시점 활성·지연 배정 커버) +
  (c) [T−48h, T−2h) 3,043 listed 중 선택 2 runs(`run_started_at>T` ∨
  `run_attempt>1` ∨ `updated_at>T`)/48 job 행. 전 잡 `filter=all`
  (rerun 시도 행별 보존 — 선택 2 runs의 attempt-2 잡이 실제 재검출됨),
  직렬 401 GET, api_failures=0, pages_complete=true(26 서브윈도), rate
  미소진(3352→2673, 13:08:22Z 리셋 5000). 결과: **`ubicloud_jobs_post_T`
  (K)=0** — Ubicloud 74잡 전부 `started_at ≤ 09:31:49Z`(T 이전 4분 10초,
  전환 전 legacy 라우팅), GHEC 228, axiom-control 자체호스트 62(group 7
  — 라우터 제어면의 의도적 `[self-hosted, axiom-control]`, 0/1 매핑
  밖·K 무관), **pending_unresolved=0**. 원장(행 단위 run/attempt/job
  식별자 + runner identity, 7개 ledger sha256 독립 재계산 일치 + 경계
  잡·acceptance 잡 라이브 API 대조 일치): `data/ci_provider/
  census_20261101T125932Z/`(독립 검증 기록: `verification.json`).
  원본 3,090건 census 스크래치(/tmp 소실)는 §3 항목 8·§5의 prose 계약
  으로 유지 — 본 재관측이 [T, t_final1]의 자기완결적 종결 증거다.
- **runs-on 소비 계약(잔여 위험 종결)**: 전 5개 required context가
  `fromJSON(vars.CI_RUNNER_MAP)` 파생(org 소유 admission-gate-v2 포함 —
  스펙 Q1/Q2 실측 근거), `vars`는 **잡 스케줄링 시점 live 평가**
  (#1062/#1091 증거 표: 동일 워크플로가 Ubicloud 창 `ubicloud-standard-2`
  → 지금 `ubuntu-24.04`), env/matrix/커밋 스냅샷 중간 복제 벡터 전무 —
  pre-T run의 post-T 배정 잡도 현행 map을 읽는다. 유일 잔여 벡터는 org
  SHA-pin의 표현식 텍스트 동결(값 전파는 항상 유효) = RESID-22 범위.
- **epoch record 9단계 종결 선언**:
  `ci_provider_router_acceptance_fix_epoch_2026-11-01.md` 9단계(merge →
  발화 → 수리 경로 통과 → confirmed write → GET 검증 → 본 갱신 각주)
  계약 이행 완료. 본 PR 착지 후 [t_final1, t_final2] 최종 delta와 본 PR
  잡 identity는 최종 운영 보고에 기록된다.
