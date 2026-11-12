# 중복 계산 전수 조사 — 7일 운영 창 관측 슬라이스 (Slice 2)

- 측정일: 2026-10-09 (KST 기준; UTC 로그 타임스탬프)
- 관측 창: **2026-10-02T00:44:42Z ~ 2026-10-09T08:30:23Z** (runs `created` 기준 7일 — 퇴출 클래스(7일 LRU ∧ 10GB) 흡수를 위한 최소 창)
- 성격: **순수 계측 (census)** — 레포 코드 변경 0, enforcement/게이트 추가 0
- 방법론 선례: `docs/evidence/ci_structural_duplicate_census_2026-09-30.md` §5(전량분류표)·§7(UNKNOWN)·§8(출처표); quirks 인용: `docs/spec/gh_run_observation_quirks.md` Q2(큐 stacking)·Q3(ANSI escape)
- 목적: "동일 canonical identity의 콜드 계산"을 실제 운영 런에서 전량 수집·분류하고, 임계 규칙("퇴출·설계된 무효화·최초 계산으로 설명되지 않는 콜드가 창 내 ≥1회?")으로 피할 수 있는 중복의 잔존 여부를 판정한다. "2회 콜드 = 위반" 집행은 본 문서의 대상이 아니다(정당 재계산 클래스 실재).

---

## 1. 수집 명령과 창 (전부 실제 운영 런, gh api 읽기 전용)

```bash
# R1. 런 전수 — 1000건 페이지 한계로 조기 종료 확인 후 일자별 분할 재수집 (누락 방지)
gh api "repos/Archright/Axiom/actions/runs?created=>=2026-10-02T00:00:00Z&per_page=100" --paginate
gh api "repos/Archright/Axiom/actions/runs?created=2026-10-0D..2026-10-0D&per_page=100" --paginate   # D=02..10

# R2. 잡 메타 — 대상 런 1,045건 전부
gh api repos/Archright/Axiom/actions/runs/{id}/jobs?per_page=100 --paginate

# R3. 잡 로그 — 캐시·컴파일 관련 잡 3,113건 (ANSI strip 후 이벤트 grep)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/{id}/logs | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E 'AXIOM_CACHE_KEYGEN|Cache (not found|hit for|restored from|saved with)|AXIOM_CACHE_B_(VERIFY|PROBE)|\[publish(-skip|-fail)?\]|RUN_ID:|AXIOM_S5'
#   + select 잡 499건 2차 패스: grep -E '"mode":|"ciBootstrap":|decision envelope|AXIOM_S5|SHADOW MODE'
#   + 빈 로그 502건 재수집 검증(수집 결함 시정 — §7)

# R4. 캐시 상태 스냅샷
gh api "repos/Archright/Axiom/actions/caches?per_page=100" --paginate
gh api repos/Archright/Axiom/actions/cache/usage ; gh api repos/Archright/Axiom/actions/cache/storage-limit
```

- HTTP 실패(404 포함) **0건**. 로그 3,113 + 499 + 502회 재수집.
- 조인 키: `AXIOM_CACHE_KEYGEN: b-identity=… b-key=…` 실행 출력 라인 (셸 소스 `echo "…"` 라인은 배제).

## 2. 볼륨 실측

| 항목 | 값 |
|---|---|
| 창 내 전체 런 (전 워크플로, 일자별 합) | **2,072** (d02:82 · d03:94 · d04:295 · d05:152 · d06:228 · d07:446 · d08:429 · d09:346) |
| 분류 대상 런 | **1,045** = admission-gate 499 (pull_request 287 + merge_group 212) + ci-cache-publisher 546 |
| 대상 런 conclusion | success 835 · skipped 128 · failure 74 · cancelled 6 · null(진행 중) 2 |
| 총 잡 | 7,823 |
| 컴파일 수행 잡 (실행 기준) | **801** — attest/build-base-artifacts 405 · gateway/ci-bootstrap 302 · admission/build-base-artifacts 94 |
| 컴파일 보유 잡 중 skipped | 599 (verdict lane build-base-artifacts 402 **전량 skip** 포함 — verdict lane은 창 내 0 컴파일) |
| run_attempt ≥ 2 런 | 36 (attempt 2 ×20+3, attempt 3 ×10+1, attempt 4 ×2) |
| 퍼블리셔 publish 잡 | 417 success + 128 skipped (job-if: `ci-cache-publisher.yml:160` `workflow_run.conclusion == 'success'`) |
| 퍼블리셔 B-key 저장 (실행 로그 `Cache saved with key: axiom-b-…`) | **232** — 단일 writer = 퍼블리셔 publish 잡 (창 내 다른 writer 0) |
| select envelope 모드 | none 182 · full 207 · selected 109 (498 런 확인) |
| 라이브 캐시 스냅샷 | 206개 · **9,908,295,314 bytes** / 상한 `max_cache_size_gb: 10` |
| 라이브 키 구성 | axiom-b 81 (**전부 `refs/heads/main` 스코프**) · axiom-a-rt 122 · axiom-a 3 |
| b-key 조인 성공 | **801 / 801 (100%)** — 미조인 0 |
| 관측 b-key 종수 | 290 (복수 발생 키 177) |
| a-key 이미지 fp 변이 | 4세대 (f68ce8af ×494 · ddc40ad6 ×158 · 375aa318 ×45 · 62f1b976 ×1) |

