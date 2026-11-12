import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import cli/cli_types
import cli/topology_cli
import core/orchestrator/orchestrator_report_types
import cli/wf_state_parsing
import cli/wf_state_vacuity
export wf_state_parsing
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import core/results
import core/sorter/sorter_core
import core/telemetry/metrics
import core/topology/topology_engine
import core/utils/file_utils
import core/vault/vault_manager_spec
import std/algorithm
import std/os
import std/sequtils
import std/sets
import std/strutils
import std/times
import core/types/quarantine
import verification/cli_bridge
import verification/proof_state_builder
import verification/state_manager
import verification/state_persistence
import core/trusted/axiom_pragmas
## Find Ax Node Status.
func findAxNodeStatus*(report: OrchestrationReport; nodeId: SorterNodeId): AxProofStatus =
  for nodeReport in report.nodeReports:
    if nodeIdEquals(nodeReport.nodeId, nodeId):
      return mapAxProofStatus(nodeReport.status)
  axProofUnattempted
func hasForceHealQuarantineReason(entry: JsonNode): bool {.raises: [].} =
  var reasons: seq[string] = @[]
  for key in [reasonKey, "staleReason", "leanDiagnostics", remediationHintKey,
      "raw_smt_query", strategyKey]:
    reasons.add(proofStateStringField(entry, key))
  if isForceHealReason(reasons):
    return true
  # Also check transitionLog for past vacuous_contradiction history
  let transitionLogOpt = entry.getOrDefault("transitionLog")
  if not transitionLogOpt.isNil and transitionLogOpt.kind == JArray:
    for logEntry in transitionLogOpt.elems:
      if logEntry.kind == JObject:
        let toNode = logEntry.getOrDefault("to")
        if not toNode.isNil and toNode.kind == JString:
          let toStatus = toNode.getStr("").toLowerAscii()
          if toStatus.contains("vacuous_contradiction"):
            return true
  false
proc resetForceHealQuarantine*(state: var JsonNode; expectedVersionHash: string  = ""): int =
  if state.kind != JObject or not state.hasKey(entriesKey) or state[entriesKey].kind != JArray:
    return 0

  var versionMismatch = false
  if expectedVersionHash.len > 0:
    let metaNode = state.getOrDefault("metadata")
    if not metaNode.isNil and metaNode.kind == JObject:
      let storedVersion = proofStateStringField(metaNode, "engineVersionHash")
      if storedVersion.len > 0 and storedVersion != expectedVersionHash:
        versionMismatch = true
    if state.hasKey("metadata") and state["metadata"].kind == JObject:
      state["metadata"]["engineVersionHash"] = newJString(expectedVersionHash)
    elif state.kind == JObject:
      state["metadata"] = newJObject()
      state["metadata"]["engineVersionHash"] = newJString(expectedVersionHash)

  for entry in state[entriesKey].elems:
    if entry.kind != JObject:
      continue
    let status = proofStateStringField(entry, statusKey)
    if status == unattemptedKey or status == certifiedExemptStatus:
      continue
    let hasQuarantine = hasForceHealQuarantineReason(entry)
    if not hasQuarantine and not versionMismatch:
      continue
    entry[statusKey] = newJString(unattemptedKey)
    entry["attempted"] = newJBool(false)
    entry["attemptCount"] = newJInt(0)
    if versionMismatch:
      entry[reasonKey] = newJString("auto-invalidation:engine-version-changed")
      entry["staleReason"] = newJString("version-hash-mismatch-retry")
    else:
      entry[reasonKey] = newJString("force-heal-quarantine-reset")
      entry["staleReason"] = newJString("force-heal-retry")
    for key in ["healCooldown", "leanDiagnostics", "bottleneckLog"]:
      if entry.hasKey(key):
        try:
          entry.delete(key)
        except KeyError:
          discard
    inc result
  if result > 0:
    recomputeAxProofStateSummary(state)
