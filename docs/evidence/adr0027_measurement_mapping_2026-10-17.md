# ADR-0027 측정조건 ↔ 증거 매핑 — 상태 결정 입력 증거 (2026-10-17)

> **문서 목적**: ADR-0027(`docs/adr/0027-queue-delegation.md`, Status **PROPOSED (2026-09-29)**) 상태 결정의 **입력 증거**를 제공한다. **본 문서는 결정이 아니다.**
> **상태 변경 권위**: 상태 변경은 ADR 자체 규정의 재의결 절차로 **아키텍트만** 가능하다(`:515-516` "γ 판정 시 본 ADR은 재의결 대상"). 본 문서는 그 재의결에 소비될 조건↔증거 매핑·결핍 분류·개정 초안을 기록할 뿐, 상태를 변경하지 않는다.
> **조사 성격**: 2026-10-17 읽기전용 조사(저장소 문서·GitHub API 실측·런 ID 대조)의 정식화. 조사에서 미확정으로 남은 항목은 §6에 미확정 그대로 기록한다.
> **반입 위치**: 결정 입력용 초안 — `docs/evidence/` 반입 여부·시점은 아키텍트 결정 사항.

---

## 1. 조건 원문 추출 (docs/adr/0027-queue-delegation.md)

### 1.1 Status·꼬리 조건

- `:5-9` — "**PROPOSED (2026-09-29)** … 본 ADR은 착지 authority의 **플랫폼 큐 위임**을 결정·기록하고, 그 확정 조건을 **Phase 0 측정(α/β)**에 결속한다. 측정 완료 전 "착지 형상 확정" 선언 금지 — 본문의 형상 서술은 전부 측정 의존 선언이다."
- `:515-516` — "*PROPOSED — Phase 0 측정(α/β) 완료 전 "착지 형상 확정" 선언 금지. γ 판정 시 본 ADR은 재의결 대상이다.*"
- `:240-241` — "α/β/γ 측정·프로브 실행 … 실측 전까지 본 ADR의 형상 서술은 예정 계약이며 확정 아님" (측정 의존 선언). 즉 ADR은 **운영 존재가 아니라 측정 계약에 status를 결속**한다.

### 1.2 Phase 0 측정 계획 (`:208-223`)

- `:210-214` — scratch 규칙셋(`queue-probe` ref 스코프)에 `merge_queue` 규칙(merge_method MERGE · min/max_entries_to_merge 1/1 · max_entries_to_build 2 · check_response_timeout_minutes 60) + required_status_checks(probe 워크플로 check) + pull_request(merge 전용)를 설치한다 — **main에는 merge_queue를 활성화하지 않는다**.
- `:215-220` — `probe-merge-queue.yml` 복원(4b56ad4fc^에서 복구 + artifact-download 결함 수정 + push 스코프 queue-probe): merge_group 페이로드(… head_commit.tree_id …)를 `merge-group-payload-<sha>` 아티팩트 + job summary에 기록하고, 착지 후 judge가 L을 맞대어 `PROBE_VERDICT`를 낸다(질의 4종: L==G · parent1(L)==B · parent2(L)==G · tree(L)==tree(G) + parents(L) 목록).
- `:221-223` — 측정 ≥2회(순차 PR). 판정: **α** = parents(L)==[B, H_PR](H_PR = PR head); **β** = parent2(L)==G ∧ tree(L)==tree(G); **γ** = 그 외 — γ 판정 시 **즉시 STOP·재의결**(본 ADR 확정 보류, 결과 보고).

관련 실측·선언:

