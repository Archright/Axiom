
import core/trusted/layer_declaration
axiomLayer "gate"
{.push, raises: [].}
import
  compiler / [ast, idents]

import
  gate / architecture_ast_facts

import
  gate / nimtry / nimtry_extract_types

import
  gate / nimtry / nimtry_extract_part1

from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect
import core/ast_kernel

func effectiveSourceSloc*(n: PNode): int {.raises: [].} =
  ## Effective source-origin SLOC: distinct source lines containing at least one
  ## effective source-origin syntax unit (comments/synthetic/source-less excluded).
  ## v6 PNode effective-source-span engine replaces the old
  ## text-based countEffectiveSLOC (see docs/spec/effective_sloc.md).
  result = effectiveSlocFromSpans(extractEffectiveSourceSpans(n))

func extractImportsV4*(root: PNode; path: string): seq[ImportFact] {.raises: [].} =
  var acc: seq[ImportFact] = @[]
  proc walk(n: PNode) =
    if n.isNil:
      return
    case n.kind
    of nkImportStmt:
      var i = 0
      while i < n.safeLen:
        let modulePath = collectImportPath(n[i])
        if modulePath.len > 0:
          acc.add(ImportFact(modulePath: modulePath, symbols: @[], location: SourceLocation(
              path: path, line: n[i].info.line.int,
              column: n[i].info.col.int + 1)))
        inc i
    of nkFromStmt:
      if n.safeLen >= 1:
        let modulePath = collectImportPath(n[0])
        if modulePath.len > 0:
          var symbols: seq[string] = @[]
          var j = 1
          while j < n.safeLen:
            let sym = extractName(n[j])
            if sym.len > 0:
              symbols.add(sym)
            inc j
          acc.add(ImportFact(modulePath: modulePath, symbols: symbols, location: SourceLocation(
              path: path, line: n[0].info.line.int,
              column: n[0].info.col.int + 1)))
    of nkImportExceptStmt:
      if n.safeLen >= 1:
        let modulePath = collectImportPath(n[0])
        if modulePath.len > 0:
          acc.add(ImportFact(modulePath: modulePath, symbols: @[], location: SourceLocation(
              path: path, line: n[0].info.line.int,
              column: n[0].info.col.int + 1)))
    of nkIncludeStmt:
      var i = 0
      while i < n.safeLen:
        let modulePath = collectImportPath(n[i])
        if modulePath.len > 0:
          acc.add(ImportFact(modulePath: modulePath, symbols: @[], location: SourceLocation(
              path: path, line: n[i].info.line.int,
              column: n[i].info.col.int + 1)))
        inc i
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

