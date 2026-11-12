# ACT2-R0 · Coverage Matrix (35행 5축 재구성 투영 + OPEN predicate)

> 정본: `coverage-matrix.json` (이 파일은 사람이 읽는 projection — 수치의 권위는 JSON에 있다)
> 원자료: agent-1 5축 표 (35행) — `session .../agent-e2z3gvpp/output.log` §1
> subject revision: `c75502ceedb5ed2a37b7b5e4744fc71313682859` (nim-stew)
> 갱신: OPEN predicate 도출 적용 (historicalTruth 보존 + currentTruth=OPEN 파생) — 2026-10-01
> 재갱신(2026-10-01): proof-atom getBitsBE run BLOCKED (run terminal) — lastVerdict=blocked, currentTruth=OPEN 유지, atom evidence 이적, `rules.campaignStateTransition` 규칙 추가

---

## 권위 계층 (Authority Hierarchy)

1. **현재 authority** — Current manifest (`data/manifest` 계열) + current canonical result (`experiments/act2-wp4h1-intrinsic/canonical/intrinsic-ranking.json` 등 canonical/ 산출물). R0 이후 현재 상태 판정은 이것만이 권위를 가진다.
2. **역사 보고서 (Historical reports)** — 과거 상태 이해·감사 자료. 현재 authority가 아니다. 보고서 내용의 재현·재검증 여부는 ④ reproducible 축과 ⑤ current truth 축이 대조한다.
3. **이 표의 위치** — 과거 주장(① reported status)과 현재 유효성(⑤ current truth)의 대조지(對照紙)이며 **Verified 목록이 아니다**. 캠페인 총괄: 외부 symbol `Verified` 판정은 35행 중 0건 — "historical, unverified-now"가 지배적. R0의 핵심 발견은 외부 symbol Verified=0이라는 사실과, 현재 정본으로 유지되는 행이 `maintained` 2건뿐이라는 것이다.

## Interpretation