- `:36-39` — probe 이력 실측: 과거 11회 런은 **전수 artifact-download 단계에서 실패**해 judge가 1회도 실행되지 않았다(`PROBE_VERDICT` 부재 — 측정 0건).
- `:104-116` — 측정 의존 선언(불변식 4/6/7 재서술): 불변식 6 (parents)은 큐 경로에서 사전 선언하지 않는다 … γ 판정 시 즉시 STOP·재의결.
- `:235-236` — main ruleset에는 merge_queue를 활성화하지 않는다(Phase 0은 queue-probe 스코프 한정).
- `:242-245` — 운영 전환 범위 밖: main ruleset merge_queue 활성화 등은 모두 본 ADR 착지 후 **Phase 1+**.
- `:452-454` — Amendment E: `checks: read` 결여 → 403, 재arm 메커니즘 전체가 no-op이었다(2026-10-14~15 표본 **7/7**).
- `:509-511` — 계획·실행 증거 문서는 **S3 착지 시 `docs/evidence/`에 기록**된다. 근본 결함 실측(7/7 no-op 표본)은 같은 날 사용자 검증 기록에 근거한다.

### 1.3 S1/S2/S3 단계의 소속 정정 (매핑 표 반영 전제)

- ADR 본문(Phase 0)에 S1/S2/S3 단계 정의는 **없다**. Phase 0 단계는 References `:251-252`의 5단계("기록 → 표면 등록 → probe 복원 → scratch 측정 → 증거")다.
- S1/S2/S3는 **Slice B(re-arm) 계획의 단계**로 Amendment E(`:444-447`)가 참조한다 — "S1 = 본 개정 + `merge-queue-rearm.yml` 하드닝, S3 = dry-run 채널 실측 검증".
- 따라서 §2 매핑 표는 Phase 0 측정 조건(표 1)과 Slice B·운영 조건(표 2)을 **구분해 배치**한다.

---

## 2. 조건 ↔ 증거 매핑

**환경 정의** (파라미터 델타 상세는 §4):

- **측정환경** — Phase 0 scratch (2026-09-29): ref `queue-probe` · check_response_timeout_minutes **60** · required check `probe-capture` 1개 · ruleset 24164452(`queue-probe`)+24162466(`queue-probe-scratch`) — close-out 철수 완료(→404).
- **운영환경** — live main (ruleset 20303214, 2026-10-17 API 실측): ref `~DEFAULT_BRANCH` · **120분** · required check `admission-check`+`bsec-integrity` 2개 · 활성 중.

**상태 열 정의**:

- **①역사적 완료** — 당시 요구된 측정·판정 절차가 수행됐는가
- **②현재 재현성** — 지금 독립 감사·재현 가능한 자료가 남았는가
- **③정책 상태** — ADR 자체 규정상 변경 허용 여부

### 표 1 — Phase 0 측정 조건 (측정환경 계약)

