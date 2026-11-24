# merge_queue `max_entries_to_build` — 후보 lever 기각과 원상복구 (2026-11-24)

> **판정**: **REJECTED — 근거 부족으로 기각, 라이브 값 원상복구(`100`)**.
> **성격**: 플랫폼 파라미터 후보의 검토 기록. 저장소 파일·trust surface·필수 컨텍스트는 무변경.
> **대상**: repository ruleset `27097366` (`main`) 의 `rules[type=merge_queue].parameters.max_entries_to_build`
> **최종 라이브 값**: `100` (변경 전과 동일, readback diff 0)

## §1. 기각한 가설

`max_entries_to_build` 는 merge queue 가 동시에 dispatch 하는 merge_group 빌드의 상한이다. 값이 100 이면 큐에 대기 중인 최대 100 entry 가 동시에 빌드된다. Axiom 의 merge_group 은 entry 1건당 워크플로 8개·job 레코드 44개를 실행하고 Free 조직의 표준 러너 동시 실행 한도는 20 job 이므로, **이 상한을 낮추면 러너 경합이 줄어 wall 이 짧아진다**는 것이 검토한 가설이었다.

## §2. 가설을 지지한 관측 (본 개정에서 실측)

`merge_group` 의 `axiom-operational-slice` 실행 300건(2026-11-20 05:35 ~ 11-24 04:59)에서, 각 실행의 지속 시간과 그 실행과 **시간 구간이 겹치는 다른 slice 실행 수**를 대조했다.

| 겹친 실행 수 | n | p50 (s) | mean (s) | min | max |
|---|---|---|---|---|---|
| 0 | 82 | 391 | 481 | 317 | 1738 |
| 1 | 54 | 452 | 477 | 328 | 686 |
| 2 | 164 | 594 | 632 | 335 | 1295 |
| 3~9 | 84 | 650~1112 | — | — | 1295 |

`Pearson r(겹침, 지속시간) = 0.473`. 최근 30건의 시간순 추이는 겹침 9 → 0 에서 지속 시간 1123 s → 389 s 로 감소했다.

merge group 단위로도 같은 방향이다. 최근 merge_group 13건의 그룹 span 은 **동시성 1 에서 476~615 s(중앙값 550 s), 동시성 ≥2 에서 962~1548 s(중앙값 1095 s)** 였다.

이 관측만 보면 상한을 낮추는 것이 옳다.

## §3. 가설을 기각한 근거

### §3.1 선행 변경은 미검증 드리프트가 아니다

`max_entries_to_build` 는 `2 → 1 → 100` 순으로 바뀌었다(`data/ci_optimization/merge_queue_concurrency_2026-11-21/summary.json:12-17`, `provenanceCorrection`). `1 → 100` 은 다음을 갖춘 의도된 변경이다.

- 목적 진술: "검증 후보 공급 상한을 제거하고 그 효과를 실측한다"
- 적용 시각과 출처(`ruleset.updated_at`) 기록
- 불변성 diff: `requiredStatusChecksDiff: IDENTICAL`, `nonMergeQueueRulesDiff: IDENTICAL`, `bypassActors 0 → 0`
- readback 과 롤백 경로(`reversible: true`)
- 후속 측정 `_after_n10/summary.json` — 같은 arm 을 n=32 로 확장 (`status: APPLIED_AFTER_ARM_OBSERVED_N34_COMPLETED_32`)
- decision record: `STAY_FREE` / `NO_CAPACITY_SATURATION_EVIDENCE` / `AFTER_ARM_COMPLETE`

### §3.2 그 측정이 세운 반증을 본 가설이 통과하지 못한다

`_after_n10/summary.json` 의 결론:

> `"configuredMaxEntriesToBuild": 100, "binding": false`
> "The dispatch ceiling 100 did not bind at all (peak 6). The maximum number of concurrently live merge_group workflow runs was 30. Raising the ceiling further would gain nothing."

그리고 동일 summary 가 다음을 **NOT SUPPORTED / REFUTED** 로 이미 기록해 두었다.

| 주장 | 선행 판정 |
|---|---|
| `max_entries_to_build = 1` 이 병합 지연의 원인이다 | **NOT SUPPORTED** |
| `max_entries_to_build` 는 보안 불변식이다 | **REFUTED** |

