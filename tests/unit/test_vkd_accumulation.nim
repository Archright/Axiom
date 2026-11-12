import std/unittest
import core/orchestrator/orchestrator_report_types
import core/sorter/sorter_core
import cli/proof_gate

func makeReport(
  verified, vacuous, tautology: int;
  totalSourceFunctions: int
): ValidatedProofReport =
  var nodes: seq[OrchestrationNodeReport] = @[]
  for i in 0 ..< verified:
    nodes.add(OrchestrationNodeReport(
      nodeId: sorterNodeId("mod.nim::ok" & $i),
      status: orchestrationVerified,
      smtlib2: ""
    ))
  for i in 0 ..< vacuous:
    nodes.add(OrchestrationNodeReport(
      nodeId: sorterNodeId("mod.nim::vac" & $i),
      status: orchestrationVacuousContradiction,
      smtlib2: ""
    ))
  for i in 0 ..< tautology:
    nodes.add(OrchestrationNodeReport(
      nodeId: sorterNodeId("mod.nim::taut" & $i),
      status: orchestrationVerified,
      smtlib2: "(assert true)"
    ))
  let report = OrchestrationReport(
    nodeReports: nodes,
    executionStats: OrchestrationExecutionStats(depthStats: @[
      OrchestrationDepthExecutionStat(dependencyDepth: 0)
    ])
  )
  initValidatedProofReport(report, totalSourceFunctions)

suite "computeCumulativeCanonicalVkd":

  test "historical=10 + netNew=5, total=94 -> cumulative 15/94":
    let report = makeReport(verified = 5, vacuous = 0, tautology = 0, totalSourceFunctions = 94)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 10)
    check state.netVerifiedFunctions == 15
    check state.totalFunctions == 94
    check string(state.vkd) == "0.1596"

  test "historical=90 + netNew=10, total=94 -> clamps VKD to 1.0000":
    let report = makeReport(verified = 10, vacuous = 0, tautology = 0, totalSourceFunctions = 94)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 90)
    check state.netVerifiedFunctions == 100
    check state.totalFunctions == 94
    check string(state.vkd) == "1.0000"

  test "historical=0 + netNew=0, total=94 -> zero VKD":
    let report = makeReport(verified = 0, vacuous = 0, tautology = 0, totalSourceFunctions = 94)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 0)
    check state.netVerifiedFunctions == 0
    check state.totalFunctions == 94
    check string(state.vkd) == "0.0000"
    check state.completionRate == 0.0
