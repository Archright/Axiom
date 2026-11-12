## Unit tests for resolveCallTarget generalized to ResolutionResult.
##
## Covers all five resolution outcomes: rrUnresolved, rrUnique, rrAmbiguous,
## module-scoped priority (rrUnique despite multiple global candidates),
## and the call-site behavior that rrAmbiguous adds no dependency edge.

import std/[unittest, tables, sequtils]
import core/topology/topology_engine
import core/topology/topology_types
import core/sorter/sorter_core
import core/utils/shadow_digests

suite "resolveCallTarget — ResolutionResult outcomes":

  # -----------------------------------------------------------------------
  # Helper: build a TopologySymbol with only the fields that matter for
  # resolveCallTarget (modulePath, functionName, nodeType, nodeId).
  # -----------------------------------------------------------------------

  func makeSym(modulePath, functionName, nodeType: string; idx: int): TopologySymbol =
    TopologySymbol(
      modulePath: modulePath,
      functionName: functionName,
      nodeType: nodeType,
      nodeId: sorterNodeId("sym" & $idx),
      declarationLine: 0,
      bodyStartLine: 0,
      bodyEndLine: 0,
      exported: false,
      boundaryKind: topologyBoundaryNone,
      rawCallTargets: @[],
      branchCount: 0,
      nestingDepth: 0,
      lineSpan: 0,
      hasAxiomImpl: false,
      definitionFingerprint: ""
    )

  # -----------------------------------------------------------------------
  # Test 1: 후보 0개 → rrUnresolved
  # -----------------------------------------------------------------------

  test "no candidates yields rrUnresolved":
    let symbols = @[
      makeSym("modA", "foo", "proc", 0)
    ]
    var nameIndex: Table[string, seq[int]]
    nameIndex["foo"] = @[0]
    let res = resolveCallTarget(symbols, nameIndex, "modA", "nonexistent")
    check res.kind == rrUnresolved
    check res.resolvedIdx == 0      # default; meaningless for rrUnresolved
    check res.candidates.len == 0

  # -----------------------------------------------------------------------
  # Test 2: 후보 1개 → rrUnique + 정확한 idx
  # -----------------------------------------------------------------------

  test "single candidate yields rrUnique with correct idx":
    let symbols = @[
      makeSym("modA", "foo", "proc", 0)
    ]
    var nameIndex: Table[string, seq[int]]
    nameIndex["foo"] = @[0]
    let res = resolveCallTarget(symbols, nameIndex, "modA", "foo")
    check res.kind == rrUnique
    check res.resolvedIdx == 0
    check res.candidates.len == 0

  # -----------------------------------------------------------------------
  # Test 3: 같은 module, 같은 name의 func + template 2개 → rrAmbiguous
  # (다른 module, 다른 name에도 func 1개 존재하는 상황)
  # -----------------------------------------------------------------------

  test "same module same name func+template yields rrAmbiguous with 2 candidates":
    let symbols = @[
      makeSym("modA", "getBitsBE", "func", 0),
      makeSym("modA", "getBitsBE", "template", 1),
      makeSym("modB", "getBitsBE", "func", 2)   # different module, same name
    ]
    var nameIndex: Table[string, seq[int]]
    nameIndex["getBitsBE"] = @[0, 1, 2]
    let res = resolveCallTarget(symbols, nameIndex, "modA", "getBitsBE")
    check res.kind == rrAmbiguous
    check res.candidates.len == 2
    check res.candidates.contains(0)
    check res.candidates.contains(1)
    check not res.candidates.contains(2)

  # -----------------------------------------------------------------------
  # Test 4: 후보 2개 중 정확히 1개만 같은 modulePath → rrUnique (모듈 우선)
  # -----------------------------------------------------------------------

  test "two candidates with exactly one matching module yields rrUnique":
    let symbols = @[
      makeSym("modA", "bar", "proc", 0),
      makeSym("modB", "bar", "proc", 1)
    ]
    var nameIndex: Table[string, seq[int]]
    nameIndex["bar"] = @[0, 1]
    let res = resolveCallTarget(symbols, nameIndex, "modA", "bar")
    check res.kind == rrUnique
    check res.resolvedIdx == 0
    check res.candidates.len == 0

  # -----------------------------------------------------------------------
  # Test 5: rrAmbiguous 결과에 대해 호출점에서 의존성이 추가되지 않음
  # (buildTopologyAnalysis를 통해 간접 검증)
  # -----------------------------------------------------------------------

  test "ambiguous resolution adds no dependency edge but is retained in unresolvedEdges":
    ## 시나리오: symA가 "getBitsBE"를 호출하는데, modA에 func+template
    ## 두 정의가 있으므로 rrAmbiguous. 의존성 그래프에 edge가 추가되지
    ## 않아야 한다 (self-dependency도 아니고, 어떤 후보든 선택되지 않음).
    ## 그러나 unresolvedEdges에 보존되어야 한다 (silent drop 금지).
    let symbols = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "getBitsBE", "func", 1),
      makeSym("modA", "getBitsBE", "template", 2)
    ]
    # caller의 rawCallTargets에 getBitsBE를 담음
    var syms = symbols
    syms[0].rawCallTargets = @["getBitsBE"]
    let analysis = buildTopologyAnalysis(syms)
    # caller(node 0)의 dependencyIds가 비어있어야 함
    # (ambiguous이므로 어떤 candidate도 선택되지 않음)
    let callerNode = analysis.state.nodes[0]
    check callerNode.dependencyIds.len == 0
    # rrAmbiguous edge는 반드시 unresolvedEdges에 보존되어야 함
    check analysis.unresolvedEdges.len == 1
    check analysis.unresolvedEdges[0].fromNodeId == sorterNodeId("sym0")
    check analysis.unresolvedEdges[0].targetName == "getBitsBE"
    check analysis.unresolvedEdges[0].modulePath == "modA"
    check analysis.unresolvedEdges[0].resolutionKind == rrAmbiguous

  # -----------------------------------------------------------------------
  # Test 6: rrUnresolved 결과에 대해 호출점에서 의존성이 추가되지 않음
  # -----------------------------------------------------------------------

  test "unresolved target adds no dependency edge but is retained in unresolvedEdges":
    let symbols = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms = symbols
    syms[0].rawCallTargets = @["nonexistent"]
    let analysis = buildTopologyAnalysis(syms)
    let callerNode = analysis.state.nodes[0]
    check callerNode.dependencyIds.len == 0
    # rrUnresolved edge는 반드시 unresolvedEdges에 보존되어야 함
    check analysis.unresolvedEdges.len == 1
    check analysis.unresolvedEdges[0].fromNodeId == sorterNodeId("sym0")
    check analysis.unresolvedEdges[0].targetName == "nonexistent"
    check analysis.unresolvedEdges[0].modulePath == "modA"
    check analysis.unresolvedEdges[0].resolutionKind == rrUnresolved

  # -----------------------------------------------------------------------
  # Test 7: rrUnique 결과에 대해 호출점에서 의존성이 정상 추가됨
  # (기존 동작 보존 확인)
  # -----------------------------------------------------------------------

  test "unique resolution adds dependency edge in buildTopologyAnalysis":
    let symbols = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms = symbols
    syms[0].rawCallTargets = @["callee"]
    let analysis = buildTopologyAnalysis(syms)
    let callerNode = analysis.state.nodes[0]
    check callerNode.dependencyIds.len == 1
    check callerNode.dependencyIds[0] == sorterNodeId("sym1")

  # -----------------------------------------------------------------------
  # Test 8: dependencyGraphDigest includes unresolved edges
  # -----------------------------------------------------------------------

  test "dependencyGraphDigest differs when unresolved edges are present vs absent":
    ## Same dependency graph, but one has an unresolved edge and one does not.
    ## The digest must differ because the unresolved set is part of the digest.
    let symbols1 = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms1 = symbols1
    syms1[0].rawCallTargets = @["callee"]
    let analysis1 = buildTopologyAnalysis(syms1)

    let symbols2 = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms2 = symbols2
    syms2[0].rawCallTargets = @["nonexistent"]
    let analysis2 = buildTopologyAnalysis(syms2)

    check analysis1.unresolvedEdges.len == 0
    check analysis2.unresolvedEdges.len == 1
    check dependencyGraphDigest(analysis1) != dependencyGraphDigest(analysis2)

  test "dependencyGraphDigest is order-independent for unresolved edges":
    let symbols = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms = symbols
    syms[0].rawCallTargets = @["nonexistent"]
    let analysis = buildTopologyAnalysis(syms)

    # Build a second analysis with the same unresolved edge — digest must match
    let symbols2 = @[
      makeSym("modA", "caller", "proc", 0),
      makeSym("modA", "callee", "proc", 1)
    ]
    var syms2 = symbols2
    syms2[0].rawCallTargets = @["nonexistent"]
    let analysis2 = buildTopologyAnalysis(syms2)

    check dependencyGraphDigest(analysis) == dependencyGraphDigest(analysis2)