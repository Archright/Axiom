# MG 착지 REUSED 정책 재결 — #895 세대 결정의 명시적 뒤집기 (2026-10-18)

> **종류**: 아키텍트급 재결 문서 (policy redecision record). **권위**: 본 문서는
> merge-admission 판정 권위(GitHub — org ruleset·merge queue·native MERGE 커밋)를
> 대체하지 않는다(Authority ≠ Adapter). 본 문서가 재결하는 것은 **행동 포즈(policy
> posture)**다 — 어느 basis가 착지 venue에서 증거로 수용되는가.
> **재결 대상**: [ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md)
> §3의 #895 세대 결정 (PR #895, merged 2026-10-17T04:03:31Z).
> **계약 관계**: `docs/spec/test_judgment_cas_contract.md`는 **개정되지 않는다** —
> §5 5조건은 애초에 MG 차단 조항을 갖지 않으며, 본 재결은 계약 §5를 착지 venue에
> **적용**하는 것일 뿐이다(§1.3). 차단은 코드+yml+사전등록 문서에만 존재했고,
> 본 재결이 그것을 해소한다.
> **소비 순서(HARD RULE)**: 본 문서(재결)가 먼저 착지하고, 구현 PR은 본 문서가
> main에 착지된 **이후에만** 시작된다(§2.5 — AGENTS.md CI Self-Bootstrap Bottleneck).

---

## 1. 재결 (Decision)

### 1.1 뒤집는 것 — 원 결정의 인용

[ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md)
§3 (Tombstone) 원문:

> **"REUSED-on-merge_group 허용"의 종료 선언.** 구세대 blob f2ad3b03의 착지 venue
> 재사용 포즈는 본 전환으로 끝난다.

같은 문서 §2.2: "**REUSED-on-MG 차단**: 레인 plan env
`AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: ${{ github.event_name == 'merge_group' && '1' || '' }}`
— … 착지 런의 계획 단락이 원장 consult 전에 jExecuted로 단락된다(48a33ede4)."

**본 재결은 위 두 단락이 수립한 행동 포즈 — "merge_group 착지 venue에서는 REUSED를
아예 도달 불가능하게 차단한다" — 를 명시적으로 뒤집는다.** 필요성의 계량 근거:
MG wall은 신세대 착지 D3의 지배 성분이다(깨끗한 n=4 평균 666.8s = 67.3%,
[post_a_d3_decomposition_2026-10-17.md](post_a_d3_decomposition_2026-10-17.md)) —
착지 런이 전부 재실행하는 구조는 착지 지연의 최대 항을 고정시킨다. 동일 클로저에
대해 사전 실행의 종결 판정이 5조건 전수 재검증으로 살아있음에도 착지가 그것을
증거로 쓰지 못하는 것은 무차별 재실행이지 강화가 아니다.

### 1.2 새 정책 (NEW POLICY)

**착지(merge_group) venue의 judgment basis는 다음 둘 중 하나다:**

1. **EXECUTED** — 이번 어드미션 실행에서 실제 실행(컴파일+런)되어 종결 판정을
   산출했다 (계약 §3 상태표 `:65-68` 그대로), **또는**
2. **eligible REUSED** — 계약 §5 5조건 전수 통과 **+** 재사용되는 레코드가
   **같은 세대의 pipeline-minted EXECUTED 루트**임이 **+** decision/attest에
   봉인된 **provenance 마커(rootRecord)** 로 표시됨 (§1.2a).

재사용 자격의 정의(요약 — 전문은 §2·§3): plan 단계에서 원장 consult 사슬이
전부 통과하고(§2의 구조적 사슬 — 계약 §5 (a)(b)(c) 상당), attest 단계에서
decision 파일의 rootRecord 3필드가 재인출 레코드와 정확히 일치하며(§3),
어떤 불일치·조회 실패·UNKNOWN도 EXECUTED로 fail-closed한다(§4).

### 1.2a provenance 마커 (rootRecord) — 스키마

decision 파일(jReused 시)과 그로부터 소비되는 attest 검증은 아래 마커를 운반한다:

```json
"rootRecord": {
  "evidenceKey":   "<64-hex — 재사용 루트 레코드의 원장 키>",
  "payloadSha256": "<64-hex — 루트 레코드 봉투의 payloadSha256>",
  "executionEpoch": "<epoch — 루트 EXECUTED 실행이 봉인한 executionEpoch>"
}
```

