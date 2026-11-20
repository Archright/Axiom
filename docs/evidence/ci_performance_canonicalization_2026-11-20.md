# CI performance canonicalization (VS-1b) — cohort B/C, single-run decomposition, upper bounds (2026-11-20)

> **Status**: 측정 완료. 코드·워크플로·정책 변경 없음(읽기 전용). 본 문서는 canonicalization(VS-1b) 추가분이다.
> **Metric contract**: `docs/spec/ci_critical_path_metric.md`
> **Canonical wall**: `docs/spec/ci_acceptance_contract.md` §6
> **Baseline**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md` (errata 포함)
> **VS-1a 상세 분해(보존)**: `docs/evidence/ci_provisioning_decomposition_2026-11-20.md`
> **VS-1a 데이터**: `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json`
> **Collected**: 2026-11-20, `gh` 2.102.0

## §0. 결론

| 항목 | 값 | 해석 |
|---|---|---|
| cohort B wall p50 | **555s** (430–763) | 표본 5건. p95는 n<20이라 선언 불가 |
| cohort B runner-seconds p50 (clamp) | **931s** (합 4,886) | raw 합은 4,874; skipped 음수 span 4–6건 |
| cohort C wall p50 | **445s** (425–659) | 복구 후 merge_group 5건. p95 UNKNOWN |
| cohort C runner-seconds p50 | **967s** (합 4,997) | wall은 개선, runner는 악화 |
| 574/979와의 화해 | cohort A + raw 합 | cohort A clamp p50은 **991**; 표본 + 정의 두 요인 |
| single-run 최대 항목 (run 44743215085) | `Install system deps (libpcre3)` **219.8s (51.8%)** | **그 run의 실측**; 8/8 job, 회당 8.2–41.9s |
| single-run A-layer restore | **171.2s (40.4%)** | hit 7 / miss 1; 네트워크 56.0s, tar 110.8s |
| cohort B 정상 구간 최대 phase | cache restore **769.5s (52.1%)** | tar 추출 67.4% (574.7s) — VS-1a §6.2 |
| intra-run 반복 | run당 **8–9 job**이 동일 composite 실행 | run 간은 별개 VM이므로 중복이 아니라 반복 |
| runner-seconds 산술 상한 | cohort B **411s/run**, cohort C **323s/run** | **달성 가능값 아님** |
| wall 산술 상한 | median **164s/run**, 비율 median **36.0%** | **달성 가능값 아님** |

## §1. 정본 정의

```
wallSeconds   = max(completed_at) − min(started_at)
                terminal attempt의 모든 job 중 started_at·completed_at이
                모두 있는 job만 사용 (skipped 포함)

runnerSeconds = Σ_jobs max(0, completed_at − started_at)
                skipped job의 음수 span(completed_at < started_at)을
                0으로 clamp하는 것이 필수
