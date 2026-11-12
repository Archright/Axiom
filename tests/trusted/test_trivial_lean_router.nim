## tests/trusted/test_trivial_lean_router.nim
## Refinement Typed IR v5 — Type-Level Encoding Tests

import std/[unittest, options, strutils]
import core/types/results
import core/trusted/axiom_ir
import core/trusted/ir_to_lean
import sieve/trivial_lean_router

# ── Helper constructors ──

func makeParam(name: string, ty: IRTypeKind = irtBitVec64): IRFuncParam =
  IRFuncParam(name: name, ty: IRType(kind: ty), constraint: none(IRExpr))

func makeConstrainedParam(name: string, constraint: IRExpr): IRFuncParam =
  IRFuncParam(name: name, ty: IRType(kind: irtBitVec64), constraint: some(constraint))

func makeLit(val: int64): IRExpr =
  IRExpr(kind: irLit, litVal: val)

func makeLitU64(val: uint64): IRExpr =
  IRExpr(kind: irLit, litVal: 0, litU64: val)

func makeVar(name: string): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: IRType(kind: irtBitVec64))

func makeBinOp(op: BinOpKind, lhs, rhs: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: lhs, binRhs: rhs)

func makeFuncDef(name: string, params: seq[IRFuncParam], body: IRExpr,
                 preConditions: seq[IRExpr] = @[],
                 isRecursive: bool = false,
                 retType: IRType = IRType(kind: irtBitVec64)): IRFuncDef =
  IRFuncDef(name: name, params: params,
            retType: retType, body: body,
            isRecursive: isRecursive, preConditions: preConditions)

# ── Test Suite ──

