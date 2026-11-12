import std/[unittest, os, macros, options, strutils]
import core/ir/ir_types
import core/ir/ir_generator
import core/ir/ir_to_lean
import core/trusted/git_content_cas

macro extractContractsTest() =
  let fnAst = quote do:
    proc myFunc(x: int): int =
      require(x > 0)
      ensure(result == x + 1)
      return x + 1
  let ir = convertFuncDefWithContracts(fnAst)
  let preOk = ir.preConditions.len == 1
  let postOk = ir.postCondition.isSome
  result = newStmtList()
  result.add quote do:
    check `preOk`
    check `postOk`

extractContractsTest()

macro runAstContractTest() =
  let fnAst = quote do:
    proc testFn(x: int): int =
      require(x > 0)
      ensure(result == x + 1)
      return x + 1
  let ir = convertFuncDefWithContracts(fnAst)
  let preLen = ir.preConditions.len == 1
  let postIsSome = ir.postCondition.isSome
  result = newStmtList()
  result.add quote do:
    check `preLen`
    check `postIsSome`

suite "Contract-Driven Verification Pipeline":
  test "Extract require/ensure contracts from Nim AST":
    runAstContractTest()

  test "Generate Lean 4 theorem with hypotheses":
    let ir = AxiomIRNode(
      name: "myFunc",
      params: @[AxiomParam(name: "x", typeStr: "Int", refinement: none(IRExpr), isInductive: false)],
      returnType: "Int",
      preConditions: @[IRExpr(kind: ieBinaryOp, op: ">", left: IRExpr(kind: ieVar, varName: "x"), right: IRExpr(kind: ieConst, val: "0"))],
      postCondition: some(IRExpr(kind: ieBinaryOp, op: "==", left: IRExpr(kind: ieVar, varName: "result"), right: IRExpr(kind: ieBinaryOp, op: "+", left: IRExpr(kind: ieVar, varName: "x"), right: IRExpr(kind: ieConst, val: "1"))))
    )
    let leanCodeOpt = irToLeanRefinedDefinition(ir)
    if leanCodeOpt.isSome:
      let leanCode = leanCodeOpt.get
      check "h_pre0" in leanCode
      check "intros" in leanCode

  test "Promote to Git CAS; the promotion path writes no debt registry":
    let leanCode = "theorem myFunc_spec (x : Int) (h_pre0 : x > 0) : result == x + 1 := by sorry"
    let registryPath = "data/debt_registry.json"
    let registryExisted = fileExists(registryPath)
    let registryBefore = if registryExisted: readFile(registryPath) else: ""

    let hash = promoteContentToGitCAS(leanCode)
    check hash.len == 40
    for ch in hash:
      check ch in {'0'..'9', 'a'..'f'}
    check promoteContentToGitCAS(leanCode) == hash
    check promoteContentToGitCAS(leanCode & "\n") != hash

    # Single-writer invariant: promoting an artifact must not materialise a
    # debt registry. The registry schema and the projections are written solely
    # by bin/debt_engine, so a registration call on this path would be a defect.
    check not fileExists("test_debt_registry.json")
    check registryExisted == fileExists(registryPath)
    if registryExisted:
      check readFile(registryPath) == registryBefore
