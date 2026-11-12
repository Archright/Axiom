# ci-cache-publisher cancelled 런 24건 포렌식 — 취소 주체 판정 (2026-10-31)

> **이 문서가 기록하는 것**: 2026-10-30 관측 창(11:11:39Z–12:15:21Z,
> `ci_three_venue_decomposition_2026-10-30.md` §5)에서 ci-cache-publisher
> cancelled 24건의 **취소 주체**를 기계 증거로 판정한 결과다. **코드·config·
> workflow 변경은 없다**(문서 1개 추가). 착지 판정 권위는 GitHub이며(AGENTS.md
> §2.3), 본 문서는 관측 기록이다.
> 선행 문서: `ci_three_venue_decomposition_2026-10-30.md` §5(취소 주체를
> "로그 미열람" 한계로 남긴 문서 — §7.6), `ci_provider_epoch_2026-10-30.md`.

---

## 1. 질문 · 판정 요약

**질문** — VS-A 문서 §5의 표: `cancelled | 24 | 0 | 잡 생성 전 취소(연속 재트리거 dedupe)`.
24건의 취소 주체는 (i) 워크플로 선언 기반 자동 취소, (ii) 업스트림 이벤트 소실·
재발화에 따른 GitHub 측 처리, (iii) 수동 개입 중 무엇인가?

**판정** — **(i) 워크플로 자신의 concurrency 선언(`ci-cache-publisher.yml:185-187`)
을 GitHub 플랫폼이 집행한 pending 대기열 축출(eviction)이다.** 인간의 수동 취소도
이벤트 소실도 아니며, 이는 장애가 아니라 파일 헤더(:63-68, :179-184)에 설계
문서된 동작이다. 근거 4축:

1. **선언**: workflow-level concurrency, group은 비보간 상수 문자열,
   `cancel-in-progress: false`, `queue` 프로퍼티 없음(= 공식 기본값 `single`) —
   `ci-cache-publisher.yml:185-187`.
2. **공식 의미론**: cancel-in-progress: false여도 "any existing `pending` job or
   workflow in the same concurrency group **will be canceled** and the new queued
   job or workflow will take its place"(GitHub 공식 문서 — §3 인용).
3. **정량 상관**: 관측 창 전체 census의 cancelled **43/43**(4-SHA census 범위
   **24/24**)이 "시간순 다음 도착 런 created_at ≤ 3초 후"에 취소됐다(§4.4).
   결정적 도착-취소 인과 외의 설명 없음.
4. **비집행 증거**: cancelled 런 24건 전부 잡 0건·러너 0·로그 0(22바이트 빈 zip,
   §4.3) — 대기(pending) 상태에서 취소됐다. 실행을 취소한 흔적이 없다.

**정정 2건(선행 문서 대비)** —

- "잡 24건 cancelled"이 아니라 **런 24건이 cancelled, 잡 0건**이다 (jobs API
  `total_count=0` × 24 — §4.2). VS-A §5 표의 "잡 0"은 정확했다.
- VS-A §5의 "workflow_run 런은 트리거 원런의 head_sha를 상속"은 **정확하지 않다** —
  runs API의 head_sha는 **기본 브랜치(main)의 최종 커밋**이다(GitHub 공식 문서:
  `GITHUB_SHA` = "Last commit on default branch"; 실측 5세대 경계 — §4.5).
  VS-A 관측 창에서 merge commit이 곧 main HEAD였으므로(`max_entries_to_merge=1`,
  VS-A §3.1) 두 값이 우연히 일치해 보였던 것. 이 정정에 따라 4-SHA 단발 조회의
  커버리지 의미도 "각 SHA가 main HEAD였던 구간에 생성된 런"으로 한정된다(§4.5).

---

## 2. 정적 구조 — file:line (기준 커밋 53e49e1139, work/inv-cpub)

