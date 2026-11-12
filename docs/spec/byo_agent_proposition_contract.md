# BYO Agent Proposition Contract — `ax prove --proposals` (고객 AI 에이전트 명제 입력 계약)

> **Status**: Committed contract — BYO Agent intake 표면의 표준 입력 계약 (§0.12 계약 선행 — 구현은 병렬 workstream에서 착지; 본 문서가 그 PR의 계약 정본이다)
> **Created**: 2026-11-02
> **Revised**: 2026-11-03 — Phase 5.1: 스키마 v2 (`id` 필수·유일, lane/claim 2형태, 경계값 상수), 명제별 `INCAPABLE` capability 축과 두 축 상태 모델(§3), 문서 거절 4종 폐쇄 집합(§6 — `UNSUPPORTED_SPEC_ID` 은퇴), `display.propositions[]` rollup(§3), 전명제 INCAPABLE exit 0 정직 완료(§8), `ax capability` disclosure 표면(§11) (구현 workstream `work/byoa-phase5-incapable`)
> **AGENTS.md 참조**: §0.12 (제품 계약 선행 · 수직 슬라이스), §0.3 (신뢰 경계), §0.5 (문서 우선), §0.9 (극장 금지), §2.3 (per-output authority), §2.4 (자격 증명 권한), §5 (SSOT 위치)
> **Related**: [upstream_reporting_contract.md](./upstream_reporting_contract.md) (`ax report --upstream` — 보고 계약·receipt SSOT `data/upstream_reports/`), [bug_verdict_glossary.md](./bug_verdict_glossary.md) (§2.2 정준 발견 모델 — `BUG_FOUND`/`BUG_SUSPECTED`/귀속 Unknown), [productization_contract.md](./productization_contract.md) §11 (upstream reporting 표면 — 본 intake의 입력단 확장), [legislator_llm_only_policy.md](./legislator_llm_only_policy.md) (§3 범위 — 고객 외부 에이전트 비적용), [authority_contract.md](./authority_contract.md) §2 (verdict authority)

---

## 1. 성격·목적 — 입력 채널 추가다, 보증 광역화가 아니다

고객이 자신의 AI 에이전트로 명제(proposition)를 제출하면 Axiom이 그 명제를 기존 판정·보고 체인(발견→재현→판정→보고)으로 검증하는 **표준 입력 계약**이다. 본 계약은 새로운 보증을 만들지 않는다 — 기존 검증 레인이 소비할 수 있는 형태로 외부 명제를 **주입하는 입력 채널**만 정의한다(non-goal 보존: `productization_contract.md` §1 — broad AI-code verification guarantee는 v1 non-goal).

- **Agent Adoption ≠ Proposition Adoption (HARD RULE)**: Agent Adoption(고객이 자신의 AI 에이전트를 선택·실행하는 행위)과 Proposition Adoption(명제의 공식 약속화 — 인간 `soExplicit` 채택)은 **분리된 권한 행위**다. 에이전트 채택이 명제 채택을 의미하지 **않는다** — 에이전트가 서술한 기대는 채택된 요구가 아니며, `requirementSourceStatus`를 변화시키지 않는다(bug_verdict_glossary.md §2.4a 비소급 규칙의 BYO 확장).
- **표면**: `ax prove --proposals <file>` — 새 커맨드가 아니라 `ax prove`의 플래그 표면 확장이다. 구현은 병렬 PR(`work/byoa-phase1-intake`)에서 착지하며, 본 문서가 그 구현의 계약 정본이다. 구현 착지 전까지 본 표면은 **문서화된 계약**이지 관측된 동작이 아니다(fail-closed — 관측 없는 PASS 주장 금지).
- **권한 분리 불변**: `ax prove`는 외부 쓰기가 0이며(로컬 검증·증거 산출만), 이슈 생성의 유일한 외부 쓰기 표면은 `ax report --upstream`이다(`gh` 서브프로세스, upstream_reporting_contract.md §2). BYO 흐름은 이 권위 구조를 변경하지 않는다.

## 2. 스키마 — proposals JSON (v2)

에이전트는 아래 스키마의 단일 JSON 문서로 명제를 제출한다. `schema_version: 2`는 본 계약(Phase 5.1)이 정의하는 유일한 버전이다 — 다른 값은 `BAD_SCHEMA` 거절이다. 명제는 두 형태 중 **정확히 하나**다: **lane-form**(커밋된 카탈로그의 `specId` 참조) 또는 **claim-form**(자유 서술 `logic` + `expression`) — 양쪽을 동시에 선언하거나 어느 쪽도 선언하지 않으면 `BAD_SCHEMA`다.

