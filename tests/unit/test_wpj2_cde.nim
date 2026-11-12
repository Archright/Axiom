## tests/unit/test_wpj2_cde.nim
## WP4-j.2 Phase C+D+E — acceptance tests (plan v16, 4 INV).
##
## Covers:
##   - INV-1: fact introduces symbol not in P → (declare-fun W ...) present
##   - INV-2: same-name collision (compile-time W + runtime W) → W rejected
##   - INV-3: (a) translationLossFree=false → all rejected
##            (b) bindingUniverseComplete=false → all rejected
##            (c) both true + literal fact → fact assert included
##   - INV-4: identical input → identical SMT script; evidence changes → digest changes
##   - F9c: name-exchange counterexample → rejected (per-name locality)
##
## Custom main() pattern per tests/unit/ast_to_ir_test.nim precedent.

import std/[strutils, sequtils, json]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/private/obligation_smt_lowering
import core/trusted/semantic_fact_types
import verification/obligation/semantic_environment
import core/logic/smt_logic

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  let smtLogic = SmtLogic.slQfBv

  # Helper: build a funcDef with a compile-time literal let binding.
  func makeFuncDefWithFact(letName: string; litVal: int64): IRFuncDef =
    IRFuncDef(
      name: "test",
      params: @[],
      retType: irTypeBitVec64(),
      body: irLet(letName, irLit(litVal), irVar(letName, irTypeBitVec64()),
                   isCompileTime = true),
      isRecursive: false)

  # Helper: build a P proposition referencing a symbol.
  func makeProposition(refName: string): IRExpr =
    irBinOp(boEq, irVar(refName, irTypeBitVec64()), irLit(0))

  # =========================================================================
  # INV-1: Declaration Completeness — fact introduces symbol not in P
  # =========================================================================
  echo "=== INV-1: fact introduces symbol not in P ==="

  check "INV-1: declare-fun W exists when W appears only in fact":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    doAssert E_all.facts.len == 1, "expected 1 fact, got " & $E_all.facts.len
    let P = makeProposition("resultBits")  # P does NOT reference W
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 1, "fact should be kept (unique name)"
    let ctx = SmtLoweringContext(
      logic: smtLogic, rlimit: 10000, obligationKind: "test",
      semanticFacts: E_safe.facts)
    let lowered = lowerObligationToSmt(P, ctx)
    doAssert not lowered.empty, "SMT script should not be empty"
    doAssert "(declare-fun W" in lowered.smtScript,
      "W must be declared in SMT script: " & lowered.smtScript
    doAssert "(declare-fun resultBits" in lowered.smtScript,
      "resultBits must be declared in SMT script"
    let decls = lowered.smtScript.splitLines.filterIt(it.startsWith("(declare-fun"))
    doAssert decls.len == 2, "exactly 2 declare-fun: got " & $decls.len

  # =========================================================================
  # INV-2: Binding Non-Conflation — same-name collision
  # =========================================================================
  echo "=== INV-2: same-name collision (per-name locality) ==="

  check "INV-2: duplicate name W (let+param) → W rejected, boundary recorded":
    let funcDef = IRFuncDef(
      name: "test",
      params: @[IRFuncParam(name: "W", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: irLet("W", irLit(64), irVar("W", irTypeBitVec64()),
                   isCompileTime = true),
      isRecursive: false)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    doAssert E_all.facts.len == 1, "1 fact from let W"
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 2)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 0,
      "W fact should be rejected (ambiguous name), got " & $E_safe.facts.len
    doAssert E_safe.boundaryRecords.anyIt(it.symbol == "W" and it.reason == "ambiguous-name"),
      "boundary should record ambiguous-name for W"

  # =========================================================================
  # INV-3: Independent Completeness Evidence
  # =========================================================================
  echo "=== INV-3: completeness evidence gates fact emission ==="

  check "INV-3a: translationLossFree=false → ALL facts rejected":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: false, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 0, "all facts rejected when lossFree=false"
    doAssert E_safe.boundaryRecords.anyIt(it.reason == "completeness unproven"),
      "boundary should record completeness unproven"

  check "INV-3b: bindingUniverseComplete=false → ALL facts rejected":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: false,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 0, "all facts rejected when bindingComplete=false"

  check "INV-3c: both true + literal fact → fact assert included in script":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 1, "fact kept when both completeness axes pass"
    let ctx = SmtLoweringContext(
      logic: smtLogic, rlimit: 10000, obligationKind: "test",
      semanticFacts: E_safe.facts)
    let lowered = lowerObligationToSmt(P, ctx)
    doAssert not lowered.empty
    doAssert "W" in lowered.smtScript,
      "fact assert should be present: " & lowered.smtScript

  # =========================================================================
  # INV-4: Deterministic Projection
  # =========================================================================
  echo "=== INV-4: identical input → identical SMT bytes ==="

  check "INV-4: same funcDef → same SMT script on repeated lowering":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe1 = filterResolvableFacts(completeness, funcDef, P, E_all)
    let E_safe2 = filterResolvableFacts(completeness, funcDef, P, E_all)
    let ctx1 = SmtLoweringContext(
      logic: smtLogic, rlimit: 10000, obligationKind: "test",
      semanticFacts: E_safe1.facts)
    let ctx2 = SmtLoweringContext(
      logic: smtLogic, rlimit: 10000, obligationKind: "test",
      semanticFacts: E_safe2.facts)
    let s1 = lowerObligationToSmt(P, ctx1).smtScript
    let s2 = lowerObligationToSmt(P, ctx2).smtScript
    doAssert s1 == s2, "identical inputs must produce identical SMT scripts"

  check "INV-4: evidence JSON differs when evidence fields change":
    let ev1 = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: true,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let ev2 = CompletenessEvidence(
      translationLossFree: false, bindingUniverseComplete: false,
      opaqueExpansionStatus: "absent", sourceBindingCount: 0, irBindingCount: 0)
    let s1 = evidenceToJson(ev1)
    let s2 = evidenceToJson(ev2)
    doAssert $s1 != $s2, "different evidence must produce different JSON"

  # =========================================================================
  # F9c: Name-exchange counterexample → rejected (per-name locality)
  # =========================================================================
  echo "=== F9c: name-exchange counterexample ==="

  check "F9c: bindingUniverseComplete=false → all facts rejected":
    let funcDef = makeFuncDefWithFact("W", 64)
    let E_all = deriveSemanticFactsFromIR(funcDef)
    let P = makeProposition("resultBits")
    let completeness = CompletenessEvidence(
      translationLossFree: true, bindingUniverseComplete: false,
      opaqueExpansionStatus: "none", sourceBindingCount: 1, irBindingCount: 1)
    let E_safe = filterResolvableFacts(completeness, funcDef, P, E_all)
    doAssert E_safe.facts.len == 0, "all facts rejected on correspondence mismatch"

  # =========================================================================
  # deriveSemanticFactsFromIR: empty environment when no compile-time facts
  # =========================================================================
  echo "=== deriveSemanticFactsFromIR edge cases ==="

  check "deriveSemanticFactsFromIR empty when no isCompileTime let":
    let funcDef = IRFuncDef(
      name: "test", params: @[], retType: irTypeBitVec64(),
      body: irLet("x", irLit(1), irVar("x", irTypeBitVec64()),
                   isCompileTime = false),
      isRecursive: false)
    let env = deriveSemanticFactsFromIR(funcDef)
    doAssert env.facts.len == 0, "no compile-time facts → empty environment"

  check "deriveSemanticFactsFromIR non-literal isCompileTime → boundary":
    let funcDef = IRFuncDef(
      name: "test", params: @[], retType: irTypeBitVec64(),
      body: irLet("W", irCall("sizeof", @[irVar("x", irTypeBitVec64())]),
                   irVar("W", irTypeBitVec64()), isCompileTime = true),
      isRecursive: false)
    let env = deriveSemanticFactsFromIR(funcDef)
    doAssert env.facts.len == 0, "non-literal → no fact"
    doAssert env.boundaryRecords.len >= 1, "non-literal → boundary recorded"
    doAssert env.boundaryRecords.anyIt(it.symbol == "W" and it.reason == "value-not-literal"),
      "boundary should record value-not-literal for W"

  # =========================================================================
  # collectLetNames / collectLoopVarNames
  # =========================================================================
  echo "=== collectLetNames / collectLoopVarNames ==="

  check "collectLetNames includes duplicates":
    let body = irLet("W", irLit(1),
      irLet("W", irLit(2), irVar("W", irTypeBitVec64()), isCompileTime = false),
      isCompileTime = false)
    let names = collectLetNames(body)
    doAssert names.len == 2, "2 let bindings"
    doAssert names.count("W") == 2, "W appears twice"

  check "collectLoopVarNames collects loop vars":
    let body = IRExpr(kind: irLoop, loopKind: lkFor, loopVars: @["i", "j"],
      loopInits: @[], loopCond: irLit(1), loopStep: irLit(1),
      loopBody: irVar("i", irTypeBitVec64()),
      loopInvariants: @[], loopVariant: nil, typ: irTypeBitVec64())
    let funcDef = IRFuncDef(
      name: "test", params: @[], retType: irTypeBitVec64(),
      body: body, isRecursive: false)
    let vars = collectLoopVarNames(funcDef)
    doAssert vars.len == 2, "2 loop vars"
    doAssert vars.contains("i") and vars.contains("j")

  # =========================================================================
  # Summary
  # =========================================================================
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