```

- **정본 소유**: wall은 `docs/spec/ci_acceptance_contract.md` §6, runner-seconds는 `docs/evidence/ci_performance_baseline_2026-11-19.md` §1, clamp 고정은 `docs/spec/ci_critical_path_metric.md` §2.2다.
- **`run_duration_ms`는 비정본**이다. 이 값은 `updated_at − run_started_at`이며, cohort B에서 431/521/556/577/765초로 canonical wall(430/519/555/574/763)보다 1–4초 크다. 수용 판정·전후 비교에 쓰지 않는다.
- `created_at`은 사용하지 않는다. workflow 생성 시각은 job 시작 전 지연을 별도로 포함한다.
- **provisioning family** = 이름에 `setup-axiom-toolchain`을 포함하는 step의 0-clamp 합. 3종 이름이 모두 composite 호출 지점이다. family 2,574초의 내역과 `setup family` 열의 범위 차이는 VS-1a 문서 §5가 다룬다.

Cohort 규약: `merge_group` 이벤트, workflow `admission-gate`(`.github/workflows/admission-gate-v2.yml`), 각 run의 terminal attempt만. `workflow_dispatch`·수동 재실행은 제외한다.

## §2. Cohort B — 기존 기준선 재현

| run | event | conclusion | head | wall | runner raw | runner clamp | family |
|---|---|---|---:|---:|---:|---:|---:|
| 44521587339 | merge_group | failure | `807f38d9` | 763 | 1,282 | **1,286** | 1,080 |
| 44542633420 | merge_group | success | `69d2dce0` | 430 | 818 | **824** | 389 |
| 44548437642 | merge_group | success | `dd8502f6` | 519 | 854 | **854** | 367 |
| 44553449785 | merge_group | success | `a2a86363` | 574 | 979 | **991** | 429 |
| 44561019095 | merge_group | success | `8bbb035a` | 555 | 925 | **931** | 309 |

- raw 합 4,874 / clamp 합 **4,886**. clamp는 run당 +4~+12초를 더한다(음수 span 4–6건).
- **wall p50 555s, runner-seconds(clamp) p50 931s**. p95는 n=5<20이므로 **UNKNOWN**이다(계약 §5).
- run 44521587339는 conclusion이 failure지만 자연 발생한 terminal attempt이므로 제외하지 않았다. 제외하면 "성공한 실행만"으로 편향된다.

## §3. 574/979와의 화해 — 표본 + 정의

기존 문서(`docs/evidence/ci_critical_path_baseline_2026-11-20.md` §2, `docs/spec/ci_critical_path_metric.md` §4)는 574/979와 555/931의 차이를 **표본 차이**로만 설명한다. 이는 절반만 맞다. 574/979는 **cohort A + raw 합**의 조합이고, 555/931은 **cohort B + clamp 합**의 조합이다.

| 정의 | cohort A (5번째 run `44519217624`) | cohort B (5번째 run `44561019095`) |
|---|---:|---:|
| wall p50 | **574** | **555** |
| runner p50 (raw) | **979** ← 기존 문서 인용값 | 925 |
| runner p50 (clamp) | **991** | **931** ← 본 문서 정본 |

- cohort A 원자료: run `44519217624`는 wall 708 / raw 1,366 / **clamp 1,372**다. cohort A clamp runner 값은 1,372/1,286/824/854/991이고 p50은 **991**이다.
- **정의 효과**: 같은 cohort A에서 raw 979 → clamp 991, **+12초**.
- **표본 효과**: cohort A clamp 991 → cohort B clamp 931, **−60초**.
- **순효과**: 979 → 931, **−48초**. 즉 차이는 표본과 정의 두 요인의 합이며, "표본 차이"만으로는 12초를 설명하지 못한다.

이 정정은 본 문서에서만 수행한다. `docs/spec/ci_critical_path_metric.md`의 정의 자체는 유효하며, 수정하지 않는다(범위 밖).

## §4. Cohort C — 복구 후 merge_group 5건

| run | event | conclusion | head | wall | runner | family | 호출/실행 |
|---|---|---|---:|---:|---:|---:|---:|
| 44743215085 | merge_group | success | `f8959445` | 445 | 844 | 424 | 9 / 8 |
| 44741298189 | merge_group | success | `b0967e55` | 428 | 813 | 358 | 9 / 8 |
| 44735026078 | merge_group | success | `20fc6d44` | 425 | 967 | 418 | 10 / 9 |
| 44724689422 | merge_group | failure | `79536817` | 602 | 1,192 | 399 | 10 / 9 |
| 44723151115 | merge_group | success | `467e02f4` | 659 | 1,181 | 375 | 10 / 9 |

| 지표 | cohort B | cohort C | Δ |
|---|---:|---:|---:|
| wall p50 | 555 | **445** | −110 |
| runner-seconds p50 | 931 | **967** | +36 |
| family 합 | 2,574 | **1,974** | −600 |
| wall max | 763 | 659 | −104 |

wall은 개선됐지만 runner-seconds는 악화됐다. 표본 5건이며 p95는 **UNKNOWN**이다. run 44724689422는 failure지만 자연 발생한 terminal attempt이므로 유지한다.

## §5. Single-run 분해 — run 44743215085

### §5.1 방법

composite 내부 step은 jobs API에 노출되지 않는다(`docs/spec/ci_critical_path_metric.md` §2.4). 액션이 job 로그에 출력하는 마커로 분해했다:

```
##[start-action display=<step 이름>;id=<action>.<step id>]
##[end-action id=<action>.<step id>;outcome=<...>;conclusion=<...>;duration_ms=<n>]
```

`gh run view 44743215085 --log`에서 **176 레코드 = 8 실행 × 22 step**을 파싱했다. 내부 step 값은 전부 `duration_ms`(ms 정밀도)이고, 바깥 span 검증에는 jobs API의 초 정밀도 step span을 썼다.

| 항목 | 초 | 비고 |
|---|---:|---|
| composite outer span 합 (8 호출) | **424** | jobs API step span: 298 + 49 + 77 |
| 내부 22 step 합 | **420.4** | outer의 99.2% |
| 미귀속(경계 오버헤드) | **3.6** | 0.8% |

### §5.2 구성요소

비율의 분모는 **424초**(이 run의 composite outer 합)다. 아래 값은 **run 44743215085 한 건의 실측**이며, cohort B 대표값이 아니다(§6).

| 구성요소 | 초 | outer 대비 | 실행 | 비고 |
|---|---:|---:|---:|---|
| `Install system deps (libpcre3)` | **219.8** | **51.8%** | 8/8 | 회당 8.2–41.9s, apt 재실행 |
| `A-layer restore` (1,078 MB) | **171.2** | **40.4%** | 8/8 | hit 7 / miss 1 |
| └ 네트워크 | 56.0 | 33.6%¹ | 7 hit | `Cache hit` → `Cache Size` |
| └ tar 추출 | **110.8** | **66.4%**¹ | 7 hit | `Cache Size` → `restored` |
| `B-layer restore` (51 MB) | **13.7** | **3.2%** | 8/8 | |
| `Compute A/B cache identities` | **4.8** | **1.1%** | 8/8 | keygen |
| verification/probe 계열 | **7.2** | **1.7%** | | 지문 검증·provenance/기능 probe·핀 검증·restore 관측 |
| 기타 (Z3·jq 설치, A-layer save, export/discard) | 3.8 | 0.9% | | |
| harness 경계 | 3.6 | 0.8% | | 내부 합과 outer의 차이 |
| **합** | **424.0** (반올림) | **100%** | | 내부 합 420.4 + 경계 3.6 |

¹ A-layer 내부 비율. 네트워크+tar = 166.8s이고, A-layer 전체 171.2s와의 차이 4.4s는 캐시 액션의 조회·경계 오버헤드다.

`Install system deps`는 이 run의 **8/8 job 전부**에서 실행됐고, 로그에 apt fetch/install이 매번 다시 나온다. `libpcre3`는 캐시 restore 대상이 아니라 **job마다 apt를 재실행**하는 구조다.

### §5.3 캐시 관측

- 로그에 `Cache hit for: axiom-a-…` / `Cache not found for input keys: axiom-a-rt-…` / `Cache restored from key: …`가 그대로 남는다. 이 run은 **A-layer hit 7 / miss 1**이다.
- miss 1건은 `mint-prepare / prepare`(13:24:22Z)다. VS-1a 문서 §6.2가 지목한 런타임 스코프 키(`axiom-a-rt-*`) 요청과 같은 지점이다.
- hit/miss는 로그로 판정 가능하지만, miss의 원인이 키 네임스페이스인지 save 이력인지는 이 측정 범위 밖이다.

### §5.4 job별 provisioning 비중

| job | job 초 | setup 초 | 비중 |
|---|---:|---:|---:|
| closure-deriver | 103 | 77 | 74% |
| mint-publish / publish | 72 | 49 | 68% |
| attest / build-base-artifacts | 77 | 51 | 66% |
| attest / admission-check | 107 | 63 | 58% |
| mint-prepare / prepare | 51 | 20 | 39% |

작은 job일수록 provisioning 비중이 크다. composite는 이 job들에서 **병렬로** 실행되므로, setup 합을 runner-seconds나 wall에 그대로 더하면 안 된다.

## §6. 단일 run과 cohort의 대조 — 일반화 금지

VS-1a 문서는 cohort B 5 run / composite 40 실행의 22-step 전체 분해를 보존한다. 본 문서 §5는 cohort C의 **단일 run** 1건을 분해한다. 두 표본은 크기·사고 포함 여부가 다르므로, 단일 run 수치를 cohort 대표값으로 쓰지 않는다.

| 항목 | 단일 run 44743215085 (8 실행) | cohort B (40 실행, VS-1a) |
|---|---:|---:|
| `Install system deps (libpcre3)` | **219.8s (51.8%)** | **1,542.1s** (사고 포함) |
| — 사고 5건 제외 | — | **657.3s / 35회 = 평균 18.8s** |
| `A-layer restore` | 171.2s (40.4%) | 874.5s |
| — tar 추출 | 110.8s / 166.8s (66.4%) | **574.7s (67.4%)** |
| `B-layer restore` | 13.7s (3.2%) | 59.4s |
| 정상 구간 최대 phase | — (단일 run) | **cache restore 769.5s (52.1%)** |
| 처리량 / payload | — | 144 MB/s, 복원당 1,004 MB |

핵심 조건:

- 단일 run의 `Install system deps` **219.8s (51.8%)**는 **그 run의 실측값**이다. 이 run은 libpcre3 설치가 상대적으로 비쌌던 표본이며, cohort B의 대표값이 아니다.
- cohort B 40회 기준 install은 **1,542.1s**(사고 포함)이고, 사고 5건(전부 run 44521587339의 Ubuntu archive HTTP 503, 합 884.8s)을 제외하면 **657.3s/35회 = 평균 18.8s**다.
- 정상 구간의 최대 phase는 **cache restore 769.5s(52.1%)**이고, 그 **67.4%가 tar 추출(574.7s)**이다. 네트워크는 32.6%(278.6s)다.
- 따라서 **"libpcre3가 항상 최대 단일 비용"이라고 일반화하지 않는다.** 단일 run에서는 install이 51.8%로 최대였지만, cohort B 정상 구간에서는 cache restore가 최대 phase다. 반대로 단일 run의 cache restore 40.4%를 cohort B의 정상 구간 비중으로 일반화하지도 않는다.
- cohort B의 raw install 합은 공급 사고 1건이 지배한다. 사고를 포함한 합계와 사고 제외 평균을 섞어 "평균 install 비용"을 만들지 않는다.

## §7. Intra-run 반복 — 중복의 성격

- run 44743215085에서 동일 composite가 **8개 job**에서 실행됐다: `closure-deriver`, `attest / build-base-artifacts`, `attest / go-critical-lane (0)`, `(1)`, `attest / admission-independents`, `attest / admission-check`, `mint-prepare / prepare`, `mint-publish / publish`. `verdict / admission-check` 1건은 `skipped` 0초다.
- cohort C는 48 호출 중 43 실행 / 5 skipped, cohort B는 46 호출 중 40 실행 / 6 skipped다. run당 **8–9 job이 실제 실행**한다.
- **run 간은 중복이 아니라 반복**이다. GitHub-hosted runner는 job마다 새 VM을 할당하고 job 종료 후 폐기한다. 따라서 run 사이에는 공유 상태가 없고, 공유 수단은 캐시뿐이다.
- 최적화 대상은 **동일 run 안의 8–9회 반복**이다. run 간 값을 "중복 제거"로 합산하지 않는다.

## §8. 산술 상한 — 달성 가능값 아님

### §8.1 runner-seconds 상한

정의: run별 `Σ(family) − max(단일 composite 호출)`. run당 provisioning을 1회만 남긴다는 가정이며, 공유 비용을 0으로 둔 값이다.

| cohort | run별 상한 | 합 | 평균 |
|---|---|---:|---:|
| B | 827 / 327 / 291 / 355 / 255 | 2,055 | **411 s/run** |
| C | 347 / 283 / 338 / 337 / 312 | 1,617 | **323 s/run** |

### §8.2 wall 상한

정의: critical-path job들의 setup 합(`attest / build-base-artifacts` + `attest / admission-check` + `mint-prepare / prepare` + `mint-publish / publish`). 그 job들에서 provisioning을 완전히 없앨 수 있다는 가정이다.

| run | chainSetup | wall | 비중 |
|---|---:|---:|---:|
| 44743215085 | 183 | 445 | 41.1% |
| 44741298189 | 164 | 428 | 38.3% |
| 44735026078 | 153 | 425 | 36.0% |
| 44724689422 | 177 | 602 | 29.4% |
| 44723151115 | 141 | 659 | 21.4% |

**중앙값 164 s/run (36.0%)**. 여기서 164s는 절대값의 중앙값(run 44741298189), 36.0%는 비율의 중앙값(run 44735026078)이며, 같은 run에서 나온 한 쌍이 아니다.

### §8.3 왜 달성 가능값이 아닌가

- 8개 job이 각각 1,078 MB를 복원하는 것을 1회로 줄이려면 나머지 7개 job이 그 payload를 **다른 경로로** 받아야 한다. artifact 다운로드도 약 1 GB이고, A-layer restore의 회당 비용은 약 21초(171.2/8)다.
- `Install system deps`는 캐시 대상이 아니므로, provisioning을 1회로 줄여도 apt 재실행 비용은 남는다.
- 따라서 위 값은 **산술 상한**이며, 실제 절감은 after cohort 없이는 **UNKNOWN**이다.

## §9. 한계

- cohort B/C 모두 n=5다. **p95는 n<20이라 선언 불가(UNKNOWN)**. 중앙값·최대값만 보고한다.
- critical path는 GitHub가 export하는 값이 아니라 `needs`와 관측 span으로 사후 재구성한 것이다(`docs/spec/ci_critical_path_metric.md` §2.5). 2초 tolerance에 의존한다.
- composite 내부 step은 **액션 로그 마커**로만 분해된다. 마커를 출력하지 않는 개정에서는 같은 방법을 쓸 수 없다.
- `duration_ms`는 액션이 보고한 값이다. VS-1a 문서 §9의 cohort B 880 레코드 전수 확인에서 `start-action`/`end-action` 타임스탬프 차이와 0.000–0.003초 안에서 일치했다.
- apt의 fetch/install 경계는 `apt-get -qq` 때문에 근사다. fetch 구간에 인덱스 해석 시간이 섞인다.
- cohort C의 closure 5건은 `@c021c338` remote-ref 사본이다. step 이름은 같지만 blob이 다르므로, 내부 시간을 트리 사본의 성능으로 일반화하지 않는다.
- 원시 로그·JSON은 커밋하지 않았다. run ID와 §10의 명령으로 재수집 가능하다.
- after cohort(변경 커밋 이후 새 merge_group 실행)가 없으므로 실제 절감은 **UNKNOWN**이다.

## §10. 재현 명령

```bash
# run 메타데이터
gh api repos/Archright/Axiom/actions/runs/<id> \
  --jq '{id,name,event,head_sha,created_at,run_started_at,updated_at,conclusion,run_attempt}'