proc extractFunctionsV4*(root: PNode; path: string; st: SymbolTable; source: string): seq[
    FunctionFact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  proc maxLineInTree(n: PNode): int {.raises: [].} =
    ## Find the maximum source line number in a PNode subtree.
    if n.isNil:
      return 0
    result = n.info.line.int
    var i = 0
    while i < n.safeLen:
      let childLine = maxLineInTree(n[i])
      if childLine > result:
        result = childLine
      inc i

  var acc: seq[FunctionFact] = @[]
  proc walk(n: PNode) =
    if n.isNil:
      return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef:
      if n.safeLen < 7:
        return
      let body = n[6]
      if body.isNil or body.kind == nkEmpty:
        return
      let nameNode = n[0]
      let exported = isExportMarker(nameNode)
      let name = extractName(nameNode)
      if name.len == 0:
        return
      let refs = collectIdents(body)
      let count = recNodeCount(body)
      let cfp = fingerprintNode(canonicalizeNode(body))
      let startLine = n.info.line.int
      let endLine = maxLineInTree(n)
      let dk = case n.kind
      of nkProcDef:
        fdkProc
      of nkFuncDef:
        fdkFunc
      of nkMethodDef:
        fdkMethod
      else:
        fdkProc
      let formalParams = n[3]
      let retType = if formalParams.safeLen >= 1:
        nodeToString(formalParams[0])
      else:
        ""
      var paramList: seq[ParamInfo]
      for i in 1 ..< formalParams.safeLen:
        let idDef = formalParams[i]
        let pType = if idDef.safeLen >= 2:
          nodeToString(idDef[^2])
        else:
          ""
        for j in 0 ..< idDef.safeLen - 2:
          paramList.add(ParamInfo(name: extractName(idDef[j]), paramType: pType))
      let physicalSpan = endLine - startLine + 1
      let effectiveLines = effectiveSourceSloc(n)
      acc.add(FunctionFact(name: name, exported: exported, declKind: dk,
                           normalizedAstFingerprint: cfp, alphaFingerprint: cfp,
                           nodeCount: count, lineCount: physicalSpan,
                           physicalSpan: physicalSpan,
                           effectiveSLOC: effectiveLines,
                           variableRefs: refs, params: paramList,
                           returnType: retType, location: SourceLocation(
             path: path, line: startLine, column: n.info.col.int + 1)))
    of nkIteratorDef:
      if n.safeLen < 7:
        return
      let body = n[6]
      if body.isNil or body.kind == nkEmpty:
        return
      let name = extractName(n[0])
      if name.len == 0:
        return
      let refs = collectIdents(body)
      let count = recNodeCount(body)
      let cfp = fingerprintNode(canonicalizeNode(body))
      let startLine = n.info.line.int
      let endLine = maxLineInTree(n)
      let iterFormalParams = n[3]
      let iterRetType = if iterFormalParams.safeLen >= 1:
        nodeToString(iterFormalParams[0])
      else:
        ""
      var iterParamList: seq[ParamInfo]
      for i in 1 ..< iterFormalParams.safeLen:
        let idDef = iterFormalParams[i]
        let pType = if idDef.safeLen >= 2:
          nodeToString(idDef[^2])
        else:
          ""
        for j in 0 ..< idDef.safeLen - 2:
          iterParamList.add(ParamInfo(name: extractName(idDef[j]),
                                      paramType: pType))
      let physicalSpan = endLine - startLine + 1
      let effectiveLines = effectiveSourceSloc(n)
      acc.add(FunctionFact(name: name, exported: isExportMarker(n[0]),
                           declKind: fdkProc, normalizedAstFingerprint: cfp,
                           alphaFingerprint: cfp, nodeCount: count,
                           lineCount: physicalSpan,
                           physicalSpan: physicalSpan,
                           effectiveSLOC: effectiveLines,
                           variableRefs: refs, params: iterParamList,
                           returnType: iterRetType, location: SourceLocation(
                               path: path, line: startLine, column: n.info.col.int + 1)))
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

func extractCallsV4*(root: PNode; path: string; st: SymbolTable): seq[CallFact] {.
    raises: [].} =
  var acc: seq[CallFact] = @[]
  proc walk(n: PNode) =
    if n.isNil:
      return
    case n.kind
    of nkCall, nkCommand, nkCallStrLit:
      if n.safeLen >= 1:
        let callee = calleeName(n[0])
        let qualified = qualifiedCalleeRec(n[0])
        if callee.len > 0:
          acc.add(CallFact(callee: callee, qualifiedCallee: qualified, location: SourceLocation(
              path: path, line: n.info.line.int, column: n.info.col.int + 1)))
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

func extractAssignmentsV4*(root: PNode; path: string): tuple[
    assignments: seq[AssignmentFact]; divisions: seq[DivisionFact]] {.
    raises: [].} =
  proc targetToString(n: PNode): string {.raises: [].} =
    if n.isNil:
      return ""
    case n.kind
    of nkIdent:
      n.ident.s
    of nkSym:
      n.sym.name.s
    of nkDotExpr:
      if n.safeLen >= 2:
        targetToString(n[0]) & "." & targetToString(n[1])
      elif n.safeLen == 1:
        targetToString(n[0])
      else:
        ""
    of nkBracketExpr:
      if n.safeLen >= 2:
        targetToString(n[0]) & "[" & targetToString(n[1]) & "]"
      elif n.safeLen == 1:
        targetToString(n[0])
      else:
        ""
    of nkAccQuoted:
      if n.safeLen >= 1:
        targetToString(n[0])
      else:
        ""
    of nkHiddenDeref, nkDerefExpr:
      if n.safeLen >= 1:
        targetToString(n[0]) & "[]"
      else:
        ""
    of nkCheckedFieldExpr:
      if n.safeLen >= 2:
        targetToString(n[0]) & "." & targetToString(n[1])
      else:
        ""
    else:
      nodeToString(n)

  var acc: seq[AssignmentFact] = @[]
  var divAcc: seq[DivisionFact] = @[]
  proc captureDef(m: PNode; operator: string) {.raises: [].} =
    ## Capture a single binding (nkIdentDefs / nkVarTuple) as an AssignmentFact.
    if m.isNil:
      return
    case m.kind
    of nkConstDef:
      # Const definitions wrap their nkIdentDefs child — unwrap so const
      # bindings are captured (FACADE-ratchet false-positive fix).
      if m.safeLen >= 1:
        captureDef(m[0], operator)
    of nkIdentDefs:
      if m.safeLen >= 3:
        let target = targetToString(m[0])
        let rhs = nodeToString(m[2])
        if target.len > 0 and rhs.len > 0:
          acc.add(AssignmentFact(targetPath: target, rhsExpr: rhs,
                                 operator: operator, location: SourceLocation(
              path: path, line: m.info.line.int, column: m.info.col.int + 1)))
    of nkVarTuple:
      if m.safeLen >= 2:
        let rhs = nodeToString(m[^1])
        if rhs.len > 0:
          acc.add(AssignmentFact(targetPath: targetToString(m[0]), rhsExpr: rhs,
                                 operator: operator, location: SourceLocation(
              path: path, line: m.info.line.int, column: m.info.col.int + 1)))
    else:
      discard
  proc walk(n: PNode; insideFactory: bool = false) =
    if n.isNil:
      return
    case n.kind
    of nkImportStmt, nkFromStmt, nkImportExceptStmt, nkIncludeStmt:
      # Module path separators (`/`) in import statements are not divisions.
      return
    of nkAsgn:
      if n.safeLen >= 2:
        let target = targetToString(n[0])
        let rhs = nodeToString(n[1])
        if target.len > 0:
          acc.add(AssignmentFact(targetPath: target, rhsExpr: rhs,
                                 operator: "=", location: SourceLocation(
              path: path, line: n.info.line.int, column: n.info.col.int + 1)))
    of nkLetSection, nkVarSection:
      var i = 0
      while i < n.safeLen:
        captureDef(n[i], "let")
        inc i
    of nkConstSection:
      # Const bindings are real code (e.g., toolchain_config SSOT, judge
      # constants, gateway endpoint tables) — without this branch, const-only
      # modules were misclassified as forwarding stubs by the FACADE-ratchet.
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkConstDef and child.safeLen >= 1:
          # Nim wraps const bindings in nkConstDef(name, type, value).
          # Record the binding name + rhs so const-only modules are not
          # treated as forwarding stubs.
          let target = targetToString(child[0])
          let rhs = if child.safeLen >= 3: nodeToString(child[2])
                    elif child.safeLen >= 2: nodeToString(child[1])
                    else: ""
          if target.len > 0 and rhs.len > 0:
            acc.add(AssignmentFact(targetPath: target, rhsExpr: rhs,
                                   operator: "const", location: SourceLocation(
                path: path, line: child.info.line.int, column: child.info.col.int + 1)))
        else:
          captureDef(child, "const")
        inc i
    of nkCall, nkCommand:
      # Recurse into callee arguments; if the callee is a ratio factory,
      # mark the subtree so divisions inside its arguments are exempt.
      var childFactory = insideFactory
      if n.safeLen > 0:
        let callee = calleeName(n[0])
        if callee == "initAsiRatio" or callee == "initKernelRatio":
          childFactory = true
      var i = 0
      while i < n.safeLen:
        walk(n[i], childFactory)
        inc i
      return
    of nkInfix:
      # Division candidate: operator is "/" (node at index 0 in nkInfix).
      if n.safeLen >= 3 and not insideFactory:
        let op = n[0]
        let opName = if not op.isNil:
          extractName(op)
        else:
          ""
        if opName == "/":
          divAcc.add(DivisionFact(lhs: nodeToString(n[1]), rhs: nodeToString(n[2]),
                                  text: nodeToString(n), insideFactory: insideFactory,
                                  location: SourceLocation(
              path: path, line: n.info.line.int, column: n.info.col.int + 1)))
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i], insideFactory)
      inc i

  walk(root)
  result = (assignments: acc, divisions: divAcc)

