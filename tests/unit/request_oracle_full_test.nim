## request_oracle_full_test.nim — computeRequiredRequestsFull + evaluateClosureCompleteness tests
##
## Tests for src/verification/selection/request_oracle.nim and
## src/verification/selection/request_completeness.nim:
##   - computeRequiredRequestsFull determinism
##   - computeRequiredRequestsFull kernel-scope filtering
##   - computeRequiredRequestsFull verified subtraction
##   - evaluateClosureCompleteness: complete when all covered
##   - evaluateClosureCompleteness: incomplete + uncompleted list
##   - validateBasis: blocked_by accepted for dkSkip
##   - validateBasis: blocked_by rejected when evidence empty

{.push raises: [CatchableError].}

import std/[algorithm, sequtils, sets, strutils, unittest]
import core/types/request_id
import core/types/request_derivation_types
import core/topology/topology_types
import core/proof/proof_integrity
import core/sorter/sorter_core
import core/orchestrator/orchestrator_types
import verification/selection/request_oracle
import verification/selection/request_completeness

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func makeKernelScope*(symbols: seq[string]; exempt: seq[string] = @[]): KernelScopeInfo =
  KernelScopeInfo(
    kernelSymbols: symbols,
    kernelTotal: symbols.len,
    kernelExemptSymbols: exempt)

func makeTopologyAnalysis*(nodes: seq[SorterNode]; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]): TopologyAnalysis =
  TopologyAnalysis(
    state: SorterState(nodes: nodes),
    unresolvedEdges: unresolvedEdges)

func makeSorterNode*(id: string; depIds: seq[string] = @[]): SorterNode =
  var deps: seq[SorterNodeId] = @[]
  for d in depIds:
    deps.add(sorterNodeId(d))
  SorterNode(
    id: sorterNodeId(id),
    modulePath: id.split("::")[0],
    functionName: id.split("::")[1],
    dependencyIds: deps)

func makeUnresolvedEdge*(fromNodeId: string): TopologyUnresolvedEdge =
  TopologyUnresolvedEdge(
    fromNodeId: sorterNodeId(fromNodeId),
    targetName: "",
    modulePath: "",
    resolutionKind: rrUnresolved)

# ---------------------------------------------------------------------------
# computeRequiredRequestsFull determinism
# ---------------------------------------------------------------------------

suite "computeRequiredRequestsFull - determinism":

  test "same inputs → same output":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y"),
      makeSorterNode("mod_c::fn_z")]
    let analysis = makeTopologyAnalysis(nodes)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"])
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let r1 = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    let r2 = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    check r1.len == r2.len
    for i in 0 ..< r1.len:
      check r1[i] == r2[i]

# ---------------------------------------------------------------------------
# computeRequiredRequestsFull kernel-scope filtering
# ---------------------------------------------------------------------------

suite "computeRequiredRequestsFull - kernel-scope filtering":

  test "non-kernel symbols excluded from required set":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y"),
      makeSorterNode("mod_c::fn_z")]
    let analysis = makeTopologyAnalysis(nodes)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])  ## mod_c::fn_z NOT in kernel
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let result = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    check result.len == 2
    check result.mapIt(string(it)).contains("mod_a::fn_x")
    check result.mapIt(string(it)).contains("mod_b::fn_y")
    check not result.mapIt(string(it)).contains("mod_c::fn_z")

  test "exempt symbols excluded from required set":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y")]
    let analysis = makeTopologyAnalysis(nodes)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"], exempt = @["mod_b::fn_y"])
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let result = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    check result.len == 1
    check string(result[0]) == "mod_a::fn_x"

# ---------------------------------------------------------------------------
# computeRequiredRequestsFull verified subtraction
# ---------------------------------------------------------------------------

suite "computeRequiredRequestsFull - verified subtraction":

  test "already-verified nodes excluded from required set":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y"),
      makeSorterNode("mod_c::fn_z")]
    let analysis = makeTopologyAnalysis(nodes)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"])
    var verifiedSet: HashSet[string] = initHashSet[string]()
    verifiedSet.incl("mod_a::fn_x")

    let result = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    check result.len == 2
    check not result.mapIt(string(it)).contains("mod_a::fn_x")

# ---------------------------------------------------------------------------
# computeRequiredRequestsFull unresolved edges
# ---------------------------------------------------------------------------

