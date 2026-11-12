# Canonical Verification Obligation Semantics

> **Status**: Normative SSOT — P0 규범 문서  
> **Created**: 2026-08-18  
> **Phase**: P0 (규범 정의, 코드 미구현)  
> **Related**: [VKD — Verified Kernel Density](./verification_density.md), [Two-Phase Verification Pipeline](./two_phase_verification.md), [Query No-Obligation Debt Analysis](./query_no_obligations_debt.md), [Certificate / Asset Lifecycle Contracts](./cert_lifecycle_contracts.md)  
> **AGENTS.md 참조**: §0.1 (프로젝트 목적), §0.9 (Theater 금지), §0.12 (Product Contract), §4 (Guardian)

---

## 1. Purpose

이 문서는 Axiom 검증 파이프라인에서 **Verification Obligation**(검증 의무)의 정의를 불변 규범으로 고정한다. "무엇을·왜·어떻게 증명해야 하는가"에 대한 canonical semantic property를 규정하며, backend/env 독립적인 단일 정규화 경로를 제공한다.

이 규범은 다음 세 가지 문제를 해결한다:

1. **Postcondition ∅ → Obligation ∅ 누수**: CHC/Spacer 백엔드가 postcondition이 없으면 의무도 없다고 판단하여 증명을 스킵하는 경로 차단 (§1.2 C0).
2. **Backend obligation 선택 권한 부재**: 백엔드가 의무 존재 여부를 결정하지 못하도록 C1/C7 강제 (§5).
3. **NoApplicable vs Unsupported 혼동**: scope 밖(Unsupported)과 의미론적 적용 불가(NoApplicable)를 명확히 분리 (§4).

---

## 2. Definitions

### 2.1 Verification Obligation

**Verification Obligation**은 IRFuncDef의 canonical semantic facts로부터 유도되는 **반드시 증명되어야 하는 속성**이다. 각 의무는 다음 5-튜플로 완전히 고유하게 식별된다:

```
ObligationID = SHA-256(subject ‖ kind ‖ canonicalAssumptions ‖ canonicalPredicate ‖ derivationRule)
```

여기서 `‖`는 바이트열 연결(concatenation)을 나타낸다. 이 해시는 **환경·backend 무관**하게 동일 입력에 대해 항상 동일한 값을 생성한다.

**Obligation의 구성 필드 (C6 Closure):**

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | `string` (hex) | 위 5-튜플 SHA-256 해시 |
| `kind` | `ObligationKind` | 의무의 종류 (divSafety, indexSafety, loopBound, loopVariant, precondition, postcondition) |
| `subject` | `string` | 의무가 적용되는 IR 표현식 또는 함수 시그니처 |
| `assumptions` | `seq[string]` | 의무가 성립한다고 가정하는 canonical semantic facts 목록 (정렬됨) |
| `predicate` | `string` | 증명 대상 proposition (정규화된 논리식) |
| `derivationRule` | `string` | 이 의무를 유도한 규칙 ID (본 문서 섹션 참조) |
| `provenance` | `ObligationProvenance` | 생성 경로 (Generated / NoApplicable / Unsupported / IllFormed) |

**C6 불변식**: 각 의무는 `subject · assumptions · predicate · derivationRule`만으로 완전하게 해석 가능해야 한다. backend 상태, 환경 변수, 솔버 설정에 의존하는 정보는 의무 레코드에 포함되지 않는다.

### 2.1a Subject-Bound Obligation Identity (I1 — evidence-facing identity)

5-튜플 id(§2.1)는 **무엇을** 주장하는지는 고정하지만, 그 주장이 **어떤 lowered subject 의미론**에 대한 것인지는 고정하지 않는다. 동일 name/kind/assumptions/predicate/derivationRule을 공유하면서 본문(lowering)이 다른 두 funcDef는 동일한 5-튜플 id를 가지므로, 하나 아래 봉인된 증거가 다른 쪽의 섀도 모델에 부착될 수 있다. **증거 대면(evidence-facing) id**는 최소 바인딩 집합을 소화하여 이 경계를 닫는다:

```
ObligationId(bound) = SHA-256(
    "obligation-bound-v1"
  | "tuple="        obligationTupleId            = SHA-256(subject ‖ kind ‖ canonicalAssumptions ‖ canonicalPredicate ‖ derivationRule)
  | "treeMerkle="   subjectTreeMerkleRoot        = computeSourceMerkleRoot(subject tree)
  | "module="       subjectModuleSha256          = §6a sourceHash (subject 모듈 소스 바이트의 SHA-256)
  | "git="          subjectGitRef                = subject를 고정하는 git commit-or-tree hash
  | "pnodeV2="      pnodeCanonicalV2Digest       = computeCanonicalAstHash (docs/spec/canonical_ast_identity.md)
  | "ir="           irDigest                     = SHA-256(serializeIRFuncDef(funcDef))
  | "ea="           (agree|disagree ":" nimDigest "," leanDigest "," ircheckBinaryDigest)
  | "completeness=" completenessRecordDigest     = irDigest로 키된 CompletenessEvidence 레코드 digest
  | "leanSource="   leanSourceHash               = 렌더링된 Lean 소스의 SHA-256
  | "toolchain="    toolchainFingerprint         = 측정된 toolchain/bundle fingerprint
)
```

**구현 SSOT**: `computeBoundObligationId` (`src/verification/obligation/obligation_types.nim`), 바인딩 타입 `ObligationSubjectBinding`. 증거 봉인 경로: `newCanonicalLeanEvidenceBound` (`src/verification/obligation/kernel_acceptance_authority.nim`).

**합성 합성 주체 확장 (synthesized composite mode)** — [base36_sizing_binding_contract.md §2.1a](./base36_sizing_binding_contract.md)가 규정한 규칙의 구현:

