## execution_plan_serialization_test.nim — W2: ExecutionPlan JSON + digest fail-closed
##
## Covers: toJson/fromJson round-trip, verifyPlanDigest (tamper detection),
## and the plan→payload mapping fail-closed branch (unknown unit → err).

import std/[unittest, json, options, algorithm]
import core/results
import core/types/execution_plan
import core/types/selection_derivation
import verification/selection/selection_digests
import cli/payload_bridge
import core/topology/topology_types

func samplePlan(): ExecutionPlan =
  ExecutionPlan(
    mode: umSelected,
    selectedUnitIds: @["src/core/a.nim::fA", "src/core/b.nim::fB"].sorted(cmp),
    planIdentity: PlanIdentity(
      selectionDigest: "sel", changeSetDigest: "cs", graphDigest: "g",
      universeDigest: "u", policyDigest: "p", planDigest: ""),
    planDigest: "")

suite "ExecutionPlan JSON round-trip":

  test "toJson → fromJson round trip preserves mode, units, identity":
    let plan = samplePlan()
    let jsonPlan = plan.toJson
    let back = fromJson(jsonPlan)
    check back.isSome
    check back.get.mode == umSelected
    check back.get.selectedUnitIds == plan.selectedUnitIds
    check back.get.planIdentity.selectionDigest == "sel"
    check back.get.planIdentity.policyDigest == "p"

  test "umFull with empty units round-trips":
    let plan = ExecutionPlan(
      mode: umFull, selectedUnitIds: @[],
      planIdentity: PlanIdentity(selectionDigest: "s", changeSetDigest: "",
        graphDigest: "", universeDigest: "", policyDigest: "", planDigest: ""),
      planDigest: "")
    let back = fromJson(plan.toJson)
    check back.isSome
    check back.get.mode == umFull
    check back.get.selectedUnitIds.len == 0

  test "malformed JSON returns none":
    check fromJson(newJObject()).isNone
    check fromJson(newJString("nope")).isNone
    check fromJson(parseJson("""{"mode":"selected"}""")).isNone  # missing planIdentity
    check fromJson(parseJson(
      """{"mode":"umSelected","selectedUnitIds":[],"planIdentity":{"selectionDigest":"s"}}""")).isSome

suite "planDigest verification (fail-closed)":

  test "verifyPlanDigest true for genuine plan":
    let deriv = SelectionDerivation(
      inputDigests: SelectionInputs(changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p"),
      status: ssValid, selected: @[], excluded: @[],
      fallbackReason: "", witnessDigest: "")
    let plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
    check verifyPlanDigest(plan)

  test "tampered selectedUnitIds fails verification":
    let deriv = SelectionDerivation(
      inputDigests: SelectionInputs(changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p"),
      status: ssValid, selected: @[], excluded: @[],
      fallbackReason: "", witnessDigest: "")
    var plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
    plan.selectedUnitIds = @["m::f", "m::other"]  # tamper
    check not verifyPlanDigest(plan)

  test "computePlanDigest is deterministic":
    let p1 = samplePlan()
    let p2 = samplePlan()
    check computePlanDigest(p1) == computePlanDigest(p2)
    check computePlanDigest(p1).len == 64

suite "plan→payload mapping fail-closed":

  test "rollback invariant: tampered plan → verifyPlanDigest false → rejection (never partial run)":
    ## 계약 §10.2/§13 — executor-level fail-closed: an invalid/tampered plan must be
    ## REJECTED before any execution; a partial run must never happen.
    let deriv = SelectionDerivation(
      inputDigests: SelectionInputs(changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p"),
      status: ssValid, selected: @[], excluded: @[],
      fallbackReason: "", witnessDigest: "")
    var plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
    let genuineDigest = plan.planDigest
    plan.selectedUnitIds = @["m::f", "m::injected"]  # tampered after plan signing
    check not verifyPlanDigest(plan)                 # digest check fails (reject)
    check computePlanDigest(plan) != genuineDigest
    ## The prove path consumes plans only after verifyPlanDigest (fail-closed);
    ## a tampered plan therefore never reaches execution.

  test "unknown unit id in empty analysis returns err (never silent skip)":
    let emptyAnalysis = TopologyAnalysis(
      state: SorterState(nodes: @[]),
      symbols: @[], metrics: @[], verificationQueue: @[],
      structuralBottlenecks: @[], repairPriorityDependencies: @[],
      symbolFirstPass: false)
    let res = payloadsForSelectedUnits(emptyAnalysis, @["src/core/x.nim::fx"])
    check not res.isOk()