suite "Refinement Typed IR v5":

  # ── Serialization Round-Trip ──

  test "constraint serialization roundtrip":
    let constraint = makeBinOp(boLt,
      makeBinOp(boAdd, makeVar("a"), makeVar("b")),
      makeLitU64(18446744073709551615'u64))  # the REAL width-64 bound 2^64−1 (u64-domain form)
    let param = makeConstrainedParam("a", constraint)
    let f = makeFuncDef("safe_add", @[param, makeParam("b")], makeBinOp(boAdd, makeVar("a"), makeVar("b")))
    let serialized = serializeIRFuncDef(f)
    let deserialized = deserializeIRFuncDef(serialized)
    check deserialized.name == "safe_add"
    check deserialized.params.len == 2
    check deserialized.params[0].constraint.isSome
    check deserialized.params[1].constraint.isNone

  test "preConditions serialization roundtrip":
    let precond = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let f = makeFuncDef("clamp", @[makeParam("x")], makeVar("x"),
                        preConditions = @[precond])
    let serialized = serializeIRFuncDef(f)
    let deserialized = deserializeIRFuncDef(serialized)
    check deserialized.preConditions.len == 1

  test "backward-compatible deserialization — old v4 format without constraint":
    # Canonical format: no |CONSTRAINT on params, no preconds
    let oldFormat = "FUNC(add([x:BV64,y:BV64]):BV64=BIN(boAdd,V(x:BV64),V(y:BV64)),rec=false)"
    let deserialized = deserializeIRFuncDef(oldFormat)
    check deserialized.name == "add"
    check deserialized.params.len == 2
    check deserialized.params[0].constraint.isNone
    check deserialized.params[1].constraint.isNone
    check deserialized.preConditions.len == 0

  # ── classifyTypeLevel ──

  test "classifyTypeLevel positive — constrained non-recursive simple function":
    let constraint = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let f = makeFuncDef("clamp", @[makeConstrainedParam("x", constraint)],
                        makeVar("x"))
    check classifyTypeLevel(f) == true

  test "classifyTypeLevel negative — no constraints":
    let f = makeFuncDef("add", @[makeParam("x"), makeParam("y")],
                        makeBinOp(boAdd, makeVar("x"), makeVar("y")))
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — recursive function":
    let recCall = IRExpr(kind: irRecCall, recArgs: @[makeVar("x")])
    let f = makeFuncDef("rec", @[makeConstrainedParam("x", makeBinOp(boLt, makeVar("x"), makeLit(100)))],
                        recCall, isRecursive = true)
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — external function call":
    let call = IRExpr(kind: irCall, callName: "external", callArgs: @[makeVar("x")])
    let f = makeFuncDef("withcall", @[makeConstrainedParam("x", makeBinOp(boLt, makeVar("x"), makeLit(100)))],
                        call)
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — nonlinear operation (boMul)":
    let mulExpr = makeBinOp(boMul, makeVar("x"), makeVar("y"))
    let f = makeFuncDef("mul", @[makeConstrainedParam("x", makeBinOp(boLt, makeVar("x"), makeLit(100))),
                                  makeParam("y")],
                        mulExpr)
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel positive — preConditions without param constraints":
    let precond = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let f = makeFuncDef("guarded", @[makeParam("x")], makeVar("x"),
                        preConditions = @[precond])
    check classifyTypeLevel(f) == true

  # ── classifyTypeLevel — string/list types ──

  test "classifyTypeLevel positive — string param with simple body":
    let sParam = IRFuncParam(name: "s", ty: IRType(kind: irtString),
                             constraint: none(IRExpr))
    let f = makeFuncDef("process_str", @[sParam], makeVar("s"),
                        preConditions = @[makeLit(1)])
    check classifyTypeLevel(f) == true

  test "classifyTypeLevel positive — list param with simple body":
    let xsParam = IRFuncParam(name: "xs",
                              ty: IRType(kind: irtList, elemType: irTypeBitVec64()),
                              constraint: none(IRExpr))
    let f = makeFuncDef("process_list", @[xsParam], makeVar("xs"),
                        preConditions = @[makeLit(1)])
    check classifyTypeLevel(f) == true

  test "classifyTypeLevel positive — string return type with simple body":
    let f = makeFuncDef("get_name",
                        @[IRFuncParam(name: "x", ty: irTypeBitVec64(),
                                      constraint: some(makeLit(1)))],
                        makeVar("x"),
                        retType = IRType(kind: irtString))
    check classifyTypeLevel(f) == true

  test "classifyTypeLevel negative — string param with irCall body":
    let sParam = IRFuncParam(name: "s", ty: IRType(kind: irtString),
                             constraint: none(IRExpr))
    let callBody = IRExpr(kind: irCall, callName: "external",
                          callArgs: @[makeVar("s")])
    let f = makeFuncDef("complex_str", @[sParam], callBody,
                        preConditions = @[makeLit(1)])
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — string param with irBinOp body (stricter check)":
    let sParam = IRFuncParam(name: "s", ty: IRType(kind: irtString),
                             constraint: none(IRExpr))
    let binopBody = makeBinOp(boAdd, makeVar("s"), makeLit(0))
    let f = makeFuncDef("binop_str", @[sParam], binopBody,
                        preConditions = @[makeLit(1)])
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — string param with irUnaryOp body (stricter check)":
    let sParam = IRFuncParam(name: "s", ty: IRType(kind: irtString),
                             constraint: none(IRExpr))
    let unaryBody = IRExpr(kind: irUnaryOp, unaryOp: uoNot,
                           unaryArg: makeVar("s"))
    let f = makeFuncDef("unary_str", @[sParam], unaryBody,
                        preConditions = @[makeLit(1)])
    check classifyTypeLevel(f) == false

  test "classifyTypeLevel negative — string param no constraints":
    let sParam = IRFuncParam(name: "s", ty: IRType(kind: irtString),
                             constraint: none(IRExpr))
    let f = makeFuncDef("no_constr", @[sParam], makeVar("s"))
    check classifyTypeLevel(f) == false

  # ── irToLeanRefinedModule ──

  test "irToLeanRefinedModule output — constrained parameter":
    let constraint = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let f = makeFuncDef("clamp", @[makeConstrainedParam("x", constraint)],
                        makeVar("x"))
    let leanRes = irToLeanRefinedModule(f)
    check leanRes.isOk
    let lean = leanRes.get
    check lean.contains("def clamp")
    check lean.contains("(x : BitVec 64)")
    check lean.contains("(h_x :")
    check lean.contains("< 100")

  test "irToLeanRefinedModule output — preConditions parameter":
    let precond = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let f = makeFuncDef("clamp", @[makeParam("x")], makeVar("x"),
                        preConditions = @[precond])
    let leanRes = irToLeanRefinedModule(f)
    check leanRes.isOk
    let lean = leanRes.get
    check lean.contains("(h_pre0 :")
    check lean.contains("< 100")

  # ── refinedExprToProp regression tests ──

  test "refinedExprToProp — supported boLt returns ok":
    let expr = makeBinOp(boLt, makeVar("x"), makeLit(100))
    let res = refinedExprToProp(expr)
    check res.isOk
    check res.get == "(x < 100)"

  test "refinedExprToProp — supported boEq returns ok":
    let expr = makeBinOp(boEq, makeVar("a"), makeVar("b"))
    let res = refinedExprToProp(expr)
    check res.isOk
    check res.get == "(a = b)"

  test "refinedExprToProp — irCall in precondition returns err":
    let call = IRExpr(kind: irCall, callName: "external", callArgs: @[makeVar("x")])
    let res = refinedExprToProp(call)
    check res.isErr
    check "unrepresentable-ir" in res.error

  test "refinedExprToProp — nil returns err":
    let res = refinedExprToProp(nil)
    check res.isErr
    check res.error == "nil-expr"

  test "refinedExprToProp — irRecCall returns err":
    let recCall = IRExpr(kind: irRecCall, recArgs: @[makeVar("x")])
    let res = refinedExprToProp(recCall)
    check res.isErr
    check "unrepresentable-ir" in res.error

  test "refinedExprToProp — irLoop returns err":
    let loop = IRExpr(kind: irLoop)
    let res = refinedExprToProp(loop)
    check res.isErr
    check "unrepresentable-ir" in res.error

  test "irToLeanRefinedModule — rejects function with irCall in constraint":
    let constraint = IRExpr(kind: irCall, callName: "external", callArgs: @[makeVar("x")])
    let f = makeFuncDef("bad", @[makeConstrainedParam("x", constraint)],
                        makeVar("x"))
    let leanRes = irToLeanRefinedModule(f)
    check leanRes.isErr
    check "unrepresentable-ir" in leanRes.error
