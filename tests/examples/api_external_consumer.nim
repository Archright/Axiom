import api

let nodeId = initVerificationSorterNodeId("pkg/demo.nim::prove")
let node = initVerificationSorterNode("pkg/demo.nim", "prove", nodeId, @[])
let request = initVerificationProofRequest(nodeId, "(assert true)", 1, 0)
let state = initVerificationSorterState(@[node])
let plan = initVerificationLoopPlan(state, @[request], "vault")

doAssert plan.requests.len == 1
doAssert verificationSorterNodeIdString(plan.requests[0].nodeId) == verificationSorterNodeIdString(nodeId)

let emptyState = initVerificationSorterState(@[])
let emptyPlan = initVerificationLoopPlan(emptyState, @[], "vault")
let emptyReport = runVerificationLoop(emptyPlan)

doAssert emptyReport.ok
doAssert emptyReport.value.finalState.nodes.len == 0
doAssert emptyReport.value.nodeReports.len == 0
