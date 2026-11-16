# Pre-registration — 공식 SLO 판정창(문서 착지 정렬 창) 등록 (2026-11-16)

> **종류**: 사전등록 문서 (판정창 등록 — judgment-window registration). 동결된 공식 SLO 측정 계약
> (`docs/evidence/slo_official_measurement_prereg_2026-11-01.md`, 이하 "측정 prereg")의 **지표·
> 모집단·계산식·판정 규칙을 1도 변경하지 않고**, 그 계약이 모든 P95 보고에 요구하는 **관측 창
> 하나를 관측 이전에 고정**한다. 창이 닫힌 뒤의 판정은 본 등록 창과 동결 계약만으로 재현 가능해야
> 한다(§8).
> **표기(계약 지위)**: **동결 계약에 따른 공식 판정창(문서 착지 정렬 창) 등록 — 계약 불변**.
> 2026-11-02 등록 선례(세대 정렬 창)와 같은 등록 계층이며, 정렬점의 종류만 다르다(§2 — 현재 사용
> 가능한 구조적 사건이 다르기 때문).
> **관측값 미포함 선언(최우선 규정)**: 본 문서에는 wall 시간·P95·P50·min·max·현재 누적 표본 수
> 등 **지금까지 관측된 어떤 값도 기재하지 않는다**. 본 문서가 새로 등록하는 값은 창 양 끝의
> **규칙**(§2)뿐이며, 그 양 끝은 구조적 사건 시각(등록 문서 착지)과 계약상 고정 역치(표본 수)로만
> 결정된다(§3). 실측 타임스탬프는 창이 닫힌 뒤 판정 보고서가 기록한다(§2·§6).
> **Date**: 2026-11-16 · **착지 대상**: `docs/evidence/` · **Scope**: 본 문서 1건(docs-only) — 코드·
> 워크플로우·게이트·핀·도구 변경 0건, trust surface 비관여(정상 merge queue 경로). 동일 PR에는
> 별개 관측 기록 문서 `slo_n0_fixed_window_record_2026-11-16.md`가 동반 착지한다(§3 — 상호 참조
> 전용, 값 비상속).
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE
> commit)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 어떤 게이트도 본 문서의 값을
> 소비하지 않는다. 모든 관측은 GET-only·`gh` 네이티브 인증(AGENTS.md §2.4).

---

## §0. 상속·참조 권위 (본 문서는 아래를 대체하지 않는다)