- 합성 관계 합성물(`roundtrip_dec_enc(n) := decodedLength(encodedLength(n))`)은 주체 소스에 존재하지 않는 이름이므로 단일 심볼 EA 규칙을 문자 그대로 적용할 수 없다. EA는 **두 원본 심볼 각각**에 대해 동일한 fail-closed 차등(`runExtractionAgreement`)으로 측정되며(`measureCompositeParseBoundComponents`, `canonical_verification.nim`), 그 결과가 바인딩의 첫 번째/두 번째 EA leg로 운반된다.
- 합성 모드 표지는 `synthesisDerivationDigest`다 — 결정적 β-splice 유도 규칙(`"beta-splice-v1|outer=<outer>|inner=<inner>"`의 SHA-256, `betaSpliceDerivationDigest`)의 digest. 합성물의 정체성 = (두 원본의 EA 증거) ∧ (기록된 유도 규칙) ∧ (합성물 IR digest)이며, 세 성분 모두 bound id 페이로드에 소화된다:

```
  [composite mode 추가 세그먼트]
  | "derivation="   synthesisDerivationDigest  = 기록된 β-splice 유도 규칙 digest
  | "ea2="          (agree|disagree ":" nimDigest₂ "," leanDigest₂ "," ircheckBinaryDigest₂)
```

- **게이트 (약화 없음)**: 합성 모드에서 `buildSubjectBinding`은 두 EA leg가 (1) 합성물 이름이 아닌 서로 다른 두 원본 이름으로 측정되고 (2) **둘 다** `eaAgree`임을 강제한다. 하나라도 누락·불일치면 봉인 거부 — "EA 없는 봉인" 또는 "한 leg만 있는 봉인"은 어떤 형태로도 존재하지 않는다. 측정은 합성 지점(메인 스레드)에서 수행되어 `ExternalIrEntry.parseBound`로 운반되며, 선택 경계(`selectProofCandidates`)는 비어 있는 항목만 재측정한다.
- **모드 혼용 금지**: 비합성 모드에서 `ea2*`/`synthesisDerivationDigest`가 비어 있지 않으면, 합성 모드에서 이들이 정규 형식(64-hex)이 아니면 `computeBoundObligationId`는 `""`를 반환한다.

**단일-오리진 클레임 캐리어 확장 (single-origin claim-carrier mode)** — [nim_stew_base32_rem_binding_contract.md §3 D2](./nim_stew_base32_rem_binding_contract.md)가 규정한 규칙의 구현:

- 하나의 원본 심볼에서 파생된 합성 클레임 캐리어(예: `decodedLength_rem_range` — 청구가 `<symbol>` 자신의 `mod` 항 위에 정량화됨)는 주체 소스에 존재하지 않는 이름이므로 단일 심볼 EA 규칙을 문자 그대로 적용할 수 없다. 측정할 **두 번째 원본이 존재하지 않으므로** 합성 2-leg 모드도 적용할 수 없다. EA는 **하나의 원본 심볼**에 대해 단일 심볼 경로와 동일한 fail-closed 차등으로 측정되며(`measureClaimCarrierParseBoundComponents`, `canonical_verification.nim`), 그 결과가 첫 번째 EA leg로 운반된다.
- 모드 표지는 `claimCarrierSingleOrigin = true`다. 파생 규칙 digest(`"term-splice-v1|rule=<ruleId>|symbol=<symbol>"`의 SHA-256)는 필수 정규 성분이고, `ea2` 슬롯은 **빈 것이 필수**다 — 채워진 두 번째 leg는 조작된 측정(극장)이며 바인딩 지점(`buildSubjectBinding`)과 id 계산 모두 이를 거부한다. 캐리어의 정체성 = (하나의 원본 EA 증거) ∧ (기록된 유도 규칙) ∧ (캐리어 IR digest)이며, bound id 페이로드는 합성 모드의 `|derivation=` 세그먼트만 추가한다(`|ea2=` 세그먼트 없음):

```
  [single-origin mode 추가 세그먼트]
  | "derivation="   synthesisDerivationDigest  = 기록된 term-splice 유도 규칙 digest
```

- **게이트 (약화 없음)**: 캐리어 모드에서 `buildSubjectBinding`은 (1) EA leg가 캐리어 이름이 아닌 원본 심볼로 측정되고 (2) `eaAgree`이며 (3) `ea2` 슬롯이 비어 있음을 강제한다. 이 모드는 도입 전에는 항상 `""`(합성 2-leg 게이트가 기각)였으므로 페이로드 구성의 추가는 기존에 봉인된 어떤 정체성도 무효화하지 않는다.
- **모드 비혼용**: `synthesisDerivationDigest`가 비어 있지 않은데 `claimCarrierSingleOrigin`이 거짓이면 합성 2-leg 모드로 해석된다 — 빈 `ea2`는 `""`(fail-closed). 반대로 `claimCarrierSingleOrigin = true`에서 채워진 `ea2*` 슬롯도 `""`다. 세 모드(단일 심볼·합성·단일-오리진)는 동일 성분이라도 서로 다른 정체성을 가진다(`tests/unit/obligation_subject_binding_test.nim` Suite 7).
- **웨이브 면 귀속명**: `census.eligible`의 `RuntimeAxiomEntry.name`은 **피검사 심볼**(규칙 S의 적용 대상 노드명)로 설정된다 — loop_driver stage2가 IR 파이프라인 결과를 노드의 bare function name으로 귀속하기 때문이다 (`loop_driver.nim` stage2). 청구 정체성은 다른 모든 곳에서 합성물명을 유지한다: census 레코드명(중복 제거·선택), `funcDef.name`(def/theorem/obligation id), 그리고 봉인된 `CanonicalLeanEvidence`의 `obligationId`. 인증서의 `functionName` 필드는 노드 선택 인덱스이며, 실제 청구 주체는 인증서에 바운드된 `leanProposition`(합성물 정리 전문)과 `obligationId`로 식별된다 — §8의 "decodedLength 단독 후조건 아님" 비청구는 인증서 열람으로 검증 가능하다.
- **result-free 후조건 렌더**: 합성물의 후조건은 β-splice로 result-free이므로 목표에 def 적용이 나타나지 않는다. 렌더러는 proposition이 def 이름을 식별자 토큰으로 참조할 때만 `unfold`를 출력한다 (`containsIdentToken`) — 목표에 없는 상수의 `unfold`는 전술 실패(커널 REJECT)이기 때문이다. 정리 명제 자체는 불변이며, def는 아티팩트에 동일하게 렌더된다.

