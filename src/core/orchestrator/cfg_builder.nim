import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/tables
import core/types/results
import core/parser_utils
import core/symbolic/cfg_types
import ../../core/trusted/axiom_pragmas
export cfg_types

type
  CfgBuilderState = object
    blocks: seq[BasicBlock]
    nextId: int
    exitId: int

func newBlock(state: var CfgBuilderState): int {.axiomTryImpl.} =
  let id = state.nextId
  inc state.nextId
  state.blocks.add(BasicBlock(id: id))
  result = id

func link(state: var CfgBuilderState; fromId: int; toId: int) {.axiomTryImpl.} =
  if fromId >= 0 and fromId < state.blocks.len and toId >= 0 and toId < state.blocks.len:
    if toId notin state.blocks[fromId].successors:
      state.blocks[fromId].successors.add(toId)
    if fromId notin state.blocks[toId].predecessors:
      state.blocks[toId].predecessors.add(fromId)

# ── PNode CFG Builder ──

import compiler/ast

const
  StmtKinds* = {nkExprColonExpr, nkCall, nkAsgn, nkIfStmt, nkWhileStmt, nkForStmt,
                nkReturnStmt, nkBreakStmt, nkContinueStmt, nkCaseStmt, nkBlockStmt,
                nkStmtList, nkBlockExpr, nkVarSection, nkLetSection, nkConstSection,
                nkProcDef, nkFuncDef, nkMacroDef, nkIteratorDef, nkConverterDef,
                nkTemplateDef, nkPragmaExpr}
  ## Leaf/literal nodes have no children — iterating sons raises Defect
  ## (same invariant B4-A enforced in pnode_nav.nim).
  LeafPNodeKinds* = {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                nkNone}

func isControlFlowP(node: PNode): bool {.inline.} =
  if node.isNil: return false
  result = node.kind in {nkWhileStmt, nkForStmt, nkIfStmt, nkCaseStmt,
                         nkReturnStmt, nkBreakStmt, nkContinueStmt}

func collectStatementsP(node: PNode): seq[PNode] {.raises: [].} =
  ## Collect child statement nodes from a PNode.
  if node.isNil: return
  if node.kind notin LeafPNodeKinds:
    for child in node:
      if child.isNil: continue
      if child.kind in StmtKinds:
        result.add(child)

func buildCfgFromStatementListP(
  state: var CfgBuilderState;
  stmts: openArray[PNode];
  entryId: int;
  exitId: int
): int {.raises: [].} =
  ## Build CFG for a list of PNode statements. Returns the id of the fall-through block.
  var currentId = entryId
  var i = 0
  while i < stmts.len:
    let stmt = stmts[i]
    if stmt.isNil or not isControlFlowP(stmt):
      state.blocks[currentId].statements.add(stmt)
      inc i
      continue

    case stmt.kind
    of nkReturnStmt:
      state.blocks[currentId].statements.add(stmt)
      link(state, currentId, state.exitId)
      return -1

    of nkWhileStmt:
      let headerId = newBlock(state)
      link(state, currentId, headerId)
      state.blocks[headerId].loopHeader = true

      # Condition is the first child of nkWhileStmt
      if stmt.len > 0 and not stmt[0].isNil:
        state.blocks[headerId].statements.add(stmt[0])

      # Body is the second child (or first nkStmtList/nkBlockStmt)
      let bodyId = newBlock(state)
      link(state, headerId, bodyId)
      let afterId = newBlock(state)

      var bodyStmts: seq[PNode] = @[]
      if stmt.len > 1 and not stmt[1].isNil:
        if stmt[1].kind == nkStmtList or stmt[1].kind == nkBlockStmt:
          bodyStmts = collectStatementsP(stmt[1])
        else:
          bodyStmts.add(stmt[1])
      let bodyExit = buildCfgFromStatementListP(state, bodyStmts, bodyId, afterId)
      if bodyExit >= 0:
        link(state, bodyExit, headerId)
        state.blocks[headerId].loopBackEdgeFrom.add(bodyExit)

      link(state, headerId, afterId)
      currentId = afterId
      inc i

    of nkForStmt:
      let headerId = newBlock(state)
      link(state, currentId, headerId)
      state.blocks[headerId].loopHeader = true
      state.blocks[headerId].statements.add(stmt)

      let bodyId = newBlock(state)
      link(state, headerId, bodyId)
      let afterId = newBlock(state)

      var bodyStmts: seq[PNode] = @[]
      if stmt.len > 2 and not stmt[2].isNil:
        if stmt[2].kind == nkStmtList or stmt[2].kind == nkBlockStmt:
          bodyStmts = collectStatementsP(stmt[2])
        else:
          bodyStmts.add(stmt[2])
      let bodyExit = buildCfgFromStatementListP(state, bodyStmts, bodyId, afterId)
      if bodyExit >= 0:
        link(state, bodyExit, headerId)
        state.blocks[headerId].loopBackEdgeFrom.add(bodyExit)

      link(state, headerId, afterId)
      currentId = afterId
      inc i

    of nkIfStmt:
      let condBlockId = newBlock(state)
      link(state, currentId, condBlockId)

      # Process branches sequentially (children of nkIfStmt are branch nodes)
      var branchIdx = 0
      var trueExit = -1
      var trueBodyStmts: seq[PNode] = @[]
      var falseBodyStmts: seq[PNode] = @[]
      
      for branch in stmt:
        if branch.isNil: continue
        
        if branchIdx == 0:
          # First branch: condition
          if branch.len > 0 and not branch[0].isNil:
            state.blocks[condBlockId].statements.add(branch[0])
        elif branchIdx == 1:
          # Second branch: consequence (true branch)
          for bchild in branch:
            if bchild.isNil: continue
            if bchild.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
              trueBodyStmts = collectStatementsP(bchild)
              break
            trueBodyStmts.add(bchild)
        else:
          # Subsequent branches: elif/else
          for bchild in branch:
            if bchild.isNil: continue
            if bchild.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
              falseBodyStmts = collectStatementsP(bchild)
              break
            falseBodyStmts.add(bchild)
        
        inc branchIdx

      let trueId = newBlock(state)
      link(state, condBlockId, trueId)
      if trueBodyStmts.len > 0:
        trueExit = buildCfgFromStatementListP(state, trueBodyStmts, trueId, exitId)

      let falseId = newBlock(state)
      link(state, condBlockId, falseId)
      var falseExit = -1
      if falseBodyStmts.len > 0:
        falseExit = buildCfgFromStatementListP(state, falseBodyStmts, falseId, exitId)
      else:
        falseExit = falseId

      let mergeId = newBlock(state)
      if trueExit >= 0: link(state, trueExit, mergeId)
      if falseExit >= 0: link(state, falseExit, mergeId)
      currentId = mergeId
      inc i

    of nkBreakStmt, nkContinueStmt:
      state.blocks[currentId].statements.add(stmt)
      inc i

    else:
      state.blocks[currentId].statements.add(stmt)
      inc i

  return currentId

