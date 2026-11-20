# CI provisioning 구성요소 분해 — `setup-axiom-toolchain` (2026-11-20)

> **Status**: 측정 완료. 워크플로·액션·정책 변경 없음(읽기 전용). 산출물은 본 문서 + `summary.json`뿐이다.
> **Metric contract**: `docs/spec/ci_critical_path_metric.md`
> **선행 baseline**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md` (동일 cohort, 동일 정의)
> **Data**: `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json`
> **Collected**: 2026-11-20, `gh` 2.102.0

## §0. 결론

baseline은 provisioning family 2,574초를 "단일 최대 기여"로 지목하면서, 그 안의 `다운로드 vs 설치 vs 복원` 분해가 없다는 이유로 캐시 변경을 보류했다. 본 측정이 그 분해를 수행했다.

| 항목 | 값 | 해석 |
|---|---|---|
| composite 호출 지점 | **46** (실행 40, 0초 6) | 이름 매칭 3종 모두 composite 호출이다 |
| composite outer span 합 | **2,574.0s** | baseline의 provisioning family와 정확히 일치 |
| 내부 22개 step 합 | **2,552.7s** | outer의 99.2% |
| 미귀속 | **21.3s (0.83%)** | composite harness 오버헤드. 남는 시간 없음 |
| 최대 phase (cohort) | **install/extract 1,549.1s (60.7%)** | 그중 884.8s가 **단일 공급 사고** |
| 최대 phase (사고 제외) | **cache restore 769.5s (52.1%)** | 그중 67.4%가 **tar 추출**, 네트워크는 32.6% |
| verification/provenance | 64.7s (2.5%) | 고정비. phase 순위와 무관 |

핵심 판정 두 가지:

1. **cohort 최대치는 사고가 만든 값이다.** `Install system deps` 1,542.1초 중 884.8초는 run `44521587339`의 Ubuntu archive HTTP 503 구간이다(느린 상위 5건이 모두 이 run — 4건 실패, 1건은 92초 재시도 후 성공). 이 5건을 빼면 같은 step은 657.3초/35회 = 평균 18.8초다.
2. **정상 구간의 최대 phase는 cache restore이고, 그 비용은 대역폭이 아니라 추출이다.** A-layer restore 874.5초 중 네트워크 278.6초, tar 추출 574.7초(67.4%)다. 실측 처리량은 144 MB/s, 복원당 payload는 1,004 MB다.

## §1. Cohort와 수집 명령

baseline과 동일한 5개 `merge_group` run, terminal attempt, `admission-gate`(`.github/workflows/admission-gate-v2.yml`)다. run `44521587339`는 결론이 `failure`지만 자연 발생한 terminal attempt이므로 유지한다.

```
# 1) step span (초 정밀도)
for id in 44521587339 44542633420 44548437642 44553449785 44561019095; do
  gh api "repos/Archright/Axiom/actions/runs/$id/jobs?per_page=100" > /tmp/prov-data/jobs_$id.json
done

# 2) composite 내부 step span (ms 정밀도) — job 로그
for id in 44521587339 44542633420 44548437642 44553449785 44561019095; do
  gh run view $id --log --repo Archright/Axiom > /tmp/prov-data/runlog_$id.txt
done

