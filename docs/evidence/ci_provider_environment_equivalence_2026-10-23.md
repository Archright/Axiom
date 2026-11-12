# CI Provider Environment Equivalence — GHEC vs Ubicloud (2026-10-23)

> 문서 성격: 실행 증거 기록(docs/evidence — §5 SSOT 표). GHEC↔Ubicloud
> failover가 **검증 동등성**을 보존하는지에 대한 실측 근거다. 공급자를
> 바꿔도 필수 검증의 의미가 달라지지 않는다는 주장은 이 문서의 관측으로만
> 지지된다. quirk 본문: `docs/spec/ci_provider_failover_quirks.md`.
>
> 방법: 11개 잡 로그를 `GET /repos/Archright/Axiom/actions/jobs/<id>/logs`
> (전건 HTTP 200)로 수집해 비교했다. 모든 행은 run id + job id를 인용한다.
> 표기: **[measured]** = 로그에서 직접 관측, **[not-observable]** = 양쪽 모두
> 출력하지 않아 비교 불가, **[derived]** = 관측에서 도출.

## 1. 비교에 사용한 잡

**GHEC 측 (전건 success, 03:10Z 제공량 차단 이전)**

| Run | Workflow | Job id | Label | Event |
|---|---|---|---|---|
| 39887775242 | landing-integrity | 120199884046 `trust-surface-codeowners` | `ubuntu-latest` | merge_group |
| 39887775242 | landing-integrity | 120199884270 `trusted-writer-set-pairing` | `ubuntu-latest` | merge_group |
| 39887775242 | landing-integrity | 120199884338 `merge-admission-sanity` | `ubuntu-latest` | merge_group |
| 39887775254 | debt-registry-gate | 120199884195 | `ubuntu-24.04` | merge_group |
| 39887775240 | probe-merge-queue | 120199884331 `probe-capture` | `ubuntu-latest` | merge_group |
| 39887775290 | generation-acceptance | 120199884328 | `ubuntu-24.04` | merge_group |
| 39887775247 | bsec-integrity | 120199883974 | `ubuntu-24.04` | merge_group |

**Ubicloud 측 (전건 success, 전환 이후; 전 잡 `labels=["ubicloud-standard-2"]`,
`runner_group_id=1`, 로그 헤더 "Runner group name: 'Default'")**

| Run | Workflow | Job id | Event |
|---|---|---|---|
| 39916148648 | generation-acceptance | 120290055440 | merge_group |
| 39916148551 | debt-registry-gate | 120290054424 | merge_group |
| 39916148558 | bsec-integrity | 120290054346 | merge_group |
| 39933629685 | ci-provider-router | 120347721787 `router` | workflow_run |

## 2. 비교표