| 항목 | 위치 | 내용 |
|---|---|---|
| 트리거 | `ci-cache-publisher.yml:170-173` | `workflow_run` / `workflows: ['*', '!ci-cache-publisher']` / `types: [completed]` — **모든 워크플로 완료 1건당 이 워크플로 런 1개가 발화**된다 |
| concurrency | `ci-cache-publisher.yml:185-187` | `group: ci-cache-publisher-single-flight`(상수 문자열 — `github.*` 비보간 → 전 저장소 단일 그룹), `cancel-in-progress: false`, `queue` 선언 없음 |
| 설계 주석 | `ci-cache-publisher.yml:63-68` | "cancel-in-progress: false — 진행 중 publisher(A-seed·저장 완주)를 죽이지 않는다. **플랫폼 규칙상 그룹당 pending은 최신 1개만 보존되고 초과 대기 런은 취소되지만**, 생존 런의 (2) 사전조회가 dedup을 보장" — 본 문서가 관측한 축출은 이 문장이 예고한 동작이다 |
| 설계 주석(헤더) | `ci-cache-publisher.yml:179-184` | "이 그룹은 publisher 런만 지연시킨다 — 게이트·큐·병합 동작과 무관(이 워크플로는 admission-gate의 required check가 아니다)" |
| publish pre-filter | `ci-cache-publisher.yml:199` | job-level `if`: 트리거 conclusion == success ∧ path == admission-gate-v2 — 성공한 비게이트 완료는 잡 2개 모두 skipped(§4.2의 skipped 49런 × 2잡의 근거) |
| skip-report | `ci-cache-publisher.yml:752-762` | `if`: 트리거 conclusion != success — 비성공 완료에서 구조 라인 1개 출력 |
| 사전조회(save gate) | `ci-cache-publisher.yml:432-449, 660-677` | 취소된 발화가 저장을 못 해도 생존 런의 exact-key lookup-only가 저장 중복을 0으로 유지(단일-flight (2) 겹) |

전제 확인: `workflows: ['*']` 완화 필터는 **2026-10-15에 이미 착지**했다
(commit `808bdd166`, `git log -S"workflows: ['*'"`) — 관측 창 이전이므로 fan-out
자체는 신규 현상이 아니다. pre-landing main(`87fb70eda4`)과 착지 커밋
(`d308215817`)의 `:170-173`은 바이트 동일하게 확인했다.

---

## 3. 공식 문서 인용 (Context7 `/websites/github_en_actions` — 2026-10-31 조회)

**concurrency 대기열 축출** —
`docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency` 및
`docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax`:

> "This means that there can be at most one running job or workflow in a
> concurrency group at any time. When a concurrent job or workflow is queued, if
> another job or workflow using the same concurrency group in the repository is
> in progress, the queued job or workflow will be `pending`. **By default, any
> existing `pending` job or workflow in the same concurrency group will be
> canceled and the new queued job or workflow will take its place.**"

> "`queue` property … `single` (default): At most one job or workflow run can be
> `pending` in the concurrency group. **When a new job or workflow run is queued,
> any existing `pending` job or workflow run in the same group is canceled and
> replaced.**"

즉 `cancel-in-progress: false`는 **running 런을 보호**할 뿐, pending 축출은
기본 동작이다. 이 워크플로에 `queue: max` 선언은 없다(:185-187).

**workflow_run 발화·head_sha** —
`docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows`:

> "`workflow_run` … `GITHUB_SHA`: **Last commit on default branch**,
> `GITHUB_REF`: Default branch"
> "This event will only trigger a workflow run if the workflow file exists on
> the default branch."
> "You can't use `workflow_run` to chain together more than three levels of
> workflows." — `!ci-cache-publisher` 자기-연쇄 차단(:160-163)의 문서 근거.

⚠️ 구별: **이벤트 페이로드**의 `github.event.workflow_run.head_sha`는 트리거
원런의 head_sha이며(게시 identity 결속에 사용 — `ci-cache-publisher.yml:253`),
**runs API 런 객체**의 `head_sha`는 기본 브랜치 HEAD다(§4.5 실측). 두 필드는
다른 값을 가질 수 있다.

---

## 4. 실측 (재조회 — 원자료 /tmp/vsa_data 소실 대체의 정본 사본)

### 4.1 4-SHA 단발 재조회 — VS-A §1/§5와 1:1 일치

`gh api "repos/Archright/Axiom/actions/runs?head_sha=<sha>&per_page=100"` × 4:

| SHA | total | cache-publisher |
|---|---|---|
| `cf80d1d6af…` | 11 | 0 |
| `0f459db84e…` | 11 | 0 |
| `d308215817…` | 72 | 36 |
| `474392b113c…` | 53 | 41 |

cache-publisher 77런 = event `workflow_run` 77 · attempt 1 ·77 ·
conclusion **cancelled 24 / skipped 49 / success 4** — VS-A §5 총량과 정확히
일치한다(원자료 소실 후 재관측 성립).

### 4.2 잡 전수 스윕 — "런 24 취소, 잡 0"

77런 전부 `gh api repos/Archright/Axiom/actions/runs/<id>/jobs?per_page=100&filter=all`:

| run conclusion | runs | jobs | 잡 내역 |
|---|---|---|---|
| **cancelled** | **24** | **0** | 잡 생성 전 취소 — runner 없음 |
| skipped | 49 | 98 (런당 2) | `publish` skipped + `skip-report` skipped (예: 41049517735 → 잡 124041955088/124041988783) |
| success | 4 | **8** (런당 2) | 실행 잡 1 + 나머지 1 skipped (예: 41050775280 → `skip-report` success 6s, runner `gr9d113y4v8a2nb633wzchz904` + `publish` skipped) |
| **합계** | 77 | **106** | |

총량 106은 VS-A §5 헤더와 일치하나, VS-A의 내역 "skipped 102 + success 4"은
"**skipped 98 + success 8**"이 정확하다(VS-A는 success 런의 미실행 잡 4개를
미계상). 4-SHA 밖 런(§4.5)까지 포함하는 확장 census는 §4.4에 있다.

### 4.3 cancelled 런의 API 필드 전수 · 로그 엔드포인트

런 객체(예: 41049042984)가 노출하는 필드 전수 — **canceller 식별 필드는 존재하지
않는다**: `actor`·`triggering_actor` = `wintrover`(머지/푸시 수행자 — 취소자가
아니라 발화원), `conclusion: cancelled`, `run_attempt: 1`,
`created_at == run_started_at == 11:34:28Z`, `updated_at: 11:34:39Z`.

- `run_started_at == created_at`은 **실행 개시가 아니다** — 잡 0건(§4.2)이
  권위다. 이 런들은 pending에서 취소됐다(공식 문서 §3의 pending 정의와 일치).
- 로그: `GET /actions/runs/41049042984/logs` → **HTTP 200, 22바이트 zip, 엔트리
  0개**(`PK\x05\x06` end-of-central-directory만 존재; `zipfile.namelist() == []`).
  취소 원인 문구는 어디에도 없다 — "로그에서 취소 원인 확인" 경로는 구조적으로
  비어 있으며, 이것 자체가 pending-취소의 증거다(실행 중 취소였다면 최소 1개 잡의
  로그가 존재했을 것).

### 4.4 도착-취소 시간 상관 — 판정의 핵심 수치

**(a) 4-SHA census 범위(24건)** — 시간순 다음 cache-publisher 런의 `created_at`과
취소 시각(`updated_at`)의 차(delta, 초). 같은 초에 도착한 쌍(7541/7542)은 하나의
도착 배치로 상호 배위했다:

