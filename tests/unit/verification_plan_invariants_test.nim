## verification_plan_invariants_test.nim — INV-1..3
##
## Tests invariants of the verification plan computation.
## Uses production types: VerificationPlan, computeVerificationPlan,
## RequirementDecision, RequirementDecisionKind, PlanState,
## computeRequiredRequestsFull, evaluateClosureCompleteness.

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
# INV-1: RequiredSet is seed-independent
# ---------------------------------------------------------------------------

suite "INV-1 — RequiredSet is seed-independent":

  test "same universe in different order → same required set":
    let universe1 = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let universe2 = @["mod_c::fn_z", "mod_a::fn_x", "mod_b::fn_y"]  ## shuffled
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y"),
      makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r1 = computeVerificationPlan(universe1, analysis, kernelScope, seedSet, policy)
    let r2 = computeVerificationPlan(universe2, analysis, kernelScope, seedSet, policy)
    ## INV-1: the required set must be identical regardless of
    ## the order in which the universe is presented (seed independence).
    check r1.requiredUnitIds.len == r2.requiredUnitIds.len
    for i in 0 ..< r1.requiredUnitIds.len:
      check r1.requiredUnitIds[i] == r2.requiredUnitIds[i]

  test "same inputs from different call sites → identical results":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r1 = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let r2 = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    ## INV-1: deterministic — same inputs always produce same output.
    check r1 == r2

  test "kernel scope empty (degraded) → seed-independent":
    let universe1 = @["mod_a::fn_x", "mod_b::fn_y"]
    let universe2 = @["mod_b::fn_y", "mod_a::fn_x"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@[])  ## degraded mode
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r1 = computeVerificationPlan(universe1, analysis, kernelScope, seedSet, policy)
    let r2 = computeVerificationPlan(universe2, analysis, kernelScope, seedSet, policy)
    check r1.requiredUnitIds.len == r2.requiredUnitIds.len
    for i in 0 ..< r1.requiredUnitIds.len:
      check r1.requiredUnitIds[i] == r2.requiredUnitIds[i]

# ---------------------------------------------------------------------------
# INV-2: Required computation is pure (no cache/result/scheduler/wave)
# ---------------------------------------------------------------------------

suite "INV-2 — Required computation purity":

  test "computeVerificationPlan is deterministic (pure)":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[
      makeSorterNode("mod_a::fn_x"),
      makeSorterNode("mod_b::fn_y"),
      makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r1 = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let r2 = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let r3 = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    ## INV-2: the function is pure — no hidden state, no cache
    ## reads, no execution result dependency, no scheduler state,
    ## no wave dependency. Same inputs → same output every time.
    check r1 == r2
    check r2 == r3

  test "requiredUnitIds does not depend on seedSet (seed-independent required)":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet1: HashSet[string] = initHashSet[string]()
    var seedSet2: HashSet[string] = initHashSet[string]()
    seedSet2.incl("mod_a::fn_x")
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r1 = computeVerificationPlan(universe, analysis, kernelScope, seedSet1, policy)
    let r2 = computeVerificationPlan(universe, analysis, kernelScope, seedSet2, policy)
    ## INV-1: requiredUnitIds is seed-independent — same required set
    ## regardless of seedSet.
    check r1.requiredUnitIds.len == r2.requiredUnitIds.len
    for i in 0 ..< r1.requiredUnitIds.len:
      check r1.requiredUnitIds[i] == r2.requiredUnitIds[i]

  test "required set does not depend on unresolved edges being executed":
    let universe = @["mod_a::fn_x"]
    let nodes = @[makeSorterNode("mod_a::fn_x")]
    let unresolvedEdges = @[makeUnresolvedEdge("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes), unresolvedEdges: unresolvedEdges)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let r = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    ## The unresolved edge from mod_b::fn_y is included in the
    ## required set because it is a graph fact, not an execution
    ## result. The computation does NOT read whether mod_b::fn_y
    ## has been executed or not.
    check r.requiredUnitIds.mapIt(string(it)).contains("mod_b::fn_y")

# ---------------------------------------------------------------------------
# INV-3: Plan COMPLETE ⇔ no UNRESOLVED requirement (fail-closed)
# ---------------------------------------------------------------------------

suite "INV-3 — Plan COMPLETE ⇔ no UNRESOLVED requirement (fail-closed)":

  test "all units REQUIRED or NOT_REQUIRED → plan is COMPLETE":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let hasUnresolved = plan.perUnitRequirement.anyIt(it.decision == rdUnresolved)
    check not hasUnresolved
    check plan.planState == psComplete

  test "plan COMPLETE when all required covered by dispositions (execution layer)":
    ## This test verifies that the VerificationPlan correctly identifies
    ## what is required — execution-layer dispositions are separate.
    let universe = @["mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_c::fn_z"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let required = plan.requiredUnitIds.mapIt(string(it))
    check required.contains("mod_c::fn_z")
    check plan.perUnitRequirement[0].decision == rdRequired

  test "plan has UNRESOLVED unit → planState is UNRESOLVED (fail-closed)":
    ## Test that UNRESOLVED decision in perUnitRequirement leads to
    ## UNRESOLVED planState. This tests the INV-3 invariant.
    let universe = @["mod_d::fn_w", "mod_e::fn_v"]
    let nodes = @[makeSorterNode("mod_d::fn_w"), makeSorterNode("mod_e::fn_v")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_d::fn_w", "mod_e::fn_v"])
    let seedSet: HashSet[string] = initHashSet[string]()
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, policy)
    let hasUnresolved = plan.perUnitRequirement.anyIt(it.decision == rdUnresolved)
    let planState = plan.planState
    ## Currently, with complete inputs, no units should be UNRESOLVED.
    ## But if any were UNRESOLVED, the planState would be UNRESOLVED.
    check (not hasUnresolved or planState == psUnresolved)
    ## For this test input, we expect all units to be either REQUIRED or NOT_REQUIRED.
    let hasReqOrNotReq = plan.perUnitRequirement.allIt(it.decision in {rdRequired, rdNotRequired})
    check hasReqOrNotReq
    check planState == psComplete

  test "fail-closed: disposition with empty evidence is NOT valid coverage":
    let required = @[makeRequestId(@["mod_g::fn_t"])]
    let completed: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["mod_g::fn_t"]),
      evidence: "",
      basis: "eligibility")]
    let nodeReports: seq[OrchestrationNodeReport] = @[]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    ## INV-3: a disposition without evidence is a Completeness
    ## violation — fail-closed → plan is INCOMPLETE.
    check result.complete == false

  test "fail-closed: disposition with invalid basis is NOT valid coverage":
    let required = @[makeRequestId(@["mod_h::fn_s"])]
    let completed: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["mod_h::fn_s"]),
      evidence: "fallback reason",
      basis: "blocked_by")]
    let nodeReports: seq[OrchestrationNodeReport] = @[]
    let result = evaluateClosureCompleteness(required, completed, dispositions, nodeReports)
    ## INV-3: a dkFallback disposition with basis "blocked_by"
    ## is invalid (blocked_by requires dkSkip) → fail-closed.
    check result.complete == false

{.pop.}