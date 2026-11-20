## Direct proof boundary conformance — executable form of
## docs/spec/direct_proof_boundary.md §2–§3.
##
## Every normative row of §3 (nine constructs) and every renderer-empty item
## of §2 (eight IR kinds) is asserted against the production functions, not
## against a reimplementation:
##
##   A1 object constructor (nnkObjConstr) — NimNode path (compile-time
##      quote/do → convertFuncDef) and Canon path (parseStringAST →
##      pnodeToCanon → axiomBodyCanon): irLit(0) placeholder handled by the
##      generic fallback with markLoss, translationLossFree=false.
##   A2 template definition — hasAxiomPragma accepts nnkTemplateDef,
##      IrTranslatableDefKinds rejects it, and the real materializer API
##      (materializeExternalIR) reports moUnsupportedDeclKind.
##   A3 move(x) — irCall("move", …), loss-free at conversion, and the
##      canonical renderer emits no denotation.
##   A4 in / of — convertBinOp → boUnsupported, loss-marked, empty lowering.
##   A5 .. / ..< slice — irCall("[]", [seq, idx]) with the index infix at
##      boUnsupported, loss-marked, empty lowering.
##   A6 .. / ..< range-for, NimNode path — irLoop with boLt (exclusive) /
##      boLe (inclusive), loss-free; irLoop has no canonical denotation.
##   A7 .. / ..< range-for, Canon path — ckForStmt region drop, loop absent
##      from the IR, translationLossFree=false.
##   A8 shl / shr — boShl / boShr, loss-marked, empty lowering, and the
##      replay evaluator refuses (none), so no refutation can be manufactured.
##   A9 any other infix — boUnsupported (xor spelling), loss-marked, empty
##      lowering.
##
##   B  renderer-empty items (§2): lowerIRExprToLean returns "" for irCall,
##      irLet, irLoop, irRecCall, irCase, irCast, irStringLit, and a
##      non-parameter irVar. B0 is a positive control proving the renderer is
##      not universally empty.
##
## Status-vocabulary guard (§2 "refuted"): NOT asserted here, deliberately.
## "refuted" is a per-obligation replay verdict — a concrete counterexample
## against a specific proposition — and no construction-only path emits it.
## The canonical obligation path (executeCanonicalVerification) requires a
## live Lean kernel run and a postcondition; synthesising a certRed from a
## construct's shape would fabricate the very evidence §4 says is per
## obligation. What IS cheap and honest is asserted: evalConcreteBinOp refuses
## boShl/boShr/boUnsupported (none), so rows A8/A9 cannot manufacture a
## refutation through replay. No other row is classified here.
##
## Run: nim c -r tests/trusted/test_direct_proof_boundary.nim
##      (make verify-proof-boundary — prerequisite of the required CI check's
##       verify-contract-release-e2e-full path)

import std/[macros, options, sets, strutils]
import compiler/ast
import core/parser_utils
import core/axiom_pragmas
import core/trusted/ast_to_ir
import core/trusted/axiom_ir_helpers
import core/trusted/pnode_to_canon
import infrastructure/external_ir_materializer
import verification/obligation/canonical_verification
import verification/counterexample_replay

setExternalSubjectMode(true)

func outermostLetValChain(e: IRExpr): IRExpr =
  ## The range-for body is an irLet chain whose letVal terminates at the
  ## irLoop (tests/trusted/test_ast_to_ir.nim Tests 7–8 walk it the same way).
  result = e
  while result != nil and result.kind == irLet:
    result = result.letVal

