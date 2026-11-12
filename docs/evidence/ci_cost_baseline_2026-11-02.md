# CI Cost Baseline — 2026-11-02 (WP-B 1단계)

> **문서 성격**: Archright/Axiom의 CI 비용 최초 고정 baseline. 관측 도구
> `tools/ci/ci_cost_observe.py`(collect/freeze/aggregate 3단계, GET 전용)가
> 생성한 immutable snapshot(`data/ci_cost/`)에서만 수치를 읽는다. 본 문서는
> 해석·계약·사전등록을 담는 1차 SSOT이며, 수치의 원본은 snapshot이다(문서가
> snapshot을 대체하지 않는다).
>
> **관측 세션**:
> - 관측 A (2026-10 폐쇄월 전월): `ci_cost_20261102T010928Z`
> - 관측 A2 (ETag 304 재사용 증거): `ci_cost_20261102T014936Z`
> - 관측 B (2026-11 관측월 1일 창): `ci_cost_20261102T020849Z`
>
> **결정론 증명**: 동일 snapshot에 대한 aggregate 재생 출력 sha256이 재생
> 간 동일하다 — 관측 A: 4회 재생 모두
> `2366f210b4abd3080d1fb2b6d98c22208e7cd42826e45ea5f4555da55ebe319e`,
> 관측 B: 2회 재생 모두
> `6152b46a9f4917a1572a2a1629805cb325423093032b30def27c118b96d7996b`
> (동일 인자, 재생 중 라이브 조회 0건).
>
> **QUIRK 문서**: `docs/spec/ci_cost_observation_quirks.md` (CQ1 usage
> `page` 무시→Link 헤더 전용, CQ2 `--paginate`+If-None-Match 304 파싱
> 사망→비페이지네이션 `--include` 프로브, CQ3 runs `total_count` 2500 캡
> 아티팩트→서브윈도+반분 가드).

---

## 1. 관측 방법 (요약)

- **수집(collect)**: `gh api` GET 전용. usage는 조직 billing usage
  엔드포인트 폐쇄월 1회 slurp 수집(CQ1), runs는 6시간 서브윈도 × 완전
  페이지네이션 × 반분 가드(CQ3), jobs는 결정론 stride 표본
  (`--jobs-window` × `--jobs-max-runs 300`), merge 착지는
  `--merged-since/--merged-until` 창 필터, admission 지연은 기존
  `tools/ci/merge_latency_audit.sh --no-logs` 위임(새 수집 경로 없음 —
  산출물당 생성 authority 1개 원칙).
- **고정(freeze)**: ledger + `ledger_sha256` + `manifest.json`로 immutable
  snapshot 확정. freeze 이후 원장은 불변이며 aggregate는 snapshot만 읽는다
  (라이브 조회 없음 — 도구가 강제).
- **집계(aggregate)**: `--out` JSON 1개 + `--waste-md` 표 1개. sort_keys +
  고정 rounding + 시간 미포함 → 동일 snapshot 재생은 동일 출력.

---

## 2. 2026-10 재현 대조 (폐쇄월)

기준 실측치는 WP-B 태스크 계약에 고정된 2026-10 빌링 실측값이다(관측시각
상이로 인한 accrual 차이는 아래에 명시한다). 관측 A는 동일 endpoint를
2026-11-02에 재수집한 값이다.

| SKU | 기준 실측(quantity / USD) | 관측 A (2026-11-02T01:09Z 수집) | 비고 |
|---|---|---|---|
| Actions Linux | 49,511.33분 / $297.07 / net $0 | 49,138.33분 / $294.83 / net $0 | 수량 편차 −0.75% (≤1% 기준 내) |
| Actions Linux Slim | 2,609분 / $5.22 / net $0 | 2,609.0분 / $5.218 / net $0 | 정확 일치 |
| Actions storage | 37,995.3 GBh / $12.77 / net $0.27 | 37,995.289 GBh / $12.767 / net $0.267177 | 정확 일치 |
| Enterprise Cloud (좌석) | 0.97 UM / $20.32 | 0.9677 UM / $20.3226 / net $20.3226 | 정확 일치 — 고정비 버킷(`fixed_cost_usd`) |
| 일자 분포 | 10/1–22 집중, 피크 10/20 4,767분, 10/23 295.3분으로 급감, 10/24–31 1–2분/일, 11/1 1,979분 복귀 | 피크 10/20 4,767분·10/23 295.33분·10/24 2분·10/31 2분 — 전 구간 정확 일치 | Actions Linux 일자 |