proc applyCertifiedExemptionsFromSource*(state: var JsonNode; sourceRoot: string): int  =
  if state.kind != JObject or not state.hasKey(entriesKey) or state[entriesKey].kind != JArray:
    return 0
  for entry in state[entriesKey].elems:
    if entry.kind != JObject:
      continue
    let modulePath = proofStateStringField(entry, modulePathKey)
    let functionName = proofStateStringField(entry, functionNameKey)
    if modulePath.len == 0 or functionName.len == 0:
      continue
    let sourcePath = joinPath(sourceRoot, modulePath.replace('/', DirSep))
    if not fileExists(sourcePath):
      continue
    try:
      let source = readFileSafe(sourcePath)
      if not isCertifiedExemptFunctionSource(source, functionName):
        continue
      entry[statusKey] = newJString(certifiedExemptStatus)
      entry["attempted"] = newJBool(true)
      entry[reasonKey] = newJString("certified-exempt:axiom-pure-or-vacuous-primitive")
      entry["exemptionReason"] = newJString("axiom-pure-or-vacuous-primitive")
      if entry.hasKey("healCooldown"):
        try:
          entry.delete("healCooldown")
        except KeyError:
          discard
      inc result
    except CatchableError:
      discard # axiom:best-effort(exemption scan; non-critical path)
  if result > 0:
    recomputeAxProofStateSummary(state)

## Json From Ax Proof Entries.
# @axiom-hint: lean="selectedItems.size ≥ 0" smt="(assert (and (>= (seq.len selectedItems) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func jsonFromAxProofEntries*(
  bundle: TopologyCliAnalysisBundle;
  selectedItems: seq[SorterWorkItem];
  report: OrchestrationReport
): JsonNode =
  let selectedNodeIds = selectedItems.mapIt(it.nodeId)
  let nodeIndexTable = buildNodeIndexTable(bundle.analysis.state)
  let dependencyDepths = computeTopologyNodeDepths(bundle.analysis.state, nodeIndexTable)
  result = newJArray()
  var addedNodeIds: HashSet[string]
  for metric in bundle.analysis.metrics:
    let nodeIdx = findNodeIndex(nodeIndexTable, metric.nodeId)
    if nodeIdx < 0:
      continue
    let nodeIdStr = sorterNodeIdString(metric.nodeId)
    addedNodeIds.incl(nodeIdStr)
    let attempted = containsNodeId(selectedNodeIds, metric.nodeId)
    let status =
      if attempted:
        findAxNodeStatus(report, metric.nodeId)
      else:
        axProofUnattempted
    var premises = 0
    var smtlib2 = ""
    for nodeReport in report.nodeReports:
      if nodeIdEquals(nodeReport.nodeId, metric.nodeId):
        premises = nodeReport.injectedAxioms.len
        smtlib2 = nodeReport.smtlib2
        break
    let node = bundle.analysis.state.nodes[nodeIdx]
    let entryObj = %*{
      nodeIdKey: nodeIdStr,
      labelKey: verifyWorkflowLabelFromNode(node),
      functionNameKey: node.functionName,
      modulePathKey: node.modulePath,
      "nodeType": node.nodeType,
      dependencyDepthKey: dependencyDepths[nodeIdx],
      impactIndexKey: topologyImpactIndex(metric),
      statusKey: axProofStatusValue(status),
      "attempted": attempted,
      premiseCountKey: premises,
      "dependencyCount": metric.dependencyCount,
      "dependentNodeCount": metric.dependentCount,
      "transitiveDependentCount": metric.transitiveDependentCount
    }
    if smtlib2.len > 0:
      entryObj["raw_smt_query"] = %smtlib2
    else:
      entryObj["raw_smt_query"] = %""
    result.add(entryObj)
  ## Ensure selectedItems that are not present in metrics are still
  ## recorded in proof state (e.g., nodes discovered after topology
  ## analysis or from external sources).
  for item in selectedItems:
    let nodeIdStr = sorterNodeIdString(item.nodeId)
    if nodeIdStr in addedNodeIds:
      continue
    addedNodeIds.incl(nodeIdStr)
    let nodeIdx = findNodeIndex(nodeIndexTable, item.nodeId)
    if nodeIdx < 0:
      continue
    let status = findAxNodeStatus(report, item.nodeId)
    var premises = 0
    var smtlib2 = ""
    for nodeReport in report.nodeReports:
      if nodeIdEquals(nodeReport.nodeId, item.nodeId):
        premises = nodeReport.injectedAxioms.len
        smtlib2 = nodeReport.smtlib2
        break
    let node = bundle.analysis.state.nodes[nodeIdx]
    let entryObj = %*{
      nodeIdKey: nodeIdStr,
      labelKey: verifyWorkflowLabelFromNode(node),
      functionNameKey: node.functionName,
      modulePathKey: node.modulePath,
      "nodeType": node.nodeType,
      dependencyDepthKey: dependencyDepths[nodeIdx],
      impactIndexKey: 0,
      statusKey: axProofStatusValue(status),
      "attempted": true,
      premiseCountKey: premises,
      "dependencyCount": 0,
      "dependentNodeCount": 0,
      "transitiveDependentCount": 0
    }
    if smtlib2.len > 0:
      entryObj["raw_smt_query"] = %smtlib2
    else:
      entryObj["raw_smt_query"] = %""
    result.add(entryObj)
  result.elems.sort(proc(left: JsonNode; right: JsonNode): int =
    let leftDepth = left[dependencyDepthKey].getInt()
    let rightDepth = right[dependencyDepthKey].getInt()
    if leftDepth != rightDepth:
      return cmp(leftDepth, rightDepth)
    let leftImpact = left[impactIndexKey].getInt()
    let rightImpact = right[impactIndexKey].getInt()
    if leftImpact != rightImpact:
      return cmp(rightImpact, leftImpact)
    cmp(left[labelKey].getStr(), right[labelKey].getStr())
  )