**구성 요소별 측정 지점**:

| 구성 요소 | 측정 위치 (기존 기계) |
|-----------|----------------------|
| `treeMerkle` | `computeSourceMerkleRoot` (`global_symbol_graph_builder_part2.nim`) |
| `module` | `resolveSourceHashForVerification` (§6a, `canonical_verification.nim`) |
| `git` | 빌드 시 hermetic SSOT(`generated/build_env.nim` `BuildEnvGitHash`) 또는 git snapshot |
| `pnodeV2` | `computeCanonicalAstHash` (`src/core/ast_kernel.nim`, DECISION-0002) |
| `ir` | `sha256Hex(serializeIRFuncDef(funcDef))` |
| `ea` | `runExtractionAgreement` 결과(`nimDigest`/`leanDigest`, `extraction_agreement.nim`) + ircheck 워커 바이너리 digest |
| `completeness` | `saveEvidenceArtifact`/`loadEvidenceArtifact` 레코드(`evidence_artifact_io.nim`, irDigest 키) |
| `leanSource` | `renderLeanForFuncDef` 산출물의 SHA-256 |
| `toolchain` | `computeBundleDigest` (`lean_kernel_boundary.nim`) — 측정값만 포함 (하드코딩 버전 라벨 금지) |

**Fail-closed**: 필수 구성 요소가 하나라도 없거나 정규 형식(lowercase sha256 hex; `git`은 40/64 hex; `pnodeV2`·`completeness`는 비어 있지 않음)이 아니면 `computeBoundObligationId`는 `""`를 반환한다. `""`는 id가 아니다 — 호출자는 `""` 아래 의무를 생성하거나 증거를 봉인해서는 안 된다. 결정론: wall-clock, run id, 물리 경로는 페이로드에 들어가지 않는다.

**평가 구현 바인딩**: `toolchain` fingerprint(`computeBundleDigest`)는 lowering 구현 — `pnode_to_canon.nim`, `ast_to_ir.nim`, IR→Lean 렌더러, `proofs/IR/Denotation.lean` — 의 콘텐츠 digest(`evaluationImplementationDigest`, `identity.nim`)를 반드시 포함한다. 이는 의미론을 조용히 넓히는 "수정"이 이전 증거를 재사용할 수 없게 한다. 실행 id는 `computeSemanticBundleFingerprintBound`을 통해 동일한 digest를 소화한다. subject의 checks/div 의미 프로파일은 별도 라벨이 아니라 이 의미-정의 모듈들의 콘텐츠 digest로 바인딩된다.

**섀도 모델 부착 거부**: `newCanonicalLeanEvidenceBound`는 (1) `binding.irDigest`를 실제 funcDef로부터 재측정하고, (2) id를 바인딩으로부터 재계산하여 일치를 강제하며, (3) `binding.leanSourceHash`가 실제 증거 소스와, (4) `binding.toolchainFingerprint`가 실제 측정 fingerprint와 일치함을 요구한다. 임의 단계의 불일치는 err이고 KAA는 존재하지 않는 것과 같다. 손으로 쓴 Lean 정의·stdlib 대체물·LLM 생성 정의는 렌더링된 소스와 다른 `leanSource` 해시를 가지므로, 주어진 bound id 아래 봉인될 수 없다.

### 2.2 Semantic Target

**Semantic target**은 의무 후보를 탐색하기 위한 IRFuncDef의 구조적 특징이다. 의무는 semantic target으로부터만 유도되며, backend가 임의로 추가하거나 제거할 수 없다.

### 2.3 ObligationGenerationResult

```nim
type
  LightNonEmptySeq[T] = object
    data*: openArray[T]           # len ≥ 1 (생성자 강제)

  ObligationGenerationResult* = object
    case kind*: ObligationResultKind
    of ogrGenerated:
      obligations*: LightNonEmptySeq[VerificationObligation]
        ## len ≥ 1 — 빈 집합은 허용되지 않음
    of ogrNoApplicableObligation:
      provenance*: NoObligationProvenance
        ## "증명된 분류" — 무작위 결과 아님
    of ogrUnsupported:
      reason*: UnsupportedReason
        ## semantic scope 밖만 허용
    of ogrIllFormed:
      reason*: IllFormedReason
        ## semantic_validator 산출물
```

**ObligationResultKind** 열거형:

| 값 | 의미 |
|----|------|
| `ogrGenerated` | 하나 이상의 의무가 생성됨 (non-empty 강제) |
| `ogrNoApplicableObligation` | semantic derivation으로 적용 불가가 증명됨 |
| `ogrUnsupported` | semantic scope 밖의 구성 요소 감지 |
| `ogrIllFormed` | semantic_validator가 구조적 결함 판정 |

**중요**: `ogrGenerated([])` — 빈 의무 리스트 — 는 절대 불가능하다. 빈 집합은 오직 `ogrNoApplicableObligation`으로만 표기한다. 이는 과거 `NoObligation` 부활을 차단하는 핵심 불변식이다.

### 2.4 NoObligationProvenance