func extractTypeDefsV4*(root: PNode; path: string): seq[TypeDefFact] {.
    raises: [].} =
  var acc: seq[TypeDefFact] = @[]
  proc walk(n: PNode) =
    if n.isNil:
      return
    case n.kind
    of nkTypeSection:
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkTypeDef and child.safeLen >= 1:
          let typeName = extractName(child[0])
          let exported = isExportMarker(child[0])
          if typeName.len > 0:
            acc.add(TypeDefFact(name: typeName, exported: exported, location: SourceLocation(
                path: path, line: child.info.line.int,
                column: child.info.col.int + 1)))
        inc i
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

func extractConstStringsV4*(root: PNode; path: string): seq[ConstStringFact] {.
    raises: [].} =
  ## Extract const string literals from nkConstSection nodes.
  var acc: seq[ConstStringFact] = @[]
  proc collectStringLiteral(m: PNode): seq[string] =
    if m.isNil:
      return
    case m.kind
    of nkStrLit .. nkTripleStrLit:
      if m.strVal.len > 0 and m.strVal.len <= 40:
        result.add(m.strVal)
    else:
      var i = 0
      while i < m.safeLen:
        for s in collectStringLiteral(m[i]):
          result.add(s)
        inc i

  proc walk(n: PNode) =
    if n.isNil:
      return
    case n.kind
    of nkConstSection:
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkIdentDefs and child.safeLen >= 1:
          let constName = extractName(child[0])
          if constName.len > 0 and child.safeLen >= 3:
            for literal in collectStringLiteral(child[2]):
              acc.add(ConstStringFact(value: literal, name: constName, location: SourceLocation(
                  path: path, line: child.info.line.int,
                  column: child.info.col.int + 1)))
        inc i
    else:
      discard
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

{.pop.}