`freeConcurrencyLimitReached` 는 `limit: 20, reached: true, timeAtOrAbove20Seconds: 111, fractionPercent: 0.693` 이며, 한도 도달이 지속적인 큐 성장으로 이어지지 않았다고 기록한다.

### §3.3 독립 재측정이 상한이 binding 이 아님을 확인했다

가장 최근 완료 merge_group(`45329393421`, head `c07b8354`, 04:52:38 → 05:00:48Z)의 8개 워크플로 job 레코드 44개(실행 32, skip 12)에 대해 `[started_at, completed_at]` 구간 겹침을 계산했다.

| 집합 | 최대 동시 `in_progress` |
|---|---|
| `admission-gate-v2` 단독 | 5 |
| + `axiom-operational-slice` | 6 |
| 8개 워크플로 전체 | **16** |

488 s 창에서 평균 점유는 **5.3 / 20 (27%)**, `≥18` 및 `≥20` 구간은 **0 초**. 다른 4개 그룹도 peak 14·16·16·15 로 같다.

즉 **단일 merge group 이 20 슬롯을 포화시키지 않는다.** 상한을 낮춰 동시 그룹 수를 줄이면 그만큼 병렬성이 사라지고, 상한은 애초에 구속력이 없었다.

### §3.4 관측된 겹침 상관은 상한의 효과가 아니다

§2 의 상관은 **인과가 아니다**. 상한이 binding 하지 않았다면(§3.3) 겹침은 상한이 아니라 **제출 부하**의 함수다. 부하가 큰 구간에는 겹침도 크고 대기도 길다 — 상한을 낮추면 대기만 늘어난다. 선행 측정의 c100 arm 이 `n=3` 에서 정확히 이 이유로 분포를 선언하지 않고 구조적 부등식만 보고한 것도 같은 이유다.

## §4. 실제로 수행한 조작과 되돌림

1. `GET /repos/Archright/Axiom/rulesets/27097366` 으로 before 스냅샷 확보
2. `max_entries_to_build` 만 `100 → 1` 로 바꾼 PUT 본문 작성·적용
3. readback 의미 diff = **1개 필드**(`100 → 1`), required context 7개·`admission-check` App `5795152`·`bypass_actors: []`·`can_bypass: never` 불변 확인
4. §3 의 근거 확인 후 before 스냅샷으로 **PUT 복원**
5. 복원 readback 의미 diff = **0개 필드**, `max_entries_to_build = 100`

최종 상태는 이 작업 이전과 **완전히 동일**하다.

## §5. 왜 이 필드를 건드리지 않는가

| 항목 | 판정 |
|---|---|
| 드리프트 대상인가 | **아니다** — `tools/merge_ruleset_drift_monitor.nim:135-144` 가 명시적 NOT expectation 으로 선언하고, `tests/unit/test_merge_ruleset_drift_monitor.nim:394-409` 가 값 변경에 무반응임을 단언한다 |
| 값 100 이 측정된 최적인가 | **아니다** — 선행 기록도 "100 이 좋다"고 주장하지 않는다. 주장은 "상한이 구속력이 없어야 한다"이고, 100 은 그 상한 제거의 구현이다 |
| 낮추면 개선되는가 | **아니다** — peak 16/20, 평균 27% 점유, 상한 비구속. 낮추면 병렬성만 감소한다 |
| 검증 계약과 관련 있는가 | **없다** — 필수 컨텍스트·발행 주체·판정 의미를 바꾸지 않는다 |

## §6. 이 기각이 남기는 것

`max_entries_to_build` 는 **파일이 아니므로 trust surface 무관**하고 에이전트 권한으로 즉시 조작 가능하다. 그래서 "권한 때문에 못 했다"는 변명이 성립하지 않는 유일한 lever 였고, 실제로 조작한 뒤 **측정 근거가 지지하지 않아 스스로 되돌렸다**. 파레토 라인 판정에서 이 항목은 "권한 밖"이 아니라 **"근거 밖"** 이다.

## §7. 재현 명령

```bash
gh api repos/Archright/Axiom/rulesets/27097366 > rs_before.json
# max_entries_to_build 만 수정한 rs_put.json 을 만든 뒤
gh api -X PUT repos/Archright/Axiom/rulesets/27097366 --input rs_put.json
gh api repos/Archright/Axiom/rulesets/27097366 > rs_after.json   # 의미 diff 로 검증
gh api -X PUT repos/Archright/Axiom/rulesets/27097366 --input rs_before.json   # 복원
```