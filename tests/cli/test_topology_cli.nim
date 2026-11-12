{.push raises: [].}

## Unit tests for topology_cli — pure business logic functions.
## Covers all exported procs/funcs: computation, enum mapping, JSON generation,
## I/O helpers (temp directory), and error paths.
## No stub tests — every check asserts real behavior.

import std/json
import std/os
import std/strutils
import std/tables
import std/unittest

import cli/cli_types
import cli/topology_cli
import core/contracts/universal_pipeline_contract
import core/diagnostics/diagnostics_engine_helpers
import core/orchestrator/orchestrator_report_types
import core/results
import core/sorter/sorter_core
import core/sorter/sorter_core_index_table
import core/topology/topology_types

# ── helpers ──────────────────────────────────────────────────────────────────

func makeAnalysis(
  nodes: seq[SorterNode] = @[];
  symbols: seq[TopologySymbol] = @[];
  metrics: seq[TopologyNodeMetric] = @[];
  verificationQueue: seq[SorterNodeId] = @[];
  structuralBottlenecks: seq[SorterNodeId] = @[];
  repairPriorityDependencies: seq[SorterNodeId] = @[];
): TopologyAnalysis =
  var mi = initTable[string, int]()
  for idx, m in metrics:
    mi[sorterNodeIdString(m.nodeId)] = idx
  var si = initTable[string, int]()
  for idx, s in symbols:
    si[sorterNodeIdString(s.nodeId)] = idx
  TopologyAnalysis(
    state: initSorterState(nodes),
    symbols: symbols,
    metrics: metrics,
    verificationQueue: verificationQueue,
    structuralBottlenecks: structuralBottlenecks,
    repairPriorityDependencies: repairPriorityDependencies,
    symbolFirstPass: true,
    metricIndex: mi,
    symbolIndex: si
  )

func makeDiag(
  nodeId: string;
  labels: seq[string] = @[];
  hint: string = "";
  rationale: string = "";
): StructuralDiagnosis =
  StructuralDiagnosis(
    nodeId: sorterNodeId(nodeId),
    diagnosticLabels: labels,
    remediationHint: hint,
    mathematicalRationale: rationale
  )

func makeSymbol(
  modPath, funcName, nodeTy, nid: string;
  exported: bool = false;
): TopologySymbol =
  TopologySymbol(
    modulePath: modPath,
    functionName: funcName,
    nodeType: nodeTy,
    nodeId: sorterNodeId(nid),
    exported: exported,
    boundaryKind: topologyBoundaryNone,
    rawCallTargets: @[]
  )

func defaultPayload(): SemanticEqualityPayload =
  SemanticEqualityPayload(
    schemaVersion: SemanticPayloadSchemaVersion("axiom.semantic-payload.v1"),
    modulePath: SemanticModulePath("src/mod.nim"),
    functionName: SemanticFunctionName("foo"),
    enumTypeName: SemanticEnumTypeName("Color"),
    leftSymbol: SemanticSymbolName("RED"),
    rightSymbol: SemanticSymbolName("BLUE"),
    throwsSymbol: SemanticSymbolName("ERR"),
    enumValues: @[],
    proofGoal: semanticGoalEqualValuesDoNotThrow,
    unsatCore: @[]
  )

# ── computeTopologyNodeDepths ────────────────────────────────────────────────

