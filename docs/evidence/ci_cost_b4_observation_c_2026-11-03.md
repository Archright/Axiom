# WP-B4 — 관측 C 종합 기록: CI 비용 3축 판정 · 불변식 · 증거 착지 (2026-11-03)

> **문서 성격**: WP-B4(B3 후속 효과 판정) 관측 C의 종합 기록이다. 본 문서는 **새
> 주장·해석을 추가하지 않는다** — freeze된 snapshot 원장
> (`data/ci_cost/ci_cost_20261103T012923Z/` · `data/ci_cost/acache_20261103T015017Z/`)
> 와 B4 실행 세션에서 산출된 **기계 판정 기록**을 충실하게 보존하는 것만이 임무다.
> 워크플로·스크립트·정책 mutation 0건의 docs-only 문서다.
> **관측 규율**: 본 문서의 모든 수치는 freeze된 snapshot 원장과 그 파생 산출물
> (`derived_v2/` TOOL_VERSION 2.0.0, `mla/`)에서만 산출됐다. 라이브 API 관측 0건
> (gh는 PR·CI·큐 운영에만 사용). 기존 snapshot(관측 A `ci_cost_20261102T010928Z` ·
> 관측 B `ci_cost_20261102T020849Z`)은 0444 불변으로 존중했다 — B 원장의 존재
> 정정(§7)을 포함해 재수집·재수정 없이 읽기만 했다.
> **사전등록 준수**: 측정·통계·epoch·판정 규칙 전부 B2 사전등록
> (`ci_cost_b2_selection_b4_prereg_2026-11-02.md`) §4 계약을 따른다 — §1.1 명령은
> §4.7 verbatim이며, 본 문서는 기준 변경을 수반하지 않는다.
> **계보**: B2 선정·사전등록 = `ci_cost_b2_selection_b4_prereg_2026-11-02.md`,
> B3 실행 = PR #1213 (MERGE `8c46c4ea8a`, 2026-11-02T07:57:49Z = **T_land**),
> 관측 C 원장 착지 = PR #1227, acache `tool.py` 수복 = PR #1229. 본 문서는 그 위의
> **종합 기록** 단계다.
> **권위**: 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset·required checks·
> merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).

---

## 1. 실행 기록 (관측 C)

| 항목 | 값 |
|---|---|
| OBS_ID | `ci_cost_20261103T012923Z` |
| ACACHE_ID | `acache_20261103T015017Z` |
| 관측 창 | `[2026-11-02T00:00:00Z, 2026-11-03T00:00:00Z)` |
| collect | GET **543 요청 · failures=0** (`integrity.api_requests=543`, `integrity.api_failures=0`, `pages_complete=true`) |
| freeze | **0444 · `frozen_at_utc=2026-11-03T01:40:22Z`** (collected 01:40:08Z) |
| population | usage **20** · runs **3,609** · jobs **564** · merges **200** · merge_commits **190** · budgets 4 · mla n=**52** |

ledger 원장 SHA256 (`snapshot.ledger_sha256` — 무결성 앵커):

| 파일 | sha256 |
|---|---|
| `budgets.jsonl` | `93f8862c6964b9f31185ad79dd322eee65bac4941e0aab87277983da23c851cf` |
| `jobs.jsonl` | `d51e02f56e6c817f80c2fb571390214358e67c1982d5724142c3ec01d2c2c6f5` |
| `merge_commits.jsonl` | `40ba6776388df9d204758f509c880ea42b951e2e312d7b881e8c91e7f687c93d` |
| `merges.jsonl` | `03139a204297f85d716aeb8fb727d9cecb3bb43477b324cf32b88c61e39c4842` |
| `runs.jsonl` | `e7eaeb058fb9ecc5c14129651fbb055a46e6b576ca39a4bd31446e14fed88daf` |
| `usage.jsonl` | `e99ed029e44484dada136e1959c0e0fa0a713c273592b66671a456dac723337d` |

### 1.1 §4.7 측정 명령 (사전등록 verbatim + 실행 파라미터)

