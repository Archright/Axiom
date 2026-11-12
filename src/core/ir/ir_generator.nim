{.push raises: [].}
import std/[macros, options, strutils, sequtils]
import ir_types
import shared/canonical_ast

const nnkExprStmt = nnkStmtListExpr

# ── Canonical AST helpers ──────────────────────────────────────
# Lightweight wrappers that use CanonNode for read-only analysis
# while keeping NimNode for AST construction/manipulation.

func canonKind(n: NimNode): CanonKind = nimKindToCanon(n.kind)
func canonIdent(n: CanonNode): string = getStringValue(n)

proc convertNimTypeToLean*(nimType: string): string =
  case nimType
  of "int", "int64": "Int"
  of "string": "String"
  of "bool": "Bool"
  else: nimType

proc isInductiveType*(typeName: string): bool =
  const inductivePrefixes = ["seq[", "List[", "Tree["]
  const inductiveExact = ["Nat", "Natural"]
  if typeName in inductiveExact: return true
  for p in inductivePrefixes:
    if typeName.startsWith(p): return true
  return false

proc toAxiomParam*(param: AxiomIRParam): AxiomParam =
  AxiomParam(
    name: param.name,
    typeStr: convertNimTypeToLean(param.typeName),
    refinement: none(IRExpr),
    isInductive: param.isInductive
  )

# extractParam works on raw NimNode (index-based AST access)
proc extractParam*(node: NimNode): AxiomIRParam =
  let tName = $node[1] # AST에서 타입 노드 추출
  result = AxiomIRParam(name: $node[0], typeName: tName, isInductive: isInductiveType(tName))

# extractParams uses CanonNode for structure validation, NimNode for data extraction
proc extractParams*(formalParams: NimNode): seq[AxiomParam] =
  let c = toCanon(formalParams)
  result = newSeq[AxiomParam]()
  let total = getChildCount(c)
  for i in 1 ..< total:
    let child = getChild(c, i)
    if getNodeKind(child) == ckIdentDefs:
      let identDef = formalParams[i]  # original NimNode for index access
      for j in 0 ..< identDef.len - 2:
        let rawParam = extractParam(identDef)
        result.add(toAxiomParam(rawParam))
    else:
      let paramName = $formalParams[i][0]
      let typeNode = formalParams[i][1]
      let typeStr = repr(typeNode)
      result.add(AxiomParam(
        name: paramName,
        typeStr: convertNimTypeToLean(typeStr),
        refinement: none(IRExpr),
        isInductive: isInductiveType(convertNimTypeToLean(typeStr))
      ))

proc unwrapStmt*(node: NimNode): NimNode =
  if node.kind == nnkExprStmt and node.len > 0:
    node[0]
  else:
    node

proc parseExpr*(node: NimNode): IRExpr =
  let n = unwrapStmt(node)
  case canonKind(n)
  of ckIdent, ckSym:
    result = IRExpr(kind: ieVar, varName: $n)
  of ckIntLit, ckFloatLit:
    result = IRExpr(kind: ieConst, val: repr(n))
  of ckStrLit:
    result = IRExpr(kind: ieConst, val: repr(n))
  of ckInfix:
    result = IRExpr(
      kind: ieBinaryOp,
      op: $n[0],
      left: parseExpr(n[1]),
      right: parseExpr(n[2])
    )
  of ckCall, ckCommand:
    var args: seq[IRExpr] = @[]
    for i in 1 ..< n.len:
      args.add(parseExpr(n[i]))
    result = IRExpr(kind: ieApp, fnName: $n[0], args: args)
  else:
    result = IRExpr(kind: ieConst, val: "true")

proc extractContracts*(body: NimNode, preConds: var seq[IRExpr], postCond: var Option[IRExpr]) =
  let c = toCanon(body)
  if getNodeKind(c) in {ckStmtList, ckStmtListExpr}:
    for i in 0 ..< getChildCount(c):
      let rawStmt = body[i]  # original NimNode for manipulation
      let stmt = unwrapStmt(rawStmt)
      if canonKind(stmt) in {ckCall, ckCommand} and stmt.len > 1:
        let head = $stmt[0]
        if head == "require":
          preConds.add(parseExpr(stmt[1]))
        elif head == "ensure":
          postCond = some(parseExpr(stmt[1]))

proc convertFuncDefWithContracts*(fnAst: NimNode): AxiomIRNode =
  let procDef = if fnAst.kind == nnkProcDef: fnAst else: fnAst[0]
  let fnName = $procDef[0]
  let params = extractParams(procDef[3])
  let retType = if procDef[3][0].kind != nnkEmpty: convertNimTypeToLean(repr(procDef[3][0])) else: "Unit"

  var preConds: seq[IRExpr] = @[]
  var postCond: Option[IRExpr] = none(IRExpr)
  let bodyAst = if procDef.len > 6: procDef[6] else: newStmtList()
  extractContracts(bodyAst, preConds, postCond)

  result = AxiomIRNode(
    name: fnName,
    params: params,
    returnType: retType,
    preConditions: preConds,
    postCondition: postCond,
    children: @[],
    body: nil
  )

proc convertFuncDef*(fnAst: NimNode): AxiomIRNode =
  let fnAstCanon = toCanon(fnAst)
  if getNodeKind(fnAstCanon) != ckProcDef:
    error("Expected nnkProcDef", fnAst)

  let fnName = $fnAst[0]
  let params = extractParams(fnAst[3])
  let retType = if fnAst[3][0].kind != nnkEmpty: convertNimTypeToLean(repr(fnAst[3][0])) else: "Unit"

  var preConds: seq[IRExpr] = @[]
  var postCond: Option[IRExpr] = none(IRExpr)
  let bodyAst = if fnAst.len > 6: fnAst[6] else: newStmtList()
  extractContracts(bodyAst, preConds, postCond)

  return AxiomIRNode(
    name: fnName,
    params: params,
    returnType: retType,
    preConditions: preConds,
    postCondition: postCond,
    children: @[],
    body: nil
  )
