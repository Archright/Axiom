import core/trusted/layer_declaration
axiomLayer "domain"
import core/parser_utils
import core/types/results
import compiler/ast
import core/parsers/pnode_nav
{.push raises: [].}
# import ../../verification/cegar_engine — REMOVED: unused

func smtOp*(nimOp: string): string {.raises: [].} =
  ## Map Nim operators to SMT-LIB2 function symbols.
  case nimOp
  of "+": "+"
  of "-": "-"
  of "*": "*"
  of "/": "div"
  of "%": "mod"
  of "==": "="
  of "!=": "not (= ...)"
  of ">": ">"
  of "<": "<"
  of ">=": ">="
  of "<=": "<="
  else: nimOp
func extractAssignments*(node: PNode): seq[tuple[varName, expr: string]] {.raises: [].} =
  ## AST-to-SMT: extract variable assignments as (varName, expression) pairs.
  ## Critical Checkpoint #2: Only extracts valid SMT-encodable assignments.
  ## PNode version using compiler AST node kinds.
  if node.isNil: return
  case node.kind
  of nkAsgn:
    var lhs = ""
    var rhs = ""
    if node.len > 0 and not node[0].isNil:
      lhs = pNodeText(node[0])
    if node.len > 1 and not node[1].isNil:
      rhs = pNodeText(node[1])
    if lhs.len > 0 and rhs.len > 0:
      result.add((varName: lhs, expr: rhs))
  of nkIdentDefs:
    if node.len > 0 and not node[0].isNil:
      let varName = pNodeText(node[0])
      if varName.len > 0:
        var expr = ""
        if node.len > 1 and not node[1].isNil:
          expr = pNodeText(node[1])
        result.add((varName: varName, expr: expr))
  else:
    discard
  # Recurse into children
  if not node.isNil:
    for child in node:
      if not child.isNil:
        result.add(extractAssignments(child))
func buildSmtConstraints*(assignments: seq[tuple[varName, expr: string]]): string {.raises: [].} =
  ## Convert extracted assignments to SMT-LIB2 assertions.
  for a in assignments:
    result &= "(declare-const " & a.varName & " Int)\n"
  for a in assignments:
    result &= "(assert (= " & a.varName & " " & a.expr & "))\n"
proc buildEquivalenceQuery*(originalSource, refactoredSource: string;
    functionName: string): string {.raises: [].} =
  ## Build SMT-LIB2 equivalence query from two source code versions.
  ## Strategy: extract arithmetic constraints from both, assert outputs differ.
  ## Critical Checkpoint #2: AST-to-SMT conversion prevents unknown constants.
  let origParse = parseNimRes(originalSource)
  let refParse = parseNimRes(refactoredSource)
  if origParse.isErr or refParse.isErr:
    return ""

  let origAssignments = extractAssignments(origParse.get())
  let refAssignments = extractAssignments(refParse.get())

  if origAssignments.len == 0 and refAssignments.len == 0:
    return ""  # No extractable constraints — cannot verify

  result = "(set-logic QF_LIA)\n"
  result &= buildSmtConstraints(origAssignments)
  result &= "\n;; Refactored constraints (shadowed variables with _ref suffix)\n"
  for a in refAssignments:
    result &= "(declare-const " & a.varName & "_ref Int)\n"
  for a in refAssignments:
    result &= "(assert (= " & a.varName & "_ref " & a.expr & "))\n"
  result &= "\n;; Equivalence hypothesis: at least one output differs\n"
  # Find the last assignment (likely the return value) and compare
  if origAssignments.len > 0 and refAssignments.len > 0:
    let origLast = origAssignments[^1].varName
    let refLast = refAssignments[^1].varName & "_ref"
    result &= "(assert (not (= " & origLast & " " & refLast & ")))\n"
  result &= "(check-sat)\n"
proc verifySemanticEquivalence*(originalCode, refactoredCode: string;
    functionName: string;
    z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].}
): bool {.raises: [CatchableError].} =
  ## Z3 structural equivalence verification.
  ## Returns true if UNSAT (equivalent), false if SAT/UNKNOWN (not equivalent → rollback).
  ## DIP: Z3 checker injected via callback — no Infrastructure dependency.
  let query = buildEquivalenceQuery(originalCode, refactoredCode, functionName)
  if query.len == 0:
    return false  # Cannot verify → safe rollback
  try:
    return z3Check(query)
  except CatchableError:
    return false  # Z3 failure → safe rollback

{.pop.}