| run id | run # | created | cancelled_at | 다음 도착 | 도착 created | delta(s) |
|---|---|---|---|---|---|---|
| 41049042984 | 7536 | 11:34:28 | 11:34:39 | 41049061239 | 11:34:38 | +1 |
| 41049061239 | 7537 | 11:34:38 | 11:34:49 | 41049081488 | 11:34:48 | +1 |
| 41049081488 | 7538 | 11:34:48 | 11:34:56 | 41049095352 | 11:34:54 | +2 |
| 41049095352 | 7539 | 11:34:54 | 11:34:58 | 41049099839 | 11:34:57 | +1 |
| 41049099839 | 7540 | 11:34:57 | 11:35:03 | 41049110014 | 11:35:01 | +2 |
| 41049110029 | 7542 | 11:35:01 | 11:35:03 | 41049110014(동초 배치) | 11:35:01 | +2 |
| 41049110014 | 7541 | 11:35:01 | 11:35:32 | 41049171785 | 11:35:30 | +2 |
| 41049171785 | 7543 | 11:35:30 | 11:35:58 | 41049223847 | 11:35:56 | +2 |
| 41049223847 | 7544 | 11:35:56 | 11:35:58 | 41049225438 | 11:35:57 | +1 |
| 41049225438 | 7545 | 11:35:57 | 11:36:27 | 41049281744 | 11:36:26 | +1 |
| 41049281744 | 7546 | 11:36:26 | 11:36:58 | 41049342187 | 11:36:57 | +1 |
| 41049342187 | 7547 | 11:36:57 | 11:37:23 | 41049395526 | 11:37:22 | +1 |
| 41049395526 | 7548 | 11:37:22 | 11:37:44 | 41049436259 | 11:37:42 | +2 |
| 41049436259 | 7549 | 11:37:42 | 11:37:58 | 41049463267 | 11:37:57 | +1 |
| 41049463267 | 7550 | 11:37:57 | 11:38:26 | 41049517735 | 11:38:25 | +1 |
| 41051567362 | 7579 | 11:55:35 | 11:55:42 | 41051579604 | 11:55:41 | +1 |
| 41051579604 | 7580 | 11:55:41 | 11:56:02 | 41051619021 | 11:56:01 | +1 |
| 41051619021 | 7581 | 11:56:01 | 11:56:31 | 41051674728 | 11:56:30 | +1 |
| 41051674728 | 7582 | 11:56:30 | 11:56:37 | 41051685443 | 11:56:36 | +1 |
| 41051685443 | 7583 | 11:56:36 | 11:56:41 | 41051693502 | 11:56:40 | +1 |
| 41051693502 | 7584 | 11:56:40 | 11:57:00 | 41051728893 | 11:56:59 | +1 |
| 41051728893 | 7585 | 11:56:59 | 11:57:25 | 41051776452 | 11:57:23 | +2 |
| 41051776452 | 7586 | 11:57:23 | 11:58:08 | 41051859884 | 11:58:07 | +1 |
| 41051859884 | 7587 | 11:58:07 | 11:58:10 | 41051862715 | 11:58:08 | +2 |

→ **24/24, delta +1~+2초, 예외 0.**

**(b) 관측 창 전체 census(11:00:00Z–12:30:00Z, workflow-scoped)** —
`GET /actions/workflows/ci-cache-publisher.yml/runs?created=…&per_page=100&page=1..2`:
런 159(cancelled 43 · skipped 105 · success 11). 도착 배치(동일 created_at 그룹)
기준으로 **43/43이 "어떤 도착의 created_at ≤ 3초 후"에 취소** — 미해명 0건.
cancelled 런의 head_sha 세대 분포: `8ac1cd1149` 17 · `d308215817` 17 ·
`474392b113` 7 · `87fb70eda4` 1 · `a9b4dca685` 1. 취소 시각 범위
11:18:15Z–12:19:31Z — 4-SHA census(11:34:28–11:58:10Z)는 그 한 구간이다.

burst(도착 간격 수 초)에서는 연쇄 축출, 간격 ≥ ~30s에서는 잡 2개 skip으로 정상
종료(succeeded/skipped 꼬리) — 같은 메커니즘의 양면이다(§4.1 표의 11:38:25 이후
skipped 연속 구간).

### 4.5 head_sha = 기본 브랜치 HEAD — VS-A 정정의 실측 근거

세대 경계에서 런 객체의 head_sha가 **도착 시점의 main HEAD**로 바뀐다
(모두 API 실측):

| 전환 시점(main push) | 이전 세대 런 | 이후 세대 런 |
|---|---|---|
| ~11:34:1x `87fb70eda4` 착지 | `8ac1cd1149` 세대 (마지막 런 41048992716, 11:34:03Z) | 41049031672 (11:34:22, `87fb70eda4`) |
| 11:34:28 `d308215817` 착지 | 41049031672 | 41049042984 (11:34:28, `d308215817`) |
| ~14:16 `9b87ce7ca6` 착지 | run 7706 (`a9b4dca685`) | run 7707 (`9b87ce7ca6`) |
| ~14:20 `b16d25c1c2` 착지 | run 7720 | run 7721 |
| ~15:01 `53e49e1139` 착지 | run 7763 (`efa771dab3`) | run 7764 (`53e49e1139`) |

