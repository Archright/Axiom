# 잔여 종결 관측 — 12월 무인 폴백 readiness + webhook 재평가 조건 확인 (2026-11-02)

> **종류**: 읽기 전용 관측 기록 — 명령→결과 쌍의 수집. 신규 구현 0, 기존 정본
> 0수정(본 파일이 이 변경의 유일 신규 파일이다), ledger 수정 없음.
> **사전등록 성격 명시**: 본 기록은 2026-12-01 사건 관측이 아니라 **readiness
> 확인 + 판정 분류의 사전 고정**이다. 계약 §2.4(사후 기준 변경 금지)와 정합한다.
> 12월 실제 판정은 이 분류(§1.2)로만 수행되는 별도 작업이다(계약 §1, §4, §6 —
> AGENTS.md §2.2 관측 전 완료 주장 금지).
> **관측 시점**: GitHub-clock 2026-11-02T03:00–03:02Z. 관측 기점 커밋(origin/main):
> `83ae548ae5f58eb6b39578bb35fd62db172aab6b`. 본 문서는 Reporter다 — 각 주장의
> 권위는 기재된 GitHub REST 관측·git 관측이며, 문서 병합 자체는 판정이 아니다
> (Authority ≠ Adapter, AGENTS.md §2.3).

## 1. 12월 무인 폴백 readiness

### 1.1 계약 위치와 발화 기회

- 판정 기준의 유일 정본:
  `docs/spec/ci_provider_december_unattended_fallback_acceptance_contract.md`
  §2 (§2.4 — 결과 보고 후의 기준 변경 금지 명문화).
- **발화 기회**: UBICLOUD_ACTIVE 상태에서 맞이하는 첫 고정 달력월 경계(계약 §3,
  Q11 — 매월 1일 00:00:00 UTC 리셋). 예상 창은 **2026-12-01**이다.
- 관측 시점 라우터 상태는 **GHEC_ACTIVE**(§1.4 OBS-4)다. GHEC 유지 시 폴백이
  발생하지 않아 본 경로는 발화하지 않을 수 있다 — 그 경우 계약은 **"발동되지
  않은 상태"로 유지**되며 성공도 실패도 아니다(§2.4). 목표 상태는 "GHEC가
  소진되지 않으면 발화할 필요 없음"이다(계약 §2.4가 복귀수용 문서 §6 잔여에서
  인용).

### 1.2 결과 분류 사전 등록 (12월 관측 시 이 분류로만 판정 — 혼동 금지)

| 분류 | 조건 | 판정 |
|---|---|---|
| (a) | 발화 조건 미충족(관측 창 개시 시 UBICLOUD_ACTIVE 아님) | **정상 미발동** — 계약은 발동되지 않은 상태 유지(§2.4), 성공도 실패도 아님 |
| (b) | 발화 조건 충족 + 관측 창(§3) 내 schedule event run 부재 | **S1 미관측 → UNKNOWN + fail-closed**, 원인 조사 필요 — Q10: schedule은 늦고 불규칙한 best-effort 차량(§2.1 S1 각주) + GitHub 공식 문서 고부하 지연·queued job drop·(공개 repo 한정) 60일 무활동 자동 비활성화 점검(§1.5) |
| (c) | schedule 발화 확인 + S2(canary 실행·판정) 또는 S3(Router 전이·증거 기록) 미확인 | **UNKNOWN — 성공 아님**(계약 §2.3: S1·S2·S3 중 하나라도 불충분하면 UNKNOWN, Ubicloud 보수 유지) |
| (d) | push(main) 활동 이벤트가 같은 무인 판정식으로 trial 수행 | **"발화 차량 = push"로 기록**, S1 차량 요건(schedule) 미충족이므로 본 계약의 성공 판정 불가 — 별개 종결 기록(§2.4 명시: 사후에 "push도 무인이므로 성공"으로 고치는 것은 §2.4 위반) |
| (e) | S1·S2·S3 전부 관측 | **§2.1 성공 판정 가능** |

### 1.3 계약 §2·§3 원문 핵심 인용 (사전 고정의 대상)

- **S1**(§2.1 표): "12월 관측 창(§3) 내 `ci-provider-router`의 `event=schedule`
  run 존재(run ID·GitHub-clock created_at) + 잡 로그 decision line이 trial
  발동을 기록".
