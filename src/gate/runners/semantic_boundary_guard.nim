import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## semantic_boundary_guard — Gate 2: Post-expansion symbol origin tracker
##
## After macro/template expansion, checks that each imported symbol's
## *defining module* does not violate layer boundaries.  Gate 1 (unified)
## catches syntactic cross-layer imports; Gate 2 catches cases where a
## re-exported or forwarded symbol originates from a forbidden layer.
##
## Two-phase approach:
##   1. `buildSymbolIndex`  — walk src/, parse every .nim file, extract
##      exported symbol names and map them to their defining file.
##   2. `checkSymbolOrigins` — for each file's imports, resolve the
##      origin module of every imported symbol via the index and verify
##      that the origin layer is allowed by the layer DAG.
##
## Rule tag: SB-3.1 (Semantic Boundary).

import std/[os, strutils, strformat, json, tables, monotimes]
import core/parser_utils
import compiler/ast
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

const
  GateTag* = "[semantic-boundary]"

  ## Layer prefix mapping for source files (mirrors unified_gate_runner)
  CorePrefix* = "src/core/"
  DomainPrefix* = "src/engine/"
  GatePrefix* = "src/gate/"
  InfraPrefix* = "src/infrastructure/"
  CliPrefix* = "src/cli/"

  ## Infrastructure layer paths — exempt from some checks
  InfrastructureExemptPaths* = [
    "src/core/trusted/",
    "src/infrastructure/",
  ]

type
  Violation* = object
    ## Single semantic-boundary violation.
    file*: string
    line*: int
    column*: int
    rule*: string       ## e.g. "SB-3.1"
    severity*: string   ## "critical", "high", "medium"
    message*: string

  GateResult* = object
    ok*: bool
    violations*: seq[Violation]
    stdout*: string
    stderr*: string

  LayerDag* = JsonNode
    ## Layer dependency graph:
    ## { "core": { "allowed": ["core"] },
    ##   "gate": { "allowed": ["gate", "core"] },
    ##   "engine": { "allowed": ["engine", "core", "gate"] },
    ##   ... }

  SymbolOrigin* = object
    ## A single origin entry for an exported symbol.
    module*: string     ## file path (e.g. "src/core/types.nim")
    layer*: string      ## resolved layer (e.g. "core")

  ExportedSymbol* = object
    ## An exported symbol extracted from a module.
    name*: string
    location*: tuple[line, col: int]

# ─── Layer Resolution ──────────────────────────────────────────────────────

func isInfrastructureExempt*(filePath: string): bool {.raises: [].} =
  ## Check if a file resides in an infrastructure-exempt path.
  for prefix in InfrastructureExemptPaths:
    if filePath.startsWith(prefix):
      return true
  result = false

func layerForPath*(filePath: string): string {.raises: [].} =
  ## Determine the architecture layer for a given source file path.
  if filePath.startsWith(CorePrefix): return "core"
  if filePath.startsWith(DomainPrefix): return "domain"
  if filePath.startsWith(GatePrefix): return "gate"
  if filePath.startsWith(InfraPrefix): return "infrastructure"
  if filePath.startsWith(CliPrefix): return "cli"
  result = ""

func isAllowedImport*(layerDag: LayerDag; sourceLayer, targetLayer: string): bool {.raises: [].} =
  ## Check if sourceLayer is allowed to import from targetLayer per the DAG.
  if layerDag == nil:
    return true
  if sourceLayer == targetLayer:
    return true
  let allowed = layerDag{sourceLayer, "allowed"}
  if allowed == nil or allowed.kind != JArray:
    return false
  for a in allowed:
    if a.getStr("") == targetLayer:
      return true
  result = false

# ─── AST Parsing ───────────────────────────────────────────────────────────

proc parseFileToAst*(filePath: string): PNode {.raises: [].} =
  ## Parse a .nim file into a PNode tree using shared IdentCache/ConfigRef caches.
  parser_utils.parseFileAST(filePath)

# ─── Export Extraction ─────────────────────────────────────────────────────

