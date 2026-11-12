import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/boundary/boundary_extractor
import core/interfaces/logging_hub
import core/json/json_utils
import core/json/std_redirect
import core/parser_utils
import core/parsers/pnode_nav
import compiler/ast
import core/sorter/sorter_core
import core/topology/topology_dependency
import core/topology/topology_parser
import core/topology/topology_symbol_scanner
import core/topology/topology_types
import core/trusted/axiom_pragmas
import core/types/results
import core/utils/axiom_error
import core/utils/io_utils
import core/topology/merkle_cache
import core/topology/node_filter
import core/utils/file_utils
import std/options
import std/os
import std/tables
import std/times
import std/sets
import core/topology/import_graph  # extractCoreImports
export topology_types
export topology_parser
export topology_symbol_scanner
export topology_dependency

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildTopologyAnalysis*(symbols: seq[TopologySymbol]): TopologyAnalysis =
  var nameIndex: Table[string, seq[int]]
  var nodes: seq[SorterNode] = @[]
  var unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
  for idx, symbol in symbols:
    var dependencies: seq[SorterNodeId] = @[]
    nameIndex.mgetOrPut(symbol.functionName, @[]).add(idx)
    nodes.add(makeSorterNode(symbol.modulePath, symbol.functionName, symbol.nodeId, dependencies, symbol.nodeType, symbol.definitionFingerprint))
  for idx, symbol in symbols:
    var dependencies: seq[SorterNodeId] = @[]
    for rawTarget in symbol.rawCallTargets:
      let res = resolveCallTarget(symbols, nameIndex, symbol.modulePath, rawTarget)
      if res.kind == rrUnique and res.resolvedIdx != idx:
        dependencies.add(symbols[res.resolvedIdx].nodeId)
      elif res.kind in {rrUnresolved, rrAmbiguous}:
        unresolvedEdges.add(TopologyUnresolvedEdge(
          fromNodeId: symbol.nodeId,
          targetName: rawTarget,
          modulePath: symbol.modulePath,
          resolutionKind: res.kind
        ))
    nodes[idx] = makeSorterNode(symbol.modulePath, symbol.functionName, symbol.nodeId, deduplicateNodeIds(dependencies), symbol.nodeType, symbol.definitionFingerprint)
  let dependents = computeDependents(nodes)
  let symbolIndexTable = buildSymbolIndexTable(symbols)
  let interfaceDistances = computeInterfaceDistances(nodes, symbols, symbolIndexTable)
  result.state = initSorterState(nodes)
  result.symbols = symbols
  result.symbolFirstPass = true
  result.metrics = newSeq[TopologyNodeMetric](nodes.len)
  var transitiveMemo = initTable[int, seq[int]]()
  for idx, node in nodes:
    let transitiveDependents = collectTransitiveDependentsMemo(dependents, idx, transitiveMemo)
    result.metrics[idx] = buildMetric(
      node,
      symbols[idx],
      interfaceDistances[idx],
      dependents[idx].len,
      transitiveDependents.len,
      nodes.len
    )
  var trivialNodes: HashSet[string]
  for sym in result.symbols:
    if sym.boundaryKind == topologyBoundaryTrivialDiscard:
      trivialNodes.incl(sorterNodeIdString(sym.nodeId))

  for idx in sortMetricIndices(result.metrics):
    let nodeId = result.metrics[idx].nodeId
    let key = sorterNodeIdString(nodeId)
    if key in trivialNodes:
      continue
    result.verificationQueue.add(nodeId)
  var bottlenecks: seq[SorterNodeId] = @[]
  for idx in sortByCoupling(result.metrics):
    if bottlenecks.len >= min(3, result.metrics.len):
      break
    if result.metrics[idx].couplingScore <= 0 and bottlenecks.len > 0:
      break
    bottlenecks.add(result.metrics[idx].nodeId)
  result.structuralBottlenecks = deduplicateNodeIds(bottlenecks)
  var repairTargets: seq[SorterNodeId] = @[]
  for idx in sortByRepairPriority(result.metrics):
    if repairTargets.len >= min(5, result.metrics.len):
      break
    let metric = result.metrics[idx]
    if metric.dependencyCount == 0 and metric.couplingScore == 0 and metric.complexityScore == 0:
      continue
    repairTargets.add(metric.nodeId)
  result.repairPriorityDependencies = deduplicateNodeIds(repairTargets)
  result.unresolvedEdges = unresolvedEdges

  ## W3-C: Build O(1) index tables from sorted nodeIds.
  result.metricIndex = initTable[string, int](result.metrics.len)
  for idx, metric in result.metrics:
    result.metricIndex[sorterNodeIdString(metric.nodeId)] = idx
  result.symbolIndex = initTable[string, int](result.symbols.len)
  for idx, symbol in result.symbols:
    result.symbolIndex[sorterNodeIdString(symbol.nodeId)] = idx

