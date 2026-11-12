# ACT 2 WP4-j.2 — Semantic Fact Preservation: 실측 보고서 (v16 동결 계획 실행)

- **실험 ID**: ACT2-WP4j2-semantic-facts
- **날짜**: 2026-08-30
- **Subject**: nim-stew `stew/bitops2.nim::getBitsBE` (rev `c75502ceedb5…`)
- **Axiom rev**: `44fefd470` working tree (WP4-j.1~j.2 변경 포함, 미커밋)
- **계약**: 승인 계획 v16(동결) — 구현 체크리스트 4불변식(INV-1~4), 부록 23개 잠금

---

## Question

`Source → faithful IR → F_const → E_all → BindSafetyGate → E_safe → SMT`
사슬의 각 경계에서 semantic information loss와 semantic aliasing을 기계적으로
차단하는 substrate를 코드로 고정할 수 있는가? (성공 기준은 getBitsBE UNSAT가 아니라
사슬 fidelity — 16차 확정.)

---

## Context

- 선행 사실(WP4-j.1): getBitsBE golden obligation `resultBits != 0`이 무제약 자유변수로
  lowering되어 자명한 sat → psFail (digest `d9f9af27…` 실증).
- 근본 원인(12라운드 검증 확정): ① `nnkConstSection` 미처리로 const 바인딩 드랍
  (ast_to_ir.nim convertBodyFrom case 누락) ② 미처리 표현식 노드의 `irLit(0)` 폴백
  ③ symbolTable 미구현 ④ template/macro의 opaque 확장 경계.

## Scope

- 포함: Level-1 fidelity repair(const/sizeof 보존 + lossy 추적), 독립 binding
  inventory, coverage witness, completeness evidence artifact(2축), BindSafetyGate,
  lowering fact assert(INV-1~4).
- 배제: scope-aware renaming, template/macro expansion, canonicalizeExpr shadowing
  수정, symbolTable 구현, sizeof 평가, relevance filtering, module-level const,
  generic instantiation — 전부 다음 capability(계획 §3).

## Procedure

- Phase A: 소실 경로 probe 고정(`probe/ingress-fidelity.md`).
- Phase B: fidelity repair — irLet `isCompileTime` 필드, CLET 직렬화/파싱/round-trip,
  binary 0x0E, Lean codec parity, canonicalizeExpr/tree-walk 복사, const 섹션 보존,
  sizeof 불투명 보존(irCall), lossySeen 추적, IRFuncDef evidence 필드(digest 분리
  검증), 독립 관찰자 `binding_inventory.nim`.
- Phase C: `semantic_fact_types.nim`(core, 데이터-온리) + `semantic_environment.nim`
  (verification) — `deriveSemanticFactsFromIR`(P-blind), `collectLetNames`,
  `collectLoopVarNames`, `filterResolvableFacts`(게이트).
- Phase D: evidence artifact(`.axiom/cache/evidence/<irDigest>.json`, 4종 exact-match),
  외부 경로 materializer 배선(raw PNode 독립 관찰 + correspondence + 저장),
  lowering 배선(선언 universe 확장 + fact assert), 호출 배치(:967~:969).
- Phase E: acceptance 테스트 행렬(F1a~F13) + 전체 회귀.
- Phase F: getBitsBE E2E Run A/B.

## Result (canonical machine-observed)

### 신규 테스트: 27/27 통과
- `test_wpj2_phaseb.nim` **15/15** (CLET round-trip, LET 호환, digest 구분/보존,
  binary 0x0E, F1a const 보존, F1b sizeof 불투명 보존, F1c lossy/lossless,
  F1d inventory NimNode/PNode+opaque, evidence/digest 분리)
- `test_wpj2_cde.nim` **12/12** (INV-1 선언 universe, INV-2 per-name 국소 거부,
  INV-3a/b/c 완전성 게이트, INV-4 결정론, F9c 이름 교환 반례, 파생 edge case)

### 기존 회귀: 전부 통과
ast_to_ir_test 39, axiom_ir_test 98, test_obligation_ir ALL,
test_obligation_execution_ledger 11, test_ir_pipeline_theaterguard (a)–(f),
proof_state_machine_test 52, wpj1_golden_script_repro **golden digest 불변**
(`d9f9af27…` — fact-free 기본 경로 회귀 안전). `make build` ✅, `make check-imports`
PASSED(41 files).

### Phase B 발견·수정 (검증 중 확정된 추가 사실)
- Nim 2.2.10에는 `nnkSizeOfExpr`/`nnkWhenExp` 노드 kind가 **존재하지 않는다**
  (sizeof는 nnkCall로 파싱; compile error로 실증) — 선행 분석의 일부 주장 정정.
  실제 getBitsBE의 1차 손실은 const 섹션 드랍이었다.
- const 섹션은 `nnkConstDef`/`nkConstDef`/`ckConstDef` 노드를 담는다
  (nnkIdentDefs 아님) — 3표현 모두에서 매칭 수정 필요했음.
- pnode_to_canon의 atom-guard 패턴(원자 노드 `.len` 접근 시 FieldDefect)을
  독립 관찰자에도 적용.

### Phase F — getBitsBE E2E (Run A/B, exit 2)
- **CAS key 변경**: `cf4013de…` → **`6c68651bf22c6234a8fd0935c3e6d15640ecc7a922a5eff49164edc9762bafaa`**
  — fidelity repair가 identity에 반영됨(const 보존 → CLET 직렬화 → digest 변화).
