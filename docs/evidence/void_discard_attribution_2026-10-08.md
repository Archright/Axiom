# Void-Discard 귀속 조사 — axiom_pragmas + ir_inline_pass 조합 판정 (2026-10-08)

> 이전 세션의 안전 진단 프로브 `tmp/kernel_oracle_probe.nim`(gitignored)에서 참고용으로만
> 기록됐던 사실 — "**`axiom_pragmas` + `ir_inline_pass` 조합 시 void-discard 해석 오류**" — 의
> 귀속을 확정한다. 작업 브랜치: `chore/void-discard-investigation`, worktree:
> `wt-bg4-voiddiscard` (origin/main 83bc2c995 기준).

---

## 1. 판정 (Verdict): (b) — 등록 필요, 코드 수정 불요

**실제 파이프라인(ir_inline_pass)은 정상이고, 프로브도 void-discard 오류를 실제로 발생시키지
않았으며, 근본 요인은 Axiom IR 번역기(ast_to_ir)의 void 표현력 한계다.** 현재 파이프라인
입력에서는 도달 불가(loss 플래그 + census 분류로 봉쇄)이므로 §0.12 최소 변경 원칙에 따라
코드 패치 없이 **DEBT#496** 으로 등록한다 (ADR-0029 §5 승인 수동 mutation surface,
DEBT#494 등록 방식 준용). Nim 언어 quirk가 아니므로 (c) `docs/spec/nim_2_2_10_stdlib_quirks.md`
등록은 기각된다.

## 2. 재현 (Reproduction)

프로브 자체는 오류 없이 컴파일·실행된다 (typed lowering의 refuse 2건은 DEBT#465 이후의
fail-closed 설계 동작 — `smtTermFor` 지원 slice 밖의 `irIf`/`boLe` 등 — 로 void-discard와
무관):

```
$ nim c --path:src -o:tmp/kernel_oracle_probe tmp/kernel_oracle_probe.nim   # 성공
$ ./tmp/kernel_oracle_probe
== normalizeMaxWorkers ogrKind=ogrNoApplicableObligation obligations=0
== calcDynamicTimeoutCore ogrKind=ogrNoApplicableObligation obligations=0
== safeSpeedupRatioCore ogrKind=ogrNoApplicableObligation obligations=0
== proximityScore ogrKind=ogrGenerated obligations=2
   proposition nil? false
   empty=true err=lowerObligationToSmt: unsupported IRExpr kind in proposition
   --- CLASSIC SCRIPT (typed refused) ---
== NMW(hand-built) ogrKind=ogrGenerated
   err=lowerObligationToSmt: 'result' requires body binding but the subject body
   is not expressible in the typed define-fun impl form
```

최소 재현 2건 (모두 gitignored probe, worktree에서 제작):

** repro 1 — 매크로 레지스트리 경로 (axiomImpl → runtimeAxiomRegistry → deserialize →
ir_inline_pass.inlineSmallFunctions):**

```
-- vdVoidIf   (proc vdVoidIf(n: int) {.axiomImpl.} = if n > 0: discard)
   ret=irtBitVec64 body=If(Bin(boGt),Lit(0),Lit(0))          ← void가 BitVec64+Lit(0)으로 위조
-- vdLeadingDiscard (discard; x + 1)
   ret=irtBitVec64 body=Bin(boAdd)                            ← discard drop은 의미 보존 (정상)
-- vdVoidOnly (proc(x: int) {.axiomImpl.} = discard)
   ret=irtBitVec64 body=Lit(0)                                ← void 본문 = 상수 0 위조
-- vdTryDiscard (try: result = 1 except: discard)
   ret=irtBitVec64 body=Lit(0)                                ← result = 1 대입까지 소실
inline caller: Let(r,Call(vdLeadingDiscard),Var(r))
          → Let(r,Let(__inl_1,Var(x),Bin(boAdd)),Var(r))      ← 인라인 패스 자체는 정확
inline void callee: Let(u,Call(vdVoidIf),Lit(7))
          → Let(u,Let(__inl_2,Var(n),If(Bin(boGt),Lit(0),Lit(0))),Lit(7))
                                                             ← 위조 본문이 그대로 인라인됨
```

**repro 2 — external materializer 경로 (materializeExternalIR, 프로브가 실제 사용하는 경로):**

```
== subjectCaller (helperVoid(x); x + 1)  → body=Bin(boAdd) lossFree=false
   ← void 호출문이 IR 도달 전에 drop — inline 패스는 void callee를 애초에 못 받음
== helperVoid (if n > 0: discard)        → body=Lit(0)      lossFree=false
== subjectTail  (discard; x * 2)         → body=Bin(boMul)  lossFree=false (의미 보존)
== subjectTry   (try: result = 3 except: discard) → body=Lit(0) lossFree=false
inline(subjectCaller.body, env=[caller, helperVoid]): before=Bin(boAdd) after=Bin(boAdd)  ← no-op
```

## 3. 근본 원인 메커니즘