```json
{
  "schema_version": 2,
  "subject": { "repository": "<owner/repo 클레임>", "commit": "<40-hex 클레임>" },
  "agent": { "id": "<선언>", "version": "<선언>" },
  "propositions": [
    { "id": "<문서 내 유일 식별자>", "target": "<module::symbol>",
      "specId": "<카탈로그 specId>",
      "source_location": { "file": "<path>", "line": 0 },
      "explanation": "<자연어 — 증거 아님>" },
    { "id": "<문서 내 유일 식별자>", "target": "<module::symbol>",
      "logic": "<선언 논리 이름>", "expression": "<논리식 서술>" }
  ]
}
```

| 필드 | 의미 | 신뢰 지위 |
|---|---|---|
| `subject.repository` | 검증 대상 저장소의 `owner/repo` | **클레임** — 권위 아님(§5) |
| `subject.commit` | 검증 대상 커밋 (40-hex) | **클레임** — 권위 아님(§5) |
| `agent.id` / `agent.version` | 제출 에이전트의 선언 식별 | **선언 정보(미인증)** — 검증 판정 입력 아님 |
| `propositions[].id` | 문서 내 **유일** 명제 식별자 (필수) | rollup·추적의 키 — 명제별 `INCAPABLE` 사유가 이 id로 귀결된다(§3) |
| `propositions[].target` | `<module::symbol>` — 명제 적용 대상 (필수) | 런의 단일 `--target`으로 투영 — 서로 다른 target 혼재는 `MULTIPLE_TARGETS` 거절(§3·§6) |
| `propositions[].specId` | lane-form 페이로드 — 카탈로그 specId 참조 | 스키마 계층은 비어있지 않은 문자열만 요구한다(자유 형식); 카탈로그 해석은 intake resolution이 수행하며 미해석 specId는 문서 거절이 아니라 그 명제의 `INCAPABLE{UNKNOWN_SPEC}`다(§3) |
| `propositions[].logic` / `.expression` | claim-form 페이로드 | **v1 미검증 (HARD RULE)** — 내용은 v1에서 해석되지 않으며 `INCAPABLE{UNSUPPORTED_LOGIC}`으로 정직 기록된다(§3·§13) |
| `propositions[].source_location` | 대상 소스 위치 (파일·행 — 선택) | 카탈로그 spec의 파라미터 |
| `propositions[].explanation` | 자연어 설명 (선택) | **증거로 취급 금지 (HARD RULE)** — 인간 가독 맥락 전용; 판정·증거·receipt 어디에도 증거 필드로 진입하지 않는다 |

**경계값 (닫힌 상수 — 위반 = `BAD_SCHEMA`)**: 문서 전체 ≤ 262,144 bytes · `propositions` ≤ 32항목 · `id` ≤ 128자 · `logic` ≤ 128자 · `expression` ≤ 4096자. 빈 `propositions` 배열은 경계 위반이 아니라 `NO_PROPOSALS` 거절이다(§6).

## 3. 명제 규칙 — 3계층 능력 모델과 두 축 상태 (HARD RULE)

- **lane-form — 카탈로그 참조·파라미터화 전용**: `specId` 명제는 커밋된 카탈로그(config/spec)의 spec을 참조하고 `target`·`source_location`으로 파라미터화한다. 외부 명제의 해석은 기존과 동일하게 커밋된 카탈로그 문서의 **런타임 오버레이 설치** 경로다(`$AXIOM_STATE_DIR/specs/` — 사용자 `soExplicit` 채택 선례; intake는 주체 저장소를 절대 쓰지 않는다, §7).
- **claim-form — 선언은 수용, v1 검증 없음 (HARD RULE)**: `logic`+`expression` 자유 서술 명제는 스키마상 수용되지만 v1에 어떤 논리 파서·검증 레인도 존재하지 않는다 — 그 내용은 검증되지 않으며 `INCAPABLE{UNSUPPORTED_LOGIC}` 사실로 정직 기록된다. 새 명제의 공식 약속화는 여전히 기존 `soExplicit` 채택 경로 — **인간이 오버레이를 커밋하는 행위** — 만이 수행한다(§1 Proposition Adoption — claim-form은 채택 경로가 아니다).
- **3계층 능력 모델**: 제출된 명제는 다음 세 계층 중 하나로 귀결된다 —
  1. **INPUT_REJECTED** (문서 거절 — exit 3): §6의 4종 폐쇄 집합. 어떤 명제도 검증되지 않는다.
  2. **INCAPABLE** (명제별 능력 부재 — **런 계속**): 사유 폐쇄 집합 `UNKNOWN_SPEC` (specId가 카탈로그에서 해석 불가 — intake 결정) · `UNSUPPORTED_LOGIC` (claim-form — intake 결정) · `LANE_NOT_EQUIPPED` (카탈로그 해석 가능하나 엔진 레인 미장착 — dispatch 결정, 채택 기록 `adoptedSpecRefs`에 해당 specId 부재). INCAPABLE 명제는 레인에 선택되지 않고(`attempted=false`) 검증을 수행하지 않는다 — 이슈 생성·upstream 보고 대상도 아니다(§11 A11).
  3. **CAPABLE** (검증 수행): dispatch winner가 존재하는 lane-form 명제 — 기존 검증 레인이 소비하고 verdict를 투영한다.