```nim
type
  NoObligationProvenance* = object
    applicableClasses*: seq[ObligationClass]
      ## 항상 빈 시퀀스 — 적용 가능한 클래스 없음
    excludedClasses*: seq[ObligationClass]
      ## 탐색했으나 배제된 클래스 목록
    derivationRule*: string
      ## 기준 문서 ID (예: "obs:division", "obs:loopVariant")
    semanticFacts*: seq[string]
      ## NoObligationProvenance 스키마 — 관찰된 semantic fact 기술
```

**NoObligationProvenance 스키마**: `semanticFacts`는 해당 함수의 IR에서 관찰된 (또는 관찰된 후 배제된) semantic fact를 기술한다. 이 시퀀스는 감사 가능(machine-readable)해야 하며, "무작위 결과가 아니라 명시적 derivation의 산출물"임을 입증한다.

---

## 3. Obligation Generation Rules

### 3.1 Division — boDiv / boRem

**유도 규칙 ID**: `obs:division`

IRFuncDef 내에서 `boDiv`(나눗셈) 또는 `boRem`(나머지) 연산이 발견되면, **0Division 안전성** 의무가 자동으로 생성된다.

```
IF irExpr contains boDiv(a, b) OR boRem(a, b)
THEN obligation(kind=divSafety, subject="b ≠ 0", predicate="b ≠ 0")
```

- **assumptions**: `[ "b ≠ 0" ]` (피연산자가 0이 아님)
- **predicate**: `"∀ inputs : b(inputs) ≠ 0"`
- overflow/underflow 검사는 §3.8의 overflow obligation(goal 형태)으로 구현됨. div/rem 자체의 0-divide 안전성은 본 규칙의 predicate로 유지.

### 3.2 Index Access — irCall("[]")

**유도 규칙 ID**: `obs:index`

IRFuncDef 내에서 배열/문자열 인덱스 접근 `irCall("[]")`이 발견되면, **Bounds safety** 의무가 생성된다.

```
IF irExpr contains irCall("[]")(arr, idx)
THEN obligation(kind=indexSafety, subject="0 ≤ idx < length(arr)", predicate="idx ∈ [0, length(arr))")
```

- **assumptions**: `[ "0 ≤ idx", "idx < length(arr)" ]`
- **predicate**: `"∀ i : 0 ≤ i ∧ i < |arr| ⇒ arr[i] is valid"`

### 3.3 Loop Bound — loopCond

**유도 규칙 ID**: `obs:loopBound`

IRFuncDef 내에서 반복문 조건(`loopCond`)이 발견되고, 해당 루프가 유한 번 실행됨을 보장하는 조건이 필요하면 **Loop termination bound** 의무가 생성된다.

```
IF irFunc contains loopCond(cond) AND cond does not trivially terminate
THEN obligation(kind=loopBound, subject="loopCond", predicate="∃ bound : bound ∈ ℕ ∧ bound > 0")
```

- **assumptions**: `[ "bound ∈ ℕ", "bound decreases each iteration" ]`
- **predicate**: `"∃ B : ℕ . ∀ k ≥ B : ¬cond(k)"`

### 3.4 Loop Variant — loopVariant

**유도 규칙 ID**: `obs:loopVariant`

반복문 변이 함수(loop variant function)가 명시되거나 추론될 수 있으면 **Termination variant** 의무가 생성된다.

```
IF irFunc contains loopVariant(v) OR v can be derived from loopCond
THEN obligation(kind=loopVariant, subject="variantFunction", predicate="v decreases well-foundedly")
```

- **assumptions**: `[ "v ∈ ℕ", "v strictly decreases on each iteration" ]`
- **predicate**: `"¬∞ loop execution"`

### 3.5 Precondition / Postcondition Pragma

**유도 규칙 ID**: `obs:contract`

`{.axiom.precondition.}` 또는 `{.axiom.postcondition.}` 프라그마가 함수에 부착되면, 해당 contract 의무가 생성된다.

```
IF func has {.axiom.precondition(P)} pragma
THEN obligation(kind=precondition, subject="P", predicate="P holds at entry")

IF func has {.axiom.postcondition(Q)} pragma
THEN obligation(kind=postcondition, subject="Q", predicate="Q holds at exit")
```

- **assumptions**: contract 프라그마 내 proposition
- **predicate**: contract proposition 자체

### 3.6 Composite Patterns — enum / variant / clamp

**유도 규칙 ID**: `obs:composite`

다음 합성 패턴은 의무 유발 semantic fact를 포함할 수 있다:

| 패턴 | 유발 의무 | 조건 |
|------|----------|------|
| `enum` 기반 범위 제한 | `indexSafety` | enum cardinality 초과 접근 가능성 |
| `variant` 객체 분기 | `divSafety` / `indexSafety` | 각 branch 내 sub-expression 분석 |
| `clamp` 함수 | `divSafety` | clamp 내부에 div/rem 포함 시 |

**합성 규칙**: composite pattern의 각 하위 expression은 독립적으로 semantic target 탐색을 받으며, 각 하위에서 의무가 유도되면 상위에도 전파된다.

### 3.7 Deferred — Effect / Domain

본 문서에서 정의되지만 **P0 구현 범위에서 제외**되는 의무 유형:

| 유형 | 이유 |
|------|------|
| `effect` (I/O side-effect) | `{.axiomEffect: IOEffect.}` 함수는 kernel scope 밖. 문서에서만 정의 |
| `domain` (semantic domain violation) | 언어/솔버 간 도메인 불일치. 추후 orthogonal spec으로 분리 |

**규정**: deferred 유형의 의무는 이 문서의 §3.1–§3.6 규칙 목록에 명시적으로 기록되지만, generator 구현에서는 무시된다. generator가 deferred 유형을 생성하면 build-blocked이다. overflow는 더 이상 deferred가 아니다 — §3.8에서 goal obligation으로 정의·구현된다.