의미: 이 판정이 채택한 사실의 **근본 생산 런(root EXECUTED run)** 이 어느
원장 엔트리인지를 decision/attest 표면에서 **명시적으로 가시**하게 한다.
루트는 원장이 exactly-once로 보증하는 유일한 EXECUTED mint(§2)이며 — 마커는
그 귀속을 소비자가 검증 가능한 형태로 노출한다(§3).

### 1.3 원래 위험(hazard)은 닫힌 채 유지된다 — 재결의 논거

#895 세대가 차단으로 채택한 이유는 "착지가 **실제 실행 0건**으로 성립하는"
위험이었다. 그 위험은 **오늘 이미 구조적으로 폐쇄**되어 있다 — 차단이 아니라
구조가 닫는다:

**(i) REUSED-유래 원장 레코드는 표현 불가능하고, 재사용 사슬(reuse chain)은
구조적으로 존재할 수 없다.**

- 원장 레코드(`EvidenceCasRecord`)에 **basis 필드는 없다** —
  `src/verification/evidence_ledger.nim:88-96` (`evidenceKey·payload·payloadSha256·
  evidenceDigest·verifierArtifactDigests·storedAtUtc`). payload는 클로저의
  **순수 함수**다 — `src/verification/judgment_cas.nim:133-140` "same closure ⇒
  byte-identical payload"; validator는 정확 필드 집합 외 일절 기각한다
  (`validateJudgmentPayloadNode` exact-field-set). 따라서 "REUSED에서
  왔다"는 상태 자체가 payload에 표현될 수 없다.
- **유일한 신규 mint 경로는 EXECUTED leg다** — `judgment_cas.nim:1891-1909`:
  EXECUTED basis는 실행 측정 evidence 파일을 **요구**하고(부재 → fail-closed),
  그 파일은 실제 테스트 런의 armed flush canary만 생산한다(`:1405-1408`
  d2_golden·`:1426-1429` d2_persist의 `observedKernelRunCount != canonical →
  레코드 생산 자체 실패`).