suite "computeTopologyNodeDepths":
  test "empty node list yields empty result":
    let state = initSorterState(@[])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    check depths.len == 0

  test "single node with no deps has depth 0":
    let nodeA = makeSorterNode("mod", "fn_a", sorterNodeId("a"), @[], "func")
    let state = initSorterState(@[nodeA])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    check depths.len == 1
    check depths[0] == 0

  test "node depending on leaf gets depth 1":
    # Nodes in reverse-dep order: leaf first (idx 0), dependent second (idx 1)
    let nodeLeaf = makeSorterNode("mod", "leaf", sorterNodeId("leaf"), @[], "func")
    let nodeDep = makeSorterNode("mod", "dep", sorterNodeId("dep"), @[sorterNodeId("leaf")], "func")
    let state = initSorterState(@[nodeLeaf, nodeDep])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    check depths.len == 2
    check depths[0] == 0  # leaf
    check depths[1] == 1  # dep depends on leaf

  test "chain of three: depths are 0, 1, 2":
    # Algorithm iterates high→low; dependents must come before dependencies
    let n2 = makeSorterNode("m", "root", sorterNodeId("n2"), @[sorterNodeId("n1")], "func")
    let n1 = makeSorterNode("m", "mid", sorterNodeId("n1"), @[sorterNodeId("n0")], "func")
    let n0 = makeSorterNode("m", "leaf", sorterNodeId("n0"), @[], "func")
    let state = initSorterState(@[n2, n1, n0])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    # root(idx0)=2, mid(idx1)=1, leaf(idx2)=0
    check depths == @[2, 1, 0]

  test "diamond dependency: max depth wins":
    # d depends on b and c; b and c depend on a
    let d = makeSorterNode("m", "d", sorterNodeId("d"), @[sorterNodeId("b"), sorterNodeId("c")], "func")
    let b = makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")], "func")
    let c = makeSorterNode("m", "c", sorterNodeId("c"), @[sorterNodeId("a")], "func")
    let a = makeSorterNode("m", "a", sorterNodeId("a"), @[], "func")
    let state = initSorterState(@[d, b, c, a])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    check depths[3] == 0  # a (leaf)
    check depths[1] == 1  # b depends on a
    check depths[2] == 1  # c depends on a
    check depths[0] == 2  # d depends on b,c

  test "missing dependency in table is skipped (treated as depth 0)":
    # b depends on ghost (not in table), a is leaf
    let b = makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("ghost")], "func")
    let a = makeSorterNode("m", "a", sorterNodeId("a"), @[], "func")
    let state = initSorterState(@[b, a])
    let table = buildNodeIndexTable(state)
    let depths = computeTopologyNodeDepths(state, table)
    check depths[0] == 0  # ghost not found → depIdx < 0 → skipped → output stays 0
    check depths[1] == 0  # leaf

# ── topologyImpactIndex ──────────────────────────────────────────────────────

suite "topologyImpactIndex":
  test "all zeros yields 0":
    let m = TopologyNodeMetric()
    check topologyImpactIndex(m) == 0

  test "weighted formula verification":
    # impact = transitiveDependentCount*5 + dependentCount*3 + centralityScore + couplingScore
    let m = TopologyNodeMetric(
      transitiveDependentCount: 2,
      dependentCount: 3,
      centralityScore: 5,
      couplingScore: 7
    )
    # 2*5 + 3*3 + 5 + 7 = 10 + 9 + 5 + 7 = 31
    check topologyImpactIndex(m) == 31

  test "large values do not overflow":
    let m = TopologyNodeMetric(
      transitiveDependentCount: 1000,
      dependentCount: 500,
      centralityScore: 100,
      couplingScore: 200
    )
    # 5000 + 1500 + 100 + 200 = 6800
    check topologyImpactIndex(m) == 6800

# ── axProofStatusValue ───────────────────────────────────────────────────────

suite "axProofStatusValue":
  test "axProofVerified maps to verifiedKey":
    check axProofStatusValue(axProofVerified) == "verified"

  test "axProofCounterExampleFound":
    check axProofStatusValue(axProofCounterExampleFound) == "counter_example_found"

  test "axProofTimedOut":
    check axProofStatusValue(axProofTimedOut) == "timed_out"

  test "axProofUnverifiable":
    check axProofStatusValue(axProofUnverifiable) == "unverifiable"

  test "axProofUnattempted maps to unattemptedKey":
    check axProofStatusValue(axProofUnattempted) == "unattempted"

  test "axProofVacuousContradiction":
    check axProofStatusValue(axProofVacuousContradiction) == "vacuous_contradiction"

  test "axProofBlocked":
    check axProofStatusValue(axProofBlocked) == "blocked"

  test "axProofUnknown":
    check axProofStatusValue(axProofUnknown) == "unknown"

# ── mapAxProofStatus ─────────────────────────────────────────────────────────

suite "mapAxProofStatus":
  test "orchestrationVerified -> axProofVerified":
    check mapAxProofStatus(orchestrationVerified) == axProofVerified

  test "orchestrationProofFailed -> axProofCounterExampleFound":
    check mapAxProofStatus(orchestrationProofFailed) == axProofCounterExampleFound

  test "orchestrationTimedOut -> axProofTimedOut":
    check mapAxProofStatus(orchestrationTimedOut) == axProofTimedOut

  test "orchestrationVacuousContradiction -> axProofVacuousContradiction":
    check mapAxProofStatus(orchestrationVacuousContradiction) == axProofVacuousContradiction

  test "orchestrationBlocked -> axProofUnknown (fallback)":
    check mapAxProofStatus(orchestrationBlocked) == axProofUnknown

  test "orchestrationInductiveValid -> axProofUnknown (fallback)":
    check mapAxProofStatus(orchestrationInductiveValid) == axProofUnknown

  test "orchestrationPreSievedUnverifiable -> axProofUnknown (fallback)":
    check mapAxProofStatus(orchestrationPreSievedUnverifiable) == axProofUnknown