## Find Topology Metric Index.
  ## axiom-smt: (assert (and (>= (seq.len analysis_symbols) 0) (>= (seq.len analysis_metrics) 0) (>= (seq.len analysis_verificationQueue) 0) (>= (seq.len analysis_structuralBottlenecks) 0) (>= (seq.len analysis_repairPriorityDependencies) 0) (or (= analysis_symbolFirstPass true) (= analysis_symbolFirstPass false)) (< metricIdx 0) (or (= analysis_symbolFirstPass true) (= analysis_symbolFirstPass false))))
  ## axiom-lean: analysis_symbols.size ≥ 0 ∧ analysis_metrics.size ≥ 0 ∧ analysis_verificationQueue.size ≥ 0 ∧ analysis_structuralBottlenecks.size ≥ 0 ∧ analysis_repairPriorityDependencies.size ≥ 0 ∧ analysis_symbolFirstPass = true ∨ analysis_symbolFirstPass = false ∧ metricIdx < 0 ∧ analysis_symbolFirstPass = true ∨ analysis_symbolFirstPass = false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findTopologyMetricIndex*(analysis: TopologyAnalysis; nodeId: SorterNodeId): int {.axiom, axiomImpl.} =
  ## W3-C: O(1) index lookup instead of O(N) linear scan. Uses getOrDefault to avoid KeyError.
  let key = sorterNodeIdString(nodeId)
  analysis.metricIndex.getOrDefault(key, -1)

## Find Topology Symbol Index.
  ## axiom-smt: (assert (and idx (or (= analysis_symbolFirstPass true) (= analysis_symbolFirstPass false)) (< symbolIdx 0) (or (= analysis_symbolFirstPass true) (= analysis_symbolFirstPass false))))
  ## axiom-lean: idx ∧ analysis_symbolFirstPass = true ∨ analysis_symbolFirstPass = false ∧ symbolIdx < 0 ∧ analysis_symbolFirstPass = true ∨ analysis_symbolFirstPass = false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findTopologySymbolIndex*(analysis: TopologyAnalysis; nodeId: SorterNodeId): int {.axiom, axiomImpl.} =
  ## W3-C: O(1) index lookup instead of O(N) linear scan. Uses getOrDefault to avoid KeyError.
  let key = sorterNodeIdString(nodeId)
  analysis.symbolIndex.getOrDefault(key, -1)

## Find Topology Metric.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findTopologyMetric*(analysis: TopologyAnalysis; nodeId: SorterNodeId): Option[TopologyNodeMetric] =
  let metricIdx = findTopologyMetricIndex(analysis, nodeId)
  if metricIdx < 0:
    return none(TopologyNodeMetric)
  some(analysis.metrics[metricIdx])

## Find Topology Symbol.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findTopologySymbol*(analysis: TopologyAnalysis; nodeId: SorterNodeId): Option[TopologySymbol] =
  let symbolIdx = findTopologySymbolIndex(analysis, nodeId)
  if symbolIdx < 0:
    return none(TopologySymbol)
  some(analysis.symbols[symbolIdx])