- Historical reports = 과거 상태 이해·감사 자료(현재 authority 아님). Current manifest + current canonical result = 현재 authority. 이 표는 과거 주장과 현재 유효성의 대조이지 Verified 목록이 아니다. 외부 symbol Verified=0이 R0의 핵심 발견.
- ③ subject-bound의 원문 "report yes / X no" 표기는 **파일 단위 기계 결속 실측**(보고서는 결속, 생성물 파일은 미결속 — source §4(a)와 교차 일치)이며, 행 수준 `subjectBound`는 보고서 결속 기준 boolean으로 정규화했다.
- **OPEN predicate 도출**(최초 갱신): `OPEN ⇔ attempted==false OR lastVerdict ∈ [none, pre_sieved, psSkip, timeout, inconclusive]` — 기존 ⑤열 값은 각 행 `historicalTruth`로 **보존**하고, `currentTruth`는 predicate를 기계 평가해 조건 충족 시 `"OPEN"`으로 파생. 평가 결과 **OPEN 2행**:
  - sortKey 12 — `WP4-j` / `bitops2.getBitsBE` / lastVerdict=`pre_sieved` → **`blocked`** (atomRun BLOCKED 2026-10-01 — RUN TERMINAL, OPEN 유지) (historicalTruth: historical — "0 results" 계측 해소, 모순#6)
  - sortKey 17 — `WP2-a` / `base36.decodedLength` / lastVerdict=`timeout` (historicalTruth: historical — E2E 대상 base32 편향, 모순#4)
- **campaignStateTransition 규칙 한 줄**: `RUN TERMINAL ≠ CAMPAIGN TERMINAL` — 행 12의 lastVerdict=blocked는 run terminal이며 currentTruth="OPEN"은 캠페인 terminal이 아님(BLOCKED → OPEN retained, nextPrerequisite 기록, same target). 전이 권위는 `rules.campaignStateTransition`이며 OPEN 행 currentTruth는 재유도하지 않는다. `campaignTerminalDerivation`은 `(currentTruth != "OPEN")` 파생 — 저장 금지. `openPredicate`는 bootstrap 시 OPEN 발견 규칙; 전이 이후에는 `campaignStateTransition`이 권위 — 재유도 금지.

## OPEN predicate 정규화 (rules.openPredicateNormalization)

- **members**: `[none, pre_sieved, psSkip, timeout, inconclusive]`
- **normSteps**: ① toLowerCase → ② 괄호 세그먼트 제거 (`\([^)]*\)` 반복) → ③ non-word run 기준 토큰화 (word char = `[A-Za-z0-9_]`, underscore 포함 — `pre_sieved`가 한 토큰이 되도록) → ④ 빈 토큰 제거
- **matchMode**: 토큰 == member (대소문자 무시) **또는** 토큰이 member를 whole-word prefix로 포함 (member 뒤 = non-word char 또는 token 끝)
- **실측 결과**: `exactMemberMatches=["pre_sieved","timeout"]`, `normalizedMemberMatches=[]`, decorated 판정어 15개 전부 탈락(예: "Vacuous (erratum)" → "vacuous" — 멤버 아님 → closed). "Incomplete"·"Vacuous"·"Unsupported" 등은 계획상 멤버가 아니므로 OPEN을 유발하지 **않는다** (의도된 규칙 — 확장 금지). 변형 결합어(예: "Incompleteskip")는 실측 없음.
- **교차 검증**: 계획 예시 jq(정확 일치 전용)와 정규화 구현의 OPEN 집합이 동일함을 diff로 확인 — `PLAN_JQ_EQ_NORMALIZED`.

## jq firstOpenTarget 사용법

```bash
# 행 수
jq '.rows | length' coverage-matrix.json                      # → 35 (검증 1)

# OPEN 행 수
jq '[.rows[] | select(.currentTruth=="OPEN")] | length'       # → 2 (검증 2)

# OPEN 행 목록 (sortKey 순, 필수 필드)
jq '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[] | {sortKey, target, wp, lastVerdict}' coverage-matrix.json

# firstOpenTarget 후보 (B6 사용)
jq -r '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[0] | {sortKey, target, lastVerdict}' coverage-matrix.json
# → {"sortKey": 12, "target": "bitops2.getBitsBE", "lastVerdict": "blocked"}  (검증 3 — atomRun BLOCKED 전이 후)

# 역사 분포 (기존 ⑤열과 동일해야 함)
jq -r '.rows[].historicalTruth' coverage-matrix.json | sed -E 's/^(maintained|historical|refuted|conflicted|superseded[^ —(]*).*/\1/' | sort | uniq -c
# → 27/3/2/1/1/1 (검증 4)

# 주의: OPEN 판정은 단독으로 내려지지 않는다 —
#   rules.openPredicate = attempted==false OR lastVerdict in [none, pre_sieved, psSkip, timeout, inconclusive]
#   rules.openPredicateNormalization = 위 "정규화" 절 — 멤버 일치 규칙 명시
#   rules.closureNotOpen  = 번역 완전성 closure는 fact-gate CLOSED — OPEN 아님
#   rules.campaignStateTransition = RUN TERMINAL(BLOCKED 등) ≠ CAMPAIGN TERMINAL — BLOCKED→OPEN retained, currentTruth는 전이 규칙이 권위
```

---

## 요약 표 (sortKey 순 — canonical order 보존, historicalTruth/currentTruth 2열)

**sortKey 규칙**: `intrinsic-ranking.json`의 `intrinsicRank`에 해당하는 target을 우선한다 — `getBitsBE`(rank 1) = sortKey 1–16, `base36.decodedLength`(rank 2) = sortKey 17–22. 그 외 행은 원 표 순서 유지 (sortKey 23–35). 공백 없이 연속 1–35.

| sortKey | WP | target | reportedStatus (원문) | evidenceExists | subjectBound | historicalTruth | currentTruth |
|---|---|---|---|---|---|---|---|
| 1 | WP4-b | bitops2.getBitsBE | InfrastructureFailure — axiom_engine.nim:719 slice crash exit 2 (L79) | true | true | superseded (wp4c V2에서 결함 제거 확인) | superseded (wp4c V2에서 결함 제거 확인) |
| 2 | WP4-c | bitops2.getBitsBE | V2 PASS(crash 제거); V3 미해결·국소화 (L8) | true | true | historical (V3 국소화 — 현행 대조 필요) | historical (V3 국소화 — 현행 대조 필요) |
| 3 | WP4-d-0 | bitops2.getBitsBE (func/template identity) | PASS — decl-text discriminator (L39) | true | true | historical (identity 판정 — proof 아님) | historical (identity 판정 — proof 아님) |
| 4 | WP4-d-4 | bitops2.getBitsBE | Incomplete — V3 FIXED, A4 psSkip illFormed (L34, L85) | true | true | historical | historical |
| 5 | WP4-e | canonical --target fail-closed | PASS — NotFound/Ambiguous exit 2 (L12-14) | true | true | historical (fail-closed 설계 — 현행 계약 대조) | historical (fail-closed 설계 — 현행 계약 대조) |
| 6 | WP4-f A | bitops2.getBitsBE | 국소화: illFormed 직접 원인 = postcondition vacuous (L21) | true | true | historical | historical |
| 7 | WP4-h-1 | bitops2.getBitsBE (Anchor#1) | Incomplete/measurement success (L124) | true | true | historical | historical |
| 8 | ACT2-WP4-3 | bitops2.getBitsBE | Unsupported/ExecutionTerminated — erGuardHardReject, empty SMT (L57, L75) | true | true | superseded (후속 wp4d-4에서 frontier 입성 달성) | superseded (후속 wp4d-4에서 frontier 입성 달성) |
| 9 | WP4-h-2 | bitops2.getBitsBE | A2-script-pocketed-but-not-z3-executable (L128, md5 f75cba83…) | true | true | historical | historical |
| 10 | WP4-h-3 | bitops2.getBitsBE | typing established(결정론, Z3 sat); E2E Unsupported (L74-75, L113) | true | true | historical, unverified-now (sat=자명성 — proof 아님, 보고서도 명시) | historical, unverified-now (sat=자명성 — proof 아님, 보고서도 명시) |
| 11 | WP4-i | bitops2.getBitsBE | premise REFUTED — 원인=payload_bridge.nim CWD read (L55, L61); 새 경계 Missing preconditions: has_loop (L95) | true | true | refuted (원인 귀속 정정됨 — 정정된 경계가 현재 기술 상태, R0 확인) | refuted (원인 귀속 정정됨 — 정정된 경계가 현재 기술 상태, R0 확인) |
| **12** | **WP4-j** | **bitops2.getBitsBE** | **Incomplete — pre_sieved, UAP requests=1 results=0 (L105-107, L170)** | true | true | historical (j.1이 "0 results" 계측 해소 — 모순#6) | **OPEN** |
| 13 | WP4-k | bitops2.getBitsBE | Incomplete + InfrastructureFailure(PERSIST FAIL) — O9/O10/O11 closed; erratum: Z3 도달 → Vacuous 정정 (L155, L233-247) | true | true | superseded-by-own-erratum — 최종 판정 Vacuous(sat) | superseded-by-own-erratum — 최종 판정 Vacuous(sat) |
| 14 | WP4-j.1 | bitops2.getBitsBE | Vacuous — Z3 실호출 2건 sat, golden digest d9f9af27… 정확 일치 (L150, L68) | true | true | historical, unverified-now (sat — 만족성은 증명 아님) | historical, unverified-now (sat — 만족성은 증명 아님) |
| 15 | WP4-j.2 | bitops2.getBitsBE | substrate 성공 + lossy 판정 → fact 미주입 (translationLossFree=false, bindingUniverseComplete=false, 15 vs 12/13) → Incomplete (L79-82) | true | true | historical | historical |
| 16 | WP4-j.3+j.4 | bitops2.getBitsBE | j.3 완료; j.4 ladder 14/14; fact 주입 차단(completeness 게이트 15 vs 13) → Incomplete (L103-106, L133) | true | true | historical — 캠페인 중단점 (R0 재관측 출발점) | historical — 캠페인 중단점 (R0 재관측 출발점) |
| **17** | **WP2-a** | **base36.decodedLength** | **Incomplete → 경계 PASS V1~V7, 대상 심볼 status=timeout (L88 V7 PASS)** | true | true | historical — 판정 자체가 Verified 아님 명시; E2E 대상 base32 편향 기재(모순#4) | **OPEN** |
| 18 | WP3-a | base36.decodedLength | Vacuous — T3 tautology REJECT, exit=2 (L48) | true | true | historical (다중 보고서 일치 — R0 재관측) | historical (다중 보고서 일치 — R0 재관측) |
| 19 | WP3-b | base36.decodedLength | Vacuous (L128) + 라우팅·tcVerifiedProof 승격 2 BLOCKER fixed (L15) | true | true | historical (fix 현행 존속 추정 — R0 확인) | historical (fix 현행 존속 추정 — R0 확인) |
| 20 | WP4-a PA | base36.encode/decodedLength | elNoObligation/elProofCandidate (L38-39) | true | true | historical, unverified-now (eligibility 분류) | historical, unverified-now (eligibility 분류) |
| 21 | WP4-a B-2b | base36.decodedLength | Failed(main) + cross-validation vacuous, solverInvocationCount=1 (L79) | true | true | conflicted — WP3-a/B-5b의 tautology REJECT와 기전 상충, 미해소 | conflicted — WP3-a/B-5b의 tautology REJECT와 기전 상충, 미해소 |
| 22 | WP4-a B-5/5b | base36.decodedLength | InfrastructureFailure → fixed (CWD source-acquisition); tautology REJECT 유지 | true | true | historical (fix 현행 존속 — R0 재검증) | historical (fix 현행 존속 — R0 재검증) |
| 23 | WP0-a | 계약 개정 §10 | COMPLETE (verdict L73) | true | false | maintained — §10 현행 계약 존속 확인 | maintained — §10 현행 계약 존속 확인 |
| 24 | WP0-b/c | external exec context (self-run verified=1) | Verified + M1 Incomplete (L54-55) | true | true | historical, unverified-now — 보고서 L64가 "verified=1은 Axiom 자기 커널 스코프"임을 자체 명시 | historical, unverified-now — 보고서 L64가 "verified=1은 Axiom 자기 커널 스코프"임을 자체 명시 |
| 25 | WP1 | endians2.nim::swapBytesNim | Partial PASS — E1–E3 PASS, E4 Blocked:S3-registry-static, E5 Unsupported(PNode→NimNode-boundary) (L48) | true | true | historical, unverified-now (외부 Verified=0) | historical, unverified-now (외부 Verified=0) |
| 26 | WP1.5 | endians2.nim::swapBytesNim | PASS — E4 admitted(soExternalSubject), E5 CanonicalNoObligation (L24) | true | true | historical, unverified-now (ingress 분류 판정 — proof 아님) | historical, unverified-now (ingress 분류 판정 — proof 아님) |
| 27 | WP3-c | nim-stew trust journal 6,806 | DEBT#445 등록, legacy-unverified ×6,806 (result L10-31) | true | true | maintained — data/debt_registry.json:3464에 DEBT#445 현존, manifestDigest a42bf17d… 일치(행 중 유일) | maintained — data/debt_registry.json:3464에 DEBT#445 현존, manifestDigest a42bf17d… 일치(행 중 유일) |
| 28 | WP4-a B-1 | registry field supply | PASS (registry 230, L136-139) | true | true | historical (현행 registry 수치 재확인 필요) | historical (현행 registry 수치 재확인 필요) |
| 29 | WP4-f C | nim-stew 전 트리 46 symbols | verified=0/40 "correct zero", A4 통과 0 (L7, L71) | true | true | historical — 외부 Verified=0 원칙과 정합 (R0 재관측 시 동일 예상) | historical — 외부 Verified=0 원칙과 정합 (R0 재관측 시 동일 예상) |
| 30 | WP4-g.0 | reference vault 6 certs | 5/6 AMBIGUOUS, 1/6 REPLACE (L97-98) | true | false | historical, unverified-now (기준 cert 소실로 재검증 불가) | historical, unverified-now (기준 cert 소실로 재검증 불가) |
| 31 | WP4-g.1 | proximityScore | Case A 아님 (NC1 PASS/NC2 dvcPbtFailed/NC3 PASS) → Case B; Phase D rpoResolved (phase-a L15/L41) | true | false | historical, unverified-now | historical, unverified-now |
| 32 | WP4-g.2 | ax cert reconcile primitives | Verified — RESOLVED EXIT=0 / full check EXIT=2 / apply REFUSED (L39-78) | true | false | historical (primitive 판정 — R0 재검증) | historical (primitive 판정 — R0 재검증) |
| 33 | WP22→h0 | nim-stew 458 symbols / 6 anchor | 1차 Empty → hardEligible=6 확정 (result L4-6) | true | true | superseded → 해소 (SUPERSEDED 명시; 최종 hardEligible=6 — R0 재확정) | superseded → 해소 (SUPERSEDED 명시; 최종 hardEligible=6 — R0 재확정) |
| 34 | act2-1-pr13 | rebase V4b witness | baseline capture; vacuous expected; V1 solver reach=1 (L29-55) | true | true | historical (witness; vacuous는 wp3/b5b와 일치) | historical (witness; vacuous는 wp3/b5b와 일치) |
| 35 | act3-o1 | 빌드 프로토콜 (warm) | GO — CC 599→51 (−91.5%), ArtifactOutputDigest 81b04430… cold==warm (L68-74) | true | false | historical (warm 프로토콜 채택 여부 R0 확인) | historical (warm 프로토콜 채택 여부 R0 확인) |

## 수치 요약 (JSON과 일치)

**historicalTruth** (기존 ⑤열 분포 — 보존, 검증 4):

| 값 | 행 수 |
|---|---|
| historical (+변형) | 27 |
| superseded | 3 |
| maintained | 2 |
| refuted | 1 |
| conflicted | 1 |
| superseded-by-own-erratum | 1 |
| **합계** | **35** |

**currentTruth** (predicate 파생 후):

| 값 | 행 수 |
|---|---|
| **OPEN** | **2** (sortKey 12: WP4-j/getBitsBE/pre_sieved · sortKey 17: WP2-a/decodedLength/timeout) |
| historical (+변형) | 25 |
| superseded | 3 |
| maintained | 2 |
| refuted | 1 |
| conflicted | 1 |
| superseded-by-own-erratum | 1 |
| **합계** | **35** |

기타 축 (변화 없음): subjectBound true 30 / false 5 · evidenceExists true 35 (evidencePaths 104건 — 행 12에 `repo:experiments/act2-r0-atom-getbitsbe/` 11건 추가, 전부 `repo:`/`workspace-untracked:` — 절대경로 없음) · reproducible likely 29 / no 6 · attempted true 35.

## OPEN 행 (firstOpenTarget 후보 — B6에서 사용)

```json
{"count": 2, "firstOpenTarget": {"sortKey": 12, "target": "bitops2.getBitsBE", "lastVerdict": "blocked"}, "lastRunVerdictOfFirst": "blocked"}
```

| sortKey | WP | target | lastVerdict | historicalTruth |
|---|---|---|---|---|
| 12 | WP4-j | bitops2.getBitsBE | **blocked** (prev pre_sieved) | historical (j.1이 "0 results" 계측 해소 — 모순#6) |
| 17 | WP2-a | base36.decodedLength | timeout | historical — 판정 자체가 Verified 아님 명시; E2E 대상 base32 편향 기재(모순#4) |

→ **firstOpenTarget = sortKey 12 (WP4-j / bitops2.getBitsBE / lastVerdict=blocked)** — R0-atom proof run BLOCKED(2026-10-01) 후 OPEN 유지(retained). RUN TERMINAL ≠ CAMPAIGN TERMINAL (`rules.campaignStateTransition`): nextPrerequisite = fact-gate translationLossFree=true 또는 UAP 결과 생산(requests=1 results=0), same target.

## 검증 기록 (2026-10-01)

```bash
jq '.rows|length' coverage-matrix.json
→ 35

jq '[.rows[] | select(.currentTruth=="OPEN")] | length' coverage-matrix.json
→ 2

jq -r '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[] | "sortKey=\(.sortKey) target=\(.target) lastVerdict=\(.lastVerdict)"' coverage-matrix.json
→ sortKey=12 target=bitops2.getBitsBE lastVerdict=blocked   # atomRun BLOCKED 전이 후 (prev pre_sieved)
→ sortKey=17 target=base36.decodedLength lastVerdict=timeout

jq -r '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[0] | {sortKey, target, lastVerdict}' coverage-matrix.json
→ {"sortKey": 12, "target": "bitops2.getBitsBE", "lastVerdict": "blocked"}   # firstOpenTarget (BLOCKED 전이 후)

jq -r '.rows[].historicalTruth' coverage-matrix.json | sed -E 's/^(maintained|historical|refuted|conflicted|superseded[^ —(]*).*/\1/' | sort | uniq -c
→ 27 historical / 3 superseded / 2 maintained / 1 refuted / 1 conflicted / 1 superseded-by-own-erratum   # 기존 ⑤열과 동일

jq -e '[.rows[] | has("historicalTruth")] | all' coverage-matrix.json
→ true   # 35행 전부 보존

# 계획 예시 jq(정확 일치)와 정규화 구현의 OPEN 집합 diff
diff <(jq '...plan예시...' coverage-matrix.json) <(jq '[.rows[] | select(.currentTruth=="OPEN") | {sortKey, lastVerdict}]' coverage-matrix.json)
→ 출력 없음 (동일)
```

### P4 자가점검 기록 (C7/C8 — proof-atom getBitsBE BLOCKED 전이 후, 2026-10-01)

```bash
jq -e '.rows[]|select(.sortKey==12)|(.currentTruth=="OPEN" and .lastVerdict=="blocked" and (.historicalTruth|length)>0 and (has("campaignTerminal")|not))' coverage-matrix.json
→ true   # currentTruth=OPEN ∧ lastVerdict=blocked ∧ historicalTruth 보존 ∧ 저장 필드 없음

jq -e '(.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[0].target) == .openSummary.firstOpenTarget.target and .openSummary.firstOpenTarget.target == "bitops2.getBitsBE" and (.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[0].lastVerdict) == "blocked"' coverage-matrix.json
→ true   # OPEN-CONSISTENT: firstOpenTarget == bitops2.getBitsBE (lastVerdict=blocked)

jq '.rules.campaignStateTransition' coverage-matrix.json
→ 존재   # runTerminal 4종 / BLOCKED→"OPEN (retained)" / campaignTerminalDerivation=derived 저장 금지 / openPredicateRelation

jq -e '[.rows[] | has("campaignTerminal")] | any | not' coverage-matrix.json
→ true   # ROWS-CLEAN

jq -e '[.openSummary, .openSummary.firstOpenTarget, .openSummary.rows[]] | map(has("campaignTerminal")) | any | not' coverage-matrix.json
→ true   # OPENSUMMARY-CLEAN
# 주의: rules.campaignStateTransition 내 "campaignTerminalDerivation" 키는 파생 규칙 라벨(저장 금지 선언) — 행·요약 저장 필드 아님. "openPredicateRelation": openPredicate는 bootstrap 시 OPEN 발견 규칙; 전이 이후에는 campaignStateTransition이 권위 — 재유도 금지.

jq '.rows|length' coverage-matrix.json                    → 35
jq '[.rows[]|select(.currentTruth=="OPEN")]|length'       → 2 (sortKey 12·17)
```

## 각주

- ④/⑤의 상세 근거(reproducibleNote, verdictAuthority)는 JSON 행 필드에 있다 — 본 표는 요약 컬럼만 담는다.
- **OPEN 2행은 재관측 대상 후보지** — 마지막 관측일(2026-10-01) 기준 currentTruth 쿼리는 이 JSON 파일 그대로의 상태다. B6 단계 firstOpenTarget(sortKey 12) 재관측 **완료**: proof-atom run BLOCKED(2026-10-01) 적용 후 lastVerdict=blocked로 갱신, currentTruth=OPEN **유지**(BLOCKED는 run terminal — 캠페인 terminal 아님, `rules.campaignStateTransition`). 다음 재관측 대상은 동일 target(sortKey 12, nextPrerequisite 기록됨).
- 병렬 작업 파일(`subject_authority.json`, `execution_authority.json`, `restored_evidence_checksums.txt`)은 이 산출물과 무관하며 건드리지 않았다.