- **두 축 상태 모델 (two-axis state model)**: 명제 상태는 서로 독립인 두 축이다 — **capability 축** (`CAPABLE | INCAPABLE` + INCAPABLE 사유)과 **verification 축** (`attempted` + `verdict`). 기계 판정 어휘는 무변경이다 — `verdict`는 bug_verdict_glossary.md §2.2의 기존 3-value 그대로이며 `INCAPABLE`은 새 판정 값이 **아니다**. rollup은 report `display.propositions[]`(스키마 `proposition-rollup-v1`)에 투영된다: `{id, capability{status, reason(INCAPABLE일 때만)}, verification{attempted, verdict}}` — `verdict`는 `attempted=false`일 때 JSON null이다. rollup 키는 rollup이 비어 있지 않을 때만 emit된다 — 명제 없는 런의 `display`는 v3 형태 그대로다.
- **VS-2 flip recipe와 INCAPABLE의 지위**: 엔진 레인 장착은 VS-2 주체 레지스트리 rotation flip(`docs/design/vs2_external_subject_registry_spec_2026-10-24.md`)으로 확장된다 — `INCAPABLE`은 flip 전의 **정직한 사전 상태**다: 사유가 명제별로 기록되므로 레인 장착 후 동일 명제는 `CAPABLE`로 전이되어 재검증될 수 있다. INCAPABLE 런을 실패·거절로 전환하는 것은 이 전이 경로를 막는 위장이다(§0.9).
- **MULTIPLE_TARGETS — v1 PROVISIONAL 배포 제한**: 한 prove 런은 하나의 distinct target만 소비한다(엔진 `--target` 스칼라·dispatch 레인의 단일 대상 라우팅). 서로 다른 target을 섞은 문서는 `MULTIPLE_TARGETS`(§6)로 거절되며, target별 분할 제출이 v1 사용법이다. 명제별 target 라우팅은 장기 방향이며 **미래 계약 개정으로만** 착지한다 — 본 문서는 그것을 약속하지 않는다(§13).
- **명제 채택 상태는 무변경이다**: BYO 흐름은 `requirementSourceStatus`를 절대 승격시키지 않는다 — `recordedBinding`은 오직 주체 저장소 자신의 기록으로만 성립한다(bug_verdict_glossary.md §2.4a).

## 4. 판정·보고 의미 무변경 (HARD RULE)

- **기존 계약 무변경**: 판정 어휘와 귀속 규칙은 bug_verdict_glossary.md §2.2 판정표 그대로다 — `BUG_FOUND ⟺ DISPROVED ∧ recordedBinding`(인간 채택). BYO 명제의 반증이 자동으로 `BUG_FOUND`가 되는 경로는 없다.
- **채택 없는 반증 = `BUG_SUSPECTED`**: 보고 가능하며, grounds 기록 `requirementSourceStatus = unrecorded`("탐색했으나 발견하지 못함"의 확정 기록)가 **필요**하다. grounds 기록 없이는 귀속이 Unknown이며 **보고할 수 없다**(upstream_reporting_contract.md §11 — UNKNOWN은 보고하지 않는다).
- **exit 어휘 무변경**: `ax prove`의 exit 0/1/2/3/4 = SUCCESS/VERIFICATION_FAILURE/INTERNAL_ERROR/INVALID_INPUT/NOT_CURRENT 5-state 계약(`productization_contract.md` v1 CLI Exit-State)은 그대로 소비된다 — 본 계약은 그 위의 workflow 래퍼 전이만 정의한다(§8).
- **receipt SSOT 무변경**: 보고 결과의 정본은 `data/upstream_reports/<findingKey>.json`(upstream_reporting_contract.md §10)이며, BYO 흐름의 receipt도 동일 SSOT에 기록된다.

## 5. 신뢰 경계 — 에이전트 JSON은 클레임이지 권위가 아니다

| 대상 | 에이전트 JSON의 지위 | 권위 출처 (authority) |
|---|---|---|
| `subject.repository` (slug) | **클레임** | workflow env `AXIOM_SUBJECT_REPOSITORY` — `github.context`에서 유래 |
| `subject.commit` (40-hex) | **클레임** | workflow env `AXIOM_SUBJECT_COMMIT` — `github.context`에서 유래 |
| `agent.id` / `agent.version` | 선언 정보(미인증) | 권위 없음 — 검증 판정·귀속·보고 대상 아님 |
| `explanation` | 자연어 서술 | 권위 없음 — 증거로 취급 금지(§2) |

