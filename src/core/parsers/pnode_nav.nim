{.push raises: [].}
## pnode_nav.nim — PNode navigation helpers for tree-sitter purge Phase 5.2
## Provides PNode-based nav/collect/pred functions (post-XmlNode era).
## Built on top of compiler/ast; tested against Nim 2.2.10.

import core/trusted/axiom_pragmas_lite
import compiler/[ast, idents]
import std/[options, tables, strutils, sets]

# ── PNode kind sets (NKind enum values confirmed working in Nim 2.2.10) ────
const
  ProcDefKinds* = {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef,
                   nkConverterDef, nkMacroDef, nkTemplateDef}
  DeclarationSectionKinds* = {nkVarSection, nkLetSection, nkConstSection, nkTypeSection}

# ── PNode recursive search ────────────────────────────────────────

func findNodesP*(root: PNode; testKind: set[TNodeKind]): seq[PNode] =
  ## Recursively collect all descendant nodes matching given NKind set.
  if root.isNil: return
  if root.kind in testKind:
    result.add(root)
  if not root.isNil:
    for child in root:
      if not child.isNil:
        result.add(findNodesP(child, testKind))

func findFirstNodeP*(root: PNode; testKind: set[TNodeKind]): Option[PNode]  {.axiomDecision.} =
  ## Find first descendant matching given NKind set (depth-first).
  if root.isNil: return none(PNode)
  if root.kind in testKind:
    return some(root)
  if not root.isNil:
    for child in root:
      if not child.isNil:
        let found = findFirstNodeP(child, testKind)
        if found.isSome:
          return found
  none(PNode)

# ── PNode child elements ────────────────────────────────────────

func childElements*(node: PNode): seq[PNode] =
  ## Return non-nil children of a PNode (PNode equivalent of nav.childElements).
  result = @[]
  if node.isNil: return
  for i in 0 ..< node.len:
    if not node[i].isNil:
      result.add(node[i])

# ── PNode nodeText helpers ────────────────────────────────────────

func pNodeText*(node: PNode): string =
  ## Extract text content from a PNode (compat with legacy XmlNode.nodeText).
  if node.isNil: return ""
  case node.kind
  of nkIdent:
    result = node.ident.s
  of nkSym:
    result = node.sym.name.s
  of nkStrLit, nkTripleStrLit:
    result = node.strVal
  of nkCharLit:
    # Char literals store their codepoint in intVal, not strVal (TNode layout).
    result = $chr(int(node.intVal))
  of nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit, nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit:
    result = $node.intVal
  of nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit:
    result = $node.floatVal
  else:
    # Leaf/literal nodes have no children — iterating sons raises Defect.
    if node.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                       nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                       nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                       nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                       nkNone}:
      discard
    else:
      for child in node:
        if not child.isNil:
          result.add(pNodeText(child))

func innerText*(node: PNode): string =
  pNodeText(node)

## PNode-compatible nodeText overload (compat with legacy XmlNode API)
func nodeText*(node: PNode): string =
  pNodeText(node)

# ── PNode line offset table ────────────────────────────────────────

func lineStartOffsets*(s: string): seq[int] {.raises: [].} =
  result.add(0)
  var i = 0
  while i < s.len:
    if s[i] == '\n':
      result.add(i + 1)
    inc i

func sourceSlice*(sourceCode: string; srow, scol, erow, ecol: int): Option[string] {.raises: [], axiomDecision.} =
  if srow < 0 or scol < 0 or erow < 0 or ecol < 0:
    return none(string)
  let offsets = lineStartOffsets(sourceCode)
  if srow >= offsets.len or erow >= offsets.len:
    return none(string)
  let startOffset = offsets[srow] + scol
  let endOffset = min(offsets[erow] + ecol, sourceCode.len)
  if endOffset <= startOffset:
    return none(string)
  some(sourceCode[startOffset ..< endOffset])

# ── PNode field access helpers ────────────────────────────────────