- **Evidence artifact 2개 생성**(`.axiom/cache/evidence/`): 정직한 계측값 —
  `translationLossFree: false`, `bindingUniverseComplete: false`,
  `opaqueExpansionStatus: "opaque-boundary-present"`,
  **`sourceBindingCount: 15` vs `irBindingCount: 12/13`** — 손실이 관찰되고 계측됨.
- **독립 관찰자 실증**: `binding_inventory`가 getBitsBE를 관찰 — 17 witnesses
  (param 3, let 12, **const:resultBits 1**, opaque template 경계 2) —
  번역기가 과거에 드랍하던 const 바인딩을 관찰자는 봈다(self-certification 차단 실증).
- 결정론: Run A ≡ Run B(timestamp 제거 후 diff IDENTICAL), CAS key 일관.
- 최종 분류: getBitsBE는 `sizeof 비-literal + opaque boundary`로 증표 미성립 →
  fact 전면 거부 → free-var → sat → psFail — **예상된 capability boundary의 재현**.

## Evidence

| 항목 | 값/위치 |
|---|---|
| probe | `experiments/act2-wpj2-semantic-facts/probe/ingress-fidelity.md` |
| Phase B 테스트 | `tests/unit/test_wpj2_phaseb.nim` 15/15 |
| Phase C/D/E 테스트 | `tests/unit/test_wpj2_cde.nim` 12/12 |
| 독립 관찰자 | `src/core/trusted/binding_inventory.nim` (func 10, proc 0 — cap 무관) |
| fact 타입 | `src/core/trusted/semantic_fact_types.nim` |
| projection/게이트 | `src/verification/obligation/semantic_environment.nim` |
| evidence IO | `src/infrastructure/evidence_artifact_io.nim` |
| E2E | `/tmp/wpj2_e2eA2.txt`, `/tmp/wpj2_e2eB.txt` (A≡B), evidence artifact 2건 |
| getBitsBE 신규 CAS key | `6c68651bf22c6234a8fd0935c3e6d15640ecc7a922a5eff49164edc9762bafaa` |

## Classification

**substrate 구현 성공 + capability boundary 재현 (`Incomplete`, getBitsBE UNSAT 미달)**.
- 4불변식 모두 기계 검증 통과(INV-1 선언 universe, INV-2 per-name 비혼합,
  INV-3 독립 완전성 증거+보존, INV-4 결정론).
- getBitsBE는 증표 미성립(손실 계측: 15 vs 12/13)으로 fact 거부 — 정직한 fail-closed.

## Interpretation

1. **loss가 이제 관찰되고 계측된다**: 과거에는 const 바인딩이 조용히 사라졌지만,
   이제 독립 관찰자가 15개 source binding을 세고 IR의 12/13개와 대조해 손실을
   수치로 남긴다. "잘 동작하는 것처럼 보이는 파이프라인"이 "각 경계의 보존/미보존을
   증명하는 파이프라인"으로 바뀌었다.
2. **translationLossFree ≠ bindingUniverseComplete 분리가 실제로 작동한다**:
   getBitsBE는 두 증거가 모두 false — 서로 다른 failure class(번역 손실 vs
   coverage 경계)가 별도로 기록된다.
3. **fidelity repair가 identity에 반영된다**: CAS key 변화는 보존된 의미가
   identity 체계에 도달했음을 보인다 — 하위 호환(LET 형식)은 불변.
4. **F6가 보조로 완화된 것은 정확하다**: getBitsBE UNSAT는 다음 capability
   (generic instantiation)의 결과다.

## Non-Conclusions

- getBitsBE(또는 nim-stew)가 검증됐다/안전하다 → 아님 (SMT 미판별).
- Axiom이 Nim binding universe 전체를 이해한다 → 아님 — "binding-witness.v1
  observation universe에 대해 correspondence가 닫혔다"만 주장 가능.
- 본 WP가 semantic aliasing을 "해결"했다 → 아님 — "검출 가능 범위에서 refusal"
  이다. scope-aware resolution은 다음 WP.
- evidence artifact 부재 시 기본값 true 복원 → 금지됨(부재 = 거부) — 확인됨.

## Next Experiment

1. **Generic instantiation → elaborated concrete type**: getBitsBE UNSAT의 정통
   경로(subject 소스 내 concrete instantiation — bitops2.nim:599 template
   wrapper의 BiggestUInt).
2. **RuntimeAxiomEntry.evidenceSerialized**(v2): 자기검증 경로의 evidence
   persistence(현재 외부 경로만 artifact 보존).
3. **canonicalizeExpr shadowing 결함 수정**(flat renameMap — 7차 발견, 별도 WP).
4. **WP4-j.3**: smNone provenance normalization.
5. **새 axiomDecision WARN 1건**: `loadEvidenceArtifact`(evidence_artifact_io.nim:75)
   — Result 반환에 pragma 미부여. 다음 WP에서 pragma 추가 또는 waiver.

## Non-goals (동결 유지)
- scope-aware renaming / template·macro expansion / sizeof 평가 / relevance
  filtering / module-level const / 일반 evaluator / Track B / repository-wide
  proof / Lean-KAA 변경 / contract 주입
