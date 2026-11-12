import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/strutils
import std/sets
import std/tables
import std/options
import std/sequtils
import compiler/ast
import core/contract/contract_types as ct
import core/encoding/smt_atom_generator as satom
import core/contract/contract_text_extractor as ctxt
import core/encoding/type_logic_registry as tlr
import core/parsers/pnode_nav
import core/parser_utils
import core/trusted/axiom_pragmas

# ─── Rule Registry (PNode-native) ────────────────────────────────────────
##
## Each extraction rule is an independent proc that accumulates into shared
## preAcc/postAcc with deduplication via seen: HashSet[string].
## Monadic accumulation: all rules run, first-match-wins is replaced.

func rule1DotExpressionLenP(fnNode: PNode; ctx: ct.ExtractionContext;
                            preAcc: var seq[string]; postAcc: var seq[string];
                            seen: var HashSet[string]) =
  ## Rule 1: dot_expression with .len → precondition
  for dotNode in findNodesP(fnNode, {nkDotExpr}):
    if dotNode.len >= 2 and not dotNode[0].isNil and not dotNode[^1].isNil:
      let rightText = pNodeText(dotNode[^1])
      if rightText == "len":
        let base = dotNode[0]
        var target = ""
        if base.kind == nkIdent:
          target = base.ident.s
        elif base.kind == nkDotExpr and base.len > 0 and not base[0].isNil:
          # Nested dot expr: a.b.len — get leftmost base
          var n = base
          while n.len > 0 and not n[0].isNil and n[0].kind == nkDotExpr:
            n = n[0]
          if n[0].kind == nkIdent:
            target = n[0].ident.s
        if target.len > 0 and "." notin target:
          var isStr = ctxt.isStringContext("", target)
          if not isStr and ctx.paramTypes.hasKey(target):
            let typ = ctx.paramTypes.getOrDefault(target, "")
            if typ in ["string", "str"]:
              isStr = true
          if isStr:
            ctxt.addPrecondition(preAcc, satom.smtStrLenPos(target), seen, ctx.paramNames)
          else:
            ctxt.addPrecondition(preAcc, satom.smtSeqLenPos(target), seen, ctx.paramNames)

func rule2BracketExpressionP(fnNode: PNode; ctx: ct.ExtractionContext;
                              preAcc: var seq[string]; postAcc: var seq[string];
                              seen: var HashSet[string]) =
  ## Rule 2: bracket_expression (indexing)
  for bracketNode in findNodesP(fnNode, {nkBracketExpr}):
    let idents = findNodesP(bracketNode, {nkIdent})
    if idents.len >= 1:
      let target = pNodeText(idents[0])
      var indexExpr = ""
      if bracketNode.len > 1 and not bracketNode[1].isNil:
        let argNode = bracketNode[1]
        if argNode.kind == nkIdent:
          indexExpr = argNode.ident.s
        elif argNode.kind == nkIntLit:
          indexExpr = $argNode.intVal
        else:
          indexExpr = pNodeText(argNode)
      if target.toLowerAscii() notin ct.smtTypeNames and indexExpr.len > 0:
        ctxt.addPrecondition(preAcc, satom.smtGteZero(indexExpr), seen, ctx.paramNames)
        if ctxt.isStringContext("", target):
          ctxt.addPrecondition(preAcc, satom.smtStrLtLen(indexExpr, target), seen, ctx.paramNames)
        else:
          ctxt.addPrecondition(preAcc, satom.smtLtLen(indexExpr, target), seen, ctx.paramNames)

func rule3DivisionNonZeroP(fnNode: PNode; ctx: ct.ExtractionContext;
                            preAcc: var seq[string]; postAcc: var seq[string];
                            seen: var HashSet[string]) =
  ## Rule 3: infix_expression with div or /
  for infixNode in findNodesP(fnNode, {nkInfix}):
    var opText = ""
    if infixNode.len > 1 and not infixNode[1].isNil:
      opText = pNodeText(infixNode[1])
    if opText in ["div", "/"]:
      if infixNode.len > 2 and not infixNode[2].isNil:
        let divisor = pNodeText(infixNode[2])
        if divisor.len > 0 and divisor != "0":
          ctxt.addPrecondition(preAcc, satom.smtNonZero(divisor), seen, ctx.paramNames)