| 권위 | 내용 | 위치 |
|---|---|---|
| 동결 계약 본체 | 공식 지표·모집단·censoring 역치·R-7·n≥30·관측 프로토콜·소급 수정 금지 — 본 문서가 상속하는 계약. 원 등록의 이슈 참조(#1166)는 현 저장소(클린룸 재구축 "Initial public source baseline")에서 **404(관측 확인)** — **착지된 계약 문서가 SSOT**다 | `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` 전체 |
| 측정 prereg 세부 조항 | official_wall §2 · 모집단·취소·censoring §4 · R-7 §6 · 표본 기준·창 선언 §7 · 관측 프로토콜 §9 · 소급 수정 금지 §10 | 같은 문서 |
| SLO of record | Merge Queue wall P95 ≤ 480s = **policy** — 헌법 불변식 아님, 유지·계승 | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135 |
| 판정창 등록 선례(구조 계승 원본) | 창 등록 구조·관측값 미포함·결과-맹겸 2단계·잔존 런 조항·§8 재현 템플릿. since 고정 자유도 근거("동결 계약에는 since 고정 규정이 없다") | `docs/evidence/slo_judgment_window_prereg_2026-11-02.md` §2·§4 |
| 관측·판정 선례 | 종결 집행·표본 표·통계·민감도 병기·재현 구조 | `slo_official_window_observation_2026-11-03.md` · `slo_official_judgment_2026-11-03.md` |
| 공급 상태 어휘 | EXECUTED/REUSED 상태 어휘·REUSED 5조건·fail-closed — 계약 본체가 재정의하지 않아 선행 계약에서 상속 | `docs/spec/test_judgment_cas_contract.md` §3·§5·§6 |
| 창 소속 축·시계 | 관측 창 `[since, until]` = 런 `created_at` 기준 GitHub-clock | 측정 prereg §7 |
| 목록 누락 quirk | `event=merge_group` 목록이 실존 런을 누락 — 경계·판정 대상 런 단일 GET 교차검증 | `docs/spec/gh_run_observation_quirks.md` Q16 |
| P95 어휘 | N≥30 도달 전 p50/p95는 "잠정·미산출" | `docs/evidence/residual_issue_ledger_2026-10-31.md` RESID-09 |
| 자연 누적 원칙(유도 원칙 — **계약 조항 아님**) | 임의 표본 생성 금지 — 스냅샷의 창 시작 근거에서 유도: "창 시작 = 계약 착지(merged_at), 근거: … + 자연 누적 원칙(임의 표본 생성 금지)" | `docs/evidence/slo_status_snapshot_2026-11-02.md` §3 |
| 동반 관측 기록 문서 | 종료된 n=0 고정창 기록 + 24h 비공식 룩백 — 별개 문서, 상호 참조 전용·값 비상속(§3) | `slo_n0_fixed_window_record_2026-11-16.md` (동일 PR 착지) |

## §1. 등록 범위 — 본 문서가 등록하는 것은 창 하나뿐이다

- **신규 등록**: 관측 창 1개의 양 끝 **규칙** (§2). 그 외 아무것도 아니다.
- **비등록(동결 계약에서 불변 상속)**: 공식 지표(official_wall)·모집단 정의·취소 분리·censoring
  역치·R-7 백분위·판정 최소 표본 n≥30·관측 프로토콜·소급 수정 금지 절차 — 전부 측정 prereg의
  값 그대로이며, 본 문서가 재정의·재핀·재분모화하지 않는다.
- 본 문서는 측정 prereg §10이 정한 "기준 변경은 새 날짜의 사전등록 문서로만" 절차로 착지하는 새
  날짜 사전등록 문서지만, **기준 변경을 운반하지 않는다** — 운반하는 것은 창 등록 1건이다(§4
  준수성 근거).

## §2. 판정창 등록 (본 문서의 유일한 신규 등록값 — 양 끝의 규칙)

**등록 창**:

```
[since = 본 문서를 착지시키는 PR의 native MERGE 커밋 시각 (GitHub-clock, UTC),
 until = 적격 완료 런(conclusion ∈ {success, failure}) 누적 n ≥ 30 최초 도달 시점]
```

- **since = 등록 문서 착지 시각 — 문서 착지 정렬점**:
  - (i) 측정 prereg §7은 "모든 P95 보고는 `[since, until]`을 수치와 함께 등록"만을 의무화하며
    **since를 어떻게 고정할지는 규정하지 않는다** — 이 자유도는 2026-11-02 등록 선례 §4가
    확인했다("창의 사전 수치 등록과 창 외 편입 금지만이 의무다").
  - (ii) 선례는 since를 세대 정렬점(양 org ruleset 재핀 readback 중 늦은 쪽)에 뒀다. 현재는 세대
    전환(ruleset 재핀)이 없어 그 경계를 사용할 수 없고, 본 등록 시점에 사용 가능한 **구조적
    사건**은 본 등록 문서 자체의 착지(native MERGE 커밋 시각)다. 이 시각은 GitHub merge
    authority가 발행하는 관측값-무관 사건이며, 본 문서 착지 = 창 등록이 세계에 존재하게 되는
    시각이므로 **관측 이전 고정**의 실질을 만족한다(창은 등록 문서 착지와 함께 개시된다).
  - (iii) **과거 관측 편입 차단**: since 이전 생성 런(동반 관측 기록 문서의 룩백 관측 전부 포함)은
    전부 창 밖이다 — 본 창의 표본은 착지 이후 자연 발생 트래픽만으로 구성된다.
  - (iv) **본 등록 PR 자신의 merge queue 라운드는 창 밖이다**: merge queue는 그룹(런) 생성 →
    검증 → 병합 순서로 진행하므로 등록 PR의 merge_group 런 `created_at`은 MERGE 커밋 시각보다
    앞선다 — 창의 첫 표본은 등록 PR 이후의 자연 발생 트래픽이다(등록 행위가 자기 표본을
    만들지 않는다).
  - (v) since의 실측 타임스탬프는 판정 보고서가 기록한다(§6 2항) — 본 문서는 규칙만 등록한다.
- **until = 표본 수 역치(결과-맹겸)**: 창 종료는 관측값(wall·백분위·분포)이 아니라 **적격 완료
  런 수**가 닫는다. 카운트 대상은 §5 모집단 계약 그대로다 — 창 내 생성·완료(conclusion ∈
  {success, failure}) admission-gate merge_group 런(run 객체 단위, dedupe 규칙 계승)의 누적 수.
  n≥30은 측정 prereg §7의 기존 값이지 본 문서가 새로 정의하는 것이 아니다. until의 실측
  타임스탬프도 판정 보고서가 기록한다 — 본 문서가 등록하는 것은 until의 **규칙**이며 값이
  아니다(§6).
- **창 소속과 잔존 런(2026-11-02 등록 선례 §2 조항 계승 — 원문 유지)**: 창 소속 판정 축은 런
  `created_at`이다(측정 prereg §7 그대로). 창 종료 시점까지 창 내 생성된 런 중 종료 시점에 진행
  중이던 런은 created_at 소속상 창 내 런이며, 판정 수집 시점에 완료한 것만 완료 필터로 모집단에
  편입된다. 수집 시점에도 미완결인 창 내 생성 런은 공식 모집단에서 제외하고 **별도 등록**한다
  (취소 분리 등록과 같은 위생 — 측정 prereg §4 계승). **창 외 관측의 사후 편입은 금지된다**
  (측정 prereg §7 준수).
- **자연 누적 원칙(유도 원칙 — 계약 조항 아님, §0)**: 본 창의 표본은 **자연 발생 merge_group
  트래픽만으로** 충족된다. 임의 표본 생성(합성 트래픽·측정용 차량 PR·창 종결을 위한 인위적
  enqueue)은 금지한다. 표본이 장기 부족한 상태가 지속될 경우 표본 보충 방법(트래픽 유발 여부·
  방법·측정창 재등록)은 **인간 결정 영역**이다 — 본 문서·에이전트·게이트 어느 것도 이를
  자동화하지 않는다.

## §3. 관측값 일절 기재 금지 (결과-맹겸)

- 본 문서에 기재된 관측 수치는 존재하지 않는다 — 창 양 끝은 **규칙**(구조적 사건의 종류와 표본
  수 역치)이며, 규칙의 실측값은 창이 닫힌 뒤 판정 보고서가 최초로 기록한다(§6). official_wall·
  P95·P50·min·max·현재 누적 n·창 진행률·공급 상태 도수 등 측정 대상이 되는 어떤 값도 본 문서에
  존재하지 않는다.
- **종료 조건의 결과-맹겸**: 창을 닫는 입력은 "적격 완료 런이 30개 모였는가"라는 **카운트**
  하나다. 어떤 런의 wall이 얼마였는지, 백분위가 어디에 위치하는지는 창 종료 시점·창 소속·판정의
  어느 단계에도 입력이 아니다. 이 2단계 구조 — **①관측 이전 창 등록(본 문서) → ②창 종료 후
  판정 보고(별도 문서)** — 가 곧 결과-맹겸의 실현이다.
- **동반 관측 기록 문서와의 관계**: 동일 PR에 `slo_n0_fixed_window_record_2026-11-16.md`(종료된
  n=0 고정창 기록 + 24h 비공식 룩백)가 동반 착지된다. 본 문서는 그 문서를 **참조만** 하며 그
  어떤 값도 가져오지 않는다. 룩백 관측값(그 문서 §3)이 480s 미만으로 관측됐다는 사실은 본 창
  등록의 입력이 아니다 — since가 등록 문서 착지 시각이므로 그 관측 전부는 창 밖이고(사후 편입
  금지), 창의 표본은 since 이후 자연 트래픽만으로 구성된다. 두 문서의 신분은 다르다: 관측 기록 =
  진단, 본 문서 = **동결 계약에 따른 공식 판정창 등록(계약 불변)**.

## §4. 준수성 근거 — 동결 계약 대조

- **창 선언 의무(측정 prereg §7 "표본 기준")**: "모든 P95 보고는 `[since, until]`(UTC, 런
  `created_at` 기준 GitHub-clock)을 수치와 함께 등록" + "창 외 관측의 사후 편입 금지". 동결
  계약에는 **since를 어떻게 고정하는지에 대한 규정이 없다**(2026-11-02 선례 §4 확인) — 본 등록은
  계약 내 자유도 안에서 since를 문서 착지 정렬점에 두며(§2), 창 선언(본 문서 착지 = 관측
  이전)과 창 외 편입 금지(§2 잔존 런 규정 포함)를 그대로 준수한다.