- **REUSED leg는 재결속(rebind)만 한다** — `judgment_cas.nim:1910-1934`:
  원장에서 재인출 + `verifyJudgmentReuse`(`:1756-1784` — 키 결속·payload 계약·
  epoch) 전수 재검증 후 **저장 바이트를 그대로** 재발행(`:1929-1934` "the mint's
  append of an identical (key, payload) is an exactly-once no-op").
- **원장 append는 키당 exactly-once다** — `evidence_ledger.nim:494-568`
  `appendEvidence`: 같은 키 + 다른 payloadSha256 → FAIL(`:561-565` "identity-
  derivation anomaly, fail-closed"); 같은 바이트 → 멱등 no-op. mint append는
  착지 venue 한정이며 basis ∈ {EXECUTED, REUSED}를 이미 수용한다
  (certificate-mint.yml P7c-x).

종합: **모든 원장 레코드의 루트는 실제 EXECUTED 런이고, REUSED 결정은 원장으로
역유입되지 않는다.** 다음 런의 plan은 항상 같은 루트 레코드를 재consult할 뿐 —
"REUSED의 REUSED"라는 표현식은 원장 스키마상 만들어질 수 없다. #895가 막으려던
"실행 0건 착지"는 남아있는 유일한 경로(레코드 전무 상태의 착지)에서 이미
fail-closed다: 레코드가 없으면 plan은 jExecuted고, EXECUTED는 evidence 파일을
요구하므로 실행 없는 EXECUTED 판정은 attest에서 실패한다.

**(ii) provenance 마커가 루트를 decision/attest 표면에 명시 가시하게 한다.**

오늘의 decision 파일은 `{basis, evidenceKey, reason, probeTreeOid, subject?}`
(`writeJudgmentDecisionFile`, `:1728-1748`)이고 witness node는
`{basis, evidenceKey, projection, projectionSha256, subject?}`(`:1670-1692`)다 —
어느 원장 엔트리(루트 런)가 채택됐는지는 소비자가 재인출로 추론해야 했다.
`rootRecord` 마커(§1.2a)는 이 귀속을 decision/attest에 봉인하고, attest leg가
그 3필드를 재인출 레코드와 대조하게 한다(§3). 마커는 extra 필드라
`validateJudgmentWitnessNode`(`:1694-1717`)의 현행 wire 검증이 이를 기각하지
않는다 — 무파괴 확장이다.

**(iii) 모든 불일치·UNKNOWN은 EXECUTED로 fail-closed한다.**

consult 사슬의 모든 실패 이유가 이미 jExecuted로 귀결된다(closure 수집 실패
`:1533-1540`, 조회 실패/무레코드 `:1565-1572`, fetch/payload 불량
`:1573-1588`, epoch 불일치 `:1589-1594`) — plan이 jReused에 도달하는 유일한
길은 전수 재검증 사슬의 전부 통과다. attest에서도 REUSED leg의 재인출·재검증
실패는 run 실패다(`:1910-1934`), 마커 불일치·부재는 이에 **추가**되는
fail-closed다(§3). UNKNOWN(조회 실패)이 HIT로 해석되는 경로는 존재하지 않는다 —
계약 §6 "조회 실패도 MISS다"의 구현이 그대로 소비된다.

## 2. 계약 §5 — verbatim

`docs/spec/test_judgment_cas_contract.md:159` — "## 5. REUSED 성립 5조건
(test-judgment 적용 — §15.3 표의 투영)". 5조건 표는 `:166-172`, 행별 원문:

| # | 행 | 조건 | test-judgment 적용 (계약 원문) |
|---|---|---|---|
| (a) | `:168` | 클로저 동일성 | "레코드의 9성분 클로저 지문 == 현재 실행의 재계산 지문 (§4 — v3: 성분 5는 semantic set digest, §4.1 단일 도출 권위)" |
| (b) | `:169` | executionEpoch 일치 | "레코드 `validatedAtEpoch == ctx.currentEpoch` — `sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)`" |
| (c) | `:170` | per-read 재해시 | "레코드 바이트를 **읽을 때마다** 재계산한 SHA-256 == 레코드 `contentDigest`" |
| (d) | `:171` | witness 바인딩 | "레코드에 봉인된 **판정 projection + 그 digest**가 재독출 바이트와 동일 (byte-equality) — mint exactly-once append의 입력 정합 (P7b 상당, §7)" |
| (e) | `:172` | 도구 정체성 | "판정을 산출한 실행 주체의 도구 정체성(B-built ax identity·툴체인 번들) == 현재 도구 정체성 — **v1.0.3 정밀화**: … 본 조건은 B executor의 측정 정체성(번들·핀)만 담당하며 v3로 인해 변경되지 않는다" |

**per-unit 결합 규칙** (`:180-182`) — verbatim:

> **per-unit 결합 규칙(§15.3 per-unit rule 재사용)**: 4테스트 블록의 REUSED 성립은
> 4건 전부의 조건 통과를 요구한다 — 하나라도 기각되면 블록 전체가 fail-closed로
> EXECUTED 전환한다(§6).

**fail-closed** (`docs/spec/test_judgment_cas_contract.md:184-201` §6) — 요지
원문 인용:

> 5조건 중 하나라도 불충족(누락 레코드·digest 불일치·epoch 불일치·도구 정체성
> 불일치·projection 비일치) → **REUSED 아님 → 해당 테스트를 원래대로 실행한다**
> … **조회 실패도 MISS다**: 사이드레프 조회의 네트워크·권한 실패는 HIT로 절대
> 해석되지 않는다 … **timeout/불완전 판정은 REUSED 대상이 아니다**.

**구현-계약 필드 사상 노트**: 계약은 `validatedAtEpoch`·`contentDigest`(계약 측
필드명)를 쓰고, 구현은 payload `executionEpoch` + 봉투 `payloadSha256`으로
사상한다(계약 §5 (b)(c)와 구현 필드의 동일성 — §1.2 (ii)의 3필드는 이 사상의
표면 투영이다).

## 3. attest leg의 마커 검증 — 착지 재사용의 소비 계약

구현 PR(§6)이 착지 venue에서 수행할 검증(본 재결이 요구하는 최소 소비 계약):

1. plan(jReused)은 인출된 레코드에서 `rootRecord` 3필드를 decision 파일에
   봉인한다 (§1.2a).
2. attest REUSED leg(`:1910-1934`)는 decision 파일의 `rootRecord`를 **필수**
   로 읽고, 3필드 각각이 **재인출 레코드**의 `evidenceKey·payloadSha256·
   executionEpoch`와 정확히 일치해야 한다 — 마커 부재·빈 값·불일치는 전부
   fail-closed(run 실패). EXECUTED basis는 마커를 요구하지 않는다.
3. admission-check yml의 MG basis 강제 루프는 `"basis":"REUSED"`를 **rootRecord
   마커가 유효(non-empty·well-formed)할 때만** 수용하고, 그 외는 기존
   fail-closed exit 1을 유지한다.
4. 재사용 레코드의 원장 정합(키·payload 바이트·epoch)은 기존
   `verifyJudgmentReuse`(`:1756-1784`) 전수 재검증이 그대로 담당한다 — 마커
   검증은 이 위에 **추가**되는 것이지 대체가 아니다.

## 4. 측정 계획 (3-metric — 정책 착지 후 효과 관측)

**질문**: eligible-REUSED-on-MG는 착지 지열(D3)을 실제로 줄이는가 — 감소분이
어느 성분에서 나오는가.

**지표 (동결 공식 — [post_a_d3_decomposition_2026-10-17.md](post_a_d3_decomposition_2026-10-17.md)
정의 그대로, 한 글자 변경 없음)**:

| 지표 | 정의 | 관련 기준선 |
|---|---|---|
| preflight (D1) | PR 생성→첫 required-green | 신세대 clean 분해 평균 287.5s (29.0%) |
| MG wall | merge_group 런 created→updated | 신세대 clean 평균 **666.8s (67.3%)** — 본 정책의 직접 표적 |
| D3 | 생성→mergedAt | 신세대 clean 중앙값 **1006s ≤ 1256s 목표 (4/4)** |

**절차**:

- 정책 착지 후 **docs-only PR ≥5건**을 관측 표본으로 삼는다 — docs-only는
  클로저 불변(실행-축 키 전진 없음, `test_judgment_set_derivation.nim` T2
  동일 사실)이므로 MG 착지 런의 GO-critical 4블록이 전부 eligible-REUSED에
  도달하는 **최대 효과 표본**이다. 실행-축 전진 PR은 표본에서 분리 보고한다
  (키 전진 → MISS → EXECUTED — 정상이며 효과 표본이 아님).
- before-baseline: 본 재결 PR 자신의 착지가 구세대(OLD gate — 전부 EXECUTED)
  아래의 마지막 docs-only 착지 표본이다 — **그 MG wall을 before-baseline으로
  기록**한다(런 created→updated, runs API 관측; 구현 PR 보고서에 수치 등재).
- **401s는 baseline이지 guarantee가 아니다**: FULL_REUSE(GO 0s) MG 런의 wall
  관측 하한 401–402s(`p95_attribution_2026-10-16.md:14` — SLO 480s의 유일
  관측 하한 증명)는 "eligible-REUSED 착지가 반드시 401s에 도달한다"는 뜻이
  아니라 **달성 가능성의 등록된 상한 증명**이다. bootstrap 웜/콜드 편차가
  MG wall에 ±100–200s 재는 분산(post_a_d3 §6)으로 인해 표본 값은 401s 주변에
  분포한다 — 판정은 중앙값 비교(before vs after, n≥5)로 하고 단일 런 최저치로
  하지 않는다.
- 기계 판독: after 표본은 `data/ci_optimization/`에 쌍생 JSON으로 등재한다
  (`post_a_d3_2026-10-17.json` 관례).
- **판정 기준(사전등록)**: docs-only 표본 MG wall 중앙값이 before-baseline
  대비 유의한 감소(제1 목표: GO-critical 실행 시간 상당분 제거 — clean 평균
  기준 MG wall의 GO 지배 항 축소)를 보이면 정책 효과 **확정**; 감소가 없거나
  red 왕복이 증가하면 **효과 없음으로 보고**하고 정책 유지 여부는 별도 재결로
  만든다. 본 측정은 Reporter다 — 판정 권위가 아니다.

## 5. 테스트 매트릭스 (구현 PR의 검증 계약 — 7 케이스)

기존 커버리지와 신규 케이스의 배치 (행 번호는 재결 시점 origin/main
`31662b789` 기준):

| # | 케이스 | 현황 | 배치 |
|---|---|---|---|
| 1 | same-key + eligible → REUSED (+마커 봉인) | G6(b) 존재 | **MG 변형 → 신규 G12** (`tests/unit/test_judgment_cas.nim`) |
| 2 | docs-only → reuse 유지 | T2 + G11(ii) 존재 | MG 변형 → G12 |
| 3 | data/*.json → class 분리 | G1 감도 + T1/T3 존재 | `test_judgment_set_derivation.nim` T7 — **dual-class nuance (본 행의 6개 파일 분류는 2026-10-18 실측 정오표의 대상 — §5.1)**: T7 실측에 따르면 data/*.json 전체가 키 전진(→ MISS)이며, 6개 파일(`command_policy·debt_budgets·feature_manifest·i18n/ko·policy_manifest·stateless_whitelist`)의 구분은 **배제-class가 아니라 k12 선언 면(ComputedStaticReadTargets — compile-input 선언)**이다 |
| 4 | no-record → execute / fail-closed | G6(a) + env fail-closed 사다리 존재 | 유지 (MG 변형 포함) |
| 5 | foreign-generation / corrupt → deny | G6(c)(d)(e) + G5 존재 | 유지 |
| 6 | **reuse-of-reuse → deny (불가능성 표현)** | **부재** — 구조적으로 불표현(§1.3-i) | 신규: G12에서 "REUSED 마커 부재/불일치 → jExecuted" plan 케이스 + **G7 확장**: attest에서 `basis=REUSED ∧ rootRecord 없음 → 기각` |
| 7 | digest/verdict mismatch → deny | G2/G4/G5 (+mint jq byte-binding) 존재 | 유지 |

- **G11 재작성**: 현행 G11(`test_judgment_cas.nim:1073` 이후 — "force-execution
  게이트 이유 + 벨트 단독 차단")은 **새 행동을 단언하도록 재작성**한다 —
  merge_group에서 (i) consult 전 조기 차단이 **없고**, (ii) 벨트는 착지 장소
  **마커**로만 남으며, (iii) PR venue 행동은 불변.
- **G12 권장명**: `G12 — the refined landing-venue reuse (REUSED-on-MG with
  root-EXECUTED provenance)` — 7케이스 중 MG 변형 3건 + fail-closed 사다리
  (불일치·UNKNOWN → jExecuted/실패) + reuse-of-reuse 불가능성 표현.
- yml 구조 단언이 필요하면 `tests/ci/test_admission_venue_split.nim`의
  step-name/body-text 핀 관례를 따른다(`:307/315/365` — P7c-x 스텝 구조 핀,
  스텝명 유지 시 무충돌).
- **fail-closed 사다리 계약**: 모든 부정 케이스의 기대는 "실행" 또는 "run 실패"
  이지 "그림자 REUSED"가 아니다 — 계약 §6의 구현 수준 번역.

## 6. 구현 범위 (scope — 3 edit sites only)

1. **`src/verification/judgment_cas.nim`** — (a) `:1468-1475` 벨트 술어의
   용도 변경(차단 → 착지 장소 마커; consult 차단 제거), (b) `:1559-1562`
   consult 전 early-return 제거(기존 consult 사슬 `:1565-1594`로 fall-through),
   (c) `:1450-1460` `JudgmentPlan` + `:1728-1748` `writeJudgmentDecisionFile`
   에 `landingVenue` + (jReused 시) `rootRecord` 마커 추가, (d) `:1910-1934`
   REUSED attest leg에 마커 3필드 재인출-레코드 대조 검증 추가.
2. **`.github/workflows/admission-check.yml`** — MG basis 강제 루프
   (`:1718-1730`)가 `basis=REUSED`를 rootRecord 마커 유효 시에만 수용
   (jq 단언), 그 외 fail-closed exit 1 유지. env `:2696`는 유지(의미 = 마커).
   `:2810/:2821` lane 분기·SSOT 집합 동등성 루프 `:1694-1712`·mint P7c는
   무변경.
3. **테스트 동반** — §5 매트릭스(G11 재작성 + G12 신설 + G7 확장 +
   `test_judgment_set_derivation.nim` dual-class 케이스).

**범위 밖**: 계약 개정(불요 — §전언), ruleset 변경, mint 워크플로 변경
(P7c-x basis 2값 이미 수용), org 핀 회전(§7 절차가 소관), AGENTS.md /
`import_encapsulation_gate.nim` (§-1 불변).

## 7. §2.5 cutover 요구 — 구현 PR의 착지 절차 (HARD RULE)

구현 PR은 **신뢰 표면 인접 callee(`judgment_cas.nim` — 회전 멤버)+정책
(admission-check.yml — trustSurface 멤버) 변경**이다. AGENTS.md §2.5에 따라:

- **in-place 부분 상태 혼합 금지** — 변경은 일관된 세대(coherent generation)
  전환으로 착지한다: **freeze tag(변경 이전 세대)** + **epoch record addendum**
  (선행 기록 `ci_epoch_record_mg_evidence_gate_2026-10-17.md` 형식 계보)로
  사전-세대를 고정하고, 단일 cutover 커밋으로 yml 배선을 착지시킨다.
- **J1 동반 증거**: same-key reuse가 **byte-identical canonical projection**
  을 돌려주는 J1 판정 증거를 구현 PR에 동반 등재한다(§1.3-i의 순수성 논거의
  라이브 대응물).
- **queue 착지가 기본 경로**다 — `admission-check.yml`이 trustSurface 멤버이므로
  CODEOWNERS/org rules가 수동 병합 의식을 요구하면 trustSurface manual-merge
  ceremony를 수행하고 **그 근거(basis)를 기록**한다(§4.2 경로 (b) —
  ROT_NEW_PIN 자기참조 잠금, `docs/spec/admission-generation.md`).
- **§4.3 사후 ruleset 재핀 의무**: admission-check.yml이 변경되고 org
  controller가 그 파일(또는 그것을 참조하는 caller)을 핀하는 경우, 착지 후
  **live 핀을 확인**하고 핀이 전진 대상이면 **양 ruleset(25218071·23943917)
  dual 재핀**을 하나의 논리적 단위로 수행한다 — drain 관측 → (필요 시)
  `max_entries_to_build` 2→0 동결 → PUT → readback byte-consistency → 0→2
  해제 (`admission-generation.md` §5.3–5.5 절차 준용). 재핀 불요(핀 미참조)
  면 그 사실을 readback과 함께 기록한다.
- **rollback**: freeze 태그에서의 원자 revert — yml과 두 핀은 한 커밋에
  결속(부분 상태 혼합 없음), Nim callee는 env 부재 시 무동작이지만 세대
  일관성을 위해 동반 revert를 기본으로 한다(선례: mg_evidence_gate_prereg §5).

## 8. 본 문서가 승인하지 않는 것

1. **차단 제거 = required-check 제거가 아니다** — required check
   `admission-check`(ruleset 20303214)는 불변이며, 본 재결은 #895 §3과 동일하게
   "우회·면제·required-check 제거가 아니다"를 재확인한다. 착지 증거 기준은
   마커 가시성(§3)으로 **강화**된다 — 완화로 보이는 유일한 부분(basis 2값)은
   구조적 폐쇄(§1.3)가 전제된다.
2. **프리플라이트(PR venue) 행동 변경 없음** — PR preflight의 재사용 포즈는
   오늘과 동일하다(벨트는 merge_group에서만 마커가 된다).
3. **측정은 판정이 아니다** — §4는 Reporter다. 정책의 다음 개정 권한은 본
   문서와 동격의 재결 문서에만 있다.

## 정오표 (2026-10-18 실측 수정 — 구현 PR ci/mg-reuse-eligibility-2026-10-18 동반)

§5 케이스 3의 원 문구("6개 data 파일이 배제-class, 키 불변")는 **실측으로
기각됐다**: `test_judgment_set_derivation.nim` T7 —
`data/command_policy.json` 바이트 변조가 semantic digest를 **전진**시킨다.
6개 파일(`command_policy·debt_budgets·feature_manifest·i18n/ko·
policy_manifest·stateless_whitelist`)은 배제표 N에 없고
**ComputedStaticReadTargets(k12 선언 compile-input 면)**에 속한다 — T4가
config/templates·config/policy에 대해 증명한 것과 동일 클래스다. 즉
**data/*.json 전체가 키 전진 멤버(변조 → MISS → 신규 EXECUTED)**이고, 두
class의 구분은 선언 유무(k12 면)이지 효과가 아니다. 본 정오표는 §1.2의
정책(EXECUTED OR eligible REUSED)과 무관한 테스트 매트릭스 문구 수정이다 —
키 전진 → MISS는 재사용 자격의 fail-closed 방향을 오히려 강화한다.