func nodeFieldP*(node: PNode; fieldName: string): Option[PNode]  {.axiomDecision.} =
  ## Find child node by field name pattern.
  if node.isNil: return none(PNode)
  case node.kind
  of nkExprColonExpr:
    if fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "right" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkInfix:
    if fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "operator" and node.len > 1 and not node[1].isNil: return some(node[1])
    elif fieldName == "right" and node.len > 2 and not node[2].isNil: return some(node[2])
  of nkPrefix:
    if fieldName == "operand" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkCall:
    if fieldName == "function" and node.len > 0 and not node[0].isNil: return some(node[0])
  else:
    # Leaf/literal nodes have no children — iterating sons raises Defect.
    if node.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                     nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                     nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                     nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                     nkNone}:
      discard
    elif fieldName == "body" or fieldName == "consequence":
      for child in node:
        if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
          return some(child)
    if fieldName == "left" and node.len > 0 and not node[0].isNil:
      return some(node[0])
    if fieldName == "right" and node.len > 1 and not node[1].isNil:
      return some(node[1])

# ── PNode function discovery ──────────────────────────────────────

func findFunctionNodeP*(ast: PNode; functionName: string): Option[PNode]  {.axiomDecision.} =
  if ast.isNil: return none(PNode)
  let target = functionName.strip().toLowerAscii()
  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome:
        let nm = if nameNodeOpt.get.kind == nkIdent:
                    nameNodeOpt.get.ident.s
                  elif nameNodeOpt.get.kind == nkSym:
                    nameNodeOpt.get.sym.name.s
                  else:
                    ""
        if nm.strip().toLowerAscii() == target:
          return some(node)
  none(PNode)

func indexFunctionNodesP*(ast: PNode): Table[string, PNode] =
  if ast.isNil: return
  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome:
        let nm = if nameNodeOpt.get.kind == nkIdent:
                    nameNodeOpt.get.ident.s
                  elif nameNodeOpt.get.kind == nkSym:
                    nameNodeOpt.get.sym.name.s
                  else:
                    ""
        if nm.len > 0:
          result[nm] = node

# ── PNode predicate helpers ───────────────────────────────────────

func hasIdentifierNamedP*(ast: PNode; name: string): bool =
  if ast.isNil: return false
  let target = name.toLowerAscii()
  for idNode in findNodesP(ast, {nkIdent}):
    if idNode.ident.s.toLowerAscii() == target:
      return true
  false

func hasCallToP*(ast: PNode; procName: string): bool =
  if ast.isNil: return false
  let target = procName.toLowerAscii()
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let funcName = callNode[0].ident.s.toLowerAscii()
      if funcName == target:
        return true
  false

func hasPragmaNamedP*(ast: PNode; pragmaName: string): bool =
  if ast.isNil: return false
  for pragmaNode in findNodesP(ast, {nkPragma}):
    let pragmaText = pNodeText(pragmaNode).toLowerAscii()
    if pragmaText.contains(pragmaName.toLowerAscii()):
      return true
  false

func hasInfixOperatorP*(ast: PNode; op: string): bool =
  if ast.isNil: return false
  let target = op.toLowerAscii()
  for infixNode in findNodesP(ast, {nkInfix}):
    if infixNode.len > 1 and not infixNode[1].isNil:
      let opText = pNodeText(infixNode[1]).toLowerAscii()
      if opText == target:
        return true
  false

# ── PNode extraction helpers ──────────────────────────────────────

type
  FunctionDef* = object
    name*: string
    params*: seq[tuple[name, nimType: string]]
    returnType*: string
    bodyNode*: PNode

func extractFunctionDefsFromAstP*(ast: PNode): seq[FunctionDef] =
  if ast.isNil: return
  for node in findNodesP(ast, ProcDefKinds):
    var fd: FunctionDef
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome:
        fd.name = if nameNodeOpt.get.kind == nkIdent:
                    nameNodeOpt.get.ident.s
                  elif nameNodeOpt.get.kind == nkSym:
                    nameNodeOpt.get.sym.name.s
                  else:
                    ""
    if fd.name.len == 0: continue
    for paramNode in findNodesP(node, {nkIdentDefs}):
      var paramName = ""
      var paramType = ""
      if paramNode.len > 0 and not paramNode[0].isNil:
        paramName = paramNode[0].ident.s
      if paramNode.len > 1 and not paramNode[1].isNil:
        paramType = pNodeText(paramNode[1])
      if paramName.len > 0:
        fd.params.add((name: paramName, nimType: paramType))
    for child in node:
      if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
        fd.bodyNode = child
        break
    result.add(fd)