- **차이 해석 규칙**: 두 관측시각 사이의 차이는 **accrual과 소급 정정으로
  설명**한다 — billing usage는 월 중 적립이며, **폐쇄월 행도 후행 정정될 수
  있다**(실측: 관측 A 수집 40분 후 10/03 Git LFS bandwidth 행이 0.022749 →
  0.033504 GB로 정정, ETag 변경 확인 —
  `docs/spec/ci_cost_observation_quirks.md` CQ5). 차이를 "오류"로 기술하지
  않고, 양쪽 관측시각을 명기한다. 정합 판정은 **수량 상대편차 ≤ 1%** 를
  기준으로 한다.
- 재현 판정: **성립** — 전 SKU 수량 편차 ≤ 0.75%, 일자 분포 전 구간 일치.

## 3. 2026-11 관측 (관측월, 11/01 단일 일 창)

관측 B는 관측월의 첫날(2026-11-01T00:00:00Z..2026-11-02T00:00:00Z)만
수집한다. 관측월 수치는 **적립 진행 중 값**이며 baseline 수치로 재사용할 수
없다(다음 달 폐쇄 후 재관측이 정본이 된다).

- usage (11/01 일): Actions Linux 3,384.0분 / $20.304 (net $0) · Actions
  Linux Slim 125.0분 / $0.25 · Actions storage 589.8841 GBh / $0.198 ·
  Git LFS storage 0.7613 GBh · Enterprise Cloud(좌석, 고정비 버킷)
  0.0333 UM / $0.70 — GHEC 변동비 gross 합계 **$20.752285**, net $0.
- runs / jobs / 착지: runs 1,482 (중복 재실행 98.25%; merge_group 168 ·
  workflow_run 977) · jobs 표본 558 · **main 착지 21건(전부 2-parent
  MERGE 검증)**. C_landing_min $0.00/착지(net $0), G_landing
  $0.988204/착지.
- 비고: 11/1은 10월 후반 저활동 대비 활동 복귀일(1,979분)로, 단일 일 창
  수치를 월 전체로 외삽하지 않는다.

## 4. 낭비 원인 후보 표 (aggregate `--waste-md` 산출)

읽기 규칙:

- **달러 환산은 GHEC 라벨 잡에만 적용된 추정 참고치**다(GitHub 공개
  단가×분). Ubicloud 잡은 actual cash가 계약상 미공개(UNKNOWN)이므로
  **분만** 기록한다.
- **최상위 소비자 ≠ 최상위 낭비**: 분 소비 상위 워크플로가 낭비 상위가
  아니다. 낭비 판정은 main 착지 기여도와 중복 비율이 결합해야 한다.
- **필수 5 checks**(admission-check, bsec-integrity, debt-registry-gate,
  generation-acceptance, axiom-operational-slice)는 병합 보증의 정책상
  구성요소로 **감축 대상에서 제외**한다.

### 관측 A 상위 후보 (2026-10, snapshot `ci_cost_20261102T010928Z`)

전월 runs 21,598건 중 **95.97%가 동일 head_sha+event 재실행**(20,728건,
2661 그룹) — 중복 재실행이 이 저장소 CI 낭비의 1차 형태다.

| 워크플로 | runs | merge_group | 측정 job 분(표본) | GHEC 분 | fallback 분 | 달러 환산(추정) | 중복 비율 |
|---|---:|---:|---:|---:|---:|---:|---:|
| admission-gate-v2.yml | 677 | 313 | 372.234 | 223.267 | 148.967 | $1.2734 | 100% |
| axiom-operational-slice.yml | 409 | 131 | 121.617 | 5.583 | 116.034 | $0.0335 | 99.76% |
| landing-integrity.yml | 1987 | 1000 | 71.266 | 12.950 | 58.316 | $0.0777 | 100% |
| bsec-integrity.yml | 1077 | 576 | 52.750 | 34.250 | 18.500 | $0.2055 | 100% |
| observation.yml | 1312 | 699 | 49.450 | 38.133 | 11.317 | $0.2288 | 99.92% |

(6위 이하는 snapshot `waste.md` 전체 표 참조: `data/ci_cost/ci_cost_20261102T010928Z/waste.md`)