# job/step span (wall·runner·family)
gh api "repos/Archright/Axiom/actions/runs/<id>/jobs?per_page=100" > jobs_<id>.json

# composite 내부 마커 (run 44743215085)
gh run view 44743215085 --log --repo Archright/Axiom > runlog_44743215085.txt
# start-action/end-action 쌍을 파싱해 duration_ms를 step별로 합산
```

wall/runner 계산은 §1의 정의를 그대로 적용한다. `skipped` job의 음수 span은 반드시 `max(0, …)`로 clamp한다.

## §11. 참조 / VS-1a 문서와의 관계

- **VS-1a 문서는 보존된다**: `docs/evidence/ci_provisioning_decomposition_2026-11-20.md`는 cohort B 5 run / composite 40 실행의 22-step 전체 분해, 공급 사고(HTTP 503) 884.8s 보정, 정상 install 평균 18.8s, cache restore 769.5s와 tar 추출 67.4%, 144 MB/s, 1,004 MB payload를 그대로 담고 있다. 본 PR은 그 파일을 수정하지 않는다.
- **본 문서의 역할**: 정본 정의(clamp 포함), cohort B/C p50, 574/979 화해, 단일 run 44743215085 분해, intra-run 반복, 산술 상한을 **추가**한다. VS-1a의 40회 분해를 대체하지 않는다.
- 정본 정의: `docs/spec/ci_critical_path_metric.md` §2.1–§2.5, `docs/spec/ci_acceptance_contract.md` §6
- cohort A 원자료: `docs/evidence/ci_performance_baseline_2026-11-19.md` §2
- cohort B baseline: `docs/evidence/ci_critical_path_baseline_2026-11-20.md`
- VS-1a 데이터: `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json`
- composite 정의: `.github/actions/setup-axiom-toolchain/action.yml`
- GitHub jobs API: <https://docs.github.com/en/rest/actions/workflow-jobs> — `steps[].started_at`/`completed_at`의 의미.
- 캐시 hit/복원 의미: <https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching>
- hosted runner 수명: <https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners> — "When the job begins, GitHub automatically provisions a new VM for that job."