func verifyWorkflowReason*(report: OrchestrationReport; nodeId: SorterNodeId): string =
  var reasons: seq[string] = @[]
  if containsNodeId(report.staleDependencyNodes, nodeId):
    reasons.add("stale axiom")
  if containsNodeId(report.timeoutNodes, nodeId):
    reasons.add("timeout")
  if containsNodeId(report.timeoutImpactNodes, nodeId) and
      not containsNodeId(report.timeoutNodes, nodeId):
    reasons.add("timeout impact")
  if containsNodeId(report.blockedNodes, nodeId):
    reasons.add("blocked branch")
  for nodeReport in report.nodeReports:
    if nodeIdEquals(nodeReport.nodeId, nodeId):
      case nodeReport.status
      of orchestrationProofFailed:
        reasons.add("proof failed")
      of orchestrationVacuousContradiction:
        reasons.add("vacuous contradiction")
      of orchestrationTimedOut:
        reasons.add("timeout")
      of orchestrationBlocked:
        reasons.add("blocked")
      of orchestrationVerified:
        discard
      of orchestrationInductiveValid:
        discard  # Soft Truth — not a failure reason
      of orchestrationPreSievedUnverifiable:
        reasons.add("pre-sieved unverifiable")
      of orchestrationSkippedByTheory:
        reasons.add("skipped by theory")
      of orchestrationNotVerifiable:
        reasons.add("not verifiable")
      of orchestrationNoObligation:
        discard  # No obligation — not a failure reason
  if reasons.len == 0:
    return "reproof required"
  reasons.deduplicate().join(", ")