해석 주의: **ci-cache-publisher.yml이 runs 수 1위(8,762건, workflow_run
연발)지만 job 분 표본 기준 6위(43.5분)다** — run 수 기준 최상위 소비자와
실행시간 기준 소비자가 다르고, 달러 환산 1위(admission-gate-v2 $1.27)는
GHEC 라벨 표본 한계의 추정 참고치다. 실측 청구 권위는 usage API 합계
(gross $312.88/net $0.267)다. landing-integrity·probe-merge-queue의
merge_group 1,000건은 관측 창 상한(merge queue 재시도 연쇄)에 닿은 값이다.

## 5. 경제 지표 계약

- **GHEC**: `net cash` = netAmount 합(할인 반영 실지불), `gross` =
  grossAmount 합.
- **Ubicloud**: actual cash = **UNKNOWN**(미공개 계약). 분만 기록.
- **C_landing** = (GHEC net cash + Ubicloud actual) ÷ main 착지 수 —
  Ubicloud actual이 UNKNOWN인 동안 C_landing은 **계산 불가(UNKNOWN)**로
  표기하고, GHEC-only 하한 `C_landing_min` = GHEC net ÷ 착지 수를 함께
  제시한다.
- **G_landing** = gross ÷ main 착지 수.
- **고정비**(좌석·Enterprise Cloud 등)는 변동비 지표(C_landing·G_landing)
  분모·분자에 혼입시키지 않고 별도 라인으로 둔다.

## 6. 비교 cohort 사전 등록 (측정 전 고정)

미래 최적화 PR의 A/B 비교는 아래 cohort 정의를 **사전에** 적용한다
(post-hoc cohort 재정의 금지).

- **동일 조건**: 워크플로 path+name, 이벤트(push / merge_group 각각 별도),
  기간 길이(일 단위 동일 길이), 시간대(UTC 고정)가 모두 동일한 run만 매칭.
- **wait-run 분리**: 대기(created_at→run_started_at)와 실행
  (run_started_at→updated_at)를 별도 지표로 집계 — 혼합 금지.
- **percentile**: P50·P95 보고. 최적화 주장은 P95 기준.
- **표본**: cohort별 n 명시, n<30인 cohort는 "표본 부족"으로 유의성 주장
  금지.
- **실패·취소**: conclusion 기준으로 success와 failure/cancelled를 분리
  집계.
- **SKU 경제**: GHEC 라벨만 달러 환산(추정 참고치), Ubicloud는 분만.
- **admission SLO 판정 기준**: merge_group admission P95 ≤ 480초(8분)면
  정책 SLO 충족. 이 SLO는 **정책이지 헌법 불변식이 아니다**
  (docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md:133-135)
  — 초과가 추가 최적화 의무를 자동 발생시키지 않으며, 다음 단계는 Owner
  승인 + 복잡도 예산 경계에서만 진행한다.

## 7. Admission 대기 (mla 위임 결과)

관측 A (창 2026-10-16T00:00:00Z..2026-10-23T00:00:00Z, n=206 게이트 run,
전수 — `--no-logs` 위임):

- wall(run wall = updated_at − run_started_at, E3 §7.1): P50 740초 ·
  P90 1,082.5초 · **P95 1,105초** · mean 765.2초 (frozen
  `mla/ci_cost_mla.runs.jsonl`에서 문서화된 선형보간 분위로 산출)
- 실행 파트(dur_sum) P50 719.5초, 대기 파트(wait = gaps+residual) P90 23초
  — 대기는 짧고 실행이 지배한다.
- conclusions: success 165 · failure 41. regime/classification: 전부
  unknown/UNKNOWN_LOG — `--no-logs` 위임의 fail-closed 귀결(A2.2.7 엄격
  H 밴드 적용).
- **480초(8분) 정책 SLO 판정: 미충족(P95 1,105초)** — 단, 이 SLO는 정책이지
  헌법 불변식이 아니며(citation §6), 추가 최적화 의무를 자동 발생시키지
  않는다.

관측 B (창 2026-11-01T00:00:00Z..2026-11-02T00:00:00Z, n=21 게이트 run,
전부 success): wall P50 679초 · P90 742초 · **P95 826초** — 480초 정책 SLO
미충족. 단 n=21 < 30으로 사전등록 규칙(§6)에 따라 **표본 부족** — 이 창의
P95는 유의성 주장 없이 기록값이다. B의 admission은 mla 게이트 경로 run
21건 전수(merge_group gate)다.

## 8. ETag 304 재사용 관측 (A2)

관측 A2 (`ci_cost_20261102T014936Z`, 2026-11-02T01:49Z, 3요청) —
`--reuse-from` 관측 A:

- **budgets: 304 수용 확인** — 상태 라인 파싱으로 304를 수용하고 이전
  snapshot의 4행을 복사(`etag_304_pages=1`,
  `etag_304_reused_from=["ci_cost_20261102T010928Z"]`). CQ2 계약대로
  비페이지네이션 `--include` 프로브로 수행.
- **usage: 200 전환 — 오수용 없음** — 폐쇄월 행 1건(10/03 Git LFS
  bandwidth)이 소급 정정되어 ETag가 변경되었고, 프로브가 이를 감지해
  fresh slurp로 재수집했다(나머지 176행은 이전 관측과 동일). 이는 304
  메커니즘이 내용 변경을 정확히 추적함의 음성 대조군이며, "폐쇄월 행
  불변" 반사실의 반례로 QUIRK CQ5에 기록했다.

## 9. 재현 명령

```bash
# 관측 (예: 폐쇄월 전월)
python3 tools/ci/ci_cost_observe.py collect --obs-id ci_cost_<UTC시각>Z \
  --data-dir data/ci_cost --usage-month 2026-10 \
  --runs-since 2026-10-01T00:00:00Z --runs-until 2026-11-01T00:00:00Z \
  --jobs-window 2026-10-20T00:00:00Z/2026-10-22T00:00:00Z \
  --jobs-window 2026-10-23T00:00:00Z/2026-10-25T00:00:00Z \
  --jobs-max-runs 300 \
  --merged-since 2026-10-01T00:00:00Z --merged-until 2026-11-01T00:00:00Z \
  --mla-since 2026-10-16T00:00:00Z --mla-until 2026-10-23T00:00:00Z

# 고정 (immutable snapshot)
python3 tools/ci/ci_cost_observe.py freeze --obs-id <OBS_ID> --data-dir data/ci_cost

# 집계 (snapshot 전용 — 라이브 조회 없음, 결정론)
python3 tools/ci/ci_cost_observe.py aggregate --obs-id <OBS_ID> \
  --data-dir data/ci_cost --out data/ci_cost/<OBS_ID>/aggregate.json \
  --waste-md data/ci_cost/<OBS_ID>/waste.md
```

주석: usage 수치의 권위는 `data/ci_cost/<OBS_ID>/` snapshot이며, 본
문서의 표는 그 투영이다. 수치 갱신은 새 관측ID로만 한다(기존 snapshot
수정 금지 — fail-closed).

---

## 10. Addendum — 도구 v2 보강 4건 + 커버리지 검증 (2026-11-02, WP-B1 후속)

> 본 섹션은 1–9절에 대한 **추가(addendum)** 기록이다. 기존 수치·문구는
> 재작성하지 않는다. 읽기 전용 감사가 지적한 도구 계약 누락 4건을
> `tools/ci/ci_cost_observe.py` v2(TOOL_VERSION **2.0.0**, aggregate schema
> `axiom.ci_cost.aggregate/2`)로 보강했고, 모든 신규 수치는 freeze된
> snapshot의 재생(라이브 호출 0건)으로 산출되어 별도 파생 경로
> `data/ci_cost/<gen>/derived_v2/`에 둔다. 원본 snapshot·manifest는
> 불변이다(0444 유지, git diff 0건).

### 10.1 검증 통과 착지 정의 명시 + `base_ref=="main"` 필터 (보강 1)

- 정의(도구 코드·출력에 명시): **검증 통과 착지 = required 5 checks
  green + merge queue 통과 + 2-parent GitHub native MERGE 커밋.** 도구
  조작화는 `base_ref=="main"` 필터 + parents==2 검증이며, checks
  green·queue 통과는 GitHub merge-admission authority(AGENTS.md §2.3)의
  보장을 전제로 하고 본 도구는 재판정하지 않는다(Authority ≠ Adapter).
- freeze된 기존 수치와의 병기(기존 기록은 수정하지 않으며, **필터
  적용본이 정본**이다):

| 관측 | N_landings (v1 무필터 — 비정본 참고) | N_landings (v2 필터 — 정본) | C_landing | G_landing | 병합 창 base_ref 분포 |
|---|---:|---:|---|---|---|
| A (2026-10) | 657 | 657 | $0.000407 | $0.476233 | main 659 (그 외 0) |
| B (11/01) | 21 | 21 | $0 (GHEC-only 하한) | $0.988204 | main 21 (그 외 0) |

