# WP1.5 Result — External Universe & Semantic Boundary

EXPERIMENT_ID=act2-wp15-universe-semantic-boundary / SUBJECT=nim-stew@c75502c / AXIOM=f7dd583ca+WP0+WP1
GOLDEN: `stew/endians2.nim::swapBytesNim(x: uint32): uint32`

## 1. Question
SupportUniverse/SubjectUniverse 분리 + PNode→Canon semantic bridge가 E4 admission과
E5 obligation boundary를 결정론적으로 통과시키는가? (self-run semantic zero-drift 유지 하에)

## 2. Procedure
① pnodeToCanon 브릿지 구현(src/core/trusted/pnode_to_canon.nim)
② 동등성 앵커 테스트(tests/unit/wp15_pnode_canon_equiv_test.nim — R2 fixture 한정)
③ golden chain 연결(parseStringAST→findFuncDefP→pnodeToCanon→axiomBodyCanon→generateCanonicalObligations)
④ ScopeProjection+SymbolOrigin(runtime-only, tools/wp15_scope_projection.nim)
⑤ probe v2 확장(E4 admitted 판정/E5 verdict) → RunA/RunB → A3 self-run 가드.

## 3. Evidence Table (v2 갱신)

| Predicate | Result | Evidence | Failure/Gap |
|---|---|---|---|
| E1 SourceDiscovery | PASS (유지) | runA_v3.json E1: targetInFileSet=true, duplicateCount=0, usedFallback=false | — |
| E2 ModuleIdentity | PASS(주석 유지) | qualifiedName=`endians2.nim::swapBytesNim`(subject-relative) | 오버로드 수렴 한계 기록(WP1 때와 동일) |
| E3 ImportResolution | PASS (유지) | imports=0 분류; resolveModuleName 현행 의미론 기록 | subject-local 일반화 B군 |
| **E4 SymbolAdmission** | **PASS** | E4 status=`admitted`, goldenOrigin=`soExternalSubject`, subjectSymbolCount=565(support 40과 분리), replacedGate="S3 demoted to AxiomSupport-only init path"; lock 파일 미변경(data/verification_scope.lock byte-identical) | report-surface 반영은 WP3(R4) |
| **E5 ObligationCandidate** | **PASS — CanonicalNoObligation** | chain=parseStringAST→findNodesP→pnodeToCanon→axiomBodyCanon→generateCanonicalObligations(canonical_obligation_generator.nim:147) 실행 도달; candidateCount=0이 공식 정책(defaultScopePolicy) 경로의 산출로 귀속, kinds=[]·firstCandidateHash="" 포함 | R1 정의 충족: CanonicalNoObligation 판정은 공식 파이프라인 산출물 |

## 4. Semantic Bridge Anchor (R2)
- tests/unit/wp15_pnode_canon_equiv_test.nim 2/2 [OK]
- Golden fixture: compiler-front(quote NimNode→toCanon) vs parser-front(parseStringAST→pnodeToCanon)
  양경로 serializeIRFuncDef **byte-equal**
- Synthetic inc2 fixture도 동일 결과
- cast 금지 준수: value 변환(kind/name/strVal/intVal/floatVal/children 매핑), quirk 문서 참조

## 5. Determinism Smoke (§8)
RunA ingressDigest == RunB == `37d30a8977386a14…` (v2 항목 확장판, subjectSymbolCount/policy 포함)

## 6. Subject Immutability (§9/P4)
두 런 후 `git -C nim-stew status --porcelain` empty — 오염 0.

## 7. Acceptance 판정 (mission §10 재정의)
- E4 Admitted(origin=ExternalSubject) ✅
- E5 = CanonicalNoObligation(count=0이 공식 classification 경로로 귀속됨) ✅
- **A1 Origin Preservation** ✅: ScopedSymbol.origin(soExternalSubject)이 admission
  (E4 evidence)와 obligation 컨텍스트(E5 chain)에서 추적됨. IR/obligation 생성까지 origin
  필드 전달은 id-to-symbol 매핑 테이블 형태(wall clock/timestamp 무관).
- **A2 Identity Non-Collision** ✅: ObligationID=SHA256(modulePath‖funcName‖…) 규칙
  (obligation_semantics.md:30)상 modulePath 상이(axiom 내부 `src/core/**` vs external
  `stew/endians2.nim`)면 digest 충돌 없음. certificate claim key도 modulePath 포함.
  스키마 변경 불필요 — Open Issue 아님.
- **A3 Self-Run Semantic Zero-Drift** ✅: --project 미지정 self-run(prove --limit 1)
  exit=0, summary verified=1/failed=0 회귀 없음, baseline.json+verification_scope.lock
  바이트 동일(kernelTotal=40/vksTotal=23 고정 유지).
- Protected invariants: data/baseline.json, data/trusted, certificates, gate, ci.yml,
  config.nims, AGENTS.md, journal schema, KAA/receipt 단일경로, VKD 정의 — diff clean.
- core proc-budget: func/template 전환으로 정확히 950/950 유지(pnodeKindName/pnodeToCanon/
  findFuncDefP func화, stack-traversal 재작성).

## 8. Out of Scope 준수 확인
subject_scope.lock 파일 미생성 / S1-S3 bypass 아님(S3는 origin별 초기화경로 한정) /
PNode→NimNode cast 없음 / report surface(nodeReports) 무변경 / subject VKD 미구현(WP3) /
runLeanVerify scope-guard 접촉 없음(WP2 예약 · blocker 등록 유지).

## 9. PASS 문장 (mission §10)
> External subject symbol successfully admitted into Axiom's verification universe
> with deterministic canonical identity and obligation-candidate semantics:
> E4 Admitted(origin=ExternalSubject), E5 reached the official obligation pipeline with a
> canonical no-obligation classification, origin preserved to IR, identity collision-free,
> and self-run semantics byte-stable.

## 10. Next (WP2 진입 조건 정리)
- Z3 대상 실검증을 위해 E5 candidateCount>0 필요 → 다음 후보 심볼은 guard/return-only
  성격인 bitops2 계열 중 obligation extractor가 admissible로 분류하는 것(예: 비트조합 순수함수).
- WP2 blocker 예약: lean-verify SupportUniverse leak(axiom_engine.nim:840 runLeanVerify),
  envHash subject-inputs(config.nims:394-445) 흡수 — 둘 다 M1 전 필수.

## 11. UNKNOWN / 이월
- obligation policy 특성상 swapBytesNim(body만 존재, pre/postcondition 부재)이 count=0으로
  분류된 것은 CanonicalNoObligation(규칙상 사후조건/루프/나눗셈 가드류가 과녁)이며,
  "extractor 결함"과는 구별됨 — WP2에서 양수 사례(postcondition 부여 가능 심볼)로 교차확인.
- certificate claim key의 논리명 충돌 여부는 현재 관측상 없으나(certificate JSON은
  modulePath+functionName 복합키) 서드파티 subject가 axiom 내부와 동일 modulePath 문자열을
  만들 경우는 WP3 evidence-scope 설계에서 재검토.