# ── mapSemanticProofStatus ───────────────────────────────────────────────────

suite "mapSemanticProofStatus":
  test "verified=true -> axProofVerified":
    let res = SemanticPayloadVerificationResponse(verified: true, status: "")
    check mapSemanticProofStatus(res) == axProofVerified

  test "status=sat -> axProofCounterExampleFound":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "sat")
    check mapSemanticProofStatus(res) == axProofCounterExampleFound

  test "status=unsat -> axProofTimedOut (else branch)":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "unsat")
    check mapSemanticProofStatus(res) == axProofTimedOut

  test "empty status -> axProofTimedOut":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "")
    check mapSemanticProofStatus(res) == axProofTimedOut

  test "status=unknown -> axProofTimedOut (not sat, not verified)":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "unknown")
    check mapSemanticProofStatus(res) == axProofTimedOut

  test "status=SAT (uppercase) -> axProofCounterExampleFound (case-insensitive)":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "SAT")
    check mapSemanticProofStatus(res) == axProofCounterExampleFound

# ── semanticProofNodeId ──────────────────────────────────────────────────────

suite "semanticProofNodeId":
  test "concatenates modulePath::functionName":
    let payload = defaultPayload()
    check semanticProofNodeId(payload) == "src/mod.nim::foo"

  test "empty path and function":
    var p = defaultPayload()
    p.modulePath = SemanticModulePath("")
    p.functionName = SemanticFunctionName("")
    check semanticProofNodeId(p) == "::"

# ── semanticProofLabel ───────────────────────────────────────────────────────

suite "semanticProofLabel":
  test "extracts filename from path":
    let payload = defaultPayload()
    check semanticProofLabel(payload) == "mod.nim::foo"

  test "path with no slashes":
    var p = defaultPayload()
    p.modulePath = SemanticModulePath("foo.nim")
    p.functionName = SemanticFunctionName("baz")
    check semanticProofLabel(p) == "foo.nim::baz"

# ── semanticProofFailureReason ───────────────────────────────────────────────

suite "semanticProofFailureReason":
  test "verified -> empty string":
    let res = SemanticPayloadVerificationResponse(verified: true, status: "")
    check semanticProofFailureReason(res) == ""

  test "sat -> semantic proof failed":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "sat")
    check semanticProofFailureReason(res) == "semantic proof failed"

  test "unknown -> solver returned unknown":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "unknown")
    check semanticProofFailureReason(res) == "semantic solver returned unknown"

  test "other status -> inconclusive":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "timeout")
    check semanticProofFailureReason(res) == "semantic proof inconclusive"

  test "empty status -> inconclusive":
    let res = SemanticPayloadVerificationResponse(verified: false, status: "")
    check semanticProofFailureReason(res) == "semantic proof inconclusive"

# ── computeSmartQueueLimit ───────────────────────────────────────────────────

suite "computeSmartQueueLimit":
  test "zero planned -> 1 (max with floor of 1)":
    check computeSmartQueueLimit(0, 4) == 1

  test "planned < proc*4 -> returns planned":
    check computeSmartQueueLimit(5, 4) == 5  # min(5, 16) = 5

  test "planned > proc*4 -> returns proc*4":
    check computeSmartQueueLimit(100, 4) == 16  # min(100, 16) = 16

  test "zero processors -> 1 (max with floor)":
    check computeSmartQueueLimit(10, 0) == 1  # max(1, min(10, 0)) = max(1, 0) = 1

  test "one processor, one planned":
    check computeSmartQueueLimit(1, 1) == 1

  test "large numbers":
    check computeSmartQueueLimit(10000, 256) == 1024  # min(10000, 256*4)

# ── computeSmartDiagnosisDepth ───────────────────────────────────────────────

suite "computeSmartDiagnosisDepth":
  test "zero targets -> 1 (floor)":
    check computeSmartDiagnosisDepth(0, 4) == 1

  test "targets < proc*2 -> returns targets":
    check computeSmartDiagnosisDepth(3, 4) == 3  # min(3, 8) = 3

  test "targets > proc*2 -> returns proc*2":
    check computeSmartDiagnosisDepth(100, 4) == 8  # min(100, 8) = 8

  test "zero processors -> 1 (floor)":
    check computeSmartDiagnosisDepth(10, 0) == 1

  test "one processor, one target":
    check computeSmartDiagnosisDepth(1, 1) == 1

