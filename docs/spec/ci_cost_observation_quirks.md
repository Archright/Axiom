# CI Cost Observation Quirks — GitHub billing/usage·Actions runs 관측 툴체인 (2026-11-02)

> AGENTS.md §0.5 Quirk Mandate — `tools/ci/ci_cost_observe.py` (WP-B 1단계 CI
> 비용 관측 도구) 구현·실측 중 발견된 quirk의 정식 문서다. 인접 문서:
> `docs/spec/ci_provider_failover_quirks.md` (Q18 — `gh api` 에러 본문의
> `>file` 오염 계약), `docs/spec/gh_run_observation_quirks.md`.
>
> Tagging: **[measured]** = 2026-11-02 `gh api` 라이브 실측 (관측 세션:
> `data/ci_cost/` 원장 + 본 문서 기술). **[derived]** = 관측에서 도출된
> 설계 판정.

---

## CQ1 — 조직 billing usage 엔드포인트는 `page` 파라미터를 무시한다: Link 헤더 페이지네이션 전용

### Symptom [measured]

`GET /orgs/Archright/settings/billing/usage?year=2026&month=10&per_page=100&page=2`
가 **page=1과 동일한 첫 100행**을 반환한다. `page` 명시 루프(`page=1..200`)는
매 페이지 100행씩 중복 누적되며 종료 조건(100행 미만)이 영원히 성립하지
않는다 — `ci_cost_observe.py`의 runaway 가드가 **page 201에서 HARD-FAIL로
발화**하여 실측 확정되었다(1차 수집 시도, ledger 35,400 중복행 → 해당 미동결
관측 디렉터리는 폐기).

### Documented basis

