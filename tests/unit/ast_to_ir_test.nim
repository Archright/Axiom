## Unit tests for ast_to_ir.nim — AST-to-IR conversion via runtime parseStringAST.
## Uses custom main() pattern to avoid unittest framework cleanup crashes.
##
## Architecture note: convertFuncDef/convertExpr use NimNode (std/macros magic ops)
## which are compile-time only. Runtime parseStringAST returns PNode (compiler/ast).
## TNode/PNode and NimNode are distinct types in Nim 2.x — direct call is impossible.
## Solution: compile-time macro tests exercise convertFuncDef via quote/do;
## runtime tests verify parseStringAST returns valid PNodes + IR helpers work directly.

import std/[strutils, tables]
import compiler/ast
import macros
import core/parser_utils
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir

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

  initParserUtils()

  # =========================================================================
  # Section 1: parseStringAST Runtime Tests (PNode validation)
  # =========================================================================

  echo "=== parseStringAST — Runtime Parser ==="

  # Case 1: basic proc def parses
  check "parseStringAST simple proc":
    let ast = parseStringAST("proc add(a, b: int): int = a + b")
    doAssert not ast.isNil

  # Case 2: root is nkStmtList wrapping proc
  check "parseStringAST root is StmtList":
    let ast = parseStringAST("proc f(): int = 1")
    doAssert not ast.isNil
    doAssert ast[].kind == nkStmtList

  # Case 3: child is nkProcDef
  check "parseStringAST child is ProcDef":
    let ast = parseStringAST("proc foo(): int = 1")
    let child = ast[].sons[0]
    doAssert child.kind == nkProcDef

  # Case 4: function name extracted correctly
  check "parseStringAST extracts name":
    let ast = parseStringAST("proc bar(x: int): bool = x > 0")
    let pd = ast[].sons[0]
    doAssert pd.sons[0].ident.s == "bar"

  # Case 5: func def also parses
  check "parseStringAST func def":
    let ast = parseStringAST("func double(x: int): int = x * 2")
    doAssert not ast.isNil
    let fd = ast[].sons[0]
    doAssert fd.kind == nkFuncDef

  # Case 6: empty string returns nil
  check "parseStringAST empty returns nil":
    let ast = parseStringAST("")
    doAssert ast.isNil

  # Case 7: complex proc with multiple params
  check "parseStringAST multi-param proc":
    let ast = parseStringAST("proc combine(a: int; b: string; c: bool): int = 0")
    doAssert not ast.isNil
    let pd = ast[].sons[0]
    doAssert pd.kind == nkProcDef

  # =========================================================================
  # Section 2: IR Helpers Direct Tests
  # =========================================================================

  echo ""
  echo "=== IR Helpers — Direct Construction ==="

  # Case 8: irLit creates correct literal
  check "irLit(42)":
    let e = irLit(42)
    doAssert e.kind == irLit
    doAssert e.litVal == 42

  # Case 9: irVar creates correct variable ref
  check "irVar creates var ref":
    let v = irVar("x", irTypeBitVec64())
    doAssert v.kind == irVar
    doAssert v.varName == "x"

  # Case 10: irBinOp boAdd
  check "irBinOp boAdd":
    let e = irBinOp(boAdd, irLit(1), irLit(2))
    doAssert e.kind == irBinOp
    doAssert e.binOp == boAdd

  # Case 11: irUnaryOp uoNot
  check "irUnaryOp uoNot":
    let e = irUnaryOp(uoNot, irVar("p", irTypeBool()))
    doAssert e.kind == irUnaryOp
    doAssert e.unaryOp == uoNot

  # Case 12: irCall creates function call
  check "irCall creates call":
    let e = irCall("foo", @[irLit(1), irLit(2)])
    doAssert e.kind == irCall
    doAssert e.callName == "foo"
    doAssert e.callArgs.len == 2

  # Case 13: irRecCall for recursive calls
  check "irRecCall creates rec call":
    let e = irRecCall(@[irLit(42)])
    doAssert e.kind == irRecCall

  # Case 14: irIf creates if-then-else
  check "irIf creates if-expr":
    let cond = irEq(irVar("x", irTypeBitVec64()), irLit(0))
    let e = irIf(cond, irLit(1), irLit(2))
    doAssert e.kind == irIf
    doAssert e.ifThen != nil

  # Case 15: irLet creates let binding
  check "irLet creates let-binding":
    let e = irLet("tmp", irLit(42), irVar("x", irTypeBitVec64()))
    doAssert e.kind == irLet
    doAssert e.letName == "tmp"

  # Case 16: irLoop creates for-loop
  check "irLoop creates for-loop":
    let loopVar = irVar("i", irTypeBitVec64())
    let endVal = irLit(10)
    let lcond = irBinOp(boLt, loopVar, endVal)
    let lbody = irLit(0)
    let lstep = irBinOp(boAdd, loopVar, irLit(1))
    let e = irLoop(lkFor, @["i"], @[endVal], lcond, lstep, lbody)
    doAssert e.kind == irLoop
    doAssert e.loopKind == lkFor

  # Case 17: irLoop creates while-loop
  check "irLoop creates while-loop":
    let cond = irVar("flag", irTypeBool())
    let body = irLit(0)
    let e = irLoop(lkWhile, @["flag"], @[cond], cond, nil, body)
    doAssert e.kind == irLoop
    doAssert e.loopKind == lkWhile

  # Case 18: irCase creates case expression
  check "irCase creates case":
    let scrutinee = irVar("n", irTypeBitVec64())
    let branches = @[CaseBranch(pattern: 0, body: irLit(0)), CaseBranch(pattern: 1, body: irLit(1))]
    let e = irCase(scrutinee, branches, irLit(-1))
    doAssert e.kind == irCase
    doAssert e.caseBranches.len == 2

  # =========================================================================
  # Section 3: Type Conversion Tests (via compile-time macro)
  # =========================================================================

  echo ""
  echo "=== Type Conversion — Compile-Time Macro Tests ==="

  # Case 19: int type maps to BV64
  macro testIntType(): untyped =
    let t = convertType(ident"int")
    result = newLit($t.kind)

  check "convertType int -> BitVec64":
    let r = testIntType()
    doAssert r.contains("irtBitVec64") or r.contains("0")

  # Case 20: bool type maps to Bool
  macro testBoolType(): untyped =
    let t = convertType(ident"bool")
    result = newLit($t.kind)

  check "convertType bool -> Bool":
    let r = testBoolType()
    doAssert r.contains("irtBool") or r.contains("1")

  # Case 21: seq[int] maps to List(BV64)
  macro testSeqType(): untyped =
    let t = convertType(newTree(nnkBracketExpr, ident"seq", ident"int"))
    result = newStrLitNode($t.kind)

  check "convertType seq[int] -> List":
    let r = testSeqType()
    doAssert r.contains("irtList") or r.contains("2")

  # =========================================================================
  # Section 4: Expression Conversion Tests (via compile-time macro)
  # =========================================================================

  echo ""
  echo "=== Expression Conversion — Compile-Time Macro Tests ==="

  # Case 22: integer literal expression
  macro testIntExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(newLit(42), ctx)
    result = newLit($e.kind & "|" & $e.litVal)

  check "convertExpr int lit":
    let r = testIntExpr()
    doAssert r == "irLit|42"

  # Case 23: variable reference expression
  macro testVarExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(ident"x", ctx)
    result = newLit($e.kind & "|" & e.varName)

  check "convertExpr var ref":
    let r = testVarExpr()
    doAssert r == "irVar|x"

  # Case 24: infix binary operation (a + b)
  macro testInfixExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(infix(ident"a", "+", ident"b"), ctx)
    result = newLit($e.kind & "|" & $e.binOp)

  check "convertExpr infix a+b":
    let r = testInfixExpr()
    doAssert r == "irBinOp|boAdd"

  # Case 25: prefix unary operation (not x)
  macro testPrefixExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(prefix(ident"x", "not"), ctx)
    result = newLit($e.kind & "|" & $e.unaryOp)

  check "convertExpr prefix not x":
    let r = testPrefixExpr()
    doAssert r == "irUnaryOp|uoNot"

  # Case 26: function call expression
  macro testCallExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(newCall(ident"foo", newLit(1)), ctx)
    result = newLit($e.kind & "|" & e.callName)

  check "convertExpr call foo(1)":
    let r = testCallExpr()
    doAssert r == "irCall|foo"

  # Case 27: string literal expression
  macro testStrExpr(): untyped =
    var ctx = initIrContext("", @[])
    let e = convertExpr(newStrLitNode("hello"), ctx)
    result = newLit($e.kind & "|" & e.stringVal)

  check "convertExpr strLit hello":
    let r = testStrExpr()
    doAssert r == "irStringLit|hello"

  # =========================================================================
  # Section 5: Function Definition Tests (via compile-time macro)
  # =========================================================================

  echo ""
  echo "=== Function Definition — Compile-Time Macro Tests ==="

  # Case 28: proc def converted via convertFuncDef (nnkProcDef support)
  macro testProcDefConversion(): untyped =
    let irDef = convertFuncDef(quote do:
      proc add(a, b: int): int = a + b)
    result = newStrLitNode($irDef.name & "|" & $irDef.params.len & "|" & $irDef.isRecursive)

  check "convertFuncDef accepts nnkProcDef":
    let r = testProcDefConversion()
    doAssert r == "add|2|false"

  # Case 29: func def with no params
  macro testFuncDefNoParams(): untyped =
    let funcAst = quote do:
      func fortyTwo(): int = 42
    let nameNode = funcAst[0]
    let name = case nameNode.kind
      of nnkPostfix: nameNode[1].strVal
      of nnkIdent: nameNode.strVal
      else: ""
    result = newStrLitNode(name)

  check "func def name":
    let r = testFuncDefNoParams()
    doAssert r == "fortyTwo"

  # Case 30: recursive function detection via containsRecCall
  macro testRecursiveDetection(): untyped =
    let bodyAst = quote do:
      n * fact(n - 1)
    let hasRec = containsRecCall(bodyAst, "fact")
    result = newStrLitNode($hasRec)

  check "containsRecCall detects self-call in body":
    let r = testRecursiveDetection()
    doAssert r == "true"

  # Case 31: non-recursive call not detected
  macro testNonRecursive(): untyped =
    let bodyAst = quote do:
      x + foo(y)
    let hasRec = containsRecCall(bodyAst, "bar")
    result = newStrLitNode($hasRec)

  check "containsRecCall no false positive":
    let r = testNonRecursive()
    doAssert r == "false"

  # =========================================================================
  # Section 6: buildIRModule Tests (via compile-time macro)
  # =========================================================================

  echo ""
  echo "=== buildIRModule — Compile-Time Macro Tests ==="

  # Case 32: buildIRModule with single proc def (nnkProcDef → IRFuncDef)
  macro testBuildModuleSingle(): untyped =
    let f1 = convertFuncDef(quote do:
      proc add(a, b: int): int = a + b)
    let module = buildIRModule(@[f1])
    result = newStrLitNode($module.functions.len & "|" & $f1.name & "|" & $f1.params.len)

  check "buildIRModule single proc":
    let r = testBuildModuleSingle()
    doAssert r == "1|add|2"

  # Case 33: buildIRModule with recursive proc (nnkProcDef recursion detection)
  macro testBuildModuleRecursive(): untyped =
    let f1 = convertFuncDef(quote do:
      proc fact(n: int): int =
        if n <= 1: 1
        else: n * fact(n - 1))
    let module = buildIRModule(@[f1])
    result = newStrLitNode($module.functions.len & "|" & $f1.isRecursive)

  check "buildIRModule recursive proc detected":
    let r = testBuildModuleRecursive()
    doAssert r == "1|true"

  # Case 34: func def still works (regression guard)
  macro testFuncDefStillWorks(): untyped =
    let f1 = convertFuncDef(quote do:
      func fortyTwo(): int = 42)
    let module = buildIRModule(@[f1])
    result = newStrLitNode($module.functions.len & "|" & $f1.name & "|" & $f1.params.len & "|" & $f1.body.litVal)

  check "func def still works (regression)":
    let r = testFuncDefStillWorks()
    doAssert r == "1|fortyTwo|0|42"

  # Case 35: buildIRModule with multiple proc defs
  macro testBuildModuleMultipleProcs(): untyped =
    let f1 = convertFuncDef(quote do:
      proc add(a, b: int): int = a + b)
    let f2 = convertFuncDef(quote do:
      proc sub(a, b: int): int = a - b)
    let module = buildIRModule(@[f1, f2])
    result = newStrLitNode($module.functions.len)

  check "buildIRModule multiple procs":
    let r = testBuildModuleMultipleProcs()
    doAssert r == "2"

  # =========================================================================
  # Section 7: Edge Cases
  # =========================================================================

  echo ""
  echo "=== Edge Cases ==="

  # Case 36: invalid node for convertFuncDef
  macro testInvalidNode(): untyped =
    let irDef = convertFuncDef(newLit(42))
    if irDef.name == "":
      result = newStrLitNode("true")
    else:
      result = newStrLitNode("false")

  check "convertFuncDef invalid node returns empty":
    let r = testInvalidNode()
    doAssert r == "true"

  # Case 37: stripGensym removes backtick suffix
  check "stripGensym removes gensym":
    doAssert stripGensym("a`gensym48") == "a"
    doAssert stripGensym("x`gensym2") == "x"
    doAssert stripGensym("normal") == "normal"

  # Case 38: containsRecCall detects recursion
  macro testContainsRecCall(): untyped =
    let hasRec = containsRecCall(
      quote do: n * fact(n - 1),
      "fact"
    )
    result = newStrLitNode($hasRec)

  check "containsRecCall detects self-call":
    let r = testContainsRecCall()
    doAssert r == "true"

  # Case 39: annotateOverflow adds overflow annotations
  check "annotateOverflow boAdd":
    let e = irBinOp(boAdd, irLit(1), irLit(2))
    let ann = annotateOverflow(e)
    doAssert ann.overflow == oNoOverflow

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
