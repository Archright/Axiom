# CI critical-path baseline — 5 merge-group runs (2026-11-20)

> **Status**: 측정 완료. 실행 구조·워크플로·정책 변경 없음(읽기 전용).
> **Metric contract**: `docs/spec/ci_critical_path_metric.md`
> **Baseline data**: `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json`
> **Collected**: 2026-11-20T04:42:48Z (UTC), `gh` 2.102.0

## §0. 결론

| 지표 | 값 | 해석 |
|---|---|---|
| wall p50 | **555s** (min 430, max 763) | 표본 5건, p95 산출 불가 |
| runner-seconds p50 | **931s** (합 4,886s) | 병렬도 1.72x |
| critical path / wall | **99.9%** | 대기·유휴가 아니라 **직렬 사슬**이 wall을 지배 |
| provisioning family | **2,574s / 4,669 step-seconds = 55.1%** | `setup-axiom-toolchain` 포함 step 합 |
| provisioning 호출 | 36회 / 5 run (7–8회/run), median 39.5s, p75 56s, max 253s | 6회는 0s(단축 경로) |
| queued seconds | median 44s/run (27–277) | 병목 아님 |

직렬 사슬은 `attest`(median 359s) → `mint-publish`(117s) → `mint-prepare`(26s) → `admission-check`(5s)이며, 5-run 평균 critical path는 567.8s다.

## §1. Cohort와 수집 명령

```
for id in 44521587339 44542633420 44548437642 44553449785 44561019095; do
  gh api "repos/Archright/Axiom/actions/runs/$id/jobs?per_page=100" > /tmp/jobs_$id.json
done
```

| run | event | conclusion | head | wall | runner | critical path | setup family |
|---|---|---|---|---|---|---|---|
| 44521587339 | merge_group | failure | 807f38d9 | 763 | 1,286 | 762 | 821s (7회) |
| 44542633420 | merge_group | success | 69d2dce0 | 430 | 824 | 430 | 284s (7회) |
| 44548437642 | merge_group | success | dd8502f6 | 519 | 854 | 519 | 249s (7회) |
| 44553449785 | merge_group | success | a2a86363 | 574 | 991 | 574 | 306s (8회) |
| 44561019095 | merge_group | success | 8bbb035a | 555 | 931 | 554 | 218s (7회) |

모든 run은 `merge_group` 이벤트, workflow `admission-gate`(`.github/workflows/admission-gate-v2.yml`), `run_attempt=1`이다. 44521587339는 conclusion이 failure지만 자연 발생한 terminal attempt이므로 제외하지 않았다. 제외하면 cohort가 "성공한 실행만"으로 편향된다.

## §2. p50 불일치의 원인과 화해

이전 기록의 canonical p50은 wall 574s / runner-seconds 979s였다. 동일 5-run·동일 정의로 다시 계산하면 **wall 555s / runner 931s**다.

원인은 runner-seconds 합산 방식이다. skipped job은 `completed_at < started_at`인 음수 span을 가질 수 있고(최대 1초), raw 합은 이를 그대로 더해 run당 4–6초를 깎는다. 본 baseline은 job별 span을 0으로 clamp한다. 이 표본에서 clamp 정의는 "skipped 제외"와 같은 값을 낸다(931/991/854/824/1286).

wall은 정의가 동일하며 두 계산이 일치한다. 따라서 574/979는 **다른 표본 또는 clamp 없는 합산**에서 나온 값으로 판정하고, 이후 권위 값은 §1의 run ID 집합과 `docs/spec/ci_critical_path_metric.md` 정의로 고정한다.

## §3. 귀속 — 어디에 시간이 쓰이는가

### §3.1 critical path (5-run 재구성)

| run | chain | seconds | share |
|---|---|---|---|
| 44521587339 | attest → mint-prepare → mint-publish → admission-check | 762 | 99.9% |
| 44542633420 | attest → mint-prepare → mint-publish → admission-check | 430 | 100.0% |
| 44548437642 | attest → mint-prepare → mint-publish → admission-check | 519 | 100.0% |
| 44553449785 | attest → mint-prepare → mint-publish → admission-check | 574 | 100.0% |
| 44561019095 | attest → mint-prepare → mint-publish → admission-check | 554 | 99.8% |

사슬 구성은 선언된 `needs`와 관측 span으로 사후 재구성한 것이다(정의 §2.5). `attest` composite 안에서는 `build-base-artifacts`(median 84s) → 최장 lane(median 131–133s) → `admission-check`(median 81s) → rollup(5s) 순으로 직렬이다. lane 0/1은 병렬이므로 합산하지 않는다.

### §3.2 step 귀속 상위 (cohort 합계)

| step | seconds | share of 4,669 | invocations |
|---|---|---|---|
| Run `./.github/actions/setup-axiom-toolchain` | 1,878 | 40.2% | 36 |
| Restore trusted B supply (setup-axiom-toolchain — exact-key B layer) | 441 | 9.4% | 5 |
| [lane] evidenceId contract check (B-owned checker) | 346 | 7.4% | 10 |
| [closure] Pinned toolchain (setup-axiom-toolchain — nim 2.2.10) | 255 | 5.5% | 5 |
| [check] Install libpcre3 | 117 | 2.5% | 10 |
| [build] Build bin/ax + harness from B | 108 | 2.3% | 5 |
| [check] Root layout gate | 102 | 2.2% | 5 |
| (P3) Bin/ax 준비 — trusted B supply | 87 | 1.9% | 5 |
| Install Nim 2.2.10 (choosenim, pinned) | 78 | 1.7% | 5 |

`setup-axiom-toolchain`을 이름에 포함하는 step 합은 1,878 + 441 + 255 = **2,574s = 55.1%**다. 단일 최대 기여이며, critical path 위에 있다. 단, 이 step은 composite action이므로 내부의 다운로드·설치·압축 해제·캐시 복원 시간이 GitHub API에서 하나의 span으로 보인다. **구성요소 분해는 아직 없다.**

`libpcre3` 설치는 run당 2회, 평균 11.7s다. 공급 실패 재시도가 wall에 미치는 영향은 이 표본에서 관측되지 않았다(실패 step 0건).

### §3.3 큐 대기

run별 queued 합계는 27/27/161/277/44초다. 44553449785의 277초가 최대지만 wall 574초 중 critical path가 574초로, 큐 대기는 사슬 밖에서 흡수되었다. runner 배정 지연은 주 병목이 아니다.

## §4. 다음 결정 (구현 아님)

1. **VS-3 후보**: provisioning family. 그러나 2,574초 중 "다운로드 vs 설치 vs 복원"의 분해가 없으므로 캐시부터 도입하지 않는다. 먼저 action step 로그의 타임스탬프로 구성요소를 분해한다.
2. **비교 프로토콜**: after cohort는 변경 커밋 이후 새로 발생한 merge_group 실행이어야 한다. 동일 run ID 재측정은 불가능하다.
3. **불변식**: 최적화는 Z3/Lean 증거·required context·App 출처·fail-closed를 변경하지 않는다.

## §5. 한계

- n=5이므로 p95를 선언하지 않는다. 기존 P95 480s 목표 대비 max 763s는 **관측치**일 뿐 SLO 판정이 아니다.
- critical path는 GitHub가 export하는 값이 아니라 사후 재구성이다. 2초 tolerance와 `needs` 선언에 의존한다.
- step 이름은 워크플로 작성자가 붙인 것이며, 이름 변경은 귀속 시계열을 끊는다.
- raw API 응답은 커밋하지 않았다. run ID로 재수집 가능하다.