`87fb70eda4` 세대는 **단 1런**(41049031672, 생성 11:34:22 — 12초 main HEAD 수명)이며
11:34:29에 취소됐다. 취소 원인은 다음 도착 41049042984(생성 11:34:28,
`d308215817` 세대) — delta +1s. **group이 상수 문자열이므로(:185-187) 축출은 SHA
세대를 가로지른다.** 2026-10-30 하루 전체 cache-publisher 런은 421건(workflow
endpoint total, run #7673–7772 확인분은 14:01–15:00 창)이며 동일 패턴이 반복된다.

---

## 5. 취소 주체 판정 (3가지 가설 대조)

| 가설 | 판정 | 근거 |
|---|---|---|
| (i) 워크플로 선언 기반 자동 취소(concurrency pending 축출) | **CONFIRMED** | 선언 `:185-187`(§2) + 공식 의미론(§3) + **43/43·24/24 도착 ≤3초 상관**(§4.4) + 잡 0·러너 0·빈 zip(§4.3) + SHA 세대 가로지름 축출(§4.5) — 5축이 하나의 메커니즘을 가리킨다 |
| (ii) 업스트림 이벤트 소실·재발화에 따른 GitHub 측 처리 | **배제** | 소실 시나리오는 런 부재를 예언한다 — 실제로는 런이 생성됐고(창 내 159런) 결정적 도착-취소 인과가 있다. 재발화(dedupe)도 API에 흔적이 없으며 상관으로 설명 불가 |
| (iii) 수동 개입(UI/API cancel) | **배제 (시간 인과 추론)** | 43/43이 "도착 직후 ≤3초"에 취소 — 수동 취소는 도착과 무관한 시각에 흩어진다. 인간이 24회 연쇄 취소를 +1~2초 정밀도로 수행했다는 설명은 성립하지 않는다. 단, runs API에 canceller 필드가 없어(§4.3) **직접 관측에 의한 배제는 불가능** — 이 경계는 §6 UNKNOWN으로 명시한다 |

**취소 주체의 최종 기술**: GitHub 플랫폼이 `ci-cache-publisher.yml:185-187`의
concurrency 선언을 집행하여, `ci-cache-publisher-single-flight` 그룹에서 기존
pending 런을 취소하고 새 도착 런을 그 자리에 놓은 것이다. 인간(머지·푸시)은
도착(트리거 완료)의 원인일 뿐 취소 명령의 원인이 아니다. 이 축출은
`ci-cache-publisher.yml:63-68`이 설계 문서한 동작이며, 취소된 발화의 손실은
A-seed 성능 저하(J3 fail-open)로 국한되고 저장 중복은 생존 런의 lookup-only
(:432-449, :660-677)가 0으로 유지한다 — **cancelled 24건은 장애 기록이 아니라
설계 동작의 관측이다.**

---

## 6. 한계 · UNKNOWN (명시)

1. **canceller 필드 부재**: 공개 runs API에는 "누가 취소했는가" 필드가 없다
   (§4.3 필드 전수). 수동 개입 배제는 시간 인과 추론(강도: 결정적이지만 간접)이다.
   조직 감사 로그(`workflow_run` 취소 이벤트)는 본 세션 권한에서 조회하지 않았다 —
   **UNKNOWN으로 남긴다**(단, 43/43 상관과 모순되는 감사 기록이 없다는 가정 하에
   판정 (i)은 유지된다).
2. **트리거 원런 매핑 비보존**: 어떤 완료가 어떤 cache-publisher 런을 발화했는지는
   API에 저장되지 않는다 — 도착 시각 상관(±수 초)으로만 추정 가능. 본 판정은 이
   매핑에 의존하지 않는다(도착 = 그룹 내 새 런 생성 자체).
3. **run_started_at == created_at**은 이벤트 접수 시각이며 실행 개시가 아니다 —
   wait/exec 산출에 그 값을 쓰면 안 된다(잡 0이 권위).
4. census 범위: 창(11:00–12:30Z) 159런은 2페이지로 전수했다. 하루 전체 421런은
   전수하지 않았다(표본: 14:01Z 이후 100건 확인 — 동일 패턴).
5. VS-A 원자료(/tmp/vsa_data) 소실 — 본 문서의 표가 재관측 정본 사본이다
   (재현 명령 §8).

---

## 7. 상호 참조 — invq(merge-queue 실패 창) · PR #1128 (인용만, 접촉 없음)

- **시간 창 비겹침**: 본 문서의 취소 시각대는 11:18:15–12:19:31Z(창 전체 기준).
  invq가 조사 중인 merge-queue 1차 실패 창(14:20–14:47Z, MG 런 **41070945674** —
  admission-gate merge_group, head `53f0f39925`, queue branch
  `gh-readonly-queue/main/pr-1132-efa771dab3…`, created 14:20:02Z,
  conclusion failure 14:37:22Z)과는 **≥2시간 떨어져 있다**. 인과 연결 주장 없음.
- **기제 연속성만 기록**: 14:20–14:47Z에도 cache-publisher fan-out 런들이 존재하며
  main HEAD `b16d25c1c2`(runs 7721–7727 취소 + 7728 skipped 꼬리,
  14:20:16–14:21:10)·`efa771dab3`(runs 7743–7745 취소 + 7746 skipped 꼬리,
  14:32:37–14:33:22) 세대에 붙는다 —
  invq 런의 head_sha(`53f0f39925`)와는 다른 SHA다. 취소 메커니즘(§5-(i))은 하루
  전체에서 동일하나, invq의 manifest.txt 부재 문제(별도 조사)와의 접점은
  관측되지 않았다.
- **권위 분리**: cache-publisher는 필수 검사가 아니다 —
  `ci-cache-publisher.yml:184` "이 그룹은 publisher 런만 지연시킨다 — 게이트·큐·
  병합 동작과 무관". merge-queue admission 판정 권위는 GitHub ruleset이며
  cache-publisher 취소가 그 판정에 개입하지 않는다.
- **PR #1128**(`feat/cache-carrier-separation`, OPEN — "ci(cache): separate mg
  nimcache fold from required attest job — ci-cache-publisher base-seed
  absorption"): 관측 시점(2026-10-30)에 미착지 — 본 문서의 측정 대상 런들과
  무관하며 본 조사는 이 PR에 접촉하지 않았다.

---

## 8. 재현 명령

```bash
# (1) 4-SHA 재조회 (§4.1 — VS-A §10과 동일)
for s in cf80d1d6af4ca826325a973f9c4ad58c4a9ee0b6 \
         0f459db84e4c45a513aadfba0a4b86ea6a8aea85 \
         d308215817d2b499bebe2c074f69d339390c25a4 \
         474392b113cc646d2a93e9efd36c3f1e29d31dd9; do
  gh api "repos/Archright/Axiom/actions/runs?head_sha=$s&per_page=100" | \
    jq '[.workflow_runs[] | select(.name=="ci-cache-publisher")] | length'
done

# (2) 잡 전수 (§4.2 — 예: cancelled 런 하나)
gh api "repos/Archright/Axiom/actions/runs/41049042984/jobs?filter=all" | jq .total_count   # → 0

# (3) 로그 엔드포인트 (§4.3 — 22바이트 빈 zip)
gh api repos/Archright/Axiom/actions/runs/41049042984/logs > l.zip && ls -l l.zip

# (4) 창 전체 census (§4.4b)
gh api "repos/Archright/Axiom/actions/workflows/ci-cache-publisher.yml/runs?created=2026-10-30T11:00:00Z..2026-10-30T12:30:00Z&per_page=100&page=1"
gh api "repos/Archright/Axiom/actions/workflows/ci-cache-publisher.yml/runs?created=2026-10-30T11:00:00Z..2026-10-30T12:30:00Z&per_page=100&page=2"

# (5) 도착-취소 상관 (§4.4) — census JSON에 대해:
#   created_at 정렬 → 각 cancelled 런의 updated_at − (시간순 다음 런의 created_at)
#   동일 created_at 도착은 하나의 배치로 취급. 기대값: 전건 +1..+3초.

# (6) 구조 근거 (§2)
sed -n '160,190p' .github/workflows/ci-cache-publisher.yml   # on: / concurrency
```

측정 시점: 2026-10-31 09:30–10:00 KST (원 JSON은 세션 로컬 /tmp, 휘발성 — 본
문서 표가 정본 사본).