- **불일치 → `INPUT_REJECTED` (exit 3)**: 클레임(`subject.*`)과 권위(workflow env)가 어느 하나라도 불일치하면 런은 입력 거절로 종료한다. 에이전트가 조작한 slug/commit으로 검증 주체를 바꿀 수 없다 — 검증 대상의 신원은 workflow 환경(GitHub)이 선언한다(AGENTS.md §0.3 신뢰 경계).
- **`agent.id`는 미인증 선언이다**: 에이전트 식별은 감사 참고용 선언이지 인증 주체가 아니며, 어떤 권한 부여·귀속·보고 표기의 근거가 되지 않는다.
- **`explanation`은 증거가 아니다**: 반증의 증거는 엔진이 생산한 기계 증거(반례 quartet·공용 4요소, bug_verdict_glossary.md §2.2)뿐이다 — `explanation`은 이슈 본문의 인간 맥락으로만 소비될 수 있고 evidenceDigest·receipt 증거 필드에 진입하지 않는다.

## 6. 입력 검증 — fail-closed, exit 3 (HARD RULE)

검증 실행 전에 입력을 거절하는 사유는 다음 4종으로 닫혀 있으며, 모두 exit 3(INVALID_INPUT)이다:

| 거절 사유 | 조건 |
|---|---|
| `BAD_SCHEMA` | 스키마 위반 — `schema_version` 미일치, 필수 필드 결손/형 불일치, 40-hex 커밋 위반, `id` 결손·중복·길이 초과, lane/claim 형태 위반, 경계값 초과(§2) 등 |
| `NO_PROPOSALS` | `propositions`가 비어 있음 — **빈 명제 세트는 절대 PASS가 아니다** |
| `SUBJECT_MISMATCH` | `subject.*` 클레임이 workflow env 권위와 불일치(§5) |
| `MULTIPLE_TARGETS` | 명제들이 서로 다른 target을 선언 — 한 런 하나의 target(§3) |

- **`UNSUPPORTED_SPEC_ID` 은퇴 (Phase 5.1)**: 구 v1의 거절 사유 `UNSUPPORTED_SPEC_ID`(카탈로그 미해석 specId)는 문서 거절에서 **제거**되었다 — 미해석 specId는 이제 그 명제만의 `INCAPABLE{UNKNOWN_SPEC}`(§3)로 귀결되고 나머지 명제는 계속 검증된다. 문서 거절(INPUT_REJECTED)과 명제별 능력 부재(INCAPABLE)는 계층이 다르다 — 전자는 런을 끝내고 후자는 런을 계속시킨다.
- **fail-closed**: 어느 거절 사유도 이슈 생성·보고·state 기록 없이 종료한다 — 거절된 입력은 검증 주장을 만들지 못한다(§0.9 — 확인 없는 통과 표기 금지).
- **빈 명제 절대 PASS 금지 (HARD RULE)**: `propositions`가 비어 있으면 성공(0)이 아닌 `NO_PROPOSALS`(exit 3)로 거절한다 — "제출된 것이 없음"은 "아무것도 반증되지 않음"의 증거가 아니다(bug_verdict_glossary.md §3 — 반례 미발견 ≠ 안전의 입력단 대응물).

## 7. Zero-Footprint — 명제 파일·state는 주체 트리 밖에 둔다

- **주체 트리 무변경 (불변)**: 명제 파일(proposals JSON)과 Axiom state는 검증 대상 주체 트리 **밖**에 존재한다. 런 전후 주체 소스는 바이트 동일이어야 한다 — 모듈 sha256 pre/post 일치, `git -C <subject> status --porcelain` 상시 공백(upstream_reporting_contract.md §3과 동일 계약).
- **산출물 위치**: 명제 파일은 고객 CI workspace의 주체 checkout 밖 경로에, state는 `AXIOM_STATE_DIR`(주체 밖)에 둔다(productization_contract.md §10.3 — immutable subject / ephemeral execution / state root).

## 8. exit 전이 계약 — workflow 래퍼 (HARD RULE)

workflow 래퍼는 `ax prove --proposals`의 exit code를 다음과 같이 전이한다:

| `ax prove` exit | 래퍼 해석 | 전이 |
|---|---|---|
| `0` | 정상 완료 — 단위 판정은 `DISPROVED` 또는 `UNKNOWN`일 수 있고, 명제 rollup 항목은 `CAPABLE`(검증 수행) 또는 `INCAPABLE`(검증 불가 — attempted=false)일 수 있다 | 정상 전달 — 판정·capability·귀속은 state·Summary에 정직 노출; exit 0을 "전명제 검증"으로 읽지 않는다 |
| `1` | DISPROVED — **검증 결과다** | **정상 전달·보고 계속** — 검증 실패를 workflow 실패로 전환하지 않는다. 판정은 결과이지 오류가 아니며, 보고 체인이 이 결과를 소비해야 한다 |
| `2` | canonical refusal / engine-internal — 실패 | 실패 (§3 varint WP4-e 선례). Phase 5.1 — **레인 미장착 명제는 exit 2가 아니다**: 그 명제는 `INCAPABLE{LANE_NOT_EQUIPPED}`로 귀결되고 런은 계속된다(§3) — BYO 흐름에서 관측되는 exit 2는 계약 밖 실행 실패(5-state INTERNAL_ERROR bucket)다 |
| `3` | `INPUT_REJECTED` — 실패 | 실패 (§6 4종 폐쇄 집합) |
| 기타 | 실행 오류 | 실패 — 5-state 계약 밖 신호 포함(signal = out-of-contract failure) |

- **최종 workflow 상태는 보고 완료 후 결정된다**: 보고 단계(`ax report --upstream`)는 exit 1 이후에도 실행되어야 하며(needs/status check function — §12 status check functions 참조), workflow의 최종 상태 판정은 보고 시도가 완료된 뒤에 내린다 — exit 1이 보고를 우회시키지 않는다.
- **exit 0 ≠ 전명제 증명 (첫 selftest 결함 기록, 2026-11-02)**: 기본 5-state의 exit 0은 "런 완료"다 — 단위 판정(`propositionVerdict`)은 state 파일·Summary 표면에 그대로 노출되며 `UNKNOWN`일 수 있다. 첫 selftest run 41469574000이 정확히 이 상태로 workflow conclusion success를 냈다(재생 의존성 미해결 → UNKNOWN → exit 0 — 판정 없는 green, §0.9). 이후 selftest는 판정 없는 green을 기계적으로 거절한다(§11 A9; 수정 기록 `docs/evidence/byo_agent_phase3_selftest_deps_fix_2026-11-03.md`).
- **전명제 INCAPABLE 런도 exit 0이다 (정직한 완료 — Phase 5.1)**: 모든 명제가 INCAPABLE이면 유닛 블록 없이 `display.propositions[]` rollup만 존재하는 report가 영속되고 런은 exit 0으로 정상 완료한다 — 실패도 입력 거절도 아니다. **프로그램 실행 성공 ≠ 검증 성공 (HARD RULE)**: exit 0은 "런이 계약 안에서 끝났다"는 뜻이지 "명제가 검증됐다"는 뜻이 아니며, INCAPABLE 명제는 검증을 수행하지 않았다(`attempted=false`) — 소비자는 반드시 rollup의 capability 축을 함께 읽어야 한다(§3). workflow 래퍼는 검증 완료(verified) 명제 수를 Summary에 노출하고 verified=0인 green을 "주체가 안전하다"로 읽지 않는다.

## 9. 실행 구조 — 2-Job, Minimum Trust Slice (HARD RULE)

BYO 흐름의 workflow는 두 Job으로 분리되며, 권한은 최소로 쪼개진다:

| | Job 1 — Customer Agent | Job 2 — Axiom |
|---|---|---|
| 권한 | `contents: read` | `contents: read` + `issues: write` |
| 수행 | 에이전트 실행 → proposals JSON artifact 생산 | Axiom을 pinned 전체 SHA에서 자체 빌드 → 명제 검증(§6) → `ax prove --proposals` → `ax report --upstream` |
| AI API 키 | **이 Job에만 존재한다** | 없다 — Axiom은 LLM을 호출하지 않는다 |
| 자격 증명 | GitHub 토큰 불필요(읽기) | `GH_TOKEN`은 **보고 step에만** 주입한다(§12 gh 환경변수) |
| 산출 | proposals JSON artifact **만** | 검증 결과·receipt(`data/upstream_reports/`) |
| 재생 의존성 | — | pinned `replay-dep-pins` 체크아웃 → `AXIOM_REPLAY_DEP_PATHS`(엔진 재생 설계 (b)) |