- 런/잡/로그 메타는 REST만 사용 (org ruleset 런은 `gh run view` 404 — census §8 각주와 동일).
- identity 등식: **동일 b-key = 동일 build identity = (동일 트리 ∧ 동일 레시피 ∧ 동일 toolchain fp)** — b-key = `axiom-b-<40hex tree>-<64hex recipe+fp>`.

## 3. 11유형 전량 분류표 (창 내 표본 기준 — 801/801 배정)

분류는 각 컴파일 이벤트(=실행된 컴파일 잡 1개)에 대해 ① 로그의 B-캐시 귀결(HIT/MISS) ② 같은 b-key의 창 내 저장 이력 ③ 소비 시점 전 저장 존재 여부 ④ 런 conclusion·attempt ⑤ 소속 런의 퍼블리셔 판정([publish]/[publish-skip]/[publish-fail]) ⑥ select envelope mode를 근거로 배정했다.

| 유형 | 정의 | 건수 | 판정 성격 |
|---|---|---:|---|
| 1 최초 계산 | 창 내 해당 identity 최초 발생 (저장은 런 완료 후 퍼블리셔가 수행) | **185** | 정당 (설명됨) |
| 2 퇴출 후 cold | 소비 시점 전 동일 키 저장 존재 ∧ 소비 MISS (7일 LRU ∧ 10GB 압력) | **0*** | 정당 (설명됨) — *§7 도구 결함 참조 |
| 3 미게시 | 소비 시점에 시드 부재 — 퍼블리셔 가드 skip 또는 publish 시점 선행(consume precedes publish) | **140** | 설계 가드/구조적 순서 (설명됨) |
| 4 키·레시피 불일치 | 동일 identity · 상이 suffix (레시피·지문 드리프트 = 설계된 일괄 무효화) | **0** | — (부분 검증 기준 suffix 변이 관측 없음) |
| 5 실패·재시도·cancel-rerun | red gate (publisher job-if silent skip) 또는 attempt 재실행 | **74** | 정당 (설명됨) |
| 6 게시 실패 | `[publish-fail]` | **0** | — (표본 0 — 계획 §교정2 예측과 일치) |
| 7 방어적 폐기 | `AXIOM_CACHE_B_VERIFY: FAIL/DISCARDED` | **0** | — (실행된 VERIFY 842건 전부 RESULT OK) |
| 8 큐 stacking identity 변동 (Q2) | merge-queue speculative stacking으로 tree(G_n)≠tree(merge(main,H)) — Q2 class A | **1** | 정당 (설명됨) |
| 9 mode=none 발화 자체 부재 | 모드 게이트로 퍼블리셔 발화 자체가 없는 콜드 | **0** | — (mode=none 런의 퍼블리셔는 발화 후 in-step skip 라인을 남김 → 유형 3으로 귀속) |
| 10 HIT 후 warm 재빌드 | 복원 성공 ∧ 컴파일 재실행 (J3 mtime 바닥 — S5 build-skip 별도 슬라이스) | **400** | 콜드 아님 (HIT) |
| 11 version(path) 불일치 | 라이브·접근 가능 키가 소비 시점 전 생성됐는데 MISS — actions/cache version 원인 추정 | **0*** | — *§7 도구 결함 참조 |
| UNKNOWN | 근거 부족 | **1** | §6 |

- **합계 801** (1:185 · 3:140 · 5:74 · 8:1 · 10:400 · UNKNOWN:1). 미배정 0.
- 유형 3 세부 (140건): `(no skip line)` 26 · mode=none gate 13 · base key exists 7 · lane key exists 2 · admission-check-base-artifacts absent 4 · `tree(build_sha)≠tree(head)` ahead-invariant 불등식 ~88.
- 유형 5 세부 (74건): run conclusion failure 49 · cancelled 7 · success(재시도 attempt≥2) 18.
- HIT 검증 강도: 실행된 `AXIOM_CACHE_B_VERIFY: RESULT OK` 842건, `AXIOM_CACHE_B_PROBE: OK` (bin/ax 285 · gate_hook 243 · precompile_gates 243 · install_ax_cas 243) — 복원 페이로드 digest 검증 통과가 HIT 400건의 전제.
- B 캐시 스코프: 라이브 axiom-b 81건 전부 `refs/heads/main` — 퍼블리셔(main 브랜치 실행) 단일 writer 구조상 ref 스코프 불일치 콜드는 구조적으로 발생 불가 (§2 표).