func extractAssignmentsP*(node: PNode): seq[tuple[varName, expr: string]] =
  if node.isNil: return
  case node.kind
  of nkExprColonExpr:
    var lhs = ""
    var rhs = ""
    if node.len > 0 and not node[0].isNil: lhs = pNodeText(node[0])
    if node.len > 1 and not node[1].isNil: rhs = pNodeText(node[1])
    if lhs.len > 0 and rhs.len > 0:
      result.add((varName: lhs, expr: rhs))
  else: discard
  if not node.isNil:
    # Leaf/literal nodes have no children — iterating sons raises Defect.
    if node.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                       nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                       nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                       nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                       nkNone}:
      discard
    else:
      for child in node:
        if not child.isNil:
          result.add(extractAssignmentsP(child))

# ── Tree-sitter compatibility constants ────────────────────────────

const
  declarationTags* = [
    "proc_declaration", "func_declaration", "method_declaration",
    "iterator_declaration", "converter_declaration",
    "macro_declaration", "template_declaration"
  ]

# ── PNode call identifier collection ────────────────────────────────

func collectCallIdentifiersP*(fnNode: PNode): seq[string] =
  ## Collect all call identifiers from a PNode (PNode equivalent of legacy XmlNode API).
  if fnNode.isNil: return
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nameNode = callNode[0]
      if nameNode.kind in {nkIdent, nkSym}:
        let nm = if nameNode.kind == nkIdent:
                   nameNode.ident.s
                 else:
                   nameNode.sym.name.s
        if nm.len > 0:
          result.add(nm)
  # Also check nkPrefix calls (e.g., `^x`)
  for prefixNode in findNodesP(fnNode, {nkPrefix}):
    if prefixNode.len > 0 and not prefixNode[0].isNil:
      let nameNode = prefixNode[0]
      if nameNode.kind in {nkIdent, nkSym}:
        let nm = if nameNode.kind == nkIdent:
                   nameNode.ident.s
                 else:
                   nameNode.sym.name.s
        if nm.len > 0:
          result.add(nm)

# ── PNode dot expression collection ────────────────────────────────

func collectDotExpressionsP*(fnNode: PNode): seq[string] =
  ## Collect base names from dot expressions (a.b.c → "a") (PNode equivalent of legacy XmlNode API).
  if fnNode.isNil: return
  for dotNode in findNodesP(fnNode, {nkDotExpr}):
    if dotNode.len > 0 and not dotNode[0].isNil:
      let base = dotNode[0]
      if base.kind == nkIdent:
        let nm = base.ident.s
        if nm.len > 0:
          result.add(nm)
      elif base.kind == nkDotExpr:
        # Nested dot expr: a.b.c — get the leftmost base
        var n = base
        while n.len > 0 and not n[0].isNil and n[0].kind == nkDotExpr:
          n = n[0]
        if n[0].kind == nkIdent:
          let nm = n[0].ident.s
          if nm.len > 0:
            result.add(nm)

# ── PNode assertion/if condition collection (equivalent to pred.nim) ───

func collectAssertConditionsP*(ast: PNode): seq[PNode] =
  ## Collect all doAssert call nodes from the AST.
  ## PNode equivalent of legacy XmlNode-based collectAssertConditions in pred.nim.
  if ast.isNil: return
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let funcName = pNodeText(callNode[0])
      if funcName == "doAssert":
        result.add(callNode)

func collectIfConditionsP*(ast: PNode): seq[PNode] =
  ## Collect all if-statement conditions from the AST.
  ## Handles both nkIfStmt (statement if) and nkIfExpr (inline if).
  ## PNode equivalent of legacy XmlNode-based collectIfConditions in pred.nim.
  if ast.isNil: return
  for ifNode in findNodesP(ast, {nkIfStmt}):
    for child in ifNode:
      if child.kind == nkOfBranch and child.len > 0 and not child[0].isNil:
        result.add(child[0])
  for ifExpr in findNodesP(ast, {nkIfExpr}):
    if ifExpr.len > 0 and not ifExpr[0].isNil:
      result.add(ifExpr[0])

