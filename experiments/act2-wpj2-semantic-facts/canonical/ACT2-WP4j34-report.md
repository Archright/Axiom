# ACT 2 WP4-j.3 + WP4-j.4 — Provenance Normalization & Evidence Ladder: 실측 보고서

- **실험 ID**: ACT2-WP4j3-provenance / ACT2-WP4j4-instantiation-ladder
- **날짜**: 2026-08-31
- **Subject**: nim-stew `stew/bitops2.nim::getBitsBE` (`c75502ceedb5…`)
- **Axiom rev**: `44fefd470` working tree (j.2~j.4 변경 포함, 미커밋)
- **계약**: 승인 계획 v6 — Evidence Ladder(9단계, 상태 구분) + Ladder Monotonicity

---

## Question

"Axiom이 이미 존재하는 concrete instantiation을 deterministic하게 관찰해서
elaborated concrete type fact를 보존할 수 있는가?" — generic inference 없이
**evidence ladder**(Raw Observation → Mechanical Relation → Instantiation Fact →
Type Identity / Representation / Size → Semantic Fact → SMT)를 구현하고, 각
화살표를 Observed / Mechanical-Derived / Derived / Unknown으로 엄격 구분한다.

---

## Context

- WP4-j.2 완료 사실: CLET 보존, 독립 관찰자, completeness artifact(2축), 게이트,
  fact assert lowering — 단, getBitsBE는 lossy로 판정되어 fact가 주입되지 않음.
- getBitsBE 구조: `:559` generic func(T: type[SomeUnsignedInt]) + `:599-600`
  template wrapper(본문 call `getBitsBE(data, slice, BiggestUInt)`).
- toolchain 1차 관찰: system.nim의 `BiggestUInt* = uint64`(nim-2.2.10).

---

## Scope

- **포함**: WP4-j.3(smNone 정규화 + axiomDecision 보완), WP4-j.4(1-depth template
  call 관찰, formal/actual positional correspondence witness, ladder fact 타입
  신설 — 자기-입력 id, witness artifact + witnessDigest 무결성, lowering 결합,
  monotonicity 테스트).
- **배제**: generic inference 전체, template expansion, scope-aware resolver,
  module-level const, F_bounds/F_index, relevance filtering, Lean/KAA,
  repository-wide, sizeof evaluator.

---

## Procedure

1. **j.3**: `loadEvidenceArtifact`에 axiomDecision pragma + import(axiom_pragmas).
   BMC 경로 `bmcResult`의 solverMethod/provenance/solverStatus를 실제
   `bmcOutcome.status`에서 설정(Transformation: solver_adapter.SolverStatus →
   core/types.SolverStatus — 이중 enum 해소).
2. **j.4-A**: `InstantiationWitness` 타입 + 관찰자 확장 — nkTemplateDef 본문의
   직접 자식 nkCall 헤더만 관찰(callee/actuals), 동명 generic funcDef의
   formalParams 스냅샷(typedesc 여부 포함), positional relation 기계 기록,
   occurrenceRef = sha256(모듈해시:path:callee:concreteType).
3. **j.4-B**: ladder fact 타입 신설(InstantiationBindingFact/TypeIdentityFact/
   IRRepresentationFact/SizeFact/ConstArithmeticFact — 각 status 필드, id는
   **자기 입력 재료만의 sha256**). `deriveInstantiationFacts(witness, funcDef)`:
   witness 소비형 — positionalRelation 없음/Unknown → 후속 미생성(fail-closed),
   canonicalMap {"BiggestUInt": "uint64"}만(테이블 외 → fsUnknown), SemanticFact
   subject는 `findSizeofMul8Binding`(CLET `const X = sizeof(...)*8` 패턴의
   letName)에서 기계 유도.
4. **j.4-C**: runner 배선 — anchor1(pre-inline ve.funcDef)→anchor2(current
   funcDef) 순차 evidence 탐색(결정론적 키 탐색, AST 재해석 금지), witnessDigest
   재계산 대조, fact 합류 후 이름 sorted.
