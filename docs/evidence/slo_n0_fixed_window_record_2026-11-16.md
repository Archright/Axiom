# 관측 기록 — 종료된 고정창 n=0 (2026-11-16)

> **종류**: 관측 기록 (observation record). 2026-11-15~16 관측 활동에서 관측 개시 전에 고정·
> 종료까지 대기한 6h 고정창의 관측 사실(n=0)을 종결 기록한다. 본 문서는 **판정이 아니다**(P95
> 미산출·PASS/FAIL 아님 — §1)·**사전등록이 아니다**(본 문서가 기록하는 창은 이미 종료됐다).
> 공식 판정창의 등록은 동일 PR에 동반 착지하는 `slo_judgment_window_prereg_2026-11-16.md`가
> 담당한다.
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE
> commit)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 어떤 게이트도 본 문서의 값을
> 소비하지 않는다.
> **Date**: 2026-11-16 · **Branch**: `docs/slo-window-registration-20261116` · **Scope**: 본 문서 +
> 동반 창 등록 문서 2건(docs-only 비행 — 코드·워크플로우·게이트·핀·도구 변경 0건, trust surface
> 아님, 정상 merge queue 경로).
> **관측 규율**: GET-only · `gh` 네이티브 인증(AGENTS.md §2.4) · REST core 5,000 req/h 이내 ·
> 타임스탬프 초 단위(±1s).
> **계약 준수 선언**: 관측은 관측 이전에 동결된 측정 계약 §2 공식 지표·§4 모집단·§6 R-7·§7 표본
> 기준·§9 프로토콜을 따랐다. 관측 후 기준 변경 0건(§10 — 변경은 새 날짜의 사전등록 문서로만).

---

## §0. 상속·참조 권위 (본 문서는 아래를 대체하지 않는다)

