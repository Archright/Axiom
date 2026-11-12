import std/json
import std/unittest
import cli/wf_state
import cli/cli_types
import core/sorter/sorter_core
import core/orchestrator/orchestrator_report_types

func makeNodeId(raw: string): SorterNodeId =
  sorterNodeId(raw)

func makeNodeReport(
  nodeId: SorterNodeId;
  status: OrchestrationNodeStatus;
): OrchestrationNodeReport =
  OrchestrationNodeReport(
    nodeId: nodeId,
    dependencyDepth: 0,
    status: status,
  )

proc buildReport(
  nodeReports: seq[OrchestrationNodeReport];
): OrchestrationReport =
  var r: OrchestrationReport
  r.nodeReports = nodeReports
  r

suite "minimal":
  test "findAxNodeStatus - nested call":
    let nid = makeNodeId("test::func")
    let nr = makeNodeReport(nid, orchestrationVerified)
    let report = buildReport(@[nr])
    let status = findAxNodeStatus(report, nid)
    check status == axProofVerified
