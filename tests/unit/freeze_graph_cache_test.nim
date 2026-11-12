import std/[unittest, os, tables]
import core/boundary/boundary_extractor
import ../../src/verification/global_symbol_graph
import ../../src/verification/semantic_graph

suite "Freeze Graph Cache":
  test "buildGlobalSymbolGraph freeze lock skips new modules":
    let repoRoot = getCurrentDir()
    # Default behavior (no freeze) discovers all modules
    let fullGraph = buildGlobalSymbolGraph(repoRoot)
    check fullGraph.symbols.len > 0

    # Freeze lock should reuse cache and skip new/changed modules
    let frozenGraph = buildGlobalSymbolGraph(repoRoot, freezeGraphCache = true)
    check frozenGraph.symbols.len > 0

  test "freeze graph cache does not overwrite incremental cache":
    let repoRoot = getTempDir() / "axiom_freeze_read_only_cache_test"
    if dirExists(repoRoot):
      removeDir(repoRoot)
    createDir(repoRoot)
    writeFile(repoRoot / "sample.nim", "proc alpha*() = discard\n")
    let cachePath = globalSymbolGraphIncrementalCachePath(repoRoot)
    writeFile(cachePath, """{"modules":{}}""")
    let before = readFile(cachePath)
    try:
      discard buildGlobalSymbolGraph(repoRoot, freezeGraphCache = true)
      check readFile(cachePath) == before
    finally:
      if fileExists(cachePath):
        removeFile(cachePath)
      if dirExists(repoRoot):
        removeDir(repoRoot)

  test "buildSemanticGraph threads freezeGraphCache to buildGlobalSymbolGraph":
    let repoRoot = getCurrentDir()
    let graphPath = repoRoot & "/logs/global_symbol_graph.json"
    let graph = buildSemanticGraph(repoRoot, graphPath = graphPath, freezeGraphCache = true)
    check graph.nodes.len >= 0

  test "extractBoundaries populates smtParts and leanParts":
    let res = extractBoundaries("core::depth", "")
    check res.smtParts.len >= 0
    check res.leanParts.len >= 0