B2 사전등록 §4.7의 동결 명령(`collect` → `freeze` → `aggregate`,
`tools/ci/ci_cost_observe.py` verbatim 재사용 — 새 수집 경로 0)에 본 관측의 실행
파라미터(frozen `manifest.json` `parameters` 블록이 실행 기록)를 대응시키면:

| §4.7 인자 | 실행값 |
|---|---|
| `--obs-id` | `ci_cost_20261103T012923Z` |
| `--data-dir` | `data/ci_cost` |
| `--usage-month` | `2026-11` |
| `--runs-since` / `--runs-until` | `2026-11-02T00:00:00Z` / `2026-11-03T00:00:00Z` |
| `--jobs-window` / `--jobs-max-runs` | `["2026-11-02T00:00:00Z","2026-11-03T00:00:00Z"]` / `300` |
| `--merged-since` / `--merged-until` | `2026-11-02T00:00:00Z` / `2026-11-03T00:00:00Z` |
| `--mla-since` / `--mla-until` | `2026-11-02T00:00:00Z` / `2026-11-03T00:00:00Z` |
| `run_subwindow_hours` | 6 (관측 A와 동일 파라미터 구조) |

판정 판독은 freeze된 snapshot의 `derived_v2/aggregate.json` 재생으로만 했다
(라이브 API 관측 금지 계약 준수).

### 1.2 acache 실행 (`acache_20261103T015017Z`)

- population: 관측 C frozen jobs ledger(stride 표본 `jobs_max_runs=300`) 중
  `event=merge_group` · job name ∈ {`attest / admission-check`,
  `attest / build-base-artifacts`} → **jobs 10 (PRE 8 · POST 2)**
