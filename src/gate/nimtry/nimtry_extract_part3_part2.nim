import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import compiler/[ast, parser, options, llstream, idents, pathutils]
import gate/architecture_ast_facts
import gate/nimtry/nimtry_extract_part1
import gate/nimtry/nimtry_extract_part3_part1
from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect

func extractPragmasV4(root: PNode; path: string): seq[PragmaFact] {.raises: [].} =
  ## Extract pragmas from nkPragma nodes attached to declarations.

  var acc: seq[PragmaFact] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef:
      if n.safeLen >= 5:
        let target = extractName(n[0])
        if target.len > 0:
          let pragmas = n[4]
          if not pragmas.isNil and pragmas.kind == nkPragma:
            var j = 0
            while j < pragmas.safeLen:
              let pragmaNode = pragmas[j]
              var pragmaName = ""
              var pragmaValue = ""
              if pragmaNode.kind == nkExprColonExpr and pragmaNode.safeLen >= 2:
                pragmaName = extractName(pragmaNode[0])
                pragmaValue = nodeToString(pragmaNode[1])
              elif pragmaNode.kind == nkIdent:
                pragmaName = pragmaNode.ident.s
              elif pragmaNode.kind == nkCall and pragmaNode.safeLen >= 1:
                pragmaName = extractName(pragmaNode[0])
                pragmaValue = nodeToString(pragmaNode)
              if pragmaName.len > 0:
                acc.add(PragmaFact(
                  targetName: target,
                  pragmaName: pragmaName,
                  pragmaValue: pragmaValue,
                  location: SourceLocation(
                    path: path,
                    line: pragmaNode.info.line.int,
                    column: pragmaNode.info.col.int + 1)))
              inc j
    of nkTypeDef:
      # Types can have pragmas via nkPragmaExpr
      if n.safeLen >= 1:
        let nameNode = n[0]
        if nameNode.kind == nkPragmaExpr and nameNode.safeLen >= 2:
          let target = extractName(nameNode[0])
          let pragmas = nameNode[1]
          if target.len > 0 and pragmas.kind == nkPragma:
            var j = 0
            while j < pragmas.safeLen:
              let pragmaNode = pragmas[j]
              var pragmaName = ""
              var pragmaValue = ""
              if pragmaNode.kind == nkExprColonExpr and pragmaNode.safeLen >= 2:
                pragmaName = extractName(pragmaNode[0])
                pragmaValue = nodeToString(pragmaNode[1])
              elif pragmaNode.kind == nkIdent:
                pragmaName = pragmaNode.ident.s
              if pragmaName.len > 0:
                acc.add(PragmaFact(
                  targetName: target,
                  pragmaName: pragmaName,
                  pragmaValue: pragmaValue,
                  location: SourceLocation(
                    path: path,
                    line: pragmaNode.info.line.int,
                    column: pragmaNode.info.col.int + 1)))
              inc j
    else:
      discard

    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i

  walk(root)
  result = acc

