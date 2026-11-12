import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/strutils
import std/sets
import compiler/ast
import core/parsers/pnode_nav
import ../../core/trusted/axiom_pragmas

## Match Infix Pattern (PNode).
func matchInfixPattern*(node: PNode; leftPat: string; op: string; rightPat: string): bool  {.axiomDecision.} =
  if node.isNil or node.kind != nkInfix:
    return false
  if node.len < 3: return false
  let operatorNode = node[1]
  if operatorNode.isNil: return false
  if pNodeText(operatorNode) != op:
    return false
  let leftNode = node[0]
  let rightNode = node[2]
  if leftNode.isNil or rightNode.isNil:
    return false
  let leftText = pNodeText(leftNode)
  let rightText = pNodeText(rightNode)
  if leftPat.len > 0 and leftText != leftPat:
    return false
  if rightPat.len > 0 and rightText != rightPat:
    return false
  true

func collectAssertConditions*(fnNode: PNode): seq[PNode] =
  if fnNode.isNil: return
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nameText = pNodeText(callNode[0])
      if nameText == "doAssert":
        result.add(callNode)

## Collect If Conditions (PNode).
func collectIfConditions*(fnNode: PNode): seq[PNode] =
  if fnNode.isNil: return
  for ifNode in findNodesP(fnNode, {nkIfStmt}):
    for child in ifNode:
      if child.kind == nkOfBranch and child.len > 0 and not child[0].isNil:
        result.add(child[0])

## Has Assert Condition (PNode).
func hasAssertCondition*(fnNode: PNode; leftPat: string; op: string; rightPat: string): bool =
  if fnNode.isNil: return false
  for condition in collectAssertConditions(fnNode):
    if matchInfixPattern(condition, leftPat, op, rightPat):
      return true
  false

## Has If Condition (PNode).
func hasIfCondition*(fnNode: PNode; leftPat: string; op: string; rightPat: string): bool =
  if fnNode.isNil: return false
  for condition in collectIfConditions(fnNode):
    if matchInfixPattern(condition, leftPat, op, rightPat):
      return true
  false

## Has Identifier Named (PNode).
  ## axiom-smt: (assert ast_parse_failed_isolated)
  ## axiom-lean: ast_parse_failed_isolated
func hasIdentifierNamed*(ast: PNode; name: string): bool {.axiomTryImpl.} =
  if ast.isNil: return false
  for idNode in findNodesP(ast, {nkIdent}):
    if idNode.ident.s == name:
      return true
  false

## Has Call To (PNode).
func hasCallTo*(ast: PNode; procName: string): bool =
  if ast.isNil: return false
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nameText = pNodeText(callNode[0])
      if nameText == procName:
        return true
  false

## Has Assignment To (PNode).
func hasAssignmentTo*(ast: PNode; targetName: string): bool =
  if ast.isNil: return false
  let target = targetName.toLowerAscii()
  for asgnNode in findNodesP(ast, {nkAsgn}):
    if asgnNode.len > 0 and not asgnNode[0].isNil:
      if pNodeText(asgnNode[0]).toLowerAscii() == target:
        return true
  for typeDef in findNodesP(ast, {nkTypeDef}):
    for ident in findNodesP(typeDef, {nkIdent}):
      if pNodeText(ident).toLowerAscii() == target:
        return true
  for paramDef in findNodesP(ast, {nkIdentDefs}):
    if paramDef.len > 0 and paramDef[0].kind == nkIdent:
      if pNodeText(paramDef[0]).toLowerAscii() == target:
        return true
  false

## Has Type With Fields (PNode).
func hasTypeWithFields*(ast: PNode; fieldNames: openArray[string]): bool =
  if ast.isNil: return false
  if fieldNames.len == 0: return true
  var requiredFields: HashSet[string] = initHashSet[string]()
  for name in fieldNames:
    requiredFields.incl(name.toLowerAscii())
  for typeDef in findNodesP(ast, {nkTypeDef}):
    var foundFields: HashSet[string] = initHashSet[string]()
    for identDef in findNodesP(typeDef, {nkIdentDefs}):
      if identDef.len > 0 and identDef[0].kind == nkIdent:
        let fieldName = pNodeText(identDef[0])
        foundFields.incl(fieldName.toLowerAscii())
    var allFound = true
    for name in requiredFields:
      if name notin foundFields:
        allFound = false
        break
    if allFound:
      return true
  false

## Has Pragma Named (PNode).
func hasPragmaNamed*(ast: PNode; pragmaName: string): bool =
  if ast.isNil: return false
  for pragmaNode in findNodesP(ast, {nkPragma}):
    let pragmaText = pNodeText(pragmaNode).toLowerAscii()
    if pragmaText.contains(pragmaName.toLowerAscii()):
      return true
  false

## Has Infix Operator (PNode).
func hasInfixOperator*(ast: PNode; op: string): bool =
  if ast.isNil: return false
  let target = op.toLowerAscii()
  for infixNode in findNodesP(ast, {nkInfix}):
    if infixNode.len > 1 and not infixNode[1].isNil:
      let opText = pNodeText(infixNode[1]).toLowerAscii()
      if opText == target:
        return true
  false

## Has Raise Or Quit (PNode).
func hasRaiseOrQuit*(fnNode: PNode): bool =
  if fnNode.isNil: return false
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let name = pNodeText(callNode[0]).toLowerAscii()
      if name in ["raise", "quit", "doassert", "assert"]:
        return true
  for raiseStmt in findNodesP(fnNode, {nkRaiseStmt}):
    return true
  false

{.pop.}