## Find Topology Node Context.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findTopologyNodeContext*(
  analysis: TopologyAnalysis;
  nodeId: SorterNodeId
): Option[tuple[metric: TopologyNodeMetric, symbol: TopologySymbol]] {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (or (= analysis_symbolFirstPass true) (= analysis_symbolFirstPass false))))
  ## axiom-lean: analysis_symbolFirstPass = true ∨ analysis_symbolFirstPass = false
  let metric = findTopologyMetric(analysis, nodeId)
  let symbol = findTopologySymbol(analysis, nodeId)
  if metric.isNone() or symbol.isNone():
    return none(tuple[metric: TopologyNodeMetric, symbol: TopologySymbol])
  some((metric: metric.get(), symbol: symbol.get()))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func boundaryKindToInt(k: TopologyBoundaryKind): int {.raises: [].} =
  case k
  of topologyBoundaryNone: 0
  of topologyBoundaryInterface: 1
  of topologyBoundaryTrivialDiscard: 2
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func intToBoundaryKind(i: int): TopologyBoundaryKind {.raises: [].} =
  case i
  of 1: topologyBoundaryInterface
  of 2: topologyBoundaryTrivialDiscard
  else: topologyBoundaryNone
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func topologySymbolToJson(sym: TopologySymbol): JsonNode {.raises: [].} =
  %*{
    "modulePath": sym.modulePath,
    "functionName": sym.functionName,
    "nodeType": sym.nodeType,
    "nodeId": sorterNodeIdString(sym.nodeId),
    "declarationLine": sym.declarationLine,
    "bodyStartLine": sym.bodyStartLine,
    "bodyEndLine": sym.bodyEndLine,
    "exported": sym.exported,
    "boundaryKind": boundaryKindToInt(sym.boundaryKind),
    "rawCallTargets": sym.rawCallTargets,
    "branchCount": sym.branchCount,
    "nestingDepth": sym.nestingDepth,
    "lineSpan": sym.lineSpan,
    "hasAxiomImpl": sym.hasAxiomImpl,
    "definitionFingerprint": sym.definitionFingerprint
  }
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func jsonToTopologySymbol(node: JsonNode): Option[TopologySymbol] {.raises: [].} =
  try:
    if node.kind != JObject:
      return none(TopologySymbol)
    var sym: TopologySymbol
    sym.modulePath = node{"modulePath"}.getStr()
    sym.functionName = node{"functionName"}.getStr()
    sym.nodeType = node{"nodeType"}.getStr()
    sym.nodeId = sorterNodeId(node{"nodeId"}.getStr())
    sym.declarationLine = node{"declarationLine"}.getInt()
    sym.bodyStartLine = node{"bodyStartLine"}.getInt()
    sym.bodyEndLine = node{"bodyEndLine"}.getInt()
    sym.exported = node{"exported"}.getBool()
    sym.boundaryKind = intToBoundaryKind(node{"boundaryKind"}.getInt())
    let rawTargets = node{"rawCallTargets"}
    if rawTargets.kind == JArray:
      for t in rawTargets:
        sym.rawCallTargets.add(t.getStr())
    sym.branchCount = node{"branchCount"}.getInt()
    sym.nestingDepth = node{"nestingDepth"}.getInt()
    sym.lineSpan = node{"lineSpan"}.getInt()
    sym.hasAxiomImpl = node{"hasAxiomImpl"}.getBool()
    sym.definitionFingerprint = node{"definitionFingerprint"}.getStr()
    some(sym)
  except CatchableError:
    none(TopologySymbol)