- **새 날짜 사전등록 문서 메커니즘(측정 prereg §10 "소급 수정 금지·선행 대체")**: "본 문서 착지
  후 기준 변경은 새 날짜의 사전등록 문서로만". 본 문서는 그 절차로 착지하는 새 날짜 사전등록
  문서다. 표본 수 기반 종료의 결과-맹겸 2단계 구조(①관측 이전 창 등록 → ②창 종료 후 판정
  보고)는 §10 메커니즘이 전제하는 사전등록 구조 그 자체다 — **기준 변경이 아니다**: 모집단·
  지표·계산식·역치·판정 규칙의 어떤 항목도 본 문서에서 바뀌지 않으며, n≥30 역치 자체가 동결
  계약(§7)의 기존 값이다.
- **불변 상속**: official_wall 정의(측정 prereg §2)·모집단·취소 분리·censoring 역치(§4)·R-7(§6)·
  관측 프로토콜(§9)·소급 수정 금지(§10) — **모두 동결값 그대로 상속**되며, 본 문서는 이를 §5에
  재진술할 뿐 재정의하지 않는다.

## §5. 판정 기준 재진술 (동결 계약에서 불변 — 새 등록이 아니라 재진술이다)

| 항목 | 내용 (동결 계약 그대로) | 출처 |
|---|---|---|
| 공식 지표 | `official_wall = run.updated_at − run.created_at` [초] — 최종 착지 merge_group admission-gate 런의 run 객체. `created_at`은 merge-queue 그룹 생성 시점이므로 **큐 대기 포함**(의도된 정의). API second granularity — 초 단위 정수 차, 소수 보고 금지 | 측정 prereg §2 |
| 모집단 | 창 내 admission-gate merge_group 런 중 **완료(conclusion ∈ {success, failure}) 전수**, run 객체 단위(1 run = 1 표본 — 배치 병합으로 PR 단위 정의 금지). run ID dedupe·동일 그룹 재도크 경계 관측 계승 | 측정 prereg §4 |
| 취소·censoring | 취소(conclusion = cancelled) 런 모집단 제외 + **별도 등록 의무**(런 ID·시각·사유 — 관측 사실만, 불명은 `unknown`, 추측 금지). `cancel_ratio` > 15% 또는 취소 런 중앙 큐 대기(`run_started_at − created_at` 중앙값)가 완료 런 중앙값의 2배 초과이면 P95 보고에 편향 경고 병기(고정 역치) | 측정 prereg §4 |
| 백분위 | **Hyndman–Fan type 7(R-7)**, 선형 보간 — 계산 코드는 측정 prereg §6 핀 그대로(재정의 금지). nearest-rank(`tools/ci/pareto_harness.nim:236`)와 다른 정의 — 병행 보고 시 방법명 명시 | 측정 prereg §6 |
| 판정 조건 | **n ≥ 30**(공식 모집단 완료 런 기준) + 창 `[since, until]` 명시(§2 등록 규칙). n<30이면 P95 미산출·p50만 "잠정" | 측정 prereg §7 · RESID-09 |
| SLO of record | Merge Queue wall P95 ≤ 480s = **policy** — 유지·계승. 헌법 불변식 아님(원문: "The 8-minute P95 is policy/SLO, not a constitutional invariant") | `ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135 (측정 prereg §1) |
| 해석 한계 | n≥30은 등록 절차상 계산 가능 최소 표본 수 — **장기 성능 보증으로 해석 금지** | 측정 prereg §7 계승 |

## §6. 창 종료 시 판정 보고서의 필수 동반값 (장래 보고 의무 목록 — 현재값이 아니다)

창이 닫히면 판정은 **별도 보고 문서**로 착지하며, 아래 전부를 수치와 함께 등록해야 한다. **본
목록은 의무 목록이지 값이 아니다 — 본 문서에 아래 항목의 현재치는 존재하지 않는다(§3).**

1. **표본 수 n** — §5 모집단 정의의 적격 완료 런 수.
2. **창 `[since, until]`** — since는 본 문서 등록 규칙의 실측값(등록 PR native MERGE 커밋 시각 —
   main 팁 merge 커밋과의 일치로 확인), until은 실측 확정 타임스탬프(§2 — n≥30 최초 도달 시점).
3. **p50 · p95 · min · max** — p95는 R-7(측정 prereg §6 핀)로만 산출. n≥30 미달이면 P95 미산출·
   p50 잠정만(RESID-09 어휘 계승).
4. **진단 2값(동결 계약의 "모든 보고 병행" 의무 — 측정 prereg §3)**: `latest_attempt_wall` =
   `updated_at − run_started_at` · `attempt_wall` = attempt-scoped job interval union
   (`GET /runs/{id}/attempts/{n}/jobs`의 잡 `[started_at, completed_at]` 합집합, `filter=all`).
   공식 지표만으로는 재실행·런너 지연을 진단할 수 없으므로 동결 계약이 모든 보고에 병행을
   요구하는 값이다(생략 시 계약 위반).
5. **공급 상태 카운트 — REUSED 런 수 · EXECUTED 런 수(보조 진단)**: 창 내 모집단 런이 어느 판정
   CAS 공급 상태로 서브됐는지의 도수. 이 어휘의 정의는 계약 본체에 신설되어 있지 않으며 선행
   계약 계층에서 상속된다 — `docs/spec/test_judgment_cas_contract.md` §3: **EXECUTED** =
   FRESH/ATTEMPTED(이번 어드미션 실행에서 실제 실행·종결 판정 산출), **REUSED** =
   REUSED/NOT_ATTEMPTED(실행하지 않고 5조건 통과한 사전 실행 판정 채택). 런 단위 분류 채널은
   레인 잡 로그의 `AXIOM_JUDGMENT_CAS` 발화 라인 또는 판정 아티팩트 `basis` 필드
   (`node24_merge_group_job_decomposition_2026-11-02.md` §2 코호트 정의 계승). 한 런 내 주체별
   basis가 혼재하면 런 단위 분류와 주체 단위 도수를 나란히 보고한다.
6. **run_attempt 분포** — 창 내 모집단 런의 `run_attempt` 도수(측정 prereg §3 "모든 값에
   `run_attempt` 병기" 계승).
7. **censoring 2지표 — 취소 런 수 · `cancel_ratio`**(취소 수 ÷ (완료+취소 런 수), **15% 초과 시
   편향 경고 병기 — 고정 역치**) + 취소 런의 중앙 큐 대기(`run_started_at − created_at`
   중앙값, 완료 중앙값 2배 초과 경고).
8. **epoch 명시** — provider epoch 시간 버킷 라벨(`ghec`/전환/`gen12-ubicloud` 경계는 측정
   prereg §5 등록값)을 보고에 병기. 창 내 세대 혼합 여부를 명시한다.
9. **conclusion별 도수 전수 — 동결 계약 §4 "전수" 원칙의 집행 명세(기준 변경 아님)**: 창 내
   생성 런의 관측된 **모든 conclusion 값**(success·failure·cancelled·timed_out·startup_failure·
   neutral·skipped·stale·action_required 등)을 0건 도수까지 포함해 전수 등록한다. **어떤 완료
   상태의 런도 조용히 소멸하지 않는다** — 취소의 별도 등록 의무(§5 취소 행)와 같은 위생의
   conclusion 전 범위 확장이다. 비적격 완료(conclusion ∉ {success, failure})와 수집 시점
   미완결 런은 별도 등록한다(§2 잔존 런 조항).
10. **민감도 병기(선택)** — 종결 후 문맥 런으로 재산출한 P95(2026-11-03 관측 선례 §4 방식)는
    판정 강건성 확인용으로 병기할 수 있다(판정 표본은 종결 시점 동결 표본 그대로다).

판정 보고 문서는 본 사전등록 문서와 동반 관측 기록 문서를 참조하며, 본 문서 body는 보존된다
(측정 prereg §10 절차 계승 — append-only).

## §7. 본 문서가 아닌 것

- **판정이 아니다** — 판정은 창 종료 후 별도 보고 문서에서 내려진다(§6). 본 문서는 창만 고정한다.
- **표본 선택 규칙 변경이 아니다** — 모집단 전수·run 객체 단위·dedupe·체리피킹 금지 규칙은 동결
  계약 그대로다.
- **모집단·계산 계약 변경이 아니다** — official_wall·R-7·n≥30·censoring 역치·관측 프로토콜은 1도
  변경되지 않았다(§4).
- **최적화 트리거가 아니다** — 창 종료 후 판정이 NOT MET가 나와도 그것은 정상 기록이며, 최적화
  의무가 자동으로 발생하지 않는다. SLO of record 480s는 policy다(§5 표). 후속 결정(SLO 개정·
  최적화 착수·재측정)은 인간 결정 영역이다.
- **진단 문서가 아니다** — 현재 상태 진단은 동일 PR의 관측 기록 문서가 담당한다(§3 — 본 문서는
  그 값을 소비하지 않는다).
- **트래픽 생성기가 아니다** — 자연 누적 원칙(§2)에 따라 본 창은 표본을 만들지 않고 자연
  도달을 기다린다(§2 표본 도달 시점은 비결정적 — 종결 규칙·산식·재현 경로만 결정론적이다).

## §8. 창 종료 절차·판정 재현 경로 (GET-only — 관측값 없는 명령 템플릿)

절차: ① 창 종료 확정(§2 역치 카운트 도달 — conclusion별 도수 질의로 적격 n 감시) → ② 창
`[since, until]` 확정 타임스탬프 기록 → ③ 창 내 런 전수 수집(창 분할·run ID dedupe·경계 단일 GET
교차검증 — 측정 prereg §9 프로토콜 그대로) → ④ conclusion별 도수 전수(§6 9항) + 취소·비적격
완료·수집 시점 미완결 별도 등록 → ⑤ official_wall 산출(초 단위 정수) → ⑥ R-7 p50/p95/min/max →
⑦ §6 동반값 전부 산출 → ⑧ 별도 판정 보고 문서 착지. 아래는 그 재현 경로의 명령 템플릿이다 —
**템플릿이지 관측 기록이 아니며, 본 문서에 명령 실행 결과는 존재하지 않는다.**

```bash
# (0) since 확정 — 본 등록 PR의 native MERGE 커밋(2-parent merge commit = 착지 직후 main 팁)
gh pr view <등록PR> --json state,mergedAt,mergeCommit        # mergedAt · mergeCommit.oid
gh api repos/Archright/Axiom/git/ref/heads/main --jq .object.sha   # = mergeCommit.oid 확인

