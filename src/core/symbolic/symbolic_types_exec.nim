import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/tables
import std/strutils
import compiler/ast
import core/types/results
import core/symbolic/cfg_types
import core/parsers/pnode_nav
import core/symbolic/symbolic_types_expr
import core/symbolic/symbolic_types_parse
import ../../core/trusted/axiom_pragmas

## S Var.
func cloneState(state: SymbolicState): SymbolicState {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= result 0) (>= result 0) (>= (str.len name) 0)))", "ast_parse_failed_isolated ∧ (result ≥ 0) ∧ (result ≥ 0) ∧ name.length ≥ 0"].} =
  result.pathCondition = state.pathCondition
  result.assignments = initTable[string, SymSExpr]()
  for k, v in state.assignments:
    result.assignments[k] = v
  result.loopInvariants = initTable[int, SymSExpr]()
  for k, v in state.loopInvariants:
    result.loopInvariants[k] = v

func updateAssignment(state: var SymbolicState; name: string; value: SymSExpr) {.raises: [], axiom: ["(assert (and (>= (str.len name) 0)))", "name.length ≥ 0"].} =
  state.assignments[name] = value

func evalAssignment(state: var SymbolicState; node: PNode): Result[bool, string] {.raises: [], axiom: ["(assert (and (>= depth 0) (= (str.len name) 0) (= leftNode child) (= rightNode child) (>= node 0) (>= rightNode 0) (>= leftNode 0)))", "depth >= 0 ∧ name.length = 0 ∧ leftNode = child ∧ rightNode = child ∧ (node ≥ 0) ∧ (rightNode ≥ 0) ∧ (leftNode ≥ 0)"].} =
  if node.kind != nkAsgn:
    return err("not an assignment")
  var leftNode: PNode = nil
  var rightNode: PNode = nil
  if node.len > 0 and not node[0].isNil: leftNode = node[0]
  if node.len > 1 and not node[1].isNil: rightNode = node[1]
  if leftNode.isNil or rightNode.isNil:
    return err("assignment missing left/right")
  let name = extractIdentifierNameP(leftNode)
  if name.len == 0:
    return err("assignment left side not a simple identifier")
  let rightRes = nimExprToSymSExprP(rightNode)
  if rightRes.isErr():
    return err("assignment right: " & rightRes.error())
  updateAssignment(state, name, rightRes.get())
  ok(true)

func evalVarSection(state: var SymbolicState; node: PNode): Result[bool, string] {.raises: [], axiom: ["(assert (and (>= depth 0) (= (str.len name) 0) (= nameNode c) (= valueNode c) (>= valueNode 0) (>= node 0) (>= child 0) (>= nameNode 0)))", "depth >= 0 ∧ name.length = 0 ∧ nameNode = c ∧ valueNode = c ∧ (valueNode ≥ 0) ∧ (node ≥ 0) ∧ (child ≥ 0) ∧ (nameNode ≥ 0)"].} =
  if node.kind notin {nkVarSection, nkLetSection}:
    return err("not a var/let section")
  for child in node:
    if child.isNil: continue
    if child.kind == nkIdentDefs:
      var nameNode: PNode = nil
      var valueNode: PNode = nil
      if child.len > 0 and not child[0].isNil: nameNode = child[0]
      if child.len > 1 and not child[1].isNil: valueNode = child[1]
      if nameNode.isNil: continue
      let name = extractIdentifierNameP(nameNode)
      if name.len == 0: continue
      if valueNode.isNil:
        updateAssignment(state, name, sConst(0))
      else:
        let valRes = nimExprToSymSExprP(valueNode)
        if valRes.isOk():
          updateAssignment(state, name, valRes.get())
        else:
          updateAssignment(state, name, sConst(0))
  ok(true)

func conjoinPathCondition(state: var SymbolicState; cond: SymSExpr) {.raises: [], axiom: ["(assert (and (>= depth 0) (>= state 0)))", "depth >= 0 ∧ (state ≥ 0)"].} =
  if state.pathCondition.isNil:
    state.pathCondition = cond
  else:
    state.pathCondition = sAnd(state.pathCondition, cond)

func executeBlockSymbolically(
  cfg: ControlFlowGraph;
  blockId: int;
  state: SymbolicState;
  visited: var Table[int, int];  # blockId -> visit count
  trace: var SymbolicTrace;
  resultRef: var CfgAnalysisResult
): Result[int, string] {.raises: [], axiom: ["(assert (and (or (< blockId 0) (>= blockId blockCount)) (>= currentVisits 2) succRes (>= resultRef 0) (>= blockCount 0) (>= visited 0) (or (= resultRef_hasLoops true) (= resultRef_hasLoops false)) (or (= resultRef_hasUnsupported true) (= resultRef_hasUnsupported false))))", "blockId < 0 ∨ blockId ≥ blockCount ∧ currentVisits ≥ 2 ∧ succRes ∧ (resultRef ≥ 0) ∧ (blockCount ≥ 0) ∧ (visited ≥ 0) ∧ resultRef_hasLoops = true ∨ resultRef_hasLoops = false ∧ resultRef_hasUnsupported = true ∨ resultRef_hasUnsupported = false"].} =
  var blockCount = 0
  try:
    blockCount = cfg.blocks.len
  except CatchableError:
    return err("cfg access failed")
  if blockId < 0 or blockId >= blockCount:
    return ok(0)

  # Limit path explosion: max 2 visits per block
  let currentVisits = visited.getOrDefault(blockId, 0)
  if currentVisits >= 2:
    return ok(0)
  visited[blockId] = currentVisits + 1

  var currentState = cloneState(state)
  let blk = cfg.blocks[blockId]

  # Execute statements in block
  for stmt in blk.statements:
    if stmt.isNil: continue
    case stmt.kind
    of nkAsgn:
      let res = evalAssignment(currentState, stmt)
      if res.isErr():
        resultRef.hasUnsupported = true
        resultRef.unsupportedReason = res.error()
    of nkVarSection, nkLetSection:
      let res = evalVarSection(currentState, stmt)
      if res.isErr():
        resultRef.hasUnsupported = true
        resultRef.unsupportedReason = res.error()
    of nkInfix:
      # Condition expression in header block
      let condRes = nimExprToSymSExprP(stmt)
      if condRes.isOk():
        conjoinPathCondition(currentState, condRes.get())
    of nkIdent, nkSym:
      # Simple boolean condition
      conjoinPathCondition(currentState, sVar(pNodeText(stmt)))
    of nkReturnStmt:
      # Return reached — record state and stop
      trace.add(currentState)
      return ok(0)
    else:
      discard

  # If exit block, record final state
  if blockId == cfg.exit:
    trace.add(currentState)
    return ok(0)

  # Follow successors
  if blk.successors.len == 0:
    trace.add(currentState)
    return ok(0)

  for succId in blk.successors:
    let succRes = executeBlockSymbolically(cfg, succId, currentState, visited, trace, resultRef)
    if succRes.isErr():
      return succRes

  ok(0)

