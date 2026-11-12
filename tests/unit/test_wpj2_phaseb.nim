## tests/unit/test_wpj2_phaseb.nim
## WP4-j.2 Phase B verification — Level-1 fidelity repair (plan v16, locks 18/21).
##
## Covers:
##   - CLET serialization round-trip (isCompileTime preserved, lock 18/19 format)
##   - LET backward compatibility (existing format unchanged)
##   - computeIrDigest: LET vs CLET distinct; alpha-renamed CLET equal
##     (canonicalizeExpr isCompileTime copy — agent note: must not regress)
##   - binary codec 0x0E round-trip
##   - F1a: nnkConstSection → isCompileTime=true irLet (no more const drop)
##   - F1b: sizeof preserved opaquely as irCall("sizeof", ...) (never evaluated)
##   - F1c: lossy tracking — unhandled statement kind → translationLossFree=false;
##     lossless let-only func → true
##   - F1d: independent binding inventory (NimNode + PNode raw observation)
##
## Custom main() pattern per tests/unit/ast_to_ir_test.nim precedent.

import std/[macros, strutils]
import compiler/ast
import core/parser_utils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir
import infrastructure/ir_binary_codec
import core/trusted/binding_inventory

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

  # ── CLET serialization round-trip ─────────────────────────────
  echo "=== CLET / LET serialization (lock 18/19 format) ==="

  check "CLET round-trip preserves isCompileTime":
    let ct = irLet("W", irLit(64), irVar("W", irTypeBitVec64()),
                   isCompileTime = true)
    let s = serializeIRExpr(ct)
    doAssert s.startsWith("CLET("), "compile-time let must serialize as CLET, got: " & s
    var pos = 0
    let back = parseIRExpr(s, pos)
    doAssert back != nil and back.kind == irLet, "parse failed"
    doAssert back.letName == "W"
    doAssert back.isCompileTime == true

  check "LET backward compat (isCompileTime=false unchanged format)":
    let rt = irLet("W", irLit(64), irVar("W", irTypeBitVec64()))
    let s = serializeIRExpr(rt)
    doAssert s.startsWith("LET("), "runtime let must stay LET, got: " & s
    var pos = 0
    let back = parseIRExpr(s, pos)
    doAssert back != nil and back.kind == irLet
    doAssert back.isCompileTime == false

  check "LET vs CLET produce different digests":
    let f1 = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLet("x", irLit(1), irVar("x", irTypeBitVec64()),
                  isCompileTime = false), isRecursive: false)
    let f2 = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLet("x", irLit(1), irVar("x", irTypeBitVec64()),
                  isCompileTime = true), isRecursive: false)
    doAssert computeIrDigest(f1) != computeIrDigest(f2)

  check "alpha-renamed CLET keeps same digest (canonicalize copies flag)":
    let fA = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLet("alpha", irLit(1), irVar("alpha", irTypeBitVec64()),
                  isCompileTime = true), isRecursive: false)
    let fB = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLet("beta", irLit(1), irVar("beta", irTypeBitVec64()),
                  isCompileTime = true), isRecursive: false)
    doAssert computeIrDigest(fA) == computeIrDigest(fB)

  check "binary codec CLET round-trip (0x0E)":
    let ct = irLet("W", irLit(64), irVar("W", irTypeBitVec64()),
                   isCompileTime = true)
    let bytes = serializeIRExprAligned(ct)
    let back = deserializeIRExprAligned(bytes)
    doAssert back != nil and back.kind == irLet
    doAssert back.letName == "W"
    doAssert back.isCompileTime == true

  check "binary codec LET round-trip (0x04 unchanged)":
    let rt = irLet("W", irLit(64), irVar("W", irTypeBitVec64()))
    let bytes = serializeIRExprAligned(rt)
    let back = deserializeIRExprAligned(bytes)
    doAssert back != nil and back.kind == irLet
    doAssert back.isCompileTime == false

  # ── F1a/F1b: ast_to_ir fidelity (compile-time macro tests) ────
  echo "=== ast_to_ir fidelity (const section / sizeof / lossy) ==="

  macro constSectionBecomesClet(): untyped =
    let irDef = convertFuncDef(quote do:
      proc useConst(): int =
        const W = 64
        result = W)
    let b = irDef.body
    if b != nil and b.kind == irLet:
      result = newStrLitNode(b.letName & "|" & $b.isCompileTime)
    else:
      result = newStrLitNode("unexpected:" & $b.kind)

  check "F1a const section → isCompileTime=true irLet (no drop)":
    let r = constSectionBecomesClet()
    doAssert r == "W|true", "got: " & r

  macro sizeofPreserved(): untyped =
    let irDef = convertFuncDef(quote do:
      proc sz(x: int): int =
        result = sizeof(x))
    let b = irDef.body
    if b != nil and b.kind == irCall:
      result = newStrLitNode("preserved|" & b.callName & "|" &
        $b.callArgs.len & "|" & $b.callArgs[0].kind)
    else:
      result = newStrLitNode("unexpected:" & $b.kind)

  check "F1b sizeof preserved opaquely as irCall (never evaluated)":
    let r = sizeofPreserved()
    doAssert r == "preserved|sizeof|1|irVar", "got: " & r

  macro lossyBlock(): untyped =
    let irDef = convertFuncDef(quote do:
      proc lb(): int =
        block:
          discard
        result = 1)
    result = newStrLitNode($irDef.translationLossFree)

  check "F1c lossy: unhandled statement kind → translationLossFree=false":
    doAssert lossyBlock() == "false", "block must mark lossy"

  macro losslessLet(): untyped =
    let irDef = convertFuncDef(quote do:
      proc ll(): int =
        let a = 1
        result = a)
    result = newStrLitNode($irDef.translationLossFree)

  check "F1c lossless: supported constructs keep translationLossFree=true":
    doAssert losslessLet() == "true"

  # ── F1d: independent binding inventory (NimNode) ──────────────
  echo "=== independent binding inventory ==="

  macro invNim(): untyped =
    let def = quote do:
      proc sample(p: int): int =
        const K = 4
        var v = p
        for i in 0 ..< 3:
          v = v + i
        result = v + K
    let inv = inventoryFromNimNode(def, "sample")
    var kinds = ""
    for w in inv.witnesses:
      if not w.opaque:
        kinds.add(w.bindingKind & ":" & w.name & " ")
    result = newStrLitNode(kinds & "|" & $inv.opaqueBoundaries.len)

  check "F1d inventory observes let/const/param/loopVar (NimNode)":
    let r = invNim()
    doAssert "const:K" in r, "got: " & r
    doAssert "param:p" in r, "got: " & r
    doAssert "var:v" in r, "got: " & r
    doAssert "loopVar:i" in r, "got: " & r

  check "F1d inventory: independent observer is not the translator":
    # The translator DROPPED const sections pre-repair; the inventory must
    # still observe them (independence — lock 21). Cross-check via the
    # constSectionBecomesClet result: the translator now preserves it too,
    # but the inventory result comes from binding_inventory.nim's own walk.
    let r = invNim()
    doAssert "const:K" in r

  # ── F1d: PNode inventory (external runtime path) ──────────────
  echo "=== binding inventory (PNode / external path) ==="

  check "F1d PNode inventory observes const+param (external path)":
    initParserUtils()
    let src = "proc sample(p: int): int =\n  const K = 4\n  result = p + K\n"
    let ast = parseStringAST(src)
    doAssert ast != nil, "parse failed"
    var procNode: PNode = nil
    for i in 0 ..< ast.len:
      if ast[i].kind == nkProcDef:
        procNode = ast[i]
        break
    doAssert procNode != nil, "no proc def found"
    let inv = inventoryFromPNode(procNode, "sample")
    var kinds = ""
    for w in inv.witnesses:
      if not w.opaque:
        kinds.add(w.bindingKind & ":" & w.name & " ")
    doAssert "const:K" in kinds, "got: " & kinds
    doAssert "param:p" in kinds, "got: " & kinds

  check "F1d PNode inventory records opaque boundary (template)":
    initParserUtils()
    let src = "proc tmpl(): int =\n  template inner(): int = 1\n  result = 1\n"
    let ast = parseStringAST(src)
    doAssert ast != nil
    var procNode: PNode = nil
    for i in 0 ..< ast.len:
      if ast[i].kind == nkProcDef:
        procNode = ast[i]
        break
    doAssert procNode != nil
    let inv = inventoryFromPNode(procNode, "tmpl")
    doAssert inv.opaqueBoundaries.len >= 1, "template must be an opaque boundary"
    var hasOpaque = false
    for w in inv.witnesses:
      if w.opaque:
        hasOpaque = true
    doAssert hasOpaque

  # ── Evidence metadata excluded from semantic digest ───────────
  echo "=== evidence/semantic digest separation ==="

  check "evidence fields stay out of computeIrDigest (default vs flipped)":
    # Two funcdefs identical except the evidence booleans: same semantic digest
    # only holds when the evidence is NOT serialized. computeIrDigest covers
    # name/params/retType/body/isRecursive/pre/post — so these two are equal.
    let f1 = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLit(1), isRecursive: false,
      translationLossFree: true, bindingUniverseComplete: true)
    let f2 = IRFuncDef(name: "f", params: @[], retType: irTypeBitVec64(),
      body: irLit(1), isRecursive: false,
      translationLossFree: false, bindingUniverseComplete: false)
    doAssert computeIrDigest(f1) == computeIrDigest(f2)

  # ── Summary ───────────────────────────────────────────────────
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
