## Unit tests for axiom_ir.nim — serialization/deserialization round-trips and type validation.
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[strutils, tables]
import core/trusted/axiom_ir_helpers
import infrastructure/ir_binary_codec

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

  echo "=== Axiom IR — serializeIRType / parseIRType Round-trips ==="

  # BV64 round-trip
  let bv64 = irTypeBitVec64()
  let s = serializeIRType(bv64)
  check "BV64 round-trip": assert s == "BV64"
  var pos = 0
  let back = parseIRType(s, pos)
  check "BV64 parsed kind": assert back.kind == irtBitVec64

  # BOOL round-trip
  let t2 = irTypeBool()
  let s2 = serializeIRType(t2)
  check "BOOL round-trip": assert s2 == "BOOL"
  pos = 0
  let back2 = parseIRType(s2, pos)
  check "BOOL parsed kind": assert back2.kind == irtBool

  # LIST(BV64) round-trip
  let t3 = irTypeList(irTypeBitVec64())
  let s3 = serializeIRType(t3)
  check "LIST(BV64) contains markers": assert "LIST(" in s3 and "BV64)" in s3
  pos = 0
  let back3 = parseIRType(s3, pos)
  check "LIST parsed kind": assert back3.kind == irtList
  check "LIST elemType": assert back3.elemType.kind == irtBitVec64

  # LIST(BOOL) round-trip
  let t4 = irTypeList(irTypeBool())
  let s4 = serializeIRType(t4)
  check "LIST(BOOL) contains markers": assert "LIST(BOOL)" in s4
  pos = 0
  let back4 = parseIRType(s4, pos)
  check "LIST(BOOL) parsed kind": assert back4.kind == irtList
  check "LIST(BOOL) elemType": assert back4.elemType.kind == irtBool

  # STR round-trip
  let t5 = irTypeString()
  let s5 = serializeIRType(t5)
  check "STR round-trip": assert s5 == "STR"
  pos = 0
  let back5 = parseIRType(s5, pos)
  check "STR parsed kind": assert back5.kind == irtString

  # ENUM round-trip
  let t6 = irTypeEnum("Color", @["Red", "Green", "Blue"], @[0'i64, 1'i64, 2'i64])
  let s6 = serializeIRType(t6)
  check "ENUM contains markers": assert "ENUM(Color," in s6 and "Red,Green,Blue" in s6
  pos = 0
  let back6 = parseIRType(s6, pos)
  check "ENUM parsed kind": assert back6.kind == irtEnum
  check "ENUM name": assert back6.enumName == "Color"
  check "ENUM values count": assert back6.enumValues.len == 3

  # VARIANT round-trip
  let payload = irTypeBitVec64()
  let t7 = irTypeVariant("Status", @["Ok", "Err"], @[0'i64, 1'i64], @[payload])
  let s7 = serializeIRType(t7)
  check "VARIANT contains markers": assert "VARIANT(Status," in s7
  pos = 0
  let back7 = parseIRType(s7, pos)
  check "VARIANT parsed kind": assert back7.kind == irtVariant
  check "VARIANT tags count": assert back7.variantTags.len == 2

  echo ""
  echo "=== Axiom IR — serializeIRExpr / parseIRExpr Round-trips ==="

  # irLit round-trip
  let e1 = irLit(42)
  let s1 = serializeIRExpr(e1)
  check "irLit serializes": assert s1 == "L(42)"
  pos = 0
  let back1 = parseIRExpr(s1, pos)
  check "irLit round-trip": assert back1 != nil and back1.kind == irLit and back1.litVal == 42

  # irLit negative round-trip
  let e_neg = irLit(-100)
  let s_neg = serializeIRExpr(e_neg)
  check "irLit negative contains sign": assert "L(-100)" in s_neg
  pos = 0
  let back_neg = parseIRExpr(s_neg, pos)
  check "irLit negative round-trip": assert back_neg != nil and back_neg.litVal == -100

  # irLitU64 — the u64-domain two-part form (v1.2): [2^63, 2^64−1] travels
  # ONLY in the LU(...) representation; never a signed reinterpretation.
  block:
    let e_u63 = irLitU64(9223372036854775808'u64)  # 2^63 exactly
    let s_u63 = serializeIRExpr(e_u63)
    check "irLitU64 2^63 serializes LU":
      assert s_u63 == "LU(9223372036854775808)"
    var p = 0
    let back_u63 = parseIRExpr(s_u63, p)
    check "irLitU64 2^63 round-trip":
      assert back_u63 != nil and back_u63.kind == irLit and
        back_u63.litU64 == 9223372036854775808'u64 and back_u63.litVal == 0

    let e_u64max = irLitU64(18446744073709551615'u64)  # 2^64−1
    let s_u64max = serializeIRExpr(e_u64max)
    check "irLitU64 2^64-1 serializes LU":
      assert s_u64max == "LU(18446744073709551615)"
    p = 0
    let back_u64max = parseIRExpr(s_u64max, p)
    check "irLitU64 2^64-1 round-trip":
      assert back_u64max != nil and back_u64max.kind == irLit and
        back_u64max.litU64 == 18446744073709551615'u64 and
        back_u64max.litVal == 0

    # the signed form is never produced for a u64-domain value, and the
    # signed domain keeps litU64 == 0 (disjoint two-part invariant)
    let e_m1 = irLit(-1)
    let s_m1 = serializeIRExpr(e_m1)
    check "irLit -1 stays in the signed form": assert s_m1 == "L(-1)"
    p = 0
    let back_m1 = parseIRExpr(s_m1, p)
    check "irLit -1 round-trip keeps litU64 == 0":
      assert back_m1 != nil and back_m1.litVal == -1 and
        back_m1.litU64 == 0'u64

    # binary wire: 0x0F tag carries the u64 domain byte-exactly (and
    # nothing below 2^63 ever travels under it)
    let bin_u64max = serializeIRExprAligned(e_u64max)
    let binBack = deserializeIRExprAligned(bin_u64max)
    check "irLitU64 binary wire round-trip":
      assert binBack != nil and binBack.kind == irLit and
        binBack.litU64 == 18446744073709551615'u64 and
        binBack.litVal == 0

    # domain rejects (fail-closed, never a silent reinterpretation):
    # text LU form — ≥ 2^64 overflows the accumulator guard, < 2^63 is a
    # signed-domain value; binary — a 0x0F payload below 2^63 is a domain
    # violation.
    var pRej1 = 0
    check "LU 2^64 rejected":
      assert parseIRExpr("LU(18446744073709551616)", pRej1) == nil
    var pRej2 = 0
    check "LU below 2^63 rejected":
      assert parseIRExpr("LU(9223372036854775807)", pRej2) == nil
    var badBin: seq[byte] = @[]
    badBin.add(0x0F)
    for _ in 1 ..< 8: badBin.add(0)
    badBin.add(5)
    for _ in 1 ..< 8: badBin.add(0)
    check "binary 0x0F sub-2^63 payload rejected":
      assert deserializeIRExprAligned(badBin) == nil

  # irVar round-trip
  let ev = irVar("x", irTypeBitVec64())
  let sv = serializeIRExpr(ev)
  check "irVar serializes": assert "V(x:BV64)" in sv
  pos = 0
  let backv = parseIRExpr(sv, pos)
  check "irVar round-trip": assert backv != nil and backv.kind == irVar and backv.varName == "x"

  # irLet round-trip
  let el = irLet("tmp", irLit(42), irVar("x", irTypeBitVec64()))
  let sl = serializeIRExpr(el)
  check "irLet serializes": assert "LET(tmp=" in sl
  pos = 0
  let backl = parseIRExpr(sl, pos)
  check "irLet round-trip": assert backl != nil and backl.kind == irLet and backl.letName == "tmp"

  # irIf round-trip
  let cond = irEq(irVar("x", irTypeBitVec64()), irLit(0))
  let ei = irIf(cond, irLit(1), irLit(2))
  let si = serializeIRExpr(ei)
  check "irIf serializes": assert "IF(" in si
  pos = 0
  let backi = parseIRExpr(si, pos)
  check "irIf round-trip": assert backi != nil and backi.kind == irIf

  # irCase round-trip
  let scrutinee = irVar("n", irTypeBitVec64())
  let branches = @[CaseBranch(pattern: 0, body: irLit(0)), CaseBranch(pattern: 1, body: irLit(1))]
  let ec = irCase(scrutinee, branches, irLit(-1))
  let sc = serializeIRExpr(ec)
  check "irCase serializes": assert "CASE(" in sc and "{0=>" in sc and "|D=>" in sc
  pos = 0
  let backc = parseIRExpr(sc, pos)
  check "irCase round-trip": assert backc != nil and backc.kind == irCase and backc.caseBranches.len == 2

  # irCall round-trip
  let ecall = irCall("foo", @[irLit(1), irLit(2)])
  let scal = serializeIRExpr(ecall)
  check "irCall serializes": assert "CALL(foo," in scal and "L(1)" in scal and "L(2)" in scal
  pos = 0
  let backcall = parseIRExpr(scal, pos)
  check "irCall round-trip": assert backcall != nil and backcall.kind == irCall and backcall.callName == "foo" and backcall.callArgs.len == 2

  # irBinOp round-trip
  let ebo = irBinOp(boAdd, irLit(1), irLit(2))
  let sbo = serializeIRExpr(ebo)
  check "irBinOp serializes": assert sbo == "BIN(boAdd,L(1),L(2))"
  pos = 0
  let backbo = parseIRExpr(sbo, pos)
  check "irBinOp round-trip": assert backbo != nil and backbo.kind == irBinOp and backbo.binOp == boAdd

  # irUnaryOp round-trip
  let euo = irUnaryOp(uoNot, irVar("p", irTypeBool()))
  let suo = serializeIRExpr(euo)
  check "irUnaryOp serializes": assert suo == "UN(uoNot,V(p:BOOL))"
  pos = 0
  let backuo = parseIRExpr(suo, pos)
  check "irUnaryOp round-trip": assert backuo != nil and backuo.kind == irUnaryOp and backuo.unaryOp == uoNot

  # irRecCall round-trip
  let erc = irRecCall(@[irLit(42)])
  let src = serializeIRExpr(erc)
  check "irRecCall serializes": assert "REC(" in src and "L(42)" in src
  pos = 0
  let backrc = parseIRExpr(src, pos)
  check "irRecCall round-trip": assert backrc != nil and backrc.kind == irRecCall

  # irLoop round-trip
  let loopVar = irVar("i", irTypeBitVec64())
  let endVal = irLit(10)
  let lcond = irBinOp(boLt, loopVar, endVal)
  let lbody = irLit(0)
  let lstep = irBinOp(boAdd, loopVar, irLit(1))
  let eloop = irLoop(lkFor, @["i"], @[endVal], lcond, lstep, lbody)
  let sloop = serializeIRExpr(eloop)
  check "irLoop serializes": assert "LOOP(lkFor," in sloop
  pos = 0
  let backloop = parseIRExpr(sloop, pos)
  check "irLoop round-trip": assert backloop != nil and backloop.kind == irLoop and backloop.loopKind == lkFor

  # irFloatLit round-trip
  let efl = IRExpr(typ: irTypeBitVec64(), kind: irFloatLit, floatVal: 3.14)
  let sfl = serializeIRExpr(efl)
  check "irFloatLit serializes": assert "FL(" in sfl
  pos = 0
  let backfl = parseIRExpr(sfl, pos)
  check "irFloatLit round-trip": assert backfl != nil and backfl.kind == irFloatLit

  # irStringLit round-trip
  let esl = IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: "hello")
  let ssl = serializeIRExpr(esl)
  check "irStringLit serializes": assert ssl == "SLIT(hello)"
  pos = 0
  let backsl = parseIRExpr(ssl, pos)
  check "irStringLit round-trip": assert backsl != nil and backsl.kind == irStringLit and backsl.stringVal == "hello"

  # irCast serialization (parseIRExpr does not support CAST — skip round-trip)
  let ecast = IRExpr(typ: irTypeBool(), kind: irCast, castExpr: irVar("x", irTypeBitVec64()), castFrom: irTypeBitVec64(), castTo: irTypeBool())
  let scat = serializeIRExpr(ecast)
  check "irCast serializes": assert "CAST(" in scat and "->" in scat

  echo ""
  echo "=== Axiom IR — IRFuncDef Round-trip ==="

  # simple funcDef serialize/deserialize
  let f1 = irFuncDef(
    name = "add", params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
    ret = irTypeBitVec64(), body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
  )
  let sf1 = serializeIRFuncDef(f1)
  check "funcDef serializes": assert "FUNC(add(" in sf1 and ":BV64=" in sf1
  let bf1 = deserializeIRFuncDef(sf1)
  check "funcDef round-trip name": assert bf1.name == "add"
  check "funcDef round-trip params": assert bf1.params.len == 2
  check "funcDef round-trip retType": assert bf1.retType.kind == irtBitVec64
  check "funcDef round-trip isRecursive": assert bf1.isRecursive == false

  # funcDef with recursion flag
  let f2 = irFuncDef(
    name = "fact", params = @[("n", irTypeBitVec64())],
    ret = irTypeBitVec64(), body = irLit(1), isRec = true
  )
  let sf2 = serializeIRFuncDef(f2)
  check "funcDef with rec serializes": assert ",rec=true" in sf2
  let bf2 = deserializeIRFuncDef(sf2)
  check "funcDef rec round-trip": assert bf2.isRecursive == true

  # funcDef with preconditions
  let precond = irGt(irVar("x", irTypeBitVec64()), irLit(0))
  let f3 = IRFuncDef(
    name: "safe_div",
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64()), IRFuncParam(name: "y", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: irDiv(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64())),
    isRecursive: false, preConditions: @[precond], postConditions: @[]
  )
  let sf3 = serializeIRFuncDef(f3)
  check "funcDef with preconds serializes": assert "preconds=" in sf3
  let bf3 = deserializeIRFuncDef(sf3)
  check "funcDef preconds round-trip": assert bf3.preConditions.len == 1

  # funcDef with postconditions
  let postcond = irLe(irVar("result", irTypeBitVec64()), irLit(1000))
  let f4 = IRFuncDef(
    name: "bounded", params: @[], retType: irTypeBitVec64(),
    body: irLit(500), isRecursive: false, preConditions: @[], postConditions: @[postcond]
  )
  let sf4 = serializeIRFuncDef(f4)
  check "funcDef with postconds serializes": assert "postconds=" in sf4
  let bf4 = deserializeIRFuncDef(sf4)
  check "funcDef postconds round-trip": assert bf4.postConditions.len == 1

  # deserialize invalid input
  let bInvalid = deserializeIRFuncDef("not_a_func_def")
  check "deserialize invalid returns empty": assert bInvalid.name == ""

  # serializeParams format
  let sp = serializeParams(@[
    IRFuncParam(name: "x", ty: irTypeBitVec64()),
    IRFuncParam(name: "y", ty: irTypeBool())
  ])
  check "serializeParams starts with [": assert sp.startsWith("[")
  check "serializeParams contains x:BV64": assert "x:BV64" in sp
  check "serializeParams contains y:BOOL": assert "y:BOOL" in sp
  check "serializeParams ends with ]": assert sp.endsWith("]")

  echo ""
  echo "=== Axiom IR — Canonicalization & Digest ==="

  # commutative ops produce same digest
  let digestT = irTypeBitVec64()
  let aPlusB = irFuncDef(name = "add", params = @[("a", bv64), ("b", bv64)], ret = bv64, body = irAdd(irVar("a", bv64), irVar("b", bv64)))
  let bPlusA = irFuncDef(name = "add", params = @[("a", bv64), ("b", bv64)], ret = bv64, body = irAdd(irVar("b", bv64), irVar("a", bv64)))
  let d1 = computeIrDigest(aPlusB)
  let d2 = computeIrDigest(bPlusA)
  check "a+b and b+a same digest": assert d1 == d2

  # digest determinism
  let fStable = irFuncDef(name = "stable", params = @[], ret = irTypeBitVec64(), body = irMul(irVar("x", bv64), irVar("y", bv64)))
  let ds1 = computeIrDigest(fStable)
  let ds2 = computeIrDigest(fStable)
  check "digest deterministic": assert ds1 == ds2 and ds1.len > 0

  # alpha-renaming produces same digest
  let fAlpha1 = irFuncDef(name = "f", params = @[], ret = bv64,
    body = irLet("alpha", irLit(1), irLet("beta", irLit(2), irAdd(irVar("alpha", bv64), irVar("beta", bv64)))))
  let fAlpha2 = irFuncDef(name = "f", params = @[], ret = bv64,
    body = irLet("gamma", irLit(1), irLet("delta", irLit(2), irAdd(irVar("gamma", bv64), irVar("delta", bv64)))))
  let da1 = computeIrDigest(fAlpha1)
  let da2 = computeIrDigest(fAlpha2)
  check "alpha-renamed locals same digest": assert da1 == da2

  echo ""
  echo "=== Axiom IR — Type Validation ==="

  # validateExprTypes valid expr
  let ve1 = irAdd(irVar("x", bv64), irVar("y", bv64))
  check "validateExprTypes valid": assert validateExprTypes(ve1) == true

  # validateExprTypes nil
  check "validateExprTypes nil": assert validateExprTypes(nil) == true

  # validateExprTypes missing typ
  var veNil = IRExpr(kind: irVar, varName: "x", varType: irTypeBitVec64())
  veNil.typ = nil
  check "validateExprTypes missing typ": assert validateExprTypes(veNil) == false

  # validateIrTypes valid function
  let vi1 = irFuncDef(name = "add", params = @[("a", bv64), ("b", bv64)], ret = bv64, body = irAdd(irVar("a", bv64), irVar("b", bv64)))
  check "validateIrTypes valid": assert validateIrTypes(vi1) == true

  # validateIrTypes missing param type
  var viBad = irFuncDef(name = "bad", params = @[("a", bv64)], ret = bv64, body = irLit(0))
  viBad.params[0].ty = nil
  check "validateIrTypes missing param type": assert validateIrTypes(viBad) == false

  # validateIrTypes missing ret type
  var viRetNil = irFuncDef(name = "bad", params = @[], ret = nil, body = irLit(0))
  check "validateIrTypes missing ret type": assert validateIrTypes(viRetNil) == false

  echo ""
  echo "=== Axiom IR — BMC Skippable Detection ==="

  # String return type
  let fStr = irFuncDef(name = "get_str", params = @[], ret = irTypeString(),
    body = IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: "hello"))
  check "String return bmc-skippable": assert isBmcSkippable(fStr) == true

  # String param
  let fStrP = irFuncDef(name = "process", params = @[("s", irTypeString())], ret = irTypeBitVec64(), body = irLit(0))
  check "String param bmc-skippable": assert isBmcSkippable(fStrP) == true

  # Float lit
  let fFloat = irFuncDef(name = "with_float", params = @[], ret = irTypeBitVec64(),
    body = IRExpr(typ: irTypeBitVec64(), kind: irFloatLit, floatVal: 3.14))
  check "Float lit bmc-skippable": assert isBmcSkippable(fFloat) == true

  # Pure int not skippable
  let fInt = irFuncDef(name = "add", params = @[("a", bv64), ("b", bv64)], ret = bv64, body = irAdd(irVar("a", bv64), irVar("b", bv64)))
  check "Pure int not bmc-skippable": assert isBmcSkippable(fInt) == false

  echo ""
  echo "=== Axiom IR — Builtin Registry ==="

  let builtins = irBuiltins()
  check "isIrBuiltin opCastToBool": assert isIrBuiltin("opCastToBool") == true
  check "isIrBuiltin min/max": assert isIrBuiltin("min") == true and isIrBuiltin("max") == true
  check "isIrBuiltin unknown": assert isIrBuiltin("unknown_fn") == false

  check "builtins arity opCastToBool": assert builtins.getOrDefault("opCastToBool").arity == 1
  check "builtins arity min": assert builtins.getOrDefault("min").arity == 2
  check "builtins arity max": assert builtins.getOrDefault("max").arity == 2

  check "builtins retType opCastToBool": assert builtins.getOrDefault("opCastToBool").retType.kind == irtBool
  check "builtins retType min": assert builtins.getOrDefault("min").retType.kind == irtBitVec64

  echo ""
  echo "=== Axiom IR — Type Constructors ==="

  check "irTypeFromKind BitVec64": assert irTypeFromKind(irtBitVec64).kind == irtBitVec64
  check "irTypeFromKind Bool": assert irTypeFromKind(irtBool).kind == irtBool
  let ftl = irTypeFromKind(irtList)
  check "irTypeFromKind List": assert ftl.kind == irtList and ftl.elemType.kind == irtBitVec64

  check "computeTagBitWidth 0xFF": assert computeTagBitWidth(0xFF'i64) == 8
  check "computeTagBitWidth 0xFFFF": assert computeTagBitWidth(0xFFFF'i64) == 16
  check "computeTagBitWidth 0xFFFFFFFF": assert computeTagBitWidth(0xFFFFFFFF'i64) == 32
  check "computeTagBitWidth 0xFFFFFFFFFFFFFFFF": assert computeTagBitWidth(0x7FFFFFFFFFFFFFFF'i64) == 64
  check "computeTagBitWidth zero": assert computeTagBitWidth(0'i64) == 8

  echo ""
  echo "=== Axiom IR — Serialization Helpers ==="

  check "serializeIRExpr nil": assert serializeIRExpr(nil) == "NIL"
  check "serializeExprSeq empty": assert serializeExprSeq(@[]) == "[]"
  check "serializeExprSeq single": assert serializeExprSeq(@[irLit(1)]) == "[L(1)]"
  check "serializeExprSeq multiple": assert serializeExprSeq(@[irLit(1), irLit(2)]) == "[L(1),L(2)]"

  echo ""
  echo "=== Axiom IR — recomputeTyp ==="

  # recomputeTyp on bare irLit sets typ
  var rtl = IRExpr(kind: irLit, litVal: 42)
  rtl.typ = nil
  recomputeTyp(rtl)
  check "recomputeTyp irLit sets typ": assert rtl.typ != nil and rtl.typ.kind == irtBitVec64

  # recomputeTyp on irBinOp propagates types
  var rlhs = IRExpr(kind: irVar, varName: "x", varType: irTypeBitVec64())
  rlhs.typ = nil
  var rrhs = IRExpr(kind: irVar, varName: "y", varType: irTypeBitVec64())
  rrhs.typ = nil
  var re = IRExpr(kind: irBinOp, binOp: boAdd, binLhs: rlhs, binRhs: rrhs)
  re.typ = nil
  recomputeTyp(re)
  check "recomputeTyp irBinOp propagates": assert re.typ != nil

  # recomputeTyp on irIf uses then-branch type
  var rcond = IRExpr(kind: irVar, varName: "c", varType: irTypeBool())
  rcond.typ = irTypeBool()
  var rthenE = IRExpr(kind: irVar, varName: "x", varType: irTypeBitVec64())
  rthenE.typ = irTypeBitVec64()
  var relseE = IRExpr(kind: irVar, varName: "y", varType: irTypeBitVec64())
  relseE.typ = irTypeBitVec64()
  var rie = IRExpr(kind: irIf, ifCond: rcond, ifThen: rthenE, ifElse: relseE)
  rie.typ = nil
  recomputeTyp(rie)
  check "recomputeTyp irIf uses then-type": assert rie.typ != nil and rie.typ.kind == irtBitVec64

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
