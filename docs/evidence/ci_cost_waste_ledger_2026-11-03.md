# CI 낭비 후보 원장 — 2026-11-03 (8열 14행 · 5영역 커버리지 · 계보 매핑)

> **문서 성격**: 동결 CI 비용 원장(관측 A·B·C + acache 4종)만을 소비해 산출한 **단일 낭비
> 후보 원장**(8열·14행)이다. 본 문서는 최적화 후보를 **선정하지 않는다** — 표의 상위 행은
> **조사 우선순위 라벨**이며 제거 우선순위가 아니다(§1). 다음 최적화(B2″)의 선정은 별도
> 사전등록을 거치는 인간 결정이다. 워크플로·스크립트·정책·게이트 mutation 0건의
> docs+data 문서다(짝 데이터: `data/ci_optimization/waste_ledger_2026-11-03.json`).
> **관측 규율**: 모든 수치는 freeze된 snapshot 원장(`data/ci_cost/ci_cost_20261102T010928Z`=A
> 2026-10 전월 · `ci_cost_20261102T020849Z`=B 11-01 창 · `ci_cost_20261103T012923Z`=C 11-02
> 창 · `acache_20261103T015017Z`)과 그 파생 산출물(`derived_v2/`·`mla/`)의 **전수 재계산**에서만
> 나온다. 라이브 run 조회 0건·2026-11-03T00:00Z 이후 생성 런의 수집·분석 0건 — 진행 중
> 실험(C′·#1166)의 결과-맹결을 보존한다(B2′ §2.3). 기존 snapshot(0444 불변)은 수정 없이
> 소비만 했다.
> **권위**: 본 문서는 **Reporter**다 — 병합 판정 권위(GitHub ruleset·required checks·merge
> queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 과금 규칙의 권위는 GitHub
> 공식 문서이며 §10에 인용한다. usage API 청구 원장이 actual billed의 유일 권위이며
> workflow 귀속은 불가하다(§13).
> **계보**: B2 선정·사전등록 = `ci_cost_b2_selection_b4_prereg_2026-11-02.md`, B3 실행 = PR
> #1213 (MERGE `8c46c4ea8a`, 2026-11-02T07:57:49Z = **T_land**), 관측 C 원장 = PR #1227,
> acache `tool.py` 수복 = PR #1229, B4 종합 = `ci_cost_b4_observation_c_2026-11-03.md`
> (PR #1231), B2′ 사전등록 = `ci_cost_b2_prereg_v2_2026-11-03.md` (PR #1237, MERGE
> `5fdf1ad33`). 본 문서는 그 위의 **낭비 후보 투영** 단계다. 기존 파생 원장
> `waste_candidates[]`(관측 A 25행·B 19행·C 19행)와 본 14행의 대응은 §12 계보 매핑 표가
> 정본이다.
> **Date**: 2026-11-03 · **착지 대상**: `docs/evidence/` + `data/ci_optimization/` ·
> **Scope**: 본 문서 + 원장 JSON 2건 — 코드·워크플로·게이트·도구·동결 데이터 변경 0건.

---

## 1. 라벨 규칙 — 자원량 4분류 · 증거 수준 4단

### 1.1 자원량 4분류 (상호 대체 불가)

본 원장의 모든 분·달러 수치는 아래 4분류 중 하나로 라벨되며, **분류 간 대체·합산·비교는
금지**다(비가산 원칙 선언 §7과 별개의 측정 단위 규율이다).

| 라벨 | 정의 | 권위·전수성 |
|---|---|---|
| **workflow wall minutes** | 런 `updated_at − created_at`(음수 0 클램프)의 합 | runs.jsonl **전수** |
| **job execution minutes** | 잡 `completed_at − started_at`(음수 0 클램프)의 합 | jobs.jsonl **stride 표본**(§13 — 전수 아님) |
| **billing minutes** | 잡별 분의 **올림 합** `Σ ceil(잡 분)` — 과금 상당 | 잡 표본 기반 **추정**(§10 과금 규칙) |
| **actual billed USD** | usage API 청구 원장의 gross/net 금액 | `ledger/usage.jsonl` **전용** — repo×SKU×일 집계만 제공·workflow 귀속 불가 |

### 1.2 증거 수준 4단 라벨

| 라벨 | 의미 |
|---|---|
| **관측치** | 동결 원장 전수 재계산 값(외삽·가중 없음) |
| **추정치(가중·가정 명시)** | 표본 외삽·환산값 — 사용한 가중·가정을 셀 또는 각주에 명시 |
| **일반화 가능성** | 단일 창·단일 세대 관측의 일반화 — 다른 창에서의 재현 보장 없음 |
| **UNKNOWN** | 동결 데이터에 근거 필드가 없는 항목 — fail-closed(측정 불가와 측정 불충분을 구분 기록) |

### 1.3 상위 후보 해석 규칙 (HARD RULE)

표의 기여도·예상 회수량 상위 행은 **조사 우선순위**를 뜻한다 — 제거 우선순위·최적화
선정이 아니다(§0 문서 성격·AGENTS.md §0.12). 본 원장은 B2″ 사전등록의 입력이며 선정
문서가 아니다.

---

## 2. 8열 원장 — 14행

기저: 동결 원장 전수 재계산 초안(검증 에이전트 G 산출)에 §1 라벨 규칙과
`derived_v2/aggregate.json waste_candidates[]`(A 25행·B 19행·C 19행 — 검증 에이전트 I 전수
열거)의 기여도·위험·예상 회수량 열을 대조·통합했다. 창이 명시되지 않은 행의 월 수치는
**관측 A(2026-10 전월 30.82일)** 기준이다.

| # | 대상 | 빈도 | 회당 자원 | 기여도 | 제거 가능성 | 증거 수준 | 위험 | 예상 회수량 |
|---|---|---|---|---|---|---|---|---|
| R01 | admission-gate v1 (소멸 세대 — §4 정의 ①) | 39.2런/일 [초안]·path 전수 1,310런(mg 687·pr 623)[재계산] | wall 434.9분/일·회당 13.5 wall분[초안¹] | merge_queue (mg wall 56.4%) | **이미 소멸** — B·C 창 0런(v2 세대 전환)·신규 조치 불요 | 관측치(workflow wall 전수) — job execution·billing **UNKNOWN**(잡 표본 0) | medium | **UNKNOWN**(측정 job분 0·est null) |
| R02 | admission-gate-v2 | 22.0런/일(10월 677·mg 313)·B 43·C 120 | wall 286.1분/일·회당 13.0 wall분 — 잡 표본 17.7분/런(billing 표본) | required_check [admission-check] (mg wall 56.1%) | required_check — **제거 불가**(실행 시간 최적화만 가능) | 관측치(wall 전수) + 추정치(잡 stride 표본 — 가정 §13) | high | $1.2734(10월 창·GHEC subset·잡 표본 추정) |
| R03 | observation | 42.5런/일[초안·1,311런]·path 전수 1,312런[재계산] | wall 138.2분/일·회당 3.3 wall분 | merge_queue (mg wall 57.4%) | 착지 필수 경로 — **제거 불가** | 관측치 | medium | $0.2288(동일 라벨) |
| R04 | ci-cache-publisher (**B3前** 전세대) | 284.3런/일(10월 8,762·workflow_run 전체) | wall 128.9분/일·회당 0.45 wall분 — 잡 표본 0.19분/런 | none (0%) | **제거 완료**(B3 착지 2026-11-02 — §8: 런 −98.2~−99.1%·wall-분 −82.4~−91.5% 실측) | 관측치(wall 전수) + 추정치(잡 표본) | low | $0.1447(동일 라벨) |
| R05 | ci-cache-publisher (**B3後 POST** — B·C행 후세대) | 26런/POST 창 16.04h(≈38.9런/일 환산[§4 정의 ②]·초안 ≈41/일[15.3h 분모 — 재현 불가]) | wall 31.9분/창(≈47.8분/일 환산[정의 ②]·초안 ≈50/일)·회당 1.23분(전부 success) | none (0%) | **잔존 정상 경로 — 제거 불가**(B3 이후 발화 누락은 기능 회귀) | 관측치(POST 26런 전수) + 추정치(일간 환산식 §4 정의 ②)·일반화 가능성(16.04h 단일 창) | low | **UNKNOWN**(환산 근거 동결 데이터 부재 — §4 정의 ②) |
| R06 | axiom-operational-slice | 13.3런/일(409·mg 131) | wall 102.4분/일·회당 7.7 wall분 — 잡 표본 17.8분/런 | required_check [axiom-operational-slice] (mg wall 30.0%) | required_check — **제거 불가** | 관측치 + 추정치(잡 표본) | high | $0.0335(동일 라벨) |
| R07 | repository_surface | 32.0런/일(987·pull_request 전체) | wall 72.6분/일·회당 2.3 wall분 | none (0%) | landing none — 이벤트 기인(동일 head 재실행 26런 관측) | 관측치 | low | $0.0915(동일 라벨) |
| R08 | bsec-integrity | 34.9런/일(1,077·mg 576) | wall 67.1분/일·회당 1.9 wall분 — 잡 표본 52.7분/31런 | required_check [bsec-integrity] (mg wall 52.6%) | required_check — **제거 불가** | 관측치 + 추정치(잡 표본) | high | $0.2055(동일 라벨) |
| R09 | debt-registry-gate | 16.5런/일(507·mg 230) | wall 36.1분/일·회당 2.2 wall분 — 잡 표본 41.8분/34런 | required_check [debt-registry-gate] (mg wall 40.1%) | required_check — **제거 불가** | 관측치 + 추정치(잡 표본) | high | $0.2126(동일 라벨) |
| R10 | landing-integrity | 64.5런/일(1,987·mg 1,000) | wall 35.5분/일·회당 0.55 wall분 — 잡 표본 2.64분/런(병렬 잡) | merge_queue (mg wall 44.2%) | 착지 필수 경로 — **제거 불가** | 관측치 + 추정치(잡 표본) | medium | $0.0777(동일 라벨) |
| R11 | ci-provider-router | 48.9런/일(1,507·wr 1,367) | wall 27.1분/일·회당 0.6 wall분 | none (0%) | landing none — **재발화 스톰 관측**(증분 1,270런·12.4h — B3 미적용 영역·조사 우선순위 상위) | 관측치 | low | $0.0(측정 ghec 분 0) |
| R12 | generation-acceptance | 10.0런/일(312·mg 141) | wall 18.6분/일·회당 1.8 wall분 — 잡 표본 14.7분/10런 | required_check [generation-acceptance] (mg wall 44.7%) | required_check — **제거 불가** | 관측치 + 추정치(잡 표본) | high | $0.0111(동일 라벨) |
| R13 | probe-merge-queue | 32.6런/일(1,004·mg 1,000) | wall 15.6분/일·회당 0.5 wall분 — 잡 표본 3.0분/11런 | merge_queue (mg wall 92.1%) | 착지 필수 경로 — **제거 불가** | 관측치 + 추정치(잡 표본) | medium | $0.0122(동일 라벨) |
| R14 | C mla PRE (게이트 파생 행 — §4 정의 ③) | 39런/창(created < T_land·merge_group) | 회당 9.4분(=561초 평균 wall·T_queue=0) — P50 509.0/P95 738.5초 | 착지 필수(merge_queue) | 파생 행 — 제거 대상 아님(성능 분해 전용) | 관측치(B4 공개 집계와 **초 단위 일치** 재현) | high(v2와 동일 세대) | 해당 없음 — v2 행에 포함(별도 과금 행 아님·총량 미계수) |

¹ R01 회당치는 초안 표기를 보존한다 — 전 행 공통 산식(wall-분/일 ÷ 런/일) 재현치는 11.1분이며,
초안의 산식이 문서화돼 있지 않아 병기한다(§13 한계). "예상 회수량"의 $값은 동결 파생 원장의
`est_usd_ghec_subset`(10월 창·GHEC subset·잡 stride 표본 기반)을 라벨 그대로 인용한 것이며
§10 과금 규칙으로 재계산한 값이 아니다 — billing minutes 표본이 전수가 아니므로 절대액으로
읽지 않는다(§13).

---

## 3. A-cache 행 (8열 표 외부 부기 — 워크플로 행이 아니다)

| 항목 | 값 |
|---|---|
| 등록 계약 | B2′ §3.3 — 표본 단위 = 고유 CI job ID·누적 고유 attest job **≥30**에서만 HIT율 주장 성립·관측 상한 **K_max=8**(§2.4 일일 관측으로 누적)·중복 제거 필수 |
| 현재 상태 | **누적 관측 진행 중**(2026-11-03 개시) — 본 원장 데이터 컷오프(2026-11-03T00:00Z) 이전이므로 판정 기록 없음 |
| 기록값 (판정 아님) | acache `acache_20261103T015017Z`: **10/10 HIT**(n=10 — 누적 고유 job 10·유의성 미달, B4 §1.2와 정합·콜드 재진입 0) |
| 판정 귀속 | HIT율 주장 성립/UNKNOWN 판정은 **C′ 증거 관측 세트**에서 기록한다(B2′ §3.3·§4) — 본 원장이 판정하지 않는다 |
| 도구 앵커 | acache `tool.py` sha256 `f946ec3939a6d773638f6d0f9b222ab86194b7fc626757734bef37547f5b910e`(`acache_20261103T015017Z/manifest.json` `tool_sha256` — B2′ §3.3 등록값 일치) |

---

## 4. 원장 문언 정의 3종 (계보 매핑 미해결 항목의 해소)

계보 매핑(§12)에서 미해결로 남았던 2건+중복 계수 1건을 본 원장의 문언 정의로 고정한다 —
이 정의는 본 문서가 정의하는 것이며 기존 계약을 개정하지 않는다.

### ① admission-check.yml의 v1 행 통합 범위

**"admission-gate v1" 행(R01)은 `path = .github/workflows/admission-gate.yml` 런만
계수한다.** 동결 원장 직접 재계산: admission-gate.yml = 1,310런(merge_group 687·pull_request
623·push 0), admission-check.yml = 128런(push 전용·별개 경로). admission-check.yml은 v1
세대의 push 변형이며 측정 job분 0분(aggregate A16 — ghec/fallback/job 모두 0)이므로 R01의
자원·회수 열에 0 기여다. 본 원장은 이를 R01에 **통합하지 않고** "소멸 세대 push 변형·측정
0분"으로 별기한다 — 통합 여부가 자원 총량에 영향을 주지 않음을 정의로 고정한다.

### ② publisher POST 환산식 (B3後 행 R05)

동결 데이터에 "POST 런 → 일간" 환산의 사전 등록된 산식은 존재하지 않는다(agent-I — 환산
근거 UNKNOWN). 본 원장이 기술하는 환산식은 다음과 같다:

```
일간 환산치 = POST 창 관측치 × (24h ÷ POST 창 길이)
POST 창 길이 = [T_land 2026-11-02T07:57:49Z, 데이터 컷오프 2026-11-03T00:00:00Z) = 16.036h
             (B2′ §3.1·B4 §1의 등록 POST 창 — 동결 재현 가능한 유일 분모)
→ 26런 × (24 ÷ 16.036) = 38.9런/일 · 31.9분 × (24 ÷ 16.036) = 47.8분/일
```

초안(검증 에이전트 G)의 ≈41런/일·≈50분/일은 **15.3h 분모**를 쓴 것으로 동결 원장에서
분모가 재현되지 않는다(POST 런 활동 스팬은 08:35–15:58 = 7.39h·창 정의 분모는 16.036h —
15.3h에 대응하는 창 정의를 동결 데이터에서 확인 불가). 본 원장은 **16.036h 분모 환산치를
정본**으로 쓰고 초안치를 부기한다. 런·분의 일간 확정은 C′ frozen snapshot 이후 재관측
과제다.

### ③ C mla PRE 파생 행(R14)과 admission-gate-v2 행(R02)의 중복 계수 방지

R14는 C 원장 mla 표본(39런 = admission-gate-v2 merge_group 게이트 런, created < T_land)의
**성능 분해 전용 파생 행**이며 `waste_candidates[]`에 원행이 없다. R14는 (a) 자원 총량
열(분·USD)에 계수하지 않고, (b) R02의 빈도·자원 셀과 별도로 T_queue·wall 분위 증명 전용으로만
읽으며, (c) 전체 소비 집계(§7 고유 job 원본)에서 제외한다. R14의 wall 39런 평균 9.4분은
R02의 C 창 값(C00 — 120런·12.033 ghec분 등)과 서로 다른 모집단·창의 값이므로 상호 대체·
합산하지 않는다.

---

## 5. 5영역 커버리지 표 (각 셀 실측 / UNKNOWN)

기준 관측: A(2026-10 전월 전수 21,598런·716.41h) + C mla/acache 보조. 5영역은 분석 관점이며
가산하지 않는다(§7).

| 영역 | 근거(동결 원장 필드) | 측정값 | 셀 상태 |
|---|---|---|---|
| ① 대기 — runner scheduling wait | `runs.jsonl` created→run_started(attempt=1 한정·§9 정의) + `derived_v2/aggregate.json` `wait_run_split_by_event` | C mla PRE **39/39 = 0초**·A mla **205/206 = 0초**(예외 1건 = 재시도 오분류 §9)·10월 ledger naive 최대 56,336초(전부 재시도 오염 경로 — attempt=1 한정 시 제외) | **실측**(정의 한정) — 단 merge queue dwell은 **UNKNOWN** |
| ①a merge queue dwell (대기의 별도 구간) | runs API 타임스탬프 산술로 환원 불가 — 유일 관측 수단은 GraphQL `MergeQueueEntry.enqueuedAt`(동결 원장 미수집) | — | **UNKNOWN** |
| ② 실행 | `runs.jsonl` wall 전수 + `per_workflow_measured_minutes`(15 워크플로) + `jobs.jsonl` stride 표본 | 10월 21,598런·**716.41h** wall(23.25h/일) — 상위: v1 223.4h·v2 146.9h·observation 71.0h·publisher 66.2h·slice 52.6h·잡-분 표본 513런(2.4%) 병기 | **실측**(wall 전수) + 표본(잡 실행 — §13) |
| ③ 중복 — 동일 (workflow,event,head_sha) 재실행 | `aggregate.json` `dup_rerun`(동일 head_sha+event) | 중복 그룹 770·**재실행 증분 9,679런(44.8%)·85.87h(전체 wall 12.0%)** — 73%(62.4h)가 publisher×workflow_run 재발화 스톰(최악 동일 head_sha 111회·323분)·router 1,270런/12.4h·**동일 SHA merge_group 재발화는 0건**(10월 실측) | **실측** |
| ④ 데이터 이동 — 저장·보관 | `usage.jsonl` `sku:"Actions storage" unitType:"GigabyteHours"` | 10월 **37,995.29 GBh**($12.767 gross·net $0.267) — GB-Months 산식·요율은 §10(4) | **실측**(청구 원장) — 캐시/아티팩트/LFS 구분·런·워크플로 귀속 **불가** |
| ④a 데이터 이동 — 전송량 | runs·jobs·artifacts·cache 전 REST 응답에 바이트 전송 카운터 부재(전수 확인 — agent-F) | — | **UNKNOWN** |
| ④b 데이터 이동 — 전송 기인 잡 실행시간 | 근거 필드 부재 | — | **UNKNOWN** |
| ⑤ 실패·재시도 | `conclusion`·`run_attempt` 전수 | failure **1,289런(6.0%)·81.64h(wall 11.4%)**(v1 353런/52.64h·v2 91/19.68h·publisher 357/0.78h[초단위])·run_attempt>1 **79런·57.16h**·≥300초 후 cancelled **30런/9.1h**(v2 10런/5.02h·v1 6/1.30h·publisher 7/0.91h — 장시간 취소는 게이트 집중) | **실측** |

cancelled 잡의 과금 귀속(중단 시점까지 사용분 — §10(3))은 잡 표본이 cancelled 런을 충분히
덮지 않아 **런 단위 환산 UNKNOWN**이다. skipped 런의 잡 러너-분은 표본 0.0분(무과금 정합 — §10(2)).

---

## 6. 비가산 원칙 선언 (HARD RULE)

1. 5영역(대기·실행·중복·데이터 이동·실패/재시도)은 자원 소비의 **분석 관점(비가산 분류)**이다.
   영역 간, 그리고 영역 값과 워크플로 wall 값 사이의 **합산·차감으로 전체 소비 또는 회수
   가능량을 해석하는 것을 금지**한다 — 교집합이 존재한다(예: publisher 재발화 = 중복 ∧ 실행;
   재시도 런 = 실패 ∧ 실행; 게이트 장시간 취소 = 실패/재시도 ∧ 실행).
2. 전체 소비의 기준은 **고유 job 단위 원본**(usage API 청구 원장·jobs 전수)만이다 — 5영역 값
   또는 워크플로 wall 합을 전체로 보고하지 않는다.
3. 워크플로 wall 간 합산(예: R02 wall + R04 wall = 전체 wall의 일부 주장)도 금지다 — 런 wall은
   잡의 병렬 실행을 포함한 생애 시간이라 잡-분 합과 일치하지 않는다(잡 실행 합 ≈ publisher wall의
   54~69% 관측 — agent-H).
4. 본 원장의 어떤 열도 조사 우선순위 이외의 순위를 부여하지 않는다(§1.3).

---

## 7. 조사 A — publisher 실자원 절감 (B3 효과의 실측 라벨링)

### 7.1 B3 이전 자원량 — 4분류 라벨 (상호 대체 불가 · §1.1)

| 4분류 라벨 | 값 | 근거 |
|---|---|---|
| **workflow wall minutes** (전수) | **3,040.11분/월** = success 2,993.03 + failure 47.08 — 10월 publisher 8,762런 전수 Σ(updated−created)·success+failure 한정 | 동결 A 원장 재계산(agent-H·G 일치). A publisher는 created==run_started 전 런 일치(8,762/8,762)이므로 `updated−run_started` 정의와 동치. cancelled 465.8분+skipped 465.6분은 제외된 부분합(전 conclusion wall = 3,971.5분) |
| **job execution minutes** (표본) | A 43.48분(464잡)·B 9.80분(268잡)·C 3.53분(208잡) — 잡/런 = 3관측 모두 2.0 | jobs stride 표본 — A 커버 232/8,762런(2.6%·창 한정 232/3,367 = 6.9%)·역전 잡(A 93·B 148·C 117건) 0 클램프 |
| **billing minutes** Σ ceil (표본) | A 245분·B 26분·C 10분 — **10월 전수 환산 ≈9,253~11,379분**(conclusion 층화·균등 환산 범위)·job execution 전수 환산 ≈1,642~2,093분 | 가정 4종 명시: (i) stride 무편향 (ii) 두 서브창([10-20..10-22)∪[10-23..10-25)·6.9% 커버)이 10월 대표 — 10-24·10-31 고점일 창 밖 (iii) 런당 2잡 (iv) conclusion별 런당 잡시간 불변. 잡 실행 합 ≈ wall의 54~69%로 정합 |
| **actual billed USD** (usage API 전용) | 10월 org gross $312.884967·Actions Linux 49,138.3분(+Slim 2,609분)·11월(진행 중) gross $44.655836 — **workflow 귀속 불가** | `usage.jsonl`(repo×SKU×일 집계만) — B4 §2.1 정합 |

### 7.2 B3 효과 — 런 수 감쇠와 wall-분 감쇠의 격차

| 기준 | 런 수 | wall-분 |
|---|---|---|
| 동일일 시간당 — 마지막 런까지(C PRE→POST) | −98.2%(198.4→3.53/h) | −82.4%(24.65→4.33/h) |
| 동일일 시간당 — 원장 끝까지 | −99.1%(→1.65/h) | −91.5%(→2.03/h) |
| 월평균(A 10월 vs POST 관측치 직접 대응) | −90.8%(284.3→26) | −75.2%(128.9→31.9) |

감쇠 격차(**검증 확정값 인용 — 본 원장이 재도출하지 않는다**): **동일일 기준 6.4~7.6pt·
월평균 기준 15.6pt**(총범위 6.4~15.6pt).

- **"−98.6%"는 동결 원장 단독으로 재현 불가**(산출 분모·산식 UNKNOWN) — 본 원장은 재현
  가능 범위(−98.2~−99.1%)만 실측치로 보고한다.
- 제거 물량의 **91.3%**(=1,431/1,567 — C-PRE skipped 1,142+cancelled 289÷C-PRE 전체 1,567)가
  skipped·cancelled 초단위 런이며 skipped는 **무과금**(§10(2)) — **런 카운트 감쇠는 과금 감쇠를
  과대표현**한다. 절감 실체는 성공 잡 시간이 아니라 **무효 재발화 제거**다. 다만 B3 이전
  publisher wall의 75.4%가 success 잡(2,993분 — 동일 head 최대 111회 재발화 포함)이었으므로
  성공 잡 반복 소비도 과거 낭비의 구성원이었고, POST 26런(전부 success·회당 1.23분)은 그
  잔존 실작업 부담이다.

### 7.3 라벨 교정 — "억제된 1,876" 문구의 정정 (숫자 라벨 확정안)

| 숫자 | 정확한 라벨 | 창·모집단 |
|---|---|---|
| **1,876** | B4 §2.1 census 부기 — **equal 16.04h 창 `[11-01T15:55:38Z, T_land)` × 전-conclusion 총량**(B 309 + C-PRE 1,567·success 163 포함) — "억제된" 라벨은 **오기**이므로 본 원장에 실지 않음 | B∪C 원장 재현 일치 |
| 억제 전용 (equal 창) | **1,713** = cancelled 316 + skipped 1,397 | 동일 equal 창·억제 전용 |
| 억제 전용 (epoch 창) | **1,924** = skipped 1,576 + cancelled 348 (=2,107 − success 183) | ghec-return epoch 창 `[11-01T10:53:18Z, T_land)` 21.075h |
| **주 조합** | **2,107** = success 183 + cancelled 348 + skipped 1,576 — B2′ 등록 **ghec-return epoch 창 × 전-conclusion**·R_before = **16.86 = 2,107 ÷ 125**(게이트 전 conclusion 분모 — B2′ §3.1 인용·재현 일치) | prereg 등록 산식 그대로 |
| **보조 조합** | **1,567** = success 136 + skipped 1,142 + cancelled 289 — 관측 C 단독 PRE·억제율 **91.3% = 1,431/1,567** | C 원장 단독(B+C 창 수치와 혼용 금지) |

epoch 창 억제율 1,924/2,107 = 91.31%도 91.3%로 수렴한다. 2,107 계열은
`ci_cost_b2_prereg_v2_2026-11-03.md` §3.1에 정본화돼 있다(PR #1237 착지 확인).

---

## 8. 조사 B — SLO 꼬리 분해 (T_queue 실증)

### 8.1 명칭·정의 (HARD RULE)

**T_queue ≡ "runner scheduling wait"** = `run_started_at − created_at` — 런 생성→런 시작
대기다. 공식 문서의 "queue time"(잡이 러너 할당을 기다린 시간)과 동일어가 아님을 명시한다.
규칙: (a) **attempt=1 한정** — run_started_at은 재시도 리셋("Resets on re-run")되므로 attempt>1
런의 naive T_queue는 이전 attempt lifecycle+시도 간 대기를 오분류한다(실증: A mla 유일
재시도 런 run_id 39494927042·attempt=2·naive 2,675초 = 런 span 3,654초의 73.2%·동결 데이터에
attempt별 타임라인이 없어 분해 불가 — 하한 0/상한 2,675초). (b) **제외 건수 명시**: C mla PRE
0/39·A mla 1/206·ledger A 79/21,598({2:61·3:13·4:5}·naive 최대 56,336초)·C ledger PRE
5/3,130(최대 6,004초). (c) 시도별 분해는 동결 데이터에 계산 근거가 없어 채택하지 않는다.
(d) **merge queue dwell은 created_at 이전의 별도 구간**이며 REST merge-queue 엔드포인트·
웹훅 타임스탬프로 관측 불가 — GraphQL `MergeQueueEntry.enqueuedAt`만이 유일 관측 수단이다
(§5 ①a UNKNOWN).

### 8.2 실측 (PRE만 — POST per-run 금지 준수)

| 모집단 | n | T_queue (attempt=1 한정) | T_run (updated−run_started) |
|---|---|---|---|
| C mla PRE (created<T_land·merge_group·v2 39) | 39(attempt>1 **0건**) | **P50/P95/max = 0.0초 — 39/39 = 100%** | P50 **509.0** / P95 **738.5** / max 835초 — top-10 장기 지연 전부 **대기 0%·실행 100%** |
| A mla (10-16~10-22·v2 190+v1 16) | 206(attempt>1 1건 제외 시 205) | **205/205 = 0초**(`run_started_at == created_at` 정확 등식) | P50 740 / P95 1,105 / max 1,521초 |

- B4 공개 집계와의 재현 일치: PRE P50 509.0/P95 738.5·창 R-7 P95 756.15 — **초 단위 일치**
  (Hyndman–Fan R-7). POST(n=13)는 per-run 미계산 — B4 인용만(P50 683.0/P95 779.2·n≥100
  미달 → P95 판정 근거 불가·UNKNOWN fail-closed).
- 결론: **SLO wall의 큐 대기 기여 = 0%(PRE)** — 꼬리는 전부 실행 시간(T_run)이며, 다음 성능
  조사의 분기는 게이트 **실행 시간(잡 구성)**으로 좁혀진다(조사 우선순위 라벨 — §1.3).

---

## 9. GitHub 공식 과금 규칙 인용 (공식 문서 검증 — 2026-11-03 기준)

| # | 규칙 | 근거 |
|---|---|---|
| (1) | **과금 단위는 잡(job)** — `월 compute cost = Σ_job ceil(분_j) × rate(SKU_j)`·부분분 올림·최소 청구 없음·런 생성·이벤트·트리거 과금 항목 부재. 요율(분당): Linux 2-core **$0.006**·Windows $0.010·macOS $0.062·Linux slim $0.002·arm64 $0.005 — 구 multiplier 모델 폐지 | *Actions runner pricing*·*GitHub Actions billing* — 공식 문서 원문 직접 대조 검증 완료 |
| (2) | **skipped 잡 = 과금 0**(도출 — 규정 체계: 과금이 잡 실행 분으로만 정의 + skipped는 미실행 Success + "사용되지 않는 러너 생성 비용 없음" 문구 + 반론 조항 7문서·4 reusable 전수 부재 — 단일 직접 문장은 없으며 이 도출 경로가 유일 판정이라는 한계 병기) | *Control jobs with conditions* NOTE·*About larger runners billing* |
| (3) | **cancelled 잡 = 중단 시점까지 사용분 과금**(도출 — "총 처리 시간" 원칙·실패 5분 선례·5분 강제종료 타임아웃 구간 포함) | *GitHub Actions billing* 예시·*Workflow cancellation reference* |
| (4) | **큐 대기·provisioning·merge queue 대기 = 비과금**(간접 확정 — 과금 정의가 execution time 한정·queue time은 별도 지표로 분리·wait timer만 명시 면제 문장) | *Viewing job execution time*·*Deployments and environments* |
| (5) | **저장소 산식**: 아티팩트+Packages 공유 — GB-Hours 누적 ÷ 월 시간수 = GB-Months(월말 MB 반올림) → GHEC 포함 50GB 초과분 **$0.25/GB-월**. 캐시 — repo별 시간당 peak·별도 10GB/repo 무료·초과 **$0.07/GB-월**·7일 미접근+LRU 증발. 대역(전송) 과금 없음 | *GitHub Actions billing* How storage billing works·*Dependency caching* |
| (6) | **GHEC 포함치 ≈ $300/월**(50,000 Linux 표준분 상당) — **net 바닥 관측 시 절감액은 gross-minutes로 보고**한다(달러 상쇄 주장 금지) | *Product usage included*·B4 §2.1(10월 net $0.27/11월 net $0) |
| (7) | **주의**: Actions usage metrics는 과금 지표가 아님·과거 청구기록은 당시(구 multiplier) 요율 모델 해석. 정확한 청구 검증은 billing usage records 또는 잡 수준 ceil×요율 재계산으로만 | *Billing and usage* NOTE |

사후 분해 규범: 절감액 산정은 **executed 잡의 잡 수준 분해만** 허용한다 — 런 수준 필드
(created/updated 오염·run_started 재시도 리셋)로 실행 시간을 재구성하는 것을 금지한다(§8.1
T_queue 오염 규칙과 동일 근거).

---

## 10. Ubicloud·절감 보고 규범

**Ubicloud actual cash = UNKNOWN** (한 줄 병기 — 공식 API 부재·`economic_indicators.ubicloud_actual_cash_usd`
명시·인간 인보이스 유일 경로·본 원장은 인보이스 절차를 포함하지 않는다). GHEC net이 바닥
(할인이 gross 전액 흡수 — 10~11월 관측)인 동안 절감액 보고는 **gross-minutes** 기준이며
달러 상쇄액 주장을 하지 않는다(§9(6)). 월 usage의 net 비교 판정은 2026-12-01 이후 폐쇄월
확정 시점에 분리 등록된다(B2′ §4.4).

---

## 11. 조사 우선순위 상위 후보 (선정 아님 — §1.3 HARD RULE)

| 순위 | 행 | 근거(측정값) | 라벨 |
|---|---|---|---|
| 1 | R04 publisher B3前 | 중복 증분 9,679런 중 73%(62.4h)·wall-분 −82.4~−91.5% 실측 절감 — **이미 제거됨(B3)**·효과의 C′ 확정이 남음 | 조사(효과 확정) 우선 |
| 2 | R02 admission-gate-v2 | wall 최대 워크플로(146.9h)·SLO 꼬리 = 실행 100%(§8)·required_check로 제거 불가 — 잡 구성 분해만 조사 경로 | 조사(실행 시간) 우선 |
| 3 | R11 ci-provider-router | 재발화 스톰 잔존(증분 1,270런·12.4h·B3 미적용 영역)·landing none | 조사(중복 억제) 우선 |
| 4 | R14/§8 | T_queue=0 실증으로 대기 축 조사는 종결 — merge queue dwell만 GraphQL 신규 관측 과제 | 조사(측정 공백) 우선 |

이 순위는 측정값 기반 **조사 우선순위**다 — 어떤 항목도 본 원장이 제거·변경 대상으로 지정하지
않는다.

---

## 12. 계보 매핑 표 — 기존 waste_candidates[] → 최종 14행

기존 파생 원장: **A 25행**(전세대 10월·`ci_cost_20261102T010928Z/derived_v2/aggregate.json`) +
**B 19행**(현세대 11-01·`ci_cost_20261102T020849Z/...`) + **C 19행**(현세대 11-02·
`ci_cost_20261103T012923Z/...`) = 63행. "관측별 19행"은 A에서 불성립(19행 정본은 B·C뿐 —
공통 18종+B 전용 ghec-canary/C 전용 byo-agent-selftest)이며 "admission-gate v1" 행의 유일
소스는 A(B·C 창에서 워크플로 소멸)다.

**매핑 총계**: 유지 **12 워크플로**(v2·slice·bsec·publisher(A행)·repository_surface·
debt-registry·landing·router·gen-acceptance·probe·observation·v1) + **publisher 행 분할**
(A행→B3前 R04·B/C행→B3後 POST R05) + **admission-check 정의 통합**(§4 ① — v1 행 미계수·0분) +
**파생 1행**(C mla PRE R14 — 기존 행 없음) + **제외 28행**(14 workflow 종 — 플랜 확정 12종 +
동일 사유 부기 2종). 63 = 유지 소스 행 34(v1 = A 전용 1·publisher = A/B/C 3·나머지 10
워크플로 × 3관측 30) + admission-check 1 + 제외 28.

| 기존 행 (workflow · 관측·행) | 최종 행 | 처리 | 사유·근거 |
|---|---|---|---|
| admission-gate v1 (A17·1,310런 mg687/pr623) | R01 | **유지** | 최종 14행 중 v1의 유일 소스 — A(10월) 전용·B·C 창 소멸·merge_queue 기여(mg687·pr623)·측정 job분 0 |
| admission-check (A16·128런 push) | R01 (미계수) | **정의 통합** | §4 ① — 별개 경로·push 변형·측정 0분이라 합산 영향 0 — 통합 대신 별기 정의로 고정 |
| admission-gate-v2 (A00·B00·C00) | R02 | 유지 | 3관측 공통·required_check·최대 ghec 분(10월 223.267·C 창 125.467) |
| observation (A04·B07·C04) | R03 | 유지 | 3관측 공통·merge_queue 기여 |
| ci-cache-publisher (A05·8,762런 wr) | **R04 (B3前)** | 유지·분할 | A 창 = 전세대. 주의: 동결 파일에 "B3" 경계 정의는 없으며 세대 귀속은 창 기반(T_land 2026-11-02T07:57:49Z — B3 MERGE 정본) |
| ci-cache-publisher (B04·C10) | **R05 (B3後 POST)** | 유지·분할 | B·C 창 = 후세대 — 환산식은 §4 ②로 정의(환산 근거 동결 부재 → UNKNOWN 병기) |
| axiom-operational-slice (A01·B01·C01) | R06 | 유지 | 3관측 공통·required_check |
| repository_surface (A07·B05·C09) | R07 | 유지 | 3관측 공통·PR 전용 |
| bsec-integrity (A03·B02·C02) | R08 | 유지 | 3관측 공통·required_check |
| debt-registry-gate (A06·B09·C06) | R09 | 유지 | 3관측 공통·required_check |
| landing-integrity (A02·B06·C07) | R10 | 유지 | 3관측 공통·merge_queue·최대 런수(1,987) |
| ci-provider-router (A09·B03·C03) | R11 | 유지 | 3관측 공통·fallback 분 주요 보유(17.7~17.4분) |
| generation-acceptance (A08·B10·C05) | R12 | 유지 | 3관측 공통·required_check |
| probe-merge-queue (A12·B12·C11) | R13 | 유지 | 3관측 공통·merge_queue 전용(mg 런) |
| (기존 행 없음 — C mla PRE 39런 파생) | R14 | **파생** | §4 ③ 중복 계수 방지 규정 적용 — 성능 분해 전용·총량 미계수 |
| merge-queue-rearm (A13·B13·C13) | — | **제외** | landing none·≤1.967 job분·pull_request_target 전용 |
| trusted-writer-set (A11·B11·C12) | — | **제외** | landing none·≤3.367 job분 |
| tests-ci-unit-diagnostic (B08·C08) | — | **제외** | landing none·≤6.583 job분·비게이트 진단·**A 집합에 부재(10월 이후 신규)** |
| byo-agent-selftest (C15) | — | 제외 | C 전용 1런·0분 |
| closure-watcher (A14·B16·C16) | — | **제외** | schedule 워처·landing none·≤1.133분 |
| ghec-canary (A15·B18) | — | **제외** | ≤0.05분·canary |
| dependabot-auto-merge (A20·B17·C17) | — | **제외** | 0분·자동화 보조 |
| drift-signal (A22·B14·C18) | — | **제외** | 0~0.05분·workflow_run 신호 |
| admission-ssot-drift (A18·B15·C14) | — | **제외** | 0분·schedule 감사 |
| release-ship (A10) | — | **제외** | A 전용·릴리스 파이프라인·landing none·3.367분 |
| certificate-mint (A19) | — | **제외** | A 전용 5런·0분 |
| diagnostic-authority (A21) | — | **제외** | A 전용 1런·0분 |
| dynamic/dependabot/dependabot-updates (A23) | — | 제외(부기 2종의 1) | GitHub 시스템 워크플로·0분 — 플랜 확정 12종의 "등" 범위(동일 사유: landing none·소요 ≤6.6분) |
| gateway-jobs-measure (A24) | — | 제외(부기 2종의 2) | A 전용 2런·0분·측정 도구 — 동일 사유 |

제외 사유 총괄: 전부 **landing_contribution = none**·소요 **≤6.6분**(최대 tests-ci-unit-diagnostic
6.583분)·canary/시스템/감사/자동화 보조 성격 — 게이트·착지·실행 경로와 무관. 흡수(예:
merge-queue-rearm→probe)는 기능 인접이나 최종 14행 문언에 없어 수행하지 않았다 — 흡수가
필요하면 명시 개정이 선행된다.

---

## 13. 표본 한계 (명시 의무 — 추정치·UNKNOWN의 근거)

1. **잡 표본 2.4%**: jobs는 결정론 stride 표본(`--jobs-window × --jobs-max-runs 300`) — 관측 A
   513/21,598런(2.375%). 잡-분은 병기 참고치이며 stride 밖 워크플로(v1 게이트 등)는 잡 수준
   UNKNOWN.
2. **billing 커버 3.55%**: 관측 C `waste_coverage` — sampled_runs_share_pct 6.90·billing 대비
   3.55%. 10월 전수 환산치(§7.1)는 표본 외삽 추정치(가정 4종 명시)다.
3. **stride**: 표본은 시간 스트라이드 기반이며 10-24·10-31 고점일이 A의 잡 창 밖 — conclusion
   층화 환산에 과소/과대 가능.
4. **아티팩트 무수집**: 원장 어디에도 `/actions/artifacts` 수집이 없다(manifest 엔드포인트 전수
   = billing 2종 + runs + jobs + commits + pulls) — 아티팩트 크기·전송량 UNKNOWN.
5. **런/PR별 실청구 불가**: billing API는 repo×SKU×일 집계만 제공 — actual billed의 workflow·
   PR 귀속은 구조적으로 불가.
6. **스텝 타이밍**: jobs 원장은 `steps_count`만 보유 — 스텝별 시간은 로그 판독(mla regime 마커·
   acache logs)에서만 가능.
7. **캐시 용량 시계열 부재**: 시점 스냅샷만 존재(`cache_deletion_2026-10-17.json` 등) — 지속
   프록시는 usage "Actions storage" GigabyteHours뿐.
8. **창 비대칭**: A = 10월 전월(21,598행) vs B/C = 각 1일(1,482·3,609행) — ④⑤의 A↔B/C 비교는
   밀도 기준으로만 읽는다.
9. **agent-G 초안 표 계수 경계**: 초안의 워크플로 런 수(v1 1,207·observation 1,311)는 동결 path
   전수 재계산(본 원장 직접 검증: v1 1,310[mg687·pr623]·observation 1,312)과 소폭 차이가 있고,
   R01 회당치(13.5분)는 전 행 공통 산식(wall÷런) 재현치 11.1분과 다르다 — 셀은 초안 기저를
   보존(§2 각주¹)하며 계보·총량의 정본은 `waste_candidates[]`(§12)다.
10. **mla 재사용 분류**: 3관측 모두 `UNKNOWN_LOG`(--no-logs fail-closed) — FULL_REUSE 분류는
    acache 로그 판독(10 job)이 대체 경로다.

---

## 14. UNKNOWN 셀 요약·재생

**UNKNOWN 목록**: R01 job execution·billing·예상 회수량 / R05 일간 환산(15.3h 분모·예상
회수량) / 대기 — merge queue dwell / 데이터 이동 — 전송량·전송 기인 실행시간 / cancelled 잡
과금 귀속(런 환산) / Ubicloud actual cash / 런·PR별 actual billed 귀속 / v1 잡 수준 / 아티팩트
크기 / 캐시 용량 시계열 / 스텝별 시간 / "−98.6%" 산식 / "억제된 1,876" 이전 표기의 산식.

**재생 경로** (라이브 호출 0 — 동결 원장 직독):
- 8열·5영역·조사 A/B: `git show origin/main:data/ci_cost/<obs>/ledger/{runs,jobs,usage}.jsonl`
  + `<obs>/derived_v2/aggregate.json`(`waste_candidates`·`dup_rerun`·`wait_run_split_by_event`·
  `per_workflow_measured_minutes`) + `<obs>/mla/` — 파이프 재계산.
- 등록 조합(2,107·R_before 16.86): `ci_cost_b2_prereg_v2_2026-11-03.md` §7 재생 스크립트.
- A-cache 기록값: `acache_20261103T015017Z/{manifest.json,reads/}` — tool sha256 앵커 §3.
- 기계 판독형 쌍둥이: `data/ci_optimization/waste_ledger_2026-11-03.json`.

---

*본 원장은 동결 원장(데이터 컷오프 2026-11-03T00:00Z)의 투영이며 그 외 어떤 권위도 대체하지
않는다. 최적화 선정(B2″)은 새 사전등록을 거치는 인간 결정이다.*