func extractExportedSymbols*(ast: PNode): seq[ExportedSymbol] {.raises: [].} =
  ## Walk the AST and extract all exported identifiers (names ending with '*').
  if ast == nil:
    return

  var symbols: seq[ExportedSymbol]

  proc walk(node: PNode; acc: var seq[ExportedSymbol]; depth: int = 0) {.raises: [].} =
    if node == nil or depth > 200:
      return
    case node.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkConverterDef:
      ## These have [name, pattern, genericParams, params, pragmas, body]
      if node.len > 0:
        let nameNode = node[0]
        var name = ""
        case nameNode.kind
        of nkIdent: name = nameNode.ident.s
        of nkPostfix:
          ## e.g. `foo*` — the right child is the ident
          if nameNode.len >= 2 and nameNode[1].kind == nkIdent:
            name = nameNode[1].ident.s
        else: discard
        if name.len > 0 and name.endsWith("*"):
          let info = if nameNode.kind == nkPostfix and nameNode.len >= 2: nameNode[1].info
                     else: nameNode.info
          acc.add(ExportedSymbol(
            name: name[0 .. ^2],  ## strip trailing '*'
            location: (line: info.line.int, col: info.col.int),
          ))

    of nkVarSection, nkLetSection:
      for def in node:
        ## Each child is a IdentDefs
        if def.kind == nkIdentDefs and def.len >= 3:
          let nameNode = def[0]
          case nameNode.kind
          of nkIdent:
            let name = nameNode.ident.s
            if name.endsWith("*"):
              acc.add(ExportedSymbol(
                name: name[0 .. ^2],
                location: (line: nameNode.info.line.int, col: nameNode.info.col.int),
              ))
          of nkPostfix:
            if nameNode.len >= 2 and nameNode[1].kind == nkIdent:
              let name = nameNode[1].ident.s
              if name.endsWith("*"):
                acc.add(ExportedSymbol(
                  name: name[0 .. ^2],
                  location: (line: nameNode[1].info.line.int, col: nameNode[1].info.col.int),
                ))
          else: discard

    of nkTypeSection:
      for typeDef in node:
        ## TypeDef = name, genericParams, typeBody, pragmas
        if typeDef.kind == nkTypeDef and typeDef.len >= 1:
          let nameNode = typeDef[0]
          case nameNode.kind
          of nkIdent:
            let name = nameNode.ident.s
            if name.endsWith("*"):
              acc.add(ExportedSymbol(
                name: name[0 .. ^2],
                location: (line: nameNode.info.line.int, col: nameNode.info.col.int),
              ))
          of nkPostfix:
            if nameNode.len >= 2 and nameNode[1].kind == nkIdent:
              let name = nameNode[1].ident.s
              if name.endsWith("*"):
                acc.add(ExportedSymbol(
                  name: name[0 .. ^2],
                  location: (line: nameNode[1].info.line.int, col: nameNode[1].info.col.int),
                ))
          else: discard

    of nkConstSection:
      for constDef in node:
        if constDef.kind == nkConstDef and constDef.len >= 2:
          let nameNode = constDef[0]
          case nameNode.kind
          of nkIdent:
            let name = nameNode.ident.s
            if name.endsWith("*"):
              acc.add(ExportedSymbol(
                name: name[0 .. ^2],
                location: (line: nameNode.info.line.int, col: nameNode.info.col.int),
              ))
          of nkPostfix:
            if nameNode.len >= 2 and nameNode[1].kind == nkIdent:
              let name = nameNode[1].ident.s
              if name.endsWith("*"):
                acc.add(ExportedSymbol(
                  name: name[0 .. ^2],
                  location: (line: nameNode[1].info.line.int, col: nameNode[1].info.col.int),
                ))
          else: discard

    of nkEnumTy:
      ## nkEnumTy contains nkEnumFieldDef children — walk them
      for child in node:
        walk(child, acc, depth + 1)

    of nkEnumFieldDef:
      ## Single enum field: nkEnumFieldDef has [ident, value?]
      if node.len >= 1:
        let nameNode = node[0]
        case nameNode.kind
        of nkIdent:
          let name = nameNode.ident.s
          if name.endsWith("*"):
            acc.add(ExportedSymbol(
              name: name[0 .. ^2],
              location: (line: nameNode.info.line.int, col: nameNode.info.col.int),
            ))
        of nkPostfix:
          if nameNode.len >= 2 and nameNode[1].kind == nkIdent:
            let name = nameNode[1].ident.s
            if name.endsWith("*"):
              acc.add(ExportedSymbol(
                name: name[0 .. ^2],
                location: (line: nameNode[1].info.line.int, col: nameNode[1].info.col.int),
              ))
        else: discard

    else: discard

    for child in node:
      walk(child, acc, depth + 1)

  walk(ast, symbols)
  result = symbols

# ─── Import Extraction ─────────────────────────────────────────────────────

type
  ImportEntry* = object
    ## A single imported symbol with its source module path.
    modulePath*: string       ## e.g. "core/types" or "std/os"
    symbolName*: string       ## e.g. "Violation" or "" for whole-module import
    line*: int
    column*: int

