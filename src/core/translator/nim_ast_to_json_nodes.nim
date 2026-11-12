import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/json
import std/options
import std/strutils

import compiler/ast

import core/types/results
import core/parser_utils
import core/parsers/pnode_nav
import core/translator/universal_mapper_part1

const
  IoFunctionNames = [
    "readFile", "writeFile", "execCmd", "execCmdEx",
    "startProcess", "startProcessEx", "socket", "recv", "send", "connect",
    "fetch", "network", "stdin", "readLine", "read_line",
    "httpClient", "httpGet", "httpPost"
  ]

  ## Leaf/literal nodes carry no children — iterating sons raises a Defect.
  ## Same invariant B4-A enforced in cfg_builder.nim and pnode_nav.nim.
  ## nkIdent/nkSym/nkEmpty are additionally excluded here because the
  ## TNode variant object stores no `sons` for them (compiler/ast.nim).
  ## nkRStrLit belongs here for the same reason as nkStrLit: its payload lives in
  ## `strVal`, not in `sons`.  It was missing, so a raw string literal reached
  ## the statement collector's fallback arm and `stmt.len` raised FieldDefect
  ## there — a crash on the first subject that contained one.
  LiteralPNodeKinds = {nkNone, nkEmpty, nkIdent, nkSym,
                nkCharLit, nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit, nkCommentStmt}

func extractIdentifierText(node: PNode): string {.raises: [].} =
  if node.isNil: return ""
  if node.kind == nkIdent:
    return node.ident.s.strip()
  elif node.kind == nkSym:
    return node.sym.name.s.strip()
  for i in 0 ..< node.len:
    let child = node[i]
    if not child.isNil:
      let text = extractIdentifierText(child)
      if text.len > 0:
        return text
  ""

func extractOperatorText(node: PNode): string {.raises: [].} =
  ## For nkInfix, operator is node[0].
  if node.kind == nkInfix and node.len > 0 and not node[0].isNil:
    return pNodeText(node[0]).strip()
  ""

func extractFieldNode(node: PNode; fieldName: string): Option[PNode] {.raises: [].} =
  ## Map PNode children by semantic field name.
  if node.isNil: return none(PNode)
  case node.kind
  of nkInfix:
    if fieldName == "operator" and node.len > 1 and not node[1].isNil: return some(node[1])
    elif fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "right" and node.len > 2 and not node[2].isNil: return some(node[2])
  of nkBracketExpr:
    if fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "right" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkCall, nkCommand, nkCallStrLit:
    if fieldName == "function" and node.len > 0 and not node[0].isNil: return some(node[0])
  of nkDotExpr:
    if fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "right" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkPrefix:
    if fieldName == "operator" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "operand" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkAsgn:
    if fieldName == "left" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "right" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkIfStmt:
    # Children: [0]=condition, [1]=consequence, [2..]=elif/else branches
    if fieldName == "condition" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "consequence" and node.len > 1 and not node[1].isNil: return some(node[1])
    elif fieldName == "alternative":
      for i in countdown(node.len - 1, 2):
        if not node[i].isNil and node[i].kind == nkElse:
          return some(node[i])
      return none(PNode)
  of nkElifBranch:
    # Children: [0]=condition, [1]=consequence
    if fieldName == "condition" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "consequence" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkElse:
    # Child: [0]=consequence
    if fieldName == "consequence" and node.len > 0 and not node[0].isNil: return some(node[0])
  of nkForStmt:
    # Children: [0]=iterator var(s), [1]=iterable expression, [2]=body
    if fieldName == "iterable" and node.len > 1 and not node[1].isNil: return some(node[1])
    elif fieldName == "body" and node.len > 2 and not node[2].isNil: return some(node[2])
  of nkWhileStmt:
    # Children: [0]=condition, [1]=body
    if fieldName == "condition" and node.len > 0 and not node[0].isNil: return some(node[0])
    elif fieldName == "body" and node.len > 1 and not node[1].isNil: return some(node[1])
  of nkVarSection, nkLetSection, nkConstSection:
    # Each child is nkIdentDefs: [0]=symbols, [1]=type(opt), [2]=value(opt)
    if fieldName == "symbol" and node.len > 0:
      for i in 0 ..< node.len:
        let child = node[i]
        if not child.isNil and child.kind == nkIdentDefs:
          if child.len > 0 and not child[0].isNil:
            return some(child[0])
    elif fieldName == "value" and node.len > 0:
      for i in 0 ..< node.len:
        let child = node[i]
        if not child.isNil and child.kind == nkIdentDefs:
          if child.len > 2 and not child[2].isNil:
            return some(child[2])
  of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef, nkMacroDef, nkTemplateDef:
    # Body is the last statement-like child after params (index 0).
    if fieldName == "body":
      for i in countdown(node.len - 1, 1):
        if not node[i].isNil and node[i].kind in {nkStmtList, nkBlockStmt, nkBlockExpr, nkDiscardStmt}:
          return some(node[i])
  else:
    # Default: search for body/consequence, or fall back to positional left/right.
    if fieldName == "body" or fieldName == "consequence":
      for i in 0 ..< node.len:
        let child = node[i]
        if not child.isNil and child.kind in {nkStmtList, nkBlockStmt, nkBlockExpr}:
          return some(child)
    if fieldName == "left" and node.len > 0 and not node[0].isNil:
      return some(node[0])
    if fieldName == "right" and node.len > 1 and not node[1].isNil:
      return some(node[1])