| # | 사실 | GHEC 실측 | Ubicloud 실측 | 판정 |
|---|---|---|---|---|
| 1 | 러너 이미지 계열 | `Image: ubuntu-24.04` — 7잡 전부 (`ubuntu-latest` 라벨 포함) | `Image: ubuntu-24.04` — 4잡 전부 | **일치** |
| 2 | 이미지 버전 | `20261012.334.1`, release tag `actions/runner-images ubuntu24/20261012.334` | `20261021.1.0`, release tag `ubicloud/runner-images ubuntu24/20261021.1` | **차이** — fork + 9일 최신 빌드 |
| 3 | OS 릴리스 | Ubuntu / 24.04.5 / LTS | Ubuntu / 24.04.5 / LTS | **일치** |
| 4 | `ImageOS`/`ImageVersion` env | 부재 (2026-10-01 리포지토리 정책으로 제거, 주석만 잔존) | 동일하게 부재 | **[not-observable]** (양쪽 설계) |
| 5 | gcc 배너 fingerprint | `gcc_fp=8497f84b2b8334c4` | `gccFp=8497f84b2b8334c4` | **일치** (64-bit 절단 지문) |
| 6 | glibc fingerprint | `glibc_fp=e881beabc91bfbd3` | `glibcFp=e881beabc91bfbd3` | **일치** (절단 지문) |
| 7 | Nim | `Nim Compiler Version 2.2.10 [Linux: amd64]` | 바이트 동일 | **일치** |
| 8 | Lean / Lake | `4.33.0`, commit `d8b1897`, `Lake version 5.0.0-src+d8b1897`, `~/.elan/toolchains/leanprover--lean4---v4.33.0` | 버전·commit·Lake 라인·툴체인 경로 동일 | **일치** |
| 9 | z3 | `Z3 version 4.13.3 - 64 bit` | 동일 | **일치** |
| 10 | jq | `jq-1.7.1` | 툴체인 잡 `jq-1.7.1` / **router 잡 `jq-1.7`** | **일치(툴체인)** + **Ubicloud 내부 드리프트(router VM)** |
| 11 | gh CLI | 어떤 GHEC 잡도 출력하지 않음 | `gh version 2.102.1 (2026-10-20)` | **[not-observable]** (GHEC 측) |
| 12 | `uname -a` / 커널 | 미실행 | 미실행 (양쪽 x86-64는 간접 증거) | **[not-observable]** |
| 13 | 러너 에이전트 | `'2.338.0'` | `2.338.0` | **일치** |
| 14 | 러너 이름/라벨 | `GitHub Actions 10000347xx`, Azure westus, provisioner | `Runner name: 'gr…'`, `Label: ubicloud-standard-2`, VM Family standard, Image `github-ubuntu-2404`, FSN1-DC21/24 | **플랫폼 차이(설계대로)** |
| 15 | A키 (`gcc_fp`+`glibc_fp`+script hash) | `axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-3618d290…` | **바이트 동일** | **일치** |
| 16 | B키 / b-identity | `b-identity=7a978a5efc73971cd128a55545ba38488eb51619` | 바이트 동일 | **일치** (probe-tree만 상이 — 다른 머지 커밋) |
| 17 | A-레이어 검증 | `OK — nim=2.2.10 lean=4.33.0 z3=4.13.3 gccFp=… glibcFp=… key=axiom-a-Linux-…` | **바이트 동일 OK 라인** | **일치** |
| 18 | A-레이어 복원 | exact key 복원 1,067,030,088 B | **같은 exact key** 복원 1,166,915,227 B, 복원 후 verify 통과 | **키 일치** (페이로드 크기는 동일 키의 후행 스냅샷) |
| 19 | bsec-integrity 판정 | 215 PASS / 0 FAIL | 215 PASS / 0 FAIL, GHEC 대비 diff 공집합 | **일치** |
| 20 | generation-acceptance 동작 | 정규화 로그 diff 88줄 — 전부 인프라 헤더·temp UUID·커밋 provenance | (동일 비교) | **일치** (step 출력 차이 0) |

## 3. 로그가 노출하지 않는 사실 (11개 로그 전수 grep으로 부재 확인)

`ImageOS`/`ImageVersion` 값, `/etc/os-release` 원문, gcc/ldd 배너 원문(지문만),
`uname -a`/커널, `elan --version`, GHEC 측 gh CLI 버전, Nim build metadata
(`Compiled at`/git hash), CPU/메모리/디스크/컨테이너 런타임.

## 4. 판정

- **툴체인 동등성: 성립.** Nim 2.2.10 `[Linux: amd64]`, Lean 4.33.0(동일 commit
  `d8b1897`), Lake `5.0.0-src+d8b1897`, z3 4.13.3, gcc/glibc 절단 지문
  (`8497f84b2b8334c4` / `e881beabc91bfbd3`)가 두 플릿에서 바이트 동일하다.
- **가장 강한 단일 증거:** 양쪽이 **같은 A-레이어 캐시 키**
  (`axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-3618d290…`)를 계산했고,
  Ubicloud 잡이 **그 exact key에서 복원**해 `AXIOM_CACHE_A_VERIFY`를 통과했다 —
  하나의 툴체인 캐시 엔트리가 두 플랫폼을 모두 서비스한다.
- **이미지 버전 차이는 실재하나 이미지 계층에 국한된다.** GHEC은
  `actions/runner-images ubuntu24/20261012.334`(2026-10-12 빌드, Azure westus),
  Ubicloud는 fork `ubicloud/runner-images ubuntu24/20261021.1`. 이 저장소가
  의미 있게 요구하는 동등성(gcc/glibc 바이트, Nim/Lean/z3, 스크립트 identity)은
  지문으로 고정되어 일치하고, OS 릴리스와 러너 에이전트 버전도 동일하다.
