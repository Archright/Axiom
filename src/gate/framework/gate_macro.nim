import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/macros
import std/strutils

type
  GateStatus* = enum
    Pass
    Fail
    Error

  GateResult* = object
    status*: GateStatus
    message*: string

proc isAlwaysPassReturn(node: NimNode): bool {.compileTime.} =
  case node.kind:
  of nnkIdent, nnkSym:
    if $node in ["Pass", "true", "True"]:
      return true
  of nnkObjConstr, nnkCall, nnkCommand:
    if node.len >= 1 and $node[0] == "GateResult":
      for i in 1..<node.len:
        let field = node[i]
        if field.kind == nnkExprColonExpr and $field[0] == "status":
          if $field[1] in ["Pass", "true", "True"]:
            return true
  else:
    discard
  return false

proc scanNode(node: NimNode) {.compileTime.} =
  case node.kind:
  of nnkExceptBranch:
    let body = node[^1]
    if body.kind == nnkDiscardStmt:
      error("Forbidden: except block contains discard — errors must be handled properly", node)
    if body.kind == nnkStmtList:
      if body.len == 0:
        error("Forbidden: empty except block — errors must be handled properly", node)
      for stmt in body:
        if stmt.kind == nnkDiscardStmt:
          error("Forbidden: except block contains discard — errors must be handled properly", node)
        if stmt.kind == nnkReturnStmt and stmt.len >= 1:
          if isAlwaysPassReturn(stmt[0]):
            error("Forbidden: except block always-returns Pass/true — must report failure", node)
        if stmt.kind in {nnkIdent, nnkSym} and $stmt in ["Pass", "true", "True"]:
          error("Forbidden: except block yields Pass/true — must report failure", node)
    if body.kind == nnkReturnStmt and body.len >= 1:
      if isAlwaysPassReturn(body[0]):
        error("Forbidden: except block always-returns Pass/true — must report failure", node)
  of nnkCast:
    error("Forbidden: cast expression in gate body — use proper type conversions", node)
  of nnkStrLit:
    let litVal = $node
    if litVal.contains("(assert true)"):
      error("Forbidden: string literal containing '(assert true)' — vacuous proof marker", node)
  else:
    discard
  for child in node:
    scanNode(child)

macro gate*(name: untyped, body: untyped): untyped =
  scanNode(body)
  result = quote do:
    proc `name`(): GateResult =
      try:
        `body`
      except CatchableError as e:
        return GateResult(status: GateStatus.Error, message: e.msg)

{.pop.}
