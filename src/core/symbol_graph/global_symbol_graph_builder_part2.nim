import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/interfaces/git_operations
import core/crypto/hash_kernel
import core/json/std_redirect
import core/parser_utils
import core/parsers/pnode_nav
import core/pure/json_parse
import core/symbol_graph/error_bridge
import core/symbol_graph/global_symbol_graph_builder_part1
import core/symbolic/global_symbol_graph_types
import core/trusted/axiom_pragmas
import core/types/global_symbol_graph_types
import core/types/results
import core/utils/file_utils
import core/utils/io_utils
import compiler/ast
import std/algorithm
import std/hashes
import std/options
import std/os
import std/sequtils
import std/strutils
import std/tables
import core/interfaces/logging_hub
let gitExe* = git_operations.findRealGit()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveIncrementalGraphCache*(cachePath: string; entries: Table[string, ModuleGraphContribution]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var modules = newJObject()
  var keys = entries.keys.toSeq()
  keys.sort(cmp[string])
  for key in keys:
    let entry = entries.getOrDefault(key)
    var obj = newJObject()
    obj["hash"] = newJString(entry.fileHash)
    var symArr = newJArray()
    var symbols = entry.symbols
    symbols.sort(symbolNodeCmp)
    for sym in symbols:
      var node = newJObject()
      node["qualifiedName"] = newJString(sym.qualifiedName)
      node["kind"] = newJString($sym.kind)
      node["modulePath"] = newJString(sym.modulePath)
      node["visibility"] = newJString(sym.visibility)
      symArr.add(node)
    obj["symbols"] = symArr
    var edgeArr = newJArray()
    var edges = entry.edges
    edges.sort(referenceEdgeCmp)
    for edge in edges:
      var node = newJObject()
      node["source"] = newJString(edge.source)
      node["target"] = newJString(edge.target)
      node["kind"] = newJString($edge.kind)
      node["line"] = newJInt(edge.line)
      node["column"] = newJInt(edge.column)
      edgeArr.add(node)
    obj["edges"] = edgeArr
    modules[key] = obj
  var root = newJObject()
  root["modules"] = modules
  try:
    let dir = parentDir(cachePath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    ## intentional-discard: cache write is idempotent; the entry is re-derived on read
    discard writeFileOpt(cachePath, pretty(root))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Regex-based Lean symbol extractor — deterministic, no external dependencies
func extractLeanSymbolsFromSource*(content: string; relPath: string): seq[SymbolNode] {.raises: [].} =
  ## Extract Lean declarations (def, theorem, lemma, structure, inductive, abbrev, opaque, example)
  ## using regex-like line scanning. Returns SymbolNodes with Lean-specific SymbolKind values.
  let moduleStem {.used.} = moduleNameFromPath(relPath)
  var i = 0
  while i < content.len:
    # Skip comments (-- and #)
    if i + 1 < content.len and content[i] == '-' and content[i+1] == '-':
      while i < content.len and content[i] != '\n' and content[i] != '\r':
        inc i
      continue
    if i + 1 < content.len and content[i] == '#' and content[i+1] != '#':
      while i < content.len and content[i] != '\n' and content[i] != '\r':
        inc i
      continue
    # Skip string literals
    if content[i] == '"':
      inc i
      while i < content.len and content[i] != '"':
        if content[i] == '\\' and i + 1 < content.len:
          inc i
        inc i
      inc i
      continue
    # Match Lean declaration keywords followed by optional '!' or '?' and identifier
    let declPatterns: array[8, (string, SymbolKind)] = [
      ("theorem ", skLeanTheorem),
      ("lemma ", skLeanTheorem),
      ("def ", skLeanDef),
      ("structure ", skLeanStructure),
      ("inductive ", skLeanInductive),
      ("abbrev ", skLeanAbbrev),
      ("opaque ", skLeanOpaque),
      ("example ", skLeanExample)
    ]
    for (keyword, kind) in declPatterns:
      let kwLen = keyword.len
      if i + kwLen <= content.len and content[i .. i+kwLen-1] == keyword:
        # Check that keyword is at start of line or preceded by whitespace
        if i == 0 or content[i-1] in {' ', '\t', '\n', '\r'}:
          var j = i + kwLen
          # Skip '!' or '?' suffixes
          if j < content.len and content[j] in {'!', '?'}:
            inc j
          # Skip whitespace
          while j < content.len and content[j] in {' ', '\t'}:
            inc j
          # Read identifier
          var name = ""
          while j < content.len and content[j] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '`'}:
            name.add(content[j])
            inc j
          if name.len > 0:
            let qn = qualifiedName(relPath, name)
            result.add(SymbolNode(
              qualifiedName: qn,
              kind: kind,
              modulePath: relPath,
              astNode: nil,
              visibility: "public"
            ))
        break  # Don't match multiple patterns for same position
    inc i

## Build Global Symbol Graph.
# @axiom-hint: lean="repoRoot.length ≥ 0" smt="(assert (and (>= (str.len repoRoot) 0)))"
# @axiom-hint: lean="repoRoot.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len repoRoot) 0) external_io_isolated))"
# @axiom-hint: lean="contentRes.isErr = true ∧ (edges ≥ 0) ∧ (moduleAsts ≥ 0) ∧ (tmpTable ≥ 0) ∧ (paths ≥ 0) ∧ (result ≥ 0) ∧ (refs ≥ 0) ∧ (newCache ≥ 0) ∧ (table ≥ 0)" smt="(assert (and (= (option.isNone contentOpt) true) (>= edges 0) (>= moduleAsts 0) (>= tmpTable 0) (>= paths 0) (>= result 0) (>= refs 0) (>= newCache 0) (>= table 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)

func procNameFromDeclNode*(node0: PNode): string =
  ## Extract proc name from a declaration's name node, handling nkPostfix (export marker).
  ## For exported procs (e.g. `foo*`), node0 is nkPostfix with children [nkIdent("*"), nkIdent("foo")].
  ## The real identifier is node0[1], not the first nkIdent found by findFirstNodeP.
  if node0.isNil: return ""
  var nameNode: PNode
  if node0.kind == nkPostfix:
    if node0.len > 1:
      nameNode = node0[1]
    else:
      return ""
  else:
    let nameNodeOpt = findFirstNodeP(node0, {nkIdent})
    if nameNodeOpt.isSome:
      nameNode = nameNodeOpt.get
    else:
      return ""
  if nameNode.kind == nkIdent:
    result = nameNode.ident.s
  elif nameNode.kind == nkSym:
    result = nameNode.sym.name.s
  else:
    result = ""

proc buildGlobalSymbolGraph*(repoRoot: string; freezeGraphCache: bool = false): GlobalSymbolGraph =
  ## Walk all .nim files under repoRoot, index declarations, then collect references.
  ## Pillar 4: uses SHA-content-hash incremental cache — only changed files are re-parsed.
  if freezeGraphCache:
    try:
      let (gitStatus, gitExit) = git_operations.runGitEx(gitExe, "status --porcelain")
      if gitExit == 0 and gitStatus.strip().len > 0:
        logInfo("[AXIOM] Uncommitted changes detected but --freeze is active.")
        logInfo("[AXIOM] Topology cache may ignore modified modules. Use --no-freeze to invalidate.")
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  let incCachePath = globalSymbolGraphIncrementalCachePath(repoRoot)

  # Load incremental cache (module hash -> contribution)
  var moduleCache = loadIncrementalGraphCache(incCachePath)

  # Collect all .nim paths
  var paths: seq[string] = @[]
  let walkRes = walkDirRecOpt(repoRoot)
  if walkRes.isOk:
    for path in walkRes.get():
      if path.endsWith(".nim"):
        paths.add(path)
  paths.sort(cmp[string])

  # Collect all .lean paths for cross-language symbol graph integration
  var leanPaths: seq[string] = @[]
  if walkRes.isOk:
    for path in walkRes.get():
      if path.endsWith(".lean"):
        leanPaths.add(path)
  leanPaths.sort(cmp[string])

  var table = initTable[string, SymbolNode]()
  var edges: seq[ReferenceEdge] = @[]
  var moduleAsts = initTable[string, PNode]()
  var newCache = initTable[string, ModuleGraphContribution]()

  # Phase 1: load cached contributions for unchanged files, parse changed files
  for path in paths:
    let relPath = path[len(repoRoot) .. ^1].strip(chars = {'/'})
    let contentRes = readFileOpt(path)
    if contentRes.isErr:
      continue
    let content = contentRes.get()
    let currentHash = hash_kernel.sha256Hex(content)

    if moduleCache.hasKey(relPath):
      let cached = moduleCache.getOrDefault(relPath)
      if cached.fileHash == currentHash:
        # Unchanged module — reuse cached symbols and edges
        for sym in cached.symbols:
          table[sym.qualifiedName] = sym
        for edge in cached.edges:
          edges.add(edge)
        discard newCache.mgetOrPut(relPath, cached)
        continue

    if freezeGraphCache:
      continue

    # Changed or new module — parse AST and index
    let ast = parseStringAST(content)
    if not ast.isNil:
      var moduleSymbols: seq[SymbolNode] = @[]
      var moduleEdges: seq[ReferenceEdge] = @[]
      var tmpTable = initTable[string, SymbolNode]()
      # PNode-based declaration indexer
      for node in findNodesP(ast, ProcDefKinds):
        if node.len > 0 and not node[0].isNil:
          let nm = procNameFromDeclNode(node[0])
          if nm.len > 0:
            let qn = qualifiedName(relPath, nm)
            if not tmpTable.hasKey(qn):
              let kind = if node[0].kind == nkFuncDef: SymbolKind.skFunc else: SymbolKind.skProc
              tmpTable[qn] = SymbolNode(
                qualifiedName: qn,
                kind: kind,
                modulePath: relPath,
                astNode: nil,
                visibility: "public"
              )
      for qn in sortedSymbolKeys(tmpTable):
        let sym = tmpTable.getOrDefault(qn)
        table[qn] = sym
        moduleSymbols.add(sym)
      newCache[relPath] = ModuleGraphContribution(
        fileHash: currentHash,
        symbols: moduleSymbols,
        edges: moduleEdges
      )
    else:
      # Tree-sitter fallback: extract symbols via regex when parser is unavailable
      let fallbackSyms = extractSymbolsFromSourceFallback(content, relPath)
      if fallbackSyms.len > 0:
        var moduleSymbols: seq[SymbolNode] = @[]
        for sym in fallbackSyms:
          table[sym.qualifiedName] = sym
          moduleSymbols.add(sym)
        newCache[relPath] = ModuleGraphContribution(
          fileHash: currentHash,
          symbols: moduleSymbols,
          edges: @[]
        )

  # Phase 1b: Process .lean files with regex-based Lean symbol extractor
  for path in leanPaths:
    let relPath = path[len(repoRoot) .. ^1].strip(chars = {'/'})
    let contentRes = readFileOpt(path)
    if contentRes.isErr:
      continue
    let content = contentRes.get()
    let currentHash = hash_kernel.sha256Hex(content)

    if moduleCache.hasKey(relPath):
      let cached = moduleCache.getOrDefault(relPath)
      if cached.fileHash == currentHash:
        for sym in cached.symbols:
          table[sym.qualifiedName] = sym
        for edge in cached.edges:
          edges.add(edge)
        discard newCache.mgetOrPut(relPath, cached)
        continue

    if freezeGraphCache:
      continue

    # Extract Lean symbols via regex-based parser
    let leanSyms = extractLeanSymbolsFromSource(content, relPath)
    if leanSyms.len > 0:
      var moduleSymbols: seq[SymbolNode] = @[]
      for sym in leanSyms:
        table[sym.qualifiedName] = sym
        moduleSymbols.add(sym)
      newCache[relPath] = ModuleGraphContribution(
        fileHash: currentHash,
        symbols: moduleSymbols,
        edges: @[]
      )

  # Phase 2: collect references for changed modules only (requires full symbol table)
  var modulePaths = moduleAsts.keys.toSeq()
  modulePaths.sort(cmp[string])
  for relPath in modulePaths:
    for qn in sortedSymbolKeys(table):
      let sym = table.getOrDefault(qn)
      if sym.modulePath != relPath:
        continue
      if sym.kind notin {SymbolKind.skProc, SymbolKind.skFunc}:
        continue
      let body = sym.astNode
      if body.isNil:
        continue
      let refs = collectReferencesInAstP(body, qn, sym.modulePath, table)
      for r in refs:
        edges.add(r)
      if newCache.hasKey(relPath):
        var entry = newCache.mgetOrPut(relPath, ModuleGraphContribution())
        for r in refs:
          entry.edges.add(r)

  # Build reverse index byTarget
  edges.sort(referenceEdgeCmp)
  var byTarget = initTable[string, seq[ReferenceEdge]]()
  for edge in edges:
    byTarget.mgetOrPut(edge.target, @[]).add(edge)

  result = GlobalSymbolGraph(
    symbols: table,
    edges: edges,
    byTarget: byTarget
  )
  canonicalizeGlobalSymbolGraph(result)

  # Save incremental cache for next run. Freeze mode is read-only because it may
  # intentionally skip changed modules and must not persist a partial graph.
  if not freezeGraphCache:
    saveIncrementalGraphCache(incCachePath, newCache)

# @axiom-hint: lean="graph_edges.size ≥ 0 ∧ cachePath.length ≥ 0 ∧ maxSourceMtime ≥ -9223372036854775808 ∧ maxSourceMtime ≤ 9223372036854775807 ∧ external_io_isolated" smt="(assert (and (>= (seq.len graph_edges) 0) (>= (str.len cachePath) 0) (and (>= maxSourceMtime -9223372036854775808) (<= maxSourceMtime 9223372036854775807)) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeSourceMerkleRoot*(srcRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a deterministic Merkle root over all .nim files in srcRoot.
  ## Files are processed in alphabetical order to eliminate OS-specific
  ## filesystem layout non-determinism. Content hash uses Phase 12's
  ## computeFileHash (MD5-based; total overhead < 100ms for 200+ files).
  var paths: seq[string] = @[]
  try:
    for path in walkDirRec(srcRoot):
      if path.endsWith(".nim"):
        paths.add(path)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  paths.sort(cmp)
  var acc = ""
  for path in paths:
    let h = computeFileHash(path)
    if h.len > 0:
      acc = acc & path & ":" & h & "\n"
  result = gripOr(hash_kernel.sha256Hex(acc), "")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveGlobalSymbolGraphCache*(graph: GlobalSymbolGraph; cachePath: string; sourceMerkleRoot: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var symArr = newJArray()
  for qn in sortedSymbolKeys(graph.symbols):
    let sym = graph.symbols.getOrDefault(qn)
    var node = newJObject()
    node["qualifiedName"] = newJString(sym.qualifiedName)
    node["kind"] = newJString($sym.kind)
    node["modulePath"] = newJString(sym.modulePath)
    node["visibility"] = newJString(sym.visibility)
    symArr.add(node)
  var edgeArr = newJArray()
  var edges = graph.edges
  edges.sort(referenceEdgeCmp)
  for edge in edges:
    var node = newJObject()
    node["source"] = newJString(edge.source)
    node["target"] = newJString(edge.target)
    node["kind"] = newJString($edge.kind)
    node["line"] = newJInt(edge.line)
    node["column"] = newJInt(edge.column)
    edgeArr.add(node)
  var root = newJObject()
  root["sourceMerkleRoot"] = newJString(sourceMerkleRoot)
  root["symbols"] = symArr
  root["edges"] = edgeArr
  try:
    let dir = parentDir(cachePath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    ## intentional-discard: cache write is idempotent; the entry is re-derived on read
    discard writeFileOpt(cachePath, pretty(root))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="cachePath.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len cachePath) 0) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadGlobalSymbolGraphCache*(cachePath: string): Option[(GlobalSymbolGraph, string)] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(cachePath):
    return none((GlobalSymbolGraph, string))
  try:
    let readRes = readFileOpt(cachePath)
    if readRes.isErr: return
    let data = readRes.get
    let node = pureParseJson(data)
    let storedMerkle = node.getOrDefault("sourceMerkleRoot").getStr("")
    var graph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    if node.hasKey("symbols") and node["symbols"].kind == JArray:
      for symNode in node["symbols"]:
        let qn = symNode.getOrDefault("qualifiedName").getStr("")
        let kindStr = symNode.getOrDefault("kind").getStr("")
        let modulePath = symNode.getOrDefault("modulePath").getStr("")
        let visibility = symNode.getOrDefault("visibility").getStr("")
        if qn.len == 0: continue
        var kind = SymbolKind.skProc
        case kindStr
        of "skProc": kind = SymbolKind.skProc
        of "skFunc": kind = SymbolKind.skFunc
        of "skType": kind = SymbolKind.skType
        of "skField": kind = SymbolKind.skField
        of "skVar": kind = SymbolKind.skVar
        of "skLet": kind = SymbolKind.skLet
        of "skConst": kind = SymbolKind.skConst
        of "skGenericParam": kind = SymbolKind.skGenericParam
        of "skLeanTheorem", "skLeanDef", "skLeanMacro", "skLeanAbbrev",
           "skLeanInductive", "skLeanStructure", "skLeanClass", "skLeanOpaque",
           "skLeanExample", "skLeanMeta": discard
        else: discard
        graph.symbols[qn] = SymbolNode(
          qualifiedName: qn,
          kind: kind,
          modulePath: modulePath,
          astNode: nil,
          visibility: visibility
        )
    if node.hasKey("edges") and node["edges"].kind == JArray:
      for edgeNode in node["edges"]:
        let source = edgeNode.getOrDefault("source").getStr("")
        let target = edgeNode.getOrDefault("target").getStr("")
        let kindStr = edgeNode.getOrDefault("kind").getStr("")
        let line = edgeNode.getOrDefault("line").getInt(0)
        let column = edgeNode.getOrDefault("column").getInt(0)
        var kind = rkCall
        case kindStr
        of "rkCall": kind = rkCall
        of "rkTypeUse": kind = rkTypeUse
        of "rkFieldAccess": kind = rkFieldAccess
        of "rkMutates": kind = rkMutates
        of "rkReads": kind = rkReads
        else: discard
        let edge = ReferenceEdge(source: source, target: target, kind: kind, line: line, column: column)
        graph.edges.add(edge)
        graph.byTarget.mgetOrPut(target, @[]).add(edge)
    canonicalizeGlobalSymbolGraph(graph)
    return some((graph, storedMerkle))
  except CatchableError:
    return none((GlobalSymbolGraph, string))

{.pop.}