- **이번 두 관측에서 필터는 수치를 변동시키지 않았다**: 병합 창 내 PR은
  이미 전부 `base_ref==main`이었다. snapshot 원장의 main 외 base_ref 행
  10건(queue-probe 4 · probe/spoof-base 3 · scratch/venue-fixture-base 2 ·
  fix/mq-e2e-base-ref 1)은 전부 미병합(closed, `merged_at=null`) 또는 창
  외부 병합(2026-09-29)이라 기존 창 필터에서 이미 제외되어 있었다. 따라서
  이번 변경은 현재 수치를 바꾸지 않는 **정의 경계의 경질(hardening)**이며,
  향후 관측에서 main 외 분기 착지가 snapshot에 유입되면 v2 정의가 이를
  착지 수에서 배제한다. v1 무필터 값은 파생 산출물의
  `landing.unfiltered_verified2_count`에 비정본 참고값으로 병기된다.

### 10.2 p95 산출 (보강 2)

- `stats_block`에 p95 추가 — 기존 `percentile()` 헬퍼 재사용, P50·P90과
  동일 선형보간(index (n-1)*p, mla §stats contract). 파생 재생 결과:
  - 관측 A admission wall: P50 740초 · P90 1,082.5초 · **P95 1,105.0초**
    (n=206) — §7 기존 기록 "P95 1,105초"와 **정확히 일치**(동일 분위
    방법의 재현 확인).
  - 관측 B admission wall: P95 826.0초 (n=21) — §7 기존 기록과 일치.
    n=21<30으로 §6 사전등록 규칙상 **표본 부족** — 유의성 주장 없는
    기록값이다.

### 10.3 waste 표 2컬럼 + 필수 5 checks 비대상 각주 (보강 3·4)

- waste 표에 **착지 기여도** · **변경 위험** 2컬럼을 추가했다. 두 컬럼의
  정의는 산출물 표 각주 자체에 명시된다:
  - 착지 기여도 — main 착지 경로 소비 형태의 등급: `required_check`(필수
    5 checks 컨텍스트 제공 — 판정: workflow path stem == required
    context, 또는 표본 jobs 원장에서 해당 워크플로 job 이름이 required
    context) · `merge_queue`(merge_group 런 존재) · `none`(기여 없음).
  - 변경 위험 — 표를 근거로 한 워크플로 감축·변경의 위험 등급:
    `high`(=required_check, 필수 검증 의미 변경 위험) ·
    `medium`(=merge_queue) · `low`. FROZEN 경계 등 snapshot 밖 판단은
    미반영임을 각주에 명시(snapshot-only 관측 한계).
- **필수 5 checks 비대상 각주**: admission-check · bsec-integrity ·
  debt-registry-gate · generation-acceptance · axiom-operational-slice는
  병합 보증의 필수 검증을 소비하므로 해당 워크플로는 낭비 최적화
  **비대상**(변경 위험 `high`)임을 산출물 자체에 명시했다. A 표 기준 해당
  워크플로: `admission-gate-v2.yml`→admission-check,
  `admission-check.yml`→admission-check, `bsec-integrity.yml`,
  `debt-registry-gate.yml`, `generation-acceptance.yml`,
  `axiom-operational-slice.yml`. 감사가 지적한 top5(§4) 중
  admission-gate-v2·bsec-integrity·axiom-operational-slice가 이 등급으로
  고정되고, landing-integrity·observation은 `merge_queue`/`medium`으로
  등급화됐다.
- 산출물: `data/ci_cost/ci_cost_20261102T010928Z/derived_v2/waste.md` ·
  `data/ci_cost/ci_cost_20261102T020849Z/derived_v2/waste.md`

### 10.4 커버리지 검증 — waste 표 vs billing gross 격차의 규명 (라이브 수집 0건)

파생 aggregate JSON의 `waste_coverage` 블록으로 고정했다. **이 커버리지
비율은 B2 낭비 후보 대표성 판단의 전제다** — waste 표 est 합계는 billing
gross를 대변하지 않으며, 후보 선정은 이 한계를 전제해야 한다.

| 축 | 관측 A (2026-10) | 관측 B (11/01) |
|---|---:|---:|
| waste 표 est 합계 / billing gross | $2.3399 / $312.884971 = **0.7478%** | $1.60 / $20.752285 = **7.71%** |
| waste 표 GHEC 분 / billing Actions 분 | 401.216 / 51,747.3333 = **0.7753%** | 271.617 / 3,509.0 = **7.7406%** |
| 표본 전체 분 / billing Actions 분 | 808.467 / 51,747.3333 = 1.5623% | 298.767 / 3,509.0 = 8.5143% |
| jobs 표본 run 커버 | 513 / 21,598 = **2.3752%** | 278 / 1,482 = 18.7584% |