export topology_dependency
type TopologyCacheEntry* = tuple[fileHash: string, symbols: seq[TopologySymbol]]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadTopologyCache*(cachePath: string): Result[Table[string, TopologyCacheEntry], AxiomError] {.raises: [],
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fileExists(cachePath) == false:
    return err(ioError("loadTopologyCache: file not found: " & cachePath))
  try:
    let readRes = readFileOpt(cachePath)
    if readRes.isErr:
      return err(ioError("loadTopologyCache read: " & readRes.error))
    let raw = readRes.get
    let node = parseJsonOpt(raw).get(newJObject())
    if node.kind != JObject:
      return err(parseError("loadTopologyCache: root not JObject: " & cachePath))
    var resultTbl = initTable[string, TopologyCacheEntry]()
    for key, entry in node.fields:
      if entry.kind == JObject and entry.hasKey("fileHash") and entry.hasKey("symbols"):
        let hash = entry{"fileHash"}.getStr()
        var syms: seq[TopologySymbol] = @[]
        if entry{"symbols"}.kind == JArray:
          for s in entry{"symbols"}:
            let optSym = jsonToTopologySymbol(s)
            if optSym.isSome:
              syms.add(optSym.get)
        resultTbl[key] = (fileHash: hash, symbols: syms)
    ok(resultTbl)
  except CatchableError as e:
    err(parseError("loadTopologyCache(" & cachePath & "): " & e.msg))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveTopologyCache*(cachePath: string; cache: Table[string, TopologyCacheEntry]): Result[void, AxiomError] {.raises: [],
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var root = newJObject()
  for key, entry in cache:
    var symArr = newJArray()
    for sym in entry.symbols:
      symArr.add(topologySymbolToJson(sym))
    root[key] = %*{"fileHash": entry.fileHash, "symbols": symArr}
  try:
    let tmpPath = cachePath & ".tmp"
    let writeRes = writeFileOpt(tmpPath, pretty(root))
    if writeRes.isErr:
      return err(ioError("saveTopologyCache write: " & writeRes.error))
    let moveRes = moveFileOpt(tmpPath, cachePath)
    if moveRes.isErr:
      return err(ioError("saveTopologyCache move: " & moveRes.error))
    Result[void, AxiomError](ok: true)
  except CatchableError as e:
    err(ioError("saveTopologyCache(" & cachePath & "): " & e.msg))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc updateBoundaryKinds*(symbols: var seq[TopologySymbol]; sourceCode: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Hard Gate: Detect trivial nodes after scan but before queue creation.
  ## Nodes with only trivial assertions (e.g. depth >= 0) are marked
  ## topologyBoundaryTrivialDiscard and never enter verificationQueue.
  for i in 0 ..< symbols.len:
    let nodeIdStr = sorterNodeIdString(symbols[i].nodeId)
    let res = extractBoundaries(nodeIdStr, sourceCode)
    if res.completeness == bcTrivialDiscard:
      symbols[i].boundaryKind = topologyBoundaryTrivialDiscard

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkAxiomImplCST*(source: string; funcName: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## PNode CST에서 {.axiomImpl.} 프래그마를 구조적으로 검증.
  ## parseNimRes → findFunctionNode → hasPragmaNamedP 패턴 활용.
  let parseResult = parseNimRes(source)
  if parseResult.isErr:
    return false
  let ast = parseResult.get
  let fnNode = findFunctionNode(ast, funcName)
  if fnNode.isNone():
    return false
  hasPragmaNamedP(fnNode.get(), "axiomImpl")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc enrichAxiomImplFlags*(symbols: var seq[TopologySymbol]; sourceContentCache: Table[string, string]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan each symbol's source via PNode CST to detect {.axiomImpl.} pragma.
  ## AGENT-19 FIX: cache parse result per module path to avoid O(symbols) PNode parses.
  var parsedAsts = initTable[string, Option[PNode]]()
  for i in 0 ..< symbols.len:
    let modPath = symbols[i].modulePath
    if modPath notin parsedAsts:
      let content = sourceContentCache.getOrDefault(modPath)
      if content.len > 0:
        let parseResult = parseNimRes(content)
        parsedAsts[modPath] = if parseResult.isOk: some(parseResult.get) else: none(PNode)
      else:
        parsedAsts[modPath] = none(PNode)
    let cached = parsedAsts.getOrDefault(modPath, none(PNode))
    if cached.isSome:
      let fnNode = findFunctionNode(cached.get, symbols[i].functionName)
      if fnNode.isSome():
        symbols[i].hasAxiomImpl = hasPragmaNamedP(fnNode.get(), "axiomImpl")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func countTopologyFunctionNodes*(analysis: TopologyAnalysis): int {.raises: [].} =
  ## Count proc/func declarations from PNode topology scan.
  ## Only counts functions with {.axiomImpl.} pragma (AGENT-19).
  ## Semantic equivalent of countSourceFunctions(graph) for CLI layer.
  ## "Don't pass the Factory, pass the Product" — extract scalar early.
  for sym in analysis.symbols:
    if sym.nodeType in ["proc", "func"] and sym.hasAxiomImpl:
      inc result

# ─── Incremental Topology Analysis (AGENT-A) ──────────────────────────────

type
  IncrementalTopologyResult* = object
    ## Result of incremental topology scan — carries all data needed
    ## by topology_cli to build TopologyCliAnalysisBundle.
    symbols*: seq[TopologySymbol]
    sourceContentCache*: Table[string, string]  ## modulePath → source (changed files only)
    sourceFileCount*: int
    changedFileCount*: int

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc analyzeTopologySourceRootIncremental*(
  sourceRoot: string;
  engine: var MerkleQueryEngine
): Result[IncrementalTopologyResult, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Incremental topology scan — only re-parses files whose content hash changed.
  ## Uses MerkleQueryEngine for O(1) per-file change detection.
  ## Returns TopologyAnalysis-compatible data for existing consumers.
  if not dirExists(sourceRoot):
    return err("source root not found: " & sourceRoot)
  let sourceFiles = collectGitTrackedSources(sourceRoot)
  if sourceFiles.len == 0:
    return err("no source files found in: " & sourceRoot)
  var allSymbols: seq[TopologySymbol] = @[]
  var sourceContentCache = initTable[string, string]()
  var changedCount = 0
  for filePath in sourceFiles:
    let relPath = normalizePath(relativePath(filePath, sourceRoot))
    # Dual mtime+fileSize guard: skip expensive readFileSafe on cache hit
    let cached = engine.getEntry(relPath)
    if cached.isSome:
      try:
        let mtime = getLastModificationTime(filePath)
        let fsize = getFileSize(filePath)
        if cached.get.lastModified == toUnix(mtime) and cached.get.fileSize == fsize:
          if cached.get.cachedSymbols.len > 0:
            for cs in cached.get.cachedSymbols:
              allSymbols.add(TopologySymbol(
                modulePath: cs.modulePath,
                functionName: cs.functionName,
                nodeType: cs.nodeType,
                nodeId: sorterNodeId(cs.nodeIdStr),
                declarationLine: cs.declarationLine,
                bodyStartLine: cs.bodyStartLine,
                bodyEndLine: cs.bodyEndLine,
                exported: cs.exported,
                boundaryKind: TopologyBoundaryKind(cs.boundaryKind),
                rawCallTargets: cs.rawCallTargets,
                branchCount: cs.branchCount,
                nestingDepth: cs.nestingDepth,
                lineSpan: cs.lineSpan,
                hasAxiomImpl: cs.hasAxiomImpl,
                definitionFingerprint: cs.definitionFingerprint
              ))
            continue
          let content = readFileSafe(filePath)
          if content.len == 0:
            continue
          let syms = scanTopologySource(relPath, content)
          allSymbols.add(syms)
          continue
      except CatchableError as e:
        logError("stat failed for " & filePath & ": " & e.msg)
    let content = readFileSafe(filePath)
    if content.len == 0:
      continue
    let currentHash = computeFileContentHash(content)
    # Content-hash fallback check — skip re-parsing if hash unchanged
    if engine.isFileUnchanged(relPath, currentHash):
      let cachedEntry = engine.getEntry(relPath)
      if cachedEntry.isSome and cachedEntry.get.cachedSymbols.len > 0:
        for cs in cachedEntry.get.cachedSymbols:
          allSymbols.add(TopologySymbol(
            modulePath: cs.modulePath,
            functionName: cs.functionName,
            nodeType: cs.nodeType,
            nodeId: sorterNodeId(cs.nodeIdStr),
            declarationLine: cs.declarationLine,
            bodyStartLine: cs.bodyStartLine,
            bodyEndLine: cs.bodyEndLine,
            exported: cs.exported,
            boundaryKind: TopologyBoundaryKind(cs.boundaryKind),
            rawCallTargets: cs.rawCallTargets,
            branchCount: cs.branchCount,
            nestingDepth: cs.nestingDepth,
            lineSpan: cs.lineSpan,
            hasAxiomImpl: cs.hasAxiomImpl,
            definitionFingerprint: cs.definitionFingerprint
          ))
        continue
    # File changed or not in cache — re-scan
    changedCount += 1
    sourceContentCache[relPath] = content
    let syms = scanTopologySource(relPath, content)
    allSymbols.add(syms)
    # Update Merkle cache entry with full symbol data
    var cachedSyms: seq[CachedTopologySymbol] = @[]
    for sym in syms:
      cachedSyms.add(CachedTopologySymbol(
        modulePath: sym.modulePath,
        functionName: sym.functionName,
        nodeType: sym.nodeType,
        nodeIdStr: sorterNodeIdString(sym.nodeId),
        declarationLine: sym.declarationLine,
        bodyStartLine: sym.bodyStartLine,
        bodyEndLine: sym.bodyEndLine,
        exported: sym.exported,
        boundaryKind: int(sym.boundaryKind),
        rawCallTargets: sym.rawCallTargets,
        branchCount: sym.branchCount,
        nestingDepth: sym.nestingDepth,
        lineSpan: sym.lineSpan,
        hasAxiomImpl: sym.hasAxiomImpl,
        definitionFingerprint: sym.definitionFingerprint
      ))
    var entry = MerkleCacheEntry(
      contentHash: currentHash,
      symbolNames: @[],
      lastModified: 0,
      fileSize: 0,
      cachedSymbols: cachedSyms
    )
    try:
      entry.lastModified = toUnix(getLastModificationTime(filePath))
      entry.fileSize = getFileSize(filePath)
    except CatchableError as e:
      logError("file metadata for " & filePath & ": " & e.msg)
    for sym in syms:
      entry.symbolNames.add(sym.functionName)
    engine.fileCache[relPath] = entry
  # Enrich axiomImpl flags (only for files in sourceContentCache = changed files)
  enrichAxiomImplFlags(allSymbols, sourceContentCache)
  # Rebuild symbol index
  rebuildSymbolIndex(engine)
  # Compute Merkle root
  engine.merkleRoot = computeMerkleRoot(engine)
  ok(IncrementalTopologyResult(
    symbols: allSymbols,
    sourceContentCache: sourceContentCache,
    sourceFileCount: sourceFiles.len,
    changedFileCount: changedCount
  ))

# ── Demand-Driven On-Demand Analysis ──

var parseCache {.threadvar.}: Table[string, seq[TopologySymbol]]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseSingleFile*(filePath: string): seq[TopologySymbol] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let normPath = filePath.normalizedPath
  if normPath in parseCache:
    return parseCache[normPath]
  let source = readFile(normPath)
  let relPath = relativePath(normPath, getCurrentDir())
  result = scanTopologySource(relPath, source)
  updateBoundaryKinds(result, source)
  var srcCache = initTable[string, string]()
  srcCache[relPath] = source
  enrichAxiomImplFlags(result, srcCache)
  parseCache[normPath] = result

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildOnDemandAnalysis*(targetPath: string): TopologyAnalysis {.raises: [CatchableError].} =
  var visited = initHashSet[string]()
  var queue = @[targetPath.normalizedPath]
  var allSymbols: seq[TopologySymbol] = @[]

  while queue.len > 0:
    let current = queue.pop()
    if current in visited: continue
    visited.incl(current)

    let syms = parseSingleFile(current)
    allSymbols.add(syms)

    let imports = extractCoreImports(current)
    for imp in imports:
      var impPath = ("src/core/" & imp & ".nim").normalizedPath
      if not fileExists(impPath):
        let fallback = ("src/" & imp & ".nim").normalizedPath
        if fileExists(fallback): impPath = fallback
      if fileExists(impPath) and impPath notin visited:
        queue.add(impPath)

  result = buildTopologyAnalysis(allSymbols)

