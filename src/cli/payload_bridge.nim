import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary
import std/json
import std/strutils
import std/os
import std/sets
import core/results
import core/sorter/sorter_core
import core/orchestrator/orchestrator_types
import core/topology/topology_engine
import core/utils/io_utils
import core/boundary/boundary_extractor
import core/axiom_pragmas

## DEBT#418: Directory/Documentation Debt Audit — 141 machine-grounded findings across src/, config, docs.
proc buildMinimalSmt(nodeId: string; sourceCode: string; impactIndex: int): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDebt: "DEBT#418".} =
  if sourceCode.len == 0:
    return ""
  let boundaries = extractBoundaries(nodeId, sourceCode)
  var constraints: seq[string] = @[]
  for p in boundaries.params:
    if p.smtConstraint.len > 0:
      constraints.add(p.smtConstraint)
  if constraints.len == 0:
    return ""
  for c in constraints:
    result.add(c & "\n")
  result.add("(check-sat)\n")

proc topologyToWorkflowPayload*(topologyJson: string; sourceRoot: string = ""): Result[tuple[state: SorterState, requests: seq[OrchestrationProofRequest]], string] =
  ## Bridge topology scan output to workflow payload expected by batch UAP.
  ## Synthesizes an axiomaticFrontier from verificationQueue entries.
  try:
    let root = parseJson(topologyJson)
    if root.kind != JObject:
      return err("topology JSON must be object")

    var frontier = newJArray()
    if root.hasKey("verificationQueue") and root["verificationQueue"].kind == JArray:
      for entry in root["verificationQueue"]:
        let nodeIdStr = entry{"nodeId"}.getStr("")
        if nodeIdStr.len == 0:
          continue
        let impactIndex = entry{"topologyScore"}.getInt(0)
        frontier.add(%*{
          "nodeId": nodeIdStr,
          "impactIndex": impactIndex
        })

    var nodes: seq[SorterNode] = @[]
    var requests: seq[OrchestrationProofRequest] = @[]
    for entry in frontier:
      if entry.kind != JObject:
        continue
      let nodeIdStr = entry{"nodeId"}.getStr("")
      if nodeIdStr.len == 0:
        continue
      let parts = nodeIdStr.split("::")
      if parts.len < 2:
        continue
      let modulePath = parts[0].normalizedPath()
      let functionName = parts[1]
      let impactIndex = entry{"impactIndex"}.getInt(0)
      let node = makeSorterNode(modulePath, functionName, sorterNodeId(nodeIdStr), @[])
      nodes.add(node)
      let sourceOpt = if sourceRoot.len > 0:
        let absPath = sourceRoot / modulePath
        let absOpt = readFileOpt(absPath)
        if absOpt.isOk: absOpt else: readFileOpt(modulePath)
      else:
        readFileOpt(modulePath)
      let sourceCode = if sourceOpt.isOk: sourceOpt.get() else: ""
      let smt = buildMinimalSmt(nodeIdStr, sourceCode, impactIndex)
      let request = initOrchestrationProofRequest(
        nodeId = sorterNodeId(nodeIdStr),
        sourceCode = sourceCode,
        stateValue = 100,
        inputDelta = 70,
        expectedSmtlib2 = smt,
        timeoutMs = 30_000,
        topologyScore = impactIndex
      )
      requests.add(request)
    ok((state: initSorterState(nodes), requests: requests))
  except CatchableError as e:
    err("payload bridge: " & e.msg)

proc topologyFrontierToWorkflowPayload*(
  analysis: TopologyAnalysis;
  frontier: seq[SorterNodeId];
  sourceRoot: string = ""
): Result[tuple[state: SorterState, requests: seq[OrchestrationProofRequest]], string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Bridge a topology analysis and a masked frontier to a workflow payload.
  ## The returned SorterState retains the full dependency graph from the
  ## topology analysis; only the frontier nodes become proof requests.
  try:
    var requests: seq[OrchestrationProofRequest] = @[]
    let fullState = analysis.state
    for nodeId in frontier:
      let nodeIdStr = sorterNodeIdString(nodeId)
      let parts = nodeIdStr.split("::")
      if parts.len < 2:
        continue
      let modulePath = parts[0].normalizedPath()
      let metricOpt = findTopologyMetric(analysis, nodeId)
      let impactIndex = if metricOpt.isSome: metricOpt.get().topologyScore else: 0
      let sourceOpt = if sourceRoot.len > 0:
        let absPath = sourceRoot / modulePath
        let absOpt = readFileOpt(absPath)
        if absOpt.isOk: absOpt else: readFileOpt(modulePath)
      else:
        readFileOpt(modulePath)
      let sourceCode = if sourceOpt.isOk: sourceOpt.get() else: ""
      let smt = buildMinimalSmt(nodeIdStr, sourceCode, impactIndex)
      let request = initOrchestrationProofRequest(
        nodeId = nodeId,
        sourceCode = sourceCode,
        stateValue = 100,
        inputDelta = 70,
        expectedSmtlib2 = smt,
        timeoutMs = 30_000,
        topologyScore = impactIndex
      )
      requests.add(request)
    ok((state: fullState, requests: requests))
  except CatchableError as e:
    err("payload bridge frontier: " & e.msg)

# ---------------------------------------------------------------------------
# payloadsForSelectedUnits — plan→payload mapping (unit-testable without CLI)
# ---------------------------------------------------------------------------

proc payloadsForSelectedUnits*(
  analysis: TopologyAnalysis;
  selectedUnitIds: seq[string];
  sourceRoot: string = ""
): Result[tuple[state: SorterState, requests: seq[OrchestrationProofRequest]], string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Map plan.selectedUnitIds (modulePath::functionName format) to the
  ## same OrchestrationProofRequest objects the frontier path builds.
  ## Fail-closed: any unit id that cannot be mapped to a real node in
  ## the topology analysis returns an error — never silently skips.
  try:
    var requests: seq[OrchestrationProofRequest] = @[]
    let fullState = analysis.state
    var nodeIdSet = initHashSet[string]()
    for node in fullState.nodes:
      nodeIdSet.incl(sorterNodeIdString(node.id))

    for unitId in selectedUnitIds:
      if unitId notin nodeIdSet:
        return err("plan selectedUnitId not found in topology universe: " & unitId)
      let parts = unitId.split("::")
      if parts.len < 2:
        return err("plan selectedUnitId has invalid format (expected modulePath::functionName): " & unitId)
      let modulePath = parts[0].normalizedPath()
      let functionName = parts[1]
      let nodeId = sorterNodeId(unitId)
      let metricOpt = findTopologyMetric(analysis, nodeId)
      let impactIndex = if metricOpt.isSome: metricOpt.get().topologyScore else: 0
      let sourceOpt = if sourceRoot.len > 0:
        let absPath = sourceRoot / modulePath
        let absOpt = readFileOpt(absPath)
        if absOpt.isOk: absOpt else: readFileOpt(modulePath)
      else:
        readFileOpt(modulePath)
      let sourceCode = if sourceOpt.isOk: sourceOpt.get() else: ""
      let smt = buildMinimalSmt(unitId, sourceCode, impactIndex)
      let request = initOrchestrationProofRequest(
        nodeId = nodeId,
        sourceCode = sourceCode,
        stateValue = 100,
        inputDelta = 70,
        expectedSmtlib2 = smt,
        timeoutMs = 30_000,
        topologyScore = impactIndex
      )
      requests.add(request)
    ok((state: fullState, requests: requests))
  except CatchableError as e:
    err("payload bridge selected units: " & e.msg)
{.pop.}