- **실재하는 caveat 1건:** Ubicloud 플릿은 선언된 이미지 버전 내에서도 완전히
  균질하지 않다 — router 잡(39933629685, 09:41Z, FSN1-DC24)은 `jq-1.7`,
  debt-registry-gate(39916148551, 07:11Z, FSN1-DC21, 같은 선언 이미지
  `20261021.1.0`)는 `jq-1.7.1`(GHEC와 동일)을 보고했다. jq 마이너 버전에
  의존하는 판정이 생기면 `setup-axiom-toolchain`이 gcc/glibc에 하는 것과 같은
  방식으로 지문 고정이 필요하다. 현재 게이트의 jq 사용은 버전 차이에 민감하지
  않다(파서 수준 기능만 사용).
- **failover 판정에 미치는 영향:** 없음. 검증 동등성은 "같은 판정이 나온다"는
  관측(§2 #19·#20)과 "같은 툴체인 바이트"라는 관측(§2 #7·#8·#9·#15·#17)으로
  지지된다. 이미지 태그 동일성이 아니라 이 두 관측이 근거다.

## 수정 (2026-10-24) — 캐시 엔트리 공유 판정 정정: "하나의 엔트리"는 관측되지 않았다

> 위 원문(2026-10-23 실측)은 시점 기록으로 그대로 유지된다. 본 절은 이후 확정된
> 사실을 덧붙이는 것이며 원문을 개정하지 않는다 — `docs/evidence/mg_red_forensics_2026-10-14.md`
> «수정 (2026-10-15)»(PR #830 상태 정정)과 같은 추기 스타일이다. 정정 대상은 아래
> 한 문장으로 국한되며, §4의 툴체인 동등성·환경 동등성 판정과 §2 #15·#16(키·identity
> 일치)은 그대로 유효하다.

**정정 대상 문장(73–76행)**: "Ubicloud 잡이 **그 exact key에서 복원**해
`AXIOM_CACHE_A_VERIFY`를 통과했다 — 하나의 툴체인 캐시 엔트리가 두 플랫폼을 모두
서비스한다." 같은 키 문자열을 계산·복원했다는 관측 자체는 사실이지만, 그것이
**하나의 엔트리**를 서비스한다는 결론은 관측을 초과했다. 본 절은 이 결론을 폐기한다.

### 1. 키 공식은 플랫폼 간 동일하나, 저장된 엔트리는 그렇지 않다 [measured]

- REST 캐시 API 전건에서 동일 키 문자열
  `axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-3618d290e19834f152bf534ee3083e09891b9e66`이
  4개 ref에 **서로 다른 4개 크기**로 존재한다: 1,066,997,403 B
  (`gh-readonly-queue/main/pr-987-…`), 1,067,030,088 B(`refs/heads/main`),
  1,067,258,068 B(`refs/pull/989/merge`), 1,186,863,543 B(`refs/pull/987/merge`).
  4엔트리의 `version` 해시까지 모두 동일(`3b1a2d6f…`) — (key, version) 주소가 같은
  GitHub 스토어 내부에서도 페이로드는 ref별로 분기·상이하다.
- Ubicloud 런 40094698551(ci-cache-publisher, 잡 120874391856)이 같은 exact key에서
  복원한 페이로드는 **1,166,915,227 B**(로그 376·380행)로 위 4개 중 어느 것과도
  불일치하며, §2 #18이 2026-10-23에 기록한 Ubicloud 복원 크기와 동일하다 — 스토어 내
  엔트리는 자기 스토어 안에서는 안정 재사용된다.
- Ubicloud가 복원한 B키 `axiom-b-88a5f093c6b1b6b4…`(90,464,455 B, 같은 잡 461·464행)는
  캐시 API 전건에 **부재**한다(부분 문자열 `88a5f093` 검색까지 0건).
- 결론: 키는 결정론적 공식의 산출(§2 #15·#16 그대로)이고 **페이로드는 저장소·ref별
  스냅샷**이다. §2 #18의 "페이로드 크기는 동일 키의 후행 스냅샷" 주석도 같은 전제
  위에서는 정확하지 않다 — 크기 불일치는 스냅샷 시차가 아니라 **스토어 자체가
  다르다**는 신호였다. (키 일치 판정 자체는 유지된다.)

### 2. 두 개의 분리된 저장소가 존재한다 [measured]

- **GitHub 캐시 서비스**(REST API가 열거하는 스토어)는 2026-10-24 재관측 기준
  244엔트리 10,729,873,214 B(9.993 GiB)로 동결 상태다: 최신 생성
  `2026-10-23T02:23:16.018571Z`, 최종 접근 `2026-10-23T02:25:34.160453Z`, 그 이후
  생성·접근 0건(엄격 비교).
- **러너 기판 캐시**(Ubicloud 호스트 잡에서 `actions/cache`가 실제로 읽고 쓰는
  스토어)는 GitHub API 어느 것으로도 열거되지 않는다. 라이브 관측: 2026-10-24
  12:47:16Z Ubicloud 잡(mint-prepare/prepare, 120876296634)의 a-rt 캐시 저장
  (14,112,450 B, 로그 1004–1006행)은 20분 뒤 API 재관측(13:08Z)에도 미반영됐다
  (244건·최신 생성 불변). 같은 키 문자열의 엔트리가 GitHub 스토어에는 존재하나
  (pr-1051 queue ref, 14,112,439 B, 2026-10-23 생성), 잡은 `Cache not found`(668행)
  였고 47초 뒤 형제 잡(mint-publish/publish, 120876514546)이 방금 저장한 것을
  복원했다(375행) — 두 스토어의 행적이 갈라진다. 보태면, 12:38:14Z에 같은 exact
  A키를 복원한 ci-cache-publisher 잡도 GitHub 스토어의 main-scoped A키 엔트리
  (id 9232278806)의 `last_accessed_at`(2026-10-23T02:24:33Z)을 갱신하지 않았다.
- 정정 노트: 본 사건 최초 조사에서 "vendor 공개 문서 부재(404)"로 기록된 것과 달리,
  2026-10-24 기준 Ubicloud는 `https://www.ubicloud.com/docs/github-actions-integration/ubicloud-cache`에서
  **Ubicloud Cache(transparent cache, 기본 활성)**를 문서화한다 — 러너 근접 저장소가
  GitHub Actions 캐시 API를 대행한다는 서술과 리포지토리당 30 GB(프리미엄 100 GB),
  최오래된 우선 축출·7일 무접근 제거 정책을 포함한다. 다만 **열거·조회 API는 문서화하지
  않으므로** "GitHub API로 열거 불가"라는 위 관측은 변하지 않는다.

### 3. 운영 결과: 교차 플랫폼 웜 이전은 존재하지 않는다 [measured → derived]

- 각 플랫폼의 캐시는 자기 스토어 안에서만 웜하다. Ubicloud 시대의 저장은 GitHub
  스토어에 착지하지 않으므로(위 2.의 라이브 관측) GHEC 복귀 창은 Ubicloud 시대 키에
  대해 콜드에서 시작하고, 그 역도 성립한다 — Ubicloud 잡의 복원은 GitHub 스토어의
  접근 시각을 건드리지 않았고(위 2.), GitHub 스토어에 존재하지 않는 B키를 복원했다.
- 이것은 **성능 속성**이며 검증을 약화시키지 않는다. J3 계약 — "cache is
  acceleration, never evidence"
  (`docs/audit/ci_semantic_reduction_audit_2026-09-27.md:204`)이며, 그 근거 선언은
  `.github/actions/setup-axiom-toolchain/action.yml:4`("Correctness contract — NOT
  hit-rate")다. 같은 취지의 `docs/spec/verification_dag_contract.md:67`·
  `docs/spec/github_delegation_residuals.md:7-8`(캐시는 가속일 뿐 증거가 아니며 판정
  입력도 아니다)에 따라 MISS 경로는 fail-closed 콜드 빌드로 회귀한다.

### 4. 동결된 GitHub 스토어의 처분 [measured + derived]

- 스코프 분리(2026-10-24 전건 재측정): `refs/heads/main` 27엔트리 4,388,694,194 B
  (4.087 GiB), 비-main 217엔트리 6,341,179,020 B(5.906 GiB) — 후자는 210종의
  `refs/pull/N/merge`·`gh-readonly-queue/main/pr-N-…` ref에 분산되며, 열려 있는 PR의
  최소 번호가 1086이므로 이 ref들은 이미 종료된 PR·큐에 스코프돼 있다.
- restore-scope 규칙상 캐시는 key·version·branch로 스코프되고 기본 브랜치 캐시만 타
  브랜치에 공개된다(`actions/cache` README 111–113행; Ubicloud의 cache branch
  protection 기본값도 GitHub 기본 동일이라고 문서화돼 있다). 따라서 217엔트리
  5.906 GiB는 어떤 현재 ref에서도 복원 불가이고, main-scoped 27엔트리 4.087 GiB는
  GHEC 복귀 시에만 가치를 회복한다.
- 7일 무접근 축출(`actions/cache` README 268행 "Caches that are not accessed within
  the last week will also be evicted")에 따라, 최종 접근 `2026-10-23T02:25:34Z` +
  7일 — **약 2026-10-30 전후** 스토어 전체가 자연 소멸한다. 어떤 조치도 필요하지
  않다. [derived]

### 5. 관측 불가 항목 [not-observable]

Ubicloud 스토어의 재고·TTL·축출 실측·할당량 사용률·레인별 히트율은 **어떤 API로도
노출되지 않는다** — vendor 문서는 정책값(30 GB, 최오래된 우선, 7일 무접근)을 서술할
뿐 이 리포지토리의 실측 열거 수단이 아니다. 현재 유일한 신호는 런별 로그 라인이다
(`Cache not found` / `Cache saved with key` / `Cache restored from key` + `Cache Size`).

## 재현 명령

```bash
# 러너 맵(전환 상태·사유)
gh api repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP --jq .value

# GitHub 캐시 스토어 전건 집계(총량·동결 경계·스코프 분리)
gh api 'repos/Archright/Axiom/actions/caches?per_page=100' --paginate > /tmp/caches.json
jq -s '[.[].actions_caches[]] | {count: length, total_bytes: (map(.size_in_bytes)|add),
  newest_created: (map(.created_at)|max), last_accessed: (map(.last_accessed_at)|max),
  main_scoped: ([.[]|select(.ref=="refs/heads/main")]|{count:length,total_bytes:(map(.size_in_bytes)|add)}),
  non_main_scoped: ([.[]|select(.ref!="refs/heads/main")]|{count:length,total_bytes:(map(.size_in_bytes)|add)})}' /tmp/caches.json

# 동일 A키 엔트리의 ref별 크기·version 분기
jq -s '[.[].actions_caches[] | select(.key=="axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-3618d290e19834f152bf534ee3083e09891b9e66") | {ref,size_in_bytes,version,created_at,last_accessed_at}]' /tmp/caches.json

# Ubicloud 복원 B키의 GitHub 스토어 부재(0줄이 정답)
jq -s '[.[].actions_caches[] | select(.key|contains("88a5f093"))]' /tmp/caches.json

# 런 메타데이터(Ubicloud 라벨 확인: jobs[].labels)
gh api repos/Archright/Axiom/actions/runs/40094087660 --jq '{name,event,head_branch,conclusion}'
gh api repos/Archright/Axiom/actions/runs/40094698551 --jq '{name,event,head_branch,conclusion}'

# 잡 로그의 캐시 라인(--allow-escape-sequences 필수 — 로그 원문에 터미널 이스케이프 포함)
gh api repos/Archright/Axiom/actions/jobs/120876296634/logs --allow-escape-sequences | grep -nE 'Cache (not found|saved|restored)|Cache Size'   # mint-prepare/prepare — 668·700·1004–1006행
gh api repos/Archright/Axiom/actions/jobs/120876514546/logs --allow-escape-sequences | grep -nE 'Cache (not found|saved|restored)|Cache Size'   # mint-publish/publish — 372–375·467행
gh api repos/Archright/Axiom/actions/jobs/120874391856/logs --allow-escape-sequences | grep -nE 'Cache (not found|saved|restored)|Cache Size'   # ci-cache-publisher/publish — 376·380·461·464행

# 복원이 GitHub 스토어 접근 시각을 갱신하지 않음을 재확인(12:38Z 복원 후에도 2026-10-23T02:24:33Z 유지)
jq -s '[.[].actions_caches[] | select(.id==9232278806) | {ref,last_accessed_at}]' /tmp/caches.json

# vendor 문서 존재(200 — 404가 아님; 열거 API 부재는 페이지 본문으로 확인)
curl -sS -o /dev/null -w '%{http_code}\n' https://www.ubicloud.com/docs/github-actions-integration/ubicloud-cache

# 축출·스코프 규칙 원문(actions/cache README — 268행 10GB 상한·7일 무접근 축출, 111–113행 스코프)
curl -sSL https://raw.githubusercontent.com/actions/cache/main/README.md | sed -n '111,113p;268,268p'
```