- **Job 1의 산출 경계**: Job 1은 proposals JSON artifact만 생산한다 — 바이너리·state 생성 금지.
- **오염 artifact 방지 (HARD RULE)**: Job 1이 산출한 **실행 파일을 권한 Job(Job 2)에서 실행하는 것을 금지한다** — Job 2가 실행하는 Axiom 바이너리는 Job 2 자신이 pinned 전체 SHA에서 빌드한 것만이다. 고객 에이전트 환경의 산출물은 데이터로만 Job 2에 들어간다(스키마 검증 §6이 진입 게이트다).
- **권한 근거**: job-level permissions 최소화(`contents: read` 기본, 이슈 생성에 필요한 `issues: write`는 Job 2에 한정) — §12 job-level permissions 참조. 보고는 `gh` 서브프로세스로만 수행되며(AGENTS.md §2.4·upstream_reporting_contract.md §2), `GH_TOKEN`/`GITHUB_TOKEN` 환경변수는 gh의 공식 네이티브 인증 경로로 승인된다(§12).
- **판정 요약 투영**: 래퍼의 검증·보고 결과 요약은 `GITHUB_STEP_SUMMARY`로 기록할 수 있다(§12) — 이는 표시 계층 투영이지 판정·receipt의 SSOT가 아니다(receipt SSOT 불변, §4).
- **주체 재생 의존성 프로비저닝 (2026-11-03, 첫 selftest 결함의 수정)**: ce-replay가 주체 재생 컴파일에 필요한 의존성 스택(`D2AgentSubjectDepPackages` — serialization·faststreams·stew·results)은 러너의 nimble store가 비어 있으면 fail-closed `UNKNOWN`로 판정 불능이 된다. reusable workflow의 `replay-dep-pins` 입력은 기본으로 bytesview canonical acceptance 환경이 해석한 4개 커밋(전체 SHA, 로컬 pkgs2 `nimblemeta` vcsRevision에서 유래)을 지정하고, 이를 runner에 체크아웃해 `AXIOM_REPLAY_DEP_PATHS`로 엔진에 전달한다 — 엔진 재생 설계 (b)(verbatim 경로, store 탐색 우회, 내용 결정론). 빈 값을 주면 엔진의 nimble store 탐색(설계 (a))이 그대로 사용된다.

## 10. 배포 형태 (v1) — 소스-설치 POLICY 유지 + probe-실증 3계층 배포 지형