# 3) trust surface (읽기 전용)
git show origin/main:.github/actions/setup-axiom-toolchain/action.yml > /tmp/prov-data/action.yml
```

| run | event | conclusion | head | wall | runner | critical path | 호출 지점 | 실행 | 0s | composite outer | runner 대비 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 44521587339 | merge_group | failure | `807f38d9fe` | 763 | 1,286 | 762 | 9 | 7 | 2 | 1,080 | 84.0% |
| 44542633420 | merge_group | success | `69d2dce0` | 430 | 824 | 430 | 9 | 8 | 1 | 389 | 47.2% |
| 44548437642 | merge_group | success | `dd8502f6` | 519 | 854 | 519 | 9 | 8 | 1 | 367 | 43.0% |
| 44553449785 | merge_group | success | `a2a86363` | 574 | 991 | 574 | 10 | 9 | 1 | 429 | 43.3% |
| 44561019095 | merge_group | success | `8bbb035a` | 555 | 931 | 554 | 9 | 8 | 1 | 309 | 33.2% |

`wall`·`runner`·`critical path`는 baseline 값을 같은 정의로 재계산해 일치를 확인했다(`wallSeconds` = max(completed) − min(started), `runnerSeconds` = Σ max(0, …)). "runner 대비"는 composite outer 합 ÷ `runnerSeconds`다 — composite가 여러 job에서 **병렬로** 돌기 때문에 `wall` 대비 비율은 의미가 없다(44521587339는 141.6%가 나온다).

## §2. 방법 — composite 내부 step은 jobs API에 없다

`docs/spec/ci_critical_path_metric.md` §2.4는 "composite action의 중첩 step은 GitHub가 별도 step으로 노출하지 않는다"고 이미 고정했다. 이 cohort에서 그 사실을 직접 확인했다. 이름에 `setup-axiom-toolchain`을 포함하는 step은 **3종뿐**이다.

| step 이름 | 호출 | 실행 | 0초 | 초 |
|---|---|---|---|---|
| `Run ./.github/actions/setup-axiom-toolchain` | 36 | 30 | 6 | 1,878 |
| `Restore trusted B supply (setup-axiom-toolchain — exact-key B layer)` | 5 | 5 | 0 | 441 |
| `[closure] Pinned toolchain (setup-axiom-toolchain — nim 2.2.10, no inline choosenim)` | 5 | 5 | 0 | 255 |
| **합** | **46** | **40** | **6** | **2,574** |

`action.yml`의 22개 내부 step(`Compute A/B cache identities`, `A-layer restore`, `Install Nim`, `Verify toolchain pins` …)은 jobs API에 **하나도** 나타나지 않는다. 세 이름 모두 실제로는 composite 호출이다 — `Restore trusted B supply`는 `certificate-mint.yml:1334`의 `uses: ./.github/actions/setup-axiom-toolchain`, `[closure] Pinned toolchain`은 `admission-gate-v2.yml:278`의 `uses: Archright/Axiom/...@c021c338`이다.

분해는 **job 로그의 composite 경계 마커**로 수행했다. 액션은 각 내부 step마다 아래를 출력한다:

```
##[start-action display=<step 이름>;id=<action>.<step id>]
##[end-action id=<action>.<step id>;outcome=<success|failure|skipped>;conclusion=<…>;duration_ms=<n>]
```

`duration_ms`는 ms 정밀도이고, 액션이 직접 계산한 값이다. 본 문서의 내부 step 값은 전부 이 값이며, jobs API의 초 단위 step span은 **바깥 span 검증에만** 썼다. 파싱 결과는 실행당 정확히 22개 레코드, 5-run 합계 880 레코드(40 실행 × 22)다.

외부 span과 내부 합의 정합(실행별):

| run | outer | internal | 차이 |
|---|---|---|---|
| 44521587339 | 1,080 | 1,076.6 | 3.4 |
| 44542633420 | 389 | 385.1 | 3.9 |
| 44548437642 | 367 | 363.1 | 3.9 |
| 44553449785 | 429 | 423.6 | 5.4 |
| 44561019095 | 309 | 304.3 | 4.7 |
| **합** | **2,574** | **2,552.7** | **21.3** |

실행당 0.5초 남짓이며 실행 수에 비례한다(40 실행 × 22 경계 ≈ 880 마커). 값이 음수인 step span은 없었고, 0초 호출 지점 6건은 `started_at == completed_at`인 `skipped` step이다 — **clamp가 필요한 음수 span은 step 수준에서 0건**이다(음수 span은 baseline이 지적한 job 수준 현상이다).

### §2.1 phase 매핑

| phase | 내부 step |
|---|---|
| `cache_restore` | `A-layer restore`, `A-layer restore observation`, `A-layer non-exact discard`, `B-layer restore`, `B-layer restore observation` |
| `install_extract` | `Install system deps (libpcre3)`, `Install Nim (choosenim)`, `Install Nim dependencies`, `Install Lean`, `Install Z3`, `Install jq` |
| `verification` | `Compute A/B cache identities`, `A-layer fingerprint verify`, `B-layer fingerprint verify`, `B-layer provenance probe`, `Toolchain functional probes`, `Verify toolchain pins`, `Nim-scope verification stamp`, `A-layer lock-completeness check`, `A-layer save authority`, `A-layer save` |
| `other` | `Export toolchain PATH` |

`A-layer save`는 phase 이름상 `cache_restore`가 아니라 `verification`에 두었다 — payload를 쓰는 단계이고 40회 중 36회가 skipped이므로 순위에 영향이 없다.

## §3. 내부 step별 집계 (40 실행)

`median`/`p75`는 **실행된 회차만** 대상으로 계산했다(0초 skipped 제외). `sum`은 0-clamp 합이다.

| 내부 step | phase | 실행 | skipped | sum | median | p75 | max |
|---|---|---|---|---|---|---|---|
| Install system deps (libpcre3) | install_extract | 40 | 0 | 1,542.1 | 21.2 | 32.2 | 230.2 |
| A-layer restore | cache_restore | 40 | 0 | 874.5 | 22.0 | 29.9 | 32.7 |
| B-layer restore | cache_restore | 40 | 0 | 59.4 | 1.4 | 2.5 | 3.0 |
| keygen (Compute A/B cache identities) | verification | 40 | 0 | 24.8 | 0.6 | 0.7 | 0.9 |
| Toolchain functional probes | verification | 40 | 4 | 10.7 | 0.3 | 0.4 | 0.5 |
| B-layer provenance probe | verification | 40 | 16 | 8.6 | 0.4 | 0.4 | 0.5 |
| B-layer fingerprint verify | verification | 40 | 12 | 6.9 | 0.2 | 0.3 | 0.4 |
| A-layer save | verification | 40 | 36 | 6.8 | 1.8 | 2.2 | 2.3 |
| Install Z3 4.13.3 | install_extract | 40 | 36 | 6.4 | 1.6 | 1.6 | 1.7 |
| A-layer fingerprint verify | verification | 40 | 4 | 3.6 | 0.1 | 0.1 | 0.3 |
| Verify toolchain pins | verification | 40 | 4 | 2.8 | 0.1 | 0.1 | 0.1 |
| B-layer restore obs | cache_restore | 40 | 0 | 2.3 | 0.0 | 0.1 | 0.2 |
| A-layer restore obs | cache_restore | 40 | 0 | 2.2 | 0.0 | 0.1 | 0.3 |
| Install jq 1.7.1 | install_extract | 40 | 36 | 0.7 | 0.1 | 0.2 | 0.3 |
| Export toolchain PATH | other | 40 | 4 | 0.4 | 0.0 | 0.0 | 0.0 |
| A-layer lock-completeness check | verification | 40 | 4 | 0.4 | 0.0 | 0.0 | 0.0 |
| A-layer non-exact discard | cache_restore | 40 | 36 | 0.1 | 0.0 | 0.0 | 0.0 |
| A-layer save authority | verification | 40 | 36 | 0.0 | 0.0 | 0.0 | 0.0 |
| Install Nim (choosenim) | install_extract | 40 | 40 | 0.0 | — | — | 0.0 |
| Install Nim dependencies | install_extract | 40 | 40 | 0.0 | — | — | 0.0 |
| Install Lean 4.33.0 | install_extract | 40 | 40 | 0.0 | — | — | 0.0 |
| Nim-scope verification stamp | verification | 40 | 40 | 0.0 | — | — | 0.0 |
| **합** | | | | **2,552.7** | | | |

`Install Nim`·`Install Nim dependencies`·`Install Lean`은 **40회 전부 skipped**다 — A-layer가 36/40 hit이므로 네이티브 설치 경로가 거의 발화하지 않는다. `Install Z3`·`Install jq`는 정확히 **4회** 실행됐고, 그 4회는 A-layer miss 4건과 **같은 실행**이다(`mint-prepare / prepare`, 전부 `axiom-a-rt-*` 런타임 스코프 키 요청, 로그: `Cache not found for input keys`). 즉 "다운로드해서 설치하는" 경로는 정상 구간에서 이미 거의 꺼져 있고, 켜지는 지점은 구조적으로 결정된다.

## §4. phase별 분해

### §4.1 run별

| run | cache_restore | install_extract | verification | other | 합 |
|---|---|---|---|---|---|
| 44521587339 | 169.0 | **899.5** | 8.1 | 0.0 | 1,076.6 |
| 44542633420 | 190.7 | 179.3 | 15.0 | 0.1 | 385.1 |
| 44548437642 | 194.4 | 153.6 | 15.0 | 0.1 | 363.1 |
| 44553449785 | **232.0** | 175.0 | 16.5 | 0.1 | 423.6 |
| 44561019095 | 152.3 | 141.8 | 10.1 | 0.1 | 304.3 |
| **cohort** | **938.5** | **1,549.1** | **64.7** | **0.4** | **2,552.7** |

run별 편차가 크다: 304.3 ~ 1,076.6 (3.5배). 44521587339를 제외하면 304.3 ~ 423.6으로 1.4배 안에 들어온다.

### §4.2 cohort vs 사고 제외

| phase | cohort 합 | share | 실행당 | 사고 제외 합 | share | 실행당 |
|---|---|---|---|---|---|---|
| cache_restore | 938.5 | 36.8% | 23.5 | **769.5** | **52.1%** | 23.3 |
| install_extract | **1,549.1** | **60.7%** | 38.7 | 649.6 | 44.0% | 19.7 |
| verification | 64.7 | 2.5% | 1.6 | 56.6 | 3.8% | 1.7 |
| other | 0.4 | 0.0% | 0.0 | 0.4 | 0.0% | 0.0 |
| 합 | 2,552.7 | 100% | 63.8 | 1,476.0 | 100% | 44.7 |

"사고 제외"는 run `44521587339`를 뺀 4 run / 33 실행이다. **어느 쪽을 최대 phase로 부르느냐가 결론을 바꾼다** — 그래서 둘 다 보고한다. cohort 값은 baseline과 같은 표본이라 비교 가능하고, 사고 제외 값은 재현 가능한 정상 상태를 나타낸다.

## §5. 2,574초로의 화해

baseline의 2,574초는 `이름에 setup-axiom-toolchain을 포함하는 step`의 0-clamp 합이다. 본 측정은 같은 규칙으로 **2,574초를 그대로 재현**했고(차이 0), 그것이 실제로 3개 호출 지점 × composite 실행 40건과 일치함을 확인했다.

| 항목 | 값 | 비고 |
|---|---|---|
| baseline 합계 | 2,574 | `Run ./.` 1,878 + `Restore trusted B supply` 441 + `[closure] Pinned toolchain` 255 |
| 재현 합계 | 2,574 | 차이 **0** |
| clamp로 달라진 값 | 0 | step 수준 음수 span 0건 |
| skipped 호출 지점 | 6 | 전부 `verdict / admission-check`(5) + `attest / admission-check`(1), 0초 |
| step 이름 변경 | 없음 | 5 run 모두 동일한 3개 이름, 내부 22개 이름도 동일 |
| 내부 미귀속 | 21.3 (0.83%) | composite harness 경계 오버헤드 |

**문서 간 불일치 1건(발견)**: `docs/evidence/ci_critical_path_baseline_2026-11-20.md` §1의 run별 `setup family` 열은 821/284/249/306/218이고 합이 **1,878**이다 — `Run ./.` 부분집합만 센 값이다. 같은 문서 §0·§3.2의 총계 2,574와 맞지 않는다. `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json`의 `provisioningFamilySeconds`는 1080/389/367/429/309로 **2,574와 정합**하며, 본 측정값과도 일치한다. 즉 오류는 baseline 마크다운 표에만 있다. 본 문서는 그 표를 정정 대상으로 기록하되, baseline 파일은 수정하지 않는다(범위 밖).

## §6. 최대 phase 내부

### §6.1 `Install system deps (libpcre3)` — 1,542.1s / 40회

| 구간 | 초 | 비중 |
|---|---|---|
| fetch + resolve (step 시작 ~ dpkg 최초 출력) | 1,217.3 | 78.9% |
| unpack + configure (dpkg ~ step 끝) | 324.8 | 21.1% |

40회 중 느린 5건이 **884.8초**이고 전부 run `44521587339`다(4건 failure, 1건은 92초 fetch 후 성공). 나머지 35회 합은 657.3초, 평균 18.8초다.

사고의 정체는 로그에 그대로 남아 있다:

```
E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable
W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble/InRelease  503  Service Unavailable
```

이 step은 `action.yml`의 5단 supply ladder(tier 0 이미 존재 → tier 1 apt → tier 2 pinned release asset → tier 3 공식 미러 → tier 4 explicit failure)를 타므로, 503은 재시도 창 전체가 fetch 구간에 계상된다. **fail-closed 자체는 정상 동작**이며(4건이 실제로 실패로 끝났다), 이 값은 "provisioning이 느리다"가 아니라 "공급원이 죽으면 job이 죽는다"는 관측이다.

### §6.2 `A-layer restore` — 874.5s / 40회 (36 hit)

| 구간 | 초 | 비중 |
|---|---|---|
| 네트워크 (`Cache hit for:` → `Cache Size:`) | 278.6 | 32.6% |
| tar 추출 (`tar -xf` → `Cache restored successfully`) | **574.7** | **67.4%** |

payload는 40회 합 40.16 GB, 복원당 1,004 MB, 실측 처리량 **144 MB/s**다. 즉 복원 비용의 3분의 2는 압축 해제이며, 대역폭을 늘리거나 payload를 캐시에서 빼는 것으로 얻을 수 있는 상한은 278.6초(전체의 10.9%)다.

hit은 36/40이고, miss 4건은 전부 `mint-prepare / prepare`가 **런타임 스코프 키**(`axiom-a-rt-*`)를 요청한 경우다(로그: `Cache not found for input keys: axiom-a-rt-…`). 그 4회에서만 `Install Z3`(1.5–1.7초)와 `Install jq`(0.1–0.3초)가 실행된다. miss의 원인이 키 네임스페이스인지 save 이력인지는 이 측정 범위 밖이며, 판정하려면 해당 키의 save 로그가 필요하다.

`B-layer restore`는 59.4초(median 1.4초)로 사실상 무시 가능하다.

## §7. 무엇이 귀속되지 않는가

| 잔여 | 크기 | 성격 |
|---|---|---|
| composite harness 경계 | 21.3s (0.83%) | 22개 step 경계 마커 880개의 오버헤드. 실행당 ~0.5s. 더 쪼갤 대상이 아니다 |
| 0초 호출 지점 6건 | 0s | `skipped` step. 실행 자체가 없으므로 귀속할 시간이 없다 |
| apt fetch/install 경계 | — | `apt-get -qq`가 `Get:` 행을 출력하지 않아, 경계는 dpkg의 첫 출력(`Preparing to unpack`/`Reading database`)이다. fetch 구간에는 인덱스 해석 시간이 섞여 있다 |
| remote-ref 실행 5건 | 5건 255s 전체 | `[closure] Pinned toolchain`은 `@c021c338`의 액션을 실행한다. 22개 step 이름은 트리 사본과 동일함을 diff로 확인했으나 blob은 다르다(`adee6223` vs `d01432f6`) |

이 표의 잔여를 제외하면 composite span 안에 설명되지 않는 시간은 없다.

## §8. 분해가 지지하는 것 / 지지하지 않는 것

**지지한다**

- composite span은 22개 step으로 **완전히** 설명된다(99.2%). "어딘가에 숨은 지연"은 없다.
- 정상 구간의 최대 비용은 **cache restore**(769.5초)이고, 그 비용의 대부분은 A-layer 복원의 tar 추출(67.4%)이다.
- `Install Nim`/`Lean`/`nimble`은 40회 전부 skipped다 — 네이티브 설치 경로는 이미 정상 구간에서 발화하지 않는다.
- provisioning 비용은 **안정적이지 않다**: run별 304 ~ 1,077초. 단일 run의 공급 사고가 cohort 합계의 34%(884.8/2,574)를 만든다.
- `libpcre3` apt 설치는 **job마다** 실행된다(40/40). GitHub-hosted runner는 job마다 새 VM을 할당하므로 이미지에 없는 패키지는 매번 설치된다.

**지지하지 않는다**

- **캐시를 바꿔야 한다는 결론.** 복원 비용의 2/3가 추출이고, 네트워크 상한은 278.6초(전체 10.9%)다. 캐시 payload 축소·압축 변경·캐시 제거 중 무엇이 이득인지는 이 측정으로 판정할 수 없다. 캐시를 없애면 현재 skipped인 설치 경로(0초)가 되살아나므로, 비교는 **별도 after cohort**가 필요하다.
- **apt 설치를 캐시해야 한다는 결론.** 40회 중 35회가 18.8초이고, 캐시 도입은 restore 비용을 새로 만든다. 순이득은 측정되지 않았다.
- **"provisioning이 critical path의 55.1%"라는 재사용.** 이 비율은 `stepSeconds` 분모에 대한 값이고, composite는 여러 job에서 병렬로 실행된다. runner-seconds 대비로는 33.2 ~ 84.0%다(§1). 어느 쪽도 wall 단축량을 직접 의미하지 않는다.
- **run 44521587339의 값을 대표값으로 쓰는 것.** 이 run은 공급 사고를 포함한다. 정상 상태 대표값은 사고 제외 열이다.
- **composite 밖 비용.** `bin/ax` 빌드·게이트·artifact 업로드는 이 span 밖이며 본 문서가 다루지 않는다.

## §9. 한계

- n=5. p95를 선언하지 않는다. `median`/`p75`는 **실행 40건** 기준이지 run 기준이 아니다.
- 내부 step 경계는 GitHub API 객체가 아니라 **액션 로그 마커**다. 마커를 출력하지 않는 개정에서는 같은 방법으로 분해할 수 없다.
- `duration_ms`는 액션이 보고한 값이며, 같은 step의 `start-action`/`end-action` 마커 타임스탬프 차이와 **0.000–0.003초** 안에서 일치한다(880 레코드 전수 확인, 중앙값 0.001초).
- apt의 fetch/install 경계는 `-qq` 때문에 근사다(§7).
- 5회 실행은 `@c021c338` remote-ref 사본이다. step 이름은 동일하지만 blob이 다르므로, 그 5건의 내부 시간을 트리 사본의 성능으로 일반화하지 않는다.
- 원시 로그·JSON은 커밋하지 않았다. run ID로 재수집 가능하다(§1 명령).

## §10. 참조

- jobs/steps 필드 의미: <https://docs.github.com/en/rest/actions/workflow-jobs> — `steps`는 "Steps in this job."이고, step의 `started_at`은 "The time that the step started, in ISO 8601 format.", `completed_at`은 "The time that the job finished, in ISO 8601 format."(원문 그대로 — GitHub 스키마가 step 항목에도 job 문구를 쓴다)이다. 본 문서의 outer span은 이 두 필드의 차이다.
- 캐시 한도·퇴거: <https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching> — "GitHub will remove any cache entries that have not been accessed in over 7 days. There is no limit on the number of caches you can store, but the total size of all caches in a repository is limited. By default, the limit is 10 GB per repository". A-layer payload가 복원당 1,004 MB이므로 키 1개가 한도의 10%를 쓴다.
- 캐시 hit/복원 의미: 같은 문서 — "When key exactly matches an existing cache, it's called a cache hit, and the action restores the cached files to the path directory." 및 "The cache action first searches for cache hits for key and the cache version in the branch containing the workflow run. If there is no hit, it searches for prefix-matches for key" — 액션이 비-exact 복원을 폐기하는 이유(부분 일치는 hit로 보고되지 않는다)와 일치한다.
- hosted runner 수명: <https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners> — "When the job begins, GitHub automatically provisions a new VM for that job. All steps in the job execute on the VM … When the job has finished, the VM is automatically decommissioned." — `libpcre3`가 job마다 설치되는 이유다.
- 측정 정의: `docs/spec/ci_critical_path_metric.md` §2.4(provisioning family, composite 중첩 step 비노출).