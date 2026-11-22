# GO-critical 2-lane 재배치 결정 — VS-CI-01 REJECTED (2026-11-22)

> **Status**: 측정 완료. 본 문서는 결정 기록만 추가한다 — 워크플로·검사·required check·`max_entries_to_build` 변경 없음.
> **Metric contract**: `docs/spec/ci_critical_path_metric.md` (지표 정의 문서)
> **Decision data**: `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json`
> **Sample**: 25 completed merge-group runs (2026-11-21/2026-11-22)
> **Lane composition**: `.github/workflows/admission-check.yml` `go-critical-lane` matrix — lane 0 = `s1a`; lane 1 = `proof_integrity` + `d2_golden` + `d2_persist`

## §0. 판정

> **Verdict: REJECTED — benefit ~2–4 s (≈2%) is inside noise; no verification change**

| 항목 | 값 | 비고 |
|---|---:|---|
| lane 0 wall p50 | **139 s** | 25 completed merge-group runs |
| lane 1 wall p50 | **152 s** | 동일 cohort |
| lane gap p50 | **10 s** | run별 두 lane의 차이 p50 |
| cache warm-up 후 최장 재배치 가능 항목 | **`s1a` 26 s** | 측정된 유일한 재배치 후보 |
| 고정 per-lane provisioning (합) | **≈110 s** | lane 비용의 지배 항 |
| — `setup-axiom-toolchain` | 47–48 s | provisioning 구성요소 |
| — `evidenceId` | 36 s | provisioning 구성요소 |
| 최적 결정론 재배치의 최대 이득 (유도값) | **≈2–4 s / 152 s lane (≈2%)** | 재배치는 구현되지 않음 |

결론: GO-critical 두 lane을 어떻게 재배치해도 wall time은 실질적으로 변하지 않는다. 비용의 지배 항은 작업 불균형이 아니라 **고정 provisioning**이다.

> wall time is dominated by fixed per-lane provisioning, not by work imbalance.

## §1. 배경

`go-critical-lane`은 GO-critical admission-contract 테스트를 두 개의 병렬 lane으로 나눠 실행한다. 제안 VS-CI-01("GO-critical lane rebalancing")의 전제는 두 lane의 작업 배분을 바꾸면 더 느린 lane이 짧아져 merge-group wall time이 줄어든다는 것이었다. 본 측정은 그 전제의 상한을 실측했다.

## §2. 측정

대상은 2026-11-21/22에 완료된 merge-group run 25건이다. 표의 값은 lane별 wall의 p50과 run별 lane 차이의 p50이며, 표본은 완료된 run만 포함한다.

| 지표 | 실측값 |
|---|---:|
| lane 0 wall p50 | 139 s |
| lane 1 wall p50 | 152 s |
| lane gap p50 | 10 s |
| 고정 per-lane provisioning | ≈110 s (`setup-axiom-toolchain` 47–48 s, `evidenceId` 36 s) |
| cache warm-up 후 최장 재배치 가능 항목 | `s1a` 26 s |
| 최적 결정론 재배치의 최대 이득 | ≈2–4 s (152 s lane 대비 ≈2%) |

## §3. 해석

- lane 1의 152 s 중 약 110 s가 고정 provisioning이다. 재배치로 줄일 수 있는 것은 나머지 작업 구간뿐이다.
- cache warm-up 이후 재배치 가능한 최장 항목은 `s1a`의 26 s다. 이 항목을 포함해 최적으로 배분해도 이득은 **≈2–4 s**에 그친다.
- 이는 152 s lane 대비 **≈2%**이며, 25-run 표본에서 관측된 변동(noise) 안에 들어간다. 따라서 lane 재배치는 wall time을 실질적으로 바꾸지 못한다.

## §4. 결정

- **Decision id**: VS-CI-01
- **Decision**: `REJECTED`
- **Reason code**: `INSUFFICIENT_BENEFIT_FIXED_PROVISIONING_DOMINATES`
- **결정 내용**: GO-critical 두 lane의 재배치는 CI 최적화로서 기각한다. 어떤 재배치도 구현하지 않았다.
- **불변식**: 이 결정은 검증을 제거하지 않는다. 어떤 검사도 삭제·skip하지 않으며, required check를 변경하지 않는다. `max_entries_to_build=100`도 변경하지 않는다.

> this decision removes no verification and changes no required check

## §5. 재검토 조건

고정 per-lane provisioning이 줄어 작업 불균형이 lane 비용의 지배 항이 되면, 동일 cohort 규약(`docs/spec/ci_critical_path_metric.md` §1·§5)으로 다시 측정한다. 본 기록은 그때까지의 결정을 고정한다.

## §6. 참조

- `docs/spec/ci_critical_path_metric.md` — 지표 정의 문서 (cohort·wall·step 귀속 규약)
- `docs/evidence/ci_critical_path_baseline_2026-11-20.md` — 선행 critical-path baseline (provisioning family 지배 관측)
- `docs/evidence/ci_provisioning_decomposition_2026-11-20.md` — `setup-axiom-toolchain` 구성요소 분해
- `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json` — 본 결정의 기계 판독 기록

## §7. 한계

- n=25 completed merge-group runs다. p50과 측정된 gap만 기록하며 p95를 선언하지 않는다.
- ≈2–4 s는 최적 결정론 재배치의 상한이다. 재배치 실행은 없었으므로 실측 after 값이 아니다.
- ≈110 s provisioning 합계 중 개별 측정된 구성요소는 `setup-axiom-toolchain`과 `evidenceId`뿐이며, 나머지 구성요소는 합계로만 기록했다.
- lane별 값은 `go-critical-lane` matrix leg 기준이다. run 전체 wall의 정본 정의는 `docs/spec/ci_acceptance_contract.md` §6을 따른다.