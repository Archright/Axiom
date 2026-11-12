# Pre-registration — 공식 SLO 측정 계약 동결 (2026-11-01)

> **종류**: 사전등록 문서 (pre-registration). CI 시간 최적화 슬라이스 1의 "SLO 측정 계약 동결" 차량 —
> **어떻게 측정할지를 관측 이전에 결정론적으로 고정**한다. 본 문서 착지 이후의 SLO 보고는 본 계약을
> 따르며, 관측을 본 뒤의 기준 변경은 어떤 형태로도 허용하지 않는다(변경은 새 날짜의 사전등록 문서로만 — §10).
> **등록 계층(정직 구조)**: 본 문서가 신규로 동결하는 것은 **공식 지표·모집단·백분위 계산식·귀속 규칙·
> 관측 프로토콜**이다. 1차 판정 규칙(v5 중앙값, 재결 §4)·SLO of record(480s, policy)는 이미 선행 등록돼
> 있으며 본 문서가 대체하지 않는다(§0).
> **사전 관측 공개 의무**: 본 등록 시점에 본 세션이 이미 관측한 API 값은 §11에 전부 공개한다. 계약 항목은
> 관측값이 아니라 공식 API 문서·선행 등록 문서·실증 대차(구조 확인)에서 유도됐다.
> **Date**: 2026-11-01 · **Branch**: `work/slo-prereg` · **Scope**: 본 문서 1건(`docs/evidence/*.md`) —
> 코드·워크플로우·게이트·핀·도구 변경 0건. docs-only 비행 → trust surface 아님(정상 merge queue 경로).
> **권위**: 본 계약은 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE commit)를
> 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 어떤 게이트도 본 문서의 값을 소비하지 않는다.
> 모든 관측은 GET-only·`gh` 네이티브 인증(AGENTS.md §2.4).

---

## §0. 상속·참조 권위 (본 문서는 아래를 대체하지 않는다)