5. **구현 중 발견·수정(중요)**: `ir_inline_pass.nim`의 irLet 재구성 3곳이
   `isCompileTime`을 복사하지 않아 **inlining이 CLET을 LET으로 강등** — 수정 후
   getBitsBE IR은 inline+synthesize 후에도 CLET 보존. 이는 j.2 repair의
   누락된 4번째 tree-walk이었음.
6. **artifact 분리(중요)**: `saveInstantiationWitnesses`가 CompletenessEvidence
   artifact(`<irDigest>.json`)를 **덮어써서** 게이트가 witness JSON(완전성
   필드 부재 → 기본값 false)을 읽어 전체 fact가 차단되는 결함 발견 → witness를
   별도 파일(`<irDigest>.witness.json`)로 분리 + `witnessCachePath` 신설.

---

## Result (canonical machine-observed)

### 신규 테스트: 14/14 (`test_wpj4_ladder.nim`)
- Ladder 순서/상태: TypeIdentity(observed, toolchainIdentity) →
  IRRepresentation(derived, contractId=SemanticProfileV1Hash) → Size(8/64) →
  ConstArithmetic(8×8=64) → InstantiationBinding(derived, scope-limited) — 전부 PASS
- **Monotonicity**: deriveInstantiationFacts 2회 호출 → 동일 id/provenance; fact
  id가 타 fact id와 무관함 — PASS
- **Unknown fail-closed**: positionalRelation 미관찰 → 빈 seq; 테이블 외
  concreteType(uint32) → fsUnknown → 후속 fact 미생성 — PASS
- **witnessDigest 무결성**: 저장→로드 성공; **파일 직접 변조 → digest 불일치 →
  none(거부)** — PASS
- **witness 소비형**: projection 모듈이 compiler/ast를 import하지 않음(정적 검증)
  — PASS
- **E2E 준비**: bitops2.nim 실제 파스에서 getBitsBE witness 관찰 — PASS

### 기존 회귀: 전부 통과
phaseb 15, cde 12, ast_to_ir 39, axiom_ir 98, obligation_ir ALL, ledger 11,
theaterguard (a)–(f), PSM 52, golden repro digest 불변. make build ✅,
check-imports ✅.

### j.3 실증 (E2E)
getBitsBE provenance: `solverMethod=smNone,provenance=pkNone` →
**`solverMethod=smBMC, provenance=pkZ3Bmc`** — 실제 Z3 호출이 정직하게 귀속됨.
WARN 3→2 복귀.

### Phase F — getBitsBE E2E (exit 2, Run 반복)
- witness artifact 생성·로드 확인: getBitsBE witness(actualArgs [data, slice,
  BiggestUInt], positional [0,1,2], occurrenceRef) — **관찰 단계 완전 작동**.
- 그러나 **fact 주입은 차단됨**: completeness artifact에
  `translationLossFree=false, bindingUniverseComplete=false(opaque-boundary,
  source 15 vs IR 13)` — 게이트가 fact 주입을 fail-closed 차단. Z3 telemetry의
  getBitsBE 스크립트 digest(`d067de02…`, sat) 불변.
- **이것은 결함이 아니라 설계의 실증이다**: witness ladder는 완성됐지만,
  getBitsBE의 IR이 lossy(번역 손실 + opaque 경계)인 한 증거가 불충분하여
  fact를 proof substrate로 운반하지 않는다 — "증거가 충분하면 다음 단계,
  부족하면 중단"의 기계적 실현.

---

## Evidence

| 항목 | 위치 |
|---|---|
| ladder 테스트 | `tests/unit/test_wpj4_ladder.nim` 14/14 |
| 관찰자 확장 | `src/core/trusted/binding_inventory.nim`(InstantiationWitness) |
| fact 타입 | `src/core/trusted/semantic_fact_types.nim`(ladder facts, foTemplateInstantiation) |
| projection | `src/verification/obligation/semantic_environment.nim`(deriveInstantiationFacts, findSizeofMul8Binding*) |
| artifact 분리 | `src/infrastructure/evidence_artifact_io.nim`(witnessCachePath, witnessDigest) |
| inline 수정 | `src/core/trusted/ir_inline_pass.nim`(isCompileTime 복사 3곳) |
| j.3 수정 | `evidence_artifact_io.nim:75` pragma / `ir_pipeline_runner.nim` BMC provenance |
| E2E 로그 | `/tmp/j4_runC5.txt`(pkZ3Bmc 실증), witness artifact `df2ff30d….witness.json` |