- **S2**(§2.1 표): "dispatch된 canary run(`run-name: ghec-canary <nonce>` 결속 —
  quirks Q6/H20)이 실제 실행됐고(0-step 차단 아님 — `runner_id > 0 ∧ steps >
  0`), identity 판별식 판정 결과(성공)가 step 로그로 관측됨".
- **S3**(§2.1 표): "CI_RUNNER_MAP GET(전이 후 byte-compare 원문):
  `mode=ghec, state=GHEC_ACTIVE, generation 증가, return_acceptance=pending` →
  이후 `return_acceptance=confirmed` + `return_acceptance_run_id` … + 라우터
  run 로그의 전이·수용 발화 + 수동 PATCH 부재(단일 writer 관측, §5)".
- **S1 각주(§2.1)**: "schedule은 Q10 실측상 늦거나 불규칙하므로, '발화 확인'의
  기준은 nominal 30분 cadence가 아니라 **관측 창(§3) 내 schedule event run의
  존재**다. 지연 자체는 성공 판정을 무효화하지 않는다."
- **UNKNOWN 규칙(§2.3)**: "S1·S2·S3 중 **하나라도 관측 불가·불충분**이면 결과는
  UNKNOWN이며, Ubicloud 보수(fail-closed)를 유지하고 **성공으로 취급하지
  않는다**."
- **사후 기준 변경 금지·미발동 상태(§2.4)**: "12월 결과를 **보고 나서** 본
  기준(§2)을 고쳐 결과를 성공으로 만드는 것을 금지한다. … 관측 창이 지나도
  Ubicloud 폴백이 없었다면(11월 GHEC 유지) 본 계약은 **발동되지 않은 상태**로
  유지된다 — 성공도 실패도 아니다(§3)."
- **관측 창(§3)**: "관측 창 = 2026-12-01 이후의 실제 청구주기다. 구체적으로
  UBICLOUD_ACTIVE 상태에서 맞이하는 첫 고정 달력월 경계(Q11 — 매월 1일
  00:00:00 UTC 리셋)가 발화 기회이며, 예상 창은 2026-12-01이다." / "시계 기준:
  모든 GitHub API 타임스탬프는 **GitHub-clock 단독**으로 비교하고, 라우터
  변수값 타임스탬프(`last_transition_at`)는 라우터 clock으로 병기한다".

### 1.4 readiness 관측 (명령 → 결과, 읽기 전용)

**OBS-1 — 발화 차량(스케줄 블록)**

```
명령: git show origin/main:.github/workflows/ci-provider-router.yml | sed -n '75,95p'
      git show origin/main:.github/workflows/ci-provider-router.yml | grep -n -E "^  (push|schedule|workflow_dispatch):|cron:"
결과: 81:  push:
      83:  schedule:
      84:    # :00/:30 회피 — 분당 발화 herd 배제 + 30분 재조정 계약(P3).
      85:    - cron: '7,37 * * * *'
      86:  workflow_dispatch:
```

계약 §1-1의 인용(`schedule: cron '7,37 * * * *'`, 30분 재조정 계약)과 일치.
`:00/:30 회피` 주석은 §1.5 공식 문서의 "고부하 시간대는 매 시간 시작" 주의와
정합(7분·37분 발화).

**OBS-2 — canary 차량(트리거)**

```
명령: git show origin/main:.github/workflows/ghec-canary.yml | grep -n -A 5 '^on:'
결과: 39:on:
      40-  workflow_dispatch:
      41-    inputs:
      42-      nonce: ...
```