func buildSimpleExpr(node: PNode): string {.raises: [].} =
  ## Build a simplified expression string from a PNode AST node.
  ## Used for SMT/Lean symbol generation -- does not need to be
  ## syntactically valid Nim, just a stable identifier.
  if node.isNil: return ""
  case node.kind
  of nkIdent, nkSym:
    return pNodeText(node).strip()
  of nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
     nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit:
    return pNodeText(node).strip()
  of nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit:
    return pNodeText(node).strip()
  of nkStrLit, nkTripleStrLit:
    return "str_" & sanitizeSymbol(pNodeText(node))
  of nkCharLit:
    return pNodeText(node).strip()
  of nkInfix:
    let leftNode = extractFieldNode(node, "left")
    let opNode = extractFieldNode(node, "operator")
    let rightNode = extractFieldNode(node, "right")
    let leftText = if leftNode.isSome(): buildSimpleExpr(leftNode.get()) else: ""
    let opText = if opNode.isSome(): pNodeText(opNode.get()).strip() else: ""
    let rightText = if rightNode.isSome(): buildSimpleExpr(rightNode.get()) else: ""
    if leftText.len > 0 and rightText.len > 0:
      return leftText & "_" & sanitizeSymbol(opText) & "_" & rightText
    if leftText.len > 0:
      return leftText
    if rightText.len > 0:
      return rightText
    return "expr"
  of nkBracketExpr:
    let leftNode = extractFieldNode(node, "left")
    discard extractFieldNode(node, "right")
    let base = if leftNode.isSome(): buildSimpleExpr(leftNode.get()) else: "arr"
    return base
  of nkCall, nkCommand, nkCallStrLit:
    if node.len > 0 and not node[0].isNil:
      return buildSimpleExpr(node[0])
    return "call"
  of nkDotExpr:
    let leftNode = extractFieldNode(node, "left")
    let rightNode = extractFieldNode(node, "right")
    let leftText = if leftNode.isSome(): buildSimpleExpr(leftNode.get()) else: ""
    let rightText = if rightNode.isSome(): buildSimpleExpr(rightNode.get()) else: ""
    if leftText.len > 0 and rightText.len > 0:
      return leftText & "_" & rightText
    if leftText.len > 0:
      return leftText
    if rightText.len > 0:
      return rightText
    return "dot"
  of nkPrefix:
    let opNode = extractFieldNode(node, "operator")
    let operandNode = extractFieldNode(node, "operand")
    let opText = if opNode.isSome(): pNodeText(opNode.get()).strip() else: ""
    let operandText = if operandNode.isSome(): buildSimpleExpr(operandNode.get()) else: ""
    if opText.len > 0 and operandText.len > 0:
      return sanitizeSymbol(opText) & "_" & operandText
    if operandText.len > 0:
      return operandText
    return "prefix"
  of nkNilLit:
    return "nil"
  else:
    return sanitizeSymbol(pNodeText(node).strip())