- **v1 distribution contract 무변경**: 소스-설치(`productization_contract.md` §1 Distribution — developer-source install)다. 고객 CI는 Axiom 저장소를 **pinned 전체 SHA**에서 체크아웃·빌드한다(prereqs: Nim 2.2.10+, Lean 4.29+, Z3 4.13+).
- **`AXIOM_READ_TOKEN` (임시 조건)**: Axiom이 **private인 동안** 고객 CI의 checkout을 위해 고객 프로비저닝 read 토큰이 필요하다 — 예외는 호출자가 Archright/Axiom 자신인 same-repo 호출이다(github.token이 호출 저장소에 이미 스코프되므로). 임의 외부 고객에게의 개방은 공개 전환이라는 별도 결정 사항이며 본 계약이 약속하지 않는다(§13).
- **권장 배포 인터페이스 — SHA-pinned reusable workflow**: 고객 워크플로우는 `uses: Archright/Axiom/.github/workflows/<file>@<전체 SHA>` 형태로 Axiom 제공 reusable workflow(`.github/workflows/byo-agent.yml`, workflow_call)를 호출하는 것을 권장한다. ref는 전체 커밋 SHA로 핀한다 — GitHub 공식 문서도 안정성·보안을 위해 commit SHA 사용을 권장한다(§12 reusable workflows). 고객 Job(Job 1)의 권한·시크릿은 이 호출 경계에서 Job 2로 전파되지 않는 최소 세트로 유지된다(§9). 호출된 workflow의 `github.token`은 **호출 저장소 스코프**이며, 호출된 workflow가 호출자보다 넓은 권한으로 승격될 수 없다(GitHub: called workflow는 downgrade만 가능) — 그러므로 보고(issues: write)가 필요한 호출자는 호출 job에 해당 권한을 명시해야 한다.
- **probe-실증 배포 지형 (2026-11-02 — wintrover/axiom-reuse-probe + Archright/axiom-reuse-probe-org, composite action·workflow_call 공통 access 경계)** — 3계층:
  - **(a) 비조직(user-owned) 외부 저장소 — 구조적으로 불가**: private 조직 저장소의 action·reusable workflow는 비조직 소비자에서 해석되지 않는다(`Unable to resolve action … repository not found`, Set up job 단계 실패). 후보 설정 `access_level=user`는 조직 소유 저장소에 대해 API가 **422 Validation Failed**로 거부한다 — 플랫폼이 수용하는 값은 `none | organization | enterprise`뿐이다. 유일한 우회는 **복사형(slim copy) workflow + 개인 PAT**이나, 이는 단일-SSOT 핀 성질을 상실한다(A-layer 캐시 키가 `sha256(action.yml + nimble.lock)`를 내장하므로 복사본은 자체 identity domain으로 재키잉된다) — 권장하지 않는다.
  - **(b) Archright 조직 내 private 저장소 — reusable 사용 가능(현재 `none`으로 폐쇄)**: 세 가지 조건. ① 대상 설정: `PUT /repos/Archright/Axiom/actions/permissions/access -f access_level=organization`(Probe B·Phase 4 배포로 end-to-end 실증; 실험 종료와 함께 `none` 원복 — 2026-11-03 최종 관측 `none`. 재개방은 operator 결정. repo-level 전용 엔드포인트로, org-level 엔드포인트는 존재하지 않음). ② 자격 증명: `GITHUB_TOKEN`은 호출 저장소 스코프이므로 Axiom(private) 체크아웃에는 호출자가 `AXIOM_READ_TOKEN` 시크릿을 명시 전달해야 한다(same-repo 호출 예외는 위 행 참조). ③ 워크스페이스 형태: **워크플로 루트에 Axiom 트리 체크아웃 + 주체 저장소는 하위 디렉터리** — `setup-axiom-toolchain` composite action의 keygen이 CWD 상대 경로(`action.yml`, `nimble.lock`)를 해시하므로 루트가 Axiom 트리여야 한다(Probe A2 keygen fail-closed 실패로 CWD 계약 실증).
  - **(b') 조직 내 공개 저장소도 호출자가 될 수 없다 (2026-11-03 fork 실증)**: org access level(`organization`)은 **private 소비자만** 허용한다. GitHub 공식 문서의 접근성 표는 호출자 `public` → 접근 가능 대상 `public`뿐이며, private 저장소의 actions·reusable workflows는 공개(internal 포함) 저장소에서 사용될 수 없고, org access 수준의 안내 문구도 "Access is allowed only from private repositories"로 명시한다. 실행 증거: 공개 fork 호출자에서 `uses: Archright/Axiom/.github/workflows/byo-agent.yml@<전체 SHA>` 참조 시 workflow dispatch가 **422 "workflow was not found"**로 거부되었다(2026-11-03, fork 시도 후 원상복구). 같은 경계로 (c) 공개 전환 전까지 임의 외부·공개 호출자는 구조적으로 차단된다. Phase 4 고객 환경은 이에 따라 **private 조직 저장소**로 적응 착지했다(실행 증거: `docs/evidence/byo_agent_phase4_customer_deployment_2026-11-03.md`).
  - **(c) 임의 외부 저장소 — Axiom 공개 전환 전제, 명시적 유보**: access_level로 해소되지 않는 계층이다. Axiom 저장소의 공개 전환 자체가 전제이며 이는 **사용자 결정 사항**으로 유보한다 — 에이전트가 결정하지 않는다(§13 NOT a public open-access commitment).
- **same-repo 자가검증 (Phase 3 실증)**: `.github/workflows/byo-agent-selftest.yml`은 (b)의 same-repo 특수 사례다 — `uses: ./.github/workflows/byo-agent.yml` 호출이 **org access level 변경 없이** 작동한다(같은 저장소 호출은 access 경계 밖이므로). reusable workflow 호출은 자체 checkout을 수행하지 않으므로 호출된 workflow가 Axiom·주체 checkout을 모두 직접 수행한다.

## 11. Acceptance (음성 테스트 포함)

| # | 시나리오 | 기대 결과 |
|---|---|---|
| A1 | 명제 반증 — `ax prove` exit 1 후 | **보고가 계속 진행된다** — exit 1이 workflow 실패·보고 생략으로 전환되지 않음(§8) |
| A2 | `subject.repository`/`subject.commit` 조작 제출 | `SUBJECT_MISMATCH` — exit 3, 이슈 생성 없음(§5) |
| A3 | Job 1이 가짜 바이너리를 artifact로 투입 | **실행되지 않는다** — Job 2는 자체 빌드 바이너리만 실행(§9 오염 artifact 방지) |
| A4 | `propositions` 빈 배열 | `NO_PROPOSALS`(exit 3) — 절대 PASS 아님, 이슈 생성 없음(§6) |
| A5 | 반증 ∧ 채택 없음 ∧ grounds 기록 없음 | 귀속 **Unknown** — 보고하지 않는다(§4) |
| A6 | 카탈로그에 해석 불가한 specId | `INCAPABLE{UNKNOWN_SPEC}` — **런 계속**(exit 아님), 이슈 미생성, 해당 명제는 레인에 선택되지 않음(§3 — 구 `UNSUPPORTED_SPEC_ID` exit 3 거절의 대체) |
| A7 | 엔진 레인 미장착 spec (카탈로그 해석 가능) | `INCAPABLE{LANE_NOT_EQUIPPED}` — **런 계속**(exit 아님), 이슈 미생성, 검증 미수행(§3 — 구 canonical refusal exit 2의 대체) |
| A8 | 스크립트로 생성한 propositions fixture | **"BYO 실에이전트 실증"과 별도 기록** — 스크립트 항성 테스트는 실제 에이전트 실증 증거로 계수되지 않는다(§0.9 극장 금지 — 위장 실증 방지) |
| A9 | 재생 의존성 미해결(러너 store 공백·`replay-dep-pins` 누락·핀 오류) | `UNKNOWN` — **절대 PASS 아님** — selftest acceptance job이 exit 1 ∧ DISPROVED ∧ BUG_SUSPECTED를 기계 단언한다(§8 첫 run 기록: 판정 없는 green 폐쇄) |
| A10 | claim-form 명제 (`logic`+`expression`) | 수용되나 v1 검증 없음 — `INCAPABLE{UNSUPPORTED_LOGIC}`, 이슈 미생성, 레인에 선택되지 않음(§3·§13) |
| A11 | INCAPABLE 명제의 upstream 보고 | **없다** — INCAPABLE은 보고 대상이 아니며, reportable 유닛이 없으면 보고 0건; rollup은 state·Summary 투영 전용이다(§3·§4 — receipt SSOT 무변경) |
| A12 | 재현성 | 동일 결과의 4요소 — proposals 문서 sha256(워크플로가 `proposals.sha256`으로 고정) · subject commit · axiom commit · `canonicalRunDigest`(report 정본 키) |
| A13 | `ax capability [--json]` | capability-disclosure 표면 — authority는 커밋된 카탈로그(config/spec) + 엔진 dispatch 진실(`laneDispatchEquipped`: **flipped adapter 경로 또는 legacy chain arm 경로 — 둘 다 dispatch 진실이며 엔진이 SSOT**), 출력은 그 projection; subject·`AXIOM_STATE_DIR` 없이 질의 가능하며 capability를 결정하지 않고 공개만 한다 |

## 12. References — GitHub 공식 문서

- **Job-level permissions** (권한 최소화·job 단위 스코핑): [Controlling permissions for GITHUB_TOKEN](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github-token)
- **`GITHUB_STEP_SUMMARY`** (job summary 환경 파일): [Workflow commands for GitHub Actions — Adding a job summary](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions)
- **Reusable workflows — SHA 핀** ("Using the commit SHA is the safest option for stability and security"): [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- **Job status check functions** (`needs`·`if: always()`/`!cancelled()` — 보고 step의 실행 보장): [Evaluate expressions — Status check functions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/evaluate-expressions-in-workflows-and-actions)
- **`gh` `GH_TOKEN` 환경변수** (gh의 공식 네이티브 인증 경로): [gh environment](https://cli.github.com/manual/gh_help_environment)
- **Actions access — private 저장소 컴포넌트 공유 경계** (probe-실증 지형의 플랫폼 근거 — `none|organization|enterprise` 전용, 비조직 공유 불가): [Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-a-private-repository)
- **Reusable workflow 접근성 표** (호출자 `public` → 접근 가능 대상 `public`뿐; §10(b')의 문서 근거): [Reusing workflow configurations — Access to reusable workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations#access-to-reusable-workflows)
- **Probe 실험 기록** (3계층 배포 지형의 실행 증거 — 동일 내용이 §10에 반영됨): `wintrover/axiom-reuse-probe` README @ `3fe5185` (Probe A/B 실행·API 422·원복 기록)

## 13. Non-claims

- NOT a broad AI-code verification guarantee — 본 계약은 입력 채널이지 보증 범위 확장이 아니다(`productization_contract.md` §1 non-goal 불변).
- NOT an agent authentication mechanism — `agent.id`는 미인증 선언이며 에이전트 신원 보장을 주장하지 않는다(§5).
- NOT a proposition adoption path — 명제의 공식 약속화는 인간 `soExplicit` 커밋만 수행한다(§1·§3).
- NOT a new external write surface — 외부 쓰기는 여전히 `ax report --upstream`(gh 서브프로세스) 하나다(§1).
- NOT a portable/deterministic AGENT execution guarantee — 고객 에이전트의 실행 환경·재현성은 고객 영역이며 Axiom이 보장하지 않는다.
- NOT a claim-content verification mechanism — claim-form(`logic`+`expression`)의 **내용은 v1에서 검증되지 않는다**; 수용된 선언은 `INCAPABLE{UNSUPPORTED_LOGIC}`으로 정직 기록될 뿐이며, 어떤 증거·판정을 생산하지 않는다(§3).
- NOT a statement about the subject — `INCAPABLE`은 명제가 이 엔진 버전에서 검증 가능하지 않았다는 intake/dispatch **사실**이다 — 주체 코드의 품질·안전에 대한 판정이 아니며, 전명제 INCAPABLE 런의 exit 0은 "주체가 안전하다"는 의미가 아니다(§8).
- NOT a public open-access commitment — private 동안의 `AXIOM_READ_TOKEN` 요구와 임의 외부 고객 개방은 별도 결정이다(§10).