### 3.8 Overflow — boAdd / boSub / boMul

**유도 규칙 ID**: `obs:overflow`

Nim은 checked 빌드(기본 및 `-d:release`)에서 부호 있는 정수 연산이 폭을 벗어나면 `OverflowDefect`를 발생시킨다 (`-d:danger`/`--overflowChecks:off`는 조용히 wrap한다). `annotateOverflow`(`src/core/trusted/ast_to_ir.nim`)가 `boAdd`·`boSub`·`boMul` 노드에 `oNoOverflow`를 표시하면, 이 표시는 **solver 가정이 아니라 검증 의무(goal)**이다.

```
IF irExpr contains boAdd(a, b), boSub(a, b) OR boMul(a, b)
THEN obligation(kind=overflow, subject="no overflow at node",
     predicate="signed result stays within [low(int), high(int)]")
```

- **emission**: `ir_to_smt_chunk3.collectOverflowGoals`가 본문의 각 checked-arithmetic 노드마다 `no_overflow_*`/`no_underflow_*` 술어를 생성하고, `irToSmtScript`는 이를 postcondition과 함께 부정된 BMC 질의의 conjunct로 넣는다: `(assert (let ((result ...)) (not (and <post> <goal1> ... <goalN>))))`. postcondition이 없으면 goal-only 질의 `(assert (not (and <goal1> ...)))`.
- **discharge**: solver는 (script의 precondition assert로부터) 각 goal을 도출해야 한다. 도출 불가 ⇒ 질의 `sat` ⇒ **미검증(fail-closed)**. overflow는 절대 가정되지 않는다.
- **domain preconditions**: 의무의 주 discharge 경로는 `IRFuncDef.preConditions`다. 도메인 경계는 **리터럴로 고정된다** — 리터럴 수치가 폭 커밋이다 (base36 슬라이스: `0 ≤ n ∧ n ≤ 33297371974204966` = 64-bit `high(int) div 277`의 정확한 상한; `high(int) mod 277 = 225`, `encodedLength(n)·179` 마진 61. 32-bit는 7752648, 16-bit는 118). 경계 +1의 overflow는 커널 체크됨 (`proofs/IR/Denotation.lean` `base36_domain_tight`: `(MAX+1)·277 > int64Max`).
- **scope**: 본문(body) arithmetic만 goal이 된다. precondition 내부 arithmetic은 solver 입력이며 goal이 아니다.
- **legacy**: `generateOverflowAssertions`의 assert-랩 형태는 assumption-style 잔존 API다 (unit-test pinned, 파이프라인 미사용).

---

## 4. NoApplicable vs Unsupported

### 4.1 구분 원칙

| 구분 | 의미 | 책임 위치 |
|------|------|-----------|
| **NoApplicableObligation** | semantic analysis 수행 결과, 적용 가능한 의무 클래스가 없음 | Canonical Obligation Generator |
| **Unsupported** | IRFuncDef이 semantic scope 밖의 구성 요소를 포함 | Canonical Obligation Generator |

**핵심 원칙**: Unsupported는 **오직 "semantic scope 밖"**만을 지칭한다. backend failure, solver 미지원, code path 미구현은 Unsupported가 아니다.

### 4.2 UnsupportedReason 폐쇄 목록

`UnsupportedReason`는 다음 3개 값만 허용한다. 다른 모든 값은 금지:

| 값 | 의미 | 예시 |
|----|------|------|
| `scopedRecursiveHeapNotModeled` | 재귀적 힙 조작은 현재 scope에서 모델링되지 않음 | 재귀 데이터 구조의 힙 수정 |
| `scopedHigherOrderEffectNotModeled` | 고차 효과(HOF + effect)는 현재 scope에서 모델링되지 않음 | effectful HOF 호출 |
| `scopedLanguageConstructNotModeled` | 특정 언어 구문은 현재 scope에서 모델링되지 않음 | FFI 호출, unsafe cast |

**금지 목록** (UnsupportedReason에 사용 불가):

- `postconditionMissing` — postcondition 부재는 Unsupported가 아님 (NoApplicable 또는 Generated)
- `chcEncodingNotSupported` — CHC 인코딩 미지원은 Unsupported가 아님
- `backendMissing` — backend 부재는 Unsupported가 아님
- `codePathNotImplemented` — 코드 경로 미구현은 Unsupported가 아님
- 그 외 모든 "not implemented" 사유

### 4.3 예시: 허용 / 금지 표

| 함수 IR 특징 | 결과 | 이유 |
|-------------|------|------|
| 순수 `func` + postcondition ∅ + div/index/loop 없음 | `ogrNoApplicableObligation` | 적용 가능한 의무 클래스 없음 |
| `func` + `boDiv(a, 0)` 상수 0 나눗셈 | `ogrGenerated` | divSafety 의무 발생 |
| `proc` + `{.axiomEffect: IOEffect.}` | `ogrUnsupported(scopedHigherOrderEffectNotModeled)` | effect는 kernel scope 밖 |
| `func` + 재귀 힙 조작 | `ogrUnsupported(scopedRecursiveHeapNotModeled)` | heap modeling scope 밖 |
| `func` + postcondition 프라그마 있음 | `ogrGenerated` | contract 의무 발생 |
| `func` + loopVars == 1 + result 반환 | `ogrGenerated` | loopBound/loopVariant 의무 발생 (정규 취급) |

---

## 5. Backend Constraints (C1, C7)

### 5.1 C1 — Backend Has No Obligation Selection Authority

백엔드(CHC/Spacer, SMT, Lean)는 **의무 존재 여부를 결정하지 않는다**. 의무의 존재/부재/종류/순서는 Canonical Obligation Generator 단 한 곳에서 결정된다.