| 권위 | 내용 | 위치 |
|---|---|---|
| 측정 계약(동결 본체) | 공식 지표·모집단·censoring 역치·R-7·n≥30·관측 프로토콜·소급 수정 금지. 원 등록의 이슈 참조(#1166)는 현 저장소(클린룸 재구축)에서 404(관측 확인) — **착지된 계약 문서가 SSOT** | `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` 전체 |
| 계약 세부 조항 | official_wall §2 · 모집단·취소·censoring §4 · R-7 §6 · 표본 기준·창 선언 §7 · 프로토콜 §9 · 소급 수정 금지 §10 | 같은 문서 |
| SLO of record | Merge Queue wall P95 ≤ 480s = policy — 헌법 불변식 아님, 유지·계승 | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135 |
| 선행 공식 판정(참조 — 비교 아님) | 2026-11-03 FAIL — R-7 P95 756.9s(n=30). 본 문서와 소급 비교하지 않는다(§10) | `docs/evidence/slo_official_judgment_2026-11-03.md` |
| P95 어휘 | N≥30 도달 전 p50/p95는 "잠정·미산출" | `docs/evidence/residual_issue_ledger_2026-10-31.md` RESID-09 |
| 목록 누락 quirk | `event=merge_group` 목록이 실존 런을 누락 — 경계·판정 대상 런 단일 GET 교차검증 | `docs/spec/gh_run_observation_quirks.md` Q16 |
| 관측 기록 선례(구조 계승) | 종결 시각·표본 표·통계·재현 명령·편향 점검 구조 | `docs/evidence/slo_official_window_observation_2026-11-03.md` |
| 동반 창 등록 문서 | 본 문서와 동일 PR 착지 — 상호 참조 전용·값 비상속(§3) | `slo_judgment_window_prereg_2026-11-16.md` |

## §1. 관측 대상 창 — 종료된 고정창, n=0

- **창**: `[2026-11-15T19:46:57Z, 2026-11-16T01:46:57Z]` (6h 고정창, UTC, 런 `created_at` 기준
  GitHub-clock — 측정 계약 §7 창 소속 축 계승). 창 양 끝은 관측 개시 시점(2026-11-15T19:46:57Z,
  `date -u`)에 고정됐고, 종료까지 이동·확장 없이 대기했다(유리한 표본 선택 금지 준수 — 창은 6h
  고정으로 종결).
- **창의 성격(정직 귀속)**: 본 창은 관측 개시 전 고정됐으나 **착지된 사전등록 문서 없이 운영된
  창**이다 — 창 등록 문서(2026-11-02 선례 계층)가 착지되기 전에 관측이 진행됐다. 따라서 본 창을
  공식 판정창으로 소급 승격하지 않는다(§4) — 본 문서는 이 창의 관측 사실(n=0)을 종결 기록할
  뿐이다. 공식 판정은 동반 창 등록 문서가 **관측 이전에** 등록하는 새 창에서 수행된다.
- **관측 결과**: 공식 모집단(창 내 완료 admission-gate merge_group 런, conclusion ∈ {success,
  failure}) 표본 **n=0**.
- **n=0의 의미**: 판정 가능 표본 부재 — P95 **미산출**(계약 §7), p50 미산출(표본 0 — 잠정값조차
  불가). **480s PASS도 FAIL도 아니다.** 과거 판정값(예: 2026-11-03 FAIL 756.9s)을 현재 baseline으로
  단정하지 않는다 — 본 창에는 산출값 자체가 존재하지 않는다.

## §2. 관측 사실·재현 (GET-only — 영구 동결)

창은 종료됐고 모든 관측은 창 종료 후 수행됐다 — 창 내 런은 생성 시점에 확정돼 있으므로 아래
질의는 시간이 지나도 동일 결과를 반환한다(동결 사실).

| 관측 | 결과 |
|---|---|
| (a) 정창 질의 `event=merge_group`, 창 범위 | `total_count` = **0** — 2026-11-16T03:44:04Z 관측·본 문서 작성 세션(약 04:00Z) 재현, 2회 일치 |
| (b) 무필터 대조(전 이벤트) 같은 창 | `total_count` = **1** — 유일 런 `43773358856` (name=publication-integrity, event=schedule, created 2026-11-15T23:10:34Z, success). merge_group 런 0건의 교차확정: 창에 CI가 없었던 게 아니라 **merge_group(착지) 트래픽만 0**이었다 |
| (c) 창 직전 마지막 merge_group 런 | `43714071875` (pr-105, created 2026-11-15T12:29:07Z, updated 12:36:12Z, success) = PR #105 착지 라운드. 이후 관측 시점(2026-11-16T04:00Z)까지 merge_group 신규 생성 0건 — 큐 유휴 |
| (d) main 상태 | main 팁 = `717f9c6ebb`(PR #105 native MERGE 커밋), 이후 main 커밋 0건. 창에 표본이 없는 원인은 **실착지 트래픽 부재**(관측 사실 — 이상 원인 추측은 기록하지 않는다) |

```bash
# (a) 정창 — n=0 재현
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-15T19:46:57Z..2026-11-16T01:46:57Z&per_page=100" \
  --jq '{t:.total_count,n:(.workflow_runs|length)}'
# (b) 무필터 대조 — 유일 schedule 런 1건
gh api "repos/Archright/Axiom/actions/runs?created=2026-11-15T19:46:57Z..2026-11-16T01:46:57Z&per_page=100" \
  --jq '[.workflow_runs[]|{id,name,event,conclusion,created_at}]'
# (c) 창 직전 마지막 착지 라운드 + 큐 유휴(관측 시점 기준)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=>2026-11-15T12:36:12Z&per_page=100" --jq '.total_count'
gh api repos/Archright/Axiom/actions/runs/43714071875 \
  --jq '{id,name,event,conclusion,created_at,updated_at,run_attempt,head_branch}'
# (d) main 팁
gh api repos/Archright/Axiom/git/ref/heads/main --jq .object.sha
```

## §3. 24h 비공식 룩백 (창 밖 참고 문맥 — 공식 표본 아님·사후 편입 아님)

**지위 선언(최우선)**: 아래는 **미등록 창의 비공식 진단 문맥값**이다 — 공식 판정 표본이 아니며
(창 등록 없음), n<30이므로 RESID-09 어휘상 잠정값이다. 동반 창 등록 문서가 등록하는 새 창에는
**값을 상속하지 않는다**(그 창의 since는 등록 문서 착지 시각이므로 아래 관측 전부는 창 밖이다 —
사후 편입 금지 준수).

### 3.1 룩백 R1 — [2026-11-15T00:00:00Z, 2026-11-16T01:46:57Z] 전수 센서스

- **전수성(측정 계약 §9 프로토콜 집행)**: merge_group 런 총 252건 = admission-gate 28그룹 ×
  9 워크플로우(landing-integrity·probe-merge-queue·generation-acceptance·observer-manifest-
  consistency·debt-registry-gate·bsec-integrity·axiom-operational-slice·publication-integrity·
  admission-gate). 3페이지 열거 100+100+52 = `total_count` 252 일치·page4 빈 응답 종결(페이지네이션
  완결 증명 — 2026-11-16 본 문서 작성 세션 재검증)·252 ≪ 1000(Q16 유효창).
- **모집단(측정 계약 §4 준용)**: admission-gate 완료 런 **n=28** — success 25·**failure 3**
  (`43677909905` pr-84·`43681074928` pr-88·`43681466381` pr-89)·cancelled 0. `run_attempt` 전부
  1(재실행 0 → official_wall ≡ latest_attempt_wall)·`run_started_at == created_at` 전 런(큐 대기
  0s 관측). **head_branch 28/28 고유** — 동일 그룹 재도크·dequeue 중간 완료 런 0건(§4 (ii)
  미발동). 단일 GET 교차검증: 선행 관측에서 28/28 일치, 본 문서 작성 세션에서 4런 재검증 일치
  (`43714071875`·`43673367785`·`43671902223`·`43671765678`).
- **관측 비고(추측 없음)**: pr-84·pr-86(및 pr-88·pr-89·pr-90)은 head_branch의 SHA 접미가 서로
  일치하는 관측이 있다. 그룹 정의 축(head_branch 전체 문자열 — 계약 §4)상 전부 별개 그룹이며,
  SHA 접미 일치의 원인은 본 문서가 해석하지 않는다(추측 금지 — 계약 §8 계승).
- **통계 (R-7 — 비공식·잠정)**:

| 항목 | 값 |
|---|---|
| n | 28 |
| min | 227.0s |
| p50 (R-7) | 368.5s |
| 산술평균 mean | 367.0s |
| **P95 (R-7, 비공식 참고)** | **438.75s** |
| max | 453.0s |

- **28런 표** (official_wall = `updated_at − created_at`, 초 단위 정수 — 계약 §2):

| # | run id | PR (head_branch) | conclusion | created_at (UTC) | updated_at (UTC) | official_wall |
|---|---|---|---|---|---|---|
| 1 | 43671765678 | pr-78 | success | 2026-11-15T03:18:32Z | 2026-11-15T03:26:05Z | 453 |
| 2 | 43671902223 | pr-77 | success | 2026-11-15T03:20:19Z | 2026-11-15T03:27:43Z | 444 |
| 3 | 43673367785 | pr-79 | success | 2026-11-15T03:39:50Z | 2026-11-15T03:46:48Z | 418 |
| 4 | 43674152596 | pr-80 | success | 2026-11-15T03:50:40Z | 2026-11-15T03:56:23Z | 343 |
| 5 | 43676407342 | pr-81 | success | 2026-11-15T04:21:28Z | 2026-11-15T04:27:20Z | 352 |
| 6 | 43677390737 | pr-83 | success | 2026-11-15T04:34:53Z | 2026-11-15T04:41:37Z | 404 |
| 7 | 43677582560 | pr-82 | success | 2026-11-15T04:37:28Z | 2026-11-15T04:43:34Z | 366 |
| 8 | 43677909905 | pr-84 | **failure** | 2026-11-15T04:42:09Z | 2026-11-15T04:47:46Z | 337 |
| 9 | 43678930448 | pr-86 | success | 2026-11-15T04:56:50Z | 2026-11-15T05:03:59Z | 429 |
| 10 | 43679517638 | pr-87 | success | 2026-11-15T05:04:59Z | 2026-11-15T05:11:43Z | 404 |
| 11 | 43679583825 | pr-85 | success | 2026-11-15T05:05:50Z | 2026-11-15T05:11:29Z | 339 |
| 12 | 43681074928 | pr-88 | **failure** | 2026-11-15T05:26:14Z | 2026-11-15T05:30:02Z | 228 |
| 13 | 43681466381 | pr-89 | **failure** | 2026-11-15T05:31:49Z | 2026-11-15T05:35:36Z | 227 |
| 14 | 43682601567 | pr-90 | success | 2026-11-15T05:47:47Z | 2026-11-15T05:54:23Z | 396 |
| 15 | 43682969867 | pr-91 | success | 2026-11-15T05:53:01Z | 2026-11-15T05:59:03Z | 362 |
| 16 | 43687646229 | pr-92 | success | 2026-11-15T06:55:52Z | 2026-11-15T07:01:27Z | 335 |
| 17 | 43689413660 | pr-93 | success | 2026-11-15T07:19:14Z | 2026-11-15T07:24:34Z | 320 |
| 18 | 43692723350 | pr-94 | success | 2026-11-15T08:03:36Z | 2026-11-15T08:09:56Z | 380 |
| 19 | 43697015176 | pr-95 | success | 2026-11-15T08:59:11Z | 2026-11-15T09:05:49Z | 398 |
| 20 | 43698261814 | pr-99 | success | 2026-11-15T09:14:19Z | 2026-11-15T09:21:08Z | 409 |
| 21 | 43700168843 | pr-98 | success | 2026-11-15T09:37:51Z | 2026-11-15T09:43:06Z | 315 |
| 22 | 43701453154 | pr-96 | success | 2026-11-15T09:54:01Z | 2026-11-15T10:00:40Z | 399 |
| 23 | 43701454109 | pr-97 | success | 2026-11-15T09:54:02Z | 2026-11-15T10:00:13Z | 371 |
| 24 | 43704016291 | pr-100 | success | 2026-11-15T10:25:35Z | 2026-11-15T10:31:55Z | 380 |
| 25 | 43705994592 | pr-102 | success | 2026-11-15T10:50:16Z | 2026-11-15T10:55:45Z | 329 |
| 26 | 43710843428 | pr-103 | success | 2026-11-15T11:50:19Z | 2026-11-15T11:56:23Z | 364 |
| 27 | 43711675823 | pr-104 | success | 2026-11-15T12:00:52Z | 2026-11-15T12:06:41Z | 349 |
| 28 | 43714071875 | pr-105 | success | 2026-11-15T12:29:07Z | 2026-11-15T12:36:12Z | 425 |

- **epoch(진단 참조)**: 선행 심층 관측(최근 완료 3런 잡 분해)에서 실행 잡 전부
  `runner_group_id=0`(GitHub-hosted = GHEC) — 2026-11-01T10:53:18Z 복귀 이후 단일 epoch 층
  (측정 계약 §5 진단층 준용).

### 3.2 룩백 R2 — [2026-11-15T03:44:04Z, 2026-11-16T03:44:04Z] (T_snap = 2026-11-16T03:44:04Z)

R1의 부분집합이다(00:00:00~03:44:04Z 생성 3런 pr-77·pr-78·pr-79 제외 — 별도 표를 만들지 않는
것이 누락이 아님: R1 표에 28런 전수가 실려 있다). merge_group 225런 = admission-gate 25그룹 ×
9(3페이지 완결). **n=25** — success 22·failure 3(같은 3런)·cancelled 0·`run_attempt` 전부 1.

| 항목 | 값 (비공식·잠정) |
|---|---|
| n | 25 |
| min | 227.0s |
| p50 (R-7) | 364.0s |
| 산술평균 mean | 358.4s |
| **P95 (R-7, 비공식 참고)** | **421.8s** |
| max | 429.0s |

### 3.3 페이지네이션 효과 공개 (관측 위생 — 조용한 소멸 금지)

T_snap 시점 1페이지(`per_page=100`, page 1만) 재질의에서는 admission-gate 완료 런 **11건만**
관측됐다(반환된 최신 100런 중의 게이트 런 — 나머지 125런 미열거). 본 문서의 기록값은 페이지
완결을 증명한 전수 센서스(R1·R2)를 따른다. 이는 선례 스냅샷(`slo_status_snapshot_2026-11-02.md`
§3.1 "1페이지 한도로 13건 — `--paginate`로 +2 복원")과 동일한 페이지네이션 잘림 효과의
재실측이다 — **목록 질의는 페이지 완결 증명 없이는 인용되지 않는다**(계약 §9 정신의 집행
기록).

### 3.4 룩백의 해석 한계

- 두 룩백 P95(438.75s·421.8s)가 480s 미만이라는 사실은 **공식 판정을 대체하지 않는다** — 공식
  판정은 동반 창 등록 문서가 등록한 창에서 n≥30 자연 도달 시 별도 판정 보고 문서가 내린다
  (결과-맹겸).
- n=28·25 < 30 — 잠정 어휘(RESID-09). 창 경계가 다르면 값이 달라진다(438.75 vs 421.8) — 비공식
  문맥값의 창 의존성 관측.
- 큐 대기 0s·`run_attempt` 전부 1 관측은 이 기간에 재시도·큐 적체가 없었음을 보여줄 뿐, 그
  이상의 인과 주장이 아니다.

### 3.5 재현 명령

```bash
# R1 전수 센서스(3페이지 + page4 빈 응답 = 페이지네이션 완결 증명)
for p in 1 2 3 4; do
  gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-15T00:00:00Z..2026-11-16T01:46:57Z&per_page=100&page=$p" \
    --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id,.conclusion,.created_at,.updated_at,.run_attempt,.head_branch]'
done
# R1 total_count(=252) 확인
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-15T00:00:00Z..2026-11-16T01:46:57Z&per_page=1" --jq '.total_count'
# R2 — T_snap 24h 폐쇄 구간(=225, admission-gate 25)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-15T03:44:04Z..2026-11-16T03:44:04Z&per_page=100" --jq '.total_count'
# 경계·대표 런 단일 GET 교차검증(Q16)
gh api repos/Archright/Axiom/actions/runs/43714071875 --jq '{id,name,path,event,conclusion,created_at,run_started_at,updated_at,run_attempt}'
# P95·p50 — 측정 계약 §6 고정 percentile_r7 코드 그대로(재정의 금지)
```

## §4. 완료 상태·한계

- **완료**: n=0 고정창의 관측 기록으로서 종결 — 창·질의·결과·문맥의 전부가 본 문서에 동결됐다.
  본 문서는 append-only(계약 §10 — 소급 수정·재분류·재분모화 금지).
- **본 문서가 아닌 것**: 판정 아님(§1)·공식 판정창 등록 아님(동반 문서가 담당)·최적화 트리거
  아님(n=0 또는 룩백 값이 자동 후속 작업을 발생시키지 않는다 — 다음 창 등록은 동반 문서로
  이미 결정됐고, 그 외 후속 조치는 인간 결정 영역이다).
- **한계**: org 수준 런 목록 엔드포인트 부재(404 실측 — org 축 독립 교차검증 불가; 목록 스윕·
  무필터 대조·단일 GET 교차검증으로 상쇄, Q16 잔여 위험은 완전 소거 불가 — 한계로 등록).
  타임스탬프 초 단위(±1s). R1·R2 창은 관측 시점 이후 생성 런을 포함하지 않는다(T_snap 이후
  생성 런의 사후 편입 없음 — R1·R2의 전 런은 관측 시점 이미 종결).
