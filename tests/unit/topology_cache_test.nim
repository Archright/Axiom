import std/[unittest, os, json, tables, sequtils]
import core/topology/topology_engine, core/file_utils, sorter_core

suite "Topology Cache":
  let testCachePath = "tests/test_data/topology_cache_test.json"

  setup:
    if fileExists(testCachePath):
      removeFile(testCachePath)

  teardown:
    if fileExists(testCachePath):
      removeFile(testCachePath)

  test "computeFileHash returns consistent hash for same content":
    let testFile = "tests/test_data/cache_hash_test.nim"
    writeFile(testFile, "proc test(): int = 42\n")
    let hash1 = computeFileHash(testFile)
    let hash2 = computeFileHash(testFile)
    check hash1 == hash2
    check hash1.len == 32  # MD5 hex length
    removeFile(testFile)

  test "computeFileHash returns different hash for different content":
    let testFile = "tests/test_data/cache_hash_test.nim"
    writeFile(testFile, "proc test(): int = 42\n")
    let hash1 = computeFileHash(testFile)
    writeFile(testFile, "proc test(): int = 43\n")
    let hash2 = computeFileHash(testFile)
    check hash1 != hash2
    removeFile(testFile)

  test "computeFileHash returns empty string for missing file":
    let hash = computeFileHash("tests/test_data/nonexistent_file.nim")
    check hash == ""

  test "saveTopologyCache writes valid JSON":
    var cache = initTable[string, TopologyCacheEntry]()
    let sym = TopologySymbol(
      modulePath: "test/module.nim",
      functionName: "testFunc",
      nodeType: "func",
      nodeId: sorterNodeId("test/module.nim::testFunc"),
      declarationLine: 1,
      bodyStartLine: 1,
      bodyEndLine: 5,
      exported: true,
      boundaryKind: topologyBoundaryInterface,
      rawCallTargets: @[],
      branchCount: 0,
      nestingDepth: 1,
      lineSpan: 5
    )
    cache["test/module.nim"] = (fileHash: "abc123", symbols: @[sym])
    saveTopologyCache(testCachePath, cache)
    check fileExists(testCachePath)
    let raw = readFile(testCachePath)
    let node = parseJson(raw)
    check node.kind == JObject
    check node.hasKey("test/module.nim")

  test "loadTopologyCache reads back saved cache":
    var cache = initTable[string, TopologyCacheEntry]()
    let sym = TopologySymbol(
      modulePath: "test/module.nim",
      functionName: "testFunc",
      nodeType: "func",
      nodeId: sorterNodeId("test/module.nim::testFunc"),
      declarationLine: 1,
      bodyStartLine: 1,
      bodyEndLine: 5,
      exported: true,
      boundaryKind: topologyBoundaryInterface,
      rawCallTargets: @[],
      branchCount: 0,
      nestingDepth: 1,
      lineSpan: 5
    )
    cache["test/module.nim"] = (fileHash: "abc123", symbols: @[sym])
    saveTopologyCache(testCachePath, cache)
    let loaded = loadTopologyCache(testCachePath)
    check loaded.hasKey("test/module.nim")
    check loaded["test/module.nim"].fileHash == "abc123"
    check loaded["test/module.nim"].symbols.len == 1
    check loaded["test/module.nim"].symbols[0].functionName == "testFunc"

  test "loadTopologyCache returns empty table for missing file":
    let loaded = loadTopologyCache("tests/test_data/missing_cache.json")
    check loaded.len == 0

  test "loadTopologyCache returns empty table for invalid JSON":
    writeFile(testCachePath, "not valid json")
    let loaded = loadTopologyCache(testCachePath)
    check loaded.len == 0

  test "topologySymbolToJson round-trip preserves all fields":
    let sym = TopologySymbol(
      modulePath: "core/test.nim",
      functionName: "roundTrip",
      nodeType: "proc",
      nodeId: sorterNodeId("core/test.nim::roundTrip"),
      declarationLine: 10,
      bodyStartLine: 11,
      bodyEndLine: 20,
      exported: false,
      boundaryKind: topologyBoundaryTrivialDiscard,
      rawCallTargets: @["targetA", "targetB"],
      branchCount: 2,
      nestingDepth: 3,
      lineSpan: 10
    )
    let jsonNode = topologySymbolToJson(sym)
    let recovered = jsonToTopologySymbol(jsonNode)
    check recovered.modulePath == sym.modulePath
    check recovered.functionName == sym.functionName
    check recovered.nodeType == sym.nodeType
    check $recovered.nodeId == $sym.nodeId
    check recovered.declarationLine == sym.declarationLine
    check recovered.bodyStartLine == sym.bodyStartLine
    check recovered.bodyEndLine == sym.bodyEndLine
    check recovered.exported == sym.exported
    check recovered.boundaryKind == sym.boundaryKind
    check recovered.rawCallTargets == sym.rawCallTargets
    check recovered.branchCount == sym.branchCount
    check recovered.nestingDepth == sym.nestingDepth
    check recovered.lineSpan == sym.lineSpan