func extractDistinctTypesV4(root: PNode; path: string): seq[
    DistinctTypeFact] {.raises: [].} =
  proc extractBaseType(n: PNode): string {.raises: [].} =
    if n.isNil: return ""
    case n.kind
    of nkIdent: n.ident.s
    of nkSym: n.sym.name.s
    of nkDotExpr: extractBaseType(n[0]) & "." & extractBaseType(n[1])
    of nkBracketExpr:
      extractBaseType(n[0]) & "[" & extractBaseType(n[1]) & "]"
    of nkAccQuoted: extractBaseType(n[0])
    of nkPtrTy: "ptr " & extractBaseType(n[0])
    of nkRefTy: "ref " & extractBaseType(n[0])
    else: nodeToString(n)

  var acc: seq[DistinctTypeFact] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkTypeSection:
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkTypeDef and child.safeLen >= 3:
          let typeBody = child[2]
          if not typeBody.isNil and typeBody.kind == nkDistinctTy and
              typeBody.safeLen >= 1:
            let typeName = extractName(child[0])
            let baseType = extractBaseType(typeBody[0])
            if typeName.len > 0 and baseType.len > 0:
              acc.add(DistinctTypeFact(
                name: typeName,
                baseType: baseType,
                location: SourceLocation(
                  path: path,
                  line: child.info.line.int,
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

func extractCallEdgesV4(root: PNode; path: string; functions: seq[
    FunctionFact]): seq[CallEdgeFact] {.raises: [].} =
  ## Extract call edges by traversing calls within function bodies.
  var currentFunc = ""

  var acc: seq[CallEdgeFact] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef:
      let savedFunc = currentFunc
      if n.safeLen >= 1:
        currentFunc = extractName(n[0])
      if n.safeLen >= 7 and not n[6].isNil:
        walk(n[6])
      currentFunc = savedFunc

    of nkCall, nkCommand, nkCallStrLit:
      if currentFunc.len > 0 and n.safeLen >= 1:
        let callee = calleeName(n[0])
        if callee.len > 0:
          acc.add(CallEdgeFact(
            callerModule: path,
            callerFunction: currentFunc,
            calleeModule: "",
            calleeFunction: callee,
            location: SourceLocation(
              path: path,
              line: n.info.line.int,
              column: n.info.col.int + 1)))
    else:
      var i = 0
      while i < n.safeLen:
        walk(n[i])
        inc i

  walk(root)
  result = acc

func extractWhenBlocksV4*(root: PNode): seq[string] {.raises: [].} =
  ## Extract when-condition identifiers (e.g., isMainModule) from nkWhenStmt nodes.
  proc walk(n: PNode; acc: var seq[string]) =
    if n == nil: return
    # Leaf nodes have no sons field — guard before accessing n.len
    if isAtom(n): return
    if n.kind == nkWhenStmt and n.len >= 1:
      let cond = n[0]
      if cond.kind == nkIdent:
        acc.add(cond.ident.s)
      elif cond.kind == nkCall and cond.len >= 1 and cond[0].kind == nkIdent:
        acc.add(cond[0].ident.s)
    for i in 0 ..< n.len:
      walk(n[i], acc)
  walk(root, result)

# ---------------------------------------------------------------------------
# Module-level extraction — OCP and case-stmt analysis
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Case branch counter — OCP static detection
# ---------------------------------------------------------------------------

func countCaseBranches*(root: PNode; path: string): tuple[count: int;
    typeCount: int; locations: seq[SourceLocation]] {.raises: [].} =
  ## Count nkOfBranch nodes in the entire AST and record their locations.
  ## `typeCount` tracks branches inside nkTypeSection (object variant
  ## definitions) which are type-level, not runtime dispatch, and thus
  ## not OCP violations.
  if root.isNil: return (0, 0, @[])
  var count = 0
  var typeCount = 0
  var locs: seq[SourceLocation] = @[]
  var inTypeSection = false
  proc walk(n: PNode) =
    if n.isNil: return
    if n.kind == nkTypeSection:
      inTypeSection = true
      var i = 0
      while i < n.safeLen:
        walk(n[i])
        inc i
      inTypeSection = false
      return
    if n.kind == nkOfBranch:
      count += 1
      if inTypeSection:
        typeCount += 1
      locs.add(SourceLocation(
        path: path,
        line: n.info.line.int,
        column: n.info.col.int + 1))
    var i = 0
    while i < n.safeLen:
      walk(n[i])
      inc i
  walk(root)
  result = (count, typeCount, locs)

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

proc extractModuleFactsV4*(path: string;
    source: string): ModuleFacts {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unified PNode-based Nim fact extractor.
  ##
  ## Parses `source` using Nim's compiler API (compiler/parser), builds a
  ## lightweight symbol table, and extracts all fact types consumed by the
  ## architecture gate.
  ##
  ## This replaces the line-based architecture_ast_extractor.nim and the
  ## stubbed architecture_ast_extractor_v3.nim.

  if source.len == 0:
    return ModuleFacts(path: path)

  # Parse the source using Nim's compiler API.
  # openParser lacks a raises pragma and is tracked as raising generic Exception
  # (nim_effect_system_quirks.md §7). Per Nim manual, only CatchableError should
  # be caught; Defect descendants indicate programming bugs and must not be
  # swallowed (Context7 /nim-lang/nim exception hierarchy).
  let cache = newIdentCache()
  let config = newConfigRef()
  var topNode: PNode = nil
  try:
    # The compiler API parser is declared as raising generic Exception because
    # it lacks precise raises pragmas. We use cast(raises: []) to satisfy the
    # enclosing proc's raises: [] contract, while only catching CatchableError
    # at runtime (Defect descendants are not caught). Documented quirk:
    # docs/spec/nim_effect_system_quirks.md §7.
    {.cast(raises: []).}:
      var stream = llStreamOpen(source)
      let absFile = AbsoluteFile(path)
      var parser: Parser
      openParser(parser, absFile, stream, cache, config)
      topNode = parseAll(parser)
      closeParser(parser)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  if topNode.isNil:
    return ModuleFacts(path: path)

  # Build lightweight symbol table
  let st = buildSymbolTable(topNode, path)

  # Extract all facts
  result.path = path
  result.imports = extractImportsV4(topNode, path)
  result.calls = extractCallsV4(topNode, path, st)
  let extracted = extractAssignmentsV4(topNode, path)
  result.assignments = extracted.assignments
  result.divisions = extracted.divisions
  result.typeDefs = extractTypeDefsV4(topNode, path)
  result.functions = extractFunctionsV4(topNode, path, st, source)
  result.constStrings = extractConstStringsV4(topNode, path)
  result.pragmas = extractPragmasV4(topNode, path)
  result.distinctTypes = extractDistinctTypesV4(topNode, path)
  result.callEdges = extractCallEdgesV4(topNode, path, result.functions)
  let (branchCount, typeBranchCount, branchLocs) = countCaseBranches(topNode, path)
  result.caseBranchCount = branchCount
  result.typeCaseBranchCount = typeBranchCount
  result.caseBranchLocations = branchLocs
  result.whenBlocks = extractWhenBlocksV4(topNode)

{.pop.}
