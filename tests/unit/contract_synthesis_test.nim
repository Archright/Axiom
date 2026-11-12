## Unit tests for contract_synthesis.nim — auto-generate preconditions from IR analysis.

import std/unittest
import core/trusted/contract_synthesis
import core/trusted/axiom_ir_helpers

suite "Contract Synthesis — collectDivisionGuards":
  test "simple division generates guard":
    let body = irDiv(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let guards = collectDivisionGuards(body)
    check guards.len == 1
    # Guard should be ¬(y == 0)
    check $guards[0].kind == $irUnaryOp

  test "modulo generates guard":
    let body = irRem(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    let guards = collectDivisionGuards(body)
    check guards.len == 1
    check $guards[0].kind == $irUnaryOp

  test "nested division in addition":
    let divExpr = irDiv(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let body = irAdd(divExpr, irLit(1))
    let guards = collectDivisionGuards(body)
    check guards.len == 1

  test "two divisions generate two guards":
    let d1 = irDiv(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    let d2 = irDiv(irVar("c", irTypeBitVec64()), irVar("d", irTypeBitVec64()))
    let body = irAdd(d1, d2)
    let guards = collectDivisionGuards(body)
    check guards.len == 2

  test "no division produces empty guards":
    let body = irAdd(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let guards = collectDivisionGuards(body)
    check guards.len == 0

  test "division inside let binding":
    let body = irLet("tmp", irDiv(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64())), irLit(0))
    let guards = collectDivisionGuards(body)
    check guards.len == 1

  test "division inside if-then-else":
    let cond = irEq(irVar("flag", irTypeBool()), irLit(1))
    let thenBody = irDiv(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let elseBody = irLit(0)
    let body = irIf(cond, thenBody, elseBody)
    let guards = collectDivisionGuards(body)
    check guards.len == 1

  test "division inside recursive call args":
    let recCall = irRecCall(@[irDiv(irVar("n", irTypeBitVec64()), irVar("k", irTypeBitVec64()))])
    let body = irLit(0)
    let guards = collectDivisionGuards(recCall)
    check guards.len == 1

suite "Contract Synthesis — collectIndexGuards":
  test "array index [] generates bounds guard":
    let seqExpr = irVar("arr", irTypeList(irTypeBitVec64()))
    let idxExpr = irVar("i", irTypeBitVec64())
    let body = irCall("[]", @[seqExpr, idxExpr])
    let guards = collectIndexGuards(body)
    check guards.len == 1
    # Guard should be a conjunction: 0 <= i && i < len(arr)
    check $guards[0].kind == $irBinOp  # outer is boAnd

  test "charAt generates bounds guard":
    let strExpr = irVar("s", irTypeString())
    let idxExpr = irVar("i", irTypeBitVec64())
    let body = irCall("charAt", @[strExpr, idxExpr])
    let guards = collectIndexGuards(body)
    check guards.len == 1
    check $guards[0].kind == $irBinOp  # outer is boAnd

  test "substr generates bounds guard":
    let sExpr = irVar("s", irTypeString())
    let startExpr = irVar("start", irTypeBitVec64())
    let lenArg = irVar("len", irTypeBitVec64())
    let body = irCall("substr", @[sExpr, startExpr, lenArg])
    let guards = collectIndexGuards(body)
    check guards.len == 1
    check $guards[0].kind == $irBinOp  # outer is boAnd

  test "multiple index operations produce multiple guards":
    let arr = irVar("arr", irTypeList(irTypeBitVec64()))
    let i = irVar("i", irTypeBitVec64())
    let j = irVar("j", irTypeBitVec64())
    let g1 = irCall("[]", @[arr, i])
    let g2 = irCall("[]", @[arr, j])
    let body = irAdd(g1, g2)
    let guards = collectIndexGuards(body)
    check guards.len == 2

  test "no index operation produces empty guards":
    let body = irAdd(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let guards = collectIndexGuards(body)
    check guards.len == 0

  test "index inside nested call":
    let arr = irVar("arr", irTypeList(irTypeBitVec64()))
    let idx = irVar("i", irTypeBitVec64())
    let inner = irCall("[]", @[arr, idx])
    let body = irCall("foo", @[inner])
    let guards = collectIndexGuards(body)
    check guards.len == 1

  test "index with complex expression":
    let arr = irVar("arr", irTypeList(irTypeBitVec64()))
    let idx = irAdd(irVar("base", irTypeBitVec64()), irVar("offset", irTypeBitVec64()))
    let body = irCall("[]", @[arr, idx])
    let guards = collectIndexGuards(body)
    check guards.len == 1

suite "Contract Synthesis — collectPostconditions":
  test "enum return type generates postcondition":
    let enumType = irTypeEnum("Color", @["Red", "Green", "Blue"], @[0'i64, 1'i64, 2'i64])
    let funcDef = irFuncDef(
      name = "get_color",
      params = @[],
      ret = enumType,
      body = irLit(0)
    )
    let posts = collectPostconditions(funcDef)
    check posts.len == 1
    # Postcondition: result <= max_ordinal (2)
    check $posts[0].kind == $irBinOp

  test "plain BitVec64 return has no postcondition":
    let funcDef = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let posts = collectPostconditions(funcDef)
    check posts.len == 0

  test "Bool return has no postcondition":
    let funcDef = irFuncDef(
      name = "is_positive",
      params = @[("x", irTypeBitVec64())],
      ret = irTypeBool(),
      body = irGt(irVar("x", irTypeBitVec64()), irLit(0))
    )
    let posts = collectPostconditions(funcDef)
    check posts.len == 0

  test "String return has no postcondition":
    let body = IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: "test")
    let funcDef = irFuncDef(
      name = "get_name",
      params = @[],
      ret = irTypeString(),
      body = body
    )
    let posts = collectPostconditions(funcDef)
    check posts.len == 0

  test "List return has no postcondition":
    let funcDef = irFuncDef(
      name = "empty_list",
      params = @[],
      ret = irTypeList(irTypeBitVec64()),
      body = irLit(0)
    )
    let posts = collectPostconditions(funcDef)
    check posts.len == 0

suite "Contract Synthesis — collectAssertGuards":
  test "doAssert extracts condition":
    let cond = irGt(irVar("x", irTypeBitVec64()), irLit(0))
    let body = irCall("doAssert", @[cond])
    let guards = collectAssertGuards(body)
    check guards.len == 1
    check $guards[0] == $cond

  test "assert extracts condition":
    let cond = irLe(irVar("i", irTypeBitVec64()), irVar("n", irTypeBitVec64()))
    let body = irCall("assert", @[cond])
    let guards = collectAssertGuards(body)
    check guards.len == 1
    check $guards[0] == $cond

  test "assert without args ignored":
    let body = irCall("doAssert", @[])
    let guards = collectAssertGuards(body)
    check guards.len == 0

  test "nested assert in let":
    let cond = irEq(irVar("x", irTypeBitVec64()), irLit(0))
    let body = irLet("result", irCall("doAssert", @[cond]), irLit(0))
    let guards = collectAssertGuards(body)
    check guards.len == 1

  test "multiple asserts produce multiple guards":
    let c1 = irGt(irVar("a", irTypeBitVec64()), irLit(0))
    let c2 = irLt(irVar("b", irTypeBitVec64()), irLit(100))
    let body = irLet("_", irCall("doAssert", @[c1]), irCall("assert", @[c2]))
    let guards = collectAssertGuards(body)
    check guards.len == 2

  test "assert in if-then branch":
    let cond = irEq(irVar("flag", irTypeBool()), irLit(1))
    let assertCond = irBinOp(boEq, irVar("x", irTypeBitVec64()), irLit(0))
    let body = irIf(cond, irCall("doAssert", @[assertCond]), irLit(0))
    let guards = collectAssertGuards(body)
    check guards.len == 1

suite "Contract Synthesis — synthesizeContracts":
  test "synthesizes all contract types at once":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    var funcDef = irFuncDef(
      name = "safe_div_add",
      params = @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irDiv(x, y), irLit(1)),
      isRec = false
    )
    synthesizeContracts(funcDef)
    check funcDef.preConditions.len > 0
    # Should have division guard
    var foundDivGuard = false
    for g in funcDef.preConditions:
      if $g.kind == $irUnaryOp:
        foundDivGuard = true
    check foundDivGuard

  test "synthesizes index guards from array access":
    let arr = irVar("arr", irTypeList(irTypeBitVec64()))
    let idx = irVar("i", irTypeBitVec64())
    var funcDef = irFuncDef(
      name = "get_elem",
      params = @[("arr", irTypeList(irTypeBitVec64())), ("i", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irCall("[]", @[arr, idx]),
      isRec = false
    )
    synthesizeContracts(funcDef)
    check funcDef.preConditions.len > 0
    # Should have index guard (conjunction of bounds checks)
    var foundIndexGuard = false
    for g in funcDef.preConditions:
      if $g.kind == $irBinOp:
        foundIndexGuard = true
    check foundIndexGuard

  test "postconditions synthesized for enum return":
    let enumType = irTypeEnum("Status", @["Ok", "Err"], @[0'i64, 1'i64])
    var funcDef = irFuncDef(
      name = "get_status",
      params = @[],
      ret = enumType,
      body = irLit(0),
      isRec = false
    )
    synthesizeContracts(funcDef)
    check funcDef.postConditions.len > 0

  test "existing postconditions not overwritten":
    let existingPost = irGt(irVar("result", irTypeBitVec64()), irLit(-100))
    var funcDef = IRFuncDef(
      name: "bounded",
      params: @[],
      retType: irTypeBitVec64(),
      body: irLit(0),
      isRecursive: false,
      preConditions: @[],
      postConditions: @[existingPost]
    )
    synthesizeContracts(funcDef)
    # Should keep the original postcondition, not add enum postcondition
    var foundOriginal = false
    for p in funcDef.postConditions:
      if $p == $existingPost:
        foundOriginal = true
    check foundOriginal

  test "complex function with multiple patterns":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let arr = irVar("arr", irTypeList(irTypeBitVec64()))
    let idx = irVar("i", irTypeBitVec64())
    # Body: let elem = arr[i] in elem + (x / y)
    let indexedElem = irCall("[]", @[arr, idx])
    let divResult = irDiv(x, y)
    let body = irLet("elem", indexedElem, irAdd(divResult, irLit(1)))
    var funcDef = irFuncDef(
      name = "complex_fn",
      params = @[("x", irTypeBitVec64()), ("y", irTypeBitVec64()), ("arr", irTypeList(irTypeBitVec64())), ("i", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = body,
      isRec = false
    )
    synthesizeContracts(funcDef)
    check funcDef.preConditions.len >= 2  # at least division + index guards