suite "computeRequiredRequestsFull - unresolved edges":

  test "unresolved edge from-nodes included in required set":
    let universe = @["mod_a::fn_x"]
    let nodes = @[makeSorterNode("mod_a::fn_x")]
    let unresolvedEdges = @[makeUnresolvedEdge("mod_b::fn_y")]  ## mod_b::fn_y NOT in universe
    let analysis = makeTopologyAnalysis(nodes, unresolvedEdges)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let result = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    check result.mapIt(string(it)).contains("mod_b::fn_y")

# ---------------------------------------------------------------------------
# evaluateClosureCompleteness
# ---------------------------------------------------------------------------

suite "evaluateClosureCompleteness - complete when all covered":

  test "all required nodes orchestrationVerified → complete":
    let required = @[makeRequestId(@["mod_a::fn_x"]), makeRequestId(@["mod_b::fn_y"])]
    let completed = @[makeRequestId(@["mod_a::fn_x"]), makeRequestId(@["mod_b::fn_y"])]
    let dispositions: seq[Disposition] = @[]
    let nodeReports = @[
      OrchestrationNodeReport(nodeId: sorterNodeId("mod_a::fn_x"), status: orchestrationVerified),
      OrchestrationNodeReport(nodeId: sorterNodeId("mod_b::fn_y"), status: orchestrationVerified)]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    check result.complete
    check result.uncompleted.len == 0

  test "all required covered by dispositions → complete":
    let required = @[makeRequestId(@["mod_a::fn_x"])]
    let completed: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "not eligible",
      basis: "eligibility")]
    let nodeReports: seq[OrchestrationNodeReport] = @[]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    check result.complete

  test "orchestrationInductiveValid counts as completed":
    let required = @[makeRequestId(@["mod_a::fn_x"])]
    let completed = @[makeRequestId(@["mod_a::fn_x"])]
    let dispositions: seq[Disposition] = @[]
    let nodeReports = @[
      OrchestrationNodeReport(nodeId: sorterNodeId("mod_a::fn_x"), status: orchestrationInductiveValid)]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    check result.complete

  test "orchestrationNoObligation counts as completed":
    let required = @[makeRequestId(@["mod_a::fn_x"])]
    let completed = @[makeRequestId(@["mod_a::fn_x"])]
    let dispositions: seq[Disposition] = @[]
    let nodeReports = @[
      OrchestrationNodeReport(nodeId: sorterNodeId("mod_a::fn_x"), status: orchestrationNoObligation)]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    check result.complete

# ---------------------------------------------------------------------------
# evaluateClosureCompleteness - incomplete cases
# ---------------------------------------------------------------------------

suite "evaluateClosureCompleteness - incomplete when not covered":

  test "required request neither completed nor dispositioned → incomplete":
    let required = @[makeRequestId(@["mod_a::fn_x"]), makeRequestId(@["mod_b::fn_y"])]
    let completed = @[makeRequestId(@["mod_a::fn_x"])]
    let dispositions: seq[Disposition] = @[]
    let nodeReports = @[
      OrchestrationNodeReport(nodeId: sorterNodeId("mod_a::fn_x"), status: orchestrationVerified)]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    check not result.complete
    check result.uncompleted.len == 1
    check string(result.uncompleted[0]) == "mod_b::fn_y"

# ---------------------------------------------------------------------------
# validateBasis - blocked_by extension
# ---------------------------------------------------------------------------

suite "validateBasis - blocked_by extension":

  test "blocked_by basis accepted for dkSkip":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "blocked by failed dependency mod_b::fn_y",
      basis: "blocked_by")
    check validateBasis(d)

  test "blocked_by basis rejected for dkFallback":
    let d = Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "fallback reason",
      basis: "blocked_by")
    check not validateBasis(d)

  test "blocked_by basis rejected when evidence empty":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "",
      basis: "blocked_by")
    check not validateBasis(d)

  test "eligibility basis still accepted for dkSkip":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "not eligible",
      basis: "eligibility")
    check validateBasis(d)

  test "oracle-gap basis still accepted for dkSkip":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_a::fn_x"]),
      evidence: "oracle gap detected",
      basis: "oracle-gap")
    check validateBasis(d)

{.pop.}