1. **IR에 void 타입이 없다** — `src/core/trusted/axiom_ir.nim`에 `irtVoid` 부재 (grep 0건).
   `convertFuncDef`(`src/core/trusted/ast_to_ir.nim:1367-1370`)는 void 반환(`formalParams[0]
   .kind == nnkEmpty`)을 `irTypeBitVec64()`로 조용히 기본값 처리한다.
2. **문장 레벨 discard drop** — NimNode 경로 `convertBodyFrom` `of nnkDiscardStmt: discard`
   (`ast_to_ir.nim:716-717`), CanonNode 경로 `of ckDiscardStmt: discard` (`:1255-1256`).
   값 반환 함수에서 이는 의미 보존(discard는 null statement)이지만, try/except-discard 같은
   비후위 제어문 전체가 drop되면 `result = 3` 대입까지 소실된다.
3. **후위 값 표현식 부재 시 위조 fallback** — `body = irLit(0)` (`:969-970`, CanonNode
   `:1282-1283`). void 본문이 "상수 0을 반환하는 BitVec64 함수"로 위조된다.
4. **axiomImpl은 가드 없음** — `axiomTryImpl`은 `hasUnsupportedPatterns`로 for/var/asgn/
   dot 등을 opaque fallback시키지만(`axiom_pragmas_macros.nim:753-761`), `axiomImpl`은
   이 가드 없이 `effectKind = Pure`, `isKern = true` 하드코딩으로 등록한다(`:685-686`) —
   void axiomImpl 함수가 있다면 커널 스코프 멤버로 위조 IR이 등록된다.
5. **ir_inline_pass는 기계적 중립** — 등록된 IR callee(≤10 노드, 비재귀)를 그대로 인라인할
   뿐, void/discard를 도입하거나 왜곡하지 않는다. 위조는 인라인 패스 **업스트림**(ast_to_ir)에서
   만들어진다.

## 4. 귀속 배제 근거

- **(a) 실제 검증 정확성 영향 — 아니오(오늘 기준)**: (i) src/ 전수 스캔에서 void 반환
  axiomImpl/axiomTryImpl 함수 0건 → 레지스트리 경로 도달 불가; (ii) materializer 경로는
  void 호출문을 inline 패스 이전에 drop; (iii) lossy materialization은
  `translationLossFree=false`/`bindingUniverseComplete=false`가 기록되고
  (`external_ir_materializer.nim:293-302`) semantic facts 전량 거부
  (`semantic_environment.nim:219-222`), census ineligible
  (`candidate_eligibility.nim` buvLossy* → `censusEligible=false`,
  `crrSemanticUnresolvedFact`), composite claim carrier는 loss-marked 본문 거부
  (`axiom_engine.nim:1558-1563`). 근본 수정은 IR에 void/문장 도메인을 추가하는
  표현력 확장이라 최소 변경이 아니며(§0.12), 현재 고객 대면 영향 0이다.
- **(c) Nim 언어 quirk — 아니오**: Context7 Nim 공식 문서(manual/tut1) 조회 결과 —
  `discard`는 "식을 side effect 위해 평가하고 반환값을 무시"하는 문장, 빈 `discard`는
  null statement, void는 값을 갖지 않는 타입. discard drop은 표현식 IR 번역으로서 정확하고,
  void→BitVec64(0) 위조는 Nim 의미 오해가 아니라 Axiom 자체 IR 값 도메인의 한계다.
  툴체인/stdlib quirk 문서(`docs/spec/nim_2_2_10_stdlib_quirks.md`) 대상이 아니다.

## 5. 조사·검증 명령 기록

- `git worktree add .../wt-bg4-voiddiscard -b chore/void-discard-investigation origin/main`
- `make ci-bootstrap` — 통과 (147s)
- `nim c --path:src tmp/kernel_oracle_probe.nim` + 실행 — §2 출력
- `nim c --path:src tmp/void_discard_repro.nim` + 실행 — repro 1 출력
- `nim c --path:src tmp/void_discard_materializer_repro.nim` + 실행 — repro 2 출력
- src/ void axiomImpl 전수 스캔(python 정규 스캐너) — 0건
- `bin/debt_engine --codegen && --sync-budget && --validate` — §6 참조
- `make build`, `make local-verify-static`, `tools/local_purity_check` — PR 게이트 기록 참조

## 6. 등록

- `data/debt_registry.json`: DEBT#496 open 등록 (category "Verification Semantics / IR
  Translation Expressiveness", files 5건, source "void-discard investigation 2026-10-08").
  등록 절차: ADR-0029 §5(debt projection writer authority) 수동 레지스트리 편집 +
  `debt_engine --codegen/--sync-budget/--validate` 클린, DEBT#494 선례 준용.
- 후속 트리거: void 반환 axiomImpl/axiomTryImpl 함수의 신규 추가, 또는 lossy single을
  BMC에 허용하는 external-subject selection 변경 시 이 부채의 재평가(remediation 옵션
  a/b)가 요구된다.