## build Ax Proof State Json variable.
let buildAxProofStateJson* = proc (
  target: string;
  bundle: TopologyCliAnalysisBundle;
  selectedItems: seq[SorterWorkItem];
  report: OrchestrationReport;
  shortcutStatePath: string = ""
): JsonNode =
  let entries = jsonFromAxProofEntries(bundle, selectedItems, report)
  let verifiedCount = countAxProofStatuses(entries.elems, verifiedKey)
  let counterCount = countAxProofStatuses(entries.elems, "counter_example_found")
  let vacuousCount = countAxProofStatuses(entries.elems, "vacuous_contradiction")
  let timeoutCount = countAxProofStatuses(entries.elems, "timed_out")
  let unattemptedCount = countAxProofStatuses(entries.elems, unattemptedKey)
  let unverifiableCount = countAxProofStatuses(entries.elems, "unverifiable")
  let pseudoVerifiedCount = countAxProofStatuses(entries.elems, "pseudo_verified")
  let certifiedExemptCount = countAxProofStatuses(entries.elems, certifiedExemptStatus)
  let totalForAsi = bundle.totalSourceFunctions
  let asiVal = asString(getUnifiedAsiFixed4(bundle.sourceRoot, true))
  result = %*{
    targetKey: target,
    sourceRootKey: bundle.sourceRoot,
    timestampKey: now().utc().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
    "summary": {
      totalNodesKey: bundle.analysis.state.nodes.len,
      attemptedNodesKey: selectedItems.len,
      verifiedKey: verifiedCount,
      counterExamplesKey: counterCount,
      vacuousContradictionsKey: vacuousCount,
      timedOutKey: timeoutCount,
      "unverifiable": unverifiableCount,
      "pseudoVerified": pseudoVerifiedCount,
      "certifiedExempt": certifiedExemptCount,
      unattemptedKey: unattemptedCount,
      "engineAsiFixed4": asiVal,
      "totalSourceFunctions": totalForAsi
    },
    entriesKey: entries,
    "workflow": {
      reproofRequiredKey: newJArray(),
      "performance": {
        totalWallTimeMsKey: report.executionStats.totalWallTimeMs,
        cpuEfficiencyKey: report.executionStats.cpuEfficiency,
        "parallelSpeedupRatio": report.executionStats.parallelSpeedupRatio,
        cacheHitCountKey: report.executionStats.cacheHitCount,
        "timeoutCount": report.executionStats.timeoutCount,
        "timeoutImpactNodes": report.timeoutImpactNodes.len,
        "hotspotLabel": verifyWorkflowLabelFromNodeId(report.finalState, report.executionStats.hotspotNodeId),
        "hotspotElapsedMs": report.executionStats.hotspotElapsedMs
      },
      "timeoutDiagnostics": newJArray()
    }
  }
  for nodeId in report.reproofNodes:
    result["workflow"][reproofRequiredKey].add(%*{
      labelKey: verifyWorkflowLabelFromNodeId(report.finalState, nodeId),
      reasonKey: verifyWorkflowReason(report, nodeId)
    })
  for nodeReport in report.nodeReports:
    if nodeReport.status != orchestrationTimedOut or nodeReport.remediationHint.len == 0:
      continue
    result["workflow"]["timeoutDiagnostics"].add(%*{
      labelKey: verifyWorkflowLabelFromNodeId(report.finalState, nodeReport.nodeId),
      "complexityWeight": nodeReport.timeoutComplexityWeight,
      "hotspots": jsonNodeStringArray(nodeReport.timeoutHotspots),
      remediationHintKey: nodeReport.remediationHint,
      "mathematicalRationale": nodeReport.mathematicalRationale
    })
  if shortcutStatePath.len > 0:
    result[shortcutStateKey] = %shortcutStatePath