func rule4ParameterDeclarationsP(fnNode: PNode; ctx: ct.ExtractionContext;
                                  preAcc: var seq[string]; postAcc: var seq[string];
                                  seen: var HashSet[string]) =
  ## Rule 4: parameter declarations with string/seq types
  for identDef in findNodesP(fnNode, {nkIdentDefs}):
    if identDef.len >= 2 and not identDef[0].isNil and not identDef[1].isNil:
      let name = pNodeText(identDef[0])
      let typ = pNodeText(identDef[1]).toLowerAscii()
      if typ in ["string", "str"]:
        ctxt.addPrecondition(preAcc, satom.smtStrLenPos(name), seen, ctx.paramNames)
      elif typ.startsWith("seq") or typ.startsWith("array") or typ.startsWith("openarray"):
        ctxt.addPrecondition(preAcc, satom.smtSeqLenPos(name), seen, ctx.paramNames)

func rule5DotExpressionHighLowP(fnNode: PNode; ctx: ct.ExtractionContext;
                                 preAcc: var seq[string]; postAcc: var seq[string];
                                 seen: var HashSet[string]) =
  ## Rule 5: dot_expression with .high or .low
  for dotNode in findNodesP(fnNode, {nkDotExpr}):
    if dotNode.len >= 2 and not dotNode[0].isNil and not dotNode[^1].isNil:
      let rightText = pNodeText(dotNode[^1])
      if rightText in ["high", "low"]:
        let base = dotNode[0]
        var target = ""
        if base.kind == nkIdent:
          target = base.ident.s
        elif base.kind == nkDotExpr and base.len > 0 and not base[0].isNil:
          var n = base
          while n.len > 0 and not n[0].isNil and n[0].kind == nkDotExpr:
            n = n[0]
          if n[0].kind == nkIdent:
            target = n[0].ident.s
        if target.len > 0:
          ctxt.addPrecondition(preAcc, satom.smtSeqLenPos(target), seen, ctx.paramNames)

func rule6IfStatementGteZeroP(fnNode: PNode; ctx: ct.ExtractionContext;
                               preAcc: var seq[string]; postAcc: var seq[string];
                               seen: var HashSet[string]) =
  ## Rule 6: if statement with >= 0 condition
  for ifNode in findNodesP(fnNode, {nkIfStmt}):
    for branch in ifNode:
      if branch.kind == nkOfBranch and branch.len > 0 and not branch[0].isNil:
        let cond = branch[0]
        if cond.kind == nkInfix and cond.len > 1 and not cond[1].isNil:
          let opText = pNodeText(cond[1])
          if opText == ">=":
            if cond.len > 2 and not cond[2].isNil:
              if pNodeText(cond[2]) == "0":
                if cond.len > 0 and not cond[0].isNil:
                  let expr = pNodeText(cond[0])
                  if expr.len > 0:
                    ctxt.addPrecondition(preAcc, satom.smtGteZero(expr), seen, ctx.paramNames)

proc rule7ResultAssignmentP(fnNode: PNode; ctx: ct.ExtractionContext;
                             preAcc: var seq[string]; postAcc: var seq[string];
                             seen: var HashSet[string]) =
  ## Rule 7: result = expr → POSTCONDITION (scope-aware)
  if ctx.inControlFlow: return
  let logic = lookupTypeLogic(ctx.returnType)
  if logic.ignorable:
    return
  for assignNode in findNodesP(fnNode, {nkAsgn}):
    if assignNode.len > 0 and not assignNode[0].isNil:
      let lhs = assignNode[0]
      if (lhs.kind == nkIdent and lhs.ident.s == "result") or
         (lhs.kind == nkSym and lhs.sym.name.s == "result"):
        var expr = "unknown"
        if assignNode.len > 1 and not assignNode[1].isNil:
          expr = pNodeText(assignNode[1])
        let postKey = "(= result " & expr & ")"
        if postKey notin seen:
          seen.incl(postKey)
          postAcc.add(postKey)
        if logic.resultConstraintTemplate.len > 0:
          let preKey = logic.resultConstraintTemplate
          if preKey notin seen:
            seen.incl(preKey)
            preAcc.add(preKey)

