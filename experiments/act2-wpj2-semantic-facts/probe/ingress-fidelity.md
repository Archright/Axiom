# WP4-j.2 Phase A — Source→IR localization probe (read-only 확정 사실 고정)

- 실험 ID: ACT2-WP4j2-semantic-facts / Phase A
- 날짜: 2026-08-30
- Axiom rev: 44fefd470 (working tree), Subject: nim-stew c75502c
- 근거: WP4-j.1 보고서 + 12라운드 병렬 검증(subagent 49~63, file:line 재확인 완료)

## 1. 확정된 소실/오번역 경로 (Level-1 fidelity 결함 목록)

### 1-A. convertExpr else 폴백 — irLit(0) 오번역
- 위치: `src/core/trusted/ast_to_ir.nim:340-341`
- `nnkSizeOfExpr` 등 case에 없는 모든 표현식 노드가 `irLit(0)`으로 번역됨
  — sizeof의 값이 아니라 **잘못된 상수**를 생성(A급 결함).
- 영향 구성체(폴백에 빠지는 노드 — subagent 60 확인):
  `nnkTemplateDef, nnkMacroDef, nnkIteratorDef, nnkConverterDef,
   nnkBlockStmt, nnkBlockExpr, nnkWhenStmt, nnkWhenExp, nnkStaticStmt,
   nnkImportStmt, nnkExportStmt, nnkTypeSection, nnkConstSection,
   nnkSizeOfExpr` + 기타 전부.

### 1-B. convertBodyFrom case 누락 — const 섹션 드랍
- 위치: `src/core/trusted/ast_to_ir.nim:506-796` (case :516, 처리 :517-788, else :789)
- `nnkLetSection`(:528)/`nnkVarSection`(:534)은 `irLet` 바인딩으로 보존되나
  **`nnkConstSection` case가 없어** const 선언이 드랍됨.
- else(:789)는 `bodyExpr = child` → convertExpr(:792) → **else 폴백 → irLit(0)**.
- 동일하게 드랍되는 문장 노드: `nnkBlockStmt, nnkWhenStmt, nnkTemplateDef,
  nnkMacroDef, nnkIteratorDef, nnkConverterDef, nnkStaticStmt, nnkImportStmt,
  nnkExportStmt, nnkTypeSection`.

### 1-C. resolveConstVal 하드코딩
- 위치: `:474-483` — `minDynamicTimeoutMs`/`maxDynamicTimeoutMs` 2개만 인라인,
  나머지는 미해석. 일반 상수 처리 없음.

### 1-D. symbolTable 미구현
- `IRFuncDef.symbolTable`(axiom_ir.nim:153) 선언만 존재,
  `convertFuncDef`(:1080)에서 populate하지 않음 — scope 구조가 IR에 없음.

### 1-E. 제네릭/인스턴스 정보 부재
- `convertFuncDef`(:1041)는 `nnkGenericParams`(n[1])를 무시.
- `convertTypeCanon`(:43-57)은 uint8~uint64 전부 `irTypeBitVec64()`.
- `IRType.irtBitVec64`는 폭 파라미터 없음(axiom_ir_types.nim:26-27).
- template wrapper(bitops2.nim:599)는 nnkTemplateDef로 미처리 — 인스턴스 심볼 없음.

### 1-F. canonicalizeExpr shadowing 결함 (별도 WP — 본 WP 미수정)
- `axiom_ir.nim:361` `renameMap[e.letName] = newName` flat overwrite —
  동일 이름 중첩 바인딩에서 바깥 rename이 안쪽으로 덮임.

## 2. opaque binding 구성체 목록 (opaqueExpansionStatus 판정 대상)

번역기가 binding을 도입할 수 있으나 **의미 확장이 불투명**한 구성체:
- `nnkTemplateDef` — 본문이 호출 지점에서 확장; untyped 파라미터는 호출 지점에
  binding을 선언할 수 있음(Nim manual: declareInt 예제).
- `nnkMacroDef` — 임의 AST 생성.
- `nnkIteratorDef`, `nnkConverterDef` — 선언 도입.
- `nnkWhenStmt` — 컴파일 타임 분기로 한쪽 binding만 실재.
- `nnkStaticStmt` — 컴파일 타임 실행.
- `nnkImportStmt/nnkExportStmt` — 외부 심볼 표면.
v1 규칙: 이들이 관찰되면 `opaqueExpansionStatus ∈ {opaque, unknown}` →
`bindingUniverseComplete = false` → fact 전면 거부.

## 3. 재표현(보존) 대상 — Phase B의 수정 범위

- `nnkConstSection` → `irLet(letName, letVal, letBody, isCompileTime=true)` 보존.
- `nnkSizeOfExpr` → `irCall("sizeof", [operand])` 보존(irLit(0) 폴백 제거).
- 미처리 나머지 노드: **fallback 도달을 증표로 기록**(translationLossFree=false)
  — 본 WP에서 표현하지 않는다(억지 확장 금지).

## 4. Phase A corpus

| # | 소스 패턴 | 목적 |
|---|---|---|
| C1 | getBitsBE(bitops2.nim:559) — `const resultBits = sizeof(result)*8` | anchor: const+sizeof+제네릭 |
| C2 | `const W = 64` 단독 literal const 함수 | 순수 literal const fact |
| C3 | `const W = someProc()` 형태 비-literal const | F4n 음성(universe 제외) |
| C4 | let-only 함수(대조군) | 기존 경로 회귀 |
| C5 | block/when 내 let 포함 함수 | opaque 경계 관찰 |
- 실제 소스 fixture는 Phase E 테스트에서 IR 직접 구성(ast_to_ir_test.nim:132 선례,
  `irLet("tmp", irLit(42), ...)`)+ `quote do:`(axiom_to_ir_test.nim:274) 병용.

## 5. Phase B~D 실행 전 재확인 항목 (구현 시 체크)

- irLet 필드 추가 → serializeIRExpr(:233)/parseIRExpr(:728, **CLET 분기 LET 선행**)/
  canonicalizeExpr(:357 복사 필수)/ir_binary_codec(0x0E 신규 태그)/
  AxiomIRExpr.lean(:46, :322-331 codec parity)/ir_to_smt_chunk1(:20-23,:101-104)/
  ir_tree_ops(:40-43,:121-124) 복사.
- NKind와 NimNodeKind는 동일 정수값 공유(pnode_to_canon.nim:89-90) —
  binding_inventory가 두 표현을 병렬 처리 가능.
- proc cap: `proc `로 시작하는 줄만 카운트(architecture_invariants.nim:555-566) —
  func/타입/필드/const 추가는 무관.
- evidence 필드는 semantic digest에서 자동 분리(serializeIRFuncDef가
  symbolTable을 건너뛰는 것과 동일 패턴 — :304-313).