func hasAssignmentToP*(ast: PNode; targetName: string): bool =
  ## Check if AST contains assignment to the given target name.
  ## PNode equivalent of legacy XmlNode-based hasAssignmentTo in pred.nim.
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
    if paramDef.len > 0 and not paramDef[0].isNil:
      if paramDef[0].kind == nkIdent and pNodeText(paramDef[0]).toLowerAscii() == target:
        return true
  false

func hasTypeWithFieldsP*(ast: PNode; fieldNames: openArray[string]): bool =
  ## Check if AST contains a type declaration with all specified field names.
  ## PNode equivalent of legacy XmlNode-based hasTypeWithFields in pred.nim.
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

func hasRaiseOrQuitP*(ast: PNode): bool =
  ## Check if AST contains raise, quit, doAssert, or assert calls.
  ## PNode equivalent of legacy XmlNode-based hasRaiseOrQuit in pred.nim.
  if ast.isNil: return false
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let name = pNodeText(callNode[0]).toLowerAscii()
      if name in ["raise", "quit", "doassert", "assert"]:
        return true
  for raiseStmt in findNodesP(ast, {nkRaiseStmt}):
    return true
  false

func assignmentLhsP*(assignNode: PNode): Option[PNode]  {.axiomDecision.} =
  ## Get the left-hand side of an assignment node.
  ## PNode equivalent of legacy XmlNode-based assignmentLhs in collect.nim.
  if assignNode.isNil: return none(PNode)
  case assignNode.kind
  of nkAsgn:
    if assignNode.len > 0 and not assignNode[0].isNil:
      return some(assignNode[0])
  of nkInfix, nkPrefix, nkPostfix:
    discard
  else:
    if assignNode.len > 0 and not assignNode[0].isNil:
      return some(assignNode[0])
  none(PNode)

func collectLocalVariablesP*(fnNode: PNode): HashSet[string] =
  ## Collect local variable names from declarations, parameters, and loops.
  ## PNode equivalent of legacy XmlNode-based collectLocalVariables in collect.nim.
  if fnNode.isNil: return
  let targetKinds: set[TNodeKind] = {nkIdentDefs, nkVarSection, nkLetSection}
  for identDef in findNodesP(fnNode, targetKinds):
    if identDef.len > 0 and identDef[0].kind == nkIdent:
      result.incl(identDef[0].ident.s)
  for paramDef in findNodesP(fnNode, {nkIdentDefs}):
    # Parameter definitions at proc level
    if paramDef.len > 0 and paramDef[0].kind == nkIdent:
      result.incl(paramDef[0].ident.s)
  for forStmt in findNodesP(fnNode, {nkForStmt}):
    if forStmt.len > 1 and not forStmt[1].isNil and forStmt[1].kind == nkIdent:
      result.incl(forStmt[1].ident.s)

func collectMutatedResourcesP*(fnNode: PNode; moduleGlobals: HashSet[string]): seq[string] =
  ## Collect names of global variables that are mutated (assigned to) in the function.
  ## PNode equivalent of legacy XmlNode-based collectMutatedResources in collect.nim.
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

func classifyModuleAstP*(ast: PNode): tuple[hasConcrete: bool; hasAbstract: bool] =
  ## PNode-based equivalent of legacy XmlNode-based classifyModuleAst in lean.nim.
  ## Classifies a module as concrete (object types with pure/final) or abstract.
  if ast.isNil: return
  let targetKinds: set[TNodeKind] = {nkTypeDef}
  for typeDef in findNodesP(ast, targetKinds):
    for pragmaNode in findNodesP(typeDef, {nkPragma}):
      let pragmaText = pNodeText(pragmaNode).toLowerAscii()
      if pragmaText.contains("{.pure.}") or pragmaText.contains("{.final.}"):
        result.hasConcrete = true
      if pragmaText.contains("{.inheritable.}") or pragmaText.contains("{.abstract.}"):
        result.hasAbstract = true

# ─── String-tagged PNode navigation (tree-sitter compat layer) ──────────
  ## These provide tag strings for PNode navigation (compat with legacy XmlNode API).