- **집계 대상의 경계**: jobs 원장 1,268행(A)·558행(B)은 전체 runs의 jobs가
  아니라 `--jobs-window` 창(관측당 2개 창) 내 결정론 stride 표본
  (`--jobs-max-runs 300`)이다 — A에서 513개 run만 커버한다(2.38%). 나머지
  21,085 run(97.62%)의 실행 분은 billing에는 포함되지만 waste 표 분모
  밖이다.
- **미커버 잔여의 실체**(`uncovered_remainder` 블록):
  1. jobs 표본 미커버 runs(위 수치) — 지배 성분.
  2. 비러너 청구 성분: 스토리지·Git LFS bandwidth 등 $12.836971(A) ·
     $0.198285(B) — 러너 분 기반 표와 별개의 billing 성분.
  3. fallback(Ubicloud 등) 러너 분 407.25분(A) · 27.15분(B) — actual cash
     UNKNOWN(Q7/Q11)으로 달러 환산 불가, 분만 기록.
  4. 좌석·Enterprise Cloud 고정비 — 변동비 집계 밖(§5 계약, A 월
     $20.32는 §2 표 참조).
  5. waste 표 top-25 절단 — 이번 관측에서는 미구속(측정 워크플로 17개(A)
     ·16개(B)가 전부 표 안). 즉 이번 격차의 지배 성분은 표 절단이 아니라
     **jobs stride 표본 경계**다.
- 해석 계약: 분자는 GHEC 라벨 잡 × 공개 단가의 표본 추정 참고치, 분모는
  usage API 실측 gross(비러너 SKU 포함)로 성격이 다르다. 이 비교는 청구
  대사(reconciliation)가 아니라 **B2 후보 대표성의 하한 고정**이다.

### 10.5 파생 산출물과 결정론 재생 증명

- 파생 경로: `data/ci_cost/<gen>/derived_v2/{aggregate.json, waste.md,
  derived_manifest.json}`. 파생 manifest는 도구 버전(TOOL_VERSION 2.0.0 +
  tool sha256 `e6ccf07f5433c5be3d5602f19482e2ee550c9c27cd0264e08b5e9ea7abbf30ce`),
  원본 manifest sha256, ledger sha256, `live_api_calls: 0`을 기록한다.
- 재생 명령(세대별 동일, 기존 §9 명령의 원본 경로 덮쓰기 없음 — v2 재생은
  반드시 파생 경로로 수행):

```bash
python3 tools/ci/ci_cost_observe.py aggregate --obs-id <GEN> --data-dir data/ci_cost \
  --out data/ci_cost/<GEN>/derived_v2/aggregate.json \
  --waste-md data/ci_cost/<GEN>/derived_v2/waste.md \
  --derived-manifest data/ci_cost/<GEN>/derived_v2/derived_manifest.json
```

- 재생 2회(동일 snapshot + 동일 도구 버전, 라이브 호출 0건) 결과 — 3개
  산출 파일 모두 재생 간 sha256 동일:
  - A(`ci_cost_20261102T010928Z`): aggregate
    `e0c6a2c7e9a3a22aed47f95616743e9e9ada93e5c468cba194b1f8bb05df15b6` ·
    waste.md
    `69cd95f333cad3d761065cef430f61d69d00532e754fe3ee724d67d9348467e9` ·
    derived_manifest
    `71c55b23475b4a2cc8d09cc4886278d44984007bd0b4f570201e4a333a7f58b7`
  - B(`ci_cost_20261102T020849Z`): aggregate
    `7e5b1dbcc415cb3e8757ab021c08f7060d72b76916a249b4f9075beb812cb8b0` ·
    waste.md
    `33016ba76950f0ccd3b1409a5decf14c0ccad1dfae2d4b593d541eb1feb30285` ·
    derived_manifest
    `deaed9df8c12e072152558449235f86489a2abc74d57c0215744346ea6f27a7c`
- 원본 snapshot 무결성: `manifest.json`·`ledger/*.jsonl` 0444 유지,
  v1 aggregate.json·waste.md 미변경(git diff 0건), 재수집 없음.
