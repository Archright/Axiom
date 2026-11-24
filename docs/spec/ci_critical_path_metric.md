# CI critical-path metric — canonical definitions (VS-1a)

> **Status**: 측정 정의 동결 — **v2 개정 (2026-11-24)**.
> **Created**: 2026-11-20 · **Revised**: 2026-11-24
> **Baseline**: `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json`
> **Evidence**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md`, `docs/evidence/ci_admission_measurement_2026-11-24.md`
> **개정 근거**: v1은 admission wall을 정의하는 workflow를 측정 대상에서 제외했다(§0.1). v2는 cohort·귀속·그래프 정본을 고치고, 측정 객체를 둘로 분리한다(§3).
> **보호 등급**: 이 문서는 trust surface manifest·`trustSurface`·checker closure 어디에도 속하지 않는다 — 개정에 trust 회전이 필요하지 않다.

## §0. 목적

CI 최적화 결정은 "어디가 느린가"에 대한 **재현 가능한 귀속**에 근거해야 한다. 이 문서는 GitHub Actions의 기존 REST 기록만으로 계산되는 지표의 공식을 고정한다. 새 관측 서비스·SaaS·계측 코드는 도입하지 않는다.

이 정의는 **성능 측정 전용**이다. 어떤 지표도 admission 판정·증거·캐시 신뢰의 근거가 아니다.

### §0.1 v2가 고친 결함

v1 §1은 측정 대상을 `admission-gate`(`admission-gate-v2.yml`)로 고정했다. 관측된 5개 merge queue cycle 중 **4개에서 마지막 컨텍스트는 `readiness-verdict`** 였고, `admission-gate`는 어느 cycle에서도 마지막 finisher가 아니었다. 즉 v1의 기본 cohort는 **admission wall을 정의하지 않는 workflow를 측정**하고 있었다 — 지배 경로에 대한 사각지대다.

| 항목 | v1 | v2 |
|---|---|---|
| 기본 대상 | `admission-gate` 단일 | `axiom-operational-slice`(1차) + `admission-gate`(2차 비교) |
| `criticalPathSeconds` | 선언된 `needs` 위 2초 tolerance 역추적 chain | workflow별 `needs:` DAG 최장 경로 (§2.5) |
| `queuedSeconds` | `created_at`을 정본으로 가정한 단일 합 | 두 현상 분리 + `NO_LOG_SOURCE` (§2.3) |
| job → 노드 귀속 | 규정 없음(레코드 이름 = job id 가정) | prefix 귀속 계약 (§7.1) |
| `needs` 그래프 정본 | 출처 미규정 | candidate SHA의 YAML + blob SHA 기록 (§7.4) |
| 측정 객체 | workflow wall과 admission wall이 한 표에 혼재 | 둘을 분리 (§3) |

번호 규약: §4–§6과 §2.x는 기존 문서·코드가 참조하므로 **재번호하지 않는다**. §3은 v1의 저작 공백이었고(§2.6 다음이 §4였다), v2가 이 번호를 측정 객체 분리에 사용한다.

## §1. Cohort (표본) 규약

### §1.1 측정 대상 workflow — 2계층

| 계층 | workflow | path | 역할 |
|---|---|---|---|
| **1차 (기본)** | `axiom-operational-slice` | `.github/workflows/axiom-operational-slice.yml` | admission wall을 정의하는 대상. 별도 지정이 없으면 모든 `criticalPath` 보고는 이 workflow다. |
| 2차 (비교) | `admission-gate` | `.github/workflows/admission-gate-v2.yml` | 비교·회귀 감시용. 1차 대상의 지표를 대체하지 않는다. |

1차 대상이 기본인 이유는 두 가지이며, 둘 다 정책에서 유도된다.

- `config/policy/merge_admission.json`의 required context 7개 중 **2개**(`axiom-operational-slice`, `readiness-verdict`)가 이 workflow 하나에서 나온다. 두 job은 `readiness-verdict: needs: [axiom-operational-slice]`로 **직렬**이다.
- 그중 `readiness-verdict`가 관측된 cycle의 다수에서 **마지막 finisher**다. 마지막 finisher의 완료가 곧 admission wall의 끝이므로, 이 workflow를 빼면 wall의 지배 구간을 측정하지 못한다.

1차 대상이 **항상** 마지막 finisher라는 주장은 아니다. `admission-check`가 마지막이었던 cycle도 있으므로 per-candidate 마지막 finisher는 별도로 기록한다(§3.2). 2차 대상은 top-level 8개 job이 26개 레코드로 확장되어 대부분 병렬로 실행되고, 관측상 1차 대상보다 먼저 끝났다 — 남는 slack이 있으므로 그 지표를 개선해도 wall은 움직이지 않는다.

### §1.2 이벤트·attempt·제외·최소 크기

| 항목 | 규약 |
|---|---|
| 이벤트 | `merge_group` (자연 발생 merge queue 실행만) |
| attempt | 각 run의 **terminal attempt** (`run_attempt` 최대값)만 |
| 제외 | `workflow_dispatch`·수동 재실행·합성 벤치마크 |
| 최소 크기 | 최적화 **판단**에는 n≥5, **SLO 주장**에는 n≥20 |

### §1.3 `skipped` 레코드

`skipped` job 레코드는 cohort에서도 **bucket에서도** 제거하지 않는다. 제거하면 `needs:` 그래프의 노드가 사라지고(§7.3), wall의 시작점이 달라져 재현성이 깨진다. `skipped`는 **기여 시간에서만** 배제된다.

## §2. 지표 정의

모든 timestamp는 GitHub jobs API의 ISO-8601 UTC 값을 그대로 사용한다. 반올림은 출력에서만 하고 계산은 초 단위 실수로 한다.

### §2.1 `wallSeconds` — 사용자가 체감하는 병합 대기

```
wallSeconds = max(completed_at) - min(started_at)
```

terminal attempt의 **모든 job**(skipped 포함, 두 timestamp가 모두 있는 job)에 대해 계산한다.

- 이 정의의 정본은 `docs/spec/ci_acceptance_contract.md` §6이다. 이 문서는 이를 재정의하지 않는다.
- 이 값은 runner 대기·큐 대기·job 실행을 모두 포함한 **관측 구간**이다.
- `created_at`은 사용하지 않는다(workflow 생성 시각은 job 시작 전 지연을 별도로 포함).
- `wallSeconds`는 **workflow 단위**다. 서로 다른 workflow의 `wallSeconds`를 더하거나 최대로 접어 admission wall을 만들지 않는다(§3.3).

### §2.2 `runnerSeconds` — 누적 계산 자원

```
runnerSeconds = Σ max(0, completed_at - started_at)   (job별)
```

- `max(0, …)` clamp는 skipped job의 비정상 음수 span(예: `completed_at < started_at` 1초)을 0으로 만든다.
- 이 정의는 이 표본에서 "skipped 제외"와 동일한 값을 낸다(측정 §3.2). clamp는 향후 표본에서도 정의를 고정하기 위한 것이다.
- **주의**: clamp 없이 raw 합을 내면 skipped job의 음수 span이 합계를 깎아 run당 4–6초 낮게 나온다. 2026-11-19 문서의 run별 값은 raw 합이므로 이 문서의 값과 4–6초 다르다(§4).

### §2.3 `queuedSeconds` — 배정 대기와 핸드오프 대기 (v2 재정의)

레코드 `j`의 갭을 `g(j) = started_at(j) − created_at(j)`라 할 때, `g(j)`는 **서로 다른 두 현상**을 담는다. 하나의 합으로 더하지 않는다.

| 집계 | 대상 | 의미 | 정상 크기 |
|---|---|---|---|
| `queueSeconds.firstBatch` | `needs`가 빈 job | 러너 배정·VM 프로비저닝 대기 | 수 초, burst 시 분 단위 |
| `handoffSeconds` | `needs`가 있는 job | 선행 완료 후 이 job 시작까지 | 2–3초 |

규칙:

1. **필드 부재는 0이 아니다.** `created_at`은 문서화된 Jobs REST 응답 스키마에 없다(관측 응답에는 존재한다 — `docs/spec/gh_run_observation_quirks.md` Q18). 필드가 없거나 널인 레코드는 값을 만들지 않고 `NO_LOG_SOURCE`로 보고한다. 가용 레코드 수가 전체보다 적으면 **집계값 자체를 `NO_LOG_SOURCE`로** 표기하며, 가용분만의 부분 합을 그 집계의 값으로 내지 않는다. sentinel 이름은 기존 `NO_LOG_SOURCE`를 재사용한다.
2. **두 집계를 더하지 않는다.** 첫 배치는 실제 큐잉이고 핸드오프는 의존성 해제 지연이다. 합계는 어느 쪽 병목인지 말해주지 않으므로 단일 스칼라로 보고하지 않는다.
3. **batch별 + 분포로 보고한다.** 각 집계는 batch(1차 배치, 각 의존 레벨)별 값과 cohort 분포(p50/p90/min/max)로 낸다. `wallSeconds`와 독립적으로 보고한다.
4. **`g(j)`를 "큐 대기"라고 부르지 않는다.** `g(j)`의 내부 분해(동시성 큐 대기 vs 러너 배정·VM 프로비저닝)는 API에 노출되지 않는다(Q18 판정 규칙). 갭이 측정 가능하다는 것이 성분 분해 가능성을 의미하지 않는다.

### §2.4 `stepSeconds` — 단계 귀속

```
stepSeconds(stepName) = Σ max(0, step.completed_at - step.started_at)
```

- 동일 `name`을 가진 step을 cohort 전체에서 합산한다. composite action의 중첩 step은 GitHub가 별도 step으로 노출하지 않는다.
- `stepSeconds` 합계는 `runnerSeconds` 합계보다 작을 수 있다. 차이는 step으로 기록되지 않는 job 구간이다.
- **provisioning family** = 이름에 `setup-axiom-toolchain`을 포함하는 모든 step의 합.
- `stepSeconds`는 **workflow 단위**다. 서로 다른 workflow의 step 합을 더해 admission 구간으로 읽지 않는다.

### §2.5 `criticalPathSeconds` — workflow별 `needs:` DAG의 최장 경로 (v2 재정의)

**범위**: 하나의 workflow run attempt. 서로 다른 workflow의 job을 한 그래프에 넣지 않는다. `criticalPathSeconds`는 `wallSeconds`와 **같은 attempt**에 대해서만 정의된다.

**입력**: 그 attempt의 attempt-exact job 레코드 집합(§1.3에 따라 `skipped` 포함) + 그 run의 `head_sha`에서 읽은 workflow YAML의 `jobs:`·`needs:`(§7.4).

**그래프**:

- 노드는 §7.1로 귀속된 **top-level job id**다. 노드 집합은 YAML `jobs:` 키 집합과 정확히 일치해야 한다.
- 노드 가중치는 bucket 구간이다: `w(n) = max(completed_at | bucket n) − min(started_at | bucket n)`.
- 엣지 `p → n` 가중치는 선행 완료에서 소비자 생성까지다: `e(p→n) = min(created_at | bucket n) − max(completed_at | bucket p)`.
- `e < 0`은 0으로 **clamp하고 anomaly로 기록**한다. 실측 근거: `skipped` 레코드는 `completed_at`이 `created_at`보다 앞서는 경우가 있다(원 관측 `gateway / proof-reconcile` −2s, 이 문서의 재현 표본에서는 −1s). clamp는 그 사실을 지우지 않고 anomaly 카운트로 남긴다.
- `criticalPathSeconds = max(경로) [ Σ w + Σ clamp(e) ]`, 경로는 소스에서 싱크까지다.

**결정론**: 입력 레코드 순서와 무관하게 같은 값이 나와야 한다. `completed_at` 동률은 `(job id, 레코드 id)` 사전순의 **전순서**로 깨서, 같은 snapshot에 대한 두 실행이 byte-identical 하도록 한다.

**불변식 `criticalPathSeconds ≤ wallSeconds`** (같은 attempt). 엣지가 모두 비음수이면 텔레스코핑으로 성립한다: 경로 합은 `maxComp(n_k) − minStart(n_1) + Σ_{i≥2}(minCreated(n_i) − minStart(n_i))` 로 접히고, `started_at ≥ created_at`이므로 각 항이 0 이하이며 `maxComp(n_k) − minStart(n_1) ≤ wallSeconds` 다.

clamp는 이 접힘을 깨뜨릴 수 있다(음수 엣지를 0으로 올리면 합이 커진다). 그래서 이 부등식은 **가정이 아니라 검사 항목**이다 — 초과하면 attempt·job 집합·clock 중 하나가 잘못된 것이므로 **hard error**다(§8 #6).

**경로 분해 보고 의무**: 노드 시간 합과 엣지 시간 합을 **함께** 보고한다. gather 노드(`admission-check`는 7개 선행을 모두 `needs`로 가진다)로 들어오는 엣지는 어느 선행이든 "그 선행 완료 이후의 전체 대기"를 담으므로, 최장 경로가 **대기 사슬**로 수렴할 수 있다. 노드/엣지 분해 없이 단일 share만 보고하면 "직렬 작업"과 "직렬 대기"를 구분할 수 없다.

### §2.5.1 `criticalPathShare` — per-workflow 진단 (v2 위치 변경)

```
criticalPathShare = criticalPathSeconds / wallSeconds   (같은 workflow, 같은 attempt)
```

`criticalPathShare`는 **그 workflow 자신의 wall에 대한 비율**이며, per-workflow 진단값이다. `T_admission`의 비율이 아니고, 다른 workflow와 합산되지 않는다(§3).

### §2.6 `mergesPerHour` — 처리량

```
mergesPerHour = |{c : c ∈ main 커밋, |parents(c)| ≥ 2, c.committer.date ∈ (t−W, t]}| / W(시간)
```

- **`mergedAt`이 아니라 커밋의 `committer.date`를 쓴다.** GitHub merge queue가 만든 merge commit과 로컬·직접 merge를 동일 기준으로 세기 위해서다.
- `parents`가 2개 미만인 커밋(squash·rebase·direct push)은 merge가 아니므로 제외한다.
- 창 경계는 반개구간 `(t−W, t]`이다. 경계에 걸친 커밋은 어느 창에도 이중 계상하지 않는다.
- 이 지표는 **처리량**이며 지연이 아니다. §2.1의 `wallSeconds`, PR-to-main TOT와 함께 보고하되 서로 대체하지 않는다.
- **분모는 벽시계 시간이지 runner 시간이 아니다.** 따라서 이 값만으로 병목의 위치를 말할 수 없고, `queuedSeconds`·`runnerSeconds`와 함께 읽어야 한다.
- 이론 상한은 `3600 / wallSeconds p50`이며, 실측 처리량이 상한에 근접했다면 그때 용량(capacity)이 병목이다. 상한에 한참 못 미치면 병목은 처리량이 아니라 **입력(PR 도착)** 이다.

## §3. 두 측정 객체 — per-workflow critical path vs `T_admission`

이 문서가 재는 것은 **두 개의 서로 다른 객체**다. 하나의 표·하나의 비율로 합치지 않는다.

| | **per-workflow critical path** | **`T_admission`** |
|---|---|---|
| 단위 | workflow run attempt 1개 | merge_group 후보(SHA) 1개 |
| 구간 | 그 attempt의 첫 job 시작 → 마지막 job 완료 | queue 진입 → merge |
| 분모 | 그 workflow의 `wallSeconds` | `T_admission` |
| 입력 | 그 attempt의 job 레코드 + 그 SHA의 YAML | required context 7개의 check-run |
| 답하는 질문 | "이 workflow 안에서 무엇이 직렬인가" | "사용자는 얼마나 기다렸나" |
| 답하지 못하는 질문 | 전체 admission 중 이 workflow의 비중 | workflow 내부의 직렬 구조 |

### §3.1 per-workflow critical path

§2.5·§2.5.1. 한 workflow의 `needs:` 그래프 위에서 그 attempt의 시간이 어떻게 직렬화되는지만 말한다. 다른 workflow는 **병렬로** 진행되며 이 값에 포함되지 않는다.

### §3.2 `T_admission`

`T_admission`은 required context 7개가 **모두** 완료된 시점까지의 wall이다. 7개는 `config/policy/merge_admission.json`이 선언하며, 서로 다른 workflow에 걸쳐 있다. 따라서 `T_admission`의 지배 구간은 **7개 중 가장 늦게 끝나는 컨텍스트**가 결정하고, 그 컨텍스트가 어느 workflow 소속인지는 cycle마다 달라질 수 있다.

- 4-phase 분할(`T_queue` / `T_verify` / `T_publication` / `T_merge`)과 `reconcile` 항등식(**합 == 총합**, 잔차 흡수 금지)은 v1 계약을 그대로 유지한다. **이 개정은 이를 변경하지 않는다.** 각 phase의 정본 정의는 `tools/ci/ci_admission_observe.nim`의 순수 함수이며, `docs/evidence/ci_admission_measurement_2026-11-24.md`가 그 실측을 기록한다.
- phase 값이 하나라도 관측 불가면 partition 전체를 비운다 — 부분 partition을 완전한 것처럼 내지 않는다.
- per-candidate로 **마지막 finisher 컨텍스트 이름**을 함께 기록한다. 어느 workflow가 wall을 정의했는지가 cohort 해석의 전제다.

### §3.3 금지되는 읽기

| 금지되는 진술 | 왜 틀리는가 |
|---|---|
| "slice의 `criticalPathShare`가 0.9이므로 admission의 90%가 slice다" | share의 분모는 **그 workflow의** wall이다. admission wall은 7개 컨텍스트의 max이고, 다른 workflow는 병렬로 진행된다. |
| "`criticalPathShare`가 1.0이므로 최적화 여지가 없다" | share는 attempt **내부**의 직렬성만 말한다. 경로가 대기 사슬이면(§2.5) 직렬 작업량은 그보다 작다. |
| "workflow별 `criticalPathSeconds`의 합 = `T_admission`" | workflow 간 구간이 겹친다. 합은 중복 계상이다. |
| "workflow별 `criticalPathShare`의 평균 = admission 직렬성" | 분모가 서로 다른 비율의 평균은 어떤 구간의 비율도 아니다. |
| "`wallSeconds`가 가장 큰 workflow가 wall을 정의한다" | 정의하는 것은 **마지막 finisher**다. 오래 걸리는 workflow가 더 일찍 끝날 수 있다. |

## §4. 이전 인용값과의 화해 (필수)

2026-11-19 기준선(`docs/evidence/ci_performance_baseline_2026-11-19.md`)은 **wall p50 574s / runner-seconds p50 979s**를 기록했다. 이 값들은 **다른 5-run cohort A**에서 나왔다. 두 cohort는 4개 run이 겹치고 5번째가 다르다.

| cohort | run IDs | wall p50 | runner p50 |
|---|---|---|---|
| A (2026-11-19) | 44519217624, 44521587339, 44542633420, 44548437642, 44553449785 | 574s | 979s |
| B (이 문서, 2026-11-20) | 44521587339, 44542633420, 44548437642, 44553449785, 44561019095 | 555s | 931s |

따라서 p50 차이는 **표본 차이**이지 공식 차이가 아니다. 두 값 모두 각 cohort에서 유효하며, 서로 대체하지 않는다.

별도의 작은 차이: runner-seconds의 run별 값은 raw 합(2026-11-19 문서)과 clamp 합(이 문서)에서 4–6초 다르다(예: run 44521587339의 1282 vs 1286). skipped job의 비정상 음수 span(`completed_at < started_at`)을 raw 합이 그대로 더하기 때문이다.

**v2 추가**: v2 이전에 발표된 `criticalPathSeconds`·`criticalPathShare`는 §2.5 v1의 역추적 chain 규칙(2초 tolerance, 단일 predecessor 선택)으로 계산되었다. v2의 DAG 최장 경로와 **정의가 다르므로** 두 값을 하나의 series로 비교하거나 비율을 만들지 않는다. v1 값은 역사적 기록으로만 인용한다.

규칙:

- **canonical wall의 정본 정의는 `docs/spec/ci_acceptance_contract.md` §6이다.** 이 문서는 이를 재정의하지 않고 인용한다.
- runner-seconds의 정본 정의는 `docs/evidence/ci_performance_baseline_2026-11-19.md` §1이며, 이 문서는 job별 0-clamp를 명시해 고정한다.
- 전후 비교에는 **하나의 cohort와 하나의 정의**만 사용한다. 서로 다른 cohort의 p50을 섞어 비율을 만들지 않는다.

## §5. 전후 비교 프로토콜

최적화는 다음 조건을 모두 만족할 때만 "개선"으로 판정한다.

1. **동등 workload**: 동일 이벤트(`merge_group`), 동일 워크플로 path, 동일 runner label, 동일 job DAG.
2. **별도 cohort**: before = 사전 등록된 run ID 집합(이미 종료된 실행), after = 변경 커밋 이후 새로 발생한 실행. **같은 run ID를 재측정하지 않는다** — 종료된 실행의 시간은 변하지 않는다.
3. **동일 정의**: §2의 공식과 clamp 규약을 양쪽에 동일 적용.
4. **절대값 + 비율 동시 보고**: `wallSeconds`, `runnerSeconds`, 그리고 **대상 workflow별** `criticalPathShare`. 이 비율은 그 workflow의 wall에 대한 것이며 `T_admission`의 비율이 아니다(§3.3).
5. **불변식 보존 증거**: Z3/Lean 증거, required context, App 출처, fail-closed 판정이 변경 전후 동일함을 별도로 보인다.
6. **DAG 변경은 별도 기준선**: 변경이 대상 workflow의 `jobs:`·`needs:`를 바꾸면 `criticalPathSeconds`는 정의상 비교 불가다. 새 기준선으로 등록하고 이전 값과의 차이를 "개선"으로 보고하지 않는다.
7. **admission 영향은 `T_admission`으로만 주장한다.** per-workflow 개선이 `T_admission`을 줄였다고 주장하려면 같은 cohort의 `T_admission` before/after가 있어야 한다.

표본 n<20에서 p95를 선언하지 않는다. n<20이면 `INCOMPLETE`로 표기하고 최대값·중앙값만 보고한다.

## §6. 비목표

- 이 지표로 admission 판정을 내리지 않는다.
- 캐시/artifact를 증거 저장소로 취급하지 않는다(가속과 증명의 분리).
- 최적화는 검사·증명 단계를 생략해서 달성하지 않는다. "중복 계산 제거"만 허용된다.
- **per-workflow `criticalPathShare`를 admission 비율로 사용하지 않는다**(§3.3).
- **workflow 간 우열을 `criticalPathSeconds`로 정하지 않는다.** workflow마다 wall과 DAG가 다르고, 남는 slack 여부는 별도로 측정해야 한다.
- **`criticalPathSeconds`로 최적화 대상 workflow를 고르지 않는다.** 대상은 마지막 finisher 관측(§1.1)이 정한다.

## §7. 귀속 계약과 그래프 정본

이 절은 §2.5의 입력이 어떻게 만들어지는지를 규정한다. 여기의 규칙은 **규범**이며, 위반은 UNKNOWN 또는 hard error다(§8).

### §7.1 bucket 귀속 — prefix 규칙

job 레코드 이름 `N`을 top-level job id `I`에 다음과 같이 귀속한다.

```
own(N, I)  ⟺  N == I  ∨  N.startsWith(I & " / ")  ∨  N.startsWith(I & " (")
```

구분자는 `space-slash-space`(` / `)이고, matrix instance는 ` (k)` 꼬리를 갖는다(예: `attest / go-critical-lane (0)`).

**suffix 역추론은 금지된다.** 재사용 workflow의 job 이름은 top-level id의 접미사로도 등장하며, 그 접미사가 **다른 top-level job id와 같을 수 있다**. 실측 반례: `attest / admission-check`와 `verdict / admission-check`의 접미사 `admission-check`는 top-level job id이기도 하다. 접미사 파싱은 이 두 레코드를 `admission-check` bucket으로 조용히 오귀속시키고, 정작 `admission-check` 자신의 레코드와 섞인다. **어떤 경우에도 접미사에서 상위 id를 역산하지 않는다.**

관측 앵커(비규범, run `45329393421` attempt 1 — `gh api repos/Archright/Axiom/actions/runs/45329393421/jobs?per_page=100`):

| bucket | 레코드 수 | 구성 |
|---|---:|---|
| `attest` | 6 | `admission-check`, `admission-independents`, `build-base-artifacts`, `go-critical-lane (0)`, `go-critical-lane (1)`, `go-critical-rollup` |
| `gateway` | 8 | `sl09-scope`, `select`, `ci-bootstrap`, `candidate-build-arm`, `gateway-shard`, `gateway-identity-gate`, `proof-reconcile`, `executed-jobs` |
| `verdict` | 5 | `admission-check`, `admission-independents`, `build-base-artifacts`, `go-critical-lane`, `go-critical-rollup` |
| `mint-prepare` | 2 | `certificate-mint.yml`의 `prepare` + `publish` |
| `mint-publish` | 2 | `certificate-mint.yml`의 `prepare` + `publish` |
| `anchor-resolve` | 1 | — |
| `closure-deriver` | 1 | — |
| `admission-check` | 1 | — |
| **합계** | **26** | 잔여 0, 모호 0 |

`mint-prepare`와 `mint-publish`는 **각각** `prepare`와 `publish` 양쪽으로 확장된다(둘 중 하나는 항상 `skipped`). 확장은 **호출된 workflow의 선언된 job 집합**의 성질이지 stage 입력의 성질이 아니다 — 한쪽만 나온다고 보고 다른 쪽을 잘라내지 않는다.

### §7.2 bucket 완료 시각 = `max(completed_at)`

bucket의 완료는 **구성 레코드의 `max(completed_at)`** 이다. `min`도, "아무 구성원"도 아니다. bucket은 하나의 완료 시각만 가지며, 그것이 소비자 엣지의 기점이다.

관측 앵커: 위 run에서 `attest` bucket의 max `completed_at` = `04:57:41Z`이고, 소비자 `mint-prepare / prepare`의 `created_at` = `04:57:41Z` — 엣지 가중치 0. `min`을 쓰면 이 일치가 깨진다.

### §7.3 `skipped` 레코드는 유지한다

bucket을 만들기 **전에** `skipped` 레코드를 필터링하지 않는다. 필터링하면 확장된 job이 그래프 노드에서 사라진다 — 예를 들어 `mint-prepare` bucket이 `prepare` 1개로 줄어, 그래프가 "선언된 job 집합"이 아니라 "실제로 실행된 것"이 되어 버린다. `skipped`는 **기여 시간**에서만 배제되고(§2.2), 노드·엣지 집합에는 남는다.

### §7.4 그래프 정본 — candidate SHA의 YAML + blob SHA 기록

- `needs:` 그래프는 **그 run의 `head_sha`에서 읽은** workflow YAML에서만 만든다. default branch나 working tree의 사본을 쓰지 않는다 — 그러면 과거 attempt의 그래프를 현재 그래프로 재구성하게 된다.
- 그 YAML의 **blob SHA**를 report에 기록한다: run id, `run_attempt`, `head_sha` **옆에** 같은 레코드로 남긴다. blob SHA 없이 run id만 있는 report는 재현 불가다.
- blob SHA는 그 SHA의 contents 응답이 주는 blob id다(`GET /repos/{owner}/{repo}/contents/{path}?ref={head_sha}` → `.sha`). 실측 예: `axiom-operational-slice.yml` @ `e2d35ccd…` → `5ace57c21aaf56427bc5e02b716072258a940cf2`.
- **파싱 범위는 `jobs:`와 `needs:`뿐이다.** 트리거·`with:`·표현식은 읽지 않는다.
- 기존 YAML 리더 재사용 여부: `tools/ci/publication_yaml.nim`은 **의도적으로 제한된 subset**(따옴표 스칼라만, flow style 금지)만 받는다. GitHub workflow YAML은 그 subset 밖이므로(비교: `needs: [a, b]`, 비인용 스칼라) **이 목적에 재사용할 수 없다**. 재사용 가능한 범용 리더는 저장소에 없다.
- 그 SHA에서 YAML을 읽을 수 없으면(파일 부재·API 실패) 그 attempt의 `criticalPath`는 `UNKNOWN`이다. default branch 사본으로 대체하지 않는다.

### §7.5 `parent_job_id`는 존재하지 않는다

재사용 workflow 확장 관계는 **API로 직접 표현되지 않는다**. job 객체와 check-run 객체 어디에도 `parent_job_id`(또는 동등한 상위 job 포인터)가 없다 — 두 객체의 키 합집합을 실측으로 확인했다(2026-11-24: run `45329393421`의 job 26건, 같은 `head_sha`의 check-run 58건 모두 부재).

따라서 그래프는 **YAML + 명명 규약(§7.1)** 으로만 복원된다. "API에 부모 링크가 있을 것"을 가정하는 구현은 fail-open이다.

## §8. Fail-closed 규칙

관측 불가는 추정으로 메우지 않는다. 아래 중 하나라도 해당하면 그 attempt(또는 후보)의 해당 지표는 값이 아니라 상태다.

| # | 조건 | 판정 |
|---|---|---|
| 1 | job 레코드 이름이 **어떤** top-level job id에도 귀속되지 않음 | `UNKNOWN` — 추측 귀속 금지. 부분 bucket으로 계속하지 않는다. |
| 2 | YAML이 job 레벨 `name:`으로 레코드 이름을 대체해, 남은 이름이 `jobs:` 키 집합과 하나도 맞지 않음 | **hard error** — 귀속 불가한 bare name은 그래프 복원 자체가 불가능하다는 뜻이다. |
| 3 | job 레코드가 API에는 있는데 `needs:` 그래프(§7.4)에 없음 | **hard error** — YAML과 attempt가 같은 대상을 기술하지 않는다. |
| 4 | 그래프 노드가 있는데 대응 레코드가 없음 | `UNKNOWN` |
| 5 | critical path 위 임의 노드의 `started_at`/`completed_at`/`created_at`이 없거나 널 | `UNKNOWN` — **0으로 대체 금지** |
| 6 | `criticalPathSeconds > wallSeconds` (같은 attempt) | **hard error** (§2.5 불변식) |
| 7 | job 레코드의 `head_sha` ≠ run의 `head_sha` | **reject** — 다른 commit의 job을 이 attempt로 세지 않는다 |
| 8 | `run_attempt` 불일치 (레코드의 attempt ≠ 선택한 terminal attempt) | **reject** |
| 9 | `conclusion`이 `skipped`·`cancelled`·널 | 성공으로 **계상하지 않는다**. 시간 기여는 §2.2 clamp를 따르고, 그래프 노드로는 남는다(§7.3). |
| 10 | `created_at` 부재로 `queuedSeconds`를 계산할 수 없음 | `NO_LOG_SOURCE` (§2.3) |
| 11 | 그 SHA에서 workflow YAML을 읽을 수 없음 | `UNKNOWN`, default branch 사본으로 대체 금지 (§7.4) |
| 12 | 엣지 가중치 < 0 | 0으로 clamp + anomaly 기록 (§2.5) |

**결정론 요구**: 같은 snapshot에 대한 두 실행의 report는 입력 레코드 순서와 무관하게 동일해야 한다. `completed_at` 동률은 `(job id, 레코드 id)` 전순서로 깬다(§2.5).

**UNKNOWN은 성공이 아니다.** `UNKNOWN`이 하나라도 있는 cohort에서 p50/p90을 그 값들로 채우지 않는다 — 채우면 fail-open이다. `INCOMPLETE`로 표기하고 관측된 수를 함께 낸다.