**규정**:

1. 백엔드는 generator가 생성한 의무 리스트를 **소비(consume)**만 할 수 있다.
2. 백엔드는 의무를 **추가(add)**, **삭제(remove)**, **재순서(reorder)** 할 수 없다.
3. 백엔드가 "이 함수에는 의무가 없다"고 판단하면, 그것은 원래 generator 구조로 회귀해야 한다.
4. 백엔드 오류(타임아웃, 메모리 부족, internal error)는 `Inconclusive/InternalError`로 처리되며, Unsupported로 흡수되지 않는다.

### 5.2 C7 — Obligation Count Preservation

generator가 결정한 의무 집합(개수·종류·순서)은 어댑터를 통과해도 불변이어야 한다.

**규정**:

1. 각 어댑터(CHC, SMT, Lean)는 generator 의무 리스트를 **1:1로 소비**한다.
2. 어댑터 실행 결과에서 의무 카운트는 generator 출력과 정확히 일치해야 한다.
3. 증감(increase/decrease) 또는 재순서화(reordering)는 불변식 위반이다.
4. 테스트: 각 어댑터 실행 후 `len(generator.obligations) == len(adapter.consumed)` 검증.

---

## 6. Determinism (C4)

### 6.1 Identity Determinism

동일한 canonical input에 대해 Canonical Obligation Generator는 항상 동일한 ordered set of obligations을 생성한다.

**규정**:

1. **입력 고정**: `IRFuncDef`의 canonical form (AST 정규화 후)이 동일하면, 출력义务 set도 동일하다.
2. **순서 고정**: 의무는 `kind` 사전순 → `subject` 사전순으로 정렬된다.
3. **ID 안정성**: 동일 5-튜플 → 동일 SHA-256 해시 → 동일 `id`. 증거 대면 id는 §2.1a의 bound identity이며, 동일 바인딩 → 동일 id, 구성 요소 하나라도 다르면 다른 id다.
4. **환경 무관**: OS, Nim 버전, 환경 변수가 달라도 동일 canonical input → 동일 output.

### 6.2 Canonical Normalization Path

`canonicalAssumptions`와 `canonicalPredicate`는 단일 정규화 경로로만 생성된다:

1. **정렬**: assumption 시퀀스는 사전순으로 정렬된다.
2. **공백 정규화**: 여러 공백 → 단일 공백, 선행/후행 공백 제거.
3. **문자열 정규화**: 유니코드 정규화(NFC) 적용.
4. **해싱**: UTF-8 바이트열 연결 후 SHA-256.

이 경로 외의 어떤 경로로도 identity를 생성하면 안 된다.

---

## 7. State Machine (§1.3 of Plan)

### 7.1 Workflow Phase

Workflow phase는 검증 대상의 **생명주기 진행 단계**를 나타낸다. phase는 순차적으로 전이하며, 역전不可:

```
Candidate → Analyzed → ObligationDecision → ProofAttempted → Terminal
```

| Phase | 설명 | 진입 조건 |
|-------|------|-----------|
| `Candidate` | 원시 IRFuncDef 입력 | 파이프라인 시작 |
| `Analyzed` | semantic target 탐색 완료 | `analyze()` 완료 |
| `ObligationDecision` | 4-way 결과 판정 | generator 결과 수신 |
| `ProofAttempted` | backend에 의무 전달 및 증명 시도 | `ProofAttempted` transition |
| `Terminal` | 최종 판정 도달 | proof 완료/실패/불가 |

### 7.2 Terminal Result

Terminal result는 **최종 판정**이며, 재생·감사용 고정값이다. phase와 terminal은 별도 필드로 격리된다:

```nim
type
  TerminalResult* = enum
    trProved          ## 모든 의무 증명 성공
    trRefuted         ## 하나 이상의 의무 반례 발견
    trNoApplicable    ## 의무가 없음 (증명된 NoApplicable)
    trUnsupported     ## semantic scope 밖
    trIllFormed       ## 구조적 결함
    trInconclusive    ## 증명 중 backend 오류/타임아웃
```

### 7.3 Transition Diagram

```
Candidate (phase — 원시 IR 입력)
  ↓ analyze()
Analyzed (phase)
  ↓ ObligationDecision (4-way)
  ├─ ogrNoApplicableObligation → Terminal(trNoApplicable)
  ├─ ogrUnsupported            → Terminal(trUnsupported)
  ├─ ogrIllFormed              → Terminal(trIllFormed)
  └─ ogrGenerated              → ProofAttempted (phase)
         ↓ backend proof attempt
         ├─ trProved          (terminal)
         ├─ trRefuted         (terminal)
         └─ trInconclusive    (terminal — backend 실패/InternalError 포함; Unsupported 아님)
```

**중요 구분**:

- **phase ≠ terminal**: phase는 진행 단계(진행 중/완료 여부), terminal은 최종 판정(재생·감사용 고정값).
- **ProofAttempted 중 backend 오류** → `phase=attempted`, `terminal=trInconclusive(InternalError)` 기록. Unsupported로 흡수 금지.
- **trInconclusive ≠ trRefuted**: Inconclusive은 "증명 시도 중 오류 발생", Refuted은 "명확한 반례 발견".

---

## 8. Anti-Theater Constraints (C0, C3)

### 8.1 C0 — No Empty Obligation Without Reason

**"빈 의무 + 이유 없음 + exit 0" 조합은 theater이다.**

규정:

1. 의무 개수가 0인 경우, 반드시 `ogrNoApplicableObligation` variant로 `NoObligationProvenance`를 제공해야 한다.
2. `NoObligationProvenance`는 `derivationRule`, `excludedClasses`, `semanticFacts`를 모두 포함해야 한다.
3. exit code 0은 terminal result가 `trProved` 또는 `trNoApplicable`일 때만 허용된다.
4. `trNoApplicable`일 때는 반드시 provenance가 로그/JSON에 기록되어야 한다.

