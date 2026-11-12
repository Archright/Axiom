# ADR-0029: Nim 언어 의미의 권위와 미해결 사실의 지위 — 컴파일러 유도 fact는 전제(assumption)이지 증거가 아니다

## Status

**PROPOSED (2026-10-04)** — 외부 Nim 대상 의미 검증 workstream(`axiom/semantic-eligibility-gate`)
Phase 0 ADR 기록이다. 본 ADR은 **판정만 기재하며 코드를 변경하지 않는다.** 확정되는 것은
(i) Nim 언어 의미의 권위자, (ii) Axiom의 재구현 금지 범위, (iii) 컴파일러 유도 fact의 지위,
(iv) 플랫폼 미제공 사실의 처리, (v) source-local fact의 계산 허용 및 그 경계다.

**본 ADR의 구현 동행분**: 같은 workstream(`axiom/semantic-eligibility-gate`)에서 §6이 요구하는
배선이 함께 구현된다 — census 토큰 `semantic.unresolved-fact`과 이를 판정하는 조건
(`src/verification/obligation/candidate_eligibility.nim`), 그리고 그 판정이 읽는
`IRFuncDef.bindingUniverseComplete`의 생산자
(`src/infrastructure/external_ir_materializer.nim`). **본 ADR이 승인하는 것은 판정이며,
그 배선의 적합성은 본 ADR의 범위 밖이다** — 배선 자체는 PR 리뷰와 게이트가 판정한다.

**착지 전 선행 조건 (본 ADR은 승인만으로 효력이 발생하지 않는다)**:

1. **제품 계약 정합** — 본 ADR은 외부 Nim 대상 검증의 제품 계약 문구를 확정하지 않는다.
   AGENTS.md §0.12에 따라 수직 슬라이스 계약이 선행한다.
2. **게이트 배선** — 어느 게이트가 어느 판정을 강제하는지는 §6에 명시했으나, 배선은
   `src/gate/**` (§-1 불변)를 건드리지 않는 경로에서만 가능하다.
3. **`FactStatus` 생산자** — §5가 요구하는 "사실별 등급 결속"은 현재 **생성자가 없다**(§7 U4).

---

## Context

### U1 — "컴파일러 의미를 재구현하지 말라"는 규칙이 Nim 언어 의미에는 존재하지 않는다

재구현 금지 조항은 **다른 두 도메인에만** 존재한다.

| 도메인 | 조항 | 범위 |
|---|---|---|
| git | `docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md:60-64` (D8) — "Axiom core는 git merge/rebase 알고리즘을 구현하지 않고" | git 의미 |
| GitHub | `docs/adr/0026-execution-authority-unification.md:67` (ADR-0026 §1 규칙 8) — "GitHub orchestration 재구현 금지" | GitHub 오케스트레이션 |

Nim **언어 의미**(generic instantiation 평가, sizeof 평가, 임의 표현식 타입 추론, 타깃
상수)에 대한 대응 조항은 저장소 문서 어디에도 없다. 전수 검색 결과 `docs/**/*.md`에서
"Nim semantics"는 `docs/spec/certification_continuity_contract.md:240` (INV-9의 **금지
주장 목록** `"Nim semantics certified"`) 한 건뿐이며, 이는 금지이지 재구현 금지 규칙이 아니다.

**결과**: 이 격차는 **금지**가 아니라 **허용**으로 읽힌다. 자유변수로 둔 미해결 Nim 의미를
Axiom이 임의 추정해 후보로 승격해도 현재 문서는 그것을 막지 않는다.

### U3 — "Nim 언어 의미의 권위자는 누구인가"가 명시되어 있지 않다

`docs/spec/certification_continuity_contract.md:71`은 TCB 5층 1층을 다음과 같이 규정한다.

> | Nim lexer/parser/macro runtime | **Qualified**(verified 아님) | Nim 2.2.10 6계층 버전 고정 … + AST identity 계약 |