func buildCfgFromAstP*(fnAst: PNode): ControlFlowGraph {.raises: [].} =
  ## Build a ControlFlowGraph from a PNode AST.
  ## Handles nkProcDef/nkFuncDef nodes and extracts their statement lists.
  var state = CfgBuilderState(nextId: 0)
  let entryId = newBlock(state)
  state.exitId = newBlock(state)

  # Extract body from proc/func definition
  var bodyStmts: seq[PNode] = @[]
  if fnAst.isNil:
    link(state, entryId, state.exitId)
  else:
    case fnAst.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef, nkMacroDef, nkTemplateDef:
      # PNode children: [name, params, returnType?, body/pragmas]
      if fnAst.kind notin LeafPNodeKinds:
        for child in fnAst:
          if child.isNil: continue
          if child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
            bodyStmts = collectStatementsP(child)
            break
    else:
      # Treat as raw statement list
      bodyStmts = collectStatementsP(fnAst)

    if bodyStmts.len > 0:
      let finalId = buildCfgFromStatementListP(state, bodyStmts, entryId, state.exitId)
      if finalId >= 0:
        link(state, finalId, state.exitId)
    else:
      link(state, entryId, state.exitId)

  result.entry = entryId
  result.exit = state.exitId
  result.blocks = state.blocks
  for b in state.blocks:
    result.blockById[b.id] = b

## Find Loop Headers.
func findLoopHeaders*(cfg: ControlFlowGraph): seq[int] {.raises: [].} =
  for b in cfg.blocks:
    if b.loopHeader:
      result.add(b.id)

## Find Back Edges.
func findBackEdges*(cfg: ControlFlowGraph): seq[(int, int)] {.raises: [], axiom: ["(assert (and (>= (seq.len cfg_blocks) 0) (and (>= cfg_entry -9223372036854775808) (<= cfg_entry 9223372036854775807)) (and (>= cfg_exit -9223372036854775808) (<= cfg_exit 9223372036854775807))))", "cfg_blocks.size ≥ 0 ∧ cfg_entry ≥ -9223372036854775808 ∧ cfg_entry ≤ 9223372036854775807 ∧ cfg_exit ≥ -9223372036854775808 ∧ cfg_exit ≤ 9223372036854775807"].} =
  for b in cfg.blocks:
    for src in b.loopBackEdgeFrom:
      result.add((src, b.id))

{.pop.}  # closes noSideEffect

proc buildControlFlowGraph*(sourceCode: string): Result[ControlFlowGraph, string] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Parses Nim source code via Nim compiler AST and builds CFG for the first
  ## function declaration found. Returns err if parsing fails or no function
  ## is present.
  let ast = parseStringAST(sourceCode)
  if ast.isNil:
    return err("failed to parse source code")
  if ast.kind notin LeafPNodeKinds:
    for node in ast:
      if node.isNil: continue
      case node.kind
      of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef, nkMacroDef, nkTemplateDef:
        return ok(buildCfgFromAstP(node))
      else:
        discard
  result = err("no function declaration found in source")

## Find Primary Loop Header.
func findPrimaryLoopHeader*(cfg: ControlFlowGraph): int {.raises: [].} =
  ## Returns the first loop header block ID, or -1 if none exist.
  let headers = findLoopHeaders(cfg)
  result = if headers.len > 0: headers[0] else: -1

{.pop.}  # closes raises: []