| 권위 | 내용 | 위치 |
|---|---|---|
| SLO of record | Merge Queue wall P95 ≤ 8분(480s) = **policy/SLO** — 헌법 불변식 아님, 유지 | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135 |
| v5 판정 규칙(1차) | docs-only REUSED 표본 MG wall 중앙값, n≥5 — 본 문서와 별개 축 | `docs/evidence/mg_reuse_policy_redecision_2026-10-18.md` §4 |
| v5 측정 절차(선행 등록) | 표본 단위·epoch 층화·전수 관측(체리피킹 금지)·증거 위생 — 본 문서가 계승 | `docs/evidence/judgment_key_v5_measurement_prereg_2026-10-31.md` (PR #1145) |
| v5 판정 기록(모집단 전수) | 창 내 완료 130(성공 117·실패 6·취소 7)·P95 2315.8s·Q16 발견 | `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md` §0·§6 |
| 진단 3값 어휘(선행) | `latest_attempt_wall` / `attempt_wall` / `total_elapsed_with_retries` | `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` §3 |
| Actions 열거 상한(실측) | created-range `total_count` 2,500 cap·페이지네이션 1,000 정지·일 단위 슬라이스 | `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` §4.1 |
| 목록 누락 quirk | `event=merge_group` 목록이 실존 런을 누락(실측 4건) — 창분할+단일 GET 교차검증 | `docs/spec/gh_run_observation_quirks.md` Q16 |
| P95 어휘 | 집단별 N≥30 도달 전 p50/p95는 "잠정·미산출" | `docs/evidence/residual_issue_ledger_2026-10-31.md` RESID-09 :136-144 |
| provider epoch | gen-12 Ubicloud 전환(2026-10-30T07:46:09Z PATCH)·GHEC 복귀 수용 | `docs/evidence/ci_provider_epoch_2026-10-30.md` :30-38 · `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` §2·§5 |
| 측정 교란 규칙 | 러너 VM 속도 분산(~1.4-1.5×) — wall 비교는 paired runs 필수(진단 층) | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` :152 |

---

## §1. SLO 범위 (무엇을 재는가)

**공식 SLO = 최종 착지 merge_group admission-gate 런의 공식 wall-clock(생성→완료)이다.**

- 공식 SLO의 대상은 **merge_group admission-gate 런 자체의 시간**이다. **다음이 아님을 명시한다**:
  PR 변경→main 병합 전체 시간(PR 생성→mergedAt), 리뷰 대기, 큐 진입 전 대기, PR-head CI, 저자 수정
  시간, dequeue 후 재시도 사이의 인간 대기. 이 전체 시간의 분해는 선행 등록인
  `pr_to_main_attribution_prereg_2026-10-19.md`(TOT/`wall_partition`)이 담당하며 본 계약과 별개 축이다.
- **SLO of record = 480초(P95)** — `ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135가
  등록한 policy SLO이며 **헌법 불변식이 아니다**(그 문서 원문: "The 8-minute P95 is policy/SLO, not a
  constitutional invariant. It remains the SLO of record"). 본 문서는 이 SLO를 유지·계승하며, 값을
  변경·재선언하지 않는다. 후속 최적화 의무를 자동으로 발생시키지 않는다(같은 문서의 policy 유지).

## §2. 공식 지표 정의 + 식별 관계 (어떤 필드인가)

**공식 지표(of record):**

```
official_wall = run.updated_at − run.created_at   [초]
```

- 대상 run: 최종 착지 merge_group **admission-gate** 런의 **run 객체**(`GET /actions/runs/{id}`).
- `created_at`은 merge-queue 표본(그룹) 생성 시점이므로 이 값은 **큐 대기를 포함한다** — 의도된 정의다.
- 타임스탬프 단위: API second granularity(±1초) — 소수 보고 금지, 초 단위 정수 차로 산출.

**식별 관계(중요 — 이 값은 새 독립 지표가 아니다):**

GitHub Actions의 re-run은 **새 run 객체를 만들지 않고 동일 run 객체에 attempt를 추가**한다. 근거:

- 공식 REST 문서: "Re-run a workflow — Re-runs your workflow run using its id"
  (`POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun`), run 객체 응답 필드
  `run_attempt`·`previous_attempt_url`·`rerun_url`, attempt 조회 엔드포인트
  `GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}`.
- 따라서 run 객체의 `updated_at − created_at` ≡ **"attempt1 `created_at` → 최종 attempt `updated_at`"**
  (같은 객체의 같은 필드 쌍). 이는 선행 등록
  `pr_to_main_attribution_prereg_2026-10-19.md` §3의 `total_elapsed_with_retries`와 **동일한 값**이다
  (그 문서: "attempt 1 `created_at` → final attempt `updated_at` (attempts 1..`run_attempt` 순회)").
  즉 본 계약은 새 지표를 도입한 것이 아니라 선행 3값 구조의 세 번째 값을 공식 지표로 **승격·고정**한 것이다.

**실증(2026-11-01 GET-only, §11 전문):** merge_group re-run 2건에서 (a) run 객체 `created_at`이
attempt1 생성 시각 그대로 유지됨, (b) run 객체 `run_started_at`이 최신 attempt 시작을 가리킴 — 양측 모두
확인. 관측 모집단(최근 목록 800건 스캔)에서 재시도 후 성공 사례는 미발견(2건 모두 취소 종결)이나, 식별
관계는 attempt 종결 상태와 무관한 API 구조 문제로 공식 문서+실측 2건으로 확정한다.

## §3. 진단 2값 병행 보고 (공식 지표와 함께 무엇을 기록하는가)

공식 지표만으로는 재실행·런너 지연을 진단할 수 없으므로, 모든 보고에 아래 **2값을 병행**한다.
**모든 값에 `run_attempt`를 병기한다.**

| 값 | 정의 | 의미 |
|---|---|---|
| `latest_attempt_wall` | `run.updated_at − run.run_started_at` | **최종 attempt의 실행 전용 시간** — `run_started_at`은 rerun 시 최신 attempt 시작으로 갱신됨(§11 실증 (b)) |
| `attempt_wall` | `GET /runs/{id}/attempts/{n}/jobs`의 job interval `[started_at, completed_at]` **union** (attempt-scoped) | 잡 실행 구간의 실측 겹침합 — 큐·의존성 대기 제외, 복수 잡 중복 계산 없음 |

**선행 문서와의 조정(`pr_to_main_attribution_prereg_2026-10-19.md` §3 — 3값 구조):**

| 선행 3값 | 본 계약에서의 지위 |
|---|---|
| `latest_attempt_wall` | **진단값 1로 계승** (정의 동일) |
| `attempt_wall` | **진단값 2로 계승** (정의 동일) |
| `total_elapsed_with_retries` | **공식 지표로 승격·고정** (§2 식별 관계 — 독립 지표 아님이 확인됨) |

선행 문서는 폐기되지 않는다 — 어휘가 계승되며, 그 문서의 측정(TOT·partition)은 본 계약과 별개 축으로
유효하다. 본 계약 이후 merge-group 런 보고의 최소 필드 세트는
`{official_wall, latest_attempt_wall, attempt_wall, run_attempt, conclusion}`이다.

## §4. 모집단 정의 (누구를 세는가)

- **공식 SLO 모집단** = 관측 창 내 `admission-gate` merge_group 런 중 **완료(conclusion ∈ {success,
  failure})** 런 전수, run 객체 단위(1 run = 1 표본 — 배치 병합으로 복수 PR이 하나의 런을 공유하므로
  PR 단위 정의 금지; v5 §4 각주¹ 사례).
- **Dedupe 규칙(v5 계승)**: (i) 창 분할 스윕의 중복 창 경계는 **run ID dedupe**; (ii) 동일 merge-queue
  그룹(동일 `head_branch` `gh-readonly-queue/main/pr-N-*`)의 재도크·dequeue 중간 완료 런은 모집단에서
  제외하고 **경계 관측**으로 별도 기록(v5 prereg §2 — #1144의 03:40Z·07:21Z 런을 착지 런 08:27Z와 분리한
  선례). (iii) 목록 엔드포인트 누락(Q16) 대비 경계 런 단일 GET 교차검증.
- **취소(conclusion = cancelled) 런**: 모집단에서 제외하되 **별도 등록을 의무**한다 — 취소 런 ID·
  `created_at`·`updated_at`·취소 시각(`updated_at` — 플랫폼이 별도 취소 시각 필드를 제공하지 않음)·
  사유(판별 가능 필드만: 동일 그룹 후속 런 존재 여부 등 관측 사실; 불명은 `unknown`, 추측 금지).
- **Censoring 감시 지표(취소 분리의 편향 감시 — 병행 보고 의무)**:
  (i) `cancel_ratio` = 취소 런 수 ÷ (완료+취소 런 수), (ii) 취소 런의 중앙 큐 대기
  (`run_started_at − created_at` 중앙값). 목적: **장기 대기 표본의 소실 편향** 감시 — 취소가
  구조적으로 긴 런을 골라내면(취소가 완료보다 긴 런에서 빈번하면) 남은 완료 표본의 P95가 실제보다
  낮아 보인다. `cancel_ratio` > 15% 또는 취소 중앙 큐 대기가 완료 런 중앙값의 2배 초과이면 P95 보고에
  편향 경고를 병기한다(역치는 본 등록에서 고정).
- **v5 데이터의 정직 귀속**: v5 전수 "완료 130"에는 취소 7이 포함돼 있다(v5 adjudication §0). 이는
  v5 등록 규칙으로 정당하며 **소급 수정·재분류 금지**다(§10). 본 문서 착지 이후의 측정부터 취소를
  분리 등록한다.

## §5. 모집단 분리 (공식 vs 진단)

- **공식 SLO 모집단(§4)은 전체 전수**다 — provider·epoch를 가르지 않는다. 이 값은 epoch 혼합값임을
  모든 보고에 명시한다(v5 §6 "측정 구간이 provider 세대 전환을 가로질러 P95는 세대 혼합값" 계승).
- **provider/epoch 진단 모집단(2차 보고 전용)**: 런 `created_at` 기준 epoch 태그 —
  `ghec`(≤2026-10-23) / `failover`(2026-10-23 ~ 2026-10-30T07:46:09Z) / `gen12-ubicloud`
  (2026-10-30T07:46:09Z PATCH ~ GHEC 복귀 전) / `ghec`(복귀 후).
  근거: `ci_provider_epoch_2026-10-30.md` :30-38 (gen-12 Ubicloud PATCH 07:46:09Z).
- **GHEC 복귀 경계 등록값 = 2026-11-01T10:53:18Z `GHEC_RETURN_CONFIRMED`** — 라우터 단일 writer가
  `CI_RUNNER_MAP`에 기록(`last_transition_at`, `return_acceptance=confirmed`,
  `return_acceptance_run_id=41298669695`; live GET 관측). **시계 기준 교차검증(본 등록에서 수행)**:
  확인 write를 수행한 라우터 런 41299411602(잡 124827053726)의 로그 타임스탬프(GitHub clock)가
  `2026-11-01T10:53:18.09Z`로 변수값과 초 단위 일치 → **본 경계는 GitHub-clock으로 확정**이다.
  시험 시점 관측된 라우터 −1h 시계 skew(`ci_provider_ghec_return_acceptance_2026-11-01.md` §2)는
  본 write에는 적용되지 않았다.
- **전환 창 주의(혼합 모집단 임의 변경 금지의 정직한 한계)**: 라우팅의 실제 전환은 force_trial에 의한
  `GHEC_ACTIVE`(~2026-11-01T09:35Z), confirmed(10:53:18Z)는 그 **수용 기록**이다. 전환 창
  [2026-11-01T09:35:43Z, 10:53:18Z] 생성 런은 양쪽 provider 혼합 가능 — 이 창의 런은 잡 단위
  `runner_group_id`(0 = GitHub-hosted, 1 = Ubicloud; `ci_provider_ghec_return_acceptance_2026-11-01.md`
  §5 분류 규칙)로 분류하거나 `ghec-transition` 층으로 분리 보고한다. 등록 경계 원시값 자체는 임의
  변경하지 않는다.

## §6. P95 결정론 계산식 (Hyndman–Fan type 7 — 고정)

공식 SLO 판정에 쓰는 백분위는 **Hyndman & Fan (1996) type 7(R 기본값, 선형 보간)으로만** 산출한다.
단위는 초, 표본은 오름차순 정렬, 동일 표본 → 동일 값(결정론).

```python
def percentile_r7(sorted_values, p):
    """Hyndman & Fan (1996) type 7 (R default) — 결정론 백분위.
    sorted_values: 오름차순 정렬된 표본(list[float]), p: 0 이상 100 이하."""
    n = len(sorted_values)
    if n == 0:
        raise ValueError("empty sample")
    h = (n - 1) * (p / 100.0)
    lo = int(h)              # floor(h)
    hi = min(lo + 1, n - 1)  # ceil(h), 경계 클램프
    gamma = h - lo
    return sorted_values[lo] + gamma * (sorted_values[hi] - sorted_values[lo])

# 공식 SLO P95: percentile_r7(sorted(official_walls), 95)
```

**저장소 기존 도구와의 구분(명시)**: `tools/ci/pareto_harness.nim:236`의 `percentile95`는
**nearest-rank**(`ceil(0.95*n) − 1`번째 값)이며 **R-7이 아니다**. 두 정의는 n이 20의 배수가 아닌 모든
n에서 다른 값을 낸다. 본 계약의 공식 SLO P95는 R-7로만 산출하며, nearest-rank 값이 병행 보고될 때는
방법명을 반드시 명시한다. **전용 R-7 도구는 현재 `tools/`에 존재하지 않는다** — 본 문서는 계산식 자체를
핀으로 고정하며, 도구화 여부는 별도 슬라이스 판단 사항이다(본 문서는 도구를 도입하지 않는다).

## §7. 표본 기준 (몇 개면 판정 가능한가)

- **P95 등록 판정 최소 표본: n ≥ 30** (공식 모집단 완료 런 기준). n < 30이면 P95는 **미산출** —
  p50만 "잠정"으로 보고한다(RESID-09 어휘 계승).
- **관측 시간창 명시 의무**: 모든 P95 보고는 `[since, until]`(UTC, 런 `created_at` 기준 GitHub-clock)을
  수치와 함께 등록한다. 창 외 관측의 사후 편입 금지.
- **보고 필수 동반값**: 표본 수 n, 측정 구간, p50, p95, 최소, 최대 (v5 prereg §4 어휘 —
  "표본 수·측정 구간·분포를 수치와 함께" 계승).
- **해석 한계(고정)**: n≥30은 등록 절차상 계산 가능 최소 표본 수이지 **안정적 장기 추정이 아니다** —
  n≥30 P95를 장기 성능 보증으로 해석하지 않는다(v5 prereg §6 · v5 adjudication §6 계승).

## §8. 대기 원인 귀속 규칙 (지연을 어디에 돌리는가)

- **전제(불가피 한계)**: 잡 `started_at − created_at`은 **의존성 대기·러너 배정·동시성 제한의 혼합**이다.
  이 셋을 구분하는 GitHub API 필드는 존재하지 않는다 — 혼합값을 단일 원인으로 보고하는 것을 금지한다.
- **귀속 가능(기록 허용)**:
  - **의존성 완료 후 지연**: `job.started_at − max(의존 잡(needs)들의 completed_at)` > 0 → **의존성 외
    원인(러너 배정·동시성 포함)** 귀속 가능. 값과 함께 `runner_delay_after_needs`로 기록.
  - **동시성(concurrency) 대기**: 워크플로 YAML의 `concurrency.group` 정적 확인으로 동일 그룹 선행
    실행 존재가 확인될 때 → concurrency 귀속 가능(YAML 커밋 SHA를 근거로 병기).
- **귀속 불가 → UNKNOWN**: 의존성 실행 중 구간(이 잡이 기다리는 동안 needs가 아직 실행 중인 구간)의
  원인 분해 — 의존성 대기인지 러너 대기인지 API로 구분 불가. **UNKNOWN으로 기록한다.**
- **원인 미확정 시 추측 금지** — UNKNOWN 보고가 정답이다(선행 prereg의 `unknown` 규율 계승:
  `pr_to_main_attribution_prereg_2026-10-19.md` §5 "근거 없음. 추측 금지").

## §9. 관측 프로토콜 (어떻게 읽는가)

- **필터당 1,000 결과 상한(공식)**: `GET /repos/{owner}/{repo}/actions/runs`는
  `actor, branch, check_suite_id, created, event, head_sha, status` 각 파라미터 사용 시
  **최대 1,000 결과**만 반환한다(GitHub 공식 REST 문서 — List workflow runs for a repository, 원문:
  "This endpoint will return up to 1,000 results for each search when using the following parameters:
  actor, branch, check_suite_id, created, event, head_sha, status").
- **시간창 분할**: `created=W1..W2` 서브윈도로 열거 — 창당 `total_count`가 1,000에 근접하면 창을
  반분(기본 6h, 필요 시 12h→6h→1h 재귀)한다. 실측 상한 보강: created-range `total_count`는 2,500에서
  cap, `--paginate` 반환도 1,000에서 정지(`pr_to_main_attribution_prereg_2026-10-19.md` §4.1,
  2026-10-20 실측). **판정 기준: 창당 `total_count ≪ 1000`을 확보한 창만 유효 표본 창으로 인정.**
- **run ID dedupe**: 중복·접는 창 경계에서 동일 run 재반환을 run ID로 dedupe한다.
- **경계 런 개별 GET 교차검증**: 목록 엔드포인트는 실존 런을 누락할 수 있다(Q16 — `event=merge_group`
  전 페이지 순회에서 실존 런 4건 누락 실측). 창 경계 런과 전수 판정 대상 런은 단일
  `GET /actions/runs/{id}`로 교차확정한다.
- **attempt별 jobs**: `GET /repos/{owner}/{repo}/actions/runs/{id}/attempts/{n}/jobs`(공식 엔드포인트;
  라이브 검증 완료 — 런 40835650236 attempt 1 jobs 정상 반환). `filter=all` 필수 — 기본 latest는
  rerun attempt 잡을 누락한다(`ci_provider_ghec_return_acceptance_2026-11-01.md` §5 실측).
- **기타**: 모든 관측 GET-only · `gh` 네이티브 인증 · REST core 5,000 req/h 준수 · raw 응답은 캐시
  가능하나 캐시는 증거가 아님(선행 prereg §5·§7 계승).

## §10. 소급 수정 금지·선행 대체

- **과거 prereg·판정 데이터의 재분류·재계산·재분모화 금지** — `judgment_key_v5_*` 등 기존 등록·기록은
  append-only로 보존한다(변경은 git revert 또는 새 문서뿐).
- **선행 대체 관계의 명시**: 본 문서는 (i) merge-group 런 시간의 **공식 지표**를 `updated_at − created_at`
  로 고정(§2), (ii) 취소 런 취급을 분리 등록(§4)으로 바꾼다. v5의 wall₁/wall₂ 병행(재결 §4)·"완료 130 =
  성공 117 + 실패 6 + 취소 7"은 그 등록 규칙대로 유효하며, 본 문서가 그 값을 정정하는 것이 아니다.
- **새 정의 baseline 재계산은 허용된다** — 정의 선택이 과거 판정을 뒤집을 유인이 없기 때문이다:
  두 후보 정의 모두 역사 데이터에서 P95 ≫ 480s이다(v5 adjudication §6 — 전수 130 P95 2315.8s, 성공
  한정 2012.8s; wall 정의를 바꿔도 SLO 대비 ~4배 이상 격차는 유지). baseline 재계산 시에는 구정의·
  신정의 값을 **나란히** 보고한다.
- **정의 변경 절차**: 본 문서 착지 후 기준 변경은 **새 날짜의 사전등록 문서로만** 하고 본 문서 body는
  보존한다(`pr_to_main_attribution_prereg_2026-10-19.md` §12 절차 계승).

## §11. 사전 관측 공개 — 필드 의미 실증 기록 (2026-11-01, GET-only)

등록 전 본 세션이 관측한 값의 전부. 규칙(§2 식별 관계·§5 경계)은 이 값들이 아니라 공식 API 문서·
선행 등록에서 유도됐다. **관측 명령은 §12와 동일하다.**

re-run(attempt > 1) 사례 2건 — merge_group 목록 최근 800건 스캔(페이지 1–8)에서 발견, 전체
`total_count=2500`:

| run | run_attempt | run 객체 created_at | attempts/1 created_at | run 객체 run_started_at | attempts/1 run_started_at | attempts/1 updated_at | run 객체 updated_at | conclusion |
|---|---|---|---|---|---|---|---|---|
| 40835650236 | 2 | 2026-10-29T07:28:27Z | 2026-10-29T07:28:27Z | 2026-10-29T07:38:49Z | 2026-10-29T07:28:27Z | 2026-10-29T07:34:13Z | 2026-10-29T07:44:04Z | cancelled |
| 40530789599 | 2 | 2026-10-27T15:25:15Z | 2026-10-27T15:25:15Z | 2026-10-27T16:10:16Z | 2026-10-27T15:25:15Z | 2026-10-27T15:59:41Z | 2026-10-27T16:30:01Z | cancelled |

- **(a) 확인 — run 객체 `created_at`은 attempt1 생성 시각 유지**: 양 런 모두 run 객체와 attempts/1의
  `created_at`이 초 단위 동일. → `updated_at − created_at` ≡ attempt1 created→최종 updated(§2).
- **(b) 확인 — run 객체 `run_started_at`은 최신 attempt 시작**: attempt1 값과 다른 최신 시각을 가리킴
  (40835650236: 07:38:49Z vs attempt1 07:28:27Z — attempt1 전체 구간 종료 후). → `latest_attempt_wall`
  은 최종 attempt 실행 전용(§3).
- 양 런 모두 `previous_attempt_url` 존재(공식 필드 — attempt 연결의 플랫폼 표현).
- 양 런 모두 **conclusion=cancelled** — 스캔 범위에서 재시도 후 성공 사례 미발견. 필드 관계는 종결
  상태와 무관하게 확인됐으며, §2의 식별 관계는 공식 문서(rerun이 run 객체에 attempt 추가)와 일치한다.
- 부수 관측: 런 41298669695(admission-gate merge_group, 2026-11-01T10:42:37Z created,
  10:53:00Z updated, success) = GHEC 복귀 수용 확인 런 — §5 경계 교차검증에 사용.

## §12. 재현 명령 (GET-only)

```bash
# §11 표: re-run 런 목록(merge_group, run_attempt>1)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100&page=5" \
  --jq '.workflow_runs[] | select(.run_attempt>1) | [.id,.run_attempt,.created_at,.run_started_at,.updated_at,.conclusion]'

# §11 표: run 객체 vs attempt1 대차
gh api repos/Archright/Axiom/actions/runs/40835650236 --jq '{run_attempt,created_at,run_started_at,updated_at,previous_attempt_url}'
gh api repos/Archright/Axiom/actions/runs/40835650236/attempts/1 --jq '{run_attempt,created_at,run_started_at,updated_at}'

# §3: attempt별 jobs (attempt_wall 재료; filter=all 필수)
gh api "repos/Archright/Axiom/actions/runs/40835650236/attempts/1/jobs?per_page=100&filter=all" \
  --jq '.jobs[] | [.id,.name,.started_at,.completed_at,.conclusion]'

# §5: GHEC 복귀 경계 원시값(라우터 변수) + 확인 런
gh api repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP --jq '.value' | jq '{last_transition_at,last_transition_reason,return_acceptance,return_acceptance_run_id}'
gh api repos/Archright/Axiom/actions/runs/41298669695 --jq '{id,created_at,run_started_at,updated_at,conclusion}'

# §9: 시간창 분할 열거(창당 total_count ≪ 1000) + Q16 경계 교차검증
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-01T00:00:00Z..2026-11-01T06:00:00Z&per_page=100" --jq '.total_count'
gh api repos/Archright/Axiom/actions/runs/<id> --jq '{id,event,name,conclusion}'
```