## Execute Symbolically.
func executeSymbolically*(cfg: ControlFlowGraph): Result[SymbolicTrace, string] {.raises: [], axiom: ["(assert (and (>= resultRef 0) (>= blockCount 0)))", "(resultRef ≥ 0) ∧ (blockCount ≥ 0)"].} =
  var initialState = SymbolicState(
    pathCondition: sTrue(),
    assignments: initTable[string, SymSExpr](),
    loopInvariants: initTable[int, SymSExpr]()
  )
  var visited = initTable[int, int]()
  var trace: SymbolicTrace = @[]
  var resultRef = CfgAnalysisResult(
    hasLoops: false,
    hasUnsupported: false,
    loopInvariants: initTable[int, SymSExpr](),
    unsupportedReason: ""
  )

  # Detect loops
  var blockCount = 0
  try:
    blockCount = cfg.blocks.len
  except CatchableError:
    return err("cfg access failed")
  for i in 0 ..< blockCount:
    if cfg.blocks[i].loopHeader:
      resultRef.hasLoops = true
      break

  discard executeBlockSymbolically(cfg, cfg.entry, initialState, visited, trace, resultRef)

  ok(trace)

## Path Condition To Smt.
func pathConditionToSmt*(pc: SymSExpr): string {.raises: [].} =
  if pc.isNil or pc.kind == seTrue:
    return ""
  "(assert " & sExprToString(pc) & ")"

func sExprVariables*(e: SymSExpr): seq[string] {.raises: [], axiom: ["(assert (and seVar seConst seTrue seFalse))", "seVar ∧ seConst ∧ seTrue ∧ seFalse"].} =
  if e.isNil:
    return
  case e.kind
  of seVar:
    result.add(e.name)
  of seConst, seTrue, seFalse:
    discard
  else:
    if e.lhs != nil:
      result.add(sExprVariables(e.lhs))
    if e.rhs != nil:
      result.add(sExprVariables(e.rhs))

func declareSmtVars(e: SymSExpr): string {.raises: [], axiom: ["(assert (and (>= depth 0) (>= vars 0) (>= result 0) (>= seen 0)))", "depth >= 0 ∧ (vars ≥ 0) ∧ (result ≥ 0) ∧ (seen ≥ 0)"].} =
  var seen = initTable[string, bool]()
  let vars = sExprVariables(e)
  var lines: seq[string] = @[]
  for v in vars:
    if not seen.hasKey(v):
      seen[v] = true
      lines.add("(declare-const " & v & " Int)")
  result = lines.join("\n")

  # AxiomGuard:8335058567765458 (invinvLoop)
func buildSmtQueryForCheck*(pathCondition: SymSExpr; invariant: SymSExpr; extraAsserts: seq[string] = @[]): string {.raises: [], axiom: ["(assert (and (>= (seq.len extraAsserts) 0) (forall ((extraAssertsIdx Int)) (=> (and (>= extraAssertsIdx 0) (< extraAssertsIdx (seq.len extraAsserts))) (>= (str.len (seq.nth extraAsserts extraAssertsIdx)) 0))) (> (str.len ea) 0) (>= extraAsserts 0) (>= result 0) (forall ((extraAssertsIdx Int)) (=> (and (>= extraAssertsIdx 0) (< extraAssertsIdx (seq.len extraAsserts))) (>= (str.len (seq.nth extraAsserts extraAssertsIdx)) 0)))))", "extraAsserts.size ≥ 0 ∧ (∀ (extraAssertsIdx : Fin extraAsserts.size), (extraAsserts.get extraAssertsIdx).length ≥ 0) ∧ ea.length > 0 ∧ (extraAsserts ≥ 0) ∧ (result ≥ 0) ∧ (∀ (extraAssertsIdx : Fin extraAsserts.size), (extraAsserts.get extraAssertsIdx).length ≥ 0)"].} =
  var parts: seq[string] = @[]
  let allExpr = sAnd(pathCondition, sNot(invariant))
  parts.add(declareSmtVars(allExpr))
  if pathCondition.kind != seTrue:
    parts.add(pathConditionToSmt(pathCondition))
  for ea in extraAsserts:
    if ea.len > 0:
      parts.add(ea)
  parts.add("(assert (not " & sExprToString(invariant) & "))")
  parts.add("(check-sat)")
  result = parts.join("\n")

{.pop.}

{.pop.}