- **[documented]** REST billing usage
  (https://docs.github.com/en/rest/billing/usage, fetched 2026-11-02): 응답은
  표준 Link 헤더 페이지네이션 계약을 따른다 — `page` 요청 파라미터에 대한
  별도 언급은 없다. GitHub의 Link-헤더 엔드포인트 다수는 `page`를 받지만,
  이 엔드포인트의 실측 커서는 `page`를 무시한다(문서 침묵 + 실측 부정 합성 →
  문서만으로는 예측 불가).

### Sanctioned workaround

- fresh 수집: `gh api --paginate --slurp` **1회 호출**로 전체 페이지를 배열로
  수입한다(`ci_cost_observe.py GhApi.get_slurp`).
- `page` 파라미터를 붙이는 재시도는 금지 — 중복 누적이며 종료 불가능하다.

---

## CQ2 — `gh api --paginate` + `If-None-Match`(304): "unexpected end of JSON input"로 파싱 사망한다

### Symptom [measured]

저장된 ETag로 `gh api --paginate <usage-url> -H "If-None-Match: <etag>"`
재조회 시 GitHub은 **304 Not Modified(빈 본문)**을 반환하고, gh는 빈 본문을
JSON으로 파싱하려다 stderr에 `unexpected end of JSON input`을 내고 유의미한
stdout 없이 끝난다 (관측 세션 2026-11-02 — 파이프 없는 단독 실행에서도 동일).

### Documented basis

- **[documented]** gh CLI는 304를 "수정 없음" 성공으로 추상화하지 않는다 —
  응답 본문이 비어 있으면 jq/파서 체인이 실패 출력을 낸다. `--include` 없는
  조건부 단일 GET은 304에서 빈 stdout을 반환한다(상태 라인 미노출).

### Sanctioned workaround

- 조건부 재조회(ETag 재사용)는 **비페이지네이션 단일 프로브 + `--include`**로
  수행한다 — 상태 라인(`HTTP/2.0 304 Not Modified`)과 ETag 헤더를 직접
  파싱할 수 있다(`ci_cost_observe.py GhApi._parse_include`).
- ETag 재사용 스코프는 **endpoint-월 단위**다: 304 → 이전 snapshot의 해당 월
  ledger 행 전체를 복사(본문 미수신), 200 → 전체 재수집. 페이지 단위 etag는
  이 엔드포인트에서 주소 지정 불가(CQ1)하므로 성립하지 않는다.
- page-1 스코프 etag의 304는 **폐쇄월(closed month)에서만 건전하다** —
  진행 중 월(open month)은 적립(accrual)으로 후속 페이지가 변할 수 있으므로
  fresh 수집해야 한다 [derived].
- 304 수용은 (a) 상태 라인 확인 또는 (b) exit 0 + 빈 본문 + 이전 snapshot
  존재의 결합으로만 한다. Q18과 동일하게 "파일/본문 존재"는 신뢰 근거가
  아니다.

---

## CQ3 — Actions runs 필터 조회의 `total_count`는 정확히 2500으로 캡된다: 절대 신뢰 금지

### Symptom [measured]

2026-11-02 동일 시점 두 조회가 **정확히 같은 2500**을 반환했다:

- `GET /repos/Archright/Axiom/actions/runs?created=2026-10-01T00:00:00Z..2026-10-31T23:59:59Z&per_page=1`
  → `total_count: 2500`
- 동일 창에 `event=merge_group` 필터를 추가한 조회 → `total_count: 2500`

전 이벤트 합계와 단일 이벤트 합계가 수학적으로 같을 수 없으므로 둘 중
하나 이상은 캡 아티팩트다. 한 편 6시간 서브윈도 조회(예: 10/25 00:00–06:00Z,
300건)는 자체창 합계로 신뢰 가능한 값을 낸다. census 원장
(`data/ci_provider/census_20261101T125932Z/`)이 2시간 서브윈도로 수집한
것과 동일한 제약의 재확인이다.

### Sanctioned workaround

- 기간 수집은 **고정 서브윈도(6h) × 완전 페이지네이션**으로만 수행하고,
  `total_count`는 절대 완결 판정에 쓰지 않는다.
- 서브윈도가 페이지네이션 예산(관측값 990건)에 도달하면 **반분 재귀**로
  내려간다(`ci_cost_observe.py _collect_runs_window`, depth ≤ 5) —
  `pr_latency_attribution.py list_runs`의 halving 선례와 동일 계약.

---

## CQ4 — 조직 레벨 과금 항목(seats)은 `repositoryName`이 빈 문자열이다: 저장소 필터가 무단 탈락시킨다

### Symptom [measured]

관측 `ci_cost_20261102T010928Z` usage 원장 177행 중 Enterprise Cloud 30행
(product `ghec`, unitType `UserMonths`, 일 적립 0.032258064 UM × 30일 ≈
0.97 UM / $20.32)은 **`repositoryName: ""`** 을 갖는다. 집계의 저장소 필터
(`repositoryName == repo`)가 이 행을 조용히 탈락시켰고, 고정비 버킷
(`fixed_cost_usd`)이 빈 채로 출력되었다(2026-11-02 aggregate 1차 출력에서
확정).

### Documented basis

- **[measured]** billing usage API의 조직 공통 과금(좌석·Enterprise Cloud)은
  저장소 귀속 행이 아니므로 `repositoryName`가 빈 문자열이다. 저장소 스코프
  소비 집계와 조직 고정비는 **다른 스코프**다 — 전자의 필터를 후자에
  재사용하면 무단 탈락이 된다.

### Sanctioned workaround

- `repositoryName`이 빈 행 중 `UserMonths`·Enterprise Cloud는 **고정비
  버킷(`fixed_cost_usd`)으로 가로채고**, 저장소 소비 필터는 변동비(분·GBh)
  집계에만 적용한다. 경제 지표(C_landing·G_landing)는 고정비를 혼입하지
  않는다(계약: 고정비 별도 라인).

---

## CQ5 — 폐쇄월 usage 행도 후행 정정된다: 304 미수락(200 전환)이 정확히 작동한다

### Symptom [measured]

관측 A(`ci_cost_20261102T010928Z`, usage 수집 01:09:30Z)와 관측 A2
(`ci_cost_20261102T014936Z`, 프로브 01:49:38Z) 사이 — 월 종료 34시간 후 —
GitHub가 **폐쇄월(2026-10) 행을 정정했다**: Git LFS bandwidth 2026-10-03행이
quantity 0.022749375 → 0.033504119 GB, gross $0.001990562 → $0.002931598로
변경되었고(나머지 176행 불변), 엔드포인트 ETag도 `4e5125a1…` →
`4f6fefe3…`로 바뀌었다. A2의 조건부 프로브는 정확히 **200**을 받아 fresh
slurp로 재수집했고(3요청), 같은 실행에서 budgets 엔드포인트는 **304**로
4행을 이전 snapshot에서 복사했다(`etag_304_pages=1`).

### Documented basis

- **[measured]** "폐쇄월 ⇒ 행 불변"은 성립하지 않는다 — 월 종료 후에도
  소급 정정이 도착한다. 정정은 **ETag에 반영되므로**, endpoint-월 스코프
  조건부 프로브(CQ2 계약)는 정정을 304 오수용 없이 200 fresh 재수집으로
  처리한다. 304 미수락 경로의 실측 음성 대조군이 된다.

### Implications

- 재현 대조의 미세 차이는 accrual 외에 **소급 정정**으로도 발생한다 —
  baseline 문서의 차이 해석 규칙(관측시각 명기)이 이 근거를 인용한다.
- "폐쇄월 304 안전성"의 근거는 행 불변이 아니라 **ETag가 정정을 추적한다는
  사실**이다. ETag가 정정을 놓치는 반사실은 관측되지 않았으며, 발견 시
  fail-closed로 재수집한다.

---

## Deterministic rules

1. usage 수집은 `--paginate --slurp` 1회 호출이다(CQ1) — `page` 루프는
   중복 누적이며 종료 불가능하다.
2. ETag 304 재사용은 endpoint-월 스코프 프로브 + 이전 snapshot 행 복사다
   (CQ2) — 폐쇄월에서만 건전하고, 304 수용은 상태 라인 확인을 전제한다.
3. `total_count`는 완결 판정 근거가 아니다(CQ3) — 서브윈도 × 완전
   페이지네이션 × 반분 가드가 유일한 완결 경로다.
4. 위 반사실(오염 ledger·미완료 collect)은 관측ID 폐기로만 처리한다 —
   미동결 snapshot의 부분 수용은 없다(fail-closed).
5. 조직 고정비(seats·UserMonths)는 repositoryName 빈 문자열로 식별해
   `fixed_cost_usd`로만 집계한다(CQ4) — 저장소 소비 필터·경제 지표에
   혼입되지 않는다.
6. 폐쇄월 행도 소급 정정될 수 있다(CQ5) — 조건부 프로브의 200 전환은
   fresh 재수집으로만 처리하고, 304 수용은 ETag 일치에만 근거한다. 재현
   대조의 미세 차이는 accrual·소급 정정의 결합으로 해석한다.
