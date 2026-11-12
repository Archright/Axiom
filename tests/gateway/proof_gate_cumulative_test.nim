## Proof Gate Cumulative ASI Tests — Global Monotonic Projection.
##
## Verifies that computeCumulativeCanonicalAsi unions historical verified
## certificates with the current batch, guaranteeing non-decreasing ASI.

import std/unittest
import core/orchestrator/orchestrator_report_types
import core/sorter/sorter_core
import cli/proof_gate

func makeNodeReport(
  nodeIdStr: string;
  status: OrchestrationNodeStatus
): OrchestrationNodeReport =
  OrchestrationNodeReport(
    nodeId: sorterNodeId(nodeIdStr),
    status: status,
    smtlib2: ""
  )

func makeReport(
  verified, failed: int;
  totalSourceFunctions: int
): ValidatedProofReport =
  var nodes: seq[OrchestrationNodeReport] = @[]
  for i in 0 ..< verified:
    nodes.add(makeNodeReport("src/mod.nim::ok" & $i, orchestrationVerified))
  for i in 0 ..< failed:
    nodes.add(makeNodeReport("src/mod.nim::fail" & $i, orchestrationProofFailed))
  let report = OrchestrationReport(
    nodeReports: nodes,
    executionStats: OrchestrationExecutionStats(depthStats: @[
      OrchestrationDepthExecutionStat(dependencyDepth: 0)
    ])
  )
  initValidatedProofReport(report, totalSourceFunctions)

suite "CumulativeCanonicalASI":

  test "historical plus current batch increases ASI":
    let report = makeReport(verified = 3, failed = 0, totalSourceFunctions = 100)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 10)
    check state.netVerifiedFunctions == 13
    check state.totalFunctions == 100
    check string(state.vkd) == "0.1300"
    check state.completionRate == 0.13

  test "empty batch preserves historical ASI":
    let report = makeReport(verified = 0, failed = 0, totalSourceFunctions = 100)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 10)
    check state.netVerifiedFunctions == 10
    check string(state.vkd) == "0.1000"

  test "failed nodes do not inflate cumulative count":
    let report = makeReport(verified = 2, failed = 3, totalSourceFunctions = 100)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 5)
    check state.netVerifiedFunctions == 7
    check string(state.vkd) == "0.0700"

  test "kernelScopeVerifiedCount overrides batch verified count":
    let report = makeReport(verified = 3, failed = 0, totalSourceFunctions = 100)
    let state = computeCumulativeCanonicalVkd(report, historicalVerified = 10, kernelScopeVerifiedCount = 1)
    check state.netVerifiedFunctions == 11
    check string(state.vkd) == "0.1100"