| 조건 (ADR 출처) | 증거 (run ID·문서) | 측정환경 | 운영환경 | ①역사적 완료 | ②현재 재현성 | ③정책 상태 |
|---|---|---|---|---|---|---|
| scratch 규칙셋 설치 (`:210-214`) | `merge_queue_probe_2026-09-29.md` §1-2 — 24164452 `queue-probe` 신규 + 24162466 동일 규칙 PUT 정렬, API echo · 삭제 기록 `merge_queue_operation_2026-09-29.md` §잔여(24162466·24164452 → 404) | 설치→철수 완료 | — | **충족**(과거형 — 의도된 일시성) | **제한** — ruleset 삭제·API 원문 JSON 미보존(§3 결핍 4), 문서가 유일 기록 | **정합** — Phase 0 한정 설치·비활성 선언(`:235-236`)과 일치 |
| probe 워크플로 복원+결함 수정 (`:215-220`) | `.github/workflows/probe-merge-queue.yml` 존재(재도입 `d275c71c5`, FIX-1~6 주석) · `config/repository_surface.json` v30 등록(description) | 복원 완료 | — | **충족** | **있음**(파일·surface 등록 현재 조회 가능) | **정합** |
| payload capture (`:215-220`) | run **39027894198** artifact 직접 다운로드 — schema v2 전 필드 확인(G/B/headRef/treeId/runId/capturedAt) · merge_group 총 **196런**, 최근 30/30 success | capture ✓ | capture ✓(196런) | **충족** | **있음**(아티팩트 보존 한계 내) | **정합** |
| judge PROBE_VERDICT 4질의 — scratch (`:219-220`) | `merge_queue_probe_2026-09-29.md:57-58·:80-82` 원문 — judge 런 **36537172536·36537749568**(push@queue-probe, success 실측) | 2건 자동 판정 | — | **충족** | **있음**(런 기록+원문 인용) | **정합** |
| 측정 ≥2회, 순차 PR (`:221`) | Run1=PR #361, Run2=PR #363 — Run2의 B가 Run1의 L(순차 체인 실측) | 2/2 | — | **충족** | **있음** | **정합** |
| **α 판정** (`:221-222`) | 2/2 α — parents(L)==[B, H_PR], L==G, tree(L)==tree(G) | 2/2 α | 수동 재현 1/1 α(#907 — 아래 행) | **충족** | **있음** | **정합** — γ 아님 → STOP 트리거 없음 |
| β (`:222`) | parent2(L)==G **false** 양쪽(parent2 = H_PR) | 미성립 관측 | — | **충족**(판정 절차 수행됨 — α 성립 하 미성립은 정상 결과) | **있음** | **정합** |
| γ (`:222-223`) | 없음 | 트리거 0건 | 트리거 0건 | **해당 없음**(트리거 미발생) | — | **정합** — STOP·재의결 트리거 없음 |
| judge PROBE_VERDICT — 라이브 main 큐 | judge는 push@queue-probe/dispatch 전용 → **라이브 착지 196건에 자동 판정 0건**. 대체 재현: **2026-10-17 PR #907 수동 판정** — payload 아티팩트(run 39027894198)+API: L(`7ea20436`)==G ✓ · parent1==B(`18b18009`) ✓ · parent2(`1816c4130`)==G ✗ · tree(`950285b0`)==treeId ✓ → **α** | 2건 자동 | **자동 0건 · 수동 1건(#907)** | **충족** — ADR 계약은 scratch 측정에 결속(`:5-9`)이며 라이브 자동판정은 계약 항목 아님 | **부분** — 자동 레코드 부재(§3 결핍 2), 수동 재현 기록은 본 문서 §2 | **재의결 참고** — α 형상의 운영환경 이전 가능성을 #907 수동 판정이 보강 |

- 주: ruleset `23916707`(cas-probe-scratch)은 P1c update-block 실험으로 본 조사와 무관 — 조사 과정에서 배제 확인.

### 표 2 — Slice B(re-arm)·운영 조건 (운영환경 계보)

| 조건 (출처) | 증거 (run ID·문서) | 측정환경 | 운영환경 | ①역사적 완료 | ②현재 재현성 | ③정책 상태 |
|---|---|---|---|---|---|---|
| 7/7 no-op 발견·수정 (Amendment E `:452-454`) | ADR Amendment E 본문 + `slice_b_s3_validation_2026-10-15.md` §2-3 — dry-run 채널이 결함 2건 발견→수정 커밋 명시(`53fe4c2b7`·`1fb0748af`) | — | re-arm 채널 | **충족** | **있음**(S3 문서) | **정합** — Amendment E가 결정 권위 |
| S1 (Slice B 단계 — Phase 0 아님, `:444-447`) | PR #843 착지 `84346c91a`(`slice_b_s3_validation_2026-10-15.md` §4), Amendment E | — | 착지 완료 | **충족** | **있음** | **정합** — Slice B 계획은 사용자 승인(`:508-511`) |
| S2 (Slice B 단계) | `slice_b_s2_cold_repro_2026-10-15.md` — 런 **38710338905·38711735376**, reproduced-guarded-suppressed | — | 재현 완료 | **충족** | **있음** | **정합** |
| S3 — 증거문서 착지 포함 (`:509-511`) | `slice_b_s3_validation_2026-10-15.md` — dry-run 5경로 전수 + "S3 착지 시 docs/evidence 기록" 이행 | — | 착지 완료 | **충족** | **있음** | **정합** |
| 라이브 큐 운영 (`:242-245` — Phase 1+ 범위) | ruleset 20303214 live spec(merge_queue 활성) · MG 런 **#895 39000589841 / #900 39004833947 / #905 39011781572 / #907 39027894424** 전부 success 실측 · main tip이 큐 MERGE 커밋 | — | 활성 | **충족**(운영 이행) | **있음**(live spec·런 기록) | **범위 밖 이행** — `:242-245`가 Phase 1+로 명시; ADR status 결속과 별개 계층 |
| 비상창 계보 | `emergency_evaluate_window_2026-10-12.md`(org 16분16초+repo 66초) · `emergency_evaluate_window_2026-10-14.md`(8.293초, ruleset history 교차검증) | — | 기록 | **충족** | **있음** | **정합**(주변 계보 기록) |
| Amendment A-D 계보 | A=2체크 개정(라이브 ruleset과 일치, 2026-10-12) · C/D=`merge-queue-rearm.yml` v80 등록+금일 15건 전부 success(Amendment D run-name 인코딩 live) | — | 기록 | **충족** | **있음** | **정합** — 각 Amendment가 결정 권위로 기록 |

**핵심 발견**: 측정 계약은 **2026-09-29에 이미 이행**됐다(2×α · γ 없음 · judge PROBE_VERDICT 원문 · 증거문서 v30 CONTROLLED 등록) — 그런데도 Status는 한 번도 갱신되지 않았다. 두 사실(큐 운영 중 · 계약 충족)은 **서로 다른 증거 계층**에서 성립하며, 본 표는 이를 별도 행·열(측정환경/운영환경, ①/②/③)로 유지한다.

---

## 3. 결핍 4건 분류 — 원 수용조건 위반 여부

**조사 결과: 4건 전부 "사후 감사 가능성/결정기록 문제"다.** α/β/γ 판정 · ≥2회 측정 · 증거문서 착지 등 **원래 Phase 0 수용조건은 전부 충족**됐다(§2 표 ①열). 아래 결핍은 원 수용조건 위반이 아니라, 그 이후의 감사·기록 계층 문제로 분류된다.

| # | 결핍 | 원래 Phase 0 수용조건이었는가 | 분류 | 근거·영향 |
|---|---|---|---|---|
| 1 | C3 30일 서베이(경합 164건 · transient 18.9%)의 **독립 증거 문서 부재** | **아니오** — Phase 0 측정 계약과 무관한 Amendment D의 근거 자료 | **사후 결정기록 문제** | Amendment D `:409`가 인용하는 유일 출처가 ADR 자체. docs/evidence·docs/audit·docs/agents·data/ 전수 키워드 검색("164건", "경합 사례", "서베이")에서 **원 계산 경로 미발견** — AGENTS.md §0.11(숫자=원 계산 경로) 요구와 긴장 |
| 2 | **라이브 큐 경로의 자동 PROBE_VERDICT 부재** | **아니오** — scratch 2건 judge 기록으로 ADR 계약(측정환경)은 충족 | **사후 감사 가능성 문제** | 라이브 착지 196건에 자동 판정 0건. 수동 재현(#907, α — §2 표 1)으로 보강 가능하나 자동 판정 레코드는 없음 |
| 3 | **60→120분 파라미터의 결정 기록 부재** | **아니오** — ADR이 고정한 60분은 scratch 한정이며 main은 Phase 1+ 범위 밖(`:242-245`) | **결정기록 문제** | E1(`merge_queue_operation_2026-09-29.md`)이 "PUT diff 3항목"으로 관측만 기록 — 120 선택의 근거·승인 문서 없음. 귀속 기록은 §4 |
| 4 | scratch ruleset의 API 응답 **원문 JSON 미보존** | **아니오** — 설치·철수 자체는 수용조건대로 수행됨 | **사후 감사 가능성 문제** | 요약 기술만 남고 ruleset은 삭제되어 **재검증 불가** — 복원 불가 항목(§5·§6 참조) |

---

## 4. 파라미터 델타 + 귀속

| 파라미터 | ADR draft (Phase 0 scratch 계획 `:210-214`) | scratch 실측 (2026-09-29) | LIVE main 20303214 (2026-10-17 API) | 델타 |
|---|---|---|---|---|
| 적용 ref | `refs/heads/queue-probe`, "main 미활성화" | queue-probe ✓ | `~DEFAULT_BRANCH`(main) | **main 활성화 = Phase 1+ 이행**(`:235` 금지는 Phase 0 한정 선언) |
| merge_method | MERGE | MERGE ✓ | MERGE | 없음 |
| min/max_entries_to_merge | 1/1 | 1/1 ✓ | 1/1 (wait 0) | 없음 |
| max_entries_to_build | 2 | 2 ✓ | 2 | 없음 |
| check_response_timeout_minutes | **60** | 60 ✓ | **120** | **2배 — 60→120 선택의 결정 기록 없음**(E1이 PUT diff로 관측만 기록) |
| grouping_strategy | (미지정) | ALLGREEN | ALLGREEN | ADR이 지정 안 한 값이 live에서 하중 |
| required checks | probe 워크플로 check 1개 | `probe-capture` 1개 ✓ | `admission-check`+`bsec-integrity` 2개 | **Amendment A(2026-10-12)로 개정 정합** |
| strict | P5: strict=false 전환 예정 | strict false | `strict_required_status_checks_policy=false` | P5대로 이행 ✓ |
| bypass_actors | `[]` 유지 | — | `[]` | 없음 |
| 현재 존재 | 측정용 일시 설치 | **삭제 완료**(close-out, 24162466·24164452 → 404) | 활성 | scratch는 철수 — 재현 불가, 문서가 유일 기록 |

**귀속 기록 (attribution)**:

- **60→120 델타는 ADR 개정을 요구하지 않는다.** ADR이 고정한 파라미터(60분 포함)는 scratch 규칙셋에 한정(`:210-214`)이고, main 활성화는 ADR 자체가 "범위 밖 Phase 1+"(`:242-245`)로 명시한다. 본 절의 기록은 **귀속 명시**가 목적이다 — 표가 이 귀속을 밝히지 않으면 draft-vs-live 불일치로 오독된다.
- required checks(1→2)는 Amendment A(2026-10-12), strict는 P5 — 각각 **별도 결정 권위**의 개정 기록이 이미 존재해 정합이다.
- grouping_strategy ALLGREEN은 ADR 미지정 값으로, scratch→live로 이어져 하중됐다 — 계약 귀속이 없는 값임을 본 기록으로 명시한다.
- ADR을 **운영 파라미터의 SSOT**으로 만드는 것은 §0.12의 명시적 계약 개정(범위 확장)이 필요한 별도 판단 사항이다 — 본 문서는 그 판단을 하지 않는다.

---

## 5. 개정 초안 (첨부 — 승인 대기)

**이 절은 첨부 초안이며 승인 대기다 — 상태 플립이 아니다.** 아래 문안은 아키텍트 재의결에서 승인돼야만 효력이 있으며, 본 문서는 ADR 파일을 수정하지 않는다. 최종 상태값·확정일은 재의결에서 확정된다.

### 5.1 상태 전환 제안 문안 (초안)

> **Status 개정 (초안 — 미발효)**
> `**PROPOSED (2026-09-29)**` → `**ACCEPTED (확정일: 재의결 시 기재)** — Phase 0 측정 계약 이행 확인: 2×α · γ 없음(2026-09-29 — docs/evidence/merge_queue_probe_2026-09-29.md, judge PROBE_VERDICT 원문 :57-58·:80-82) · 운영환경 수동 재현 α(2026-10-17, PR #907)`.
>
> 꼬리 각주(`:515-516`) 갱신 초안: "PROPOSED — Phase 0 측정(α/β) 완료 전 '착지 형상 확정' 선언 금지. γ 판정 시 본 ADR은 재의결 대상이다." → "Phase 0 측정 완료(2×α, γ 없음 — 2026-09-29). 본 ADR의 상태 전환은 아키텍트 재의결로 확정함(확정일 기재)."

근거: §2 표 1(측정 계약 이행 — ①열 전부 충족) · §2 표 2(운영 이행 계보) · §4(파라미터 귀속). γ STOP 트리거는 미발동(`:221-223`) — 재의결 개시는 γ 의무가 아니라 미갱신 Status의 해소를 위한 아키텍트 판단 사항이다.

### 5.2 결핍 보완 항목 (필요 시 — 개정 승인과 함께 판단)

1. **C3 원계산 경로 확보 (제안)** — 결핍 1. 현재 전수 키워드 검색에서도 원 계산 경로가 미발견이므로, 경로·데이터를 확보해 문서화하거나 해당 수치(164건·18.9%)의 인용을 정정하는 방향. 실행 여부·방식은 미확정(§6).
2. **라이브 PROBE_VERDICT 보강** — 결핍 2. 본 문서 §2의 #907 수동 판정 기록을 보강 기록으로 활용할 수 있다. 해소 방식(수동 판정의 정기 문서화 vs 자동 판정 채널 확장)은 미확정(§6).
3. **60→120 결정 기록** — 결핍 3. 개정 불필요(§4 귀속). 별도 근거 문서의 복원·작성 여부는 미확정(§6).
4. **scratch 원문 JSON** — 결핍 4. ruleset 철수·미보존으로 **복원 불가**. "보완 불가 항목"으로 명시 수용할지 여부는 아키텍트 판단 사항(§6). 현 상태에서 문서 요약 기술이 유일 기록이다.

---

## 6. 결정 요청 (아키텍트)

본 문서는 결정이 아니라 **결정 요청**이다. 아래 3개 항목의 판단을 요청한다.

1. **재의결 개시 여부** — ADR-0027 상태 재의결 절차를 개시할 것인가. (측정 계약 이행은 §2에서 확인됨; γ 트리거 없음 — 개시 여부 자체는 아키텍트 권한.)
2. **개정 승인** — §5.1 초안 문안의 승인·수정·반려(최종 상태값·확정일 포함).
3. **결핍 보완 우선순위** — §3의 4건 중 보완할 항목과 순위. 보완 불가 항목(결핍 4)의 명시적 수용 여부 포함.

**미확정 항목 명시적 목록** (조사에서 확정되지 않아 본 문서가 판단을 대신하지 않는 항목):

- C3 서베이(경합 164건 · transient 18.9%)의 **원 계산 경로** — 미발견.
- 라이브 큐의 **자동 PROBE_VERDICT 채널** — 부재. 해소 방식(수동 문서화 vs 자동화 확장) 미확정.
- **60→120분 선택의 근거·승인 기록** — 부재(귀속 기록은 §4로 처리).
- scratch ruleset **API 응답 원문 JSON** — 미보존, 복원 불가(문서가 유일 기록).
- ADR의 **운영 파라미터 SSOT화 여부** — §0.12 명시적 계약 개정 대상, 별도 판단.
- **최종 상태값·전환 시점** — 아키텍트 재의결 권한(본 문서는 §5.1 초안까지만 제공).

---

증거 보존 유의: GitHub 실행 기록 90일 보존 한계·아티팩트 30일(2026-10-01 정책 — `slice_b_s3_validation_2026-10-15.md` §7). 본 문서가 런 ID·판정 원문을 병기하는 근거다.