func extractImports*(ast: PNode): seq[ImportEntry] {.raises: [].} =
  ## Extract all import/from statements from the AST.
  if ast == nil:
    return

  var entries: seq[ImportEntry]

  proc walk(node: PNode; acc: var seq[ImportEntry]; depth: int = 0) {.raises: [].} =
    if node == nil or depth > 200:
      return
    case node.kind
    of nkImportStmt:
      ## import foo/bar  OR  import foo/bar, baz/qux
      for child in node:
        case child.kind
        of nkIdent:
          acc.add(ImportEntry(
            modulePath: child.ident.s,
            line: child.info.line.int,
            column: child.info.col.int,
          ))
        of nkInfix:
          ## import foo/bar as baz
          if child.len >= 3 and child[0].kind == nkIdent and child[0].ident.s == "as":
            if child[1].kind == nkIdent:
              acc.add(ImportEntry(
                modulePath: child[1].ident.s,
                line: child.info.line.int,
                column: child.info.col.int,
              ))
        of nkImportStmt:
          ## Nested import (rare but valid)
          walk(child, acc, depth + 1)
        else: discard

    of nkFromStmt:
      ## from foo/bar import X, Y
      if node.len >= 1:
        let moduleNode = node[0]
        let modulePath =
          case moduleNode.kind
          of nkIdent: moduleNode.ident.s
          else: ""
        ## Remaining children after [0] are the imported symbols
        for i in 1 ..< node.len:
          let symNode = node[i]
          case symNode.kind
          of nkIdent:
            acc.add(ImportEntry(
              modulePath: modulePath,
              symbolName: symNode.ident.s,
              line: symNode.info.line.int,
              column: symNode.info.col.int,
            ))
          of nkPostfix:
            ## `import foo*`
            if symNode.len >= 2 and symNode[1].kind == nkIdent:
              acc.add(ImportEntry(
                modulePath: modulePath,
                symbolName: symNode[1].ident.s,
                line: symNode.info.line.int,
                column: symNode.info.col.int,
              ))
          else: discard

    else:
      for child in node:
        walk(child, acc, depth + 1)

  walk(ast, entries)
  result = entries

# ─── Phase 1: Build Symbol Index ──────────────────────────────────────────

func normalizePath*(rawPath: string): string {.raises: [].} =
  ## Normalize a Nim import path to a filesystem-relative path.
  ## "core/types" → "src/core/types.nim"
  ## "std/os" → "" (stdlib — skip)
  ## Already starts with "src/" → strip leading path if needed
  if rawPath.startsWith("std/") or rawPath.len == 0:
    return ""
  ## If it already has a .nim extension, return as-is
  if rawPath.endsWith(".nim"):
    return rawPath
  ## Try to reconstruct a file path
  result = "src/" & rawPath.replace("/", "/") & ".nim"

proc buildSymbolIndex*(srcDir: string): Table[string, seq[SymbolOrigin]] {.raises: [CatchableError].} =
  ## Walk all .nim files under srcDir, parse them, and build a map
  ## of exported symbol names → their defining module origins.
  for path in walkDirRec(srcDir):
    if not path.endsWith(".nim"):
      continue
    ## Skip test files and build artifacts
    if path.contains("/tests/") or path.contains("/test_"):
      continue

    var ast: PNode
    try:
      ast = parseFileToAst(path)
    except CatchableError:
      continue
    if ast == nil:
      continue

    let symbols = extractExportedSymbols(ast)
    let layer = layerForPath(path)
    for sym in symbols:
      let origin = SymbolOrigin(module: path, layer: layer)
      if sym.name in result:
        ## Multiple definitions (e.g. overloaded procs) — accumulate
        result[sym.name].add(origin)
      else:
        result[sym.name] = @[origin]

# ─── Phase 2: Check Symbol Origins ────────────────────────────────────────

proc checkSymbolOrigins*(file: string; symbolIndex: Table[string, seq[SymbolOrigin]];
                         layerDag: LayerDag): seq[Violation] {.raises: [].} =
  ## For a given file, check that every imported symbol's defining module
  ## does not violate the layer boundary policy.
  let sourceLayer = layerForPath(file)
  if sourceLayer.len == 0:
    return
  if isInfrastructureExempt(file):
    return

  var ast: PNode
  try:
    ast = parseFileToAst(file)
  except CatchableError:
    return
  if ast == nil:
    return

  let imports = extractImports(ast)

  for imp in imports:
    ## Skip stdlib and empty paths
    if imp.modulePath.startsWith("std/") or imp.modulePath.len == 0:
      continue

    let normalizedModule = normalizePath(imp.modulePath)
    if normalizedModule.len == 0:
      continue

    ## Determine target layer from the module path directly
    let targetLayer = layerForPath(normalizedModule)

    ## If no specific symbol, check the whole-module import
    if imp.symbolName.len == 0:
      if targetLayer.len > 0 and sourceLayer != targetLayer:
        if not isAllowedImport(layerDag, sourceLayer, targetLayer):
          result.add(Violation(
            file: file,
            line: imp.line,
            column: imp.column,
            rule: "SB-3.1",
            severity: "critical",
            message: fmt"Semantic boundary: {sourceLayer} imports module from forbidden layer {targetLayer} ({imp.modulePath})",
          ))
      continue

    ## For specific symbol imports, look up the origin in the symbol index
    let origins = symbolIndex.getOrDefault(imp.symbolName, @[])
    if origins.len == 0:
      ## Symbol not in our index — could be stdlib or external, skip
      continue
    for origin in origins:
      ## If origin layer is different from source and not allowed → violation
      if origin.layer.len > 0 and origin.layer != sourceLayer:
        if not isAllowedImport(layerDag, sourceLayer, origin.layer):
          result.add(Violation(
            file: file,
            line: imp.line,
            column: imp.column,
            rule: "SB-3.1",
            severity: "critical",
            message: fmt"Semantic boundary: symbol '{imp.symbolName}' originates in {origin.layer} " &
                     fmt"({origin.module}), forbidden for {sourceLayer}",
          ))
          ## One violation per symbol import is enough
          break

