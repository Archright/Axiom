## verification_plan_differential_test.nim — P3: Reference vs Production differential
##
## Validates that the new production plan computation (computeVerificationPlan)
## agrees with the existing policy-UNAWARE reference oracle
## (computeRequiredRequestsFull) on the required set, across representative
## (universe, kernelScope, analysis) inputs.
##
## Reference contract: computeRequiredRequestsFull(universe, analysis,
## kernelScope, verifiedSet=∅) is the independent policy-unaware oracle.
## Production contract: computeVerificationPlan(universe, analysis,
## kernelScope, seedSet, policy=allow-all) must yield the SAME required set
## when policy allows everything (budgetCap=0 → PolicyAllows(u)≡true).
##
## With budgetCap>0, Production is policy-aware and may restrict the set —
## documented as an intentional divergence (Required predicate includes
## PolicyAllows), so requiredUnitIds must remain a subset of the reference.

{.push raises: [CatchableError].}

import std/[algorithm, sequtils, sets, strutils, unittest]
import core/types/request_id
import core/types/request_derivation_types
import core/topology/topology_types
import core/proof/proof_integrity
import core/sorter/sorter_core
import verification/selection/request_oracle
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

const allowAll = RequestPolicy(budgetCap: 0, fallbackOn: {})

## Reference required set as sorted strings (verified-set subtraction disabled —
## the plan is verified-set independent; subtraction is an execution-layer concern).
func referenceRequired*(
  universe: seq[string]
; analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
): seq[string] =
  let emptyVerified: HashSet[string] = initHashSet[string]()
  computeRequiredRequestsFull(universe, analysis, kernelScope, emptyVerified)
    .mapIt(string(it))

# ---------------------------------------------------------------------------
# P3-1: Production (allow-all) == Reference across scope shapes
# ---------------------------------------------------------------------------

suite "P3-1 — computeVerificationPlan required set == computeRequiredRequestsFull (allow-all)":

  test "all in scope → identical required set":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(universe)
    let seedSet: HashSet[string] = initHashSet[string]()

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    check plan.requiredUnitIds == refSet
    check plan.requiredUnitIds.len == 3

  test "mixed in/out of scope → identical (only in-scope required)":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_c::fn_z"])  ## mod_b out of scope
    let seedSet: HashSet[string] = initHashSet[string]()

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    check plan.requiredUnitIds == refSet
    check plan.requiredUnitIds == @["mod_a::fn_x", "mod_c::fn_z"]

  test "exempt symbols excluded by both reference and production":
    let universe = @["mod_a::fn_x", "mod_b::fn_y"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"], exempt = @["mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    check plan.requiredUnitIds == refSet
    check plan.requiredUnitIds == @["mod_a::fn_x"]

  test "degraded scope (empty kernel) → full universe by both":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@[])  ## lock unavailable → degraded
    let seedSet: HashSet[string] = initHashSet[string]()

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    check plan.requiredUnitIds == refSet
    check plan.requiredUnitIds == universe.sorted(cmp)

  test "unresolved edge from-node required by both":
    let universe = @["mod_a::fn_x"]
    let nodes = @[makeSorterNode("mod_a::fn_x")]
    ## mod_b::fn_y is not in universe but is the from-node of an unresolved edge.
    let unresolvedEdges = @[makeUnresolvedEdge("mod_b::fn_y")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes), unresolvedEdges: unresolvedEdges)
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_b::fn_y"])
    let seedSet: HashSet[string] = initHashSet[string]()

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    check plan.requiredUnitIds == refSet
    check "mod_b::fn_y" in plan.requiredUnitIds

# ---------------------------------------------------------------------------
# P3-2: Production (allow-all) invariant — required unit count equals
#        per-unit REQUIRED count (internal consistency)
# ---------------------------------------------------------------------------

suite "P3-2 — requiredUnitIds ≡ per-unit REQUIRED decisions":

  test "every required unit is marked REQUIRED; count matches":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(@["mod_a::fn_x", "mod_c::fn_z"])
    let seedSet: HashSet[string] = initHashSet[string]()

    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, allowAll)
    let requiredDecisions = plan.perUnitRequirement.filterIt(it.decision == rdRequired).mapIt(it.unitId)
    check requiredDecisions.sorted(cmp) == plan.requiredUnitIds

# ---------------------------------------------------------------------------
# P3-3: Policy-aware divergence (budgetCap>0) is a subset, seed-independent
# ---------------------------------------------------------------------------

suite "P3-3 — budgetCap>0 restricts required set (policy-aware subset) but seed-independent":

  test "budgetCap limits required set to a subset of reference":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z", "mod_d::fn_w"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z"), makeSorterNode("mod_d::fn_w")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(universe)
    let seedSet: HashSet[string] = initHashSet[string]()
    let budget2 = RequestPolicy(budgetCap: 2, fallbackOn: {})

    let refSet = referenceRequired(universe, analysis, kernelScope)
    let plan = computeVerificationPlan(universe, analysis, kernelScope, seedSet, budget2)
    ## Production is policy-aware: required set is capped to the first budgetCap
    ## units in canonical (sorted) order — a subset of the reference.
    check plan.requiredUnitIds.len == 2
    check plan.requiredUnitIds == refSet[0 .. 1]
    for u in plan.requiredUnitIds:
      check u in refSet
    ## Budget-capped units remain present in per-unit decisions but marked
    ## NOT_REQUIRED with a "policy budget cap exceeded" reason (NOT dropped).
    let capped = plan.perUnitRequirement.filterIt(
      it.decision == rdNotRequired and "budget" in it.reason)
    check capped.len == 2

  test "budgetCap restricted required set is still seed-independent":
    let universe = @["mod_a::fn_x", "mod_b::fn_y", "mod_c::fn_z"]
    let nodes = @[makeSorterNode("mod_a::fn_x"), makeSorterNode("mod_b::fn_y"),
                   makeSorterNode("mod_c::fn_z")]
    let analysis = TopologyAnalysis(state: SorterState(nodes: nodes))
    let kernelScope = makeKernelScope(universe)
    var seedA: HashSet[string] = initHashSet[string]()
    var seedB: HashSet[string] = initHashSet[string]()
    seedB.incl("mod_c::fn_z")
    let budget1 = RequestPolicy(budgetCap: 1, fallbackOn: {})

    let planA = computeVerificationPlan(universe, analysis, kernelScope, seedA, budget1)
    let planB = computeVerificationPlan(universe, analysis, kernelScope, seedB, budget1)
    ## INV-1 holds under budget cap: required set independent of seed.
    check planA.requiredUnitIds == planB.requiredUnitIds
    ## seed only affects affectedUnitIds.
    check planB.affectedUnitIds == @["mod_c::fn_z"]
    check planA.affectedUnitIds.len == 0

{.pop.}