이 조항은 frontend를 **등급으로만** 규정하고 **권위자를 이름으로 지정하지 않는다**. 같은
문서 `:63`은 certificate가 "Nim frontend 자체의 정확성(qualified — verified 아님)"을
**증명하지 않는다**고 명시하고, `:333`은 Nim manual이 prose spec("This manual is constantly
evolving into a proper specification")여서 **형식 의미론이 부재**한다고 기록한다.

**부분적 대응은 있으나 권위자 이름이 아니다**: `docs/spec/obligation_semantics.md:42`는
`assumptions` 필드를 "의무가 성립한다고 **가정하는** canonical semantic facts 목록"으로
정의하고, `:47`의 C6 불변식이 각 의무의 완전 해석 가능성을 요구한다. 즉 **전제 채널은
규약되어 있으나, 그 전제가 누구의 산출물인가는 규약되어 있지 않다.**

### U6 — 컴파일러 유도 fact가 소비될 수 있는가, 그리고 그 지위는 무엇인가

동결된 제품 계약 claim(`docs/spec/certification_continuity_contract.md:54-59`)은 Axiom이
증명하는 문장을 세 축으로 한정한다. frontend 정확성은 그 축 밖이다(`:63`). 동시에
`:235` INV-4는 "동일 생성기 산출물 간 등가는 증거 불인정"이라 규정한다. 따라서 컴파일러가
유도한 fact를 Axiom이 소비할 때, 그것은 (a) claim 문장 확장인가, (b) INV-4 위반인가,
(c) 둘 다인가가 미결 상태다. `docs/spec/cfg_contract_specification.md:663`은 같은 축의
선례를 이미 확정한다 — bare solver `UNSAT` 단독은 Inconclusive이며, `:671`은
EvidenceValidator 우회를 극장(AGENTS.md §0.9)으로 명시한다.

### 실측 앵커 (2026-10-04, Nim 2.2.10 — AGENTS.md §3 고정 버전과 일치)

환경: `nim --version` → `Nim Compiler Version 2.2.10 [Linux: amd64]`, `Compiled at 2026-04-24`.

`nimsuggest --v3 --stdin` 관측 (probe: `/tmp/adr-adoc/probe/probe.nim`, `type Box[T]` ·
`proc sizeOf[T](x: T): int = sizeof(T)` · `const ten = 10` · `sizeOf(42)`):

| 관측 | 결과 |
|---|---|
| 지원 명령 열거 | `sug\|con\|def\|use\|dus\|chk\|mod\|highlight\|outline\|known` — **`sizeof` 명령은 존재하지 않음** |
| `def 6 6` (`const ten` 선언 지점) | `skConst probe.ten int literal(10)` — **선언 지점 리터럴 형태**이며, 해석된 값·타깃 결과가 아님 |
| `def 10 6` (generic 호출 `sizeOf(42)` 포함 위치) | 무응답 |
| `con 10 15` (임의 표현식 `42`) | 무응답 |

저장소 측 정적 근거도 동일 방향이다 — `docs/spec/axiom_dsl_quirks.md:15`: "`getTypeImpl`
in macro context does **NOT** resolve generic instantiations". 반면 리터럴은 다르다 —
`docs/spec/canonical_ast_identity.md`의 Literal Canonicalization Policy는
`nkIntLit..nkUInt64Lit` → `$n.intVal`로 **원본 AST에 이미 값이 존재하는 것**을 명시한다.

**관측의 한계**: 이 표는 **공식 표면의 부재**만 실증한다. 내부 API(`semExpr` 등)의
export 가능성은 이 관측의 범위 밖이며, Nim 컴파일러가 *어떤 형태로든* 답을 내줄 수 있는지는
본 ADR이 결정하지 않는다(§7 U5).

---

## Decision

### D1. Nim compiler가 Nim 언어 의미의 권위자다 — 단, "Qualified, 미검증 TCB"로 한정한다

- **권위자** = pinned Nim frontend(Nim 2.2.10). Axiom은 **소비자**이며 권위자가 아니다.
- 이 권위자의 등급은 `docs/spec/certification_continuity_contract.md:71`이 이미 선언한
  **Qualified**(verified 아님) 그 이상으로 올라가지 않는다. `:63`이 frontend 정확성을
  증명 대상에서 명시적으로 제외했으므로, D1은 그 조항의 해석을 재확인할 뿐 확장하지 않는다.
- **Derived authority — compiler-as-library**: 컴파일러를 라이브러리로 링크해 semantic fact를
  얻는 경로가 추가되더라도 그 권위자는 **동일한** frontend이며 등급은 동일하다. 링크 경로는
  권위를 높이지 않는다.
- **정합 조건**: 본 판정은 `certification_continuity_contract.md:71`과 모순되지 않으며,
  오히려 그 조항이 **권위자 이름**을 못 정하고 있던 격차를 메운다. §0.5 문서 우선에 따라
  해당 격차 해소는 `docs/spec/certification_continuity_contract.md`의 후속 개정 대상이다
  (본 ADR은 그 문서를 수정하지 않는다 — §7 U2).

### D2. Axiom은 언어 의미를 재구현하지 않는다

다음은 **어떤 형태에서도** 금지된다.

| 금지 | 금지되는 예 |
|---|---|
| generic instantiation 평가기 | `Box[int]`의 instantiated body를 자체 계산해 IR로 내리는 것 |
| sizeof 평가기 | `sizeOf(T)` 호출을 T에 대해 자체 평가해 정수로 대체하는 것 |
| 임의 표현식 타입 추론 | 임의 표현식의 타입을 자체 규칙으로 추론하는 것 |
| 타깃 상수 하드코딩 | `sizeof(uint64) == 64` 류의 타깃 의존 상수 내장 |
| **우회로** | 위 능력을 추정해 얻은 결과로 **후보를 승격**(eligibility 상향)시키는 경로 — D2의 핵심 |

- "우회로 금지"가 실질 조항이다. 재구현을 하지 않더라도, **추정**으로 그 결과를 후보
  상태에 들여오면 우회로는 재구현과 동일한 결과를 낳는다. 그러므로 **eligibility 상향은
  어떤 계산 결과에도 근거를 두지 못한다.**
- 근거 조항: ADR-0020 `:60-64`(D8, git 의미)· ADR-0026 `:67`(규칙 8, GitHub 의미)가
  **같은 형태의 규칙을 다른 도메인에 이미 관용**한다. 본 판정은 그 관용을 Nim 언어 의미로
  확장·명문화한다(U1 해소).
- **타깃 상수 판정의 직접 근거**: `src/core/trusted/semantic_fact_types.nim:104-108`의
  `ConstArithmeticFact`은 `expression = "8*8"` → `value = 64`를 **Axiom이 스스로 계산한
  값**으로 유형화한다. 이 유형은 `sizeOf(uint64) = 64` 하드코딩의 **정확한 형태**이므로,
  D2에 의해 **금지**된다. 같은 판단이 `:97-102`의 `SizeFact`(`bytes`/`bits`를
  `fsDerived`로 선언)에 적용된다. §5가 이 두 유형에 요구하는 등급은 `fsObserved` +
  toolchain 결속이다.
- **스텁 금지 연결**: `src/` 내 평가기 위치에 `check true` 형태의 플레이스홀더를 두는 것은
  AGENTS.md §0.8 위반이며, 본 판정에 의해 추가로 **재구현으로 간주**된다.

### D3. 컴파일러 유도 fact의 지위 — 전제(assumption)로만 소비한다. 증거가 될 수 없다

- **consume-as-assumption**: compiler-derived fact는 검증 대상 프로그램의 **전제**로만
  들어갈 수 있다. IR를 대체하지 않고, solver 결과를 대체하지 않으며, obligation의
  discharged 상태를 만들지 않는다. 정규화된 위치는 이미 존재한다 —
  `docs/spec/obligation_semantics.md:42`의 `assumptions` 필드(정렬된 전제 목록)이며,
  `:47`의 C6 불변식이 그 자기완결성을 보장한다.
- **evidence 금지**: 어떤 경로에서도 compiler-derived fact 단독으로 `Verified` /
  `Safe` / `Proved`를 생성하지 않는다. 근거는 `certification_continuity_contract.md:54-59`
  (claim 스냅샷), `:63`(frontend 미증명), `:235`(INV-4), 그리고
  `cfg_contract_specification.md:663`("Bare solver `UNSAT` alone … yields `Inconclusive`"),
  `:669`("No production path may set `Safe/Proved` from raw solver status …"),
  `:671`("Any shortcut that bypasses `EvidenceValidator` is theater")이다.
- **등급 결속 (enforcement 축)**: `src/core/trusted/semantic_fact_types.nim:29-33`이 이미
  선언한 evidence ladder `FactStatus` = `fsObserved < fsMechanicalDerived < fsDerived < fsUnknown`가
  **유일한 판정 축**이다. 컴파일러 유래 fact는 이 축에서 **`fsObserved`를 넘을 수 없다**.
  `fsDerived`는 **Axiom 자신의 계약에서 기계적으로 유도된 사실**(예: IR 표현 계약)에만 허용된다.
- **provenance 바인딩**: 소비되는 모든 compiler-derived fact는 **toolchain fingerprint에
  결속**되어야 한다. 정합 근거 = `certification_continuity_contract.md:278`(Phase 3.75,
  tier-2 extraction agreement — evidence가 toolchain/subject digest에 결속되는 선례),
  `cfg_contract_specification.md:666`(provenance mismatch는 독립적으로 Inconclusive).
  fingerprint 불일치 = fail-closed, 소비 거부.
  **기존 선언의 유일한 정합 예**: `semantic_fact_types.nim:81-87`의 `TypeIdentityFact`만
  `observationSource: "toolchain-system-nim"` + `toolchainIdentity: "nim-2.2.10"`을 갖고
  `status: fsObserved`이다. 이 **세 필드의 결합이 D3가 요구하는 provenance 정형**이다.
- **등급 강설 금지 (ADR-0017 준용)**: assumption을 품은 산출물은 자기 자신의 진위를 소유하며,
  런타임 컨텍스트가 그 강도를 결정하지 않는다 —
  `docs/adr/0017-trust-claim-authority.md:48-51`("A trust artifact may never assert a stronger
  claim than the strongest evidence actually produced").

### D4. 플랫폼이 제공하지 않는 사실은 영구 fail-closed다 — 추정으로 축소하지 않는다

- Nim 2.2.10이 **공식 표면으로 제공하지 않는** 사실(generic instantiation 결과, instantiated
  body, 임의 표현식 타입, generic 파라미터를 통과하는 sizeof 값 — 실측 앵커 참조)은
  **Axiom이 나중에 구현할 대상이 아니다.** 문서화된 **플랫폼 한계**로 등록된다.
- 해당 사실을 필요로 하는 후보는 **영구 fail-closed**이며, 이는 도구가 성숙해 가는 과정에서
  해소되는 결함이 **아니다**.
- **추정 금지**: 불확실성을 "그럴듯한 값"으로 좁히는 것(타깃 가정·관측 평균·이전 버전 값·
  컴파일러 소스 역공학으로 얻은 값) 모두 금지한다. 이는 D2의 우회로 금지와 같은 조항이다.
- **fail-open 미해결 시 극장**: fail-open 경로는 AGENTS.md §0.9에 따라 `docs/spec/`에
  문서화 + 런타임 로깅된 경우에만 극장이 아니다. **D4의 적용 대상에 fail-open은 없다** —
  §7 U1이 닫히기 전까지.

### D5. source-local fact는 Axiom이 계산할 수 있다 — 단, IR을 대체하는 것은 별도 결정이다

- **허용**: 원본 AST에 값이 이미 존재하는 fact(예: `const x = 10`의 `10`)는 Axiom이 계산할
  수 있다. 이는 컴파일러 의미의 **복제가 아니다** — 값은 소스에 있고, 계산은 소스
  파싱·정규화에 속한다. 근거: `docs/spec/canonical_ast_identity.md`의 Literal Canonicalization
  Policy(`nkIntLit..nkUInt64Lit` → `$n.intVal`)와 Ignored/Preserved 표 — 리터럴 값은
  syntax identity에 **포함**되며, 계약이 이미 이를 Axiom의 정규화 산출로 선언한다.
- **구현 근거 (기존 코드가 이미 이 경계를 그는다)**: `src/verification/obligation/semantic_environment.nim:34-58`의
  `deriveFacts`는 `isCompileTime` **AND** `irLit`인 경우에만 fact를 만들고(`:40-53`),
  그렇지 않으면 `BoundaryRecord(reason: "value-not-literal")`(`:54-56`)로 남긴다.
  **리터럴이 아닌 컴파일타임 값은 이미 미해결로 기록된다** — D5의 허용 범위와 정확히 일치한다.
- **금지**: source-local fact가 **IR을 대체**하는 것은 금지한다. 2-extractor
  differential(`certification_continuity_contract.md:278`, TCB 감축 메커니즘 — `:73`)을
  깨므로, source-local fact가 canonical extractor의 출력이 될 경우 **그 자체로 별도
  결정(ADR)**이 필요하다. 추가 근거: `cfg_contract_specification.md:650-651`("No identity
  from one layer may be used as a substitute for another layer's identity").
- **경계선**: D2·D3과 D5의 분기는 **"답이 컴파일러에 있는가"가 아니라 "답이 원본 소스에 있는가"**다.
  `sizeof(uint64)`의 답은 소스에 없고 컴파일러(타깃)에 있다(D2·D4). `const x = 10`의 답은
  소스에 있다(D5). **완전성 게이트는 이미 fail-closed로 구현되어 있다** —
  `semantic_environment.nim:218-222`(`filterResolvableFacts` Gate 1)는
  `translationLossFree ∧ bindingUniverseComplete`가 거짓이면 **모든 fact를 거부**하고
  빈 환경을 반환한다(`reason: "completeness unproven"`).

---

## Rejected Alternatives (기각한 대안)

### R1. "Nim 언어 의미를 Axiom이 직접 모델링한다" — **기각**

generic instantiation·sizeof·임의 타입 추론을 Axiom 내부 평가기로 구현한다. **기각 사유**:
(i) D1상 권위자가 아닌 소비자가 권위자의 결정을 대체한다. (ii) `certification_continuity_contract.md:71`
의 Qualified 등급이 서술하는 "미검증 TCB"를 Axiom이 **새로 추가**해 TCB를 넓힌다(§0.2 우아함
위반). (iii) Nim manual에 형식 의미론이 없다는 `:333`의 고지에 따라 평가기의 정당성 자체를
증명할 방법이 없다. (iv) 평가기의 버그는 정적으로 검출되지 않는 silent divergence다 — AGENTS.md
§0.9 극장 금지의 실질 영역.

### R2. "컴파일러 유도 fact를 증거로 소비한다" — **기각**

nimsuggest 등으로 얻은 fact를 obligation의 discharged 증거로 쓴다. **기각 사유**:
(i) `certification_continuity_contract.md:235` INV-4 — 동일 생성기 산출물 간 등가는 증거가
아니다. compiler-derived fact는 정의상 같은 생성기(frontend)의 산출물이다. (ii) `:63`이
frontend 정확성을 증명 대상에서 제외했다. (iii) `cfg_contract_specification.md:663·669·671`과
**동일 축**(bare solver UNSAT 단독 = Inconclusive, 우회 = theater)이다. (iv) 제품 계약 claim
(`:54-59`)을 조용히 확장한다 — AGENTS.md §0.12 위반.

### R3. "요청 시 점유된 fact를 하드코딩/캐시한다" — **기각**

타깃 상수 테이블(`sizeof(uint64) = 64` 등), 이전 실행 캐시, 컴파일러 소스 역공학 값을
fallback으로 쓴다. **기각 사유**: D4의 추정 금지에 직결. 게다가 fallback이 명시적으로
기록되면 그 **가용성 자체가** claim이 되어 `certification_continuity_contract.md:54-59`의
스냅샷 밖으로 나간다. 미기록 fallback은 극장(AGENTS.md §0.9)이다.
**현 저장소의 대조 사례**: `semantic_fact_types.nim:104-108`(`ConstArithmeticFact`의
`8*8 = 64`)와 `:97-102`(`SizeFact`)는 이 기각 대안의 유형적 형태이며, D2·D3이 요구하는
바탕으로 status/provenance를 **교정해야** 한다(§7 U4).

### R4. "Axiom이 미해결 fact를 발견하면 자가적으로 해소한다" — **기각**

자유변수로 탐지된 사실에 대해 Axiom이 후보(예: `Box[int]`의 body)를 자체 구성해 증명을
진행시킨다. **기각 사유**: D2의 우회로 금지. 계산하지 않더라도 **답을 만들어내는 것**이
estoppel이다 — 후보가 증명 가능해지는 것 자체가 추정 결과의 승격이므로, 계산 여부와
무관하게 금지된다. UNKNOWN은 **상태**로 남아야 하고 **해결 경로가 없어야** 한다(D4).

### R5. "source-local fact 계산을 IR 하강에 바로 배선한다" — **기각(보류)**

source-local fact를 canonical extractor의 출력이 되게 한다. **기각 사유**: 2-extractor
differential(`certification_continuity_contract.md:278`)의 한쪽을 없애므로 INV-4 구조적
독립성이 깨진다. D5는 **계산 허용**만 판정하고 **IR 대체**는 명시적으로 미결로 남긴다
(§7 U3).

### R6. "이 ADR이 §0.11 어휘를 새로 정의한다" — **기각**

"Nim semantics"를 Axiom 용어로 정본화한다. **기각 사유**: AGENTS.md §0.11은 도메인 용어의
정본을 `src/`·`docs/spec/` SSOT에 두게 한다. 본 ADR이 새 용어를 만들면 §0.11이 요구하는
SSOT가 문서 밖으로 새어난다. §7 U6.

---

## Consequences

### §6 본 판정의 enforcement 지점 — census 토큰 `semantic.unresolved-fact`

새 census 토큰 `semantic.unresolved-fact`는 §7 U1–U4의 **자명적 UNKNOWN**(플랫폼 미제공)을
표면화하는 유일한 census 사유다. D4의 추정 금지 때문에 **다른 사유로 이 토큰을 낼 수 없다**
— 즉 이 토큰은 미해결 사실의 **보고 채널**이지 해소를 위한 문이 아니다.

| 항목 | 판정 | 근거 |
|---|---|---|
| 토큰 문자열 | `semantic.unresolved-fact` | 닫힌 어휘 `CandidateRejectionReason`(`src/verification/obligation/candidate_eligibility.nim:59-67`)에 추가. `RejectionReasonToken` total table(`:79-90`)이 schema change로 취급한다(`:88-91`) |
| 분류 | `elUnsupported` (INELIGIBLE) | "지원하지 않음"은 정적 admission 판정이므로 기존 4분류(`:41-49`)에 흡수된다 — enum 확장 불필요 |
| 판정 시점 | census 시점(모든 semantic fact 유도 **이전**) | semantic environment가 아직 없으므로 IR 형태만으로 결정 가능해야 한다 — fail-closed의 전제 |
| 빈 census 해석 | `NO_EXTERNAL_CANDIDATE` | "빈 census는 어떤 증거도 아니다"(`:229-233`)와 정합 — 미해결 fact가 없다는 관측도 검사 능력의 증명이 아니기 때문이다 |
| 어휘 변경 성격 | total table 추가 — 승인 필요 | `candidate_eligibility.nim:89-90`("closed … part of the census contract"), `:93-95`("changing one is a schema change") |

### §6b 판정별 영향 표

| 판정 | 확정 | 미확정(잔여) |
|---|---|---|
| D1 권위자 | Nim frontend = 권위자, Qualified 한정 | frontend를 링크해 쓰는 경로의 계층 서술(U5) |
| D2 재구현 금지 | 평가기·추론기·타깃 상수·**우회로** 금지 | "우회로"의 정적 검출 가능성(U1) |
| D3 fact 지위 | assumption only, 등급=`fsObserved` 한정, provenance=toolchain 결속 | 등급 생산자 부재(U4) |
| D4 미제공 사실 | 영구 fail-closed | 게이트 배선(U4) |
| D5 source-local | 계산 허용 (기존 `deriveFacts`가 이미 이 경계를 그음) | IR 대체 여부(U3) |

**긍정**: 자유변수로 남던 구조적 구멍이 **닫힌다**. 미해결 의미 사실은 이제 (a) 계산 금지,
(b) 증거 승격 금지, (c) 추정 금지로 세 겹 모두에서 차단되어 있고, (d) 조용히 소비될 수 없다.
완전성 게이트(`semantic_environment.nim:218-222`)와 census 게이트가 **서로 독립적으로**
fail-closed이므로 한쪽의 실패가 다른 쪽을 우회할 수 없다.

**부정(residual — 치명적이지만 의도된 비용)**:

- 검증 가능 후보 집합이 **영구적으로 축소**된다. generic을 자유롭게 쓰는 외부 코드는 Axiom이
  영구 fail-closed로 닫힌다. 이는 도구의 약점이 아니라 **문서화된 플랫폼 한계**(D4)이며,
  축소된 범위 자체가 제품 계약으로 선언되어야 한다(§0.12 — 본 ADR은 그 계약을 확정하지 않는다).
- census 토큰 schema change가 뒤따른다. 승인 없이 배선하면 census contract 위반이다.

---

## 잔여 한계 (Residual Limits)

**본 ADR이 닫지 못한 것** (기재만, 해결 주장 없음):

- **U1 — D2의 정적 강제 장치 미설계.** "우회로 금지"와 "추정 금지"를 현재 어떤 게이트도
  검사하지 않는다. 본 ADR은 판정만 확정했고 `src/gate/**`는 §-1 불변이라 손대지 않았다.
  배선 전까지 D2/D4는 **문서 규율**이지 기계 강제가 아니다.
- **U2 — spec 반영 미착수.** `docs/spec/certification_continuity_contract.md:71`은 여전히
  권위자 **이름**이 없는 채다. 본 ADR이 메운 격차는 ADR 텍스트에만 존재한다.
- **U3 — source-local fact의 IR 대체 미결.** D5가 명시적으로 미결로 남겼다.
- **U4 — `FactStatus` 생산자 부재 + 현 선언의 등급 교정 필요.**
  `semantic_fact_types.nim:29-33`의 ladder는 **선언만 있고 어디에서도 값이 대입되지 않는다**
  (`src/**` 전수 검색에서 `fsUnknown`·`fsMechanicalDerived`·`fsObserved`·`fsDerived`의 사용처는
  선언 라인뿐). 동시에 `:85`, `:93`, `:102`, `:107`, `:115`의 기본값 주석은
  `SizeFact`/`ConstArithmeticFact`/`IRRepresentationFact`에 `fsDerived`를 부여한다 — D3가
  금지하는 등급이다. **본 ADR은 코드를 고치지 않으므로 이 불일치는 그대로 남는다.**
- **U5 — compiler-as-library 계층 서술 미결.** D1은 권위자가 동일함을 선언했으나
  "frontend를 링크한 코드"가 어느 신뢰 층·어느 실행 경계에 놓이는지는 확정하지 않았다.
- **U6 — §0.11 어휘 정본 미등록.** 본 ADR이 쓴 "compiler-derived fact", "source-local fact",
  "unresolved fact"는 §0.11상 인용 출처가 `src/`/`docs/spec/` SSOT에 필요하다(§R6).
- **U7 — census 분류 우선순위.** 동시 성립 시 판정 순서는 **rule F(`divisor.constant`,
  `vacuous.tautology`) → rule S(`semantic.unresolved-fact`)** 로 고정되었다. rule S는 rule F가
  이미 증명 가능성을 인정한 후보에만 도달하므로 기존 버킷을 재표시하지 않는다. 이 순서는
  `tests/unit/candidate_eligibility_test.nim`의 되돌림 사례가 고정한다.
- **U8 — 배선은 판정에 포함되지 않는다.** Status의 구현 동행분 참조. `bindingUniverseComplete`의
  생산자가 이 workstream에서 함께 배선되었으므로, 게이트는 더 이상 "미설정 필드"를 읽지 않는다.
  남는 한계는 U1이다 — **D2의 "재구현·추정 금지"를 검사하는 게이트는 여전히 없다.** 현재의
  기계 강제는 U7의 게이트와 이 배선뿐이며, 재구현이 재발하면 그것을 막는 것은 리뷰와
  결정 바인딩이다.

**본 ADR이 하지 않은 것(범위 밖)**: 제품 계약 확정 · waiver 추가 · baseline 변경 ·
`docs/spec/` 수정. (코드 변경은 본 ADR의 기여가 아니며, 배선은 같은 workstream에서
Status가 밝히는 바와 같이 별도 산출물이다.)

**관측의 한계 재확인**: §Context 실측은 nimsuggest v3의 **공식 표면 부재**만 실증한다.
내부 API export 가능성, 미래 툴체인 버전의 표면 추가, 다른 쿼리 모드에서의 가용성은
증명되지도 반증되지도 않았다. D1은 이를 근거로 **판정**했지만, 실측이 판정을 넘어설 수는 없다.

---

## 검증 기록

본 ADR은 **문서 전용 작업**이며 코드·데이터 산출물을 생성하지 않는다. 수행한 관측:

| 명령 | 결과 |
|---|---|
| `nim --version` | `Nim Compiler Version 2.2.10 [Linux: amd64]`, `Compiled at 2026-04-24` |
| `nimsuggest --v3 --stdin probe.nim` (probe: `/tmp/adr-adoc/probe/probe.nim`) | Context 실측 앵커 표의 4개 행 |

`make`는 **실행하지 않았다**(병렬 작업자와 shared nimcache 경합 회피). 컴파일 검사가 필요한
코드는 본 ADR이 변경하지 않았으므로 수행하지 않았다. probe 파일은 `/tmp` 산출물이며 저장소에
포함되지 않는다.

---

## References

**본 ADR이 직접 인용한 저장소 근거** (`파일:라인`):

- `docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md:60-64` — D8 git semantics
  재구현 금지 (U1 선례)
- `docs/adr/0026-execution-authority-unification.md:67` — §1 규칙 8 GitHub orchestration
  재구현 금지 (U1 선례)
- `docs/adr/0017-trust-claim-authority.md:48-51` — trust artifact는 현재 검증이 산출한 가장
  강한 증거보다 강한 주장을 하지 않는다 (D3 등급 강설 금지)
- `docs/spec/certification_continuity_contract.md:54-59` — §2 증명 claim 스냅샷 (U6)
- `docs/spec/certification_continuity_contract.md:63` — frontend 정확성 미증명 (U3·U6)
- `docs/spec/certification_continuity_contract.md:71` — TCB 5층 1층 = Qualified (U3)
- `docs/spec/certification_continuity_contract.md:73` — 이중 extractor 합의 = TCB 감축
  메커니즘(폐쇄 아님) (D5)
- `docs/spec/certification_continuity_contract.md:235` — INV-4 구조적 독립성 (U6)
- `docs/spec/certification_continuity_contract.md:278` — Phase 3.75 Tier 2 extraction agreement
  (D5 provenance·2-extractor 근거)
- `docs/spec/certification_continuity_contract.md:333` — Nim manual은 prose spec, 형식
  의미론 부재 (U3)
- `docs/spec/cfg_contract_specification.md:650-651` — 층 간 identity 대용 금지 (D5)
- `docs/spec/cfg_contract_specification.md:663` — bare solver UNSAT 단독 = Inconclusive (U6·D3)
- `docs/spec/cfg_contract_specification.md:666` — provenance mismatch = Inconclusive (D3)
- `docs/spec/cfg_contract_specification.md:669-671` — Safe/Proved는 raw status로 금지, 우회 =
  theater (D3)
- `docs/spec/obligation_semantics.md:42` — `assumptions` = 전제로 가정하는 canonical semantic
  facts 목록 (D3 소비 위치)
- `docs/spec/obligation_semantics.md:47` — C6 불변식: `subject · assumptions · predicate ·
  derivationRule` 완전 해석 (D3 자기완결성)
- `docs/spec/axiom_dsl_quirks.md:15` — `getTypeImpl`은 generic instantiation을 해석하지 않음
  (실측 보강)
- `docs/spec/canonical_ast_identity.md` — Literal Canonicalization Policy(`nkIntLit..nkUInt64Lit`
  → `$n.intVal`) (D5 source-local 근거)
- `src/core/trusted/semantic_fact_types.nim:14-17` — `FactOrigin` 두 종의 정의 (D3·D5 분기)
- `src/core/trusted/semantic_fact_types.nim:22-24` — `foCompileTimeBinding` / `foTemplateInstantiation`
- `src/core/trusted/semantic_fact_types.nim:29-33` — `FactStatus` evidence ladder (D3 enforcement 축)
- `src/core/trusted/semantic_fact_types.nim:81-87` — `TypeIdentityFact`: `observationSource` +
  `toolchainIdentity` + `fsObserved` (D3 provenance 정형의 유일한 현 예)
- `src/core/trusted/semantic_fact_types.nim:89-95` — `IRRepresentationFact`: Axiom 로컬 계약
  (`SemanticProfileV1Hash`)이라 `fsDerived`가 정당한 유일한 유형
- `src/core/trusted/semantic_fact_types.nim:97-102` — `SizeFact` — D2/D3 교정 대상 (R3 대조)
- `src/core/trusted/semantic_fact_types.nim:104-108` — `ConstArithmeticFact` (`8*8 = 64`) —
  D2 금지 형태의 현 저장소 실체 (R3 대조)
- `src/core/trusted/semantic_fact_types.nim:110-117` — `InstantiationBindingFact`의
  `scopeLimitation: "observed instantiation-scoped binding — positional correspondence only"`
  (관측으로 축약된 generic 인스턴스화 — D4 대조)
- `src/verification/obligation/semantic_environment.nim:34-58` — `deriveFacts`: 리터럴만 fact,
  나머지 `value-not-literal` 경계 기록 (D5 구현 근거)
- `src/verification/obligation/semantic_environment.nim:218-222` — `filterResolvableFacts` Gate 1:
  완전성 미증명 시 **전량 거부** (D4 구현 근거)
- `src/verification/obligation/candidate_eligibility.nim:41-49` — 4분류 enum (§6 분류 근거)
- `src/verification/obligation/candidate_eligibility.nim:59-67` — 닫힌 `CandidateRejectionReason`
  어휘 (§6 토큰 근거)
- `src/verification/obligation/candidate_eligibility.nim:79-90` — `RejectionReasonToken`
  total table + 닫힌 어휘 선언 (§6 schema change 근거)
- `src/verification/obligation/candidate_eligibility.nim:93-95` — wire token 변경 = schema change
- `src/verification/obligation/candidate_eligibility.nim:229-233` — `NO_EXTERNAL_CANDIDATE`:
  "an empty census is not evidence of anything" (§6 빈 census 근거)

**규범 근거**: `AGENTS.md` §-1(불변 파일) · §0.2(우아함 — 하드코딩 금지) · §0.5(문서 우선) ·
§0.6(정적 우선) · §0.8(스텁 금지) · §0.9(극장 금지) · §0.10(결정 바인딩) · §0.11(어휘) ·
§0.12(제품 계약 선행) · §3(Nim 2.2.10 고정).

**선례(외부, §0.5)**: DO-330 / FAA AC 20-115D 도구 자격(tool qualification) —
`certification_continuity_contract.md:332`(frontend의 "qualified" 지위) · CompCert CACM §5
(미검증 parser 잔존 TCB) · `certification_continuity_contract.md:327-331`(SPARK · Pnueli
translation validation · Knight–Leveson — INV-4 생태계 전례) · Lean FAQ("번역 도구의 대응 가정
은 TCB가 된다", `:320`).

**실측**: `nim --version` = Nim Compiler Version 2.2.10 [Linux: amd64] (Compiled at 2026-04-24) ·
`nimsuggest --v3 --stdin` 관측 2026-10-04 (Context 실측 앵커 표 참조).

**선행 실험 기록**(판정과 직접 결합하지 않으나 같은 경계를 다룬다):
`experiments/act2-wpj2-semantic-facts/probe/ingress-fidelity.md`(`bindingUniverseComplete = false`
→ fact 전면 거부) · `experiments/act2-r0-atom-getbitsbe/completeness/*.json`
(`translationLossFree=false`, `opaque-boundary-present`, `sourceBindingCount=15` vs
`irBindingCount=13` — D4의 실측 사례).

**관련 선행 ADR**: ADR-0020(executor boundary·D8) · ADR-0021(execution authority·D6) ·
ADR-0026(실행 authority 단일화·§1 규칙 8) · ADR-0027(착지 authority 위임) · ADR-0017(trust
claim authority).

---

*작성일: 2026-10-04. PROPOSED — 판정 기록이며 코드 변경·토큰 배선·제품 계약 확정을 포함하지
않는다. §Residual Limits의 U1~U8이 닫히기 전 "재구현 금지·fail-closed 강제"가 **기계 강제**
되었다고 주장하지 않는다.*