# (1) 창 내 merge_group 런 열거 — 창당 total_count ≪ 1000 확인(측정 prereg §9)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<SINCE>..<UNTIL>&per_page=100" \
  --jq '.total_count'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<SINCE>..<UNTIL>&per_page=100&page=<p>" \
  --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id,.run_number,.created_at,.run_started_at,.updated_at,.conclusion,.run_attempt,.head_branch]'
# 페이지 완결 증명 필수: total_count와 페이지 합 일치 + 끝 페이지 빈 응답 확인
#   (1페이지만 쓰면 최신 100런으로 잘린다 — 실측 재현 사례: 동반 관측 기록 문서 §3.3)
# total_count가 1,000에 근접하면 created 서브윈도 반분(측정 prereg §9 — 재귀 분할)
# 관측 사실(워크플로 식별): admission-gate 런의 path는 전부 .github/workflows/admission-gate-v2.yml이나
#   이 파일은 저장소 트리에 부재 — org ruleset 25218071(axiom-admission-gate)의 required-workflow
#   (소스 Archright/.github)다. name=="admission-gate" 필터와 path 필터는 동일 집합을 반환한다
#   (2026-11-16 관측 — 동반 관측 기록 문서 §3의 전수 센서스에서 name↔path 전건 일치).

# (2) 창 종료 역치 감시 카운트(적격 완료 n) + conclusion별 도수 전수(§6 9항)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<SINCE>..<UNTIL>&per_page=100&page=<p>" \
  --jq '[.workflow_runs[] | select(.name=="admission-gate" and (.conclusion=="success" or .conclusion=="failure"))] | length'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<SINCE>..<UNTIL>&per_page=100&page=<p>" \
  --jq '[.workflow_runs[] | select(.name=="admission-gate") | .conclusion] | group_by(.) | map({conclusion:.[0],count:length})'