proc rule8NewWithResultP(fnNode: PNode; ctx: ct.ExtractionContext;
                          preAcc: var seq[string]; postAcc: var seq[string];
                          seen: var HashSet[string]) =
  ## Rule 8: call to 'new' with 'result' argument — object construction fallback
  if ctx.inControlFlow: return
  let logic = lookupTypeLogic(ctx.returnType)
  if logic.ignorable:
    return
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let funcName = pNodeText(callNode[0])
      if funcName == "new":
        for i in 1 ..< callNode.len:
          if not callNode[i].isNil:
            let argText = pNodeText(callNode[i])
            if argText == "result":
              let key = "(assert (or (= result.isOk true) (= result.isErr true)))"
              if key notin seen:
                seen.incl(key)
                preAcc.add(key)
              break

proc rule9ResultFieldAssignmentP(fnNode: PNode; ctx: ct.ExtractionContext;
                                  preAcc: var seq[string]; postAcc: var seq[string];
                                  seen: var HashSet[string]) =
  ## Rule 9: result.field = expr → POSTCONDITION (scope-aware)
  if ctx.inControlFlow: return
  let logic = lookupTypeLogic(ctx.returnType)
  if logic.ignorable:
    return
  for assignNode in findNodesP(fnNode, {nkAsgn}):
    if assignNode.len > 0 and not assignNode[0].isNil:
      let lhs = assignNode[0]
      if lhs.kind == nkDotExpr and lhs.len >= 2 and not lhs[0].isNil and not lhs[1].isNil:
        let base = lhs[0]
        let fieldNode = lhs[1]
        var baseText = ""
        var fieldText = ""
        if base.kind == nkIdent:
          baseText = base.ident.s
        elif base.kind == nkSym:
          baseText = base.sym.name.s
        if fieldNode.kind == nkIdent:
          fieldText = fieldNode.ident.s
        elif fieldNode.kind == nkSym:
          fieldText = fieldNode.sym.name.s
        if baseText == "result" and fieldText.len > 0:
          var val = "unknown"
          if assignNode.len > 1 and not assignNode[1].isNil:
            val = pNodeText(assignNode[1])
          let postKey = "(= (result." & fieldText & ") " & val & ")"
          if postKey notin seen:
            seen.incl(postKey)
            postAcc.add(postKey)
          if fieldText in ["kind", "isOk", "isErr"]:
            let preKey = "(assert (or (= result.isOk true) (= result.isErr true)))"
            if preKey notin seen:
              seen.incl(preKey)
              preAcc.add(preKey)

# ─── Main Pipeline (PNode-native) ────────────────────────────────────────

## AST-based extraction (PNode path)
proc extractContractFromAstP*(functionName: string; fnNode: PNode;
                              params: seq[(string, string)] = @[];
                              returnType: string = ""):
    ct.ExtractedContract {.raises: [].} =
  if fnNode.isNil:
    return ct.ExtractedContract()

  var ctx = ct.ExtractionContext(
    functionName: functionName,
    paramNames: initHashSet[string](),
    paramTypes: initTable[string, string](),
    returnType: returnType,
    scopeDepth: 0,
    inControlFlow: false
  )
  for p in params:
    ctx.paramNames.incl(p[0])
    ctx.paramTypes[p[0]] = p[1]

  var preAcc: seq[string] = @[]
  var postAcc: seq[string] = @[]
  var seen = initHashSet[string]()

  rule1DotExpressionLenP(fnNode, ctx, preAcc, postAcc, seen)
  rule2BracketExpressionP(fnNode, ctx, preAcc, postAcc, seen)
  rule3DivisionNonZeroP(fnNode, ctx, preAcc, postAcc, seen)
  rule4ParameterDeclarationsP(fnNode, ctx, preAcc, postAcc, seen)
  rule5DotExpressionHighLowP(fnNode, ctx, preAcc, postAcc, seen)
  rule6IfStatementGteZeroP(fnNode, ctx, preAcc, postAcc, seen)
  rule7ResultAssignmentP(fnNode, ctx, preAcc, postAcc, seen)
  rule8NewWithResultP(fnNode, ctx, preAcc, postAcc, seen)
  rule9ResultFieldAssignmentP(fnNode, ctx, preAcc, postAcc, seen)

  if isIgnorable(ctx.returnType):
    preAcc = preAcc.filterIt("result" notin it)
    postAcc = postAcc.filterIt("result" notin it)

  result.preconditions = preAcc
  result.postconditions = postAcc