### 3.1 대표 근거 라인 (원문 발췌, ANSI strip 후)

```text
AXIOM_CACHE_KEYGEN: b-identity=847b49b0b0f3e3e28fa91fed133f36d6ddd81322 b-key=axiom-b-847b49b0…-6b32c4d0…
Cache not found for input keys: axiom-a-…                      # A(toolchain) MISS — 유형 1 전제
Cache restored from key: axiom-b-af14220e…-38ee060a…           # 유형 10 전제
AXIOM_CACHE_B_PROBE: OK — restored bin/ax embedded BuildSourceHash…
[publish-skip] ci-bootstrap-artifacts absent (mode=none gate — nothing built, nothing to publish; residuals R6)
[publish-skip] base key exists
[publish-skip] tree(build_sha)=5c985f03… != tree(head_sha)=…    # ahead-invariant 불등식
[publish-skip] manifest.txt missing after download
RUN_ID: 36948756972                                            # 퍼블리셔→gate 런 링크
  "mode": "none"                                                # select decision envelope
  "ciBootstrap": false
```

- 유형 8 사건 (1건): PR `docs/venue-split-acceptance` head `fe6eebb29` — PR-phase lane 키 `axiom-b-d6e8c8e8…` (잡 113677337111) vs 이후 동일 head의 키 `axiom-b-3fff2284…` (잡 113678966616), suffix(레시피+fp `6c412f1e…`) 동일 · identity 상이 = Q2 speculative stacking. `gh_run_observation_quirks.md` Q2 실측(2026-10-08, PR #603)과 동일 패턴.

## 4. identity 재계산 밀도 (b-key별 발생 — 상위 구조)

- 290개 관측 b-key 중 **177개가 복수 발생**. 전형 패턴: PR-phase MISS(1회) → 같은 창 내 후속 merge_group 또는 다음 사이클 base에서 재등장.
- 복수 발생 키의 온도 흐름: 첫 발생 MISS(미시딩) → 퍼블리셔 저장(232건) → 이후 발생 HIT. HIT 400건은 모두 선행 저장의 소비 성공이다.
- 창 내 구조 요약: **"첫 컴파일은 무조건 콜드(저장 주체가 소비자보다 앞서 존재하지 않음) + 이후 HIT"가 지배 패턴**. 동일 키가 "저장 존재 ∧ MISS"로 관측된 사례는 도구 기준 0건(§7 한계).

## 5. UNKNOWN 목록

1. **잡 113737189540 / 런 37904763970** (gateway/ci-bootstrap, 2026-10-09T08:29:48Z, MISS, mode=full) — 창 종료 스냅샷 시점에 런이 **진행 중**(conclusion 공란)이라 퍼블리셔 판정이 아직 발화하지 않았다. 창 경계 인공물.
2. **창 이전 시딩의 존재 여부**: 퇴출된 키의 이력은 어떤 API로도 관측 불가(census §7.1과 동일 한계). 창 시작 전 저장→퇴출된 시드 위의 MISS는 이론상 존재 가능하나 관측 근거 없음.
3. **multi-attempt 런의 이전 attempt 컴파일**: jobs API가 최신 attempt만 반환 — 36개 재시도 런의 이전 attempt 컴파일은 미관측(과소 계수).
4. **동일 identity·상이 suffix(유형 4) 전수 대조**: 부분 검증 시점(259 identity)에서 suffix 변이 0; 최종 290 keys 전수 대조는 이터레이션 금지 지시로 미실시.

## 6. 임계 판정

> 규칙: **"퇴출·설계된 무효화·최초 계산으로 설명되지 않는 콜드가 창 내 1회 이상인가?"**

- **판정: 아니오(NO) — 관측된 콜드 401건 전부가 설명 클래스(최초 계산 185 · 미게시 가드/순서 140 · 실패·재시도 74 · 큐 stacking 1)로 귀속됐다. UNKNOWN 1건은 창 경계 진행 중 런이다.** → **enforcement 불필요 방향 확정** (창 내 표본 기준). 좁은 예방 슬라이스 착수안은 불요.
- **불확실성 명시 (기록 의무)**: 유형 2/11의 0은 "부재 입증"이 아니라 **"도구 미검출"**이다. 유형 3의 `(no skip line)` 서브클래스 26건(창 내 콜드의 3.2%)은 소비-저장 시점 순서 검증의 파서 결함(§7)으로 ordering-gap과 잠재 version 불일치를 구분하지 못했다. 최악의 경우(26건 전부가 미설명 잔존)라도 판정은 조건부 YES로 뒤집힐 수 있다 — 단, census(2026-09-30)의 "base 키 무시딩 구조" 실측과 본 창의 232건 단일-writer 저장 흐름은 ordering-gap 지배를 지지한다. 두 가설의 분리는 후속 계측 명세(§7)로만 가능하며, 결정 권한은 Owner에 있다.
- 유형 10 (400건, HIT 후 재컴파일)은 콜드가 아니며 J3 mtime 바닥 문제다 — S5 build-skip 별도 슬라이스의 대상일 뿐, 본 판정과 무관.

## 7. 측정 한계와 후속 계측 명세 (순수 계측 — 게이트 아님)

| # | 갭 | 원인 (실측) | 필요한 로그/API 필드 |
|---|---|---|---|
| 1 | 저장-소비 시점 정밀 비교 실패 | ISO 타임스탬프 소수부 **7자리**(예: `.4893471Z`)가 6자리 `%f` 파서를 통과하지 못해 시점 비교 분기가 미작동 — 유형 2/11 검출 경로 무효화 | 파서 교정(7자리 fraction 지원) 또는 사전식 타임스탬프 비교 — 기존 수집 데이터로 재분석 가능 |
| 2 | 퍼블리셔 job-if silent skip 사유 부재 | `ci-cache-publisher.yml:160` job-if가 비성공 게이트를 로그 0줄로 skip → 유형 5/9 구분이 런 conclusion에 의존 | publisher가 skip 시 `workflow_run.conclusion`/`path`를 구조 라인으로 출력 |
| 3 | 소비자 측 cache version 미관측 | actions/cache가 resolved version을 로그에 남기지 않음 → 유형 11 직접 확인 불가 | 복원 단계에서 resolved key+version 로깅 |
| 4 | `[publish-fail]` 표본 0 | 창 내 게시 실패 미발생 | — (관측 지속) |
| 5 | 이전 attempt 컴파일 미관측 | jobs API latest-attempt 필터 | runs/{id}/jobs?filter=all 재시도 런 수집 |
| 6 | 런 전수 페이지 1000건 한계 | `--paginate` 빈 페이지 조기 종료 | 일자별 분할 쿼리(본 조사에서 시정 완료) |

## 8. 출처표

| 데이터 | 출처 (2026-10-09 수집) | 상태 |
|---|---|---|
| 런 전수/메타 | `gh api repos/Archright/Axiom/actions/runs?created=…` (일자별 9-쿼리 + 전역 1-쿼리) | 실측 ✓ (2,072런) |
| 잡 메타 7,823 | `gh api …/runs/{id}/jobs?per_page=100` × 1,045 런 | 실측 ✓ (실패 0) |
| 컴파일·캐시 이벤트 라인 | `gh api --allow-escape-sequences …/jobs/{id}/logs` → ANSI strip → grep (3,113+502) | 실측 ✓ |
| select envelope | 동일 경로 2차 패스 (499잡, `"mode":`/`"ciBootstrap":`) | 실측 ✓ |
| 캐시 스냅샷/상한 | `…/actions/caches?per_page=100` × 3페이지 + `cache/usage` + `cache/storage-limit` | 실측 ✓ (206개, 9,908,295,314B / 10GB) |
| 퍼블리셔 판정 | publisher 잡 로그 `[publish]`/`[publish-skip]`/`RUN_ID:` 실행 라인 (417잡) | 실측 ✓ |
| 유령 라인 배제 | 셸 소스(`echo "`, `printf`, `print(`, `;;` 등 마커) 포함 라인 배제 규칙 | 실측 ✓ (§3.1 발췌 라인은 실행 출력만) |
| Q2 패턴 근거 | `docs/spec/gh_run_observation_quirks.md` Q2 + 본 창 유형 8 사건 | 실측 ✓ |
| 방법론 선례 | `docs/evidence/ci_structural_duplicate_census_2026-09-30.md` §5·§7·§8 | 인용 |

## 9. 범위 밖 (명시)

- enforcement 게이트 추가, 시딩 구조 변경, S5 build-skip, ci-bootstrap 가치 판정(Slice 3) — 본 문서는 측정만 수행한다.
- 본 문서의 수치는 전부 위 수집 명령의 실제 출력에서 산출됐다. 스크립트(analyze.py/classify.py)는 계측 보조이며 판정 문 규칙은 §6 그대로다.