## Trim Proof State Path Prefix.
# @axiom-hint: lean="normalizedPrefix.length = 0 ∧ normalizedValue ∧ normalizedPrefix.length = 0 → result = normalizedValue" smt="(assert (and (= (str.len normalizedPrefix) 0) normalizedValue (=> (= (str.len normalizedPrefix) 0) (= result normalizedValue))))"
proc trimProofStatePathPrefix*(value: string; prefix: string): string {.noSideEffect, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let normalizedValue = normalizePath(value)
  let normalizedPrefix = normalizePath(prefix)
  if normalizedPrefix.len == 0:
    return normalizedValue
  let prefixWithSeparator =
    if normalizedPrefix.endsWith("/"):
      normalizedPrefix
    else:
      normalizedPrefix & "/"
  if normalizedValue.startsWith(prefixWithSeparator):
    return normalizedValue[prefixWithSeparator.len .. ^1]
  normalizedValue

## Sort Ax Proof Entries.
# @axiom-hint: lean="entries.size ≥ 0" smt="(assert (and (>= (seq.len entries) 0)))"
# @axiom-hint: lean="leftDepth ≠ rightDepth ∧ leftImpact ≠ rightImpact" smt="(assert (and (not (= leftDepth rightDepth)) (not (= leftImpact rightImpact))))"
func sortAxProofEntries*(entries: var seq[JsonNode]) {.noSideEffect.} =
  entries.sort(proc(left: JsonNode; right: JsonNode): int =
    let leftDepth =
      if left.hasKey(dependencyDepthKey) and left[dependencyDepthKey].kind in {JInt, JFloat}:
        left[dependencyDepthKey].getInt()
      else:
        0
    let rightDepth =
      if right.hasKey(dependencyDepthKey) and right[dependencyDepthKey].kind in {JInt, JFloat}:
        right[dependencyDepthKey].getInt()
      else:
        0
    if leftDepth != rightDepth:
      return cmp(leftDepth, rightDepth)
    let leftImpact =
      if left.hasKey(impactIndexKey) and left[impactIndexKey].kind in {JInt, JFloat}:
        left[impactIndexKey].getInt()
      else:
        0
    let rightImpact =
      if right.hasKey(impactIndexKey) and right[impactIndexKey].kind in {JInt, JFloat}:
        right[impactIndexKey].getInt()
      else:
        0
    if leftImpact != rightImpact:
      return cmp(rightImpact, leftImpact)
    let leftLabel =
      if left.hasKey(labelKey) and left[labelKey].kind == JString:
        left[labelKey].getStr()
      else:
        ""
    let rightLabel =
      if right.hasKey(labelKey) and right[labelKey].kind == JString:
        right[labelKey].getStr()
      else:
        ""
    cmp(leftLabel, rightLabel)
  )

## Ax State Entry Engine.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func axStateEntryEngine*(entry: JsonNode): string {.noSideEffect.} =
  let semanticProof = entry{"semanticProof"}
  if semanticProof.isNil or semanticProof.kind != JObject:
    return "unknown"
  let universalPipeline = semanticProof{"universalPipeline"}
  if not universalPipeline.isNil and universalPipeline.kind == JObject:
    let provenance = universalPipeline{"provenance"}
    if not provenance.isNil and provenance.kind == JObject:
      let engine = provenance{"engine"}
      if not engine.isNil and engine.kind == JString:
        return engine.getStr()
  let engine = semanticProof{"engine"}
  if not engine.isNil and engine.kind == JString:
    return engine.getStr()
  "unknown"
## semantic Entry Dependency Mismatch Reason variable.
let semanticEntryDependencyMismatchReason* = proc (entry: JsonNode): string =
  let semanticProof = entry{"semanticProof"}
  if semanticProof.isNil or semanticProof.kind != JObject:
    return ""
  let universalPipeline = semanticProof{"universalPipeline"}
  if universalPipeline.isNil or universalPipeline.kind != JObject:
    return ""
  let dependencyContext = universalPipeline{"dependencyContext"}
  let smtTrack = universalPipeline{"smtTrack"}
  if dependencyContext.isNil or dependencyContext.kind != JObject:
    return ""
  if smtTrack.isNil or smtTrack.kind != JObject:
    return ""
  let modulePathNode = smtTrack{modulePathKey}
  if modulePathNode.isNil or modulePathNode.kind != JString:
    return ""
  let modulePath = modulePathNode.getStr()
  if modulePath.len == 0:
    return ""
  let symbolChecksums = dependencyContext{"symbolChecksums"}
  if symbolChecksums.isNil or symbolChecksums.kind != JArray:
    return ""
  var storedChecksum = ""
  for item in symbolChecksums.elems:
    if item.kind != JObject:
      continue
    let symbolNode = item{"symbol"}
    let checksumNode = item{"checksum"}
    if symbolNode.isNil or checksumNode.isNil:
      continue
    if symbolNode.kind == JString and checksumNode.kind == JString and symbolNode.getStr() == modulePath:
      storedChecksum = checksumNode.getStr()
      break
  if storedChecksum.len == 0:
    return ""
  if not fileExists(modulePath):
    return "dependency missing: " & modulePath
  let currentChecksum = try:
    vault_manager_spec.computeSourceFingerprint(readFileSafe(modulePath))
  except CatchableError:
    ""
  if currentChecksum.len == 0:
    return "dependency unreadable: " & modulePath
  if currentChecksum != storedChecksum:
    return "dependency checksum mismatch: " & modulePath
  ""

## persist Ax Proof State variable.
let persistAxProofState* = proc (statePath: string; reportNode: JsonNode): Result[string, string] =
  let reportDir = parentDir(statePath)
  if reportDir.len > 0 and not dirExists(reportDir):
    discard existsOrCreateDir(reportDir)
  ## Atomic self-healing: use atomicWriteProofState for crash-safe persistence.
  let jsonContent = renderJsonMultiline(reportNode)
  if not atomicWriteProofState(statePath, jsonContent):
    ## Fallback: if atomic write fails, try the legacy saveProofState path.
    let saveRes = saveProofState(statePath, reportNode, "prove", "orchestration-complete")
    if saveRes.isErr():
      return err("failed to persist ax proof state: " & statePath)
  ok(statePath)

## Merge Previous Verified State.
# @axiom-hint: lean="canCarryForward ∧ prevStatus ≠ unattemptedKey ∧ mergedTotal > 0 ∧ result = currentState ∧ result ∧ (currentIndexByLabel ≥ 0) ∧ (result ≥ 0)" smt="(assert (and canCarryForward (not (= prevStatus unattemptedKey)) (> mergedTotal 0) (= result currentState) result (>= currentIndexByLabel 0) (>= result 0)))"

{.pop.}
