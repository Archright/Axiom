## merkle_cache.nim — symbolNames persistence contract.
##
## symbolNames is a projection of cachedSymbols[].functionName and is no longer
## persisted. These tests pin: (a) new-format entries derive it, (b) legacy
## entries carrying it parse to the same engine, (c) zero-symbol files stay
## empty, (d) save/load round-trips cachedSymbols and derived order exactly.

import std/[json, os, tables, unittest]

import core/topology/merkle_cache
import core/types/results

const ModulePath = "test/module.nim"

proc testSymbol(name: string; line: int): CachedTopologySymbol =
  CachedTopologySymbol(
    modulePath: ModulePath,
    functionName: name,
    nodeType: "proc",
    nodeIdStr: ModulePath & "::" & name,
    declarationLine: line,
    bodyStartLine: line,
    bodyEndLine: line + 2,
    exported: true,
    boundaryKind: 1,
    rawCallTargets: @["helper"],
    branchCount: 0,
    nestingDepth: 1,
    lineSpan: 3,
    hasAxiomImpl: false,
    definitionFingerprint: "fp-" & name
  )

proc symbolJson(sym: CachedTopologySymbol): JsonNode =
  %*{
    "modulePath": sym.modulePath,
    "functionName": sym.functionName,
    "nodeType": sym.nodeType,
    "nodeIdStr": sym.nodeIdStr,
    "declarationLine": sym.declarationLine,
    "bodyStartLine": sym.bodyStartLine,
    "bodyEndLine": sym.bodyEndLine,
    "exported": sym.exported,
    "boundaryKind": sym.boundaryKind,
    "rawCallTargets": sym.rawCallTargets,
    "branchCount": sym.branchCount,
    "nestingDepth": sym.nestingDepth,
    "lineSpan": sym.lineSpan,
    "hasAxiomImpl": sym.hasAxiomImpl,
    "definitionFingerprint": sym.definitionFingerprint
  }

proc entryJson(symbols: seq[CachedTopologySymbol];
               withLegacySymbolNames: bool;
               legacyNames: seq[string] = @[]): JsonNode =
  var symbolsArray = newJArray()
  for sym in symbols:
    symbolsArray.add(symbolJson(sym))
  result = %*{
    "contentHash": "content-hash",
    "cstHash": "cst-hash",
    "lastModified": 123,
    "fileSize": 456,
    "cachedSymbols": symbolsArray
  }
  if withLegacySymbolNames:
    result["symbolNames"] = %legacyNames

proc writeCacheFile(path: string; entry: JsonNode) =
  var filesObj = newJObject()
  filesObj[ModulePath] = entry
  let root = %*{"files": filesObj, "merkleRoot": "root-hash"}
  writeFile(path, $root)

suite "Merkle cache symbolNames persistence":
  let tmpBase = getTempDir() / ("axiom_merkle_cache_test_" & $getCurrentProcessId())
  let legacyPath = tmpBase & "_legacy.json"
  let derivedPath = tmpBase & "_derived.json"
  let roundTripPath = tmpBase & "_roundtrip.json"
  let symbols = @[
    testSymbol("alpha", 3),
    testSymbol("beta", 10),
    testSymbol("alpha", 20)  # overload: duplicate names and order must survive
  ]
  let expectedNames = @["alpha", "beta", "alpha"]

  setup:
    for path in [legacyPath, derivedPath, roundTripPath]:
      if fileExists(path):
        removeFile(path)

  teardown:
    for path in [legacyPath, derivedPath, roundTripPath]:
      if fileExists(path):
        removeFile(path)

  test "(a) entry without symbolNames derives getSymbols and symbol index":
    writeCacheFile(legacyPath, entryJson(symbols, true, expectedNames))
    writeCacheFile(derivedPath, entryJson(symbols, false))

    let legacyRes = loadCache(legacyPath)
    let derivedRes = loadCache(derivedPath)
    check legacyRes.isOk
    check derivedRes.isOk

    var legacyEngine = legacyRes.get
    var derivedEngine = derivedRes.get

    check derivedEngine.getSymbols(ModulePath) == expectedNames
    check derivedEngine.getSymbols(ModulePath) == legacyEngine.getSymbols(ModulePath)

    rebuildSymbolIndex(derivedEngine)
    rebuildSymbolIndex(legacyEngine)
    check derivedEngine.symbolToFiles == legacyEngine.symbolToFiles
    check derivedEngine.symbolToFiles["alpha"] == @[ModulePath, ModulePath]
    check derivedEngine.symbolToFiles["beta"] == @[ModulePath]

  test "(b) legacy entry with symbolNames parses to the same structure":
    writeCacheFile(legacyPath, entryJson(symbols, true, expectedNames))
    writeCacheFile(derivedPath, entryJson(symbols, false))

    let legacyRes = loadCache(legacyPath)
    let derivedRes = loadCache(derivedPath)
    check legacyRes.isOk
    check derivedRes.isOk

    let legacyEntry = legacyRes.get.fileCache[ModulePath]
    let derivedEntry = derivedRes.get.fileCache[ModulePath]

    check legacyEntry.symbolNames == expectedNames
    check legacyEntry.symbolNames == derivedEntry.symbolNames
    check legacyEntry.cachedSymbols.len == symbols.len
    check legacyEntry.contentHash == derivedEntry.contentHash
    check legacyEntry.cstHash == derivedEntry.cstHash
    check legacyEntry.lastModified == derivedEntry.lastModified
    check legacyEntry.fileSize == derivedEntry.fileSize
    for i in 0 ..< symbols.len:
      check legacyEntry.cachedSymbols[i].functionName == symbols[i].functionName
      check legacyEntry.cachedSymbols[i].definitionFingerprint == symbols[i].definitionFingerprint

  test "(c) a file with zero symbols stays empty":
    writeCacheFile(derivedPath, entryJson(@[], false))
    writeCacheFile(legacyPath, entryJson(@[], true, @[]))

    for path in [derivedPath, legacyPath]:
      let res = loadCache(path)
      check res.isOk
      var engine = res.get
      check ModulePath in engine.fileCache
      check engine.getSymbols(ModulePath).len == 0
      rebuildSymbolIndex(engine)
      check engine.symbolToFiles.len == 0

  test "(d) save/load round-trip preserves cachedSymbols and derived order":
    var engine = MerkleQueryEngine()
    engine.merkleRoot = "root-hash"
    engine.fileCache[ModulePath] = MerkleCacheEntry(
      contentHash: "content-hash",
      cstHash: "cst-hash",
      symbolNames: @["stale-in-memory-value"],  # writer must not persist this
      lastModified: 123,
      fileSize: 456,
      cachedSymbols: symbols
    )

    let saveRes = saveCache(engine, roundTripPath)
    check saveRes.isOk

    let raw = parseJson(readFile(roundTripPath))
    check not raw["files"][ModulePath].hasKey("symbolNames")

    let loadRes = loadCache(roundTripPath)
    check loadRes.isOk
    var loaded = loadRes.get
    let entry = loaded.fileCache[ModulePath]
    check entry.cachedSymbols.len == symbols.len
    for i in 0 ..< symbols.len:
      check entry.cachedSymbols[i].functionName == symbols[i].functionName
      check entry.cachedSymbols[i].nodeIdStr == symbols[i].nodeIdStr
      check entry.cachedSymbols[i].definitionFingerprint == symbols[i].definitionFingerprint
    check entry.symbolNames == expectedNames
    check loaded.getSymbols(ModulePath) == expectedNames
    check loaded.symbolToFiles["alpha"] == @[ModulePath, ModulePath]
    check loaded.symbolToFiles["beta"] == @[ModulePath]