## Forward declaration for helper defined below
proc tryExtractContractViaAst(functionName, body: string; params: seq[(string, string)];
                              returnType: string = ""): Option[ct.ExtractedContract]

## Public entry point: parses body text then delegates to PNode AST extraction
proc extractContractFromNimBody*(functionName, body: string; params: seq[(string, string)] = @[];
                                  returnType: string = ""): ct.ExtractedContract {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if body.len == 0:
    return ct.ExtractedContract()
  let astResult = tryExtractContractViaAst(functionName, body, params, returnType)
  if astResult.isSome:
    return astResult.get
  return ctxt.extractContractFromNimBodyText(functionName, body, params)

## AST-based heuristic scan for functions that are structurally impossible to verify via SMT.
## Detects: importc pragmas, external IO primitives, recursive calls.
# @axiom-hint: lean="fnNode != null ∧ functionName.length ≥ 0" smt="(assert (and fnNode (>= (str.len functionName) 0)))"
func scanAstForCertifiedExemptionP*(fnNode: PNode; functionName: string): bool {.raises: [].} =
  if fnNode.isNil or functionName.len == 0:
    return false

  # Pragma heuristic: {.importc.}, {.importcpp.}, {.dynlib.}, {.header.}, {.inline.}
  for pragmaNode in findNodesP(fnNode, {nkPragma}):
    let pragmaText = pNodeText(pragmaNode).toLowerAscii()
    if pragmaText.contains("importc") or pragmaText.contains("importcpp") or
       pragmaText.contains("dynlib") or pragmaText.contains("header"):
      return true
    if pragmaText.contains("inline") or pragmaText.contains("compiletime"):
      return true

  # Declaration kind heuristic: converter and template are compile-time constructs
  if fnNode.kind in ProcDefKinds:
    if fnNode.kind in {nkConverterDef, nkTemplateDef}:
      return true

  # Call heuristic: IO primitives and OS-level functions
  let ioPrimitives = toHashSet(["walkdir", "readfile", "writefile", "removefile",
                                 "socket", "connect", "recv", "send", "execprocess",
                                 "execcmd", "startprocess", "walkdirrec",
                                 "copyfile", "movefile", "createdir"])
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let callName = pNodeText(callNode[0]).toLowerAscii()
      if callName in ioPrimitives:
        return true

  # Recursive call heuristic: function calls itself inside its body
  let target = functionName.strip().toLowerAscii()
  for callNode in findNodesP(fnNode, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let callName = pNodeText(callNode[0]).toLowerAscii()
      if callName == target:
        return true

  false

{.pop.}

## Private helper: try AST-based extraction, return none on parse failure.
## Placed after the pragma pop to avoid try/except inside {.raises: [].} (nimtry SAFETY-no-try-in-no-raise).
proc tryExtractContractViaAst(functionName, body: string; params: seq[(string, string)];
                              returnType: string = ""): Option[ct.ExtractedContract] {.raises: [].} =
  let ast = parseStringAST(body)
  if ast.isNil:
    return none(ct.ExtractedContract)
  let fnNode = findFunctionNodeP(ast, functionName)
  if fnNode.isNone:
    return none(ct.ExtractedContract)
  let contract = extractContractFromAstP(functionName, fnNode.get, params, returnType)
  some(contract)