---

## Classification

- **WP4-j.3**: 완료(폐쇄) — provenance normalization 실증.
- **WP4-j.4**: substrate 완료(ladder 8단계 전부 구현·검증) + **getBitsBE fact
  주입은 completeness 게이트에 의해 설계대로 차단** — `Incomplete`(UNSAT 미달,
  그러나 목표 아님). witness 관찰 계층은 실증됨.

---

## Interpretation

1. **증거 사슬이 자기 설명적이다**: getBitsBE의 경우 witness(관찰 완료) →
   completeness(손실 계측: 15 vs 13) → 게이트(차단) — 어느 단계까지 증거가
   있고 어디서 막혔는지 artifact와 로그가 그대로 증명한다. 이것이 사용자가
   정의한 evidence compiler의 정체성이다.
2. **번역 손실과 관찰 능력이 분리됐다**: 관찰자는 const 바인딩과 instantiation을
   모두 본다(15개). 번역기는 13개만 보존한다. 차이(2개 + opaque 2)가 정확히
   다음 capability(번역 완전성 + opaque expansion)의 경계를 표시한다.
3. **j.2 repair의 마지막 누락 발견**: inlining의 isCompileTime 강등은
   "CLET가 직렬화에 살아있는데 파이프라인 중간에 죽는" 교묘한 결함이었다 —
   tree-walk 복사 계약의 4번째 누락 지점. 이로써 CLET는 번역→inline→직렬화
   전 구간에서 보존됨이 테스트로 닫혔다.
4. **artifact 분리는 증거 정합성의 전제다**: completeness와 witness가 같은
   파일을 경쟁하면 게이트가 엉뚱한 payload로 판정한다 — identity(키)와
   integrity(digest)와 ownership(파일 분리)의 3중 분리가 필요했다.

## Non-Conclusions

- getBitsBE가 UNSAT/안전하다 → 아님 (fact 미주입, psFail 유지).
- ladder fact들이 Nim generic semantics를 확정한다 → 아님 — positional
  correspondence 기반 scope-limited derived fact다(open/closed, mixin/bind,
  hygiene 미해결).
- witnessDigest가 authenticity를 보장한다 → 아님 — integrity/content
  consistency만 (threat model 밖 명시).
- repository-wide 주장 불가 — 단일 anchor의 계층 실증이다.

## Next Experiment

1. **번역 완전성 확대**: 15−13=2 손실 binding의 정체(block/when 등 11종 미처리
   노드)를 줄여 `translationLossFree=true` 달성 → 게이트 통과 → ladder fact
   주입 → UNSAT 경로 개방.
2. **RuntimeAxiomEntry.evidenceSerialized**(v2): 자기검증 경로 evidence.
3. **canonicalizeExpr shadowing 수정 / symbolTable 구현** (기존 debt).
4. **WP4-j.5(후보)**: opaqueExpansionStatus의 fullyExpanded 판정(template
   wrapper의 의미 확장을 관찰 가능한 형태로) — resultBits=64 fact의 실제
   주입 조건.

## Non-goals (동결 유지)
generic inference / template expansion / scope-aware resolver / module-level
const / evaluator / relevance filtering / Lean-KAA / repository-wide /
authenticity(서명·MAC) / "UNSAT 목표화".

---

## Erratum note

이 보고서 작성 중 Z3 telemetry 타임스탬프는 UTC(15:28Z = KST 00:28)이며,
실행 로그와 동일 시계다. WP4-j.1 보고서의 "getBitsBE 전용 digest 불변" 관찰은
본 WP에서도 재현됐다(fact 미주입 상태 유지 — 설계대로).
