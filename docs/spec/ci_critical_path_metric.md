# CI critical-path metric — canonical definitions (VS-1a)

> **Status**: 측정 정의 동결. 본 문서는 **계산 규약**만 정의한다 — 워크플로·정책·소스 동작 변경 없음.
> **Created**: 2026-11-20
> **Baseline**: `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json`
> **Evidence**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md`

## §0. 목적

CI 최적화 결정은 "어디가 느린가"에 대한 **재현 가능한 귀속**에 근거해야 한다. 이 문서는 GitHub Actions의 기존 REST 기록만으로 계산되는 다섯 지표의 공식을 고정한다. 새 관측 서비스·SaaS·계측 코드는 도입하지 않는다.

이 정의는 **성능 측정 전용**이다. 어떤 지표도 admission 판정·증거·캐시 신뢰의 근거가 아니다.

## §1. Cohort (표본) 규약

| 항목 | 규약 |
|---|---|
| 이벤트 | `merge_group` (자연 발생 merge queue 실행만) |
| 워크플로 | `admission-gate` (path `.github/workflows/admission-gate-v2.yml`) |
| attempt | 각 run의 **terminal attempt** (`run_attempt` 최대값)만 |
| 제외 | `workflow_dispatch`·수동 재실행·합성 벤치마크 |
| 최소 크기 | 최적화 **판단**에는 n≥5, **SLO 주장**에는 n≥20 |

`skipped` job은 cohort에서 제거하지 않는다. 대신 기여 시간을 0으로 clamp한다(§2.2). 제거하면 wall의 시작점이 달라져 재현성이 깨진다.

## §2. 지표 정의

모든 timestamp는 GitHub jobs API의 ISO-8601 UTC 값을 그대로 사용한다. 반올림은 출력에서만 하고 계산은 초 단위 실수로 한다.

### §2.1 `wallSeconds` — 사용자가 체감하는 병합 대기

```
wallSeconds = max(completed_at) - min(started_at)
```

terminal attempt의 **모든 job**(skipped 포함, 두 timestamp가 모두 있는 job)에 대해 계산한다.

- 이 값은 runner 대기·큐 대기·job 실행을 모두 포함한 **관측 구간**이다.
- `created_at`은 사용하지 않는다(workflow 생성 시각은 job 시작 전 지연을 별도로 포함).

### §2.2 `runnerSeconds` — 누적 계산 자원

```
runnerSeconds = Σ max(0, completed_at - started_at)   (job별)
```

- `max(0, …)` clamp는 skipped job의 비정상 음수 span(예: `completed_at < started_at` 1초)을 0으로 만든다.
- 이 정의는 이 표본에서 "skipped 제외"와 동일한 값을 낸다(측정 §3.2). clamp는 향후 표본에서도 정의를 고정하기 위한 것이다.
- **주의**: clamp 없이 raw 합을 내면 skipped job의 음수 span이 합계를 깎아 run당 4–6초 낮게 나온다. 이전에 인용된 값과의 차이는 이 정의 차이에서 발생했다(§4).

### §2.3 `queuedSeconds` — runner 배정 대기

```
queuedSeconds = Σ (started_at - created_at)   (started_at이 있는 job)
```

`wallSeconds`와 독립적으로 보고한다. 큐 대기가 병목인지 실행이 병목인지 구분하기 위한 값이다.

### §2.4 `stepSeconds` — 단계 귀속

```
stepSeconds(stepName) = Σ max(0, step.completed_at - step.started_at)
```

- 동일 `name`을 가진 step을 cohort 전체에서 합산한다. composite action의 중첩 step은 GitHub가 별도 step으로 노출하지 않는다.
- `stepSeconds` 합계는 `runnerSeconds` 합계보다 작을 수 있다. 차이는 step으로 기록되지 않는 job 구간이다.
- **provisioning family** = 이름에 `setup-axiom-toolchain`을 포함하는 모든 step의 합.

### §2.5 `criticalPathSeconds` — 의존 사슬의 최장 경로

선언된 `needs` 그래프 위에서, 관측된 job span으로 사슬을 재구성한다.

1. terminal attempt에서 `completed_at`이 최대인 job을 chain의 끝으로 선택한다.
2. 각 단계에서 `needs` 선행 job 중 `completed_at ≤ start(current) + 2s`를 만족하는 것들로 후보를 만들고, `completed_at`이 최대인 것을 선택한다.
3. 후보가 없으면 종료. chain을 역순 정렬한다.
4. `criticalPathSeconds = completed_at(chain[-1]) - started_at(chain[0])`.

이 값은 **사후 재구성**이다. GitHub 스케줄러의 실제 임계 경로를 직접 노출하지 않으며, runner 배정 지연은 job 시작 시각에 이미 반영되어 있다. 2초 tolerance는 runner 시작 오차를 흡수하기 위한 것이다.

`criticalPathShare = criticalPathSeconds / wallSeconds`로 직렬성을 보고한다.

## §4. 이전 인용값과의 화해 (필수)

2026-11-20 이전 기록에는 canonical p50이 **wall 574s / runner-seconds 979s**로 적혀 있었다. 이는 서로 다른 표본(또는 서로 다른 clamp 규약)에서 나온 값이며, 본 문서의 cohort(5 run ID 고정)와 같은 정의로 재계산하면 다음과 같다.

| 지표 | 동일 5-run 재계산 | 이전 기록값 |
|---|---|---|
| wall p50 | **555s** | 574s |
| runner-seconds p50 | **931s** | 979s |

규칙:

- **본 문서 §1–§2 정의로 계산한 값이 권위다.**
- 이전 값은 삭제하지 않고 "정의 미상의 과거 관측"으로 기록한다.
- 최적화 전후 비교에는 **고정된 run ID 집합**과 **동일 정의**를 사용한다. 다른 표본의 값을 섞어 비율을 만들지 않는다.

## §5. 전후 비교 프로토콜

최적화는 다음 조건을 모두 만족할 때만 "개선"으로 판정한다.

1. **동등 workload**: 동일 이벤트(`merge_group`), 동일 워크플로 path, 동일 runner label, 동일 job DAG.
2. **별도 cohort**: before = 사전 등록된 run ID 집합(이미 종료된 실행), after = 변경 커밋 이후 새로 발생한 실행. **같은 run ID를 재측정하지 않는다** — 종료된 실행의 시간은 변하지 않는다.
3. **동일 정의**: §2의 공식과 clamp 규약을 양쪽에 동일 적용.
4. **절대값 + 비율 동시 보고**: `wallSeconds`, `runnerSeconds`, 그리고 `criticalPathShare`.
5. **불변식 보존 증거**: Z3/Lean 증거, required context, App 출처, fail-closed 판정이 변경 전후 동일함을 별도로 보인다.

표본 n<20에서 p95를 선언하지 않는다. n<20이면 `INCOMPLETE`로 표기하고 최대값·중앙값만 보고한다.

## §6. 비목표

- 이 지표로 admission 판정을 내리지 않는다.
- 캐시/artifact를 증거 저장소로 취급하지 않는다(가속과 증명의 분리).
- 최적화는 검사·증명 단계를 생략해서 달성하지 않는다. "중복 계산 제거"만 허용된다.