### 8.2 C3 — No Tautology Obligations

**Tautology 의무 합성은 금지된다.**

규정:

1. `result == result`, `x >= x`, `true` 와 같은 동치(tautology) predicate는 의무로 생성하지 않는다.
2. predicate가 tautology인지 확인하는 static check는 generator의 첫 번째 단계여야 한다.
3. tautology predicate가 감지되면 해당 candidate는 `ogrNoApplicableObligation`으로 분류한다.

---

## 9. Metrics

### 9.1 Obligation Generation Rate (OGR)

```
OGR = |VKS ∩ {target : obligations(target) > 0}| / |VKS|
```

- **분자**: 의무가 1개 이상 있는 VKS 심볼 수
- **분모**: 전체 VKS (Verifiable Kernel Scope) 심볼 수
- **의미**: VKS 중 실제로 의무가 생성되는 비율
- **계산 시기**: runtime 측정 (`getCanonicalVkdMetrics` 경로와 유사)
- **SSOT 위치**: `data/baseline.json` additive field (P6 단계)

### 9.2 Proof Attempt Rate (PAR)

```
PAR = |attempted| / |generated|
```

- **분자**: 증명 시도한 의무 수 (proofAttempted phase 진입)
- **분모**: generator가 생성한 총 의무 수
- **의미**: generated 의무 중 실제로 증명 시도에 들어간 비율
- **참조**: Inconclusive로 끝난 증명은 attempted에 포함됨

### 9.3 VKD Invariant

VKD 정의는 변경되지 않는다:

```
VKD = |VKS ∩ certGreen| / |VKS|
```

- VKD 분자는 `certGreen` 상태만 admit한다.
- `certZ3Verified`, `certLeanVerified`, `certDualVerified`, `certVerifiedAxiom` 등은 VKD 분자에 포함되지 않는다.
- 이 불변식은 obligation semantics 도입으로 변경되지 않는다.

### 9.4 Future Metrics (Deferred — Not Implemented in P0)

| 지표 | 정의 | 상태 |
|------|------|------|
| `TOC` (Target Obligation Coverage) | obligations > 0인 eligible target 비율 | 비구현, TOC spec 별도 |
| `OPR` (Obligation Proof Rate) | proved obligations / generated obligations | 비구현, OPR spec 별도 |

---

## 10. Appendix: Summary of Key Decisions

### A. Obligation Definition
Obligation은 IRFuncDef의 canonical semantic property로서, division/index/loop/contract 각 target별로 명확히 정의된다.

### B. Semantic Fact → Obligation Rules
§3.1–§3.6에 6가지 규칙 정의. overflow/effect/domain은 §3.7에서 defer 명시.

### C. Zero-Obligation Unique Path
`ogrNoApplicableObligation`만이 0 의무 표기. 명명된 `derivationRule` + `excludedClasses` + `NoObligationProvenance` 스키마 필수.

### D. Unsupported vs NoApplicable
Unsupported = scope 밖 (폐쇄 목록 3개). NoApplicable = semantic analysis 결과 적용 불가. 예시 표 §4.3 참조.

### E. C1 + C7
백엔드는 obligation 선택 권한 없음. 어댑터는 1:1 소비 전용, 증감·재순서 불가.

### F. Determinism
동일 canonical input → 동일 ordered set. 단일 정규화 경로 (정렬 → 공백 정규화 → NFC → SHA-256).

### G. C4 ID
5-튜플 `(subject ‖ kind ‖ canonicalAssumptions ‖ canonicalPredicate ‖ derivationRule)` 기반 SHA-256. 정렬 순서 규칙 §6.2.

### H. C6 Closure
각 의무는 `subject · assumptions · predicate · derivationRule`만으로 완전 해석 가능. backend/env 무관.

### 1.3 State Machine
Phase (Candidate→Analyzed→ObligationDecision→ProofAttempted→Terminal) 와 Terminal Result (6종) 분리. backend 오류 → Inconclusive.

### C0/C3 Anti-Theater
빈 의무+이유 없음+exit 0 금지. tautology 의무 합성 금지.

## P5: Semantic State → Projection (CLI/JSON/Certificate)

### P5.1 Exit-Code Separation Candidate

P5 introduces `not_verifiable:<reason>` status for `ogrUnsupported` and `ogrIllFormed` obligation verdicts.
These map to `psSkip` in `ProofCertificate` with exit code **0** (preserving the R5 regression contract).

The semantic distinction between `psSkip` (backend-incompatible skip) and `psSkip` with `not_verifiable` provenance
is carried in the certificate JSON (`solverMeta.obligationVerdict`) and the CLI summary (`obligation_terminal` column).

**Exit-code separation candidate** (not implemented in P5 — deferred to a future phase):
- `psNoObligation` → exit 0 (proven absence of obligations)
- `psSkip` + `not_verifiable:unsupported` → exit 0 (today) → **exit 4** (candidate: "semantic scope out of model")
- `psSkip` + `not_verifiable:illFormed` → exit 0 (today) → **exit 5** (candidate: "semantic validation failure")

The candidate exit codes (4/5) would allow downstream tooling to distinguish "skipped by theory" from
"not verifiable due to semantic scope/validation" without parsing provenance strings. This change requires
a separate RFC and is **not** part of the P5 minimal change set.

### P5.2 Certificate JSON Obligation Verdict

The certificate JSON now includes `solverMeta.obligationVerdict` with one of:
- `"generated"` — obligation was produced and proved/refuted
- `"no_applicable"` — no obligation applicable (proven classification)
- `"unsupported"` — semantic scope out of model
- `"ill_formed"` — semantic validation failure