- 층화 경계: **T_land = 2026-11-02T07:57:49Z** (B3 MERGE `8c46c4ea8`, PR #1213)
- log GET failures 0 · `run_attempt>1` 인프라 재시도 0 (exclusions 없음)
- `tool.py` sha256 `f946ec3939a6d773638f6d0f9b222ab86194b7fc626757734bef37547f5b910e`
  — 착지 경계 이력은 §5 (#1229)

---

## 2. 3축 판정 (사전등록 §4.1 — 상호 전이 금지)

### 2.1 비용 축 — **UNKNOWN**

census (B3 트리거 축소 #1213, T_land 기준 **동일 노출 16.04h × 2**):

| 창 | publisher runs | 게이트 완료당 |
|---|---:|---:|
| before (16.04h) | **1,876** | 18.76 |
| after (16.04h) | **26** (**−98.6%**) | **2.0** |

- **Poisson z≈−30** · after 26건 conclusion **전부 success** · **1:1 페어링**
- census 감소 자체는 결정적이나, 판정은 **UNKNOWN**이다:

| # | UNKNOWN 근거 (fail-closed) |
|---|---|
| 1 | after **n=26 < 30** — §4.2 횟수·비용 유의성 요건 미달 → **"표본 부족"** 기록 |
| 2 | usage **net $0 바닥** — 월 할인이 gross를 전액 흡수해 절감액 판별 불가 |
| 3 | **활동량 교락 병기** — N_landings **42→14** 감소, 월 스케일 착지률 **21.2→38.5/day 증가** |

- usage 실측(usage API 권위): 2026-11 **gross $44.655836 · net $0.0** —
  Actions Linux 7,225분($43.35) + Actions Linux Slim 405분($0.81) +
  Actions storage $0.495698 + Git LFS storage $0.000138
- GHEC 귀속 표본 보완(§4.6 과제): jobs 표본 564잡 = GHEC-label 210잡/253.73분 ·
  fallback(Ubicloud) 47잡/17.38분 · 미할당 307잡 — 표본 보간 (전수 라벨 데이터 없음)
- 원장 재계산 재현 노트 (freeze 원장 전수): before 1,876 = 관측 B
  `[2026-11-01T15:55:38Z→11-02T00:00)` **309** + 관측 C `[00:00→T_land)` **1,567**;
  after `[T_land→24:00)` **26** (26/26 success). N_landings before **42** = B-part 9
  + C-before 33, after **14** (14/14 `parents==2` 검증).

### 2.2 성능 축 — **UNKNOWN**

mla 층화 (wall = updated_at − run_started_at, Hyndman–Fan type 7, T_land 층화):

| 층 | n | P50 (s) | P95 (s) |
|---|---:|---:|---:|
| PRE | **39** | 509.0 | 738.5 |
| POST | **13** | 683.0 | 779.2 |

- §4.2 P95 판정 요건 **n ≥ 100 미달** → P95 판정 근거 불가 → **UNKNOWN** (fail-closed)

### 2.3 정책 SLO — 480s 미충족

- 창 P95 **756.15s** (n=52 — `admission_latency.wall_s`, 선형보간)
- baseline §7 선례: 관측 A P95 1,105초 (n=206) · 관측 B P95 826초 (n=21, 표본 부족 병기)
- **480초(8분) 정책 SLO 미충족** — 단, 이 SLO는 정책이지 헌법 불변식이 아니다
  (`ci_wall_clock_optimization_acceptance_2026-10-07.md:133-135`); 초과가 추가
  최적화 의무를 자동 발생시키지 않는다.

### 2.4 A-cache 기능 상실 징후 — **0건** (§4.5 기능 계약)

- HIT율 **10/10 = 100%** (`AXIOM_CACHE_A_VERIFY: OK` / keygen-present jobs)
- **a-key T_land 직후 회전 후 신규 키 즉시 HIT** — PRE 8잡 key `…9ee08147da6e` →
  POST 2잡 key `…e013a2c969d4`, 각 잡 4 hits
- **콜드 밴드 회귀 0건** (연속 MISS + setup wall 98–131s 밴드 재진입 없음)
- **n_POST = 2 < 30** 병기 (§4.2 — 유의성 주장 없이 기록값)

---

## 3. 세 지표 분리 (§4.6)

| 지표 | 관측 C | 관측 A | 비고 |
|---|---:|---:|---|
| **C_landing_min** | **$0.000** | $0.000407 | GHEC net ÷ N_landings 하한 — **net 바닥으로 판별 불가** |
| **G_landing** | **$0.950** | **$0.476** | gross ÷ N_landings ($44.655836/47 vs $312.884971/657) — **활동량 교락 병기** |
| **Ubicloud actual cash** | **UNKNOWN** | UNKNOWN | **공식 API 부재 — 인간 인보이스 유일 경로** (Q7/Q11) |

- N_landings (C 창): **47** — base_ref==main + 2-parent GitHub native MERGE 검증 통과
- 고정비(별도 라인 — 변동비 지표 혼입 금지): Enterprise Cloud $1.4 (0.0667 UserMonths)

---

## 4. 불변식 6축 (기준점 `498c5570`)

기준점: `498c55704552291da926fae6eb34bc5c0c04ec1b` — PR #1189 MERGE
(node24 generation cutover, 2026-11-02T07:46:00Z). 종결점: `71f237e6` (§5).

| # | 불변식 | 판정 |
|---|---|---|
| ① | 필수 5 checks + merge queue 일치 | **일치** |
| ② | org ruleset 핀 `7eaa9624` 유지 | **유지** — axiom-admission-gate ruleset(id 25218071)이 `.github/workflows/admission-gate-v2.yml` @ `7eaa9624d128b9f10e9e40d140d5c23367dabdad` 고정 |
| ③ | baseline 일치 | **일치** — `data/baseline.json` 498c5570→71f237e6 무변경 |
| ④ | Router generation 15 불변 | **불변** — `CI_RUNNER_MAP` generation=15 (착지 시점 재판독 동일) |
| ⑤ | `.github/` 3파일 전부 귀속 | **귀속** — publisher 38+/25−=#1213 · byo-agent 2건=#1224 v92+#1225 |
| ⑥ | config 3 SAME + trusted_writer_set=#1222/#1223 (ADR-0025) | **SAME·귀속** |

- **무귀속 드리프트 0건** — 위 귀속 외에 `.github/`·`config/`에 귀속 불가 변경 없음
  (재검증: `git diff --numstat 498c5570 71f237e6 -- .github/ config/` = publisher
  `38+/25−`(#1213) · `byo-agent.yml +359` · `byo-agent-selftest.yml +139`(#1224 v92
  정책 등록 + #1225 워크플로 착지) · `repository_surface.json +5/3−`(#1224
  policyVersion 92) · `trusted_writer_set.json +20/15−`(#1222/#1223, ADR-0025))

---

## 5. 증거 착지

| PR | 제목 | MERGE SHA | 병합 시각 (UTC) |
|---|---|---|---|
| **#1227** | data(evidence): WP-B4 관측 C — CI 비용 3축 판정 freeze 스냅샷 | `19df7a5a4b211f47cb3d744449166a2dca4a5638` | 2026-11-03T02:29:47Z |
| **#1229** | data(evidence): WP-B4 acache 세트 수복 — tool.py (gitignore '\*.py' 무음 제외) | `71f237e62c4310a8a0936c04f6667d6ee197048a` | 2026-11-03T02:59:57Z |

- #1227 = 36파일 — ci_cost 13 (ledger 6 · `SHA256SUMS` 없음 · collection.log ·
  manifest · derived_v2 3 · mla 2) + acache 23 (manifest · collection.log ·
  `SHA256SUMS` · logs 10 · reads 10)
- #1229 = acache `tool.py` 1파일 — **전역 gitignore `*.py`가 원장 디렉터리 내
  파일을 무음 제외한 사례** → force-add로 수복. 원장 도구는 manifest가
  `tool_path`+`tool_sha256`를 선언하므로 세트 불일치는 즉시 드러났다.
- 최종 파일 세트: `git ls-tree -r 71f237e6` → **37/37 검증 PASS**
  (ci_cost 13 + acache 24)

---

## 6. 판정 귀결 (§4.5 fail-closed)

- 비용 UNKNOWN · 성능 UNKNOWN — **UNKNOWN 2축 존재로 슬라이스 성공 선언 불가**
  (검증 불가 증거 = fail closed, AGENTS.md §4)
- 측정 절차 자체는 §4.7 계약대로 **완결** — UNKNOWN은 측정 실패가 아니라
  §4.2·§4.3 요건 미충족의 기록이다
- 후속(**UNKNOWN 판정 전환 · 다음 최적화 후보**)은 **신규 사전등록 문서로만**
  가능하다 — 관측을 본 뒤의 기준 변경은 어떤 형태로도 허용되지 않는다
- 남은 인간 결정: **D1/D2/D3** · **Ubicloud 인보이스** · **WP-C 12월 조건부 관측**

---

## 7. 정정 기록

- 관측 B(`ci_cost_20261102T020849Z`) `runs.jsonl` **실재** — **1,482행**.
  사전점검(agent-63)의 "B runs.jsonl 부재" 기록은 오류였으며, **B4 실행 중 정정**됐다.
  본 문서 §2.1 census 재계산(before 창 309건)이 그 원장을 사용한다 — 원장은 0444로
  존중됐다(재수집·재수정 없음).

---

## 8. 검증 가능성 (GET-only 재현)

```bash
# population · integrity · economic · admission_latency · landing — frozen aggregate 재생
python3 -c "import json; a=json.load(open('data/ci_cost/ci_cost_20261103T012923Z/derived_v2/aggregate.json')); print(a['integrity'], a['snapshot'], a['economic_indicators'], a['admission_latency']['wall_s'], a['landing']['landing_count'])"
# publisher · landings census — 관측 B+C freeze 원장 전수 재계산 (§2.1 재현 노트; 라이브 호출 0)
# acache HIT — data/ci_cost/acache_20261103T015017Z/reads/*.read.json 의 verify_result 집계
# mla 층화 — data/ci_cost/ci_cost_20261103T012923Z/mla/ci_cost_mla.{runs.jsonl,summary.json}
# 불변식 6축 — git diff --numstat 498c5570 71f237e6 -- .github/ config/ data/baseline.json
# 파일 세트 — git ls-tree -r 71f237e6 --name-only data/ci_cost/ | wc -l   # → 37
# 착지 — gh pr view 1227 1229 --repo Archright/Axiom --json mergeCommit,mergedAt
```

---

*본 문서는 freeze된 snapshot의 투영이다 — 문서가 snapshot을 대체하지 않는다.
수치의 원본은 0444 frozen 원장이며, 본 문서는 B4 실행 세션의 기계 판정 기록을
보존한다.*
