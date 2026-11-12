import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Core-level AST inspection interface — types and pure utility procs.
## Types live in core, implementations (I/O-dependent) live in sieve.
## This enforces the layer boundary: sieve depends on core, not vice versa.
##
## Moved from sieve/ast_inspector.nim to resolve core→sieve dependency violation.
## All procs here are pure functions on PNode — no I/O, no side effects.

import compiler/ast
import core/parsers/pnode_nav
import std/strutils

type
  AstInspectionResult* = object
    loopCount*: int
    hasRecursion*: bool
    hasQuantifiers*: bool
    hasNonLinearOps*: bool
    nestedIfDepth*: int
    maxLoopNestingDepth*: int  ## Maximum nesting depth of loops (for k-induction depth estimation)
    dangerVariables*: seq[string]

# ─── PNode-native AST inspection (compiler/ast based) ──────────────────

func containsIdentifierP*(node: PNode; name: string): bool =
  ## Check if any identifier/symbol child matches the given name.
  if node.isNil: return false
  if node.kind in {nkIdent, nkSym}:
    let n = if node.kind == nkIdent: node.ident.s else: node.sym.name.s
    return n == name
  for child in node:
    if not child.isNil and containsIdentifierP(child, name):
      return true
  false

func countNestedIfP*(node: PNode): int =
  ## Count maximum nesting depth of if statements (nkIfStmt/nkIfExpr).
  if node.isNil: return 0
  var depth = 0
  if node.kind in {nkIfStmt, nkIfExpr}:
    depth = 1
    var maxChild = 0
    for child in node:
      if not child.isNil:
        maxChild = max(maxChild, countNestedIfP(child))
    depth += maxChild
  else:
    for child in node:
      if not child.isNil:
        depth = max(depth, countNestedIfP(child))
  return depth

func countNestedLoopsP*(node: PNode): int =
  ## Count maximum nesting depth of loops (while/for).
  if node.isNil: return 0
  var depth = 0
  if node.kind in {nkWhileStmt, nkForStmt}:
    depth = 1
    var maxChild = 0
    for child in node:
      if not child.isNil:
        maxChild = max(maxChild, countNestedLoopsP(child))
    depth += maxChild
  else:
    for child in node:
      if not child.isNil:
        depth = max(depth, countNestedLoopsP(child))
  return depth

func inspectAstNodeP*(node: PNode; funcName: string = "";
    unsatVars: seq[string] = @[]): AstInspectionResult =
  ## Single-pass PNode DFS — all structural risk patterns in one traversal.
  if node.isNil: return

  # 1. Loop detection
  if node.kind in {nkWhileStmt, nkForStmt}:
    result.loopCount += 1
    let loopNesting = countNestedLoopsP(node)
    if loopNesting > result.maxLoopNestingDepth:
      result.maxLoopNestingDepth = loopNesting
    for v in unsatVars:
      if containsIdentifierP(node, v):
        if v notin result.dangerVariables:
          result.dangerVariables.add(v)

  # 2. Recursion detection
  if node.kind == nkCall and funcName.len > 0:
    if node.len > 0 and not node[0].isNil:
      let callName = pNodeText(node[0])
      if callName == funcName:
        result.hasRecursion = true

  # 3. Non-linear arithmetic detection
  if node.kind == nkInfix:
    if node.len > 1 and not node[1].isNil:
      let op = pNodeText(node[1]).toLowerAscii()
      if op in ["*", "/", "%", "*=", "/="]:
        result.hasNonLinearOps = true

  # 4. Quantifier detection (forall/exist calls or special constructs)
  if node.kind in {nkCall, nkPrefix}:
    let nodeName = pNodeText(node)
    if "forall" in nodeName.toLowerAscii() or "exist" in nodeName.toLowerAscii():
      result.hasQuantifiers = true

  # 5. Deep conditional branching (if nesting >= 4)
  if node.kind in {nkIfStmt, nkIfExpr}:
    result.nestedIfDepth = max(result.nestedIfDepth, countNestedIfP(node))

  # 6. Child traversal
  for child in node:
    if not child.isNil:
      let childRes = inspectAstNodeP(child, funcName, unsatVars)
      result.loopCount += childRes.loopCount
      result.hasRecursion = result.hasRecursion or childRes.hasRecursion
      result.hasQuantifiers = result.hasQuantifiers or childRes.hasQuantifiers
      result.hasNonLinearOps = result.hasNonLinearOps or childRes.hasNonLinearOps
      result.nestedIfDepth = max(result.nestedIfDepth, childRes.nestedIfDepth)
      result.maxLoopNestingDepth = max(result.maxLoopNestingDepth, childRes.maxLoopNestingDepth)
      for v in childRes.dangerVariables:
        if v notin result.dangerVariables:
          result.dangerVariables.add(v)

{.pop.}