func tagToKinds*(tag: string): set[TNodeKind] =
  case tag
  of "call": result = {nkCall}
  of "identifier": result = {nkIdent, nkSym}
  of "infix_expression": result = {nkInfix}
  of "operator": result = {nkIdent, nkSym}
  of "pragma": result = {nkPragma}
  of "for_statement": result = {nkForStmt}
  of "if_statement": result = {nkIfStmt}
  of "case_statement": result = {nkCaseStmt}
  of "case_branch": result = {nkOfBranch}
  of "guard": result = {nkOfBranch}
  of "while_statement": result = {nkWhileStmt}
  of "assignment": result = {nkAsgn}
  of "parameter_declaration_list", "parameter_declaration": result = {nkIdentDefs}
  of "proc_declaration", "func_declaration": result = ProcDefKinds
  else: discard

func findNodes*(root: PNode; tag: string): seq[PNode] =
  ## PNode-compatible findNodes using string tags (compat with legacy XmlNode API).
  if root.isNil: return
  let kinds = tagToKinds(tag)
  if kinds.len > 0 and root.kind in kinds:
    result.add(root)
  for child in root:
    if not child.isNil:
      result.add(findNodes(child, tag))

func findNodes*(root: PNode; tag: string; excludeTags: openArray[string]): seq[PNode] =
  ## PNode-compatible findNodes with exclusion list (compat with legacy XmlNode API).
  if root.isNil: return
  let kinds = tagToKinds(tag)
  var skipSubtree = false
  if kinds.len > 0 and root.kind in kinds:
    result.add(root)
  if tag in excludeTags:
    skipSubtree = true
  for child in root:
    if not child.isNil and not skipSubtree:
      result.add(findNodes(child, tag, excludeTags))

func findFirstNode*(root: PNode; tag: string): Option[PNode]  {.axiomDecision.} =
  ## PNode-compatible findFirstNode using string tags (compat with legacy XmlNode API).
  if root.isNil: return none(PNode)
  let kinds = tagToKinds(tag)
  if kinds.len > 0 and root.kind in kinds:
    return some(root)
  for child in root:
    if not child.isNil:
      let found = findFirstNode(child, tag)
      if found.isSome:
        return found
  none(PNode)

func findFunctionNode*(ast: PNode; functionName: string): Option[PNode]  {.axiomDecision.} =
  ## PNode-compatible findFunctionNode (compat with legacy XmlNode API).
  if ast.isNil: return none(PNode)
  let target = functionName.strip().toLowerAscii()
  for node in findNodesP(ast, ProcDefKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome:
        let nm = if nameNodeOpt.get.kind == nkIdent:
                    nameNodeOpt.get.ident.s
                  elif nameNodeOpt.get.kind == nkSym:
                    nameNodeOpt.get.sym.name.s
                  else:
                    ""
        if nm.strip().toLowerAscii() == target:
          return some(node)
  none(PNode)


# ── PNode Construction Helpers ──

proc newNode*(k: TNodeKind; children: openArray[PNode] = @[]): PNode =
  result = newNode(k)
  for c in children: addSonNilAllowed(result, c)

proc newIdent*(s: string): PNode =
  ## Create an identifier PNode using a minimal approach.
  ## Uses newNode with nkIdent kind and stores the name in strVal.
  result = newNode(nkIdent)
  result.strVal = s

func newStrLit*(s: string): PNode =
  result = newNode(nkStrLit)
  result.strVal = s

proc newInt64Lit*(v: int64): PNode =
  result = newNode(nkInt64Lit)
  result.intVal = v

proc newFloat64Lit*(v: float64): PNode =
  result = newNode(nkFloat64Lit)
  result.floatVal = v


func isPNodeElement*(node: PNode): bool =
  ## Check if a PNode represents a structural element (not a leaf value).
  if node.isNil: return false
  case node.kind
  of nkIdent, nkSym, nkStrLit, nkCharLit, nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
     nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
     nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
     nkNilLit, nkEmpty, nkHiddenAddr:
    return false
  else:
    return true

func pNodeTag*(node: PNode): string =
  ## Get a string representation of a PNode's kind (for tree-sitter compat).
  if node.isNil: return ""
  $node.kind

