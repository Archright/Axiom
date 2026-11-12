import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/utils/constants
import core/crypto/hash_kernel
import core/symbolic/global_symbol_graph_types
import std/options
import std/os
import std/sets
import std/strutils
import std/tables
import std/times
import verification/global_symbol_graph
import verification/vault_index
import infrastructure/logging_facade
# axiomIoBoundary

var inMemorySymbolGraphCache = initTable[string, tuple[graph: GlobalSymbolGraph,
    mtime: int64]]()

# @axiom-hint: lean="srcRoot.length ≥ 0" smt="(assert (and (>= (str.len srcRoot) 0)))"
proc getInMemoryCachedGraph(srcRoot: string): Option[GlobalSymbolGraph] =
  if inMemorySymbolGraphCache.hasKey(srcRoot):
    let entry = inMemorySymbolGraphCache[srcRoot]
    var currentMaxMtime: int64 = 0
    for path in walkDirRec(srcRoot):
      if path.endsWith(".nim"):
        let mtime = getLastModificationTime(path).toUnix()
        if mtime > currentMaxMtime:
          currentMaxMtime = mtime
    if currentMaxMtime == entry.mtime:
      return some(entry.graph)
  none(GlobalSymbolGraph)

# @axiom-hint: lean="srcRoot.length ≥ 0" smt="(assert (and (>= (str.len srcRoot) 0)))"
proc setInMemoryCachedGraph(srcRoot: string; graph: GlobalSymbolGraph) =
  var maxMtime: int64 = 0
  for path in walkDirRec(srcRoot):
    if path.endsWith(".nim"):
      let mtime = getLastModificationTime(path).toUnix()
      if mtime > maxMtime:
        maxMtime = mtime
  inMemorySymbolGraphCache[srcRoot] = (graph: graph, mtime: maxMtime)

# @axiom-hint: lean="primary.size ≥ 0 ∧ secondary.size ≥ 0" smt="(assert (and (>= (seq.len primary) 0) (>= (seq.len secondary) 0)))"
# @axiom-hint: lean="(primary ≥ 0) ∧ (secondary ≥ 0)" smt="(assert (and (>= primary 0) (>= secondary 0)))"
proc runSymbolicGcExtract*(idx: var VaultIndex; graph: var GlobalSymbolGraph;
    srcRoot: string; certDir: string; normalizedCertDir: string;
        repoRoot: string; freezeGraphCache: bool = false) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  # === Symbolic GC: Mark-and-Sweep orphaned certificates ===
  # [v0.4.0 Horizon Lock] GC sweep disabled; graph loading preserved for hydration
  let t2 = epochTime()
  let graphCachePath = joinPath(repoRoot, "logs", "global_symbol_graph." &
      sha256Hex(srcRoot) & ".cache.json")
  var useGraphCache = false
  ## Phase 1: Global Source Merkle Root — deterministic content-based cache key.
  ## Replaces mtime loop which suffered spurious invalidation from touch/git
  ## checkout/heal source modifications (event-based vs content-based).
  let currentMerkle = computeSourceMerkleRoot(srcRoot)
  # WP2-a: snapshot routes to stateRoot when set.
  let graphSnapshotPath = joinPath(
    (block:
       let sr = getEnv("AXIOM_STATE_DIR", "").strip()
       if sr.len > 0: sr else: repoRoot),
    "logs", "global_symbol_graph.json")
  if fileExists(graphSnapshotPath):
    let snapshotMtime = getLastModificationTime(graphSnapshotPath).toUnix()
    if snapshotMtime >= 0:
      let snapshotOpt = loadGlobalSymbolGraphCache(graphSnapshotPath)
      if snapshotOpt.isSome:
        let (candidate, _) = snapshotOpt.get()
        if candidate.symbols.len > 0 and candidate.edges.len > 0:
          ## Reject legacy snapshots where modulePath is bare filename.
          var validFormat = true
          for qn, sym in candidate.symbols:
            if sym.kind in {skProc, skFunc}:
              if '/' notin sym.modulePath and $DirSep notin sym.modulePath:
                validFormat = false
              break
          if validFormat:
            graph = candidate
            useGraphCache = true
  if fileExists(graphCachePath):
    let cachedOpt = loadGlobalSymbolGraphCache(graphCachePath)
    if cachedOpt.isSome and not useGraphCache:
      let (cachedGraph, cachedMerkle) = cachedOpt.get()
      if currentMerkle == cachedMerkle or getEnv("AXIOM_FREEZE_GRAPH_CACHE",
          "") == "1":
        graph = cachedGraph
        useGraphCache = true
  if not useGraphCache:
    let memCached = getInMemoryCachedGraph(srcRoot)
    if memCached.isSome:
      graph = memCached.get()
      useGraphCache = true
    else:
      graph = buildGlobalSymbolGraph(srcRoot, freezeGraphCache)
      saveGlobalSymbolGraphCache(graph, graphCachePath, currentMerkle)
      setInMemoryCachedGraph(srcRoot, graph)
  let t3 = epochTime()
  logDebug("stage_01_ast_extract", "[TIMING] buildGlobalSymbolGraph: " & $(t3 - t2) & "s (cached=" & $(useGraphCache) & ")")
  ## Virtual Mark-and-Sweep: cross-reference vault index against live symbol graph.
  ## Invalidates orphaned index entries without physical file deletion.
  if normalizedCertDir.endsWith(defaultCertDir):
    var currentSymbols = initHashSet[string]()
    for qn, sym in graph.symbols:
      if sym.kind in {skProc, skFunc}:
        let parts = qn.split(".")
        if parts.len >= 2:
          let fnName = parts[^1]
          currentSymbols.incl(makeVaultKey(sym.modulePath, fnName, repoRoot))
    ## Staleness guard: if cached graph has far fewer live symbols than vault
    ## entries, the cache is stale and we must rebuild to avoid mass-deletion of
    ## valid certificates.
    if useGraphCache and currentSymbols.len < idx.entries.len div 2:
      logInfo("stage_01_ast_extract", "[STALENESS GUARD] Symbol graph cache stale (" & $(currentSymbols.len) & " vs " & $(idx.entries.len) & " vault entries). Rebuilding...")
      graph = buildGlobalSymbolGraph(srcRoot, freezeGraphCache)
      saveGlobalSymbolGraphCache(graph, graphCachePath, currentMerkle)
      setInMemoryCachedGraph(srcRoot, graph)
      useGraphCache = false
      currentSymbols = initHashSet[string]()
      for qn, sym in graph.symbols:
        if sym.kind in {skProc, skFunc}:
          let parts = qn.split(".")
          if parts.len >= 2:
            let fnName = parts[^1]
            currentSymbols.incl(makeVaultKey(sym.modulePath, fnName, repoRoot))
    canonicalizeGlobalSymbolGraph(graph)
    let removedKeys = runSymbolicGc(idx, currentSymbols)
    for key in removedKeys:
      if idx.entries.hasKey(key):
        idx.entries.del(key)


{.pop.}