func inferOpFromRight(rightNode: PNode): string {.raises: [].} =
  if rightNode.isNil:
    return "assign"
  case rightNode.kind
  of nkInfix:
    let opText = extractOperatorText(rightNode)
    case opText
    of "+": return "add"
    of "-": return "sub"
    of "*": return "mul"
    of "/", "div": return "div"
    of "%", "mod": return "mod"
    else: return "assign"
  else:
    return "assign"

func isIoCall(node: PNode): bool {.raises: [].} =
  ## Determine if a call node invokes an I/O function.
  if node.isNil: return false
  if node.kind notin {nkCall, nkCommand, nkCallStrLit}:
    return false
  let funcNode = extractFieldNode(node, "function")
  if funcNode.isNone():
    return false
  let funcText = buildSimpleExpr(funcNode.get())
  for name in IoFunctionNames:
    if funcText == name:
      return true
  return false

func buildAssignJson(target, left, op, right: string): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = newJString("assign")
  result["target"] = newJString(sanitizeSymbol(target))
  result["left"] = newJString(sanitizeSymbol(left))
  result["op"] = newJString(op)
  result["right"] = newJString(sanitizeSymbol(right))

func buildIfJson(condition: string): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = newJString("if")
  result["condition"] = newJString(sanitizeSymbol(condition))

func buildLoopJson(condition: string): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = newJString("loop")
  result["condition"] = newJString(sanitizeSymbol(condition))

func buildMemoryReadJson(base, index: string): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = newJString("memory_read")
  result["base"] = newJString(sanitizeSymbol(base))
  result["index"] = newJString(sanitizeSymbol(index))
  result["length"] = newJString(sanitizeSymbol(base) & "_len")

func buildExternalInputJson(source, target: string): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = newJString("external_input")
  result["source"] = newJString(sanitizeSymbol(source))
  result["target"] = newJString(sanitizeSymbol(target))

