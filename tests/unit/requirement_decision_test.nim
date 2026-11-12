## requirement_decision_test.nim — TC-1: RequirementDecision two-axis model
##
## Encodes the two-axis semantics of requirement disposition:
##   Axis 1 — obligation presence + scope eligibility + policy allowance → REQUIRED
##   Axis 2 — dependency state → BLOCKED / UNRESOLVED / SATISFIABLE
##
## Uses production types: VerificationPlan, computeVerificationPlan,
## RequirementDecision, RequirementDecisionKind, PlanState, computeRequiredRequestsFull,
## Disposition, RequestId, RequestVerdict.

{.push raises: [CatchableError].}

import std/[algorithm, sequtils, sets, strutils, unittest]
import core/types/request_id
import core/types/request_derivation_types
import core/types/request_result
import core/topology/topology_types
import core/proof/proof_integrity
import core/sorter/sorter_core
import verification/selection/request_oracle
import verification/selection/request_completeness
import core/types/verification_plan
import verification/selection/verification_plan

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func makeKernelScope*(symbols: seq[string]; exempt: seq[string] = @[]): KernelScopeInfo =
  KernelScopeInfo(
    kernelSymbols: symbols,
    kernelTotal: symbols.len,
    kernelExemptSymbols: exempt)

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
# TC-1: Two-axis model — obligation + dependency state
# ---------------------------------------------------------------------------

suite "TC-1 — RequirementDecision two-axis model":

  # -- Axis 1: obligation + scope + policy → REQUIRED / NOT_REQUIRED --

  test "scope eligible + has obligation + policy allows → REQUIRED via computeVerificationPlan":
    let universe = @["mod_a::fn_x"]
    let nodes = @[makeSorterNode("mod_a::fn_x")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x"])
    let verifiedSet: HashSet[string] = initHashSet[string]()
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let rd = plan.perUnitRequirement.filterIt(it.unitId == "mod_a::fn_x")[0]
    check rd.decision == rdRequired

  test "obligation absent (outside kernel scope) → NOT_REQUIRED via computeVerificationPlan":
    let universe = @["mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x"])  ## mod_b NOT in scope
    let verifiedSet: HashSet[string] = initHashSet[string]()
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let rd = plan.perUnitRequirement.filterIt(it.unitId == "mod_b::fn_y")[0]
    check rd.decision == rdNotRequired

  test "two units in kernel scope → both REQUIRED (computeVerificationPlan uses no verifiedSet)":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    ## computeVerificationPlan takes no verifiedSet (pure plan layer);
    ## verifiedSet subtraction is a separate execution-layer concern.
    ## Both units in scope → both REQUIRED.
    check plan.perUnitRequirement.filterIt(it.unitId == "mod_a::fn_x")[0].decision == rdRequired
    check plan.perUnitRequirement.filterIt(it.unitId == "mod_b::fn_y")[0].decision == rdRequired
    check plan.requiredUnitIds.len == 2
    check plan.planState == psComplete

  # -- Axis 2: dependency state preserves REQUIRED (separate dimension) --

  test "dependency state is independent of RequirementDecision (two-axis separation)":
    ## The Required predicate does NOT include dependency-satisfiability.
    ## A unit can be REQUIRED even if its dependencies are blocked/unresolved.
    ## Dependency status is a SEPARATE execution dimension.
    let universe = @["mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_c::fn_z")]
    let unresolvedEdges = @[makeUnresolvedEdge("mod_h::fn_s")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes), unresolvedEdges: unresolvedEdges)
    let kernelScope = makeKernelScope(@["mod_c::fn_z"])
    let verifiedSet: HashSet[string] = initHashSet[string]()
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let rd = plan.perUnitRequirement.filterIt(it.unitId == "mod_c::fn_z")[0]
    ## The unit is REQUIRED regardless of unresolved edges (dependency state is separate).
    check rd.decision == rdRequired

  # -- computeRequiredRequestsFull as the obligation basis --

  test "computeRequiredRequestsFull: obligation exists when unit is in kernel scope and not verified":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let required = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    ## Both units are in kernel scope and not verified → both required.
    check required.len == 2
    check required.mapIt(string(it)).contains("mod_a::fn_x")
    check required.mapIt(string(it)).contains("mod_b::fn_y")

  test "computeRequiredRequestsFull: obligation absent when unit is verified (subtraction)":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    var verifiedSet: HashSet[string] = initHashSet[string]()
    verifiedSet.incl("mod_a::fn_x")

    let required = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    ## mod_a::fn_x is verified → excluded from required set.
    check required.len == 1
    check string(required[0]) == "mod_b::fn_y"

  test "computeRequiredRequestsFull: obligation absent when unit is outside kernel scope":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x"])  ## mod_b NOT in scope
    let verifiedSet: HashSet[string] = initHashSet[string]()

    let required = computeRequiredRequestsFull(universe, analysis, kernelScope, verifiedSet)
    ## mod_b::fn_y is outside kernel scope → not required.
    check required.len == 1
    check string(required[0]) == "mod_a::fn_x"

  # -- Disposition encoding of the two-axis model --

  test "Disposition with dkSkip + blocked_by basis encodes BLOCKED dependency state":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_g::fn_t"]),
      evidence: "blocked by failed dependency mod_h::fn_s",
      basis: "blocked_by")
    check d.kind == dkSkip
    check d.basis == "blocked_by"
    check d.evidence.len > 0
    ## A blocked_by disposition means the unit is REQUIRED but
    ## its dependency is BLOCKED — the obligation is not removed.

  test "Disposition with dkFallback + fallback basis encodes UNRESOLVED dependency state":
    let d = Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["mod_i::fn_r"]),
      evidence: "fallback: dependency mod_j::fn_q unresolved",
      basis: "fallback")
    check d.kind == dkFallback
    check d.basis == "fallback"
    ## A fallback disposition means the unit is REQUIRED but
    ## its dependency is UNRESOLVED — the obligation persists.

  test "Disposition with dkSkip + eligibility basis encodes SATISFIABLE dependency state":
    let d = Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_k::fn_p"]),
      evidence: "eligible but skipped per policy",
      basis: "eligibility")
    check d.kind == dkSkip
    check d.basis == "eligibility"
    ## An eligibility disposition with non-empty evidence means the
    ## unit's dependency is SATISFIABLE (the obligation is covered).

  # -- RequestResult independence from obligation --

  test "RequestResult verdict is independent of obligation presence":
    let reqId = makeRequestId(@["mod_l::fn_o"])
    let result = aggregateRequestResult(reqId, @[rvPass, rvFail], cacheHit = false)
    check result.verdict == rvFail  ## ⊔(pass, fail) = fail
    ## The verdict (result) is computed independently of whether the
    ## unit is required or not — the two axes are orthogonal.

  test "RequestResult TIMEOUT verdict is a valid result independent of execution state":
    let reqId = makeRequestId(@["mod_m::fn_n"])
    let result = aggregateRequestResult(reqId, @[rvTimeout], cacheHit = false)
    check result.verdict == rvTimeout
    ## TIMEOUT is a result value that exists independently of whether
    ## the unit was actually executed or merely required.

{.pop.}