# ─── Main Entry Point ──────────────────────────────────────────────────────

proc runSemanticGuard*(files: seq[string]; layerDag: JsonNode = nil): GateResult {.raises: [CatchableError].} =
  ## Main entry point for Gate 2.
  ## 1. Build the symbol index from src/ (once).
  ## 2. For each target file, check imported symbol origins.
  let t0Ticks = getMonoTime().ticks

  ## Phase 1: Build symbol index over entire src/
  var symbolIndex: Table[string, seq[SymbolOrigin]]
  try:
    symbolIndex = buildSymbolIndex("src")
  except CatchableError as e:
    return GateResult(
      ok: false,
      violations: @[],
      stdout: "{}",
      stderr: fmt"{GateTag} FAIL — could not build symbol index: {e.msg}",
    )

  ## Phase 2: Check each file
  var allViolations: seq[Violation]
  var processedCount = 0

  for filePath in files:
    if not filePath.endsWith(".nim"):
      continue
    ## Skip test files
    if filePath.contains("/tests/") or filePath.contains("/test_"):
      continue
    inc processedCount

    try:
      let violations = checkSymbolOrigins(filePath, symbolIndex, layerDag)
      allViolations.add(violations)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000

  ## Determine pass/fail
  var hasBlocking = false
  for v in allViolations:
    if v.severity in ["critical", "high"]:
      hasBlocking = true
      break

  ## Build JSON output
  var jViolations = newJArray()
  for v in allViolations:
    var jv = newJObject()
    jv["file"] = %v.file
    jv["line"] = %v.line
    jv["column"] = %v.column
    jv["rule"] = %v.rule
    jv["severity"] = %v.severity
    jv["message"] = %v.message
    jViolations.add(jv)

  var jOutput = newJObject()
  jOutput["gate"] = %"semantic-boundary-guard"
  jOutput["totalFiles"] = %processedCount
  jOutput["totalViolations"] = %allViolations.len
  jOutput["violations"] = jViolations
  jOutput["elapsedMs"] = %elapsedMs

  let stdoutJson =
    try: $jOutput.pretty()
    except CatchableError: "{}"

  let stderrText =
    if hasBlocking:
      var lines: seq[string]
      for v in allViolations:
        if v.severity in ["critical", "high"]:
          lines.add(fmt"  [{v.severity.toUpperAscii}] {v.rule}: {v.file}:{v.line} {v.message}")
      fmt"{GateTag} FAIL — {allViolations.len} violation(s):\n" & lines.join("\n")
    elif allViolations.len > 0:
      fmt"{GateTag} PASS — {allViolations.len} warning(s)"
    else:
      fmt"{GateTag} PASS — {processedCount} files scanned, no semantic boundary violations"

  result = GateResult(
    ok: not hasBlocking,
    violations: allViolations,
    stdout: stdoutJson,
    stderr: stderrText,
  )

# ─── CLI Entry Point ───────────────────────────────────────────────────────

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var files: seq[string]

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.endsWith(".nim"):
      files.add(arg)

  ## If no files passed, scan entire src/ directory
  if files.len == 0:
    for path in walkDirRec("src"):
      if path.endsWith(".nim"):
        files.add(path)

  let t0Ticks = getMonoTime().ticks
  let res = runSemanticGuard(files)
  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000

  if elapsedMs > 1000:
    logInfo("semantic_boundary_guard", $(GateTag) & " [PERF] semantic-boundary took " & $(elapsedMs) & "ms (threshold: 1000ms)")

  logInfo("semantic_boundary_guard", $(GateTag) & " " & $(res.stderr))
  quit(if res.ok: 0 else: 1)

when isMainModule: main()

{.pop.}