# ── nodeIdsToLabels ──────────────────────────────────────────────────────────

suite "nodeIdsToLabels":
  test "empty ids -> empty labels":
    let state = initSorterState(@[])
    check nodeIdsToLabels(state, @[]).len == 0

  test "maps node IDs to labels via state":
    let n0 = makeSorterNode("mod_a", "func_x", sorterNodeId("id0"), @[], "func")
    let n1 = makeSorterNode("mod_b", "func_y", sorterNodeId("id1"), @[], "func")
    let state = initSorterState(@[n0, n1])
    let labels = nodeIdsToLabels(state, @[sorterNodeId("id0"), sorterNodeId("id1")])
    check labels.len == 2
    check "func_x" in labels[0]
    check "func_y" in labels[1]

# ── jsonFromTopologyAnalysis ─────────────────────────────────────────────────

suite "jsonFromTopologyAnalysis":
  test "empty analysis produces correct summary structure":
    let analysis = makeAnalysis()
    let j = jsonFromTopologyAnalysis(analysis, @[], 0, 0, 1)
    check j["summary"]["topologyScanComplete"].getBool() == true
    check j["summary"]["symbolCount"].getInt() == 0
    check j["summary"]["plannedNodeCount"].getInt() == 0
    check j["summary"]["effectiveQueueLimit"].getInt() == 0
    check j["summary"]["effectiveDiagnosisDepth"].getInt() == 1
    check j["summary"]["bodyLoadCount"].getInt() == 0
    check j["verificationQueue"].len == 0
    check j["diagnostics"].len == 0

  test "queueLimit=0 means unlimited":
    let nid = sorterNodeId("n1")
    let metric = TopologyNodeMetric(nodeId: nid, topologyScore: 10)
    let sym = makeSymbol("mod.nim", "fn", "func", "n1")
    let mi = {"n1": 0}.toTable
    let si = {"n1": 0}.toTable
    let analysis = TopologyAnalysis(
      state: initSorterState(@[]),
      symbols: @[sym],
      metrics: @[metric],
      verificationQueue: @[nid],
      symbolFirstPass: true,
      metricIndex: mi,
      symbolIndex: si
    )
    let j = jsonFromTopologyAnalysis(analysis, @[], 0, 5, 2)
    check j["summary"]["plannedNodeCount"].getInt() == 1
    check j["summary"]["bodyLoadCount"].getInt() == 5
    check j["summary"]["effectiveDiagnosisDepth"].getInt() == 2

  test "queueLimit caps the preview":
    let n1 = sorterNodeId("n1")
    let n2 = sorterNodeId("n2")
    let m1 = TopologyNodeMetric(nodeId: n1)
    let m2 = TopologyNodeMetric(nodeId: n2)
    let s1 = makeSymbol("m", "f1", "func", "n1")
    let s2 = makeSymbol("m", "f2", "func", "n2")
    let mi = {"n1": 0, "n2": 1}.toTable
    let si = {"n1": 0, "n2": 1}.toTable
    let analysis = TopologyAnalysis(
      state: initSorterState(@[]),
      symbols: @[s1, s2],
      metrics: @[m1, m2],
      verificationQueue: @[n1, n2],
      symbolFirstPass: true,
      metricIndex: mi,
      symbolIndex: si
    )
    let j = jsonFromTopologyAnalysis(analysis, @[], 1, 0, 1)
    # queueLimit=1 → only first entry in preview
    check j["summary"]["plannedNodeCount"].getInt() == 1

  test "diagnoses are serialized in diagnostics array":
    let diag = makeDiag("d1", @["label_a"], "fix this", "rationale")
    let j = jsonFromTopologyAnalysis(makeAnalysis(), @[diag], 0, 0, 1)
    check j["diagnostics"].len == 1
    check j["diagnostics"][0]["nodeId"].getStr() == "d1"
    check j["diagnostics"][0]["diagnosticLabels"].len == 1

# ── jsonFromTopologyFrontier ─────────────────────────────────────────────────