func containsIrLoop(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irLoop: true
  of irLet: containsIrLoop(e.letVal) or containsIrLoop(e.letBody)
  of irIf:
    containsIrLoop(e.ifCond) or containsIrLoop(e.ifThen) or
      containsIrLoop(e.ifElse)
  of irBinOp: containsIrLoop(e.binLhs) or containsIrLoop(e.binRhs)
  of irUnaryOp: containsIrLoop(e.unaryArg)
  of irCall:
    for a in e.callArgs:
      if containsIrLoop(a): return true
    false
  of irRecCall:
    for a in e.recArgs:
      if containsIrLoop(a): return true
    false
  of irCase:
    if containsIrLoop(e.caseScrutinee): return true
    for b in e.caseBranches:
      if containsIrLoop(b.body): return true
    containsIrLoop(e.caseDefault)
  of irCast: containsIrLoop(e.castExpr)
  else: false

macro nimNodePathRows(): untyped =
  ## Every NimNode-path row is evaluated at compile time (convertFuncDef is a
  ## compile-time-only API on NimNode). The results are returned as a literal
  ## seq of (name, passed, detail) so the runtime harness can count them with
  ## the Canon-path and renderer checks in one pass/fail tally.
  var rows: seq[NimNode] = @[]
  proc addRow(name: string; ok: bool; detail: string) =
    rows.add nnkTupleConstr.newTree(newLit(name), newLit(ok), newLit(detail))

  # -- A1: object constructor (nnkObjConstr) -------------------------------
  block:
    let def = quote do:
      func pbObjCtor*(x: int): int =
        result = T(f: x)
    let ir = convertFuncDef(def)
    addRow("A1 object constructor NimNode: body=irLit(0), loss-marked",
           ir.body != nil and ir.body.kind == irLit and
             not ir.translationLossFree,
           "body=" & $ir.body.kind & " lossFree=" & $ir.translationLossFree)

  # -- A2: template definition ---------------------------------------------
  block:
    # The pragma is built as nnkIdent (the untyped-macro-input shape
    # hasAxiomPragma's Ident branch recognises). A `quote do` template whose
    # body is semantically reachable from this module resolves `axiom` to a
    # Sym instead, which the detector does not match — so the fixture mirrors
    # the untyped input the production macro actually receives.
    let tmpl = nnkTemplateDef.newTree(
      nnkPostfix.newTree(ident"*", ident"pbTemplate"),
      newEmptyNode(), newEmptyNode(),
      nnkFormalParams.newTree(
        ident"int",
        nnkIdentDefs.newTree(ident"x", ident"int", newEmptyNode())),
      nnkPragma.newTree(ident"axiom"),
      newEmptyNode(),
      nnkStmtList.newTree(ident"x"))
    addRow("A2 template: hasAxiomPragma accepts nnkTemplateDef",
           tmpl.kind == nnkTemplateDef and hasAxiomPragma(tmpl),
           "kind=" & $tmpl.kind & " pragmaAccepted=" & $hasAxiomPragma(tmpl))
    addRow("A2 template: IrTranslatableDefKinds rejects nkTemplateDef",
           nkTemplateDef notin IrTranslatableDefKinds and
             nkProcDef in IrTranslatableDefKinds and
             nkFuncDef in IrTranslatableDefKinds,
           "templateExcluded=" & $(nkTemplateDef notin IrTranslatableDefKinds) &
             " procAccepted=" & $(nkProcDef in IrTranslatableDefKinds) &
             " funcAccepted=" & $(nkFuncDef in IrTranslatableDefKinds))

  # -- A3: move(x) ----------------------------------------------------------
  block:
    let def = quote do:
      func pbMove*(x: int): int =
        result = move(x)
    let ir = convertFuncDef(def)
    addRow("A3 move(x): convertCall → irCall(\"move\", …), loss-free",
           ir.body != nil and ir.body.kind == irCall and
             ir.body.callName == "move" and ir.body.callArgs.len == 1 and
             ir.translationLossFree,
           "kind=" & $ir.body.kind & " name=" &
             (if ir.body.kind == irCall: ir.body.callName else: "-") &
             " lossFree=" & $ir.translationLossFree)

  # -- A4: in / of ---------------------------------------------------------
  block:
    let def = quote do:
      func pbIn*(x: int, s: seq[int]): bool =
        result = x in s
    let ir = convertFuncDef(def)
    addRow("A4 in: convertBinOp → boUnsupported, loss-marked",
           ir.body != nil and ir.body.kind == irBinOp and
             ir.body.binOp == boUnsupported and not ir.translationLossFree,
           "kind=" & $ir.body.kind & " op=" &
             (if ir.body.kind == irBinOp: $ir.body.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)
  block:
    let def = quote do:
      func pbOf*(x: int): bool =
        result = x of int
    let ir = convertFuncDef(def)
    addRow("A4 of: convertBinOp → boUnsupported, loss-marked",
           ir.body != nil and ir.body.kind == irBinOp and
             ir.body.binOp == boUnsupported and not ir.translationLossFree,
           "kind=" & $ir.body.kind & " op=" &
             (if ir.body.kind == irBinOp: $ir.body.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)

  # -- A5: .. / ..< slice --------------------------------------------------
  block:
    let def = quote do:
      func pbSliceIncl*(s: seq[int], a, b: int): int =
        result = s[a..b]
    let ir = convertFuncDef(def)
    addRow("A5 slice `s[a..b]`: irCall(\"[]\", [seq, idx]), idx boUnsupported",
           ir.body != nil and ir.body.kind == irCall and
             ir.body.callName == "[]" and ir.body.callArgs.len == 2 and
             ir.body.callArgs[1].kind == irBinOp and
             ir.body.callArgs[1].binOp == boUnsupported and
             not ir.translationLossFree,
           "kind=" & $ir.body.kind & " name=" &
             (if ir.body.kind == irCall: ir.body.callName else: "-") &
             " idxOp=" &
             (if ir.body.kind == irCall and ir.body.callArgs.len == 2 and
                 ir.body.callArgs[1].kind == irBinOp:
                $ir.body.callArgs[1].binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)
  block:
    let def = quote do:
      func pbSliceExcl*(s: seq[int], a, b: int): int =
        result = s[a..<b]
    let ir = convertFuncDef(def)
    addRow("A5 slice `s[a..<b]`: irCall(\"[]\", [seq, idx]), idx boUnsupported",
           ir.body != nil and ir.body.kind == irCall and
             ir.body.callName == "[]" and ir.body.callArgs.len == 2 and
             ir.body.callArgs[1].kind == irBinOp and
             ir.body.callArgs[1].binOp == boUnsupported and
             not ir.translationLossFree,
           "kind=" & $ir.body.kind & " idxOp=" &
             (if ir.body.kind == irCall and ir.body.callArgs.len == 2 and
                 ir.body.callArgs[1].kind == irBinOp:
                $ir.body.callArgs[1].binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)

  # -- A6: .. / ..< range-for, NimNode path --------------------------------
  block:
    let def = quote do:
      func pbSumExcl*(n: int): int =
        result = 0
        for i in 0 ..< n:
          result = result + i
    let ir = convertFuncDef(def)
    let loop = outermostLetValChain(ir.body)
    addRow("A6 range-for `..<` NimNode: irLoop cond boLt, loss-free",
           loop != nil and loop.kind == irLoop and
             loop.loopCond.kind == irBinOp and
             loop.loopCond.binOp == boLt and ir.translationLossFree,
           "loop=" & (if loop == nil: "nil" else: $loop.kind) &
             " cond=" &
             (if loop != nil and loop.kind == irLoop and
                 loop.loopCond != nil and loop.loopCond.kind == irBinOp:
                $loop.loopCond.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)
  block:
    let def = quote do:
      func pbSumIncl*(n: int): int =
        result = 0
        for i in 0 .. n:
          result = result + i
    let ir = convertFuncDef(def)
    let loop = outermostLetValChain(ir.body)
    addRow("A6 range-for `..` NimNode: irLoop cond boLe, loss-free",
           loop != nil and loop.kind == irLoop and
             loop.loopCond.kind == irBinOp and
             loop.loopCond.binOp == boLe and ir.translationLossFree,
           "loop=" & (if loop == nil: "nil" else: $loop.kind) &
             " cond=" &
             (if loop != nil and loop.kind == irLoop and
                 loop.loopCond != nil and loop.loopCond.kind == irBinOp:
                $loop.loopCond.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)

  # -- A8: shl / shr -------------------------------------------------------
  block:
    let def = quote do:
      func pbShl*(a, b: int): int =
        result = a shl b
    let ir = convertFuncDef(def)
    addRow("A8 shl: convertBinOp → boShl, loss-marked",
           ir.body != nil and ir.body.kind == irBinOp and
             ir.body.binOp == boShl and not ir.translationLossFree,
           "kind=" & $ir.body.kind & " op=" &
             (if ir.body.kind == irBinOp: $ir.body.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)
  block:
    let def = quote do:
      func pbShr*(a, b: int): int =
        result = a shr b
    let ir = convertFuncDef(def)
    addRow("A8 shr: convertBinOp → boShr, loss-marked",
           ir.body != nil and ir.body.kind == irBinOp and
             ir.body.binOp == boShr and not ir.translationLossFree,
           "kind=" & $ir.body.kind & " op=" &
             (if ir.body.kind == irBinOp: $ir.body.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)

  # -- A9: any other infix (xor spelling falls to the else arm) ------------
  block:
    let def = quote do:
      func pbXor*(a, b: int): int =
        result = a xor b
    let ir = convertFuncDef(def)
    addRow("A9 other infix (xor): convertBinOp → boUnsupported, loss-marked",
           ir.body != nil and ir.body.kind == irBinOp and
             ir.body.binOp == boUnsupported and not ir.translationLossFree,
           "kind=" & $ir.body.kind & " op=" &
             (if ir.body.kind == irBinOp: $ir.body.binOp else: "-") &
             " lossFree=" & $ir.translationLossFree)

  var arr = nnkBracket.newTree()
  for r in rows:
    arr.add r
  result = nnkPrefix.newTree(ident"@", arr)

proc canonIr(source, funcName: string): IRFuncDef =
  ## parseStringAST → pnodeToCanon → axiomBodyCanon: the exact Canon path the
  ## external materializer drives (external_ir_materializer.nim:544).
  let ast = parseStringAST(source)
  if ast.isNil: return default(IRFuncDef)
  let def = findFuncDefP(ast, funcName, "")
  if def.isNil: return default(IRFuncDef)
  axiomBodyCanon(pnodeToCanon(def))

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
        echo "  FAIL: " & name & " — " & getCurrentExceptionMsg()

  template require(cond: bool, detail: string) =
    if not cond:
      raise newException(ValueError, detail)

  echo "=== Direct proof boundary conformance ==="
  echo "    docs/spec/direct_proof_boundary.md §2 (renderer-empty) + §3 (9 rows)"
  echo ""

  echo "[A] §3 per-construct rows — NimNode path (compile-time conversion)"
  for r in nimNodePathRows():
    if r[1]:
      inc passed
      echo "  PASS: " & r[0]
    else:
      inc failed
      echo "  FAIL: " & r[0] & " — " & r[2]
  echo ""

  initParserUtils()
  echo "[A] §3 per-construct rows — Canon path / renderer / materializer"

  check "A1 object constructor Canon: body=irLit(0), translationLossFree=false":
    let ir = canonIr("""
func pbObjCtorCanon(x: int): int =
  result = T(f: x)
""", "pbObjCtorCanon")
    require ir.body != nil, "no body produced"
    require ir.body.kind == irLit, "body kind " & $ir.body.kind
    require not ir.translationLossFree, "translationLossFree must be false"

  check "A2 template: materializeExternalIR → moUnsupportedDeclKind (nkTemplateDef)":
    let resolver: ModuleContentResolver =
      proc(modulePath: string): Option[string] {.raises: [], noSideEffect.} =
        some("template pbTwice(x: int): int = x + x")
    let symRef = SubjectSymbolRef(relativeModulePath: "subject/pb_template.nim",
                                  functionName: "pbTwice")
    let (outcome, entry) = materializeExternalIR(symRef, resolver)
    require outcome == moUnsupportedDeclKind,
      "outcome " & $outcome & " (reason: " & entry.unsupportedReason & ")"
    require "nkTemplateDef" in entry.unsupportedReason,
      "reason did not name nkTemplateDef: " & entry.unsupportedReason

  check "A3 move: canonical lowering and rendered function are empty":
    var params = initHashSet[string]()
    params.incl "x"
    let body = irCall("move", @[irVar("x", irTypeBitVec64())])
    require lowerIRExprToLean(body, params) == "", "lowering not empty"
    let fd = irFuncDef("pbMove", @[("x", irTypeBitVec64())],
                       irTypeBitVec64(), body)
    require renderLeanForFuncDef(fd) == "", "renderLeanForFuncDef not empty"

  check "A4 in / of: canonical lowering empty":
    var params = initHashSet[string]()
    params.incl "x"
    params.incl "s"
    let inIr = canonIr("""
func pbInCanon(x: int, s: seq[int]): bool =
  result = x in s
""", "pbInCanon")
    require inIr.body != nil and inIr.body.kind == irBinOp and
      inIr.body.binOp == boUnsupported, "in did not convert to boUnsupported"
    require not inIr.translationLossFree, "in must be loss-marked"
    require lowerIRExprToLean(inIr.body, params) == "", "in lowering not empty"
    let ofIr = canonIr("""
func pbOfCanon(x: int): bool =
  result = x of int
""", "pbOfCanon")
    require ofIr.body != nil and ofIr.body.kind == irBinOp and
      ofIr.body.binOp == boUnsupported, "of did not convert to boUnsupported"
    require not ofIr.translationLossFree, "of must be loss-marked"
    require lowerIRExprToLean(ofIr.body, params) == "", "of lowering not empty"

  check "A5 slice `s[a..b]` Canon: irCall(\"[]\"), idx boUnsupported, empty lowering":
    var params = initHashSet[string]()
    params.incl "s"
    params.incl "a"
    params.incl "b"
    let ir = canonIr("""
func pbSliceInclCanon(s: seq[int], a, b: int): int =
  result = s[a..b]
""", "pbSliceInclCanon")
    require ir.body != nil and ir.body.kind == irCall and
      ir.body.callName == "[]" and ir.body.callArgs.len == 2,
      "slice did not convert to irCall(\"[]\", [seq, idx])"
    require ir.body.callArgs[1].kind == irBinOp and
      ir.body.callArgs[1].binOp == boUnsupported,
      "slice index infix did not convert to boUnsupported"
    require not ir.translationLossFree, "slice must be loss-marked"
    require lowerIRExprToLean(ir.body, params) == "", "slice lowering not empty"

  check "A5 slice `s[a..<b]` Canon: irCall(\"[]\"), idx boUnsupported, empty lowering":
    var params = initHashSet[string]()
    params.incl "s"
    params.incl "a"
    params.incl "b"
    let ir = canonIr("""
func pbSliceExclCanon(s: seq[int], a, b: int): int =
  result = s[a..<b]
""", "pbSliceExclCanon")
    require ir.body != nil and ir.body.kind == irCall and
      ir.body.callName == "[]" and ir.body.callArgs.len == 2,
      "slice did not convert to irCall(\"[]\", [seq, idx])"
    require ir.body.callArgs[1].kind == irBinOp and
      ir.body.callArgs[1].binOp == boUnsupported,
      "slice index infix did not convert to boUnsupported"
    require not ir.translationLossFree, "slice must be loss-marked"
    require lowerIRExprToLean(ir.body, params) == "", "slice lowering not empty"

  check "A6 range-for NimNode IR: irLoop (boLt/boLe) has no Lean denotation":
    # The NimNode rows above assert the actual conversion emits an irLoop
    # with boLt (..<) / boLe (..) loss-free. The canonical renderer has no
    # irLoop arm, so the same node kind lowers to "" for both conditions.
    var params = initHashSet[string]()
    params.incl "n"
    let exclLoop = irLoop(lkFor, @["i"], @[irLit(0)],
      irBinOp(boLt, irVar("i", irTypeBitVec64()),
              irVar("n", irTypeBitVec64())),
      irBinOp(boAdd, irVar("i", irTypeBitVec64()), irLit(1)), irLit(0))
    let inclLoop = irLoop(lkFor, @["i"], @[irLit(0)],
      irBinOp(boLe, irVar("i", irTypeBitVec64()),
              irVar("n", irTypeBitVec64())),
      irBinOp(boAdd, irVar("i", irTypeBitVec64()), irLit(1)), irLit(0))
    require lowerIRExprToLean(exclLoop, params) == "", "`..<` loop lowering not empty"
    require lowerIRExprToLean(inclLoop, params) == "", "`..` loop lowering not empty"
    let fd = irFuncDef("pbSumExclNimNode", @[("n", irTypeBitVec64())],
                       irTypeBitVec64(), exclLoop)
    require renderLeanForFuncDef(fd) == "", "renderLeanForFuncDef not empty"

  check "A7 range-for Canon: ckForStmt region drop, loop absent, loss recorded":
    let ir = canonIr("""
func pbSumCanon(n: int): int =
  result = 0
  for i in 0 ..< n:
    result = result + i
""", "pbSumCanon")
    require ir.body != nil, "no body produced"
    require not containsIrLoop(ir.body), "Canon path must not translate a loop"
    require not ir.translationLossFree, "translationLossFree must be false"
    require not ir.propositionRegionLossFree,
      "region drop must clear propositionRegionLossFree"

  check "A8 shl / shr: empty lowering/render and replay refusal":
    var params = initHashSet[string]()
    params.incl "a"
    params.incl "b"
    let shlIr = canonIr("""
func pbShlCanon(a, b: int): int =
  result = a shl b
""", "pbShlCanon")
    require shlIr.body != nil and shlIr.body.kind == irBinOp and
      shlIr.body.binOp == boShl, "shl did not convert to boShl"
    require not shlIr.translationLossFree, "shl must be loss-marked"
    require lowerIRExprToLean(shlIr.body, params) == "", "shl lowering not empty"
    require renderLeanForFuncDef(shlIr) == "", "shl render not empty"
    let shrIr = canonIr("""
func pbShrCanon(a, b: int): int =
  result = a shr b
""", "pbShrCanon")
    require shrIr.body != nil and shrIr.body.kind == irBinOp and
      shrIr.body.binOp == boShr, "shr did not convert to boShr"
    require not shrIr.translationLossFree, "shr must be loss-marked"
    require lowerIRExprToLean(shrIr.body, params) == "", "shr lowering not empty"
    require renderLeanForFuncDef(shrIr) == "", "shr render not empty"
    require evalConcreteBinOp(boShl, ConcreteValue(kind: ckInt, i: 1),
      ConcreteValue(kind: ckInt, i: 2)).isNone,
      "replay must refuse boShl (no ConcreteValue)"
    require evalConcreteBinOp(boShr, ConcreteValue(kind: ckInt, i: 4),
      ConcreteValue(kind: ckInt, i: 2)).isNone,
      "replay must refuse boShr (no ConcreteValue)"

  check "A9 other infix (xor): empty lowering, replay refusal":
    var params = initHashSet[string]()
    params.incl "a"
    params.incl "b"
    let ir = canonIr("""
func pbXorCanon(a, b: int): int =
  result = a xor b
""", "pbXorCanon")
    require ir.body != nil and ir.body.kind == irBinOp and
      ir.body.binOp == boUnsupported, "xor did not fall to boUnsupported"
    require not ir.translationLossFree, "xor must be loss-marked"
    require lowerIRExprToLean(ir.body, params) == "", "xor lowering not empty"
    require evalConcreteBinOp(boUnsupported, ConcreteValue(kind: ckInt, i: 1),
      ConcreteValue(kind: ckInt, i: 2)).isNone,
      "replay must refuse boUnsupported (no ConcreteValue)"
  echo ""

  echo "[B] §2 renderer-empty items (IR nodes constructed directly)"

  check "B0 positive control: supported sub-set body lowers non-empty":
    var params = initHashSet[string]()
    params.incl "x"
    let body = irBinOp(boAdd, irVar("x", irTypeBitVec64()), irLit(1))
    require lowerIRExprToLean(body, params) == "(x + 1)",
      "baseline lowering changed: " & lowerIRExprToLean(body, params)

  check "B1 irCall → empty":
    var params = initHashSet[string]()
    params.incl "x"
    require lowerIRExprToLean(
      irCall("f", @[irVar("x", irTypeBitVec64())]), params) == "",
      "irCall must have no denotation"

  check "B2 irLet → empty":
    var params = initHashSet[string]()
    params.incl "x"
    require lowerIRExprToLean(
      irLet("y", irVar("x", irTypeBitVec64()),
            irVar("x", irTypeBitVec64())), params) == "",
      "irLet must have no denotation"

  check "B3 irLoop → empty":
    var params = initHashSet[string]()
    params.incl "n"
    let body = irLoop(lkFor, @["i"], @[irLit(0)],
      irBinOp(boLt, irVar("i", irTypeBitVec64()),
              irVar("n", irTypeBitVec64())), nil, irLit(0))
    require lowerIRExprToLean(body, params) == "",
      "irLoop must have no denotation"

  check "B4 irRecCall → empty":
    var params = initHashSet[string]()
    params.incl "x"
    require lowerIRExprToLean(irRecCall(@[irVar("x", irTypeBitVec64())]),
      params) == "", "irRecCall must have no denotation"

  check "B5 irCase → empty":
    var params = initHashSet[string]()
    params.incl "x"
    let body = irCase(irVar("x", irTypeBitVec64()),
      @[CaseBranch(pattern: 0, body: irLit(1))], irLit(0))
    require lowerIRExprToLean(body, params) == "",
      "irCase must have no denotation"

  check "B6 irCast → empty":
    var params = initHashSet[string]()
    params.incl "x"
    let body = irCast(irVar("x", irTypeBitVec64()), irTypeBool())
    require body.kind == irCast, "test setup did not build an irCast"
    require lowerIRExprToLean(body, params) == "",
      "irCast must have no denotation"

  check "B7 irStringLit → empty":
    var params = initHashSet[string]()
    params.incl "x"
    let body = IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: "s")
    require lowerIRExprToLean(body, params) == "",
      "irStringLit must have no denotation"

  check "B8 non-parameter irVar → empty":
    var params = initHashSet[string]()
    params.incl "x"
    require lowerIRExprToLean(irVar("y", irTypeBitVec64()), params) == "",
      "non-parameter irVar must have no denotation"
    # And the same name IS rendered when it is a parameter (renderer live).
    require lowerIRExprToLean(irVar("x", irTypeBitVec64()), params) == "x",
      "parameter irVar must render as its name"

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()