# (3) 취소·비적격 완료·수집 시점 미완결 별도 등록(§2·§6 9항) + 경계·판정 대상 런 단일 GET 교차검증(Q16)
gh api repos/Archright/Axiom/actions/runs/<id> \
  --jq '{id,event,name,path,conclusion,created_at,run_started_at,updated_at,run_attempt}'

# (4) attempt별 jobs (filter=all 필수 — rerun attempt 누락 방지·진단 2값 attempt_wall 산출 입력, 측정 prereg §9·§3)
gh api "repos/Archright/Axiom/actions/runs/<id>/attempts/<n>/jobs?per_page=100&filter=all" \
  --jq '.jobs[] | [.id,.name,.started_at,.completed_at,.conclusion]'

# (5) 공급 상태(basis) 판독 — REUSED/EXECUTED(레인 잡 로그 발화 라인, §6 5항)
gh api repos/Archright/Axiom/actions/jobs/<LANE_JOB_ID>/logs 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"

# (6) R-7 백분위 — 측정 prereg §6의 코드 핀을 그대로 사용(재정의·재핀 없음)
```

모든 관측 GET-only · `gh` 네이티브 인증 · REST core 5,000 req/h 준수 · raw 응답 캐시는 증거가
아님 — 측정 prereg §9 계승(변경 없음). 판정 보고서 작성 시점에도 본 문서와 측정 prereg의 body는
보존되며, 본 창 등록에 대한 수정·재분류·재분모화는 금지된다(새 날짜의 사전등록 문서로만 — 측정
prereg §10).
