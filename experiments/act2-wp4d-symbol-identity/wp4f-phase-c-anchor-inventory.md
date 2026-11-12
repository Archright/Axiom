# WP4-f Phase C — Anchor Inventory Measurement: nim-stew에 A4/planning 통과 함수 존재 여부

EXPERIMENT_ID: act2-wp4f-c-anchor-inventory
PARENT: act2-wp4f-phase-b (Blocker B — TheaterGuard illFormed는 의도된 동작)
SUBJECT: nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859
STATUS: **측정 완료. nim-stew에서 canonical 실행 경로를 통해 A4(planning)까지 도달하는 함수는 없음.**
결과: `verified=0/40`. zero-drift 아님(외부 검증 대상이라 verified 0이 정상 결과).

---

## Question

WP4-f Phase B 결론("postcondition goal을 가진 함수를 anchor로")을 실행하려면,
nim-stew 전체에서 **canonical 실행 경로를 통해 A4/planning까지 도달하는 함수가
실제로 존재하는가**를 묻는 것이 이 Phase C의 질문이다.

이 질문은 정적으로 답하지 않고 **empirical로 측정**한다.

- 정적 후보(enum 반환 → ordinal-range postcondition 합성 가능)는 존재한다.
- 그러나 canonical 실행 경로(CLI `--target` + frontier eligibility gate)를
  실제로 타고 간다면 어디까지 가는지가 진짜 질문이다.

---

## 방법 1 — 병렬 서브에이전트 2개 (정적 × 경험적)

### 정적 에이전트 (agent-96)
명시적 `{.axiom:}` pragma / `post:` / clamp 패턴 전수 검색 결과:
- `{.axiom:}` / `post:` / `pre:` / `[post` pragma: **0건**
- case-object 반환 함수: **0건**
- clamp 패턴(int 반환 + if-tree clamp): **0건**
- 단, **enum 반환 함수 6개** 존재:
  `base32.nim:135/200 encode/decode`, `base36.nim:62/123 encode/decode`,
  `base58.nim:60/126 encode/decode` — `{.pure.} enum`(`Base32Status`/`Base36Status`/`Base58Status`) 반환.
  → 정적으로는 ordinal-range postcondition 합성 경로(contract_synthesis.nim:216-222)가 열릴 수 있다는 예측.

### 경험적 에이전트 (agent-95)
`ax prove --project nim-stew --limit 50` 전체 스캔:
- 외부 후보 46개 중 **`elProofCandidate` 0개**.
- `elNoObligation` 10, `elUnsupported` 3, 나머지 ambiguous overload / not found.
- getBitsBE만 유일하게 obligation 생성 → empty SMT → `illFormed`.

→ 두 에이전트 결과가 부분 배치. 정적은 "enum 반환 6개가 가능성", 경험적은 "0개 도달".
따라서 **enum 반환 함수가 실제 canonical 경로를 타는지 직접 재측정**이 필요했다.

## 방법 2 — 직접 재측정 (본 Phase C)

### 2a. enum 반환 encode/decode를 CLI canonical target으로
`bin/ax prove --project <subject> --target '<module>::<encode|decode>' --limit 1`:

| target | resolve | 비고 |
|--------|---------|------|
| `stew/base36.nim::encode` | NotFound | frontier에 없음 |
| `stew/base36.nim::decode` | **Ambiguous** | "external candidate ambiguous overload: decode" |
| `stew/base32.nim::encode` | NotFound | frontier에 없음 |
| `stew/base58.nim::encode` | **Ambiguous** | "external candidate ambiguous overload: encode" |

→ enum 반환 함수는 전부 generic(`btype: typedesc[...]`) + overload라
**canonical target 해석에서 먼저 실패**(0=NotFound 또는 >1=Ambiguous).
WP4-e에 따라 fail-closed. IR/planning 단계에 도달하지 못함.

### 2b. 전체 트리 스캔 (limit=60)
`ax prove --project nim-stew --limit 60`:
- `frontier eligibility gate: excluded 55 non-proof-candidate candidate(s); eligible=5`
- 5개 eligible이 IR pipeline으로:
  - `decodedLength`/`encodedLength` → `[tautology] invariant is tautological — REJECT`
  - `proximityScore` 등 → `[implication] invariant does not imply postcondition`
  - `getBitsBE` → `[TheaterGuard] empty SMT → illFormed`
- `[SKIPPED_BY_THEORY]`: base32/base36/base58의 `decodedLength`/`encodedLength`
- `Verification-Gate: UAP produced 0 results (requests=5)`
- **최종: `verified=0/40`, `verifiedRatio=0.0000`**

---

## 결론

**nim-stew@c75502c에서 canonical 실행 경로를 통해 A4(planning)를 통과하고
실제 proof(수학 UAP → Z3 → Lean → KAA → tcVerifiedProof)까지 도달하는 외부 함수는 존재하지 않는다.**

정적 예측("enum 반환 → postcondition 합성")은 canonical 경로에서 실증되지 않았다.
모든 enum 반환 함수는 generic/overload라 target 해석/eligibility/theory 단계에서 먼저 차단된다.