### P5.3 CLI Summary `obligation_terminal` Column

The `renderAxReportLines` function now includes an `obligation_terminal=<reason>` column for entries
with `status=not_verifiable`. The reason is extracted from `evidenceLogJson` (set by `loop_driver`
from `budgeted.skipReason`).

---

## Lean Axiom Audit

### Purpose

Every Lean 4 module generated by Axiom's IR-to-Lean pipeline (`irToLeanModule` / `irToLeanWithObligations` in `src/core/trusted/ir_to_lean.nim`) is compiled with `lean` and audited for axiom usage. The Lean kernel guarantees soundness **only up to declared axioms** — any axiom used in a verified module is a trust commitment that the kernel accepts. This section documents the actual axiom footprint of Axiom-generated modules and the policy that governs it.

### Tool

**Path**: `tools/lean_axiom_audit.nim`

**Build**: `nim c --hints:off -o:bin/lean_axiom_audit tools/lean_axiom_audit.nim`

**Invocation**: `bin/lean_axiom_audit <file.lean>`

**Exit codes**:
- `0` — all axioms are allowed (audit passed)
- `1` — unallowed axioms found (audit failed)
- `2` — file not found or no theorems found

The tool:
1. Reads the `.lean` source and extracts theorem names via `theorem <name>` pattern matching.
2. For each theorem, builds a temporary audit file that replaces the trailing `#print axioms` line with `#print axioms <theoremName>`.
3. Compiles each audit file with `lean` (120 s timeout).
4. Parses the `#print axioms` output — multi-line format:
   ```
   '<name>' depends on axioms: [axiom1,
    axiom2, ...]
   ```
   or `'name' does not depend on any axioms`.
5. Compares each extracted axiom name against the allowed-axiom policy.
6. Reports violations and exits with the appropriate code.

### Allowed-Axiom Policy (`DefaultAllowedAxioms`)

| Axiom | Justification |
|-------|---------------|
| `propext` | Propositional extensionality — required by `Std.Tactic.BVDecide` for encoding bit-vector comparisons as propositions. |
| `Classical.choice` | Global choice — transitively used by `Classical.em` which `bv_decide` invokes for discharge. |
| `Quot.sound` | Quotient soundness — transitively imported by `Classical.choice`. |
| `*_native.bv_decide.ax_*` | Internal axioms of the `bv_decide` tactic plugin — always allowed as they are tactic-internal, not user-visible logical axioms. |

**If mathlib were imported**, additional axioms (e.g. `Mathlib.Classical.choice`, `Mathlib.Equiv.ax`) would need explicit entries in the allowlist. The current policy assumes **no mathlib** — only `Init` and `Std.Tactic.BVDecide`.

### Real Measured Axiom Footprint

The following axioms were **actually measured** by running `lean_axiom_audit` on Axiom-generated `.lean` files produced by `irToLeanModule` (verified via `lean 4.29.0`):

| Theorem | Axioms Found | Violations |
|---------|-------------|------------|
| `clampTimeoutMs_post0` | `propext`, `Classical.choice`, `Quot.sound`, `clampTimeoutMs_post0._native.bv_decide.ax_1_5` | 0 |
| `proximityScore_post0` | `propext`, `Classical.choice`, `Quot.sound`, `proximityScore_post0._native.bv_decide.ax_1_5` | 0 |
| `safeSpeedupRatioCore_post0` | `propext`, `Classical.choice`, `Quot.sound`, `safeSpeedupRatioCore_post0._native.bv_decide.ax_1_5` | 0 |
| `normalizeMaxWorkers_post0` | `propext`, `Classical.choice`, `Quot.sound`, `normalizeMaxWorkers_post0._native.bv_decide.ax_1_5` | 0 |
| `calcDynamicTimeoutCore_post0` | `propext`, `Classical.choice`, `Quot.sound`, `calcDynamicTimeoutCore_post0._native.bv_decide.ax_1_5` | 0 |

**All measured axioms are within the allowed policy. No violations found.**

### Kernel Soundness Reference

From the Lean 4 official documentation (`leanprover/lean4`):

> The Lean kernel guarantees soundness of all proofs **up to declared axioms**. Axioms such as `propext` and `Classical.choice` are trusted primitives — the kernel does not verify their consistency, only that they are declared. Any proof that depends on an axiom is sound **modulo the soundness of that axiom**.

This means:
- Axiom-generated modules that use `propext` and `Classical.choice` are **kernel-sound** — the Lean kernel accepts these as trusted primitives.
- The `bv_decide.ax_*` axioms are internal to the `Std.Tactic.BVDecide` plugin and are sound by construction (the plugin is a trusted component of the standard library).
- If mathlib were added to the import chain, the axiom footprint would expand and the allowlist would need updating accordingly.

### Known Issue: Generated File Syntax

The current `irToLeanModule` output has a syntax issue in the generated `def` bodies: it uses **prefix** comparison operators (`(< timeoutMs 5000)`, `(> timeoutMs 120000)`) instead of **infix** (`timeoutMs < 5000`, `timeoutMs > 120000`). This causes Lean compilation errors for the generated files as-is. The `#print axioms` at the end of the module (without a theorem name) also fails because `axioms` is not a recognized constant when no theorem name is provided.

The audit tool handles both cases:
- Files that fail compilation are reported with `compile error` violations.
- Files that compile (after fixing the operator syntax) are fully audited for axiom usage.

### Related Documents

- `src/core/trusted/ir_to_lean.nim` — IR-to-Lean generator (lines 617–637 for `irToLeanModule`)
- `src/verification/batch_uap/loop_driver.nim` — `runLeanVerification` (lines 222–257)
- `tools/lean_axiom_audit.nim` — audit tool source
- `docs/spec/verification_density.md` — VKD definition and canonical verification-density projection