`workflow_dispatch` 단일 트리기(schedule·push·pull_request 발화 없음 — 파일
`:25` 주석 "트리거: workflow_dispatch 단일" 확인). 계약 §1-2("canary는
CI_RUNNER_MAP을 절대 읽지 않는다", M6)·§1.5 예상과 정합.

**OBS-3 — CI_RUNNER_MAP 참조 경로**

```
명령: git grep -n 'CI_RUNNER_MAP' origin/main -- .github/workflows/
결과(요지): 라우터는 변수를 repos/$REPO/actions/variables/CI_RUNNER_MAP 경로로
      GET/PATCH 한다(ci-provider-router.yml:270 GET, :404 이하 다중 PATCH —
      단일 writer). 소비 측은 전 워크플로가 fromJSON(vars.CI_RUNNER_MAP).x64
      형태(admission-check.yml, closure-watcher.yml 등).
```

→ 현재값 관측 대상 = 저장소 Actions 변수 `CI_RUNNER_MAP`.

**OBS-4 — CI_RUNNER_MAP 현재값 (예상과 일치)**

```
명령: gh api repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP
시각: GitHub-clock 2026-11-02T03:00:00Z
결과: mode=ghec, state=GHEC_ACTIVE, billing_period=2026-11, generation=15,
      last_ghec_success_period=2026-11,
      last_transition_at=2026-11-02T02:59:05Z (라우터 clock 병기 — §1.6),
      last_transition_reason=GHEC_RETURN_CONFIRMED,
      last_trial_at=2026-11-01T08:35:59Z, last_trial_result=success,
      last_trial_run_id=41289547761, group="GitHub Actions",
      x64=ubuntu-24.04, slim=ubuntu-slim, arm64=ubuntu-24.04-arm,
      last_trial_period=2026-11, trial_attempts_period=1,
      return_acceptance=confirmed, return_acceptance_run_id=41380490584,
      last_required_outcome=success, fallback_provider=ubicloud
      (GitHub 측 updated_at=2026-11-02T02:59:12Z)
```

사전 관측 예상(mode=ghec / state=GHEC_ACTIVE / confirmed / generation 15)과
**정확히 일치**한다. `last_transition_reason=GHEC_RETURN_CONFIRMED` +
`return_acceptance=confirmed` 상태는 복귀수용 문서
(`ci_provider_ghec_return_acceptance_2026-11-01.md`)가 보유한 11월 수용과
동일 계열의 상태다 — 본 기록은 이 전이의 판정을 수행하지 않는다(읽기 전용,
계약 §5 단일 writer 존중).

**OBS-12 — schedule 차량 현재 생존(12월 창의 차량 liveness 사전 확인)**

계약 §4 항목 1이 규정한 동일 읽기 전용 메서드를 liveness 사전 확인으로
재사용했다(12월 판정이 아니다 — 창 내 관측이 아니므로).

```
명령: gh api 'repos/Archright/Axiom/actions/workflows/ci-provider-router.yml/runs?event=schedule&per_page=5'
시각: GitHub-clock 2026-11-02T03:02:04Z
결과: id=41367787229 created_at=2026-11-02T00:33:32Z conclusion=success
      id=41348543082 created_at=2026-11-01T20:46:13Z conclusion=success
      id=41325470916 created_at=2026-11-01T16:16:23Z conclusion=success
      id=41291765000 created_at=2026-11-01T09:08:04Z conclusion=success
      id=41263764445 created_at=2026-11-01T02:05:55Z conclusion=success
```

발화 간격이 2.05→9.08→16.16→20.46→00.33(Z)로 nominal 30분 cadence가 아닌
**불규칙 간격(≈4h–7h)** — Q10("늦고 불규칙한 best-effort 차량")의 현재
재현이다. 차량은 살아 있으며, §2.1 S1 각주(관측 창 내 schedule event run의
존재가 기준)의 전제를 지지한다.

**OBS-13 — 라우터 최근 발화 event 분포(보조)**

```
명령: gh api 'repos/Archright/Axiom/actions/workflows/ci-provider-router.yml/runs?per_page=5'
결과: 전부 event=workflow_run (2026-11-02T02:58:44Z–03:01:51Z, success×4 +
      in_progress×1) — 최근 전이 발화는 workflow_run 이벤트 차량으로 관측됨.
```

**OBS-11 — 저장소 가시성·활동(60일 비활성화 조항 전제 확인용)**

```
명령: gh api repos/Archright/Axiom --jq '{private, visibility, default_branch, pushed_at, updated_at}'
시각: GitHub-clock 2026-11-02T03:02:03Z
결과: private=true, visibility=private, default_branch=main,
      pushed_at=2026-11-02T03:01:23Z, updated_at=2026-11-02T02:58:08Z
```

### 1.5 GitHub 공식 문서 주의사항 (Context7 `/websites/github_en_actions`, 2026-11-02 조회)

조회 소스: docs.github.com "Events that trigger workflows — schedule" 및
"Troubleshooting workflow triggers". 공식 문서 근거 4가지:

1. **고부하 지연·drop**: "The `schedule` event can be delayed during periods
   of high loads of GitHub Actions workflow runs. High load times include the
   start of every hour. If the load is sufficiently high enough, some queued
   jobs may be dropped."
2. **default branch 전용**: scheduled workflows run only on the default
   branch(워크플로 파일이 default branch에 존재해야 발화).
3. **60일 무활동 자동 비활성화**: "In a public repository, scheduled workflows
   are automatically disabled when no repository activity has occurred in 60
   days." — 전제가 **public repository**다. OBS-11에서 본 저장소는
   `private`로 관측됐으므로 이 조항의 전제는 현재 성립하지 않는다(관측값
   그대로 기록; 판정 보류). 12월 분류 (b)의 원인 조사 시 확인 항목으로 유지.
4. **UTC 기준**: "By default, scheduled workflows run in UTC." — 계약 §3의
   달력월 경계(00:00:00 UTC 리셋) 비교와 정합.

**계약과의 정합**: (1)은 계약 §2.1 S1 각주(지연 자체는 성공 판정을 무효화하지
않는다 — 관측 창 내 schedule event run의 존재가 기준)와 정합하며, "queued jobs
may be dropped"는 분류 (b)의 원인 조사 목록에 포함됐다. OBS-1의 `:00/:30 회피`
cron 설계도 (1)의 권고("schedule your workflow to run at a different time of
the hour")와 정합한다.

### 1.6 시계 기준 주의 (계약 §3)

- 본 기록의 GitHub API 타임스탬프는 전부 **GitHub-clock 단독**이다.
- 라우터 변수값 `last_transition_at`은 라우터 clock으로 병기한다(OBS-4).
  참고로 복귀수용 문서 §2는 2026-11-01 시점 Northflank 제어면 러너 시계
  **−1h** 관측을 기록한다. 본 관측 시점의 한 쌍(last_transition_at
  02:59:05Z vs GitHub 측 updated_at 02:59:12Z)은 약 7초 차이로 −1h 오프셋이
  이번 쌍에서는 관측되지 않았다 — 단, 이것이 시계 드리프트의 소멸을 증명하지
  않는다. 12월 판정 시에도 계약 §3 원칙(GitHub-clock 단독 비교 + 라우터 clock
  병기)을 그대로 적용한다.

### 1.7 readiness 결론

- **판정 아님** — 본 절은 readiness 기록만 담는다. 12월 실제 판정은 계약 §2
  기준 + §1.2 분류로 12월 사건 이후 별도 작업에서 수행된다(§2.4 — 사후 기준
  변경 금지).
- 발화 차량(schedule cron `7,37 * * * *`, OBS-1)·canary 차량(workflow_dispatch
  단일, OBS-2)·변수 읽기 경로(OBS-3)는 계약 §1 서술과 일치했고, 라우터 현재값
  (OBS-4)은 예상(GHEC_ACTIVE/confirmed/generation 15)과 일치했다. schedule
  차량은 생존해 있으나 불규칙 간격(OBS-12) — S1 각주의 전제와 정합.
- 현재 GHEC_ACTIVE 상태로 12월 창이 맞이되면 분류 (a) 정상 미발동이
  기대값이다. 폴백이 발생하면 §1.2 분류로만 판정한다.

## 2. webhook 재평가 조건 확인 (ADR-0039)

### 2.1 ADR 상태 확인

`docs/adr/0039-workflow-job-webhook-non-adoption.md` — Status: **Accepted
(2026-11-02)**. 표기 유의: 'CLOSED'는 ledger 상태가 아니라 **미채택 결정
유지**의 표현이다. Decision: "`workflow_job` webhook을 도입하지 않는다. 기존
API census가 자기완결적 관측 권위로 유지된다." 재평가는 "4개 조건이 **모두
실측으로** 충족될 때만" 연다.

### 2.2 4조건 재실측 (읽기 전용, 2026-11-02)

| # | 조건(원문 요지) | 재실측 명령 → 관측 결과 | 판정 |
|---|---|---|---|
| ① | 실 `workflow_job` payload의 runner identity 필드(`runner_group_id` 등) **수신 실측** | `gh api repos/Archright/Axiom/hooks` → **`[]`** (빈 배열, GitHub-clock 2026-11-02T03:00:54Z) — webhook 구성 0건이므로 수신 자체가 구조적으로 불가. `git grep -n 'workflow_job' origin/main -- .github/` → **매치 0건**(rc=1). 유의: REST jobs 조회(census)는 **별개 채널**이며 payload 수신 실측이 아니다. | **미충족** |
| ② | webhook 스트림 ↔ API census 대조의 누락·중복률 **정량 측정** + reconciliation 경로 입증 | 수신 스트림이 존재하지 않으므로(①) 대조 측정의 대상 자체가 없다. `git grep -iln 'webhook' origin/main -- data/` → 유일 매치 `data/promotions/baseline/authorities.md:71`은 "hooks → 빈 배열"의 과거 관측 기록(본 관측과 일치)이지 측정 artifact가 아니다. | **미충족** |
| ③ | webhook **수신 기질**(상주 수신기) 확보 — Northflank 제어기 배치 3제약(C1–C3) 상속 | `git grep -iln 'webhook' origin/main -- .github/workflows/` → 유일 매치 `probe-merge-queue.yml:51`은 merge_group payload 문서 주석(수신기 아님). 상주 수신기 인프라·App 구성 없음(`repos/Archright/Axiom/installation` GET → 401 "A JSON web token could not be decoded" — 이 endpoint는 App JWT 인증 전용이라 user token으로는 미관측; 관측 한계 그대로 기록). `orgs/Archright/hooks` GET → 404(admin:org_hook scope 필요 — 관측 한계 그대로 기록). | **미충족** |
| ④ | 실제 절감 > 수신기 유지 비용의 **실측 비교** | 비교 측정 artifact 부재(data/에 수신기 유지 비용·rate 소진 비교 기록 없음). census의 현재 사용 패턴은 사건 기반 일회성 — ADR이 예상한 대로 절감은 미확정 상태. | **미충족** |

관측 한계 명시: ①·③의 GitHub 측 관측은 repo-scope hooks 목록과 git 트리가
권위다. org/App 계층은 위 표기대로 scope·인증 한계로 미관측이며, 그 사실 자체를
본 기록에 그대로 남긴다(관측 못 한 것은 못 했다고 기록 — AGENTS.md §0.9).

### 2.3 결론

- 4조건 **전부 미충족** → **ADR-0039 미채택 결정 유지, 추가 작업 없음**.
- 재평가 조건 중 **하나라도 실측으로 충족**되면 별도 워크스트림으로만 재개한다
  (ADR Consequences "재개 통제" — 충족 관측은 별도 증거 기록으로 남긴다). 본
  기록은 재개 조건의 충족을 주장하지 않는다.

## 3. 범위·준수

- 본 변경은 신규 파일 1개(본 문서)뿐이다 — 기존 정본·ledger·설정 0수정, 코드
  0변경, 워크플로 0변경. 모든 관측은 읽기 전용 GET/git 조회다.
- 극장 금지(§0.9): 관측하지 못한 것(org/App 계층, 12월 사건)은 못 했다고
  기록했다. 성공 주장 없음 — 본 문서는 판정을 수행하지 않는다.
- 준수: AGENTS.md §0.5(문서 우선 — 12월 계약·ADR-0039를 관측에 앞서 읽음),
  §2.1(전용 workstream 브랜치 `work/closure-observations`), §2.2(관측 전 완료
  주장 금지), operations.md Worktree Bootstrap(저장소 밖 worktree).

## 참조

- `docs/spec/ci_provider_december_unattended_fallback_acceptance_contract.md`
  — §2 판정 기준(유일 정본), §2.1 S1–S3+각주, §2.3 UNKNOWN, §2.4 사후 기준
  변경 금지, §3 관측 창, §4 증거 세트, §5 단일 writer
- `docs/adr/0039-workflow-job-webhook-non-adoption.md` — 미채택 결정 + 재평가
  4조건(①–④), 플랫폼 팩트 F1–F8
- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` — 11월
  GHEC 복귀 수용(OBS-4 상태의 직전 이력), §2 시계 병기, §6 잔여
- `docs/spec/ci_provider_failover_quirks.md` — Q10(schedule best-effort),
  Q11(월 경계 리셋), Q5(단일 writer)
- docs.github.com — Events that trigger workflows(schedule), Troubleshooting
  workflow triggers(2026-11-02 Context7 `/websites/github_en_actions` 확인)