suite "jsonFromTopologyFrontier":
  test "uses explicit frontier instead of queue slice":
    let n1 = sorterNodeId("n1")
    let m1 = TopologyNodeMetric(nodeId: n1)
    let s1 = makeSymbol("m", "f1", "func", "n1")
    let mi = {"n1": 0}.toTable
    let si = {"n1": 0}.toTable
    let analysis = TopologyAnalysis(
      state: initSorterState(@[]),
      symbols: @[s1],
      metrics: @[m1],
      verificationQueue: @[n1],
      symbolFirstPass: true,
      metricIndex: mi,
      symbolIndex: si
    )
    let j = jsonFromTopologyFrontier(analysis, @[], @[n1], 3, 1)
    check j["summary"]["bodyLoadCount"].getInt() == 3
    check j["summary"]["effectiveDiagnosisDepth"].getInt() == 1

  test "empty frontier yields zero queue entries":
    let j = jsonFromTopologyFrontier(makeAnalysis(), @[], @[], 0, 1)
    check j["verificationQueue"].len == 0

# ── renderVerifyTopologySummaryLines ─────────────────────────────────────────

suite "renderVerifyTopologySummaryLines":
  test "empty analysis with no diagnoses":
    let analysis = makeAnalysis()
    let lines = renderVerifyTopologySummaryLines(analysis, @[])
    check lines.len == 3
    check lines[0] == "Topology Scan: Complete"
    check lines[1] == "Structural Bottlenecks: None"
    check lines[2] == "Top Dependencies Needing Repair: None"

  test "includes bottleneck labels when present":
    let n0 = makeSorterNode("mod", "funcA", sorterNodeId("n0"), @[], "func")
    let analysis = makeAnalysis(
      nodes = @[n0],
      structuralBottlenecks = @[sorterNodeId("n0")]
    )
    let lines = renderVerifyTopologySummaryLines(analysis, @[])
    check "None" notin lines[1]
    check "funcA" in lines[1]

  test "includes repair target labels when present":
    let n0 = makeSorterNode("mod", "funcB", sorterNodeId("n0"), @[], "func")
    let analysis = makeAnalysis(
      nodes = @[n0],
      repairPriorityDependencies = @[sorterNodeId("n0")]
    )
    let lines = renderVerifyTopologySummaryLines(analysis, @[])
    check "None" notin lines[2]
    check "funcB" in lines[2]

  test "adds priority diagnosis line when diagnoses present":
    let diag = makeDiag("n0", @["high_complexity"])
    let n0 = makeSorterNode("mod", "hotFunc", sorterNodeId("n0"), @[], "func")
    let analysis = makeAnalysis(nodes = @[n0])
    let lines = renderVerifyTopologySummaryLines(analysis, @[diag])
    check lines.len == 4
    check "Top Priority Structural Diagnosis" in lines[3]
    check "hotFunc" in lines[3]
    check "high_complexity" in lines[3]

  test "empty diagnosis labels does not add extra line":
    let diag = makeDiag("n0", @[])
    let analysis = makeAnalysis()
    let lines = renderVerifyTopologySummaryLines(analysis, @[diag])
    check lines.len == 3  # no 4th line

# ── excludedTopologyDirs ─────────────────────────────────────────────────────

suite "excludedTopologyDirs":
  test "contains expected excluded directories":
    check "build" in excludedTopologyDirs
    check ".git" in excludedTopologyDirs
    check "vendor" in excludedTopologyDirs
    check "node_modules" in excludedTopologyDirs
    check "nimcache" in excludedTopologyDirs
    check "semantic_proofs" in excludedTopologyDirs

# ── collectTopologySourceFiles (I/O) ────────────────────────────────────────

suite "collectTopologySourceFiles (I/O)":
  test "collects .nim files from temp directory":
    let tmpDir = getTempDir() / "axiom_test_topo_collect"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    writeFile(tmpDir / "good.nim", "proc foo*() = discard\n")
    writeFile(tmpDir / "also_good.nim", "func bar*() = 42\n")
    writeFile(tmpDir / "readme.txt", "not a nim file")
    let files = collectTopologySourceFiles(tmpDir)
    check files.len == 2
    # Deterministic ordering due to sort()
    check files[0].endsWith("also_good.nim")
    check files[1].endsWith("good.nim")

  test "excludes build directory":
    let tmpDir = getTempDir() / "axiom_test_topo_excl"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    createDir(tmpDir / "build")
    writeFile(tmpDir / "main.nim", "proc x*() = discard\n")
    writeFile(tmpDir / "build" / "generated.nim", "proc y*() = discard\n")
    let files = collectTopologySourceFiles(tmpDir)
    check files.len == 1
    check files[0].endsWith("main.nim")

  test "empty directory yields empty list":
    let tmpDir = getTempDir() / "axiom_test_topo_empty"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    let files = collectTopologySourceFiles(tmpDir)
    check files.len == 0

