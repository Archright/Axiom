import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/options
import std/sets
import std/strutils
import compiler/ast
import core/parsers/pnode_nav
import ../../core/trusted/axiom_pragmas

func collectCallIdentifiers*(fnNode: PNode): seq[string] =
  if fnNode.isNil: return
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nameText = pNodeText(callNode[0])
      if nameText.len > 0:
        result.add(nameText)

## Collect Dot Expressions.
func collectDotExpressions*(fnNode: PNode): seq[string] =
  if fnNode.isNil: return
  for dotNode in findNodesP(fnNode, {nkDotExpr}):
    if dotNode.len > 0 and not dotNode[0].isNil:
      let base = dotNode[0]
      if base.kind == nkIdent:
        let nm = base.ident.s
        if nm.len > 0:
          result.add(nm)
      elif base.kind == nkDotExpr:
        var n = base
        while n.len > 0 and not n[0].isNil and n[0].kind == nkDotExpr:
          n = n[0]
        if n[0].kind == nkIdent:
          let nm = n[0].ident.s
          if nm.len > 0:
            result.add(nm)

## Assignment Lhs (PNode).
  ## axiom-smt: (assert ast_parse_failed_isolated)
  ## axiom-lean: ast_parse_failed_isolated
func assignmentLhs*(assignNode: PNode): Option[PNode] {.axiomTryImpl.} =
  if assignNode.isNil: return none(PNode)
  case assignNode.kind
  of nkAsgn:
    if assignNode.len > 0 and not assignNode[0].isNil:
      return some(assignNode[0])
  else:
    discard
  none(PNode)

## Collect Local Variables (PNode).
func collectLocalVariables*(fnNode: PNode): HashSet[string] =
  if fnNode.isNil: return
  let targetKinds: set[TNodeKind] = {nkIdentDefs, nkVarSection, nkLetSection}
  for identDef in findNodesP(fnNode, targetKinds):
    if identDef.len > 0 and identDef[0].kind == nkIdent:
      result.incl(identDef[0].ident.s)
  for forStmt in findNodesP(fnNode, {nkForStmt}):
    if forStmt.len > 1 and not forStmt[1].isNil and forStmt[1].kind == nkIdent:
      result.incl(forStmt[1].ident.s)

## Collect Mutated Resources (PNode).
func collectMutatedResources*(fnNode: PNode; moduleGlobals: HashSet[string]): seq[string] =
  if fnNode.isNil: return
  for asgnNode in findNodesP(fnNode, {nkAsgn}):
    if asgnNode.len > 0 and not asgnNode[0].isNil:
      let lhsText = pNodeText(asgnNode[0])
      if lhsText.len > 0:
        let parts = lhsText.split('.')
        if parts.len > 1:
          let baseName = parts[0]
          if baseName in moduleGlobals:
            result.add(lhsText)
        elif lhsText in moduleGlobals:
          result.add(lhsText)

## Classify Module Ast.

{.pop.}