func collectNodesFromStatement(
  stmt: PNode;
  resultNodes: var seq[JsonNode];
  enclosingTarget: string = ""
) {.raises: [].} =
  ## Recursively collect JSON nodes from a single PNode statement node.
  ## `enclosingTarget` is the LHS variable of the enclosing assignment
  ## or declaration, used to tag I/O call results.
  if stmt.isNil:
    return
  if stmt.kind in LiteralPNodeKinds:
    return

  case stmt.kind
  of nkAsgn:
    let leftNode = extractFieldNode(stmt, "left")
    let rightNode = extractFieldNode(stmt, "right")
    if leftNode.isNone() or rightNode.isNone():
      return
    let target = buildSimpleExpr(leftNode.get())
    let left = target
    let op = inferOpFromRight(rightNode.get())
    let right = buildSimpleExpr(rightNode.get())
    resultNodes.add(buildAssignJson(target, left, op, right))
    collectNodesFromStatement(rightNode.get(), resultNodes, target)

  of nkVarSection, nkLetSection, nkConstSection:
    for identDefs in findNodesP(stmt, {nkIdentDefs}):
      let valueNode = extractFieldNode(identDefs, "value")
      if valueNode.isNone():
        continue
      let symNode = extractFieldNode(identDefs, "symbol")
      if symNode.isNone():
        continue
      let target = extractIdentifierText(symNode.get())
      let op = inferOpFromRight(valueNode.get())
      let right = buildSimpleExpr(valueNode.get())
      resultNodes.add(buildAssignJson(target, target, op, right))
      collectNodesFromStatement(valueNode.get(), resultNodes, target)

  of nkIfStmt:
    let condNode = extractFieldNode(stmt, "condition")
    if condNode.isSome():
      let condText = buildSimpleExpr(condNode.get())
      if condText.len > 0:
        resultNodes.add(buildIfJson(condText))
    let consNode = extractFieldNode(stmt, "consequence")
    if consNode.isSome():
      for i in 0 ..< consNode.get().len:
        let child = consNode.get()[i]
        if not child.isNil:
          collectNodesFromStatement(child, resultNodes, enclosingTarget)
    let altNode = extractFieldNode(stmt, "alternative")
    if altNode.isSome():
      for i in 0 ..< altNode.get().len:
        let child = altNode.get()[i]
        if not child.isNil:
          collectNodesFromStatement(child, resultNodes, enclosingTarget)

  of nkForStmt:
    let iterableNode = extractFieldNode(stmt, "iterable")
    if iterableNode.isSome():
      let guardText = buildSimpleExpr(iterableNode.get())
      if guardText.len > 0:
        resultNodes.add(buildLoopJson(guardText))
    let bodyNode = extractFieldNode(stmt, "body")
    if bodyNode.isSome():
      for i in 0 ..< bodyNode.get().len:
        let child = bodyNode.get()[i]
        if not child.isNil:
          collectNodesFromStatement(child, resultNodes, enclosingTarget)

  of nkWhileStmt:
    let condNode = extractFieldNode(stmt, "condition")
    if condNode.isSome():
      let condText = buildSimpleExpr(condNode.get())
      if condText.len > 0:
        resultNodes.add(buildLoopJson(condText))
    let bodyNode = extractFieldNode(stmt, "body")
    if bodyNode.isSome():
      for i in 0 ..< bodyNode.get().len:
        let child = bodyNode.get()[i]
        if not child.isNil:
          collectNodesFromStatement(child, resultNodes, enclosingTarget)

  of nkBracketExpr:
    let leftNode = extractFieldNode(stmt, "left")
    let rightNode = extractFieldNode(stmt, "right")
    let base = if leftNode.isSome(): buildSimpleExpr(leftNode.get()) else: "arr"
    let idx = if rightNode.isSome(): buildSimpleExpr(rightNode.get()) else: "idx"
    resultNodes.add(buildMemoryReadJson(base, idx))

  of nkCall, nkCommand, nkCallStrLit:
    if isIoCall(stmt):
      let funcNode = extractFieldNode(stmt, "function")
      let source = if funcNode.isSome(): buildSimpleExpr(funcNode.get()) else: "io"
      let target = if enclosingTarget.len > 0: enclosingTarget else: "call_result"
      resultNodes.add(buildExternalInputJson(source, target))
    for i in 1 ..< stmt.len:
      let arg = stmt[i]
      if not arg.isNil:
        collectNodesFromStatement(arg, resultNodes, enclosingTarget)

  of nkStmtList:
    for i in 0 ..< stmt.len:
      let child = stmt[i]
      if not child.isNil:
        collectNodesFromStatement(child, resultNodes, enclosingTarget)

  of nkInfix, nkPrefix, nkDotExpr:
    for i in 0 ..< stmt.len:
      let child = stmt[i]
      if not child.isNil:
        collectNodesFromStatement(child, resultNodes, enclosingTarget)

  else:
    # Same invariant the dispatch above relies on: an atom kind has no `sons`,
    # so `stmt.len` raises FieldDefect there.  The guard at the top of this proc
    # already returns for every kind in LiteralPNodeKinds; repeating the test
    # here means a kind added to the set cannot silently reintroduce the crash
    # through the fallback arm.
    if stmt.kind notin LiteralPNodeKinds:
      for i in 0 ..< stmt.len:
        let child = stmt[i]
        if not child.isNil:
          collectNodesFromStatement(child, resultNodes, enclosingTarget)

func findFunctionDeclaration(ast: PNode; functionName: string): Option[PNode] =
  ## Find a function/procedure definition by name using pnode_nav.
  findFunctionNodeP(ast, functionName)

proc sourceCodeToJsonNodes*(sourceCode, functionName: string): JsonNode =
  ## Parse Nim source code via Nim compiler parser and convert the named function's
  ## body into the JSON node schema expected by `mapAstJsonToUniversalTranslation`.
  ##
  ## Returns a JArray of objects, each with at minimum a `"kind"` field.
  ## On parse failure or if the function is not found, returns an empty array.
  result = newJArray()

  let astRes = parseNimRes(sourceCode)
  if astRes.isErr():
    return

  let ast = astRes.get()
  let funcDecl = findFunctionDeclaration(ast, functionName)
  if funcDecl.isNone():
    return

  let bodyNode = extractFieldNode(funcDecl.get(), "body")
  if bodyNode.isNone():
    return

  var nodes: seq[JsonNode] = @[]
  for i in 0 ..< bodyNode.get().len:
    let child = bodyNode.get()[i]
    if not child.isNil:
      collectNodesFromStatement(child, nodes)

  for node in nodes:
    result.add(node)

{.pop.}