# ── normalizeTopologyModulePath (I/O) ───────────────────────────────────────

suite "normalizeTopologyModulePath (I/O)":
  test "produces relative path from sourceRoot":
    let root = "/project/src"
    let file = "/project/src/cli/foo.nim"
    let result = normalizeTopologyModulePath(root, file)
    check result == "cli/foo.nim"

  test "file at root level":
    let result = normalizeTopologyModulePath("/p", "/p/file.nim")
    check result == "file.nim"

# ── loadSourceSlice (I/O) ───────────────────────────────────────────────────

suite "loadSourceSlice (I/O)":
  test "non-existent file returns empty string":
    let result = loadSourceSlice("/nonexistent/path.nim", 1, 10)
    check result == ""

  test "loads specified line range":
    let tmpDir = getTempDir() / "axiom_test_topo_slice"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    let filePath = tmpDir / "test.nim"
    writeFile(filePath, "line1\nline2\nline3\nline4\nline5\n")
    let slice = loadSourceSlice(filePath, 2, 4)
    check slice == "line2\nline3\nline4"

  test "startLine=1 loads from beginning":
    let filePath = getTempDir() / "axiom_test_topo_slice2" / "a.nim"
    defer: removeDir(getTempDir() / "axiom_test_topo_slice2")
    createDir(getTempDir() / "axiom_test_topo_slice2")
    writeFile(filePath, "aaa\nbbb\nccc\n")
    let slice = loadSourceSlice(filePath, 1, 2)
    check slice == "aaa\nbbb"

  test "endLine beyond file length clamps to last line":
    let tmpDir = getTempDir() / "axiom_test_topo_slice3"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    let filePath = tmpDir / "b.nim"
    writeFile(filePath, "x\ny\n")
    let slice = loadSourceSlice(filePath, 1, 100)
    check slice.len > 0
    check "x" in slice
    check "y" in slice

# ── analyzeTopologySourceRoot (I/O) ──────────────────────────────────────────

suite "analyzeTopologySourceRoot (I/O)":
  test "non-existent directory returns error":
    let res = analyzeTopologySourceRoot("/nonexistent/path/xyz")
    check res.isErr()
    check "source root not found" in res.error

  test "empty directory returns error (no source files)":
    let tmpDir = getTempDir() / "axiom_test_topo_analyze_empty"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    let res = analyzeTopologySourceRoot(tmpDir)
    check res.isErr()
    check "no source files found" in res.error

  test "directory with .nim files succeeds":
    let tmpDir = getTempDir() / "axiom_test_topo_analyze_ok"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    writeFile(tmpDir / "mod.nim", "proc foo*() = discard\n")
    let res = analyzeTopologySourceRoot(tmpDir)
    check res.isOk()
    let bundle = res.get()
    check bundle.sourceFileCount == 1
    check bundle.effectiveQueueLimit == 200  # default
    check bundle.effectiveDiagnosisDepth >= 1

  test "diagnosisDepthExplicit overrides automatic depth":
    let tmpDir = getTempDir() / "axiom_test_topo_analyze_depth"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    writeFile(tmpDir / "mod.nim", "func bar*() = 42\n")
    let res = analyzeTopologySourceRoot(tmpDir, diagnosisDepth = 5, diagnosisDepthExplicit = true)
    check res.isOk()
    check res.get().effectiveDiagnosisDepth == 5

  test "queueLimitExplicit passes through":
    let tmpDir = getTempDir() / "axiom_test_topo_analyze_ql"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    writeFile(tmpDir / "mod.nim", "proc baz*() = discard\n")
    let res = analyzeTopologySourceRoot(tmpDir, queueLimit = 10, queueLimitExplicit = true)
    check res.isOk()
    check res.get().effectiveQueueLimit == 10

  test "sourceContentCache is populated":
    let tmpDir = getTempDir() / "axiom_test_topo_analyze_cache"
    defer: removeDir(tmpDir)
    createDir(tmpDir)
    writeFile(tmpDir / "cached.nim", "let x = 1\n")
    let res = analyzeTopologySourceRoot(tmpDir)
    check res.isOk()
    let cache = res.get().sourceContentCache
    check cache.len == 1
    check "let x = 1" in cache["cached.nim"]

{.pop.}