실증된 도달 가능한 외부 함수의 실패 지점은 다양하며 **각각 정직하고 상이하다**:

| 함수 | 도달 단계 | verdict | 원인 |
|------|-----------|---------|------|
| decodedLength / encodedLength | IR pipeline | `skipped by theory` / `tautology REJECT` | anti-vacuity: 합성 invariant가 자명(tautology). 올바른 거부. |
| getBitsBE | IR pipeline → TheaterGuard | `not_verifiable:illFormed` | postcondition goal 없음 → empty SMT. 올바른 fail-closed. |
| encode/decode (base32/36/58) | target 해석 | NotFound / Ambiguous | generic(typedesc) + overload. WP4-e fail-closed. |
| proxymityScore 등 나머지 | IR pipeline | `invariant does not imply postcondition` | precondition-safety obligation이 post를 함의하지 못함. |

---

## Classification

- 결과: `verified=0/40` (외부 검증 대상). **correct zero** — anti-vacuity/theater/theory가
  가짜 성공을 올바르게 차단.
- 이것은 Axiom "결함"이 아니라 **capability boundary + subject annotation gap** 이다:
  1. nim-stew는 명시적 contract pragma(`{.axiom:}`)가 전혀 없음
  2. Axiom의 postcondition 합성은 enum(단 반환 함수가 generic이면 차단됨)/clamp에만 의존
  3. 따라서 nim-stew 원본 그대로는 non-vacuous external proof를 만들 수 없음

## Non-Claims

- 이 측정은 subject를 수정하지 않았다(니엄strict baseline 유지).
- Axiom(anti-vacuity/theater/theory gate)을 약화시키지 않았다. 수정 금지.
- "verified=0"이 Axiom이 nim-stew를 "못 분석한다"는 뜻이 **아니다**.
  소스→심볼→IR→obligation→eligibility까지는 성공하고, proof goal(postcondition)이
  없어서 real proof로 넘어가는 단계에서 정직하게 멈추는 것이다.
- anchor를 임의로 "재선정"해도 동일한 경계를 만난다(위 표 참조).

## Interpretation

Act 2의 성공 기준("외부 external symbol 하나가 non-vacuous obligation →
Z3 → Lean → KAA → tcVerifiedProof")을 nim-stew 그대로의 subject로 달성하는 것은
**현재 postcondition 합성 범위 안에서는 불가능**하다. 이는 실험의 정직한 결과이며
AGENTS.md §10(실패 귀속)에 따라 subject가 아니라 **Axiom의 postcondition-synthesis
coverage 한계**로 귀속된다.

## Evidence

- `bin/ax prove --project nim-stew --limit 60` stdout:
  `frontier eligibility gate: excluded 55 ... eligible=5`,
  `[tautology] ... REJECT`, `[implication] ... does not imply postcondition`,
  `[SKIPPED_BY_THEORY]`, `verified=0/40`, `UAP produced 0 results`.
- 직접 실행 로그: 본 WP 실행 시 `/tmp/wp4f-fullscan.log` (제한 60).
- 대상 CLI 실행(2a): 4개 열거 결과 표.
- Axiom 소스: `src/core/trusted/contract_synthesis.nim:208-267` (postcondition 합성 조건).
- 정적 에이전트: nim-stew에 `{.axiom:}` / clamp / case-object 반환 0건 (agent-96).

## Next — 결정 지점 (open, 사용자 판단 필요)

A4를 통과하는 anchor가 nim-stew 원본에 없으므로, non-vacuous external proof를
얻으려면 다음 세 길 중 하나를 정해야 한다. **무엇을 선택하든 subject 수정 또는
Axiom 확장이며, 각각 실험 정당성이 별도 기록되어야 한다.**

1. **Postcondition 합성 확장 (Axiom 쪽)** — clamp 이외 패턴(예: bit-manipulation이
   특정 post를 함의하는 규칙)이나 generic의 구체 인스턴트화(postcondition를 얻기 위한
   `T` 고정)를 합성에 추가. → Axiom-side 변경, 별도 WP로 승격. (몇 시간~며칠 규모)
2. **명시적 contract 주입 (subject variant)** — nim-stew에 `{.axiom:[post:].}`를
   추가한 experimental variant를 만들고, baseline과 분리 기록. AGENTS.md §2에 따라
   variant 원본 보존 + 이유/영향 기록 필요. (이것은 "baseline 수정 금지"와 별개 실험 variant)
3. **Act 2 목표 재조정** — nim-stew 대신 contract 합성이 쉬운 다른 subject(또는
   자체 repo의 enum/clamp 함수)로 첫 external proof를 완성하고, nim-stew는
   "annotation-gap subject"로 taxonomy 분류만 남긴다.

측정 결과: **옵션 1(Axiom 쪽 postcondition 합성 확장) 또는 옵션 2(contract 주입 variant)**
없이는 nim-stew 최초 proof slice가 성립하지 않는다. 최소 변경을 원하면 옵션 2가
(주입할 pragma가 작기 때문에) 가장 작지만, subject를 건드리므로 AGENTS.md §2의
variant 절차를 완전히 밟아야 한다.

(이 문서가 이 WP의 사전 결정 문서다. 구현은 수행하지 않았다.)
