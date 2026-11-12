import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import ../core/trusted/axiom_pragmas
import ../core/metrics
import cli/topology_cli
import cli/wf_state
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import core/orchestrator/orchestrator_types
import core/results
import core/sorter/sorter_core
import core/topology/topology_engine
import core/types/refactor_task_types
import core/types/obligation_evidence
import core/types/asi_types
import cli/report_format
import std/json
import std/sequtils
import std/strformat
import std/strutils
import std/tables
import ui/notion_semantic_mapper
## top Proof Targets From Topology Output variable.
## Render Ax Scan Lines.
  ## axiom-smt: (assert (and (>= result 0)))
  ## axiom-lean: (result ≥ 0)
proc renderAxScanLines*(target: string; bundle: TopologyCliAnalysisBundle; frontier: seq[AxFrontierEntry]): seq[string] {.axiom, axiomImpl.} =
  result = @[
    "target=" & target,
    "sourceRoot=" & bundle.sourceRoot,
    "symbolCount=" & $bundle.analysis.symbols.len,
    "plannedNodeCount=" & $bundle.analysis.state.nodes.len,
    "queueLimit=" & $bundle.effectiveQueueLimit,
    "diagnosisDepth=" & $bundle.effectiveDiagnosisDepth,
    "structuralBottleneckCount=" & $bundle.diagnoses.len,
    "axiomaticFrontierCount=" & $frontier.len
  ]

## Render Ax Workflow Report Lines.
func renderAxWorkflowReportLines*(reportNode: JsonNode): seq[string] =
  if not reportNode.hasKey("workflow") or reportNode["workflow"].kind != JObject:
    return @[]
  let workflow = reportNode["workflow"]
  if workflow.hasKey(reproofRequiredKey) and workflow[reproofRequiredKey].kind == JArray:
    if workflow[reproofRequiredKey].elems.len == 0:
      result.add("Reproof Required: None")
    else:
      result.add("Reproof Required:")
      for entry in workflow[reproofRequiredKey].elems:
        result.add("- " & entry.getOrDefault(labelKey).getStr() & " (" & entry.getOrDefault(reasonKey).getStr() & ")")
  if workflow.hasKey("performance") and workflow["performance"].kind == JObject:
    let performance = workflow["performance"]
    let totalWallTimeMs = performance.getOrDefault(totalWallTimeMsKey).getInt()
    let cpuEfficiency = performance.getOrDefault(cpuEfficiencyKey).getFloat()
    let parallelSpeedupRatio = performance.getOrDefault("parallelSpeedupRatio").getFloat()
    let cacheHitCount = performance.getOrDefault(cacheHitCountKey).getInt()
    let timeoutCount = performance.getOrDefault("timeoutCount").getInt()
    let timeoutImpactNodes = performance.getOrDefault("timeoutImpactNodes").getInt()
    let hotspotLabel = performance.getOrDefault("hotspotLabel").getStr()
    let hotspotElapsedMs = performance.getOrDefault("hotspotElapsedMs").getInt()
    result.add("Performance Summary:")
    result.add(fmt"- CPU Efficiency: {formatFloat(cpuEfficiency, ffDecimal, 2)}%")
    result.add(fmt"- Parallel Speedup: {formatFloat(parallelSpeedupRatio, ffDecimal, 2)}x")
    result.add(fmt"- Cache Hits: {cacheHitCount}")
    result.add(fmt"- Timeout Count: {timeoutCount}")
    result.add(fmt"- Timeout Impact: {timeoutImpactNodes} nodes")
    ## R7 determinism: wall-clock timing (Total Wall Time, Hotspot elapsed ms)
    ## is excluded from canonical text output and moved to runtimeMeta in JSON.
  if workflow.hasKey("timeoutDiagnostics") and workflow["timeoutDiagnostics"].kind == JArray and
      workflow["timeoutDiagnostics"].elems.len > 0:
    result.add("Timeout Diagnosis:")
    for entry in workflow["timeoutDiagnostics"].elems:
      let labelValue = entry.getOrDefault(labelKey).getStr()
      let complexityWeight = entry.getOrDefault("complexityWeight").getInt()
      let remediationHint = entry.getOrDefault(remediationHintKey).getStr()
      let mathematicalRationale = entry.getOrDefault("mathematicalRationale").getStr()
      let hotspots =
        if entry.hasKey("hotspots") and entry["hotspots"].kind == JArray:
          entry["hotspots"].elems.mapIt(it.getStr()).join(", ")
        else:
          ""
      result.add(fmt"- {labelValue} | complexity={complexityWeight} | hotspot={hotspots}")
      result.add("  remediation: " & remediationHint)
      result.add("  rationale: " & mathematicalRationale)

## Render Ax Report Lines.
func bugVerdictLine(displayNode: JsonNode): string =
  ## One display unit's 2축 표시 한 줄 (T3) — display labels only, never a
  ## machine verdict value (glossary §2.4); the consumed machine spellings
  ## co-display on the same line (display-owned namespace).
  var line = "bugVerdict=" & displayNode{"bugAttribution"}.getStr("")
  let ruleLabel = displayNode{"ruleJudgment"}.getStr("")
  if ruleLabel.len > 0:
    line &= " | rule=" & ruleLabel
  let kindsNode = displayNode{"uncertaintyKinds"}
  if not kindsNode.isNil and kindsNode.kind == JArray and kindsNode.len > 0:
    var kindLabels: seq[string] = @[]
    for kindNode in kindsNode:
      let kindLabel = kindNode.getStr("")
      if kindLabel.len > 0:
        kindLabels.add(kindLabel)
    if kindLabels.len > 0:
      line &= " (" & kindLabels.join("; ") & ")"
  let machineStatesNode = displayNode{"machineStates"}
  if not machineStatesNode.isNil and machineStatesNode.kind == JArray and
      machineStatesNode.len > 0:
    var machineLabels: seq[string] = @[]
    for machineStateNode in machineStatesNode:
      let machineLabel = machineStateNode.getStr("")
      if machineLabel.len > 0:
        machineLabels.add(machineLabel)
    if machineLabels.len > 0:
      line &= " machine=" & machineLabels.join(",")
  line

func colorizeStatus(statusValue: string; useColor: bool): string =
  if not useColor: return statusValue
  result = case statusValue
  of "verified", "inductive_valid": applyAnsiColor(statusValue, "32", true)
  of "failed", "vacuous_contradiction", "counter_example": applyAnsiColor(statusValue, "31", true)
  of "timeout": applyAnsiColor(statusValue, "33", true)
  of "blocked": applyAnsiColor(statusValue, "33", true)
  of "pre_sieved", "unverifiable": applyAnsiColor(statusValue, "36", true)
  else: statusValue
  ## axiom-smt: (assert (and (or (= includeUnattempted true) (= includeUnattempted false)) (> (str.len stateFilePath) 0) (= (str.len entriesToRender) 0) (> (str.len idValue) 0) result (=> (= (str.len entriesToRender) 0) (= result result)) (>= entriesToRender 0) (>= maxImpactLen 0) (>= maxEngineLen 0) (>= maxDepthLen 0) (>= maxIdLen 0) (>= maxPremiseLen 0) (>= maxReasonLen 0) (>= maxSymbolLen 0) (>= maxStatusLen 0) (>= result 0) (or (= includeUnattempted true) (= includeUnattempted false))))
  ## axiom-lean: includeUnattempted = true ∨ includeUnattempted = false ∧ stateFilePath.length > 0 ∧ entriesToRender.length = 0 ∧ idValue.length > 0 ∧ result ∧ entriesToRender.length = 0 → result = result ∧ (entriesToRender ≥ 0) ∧ (maxImpactLen ≥ 0) ∧ (maxEngineLen ≥ 0) ∧ (maxDepthLen ≥ 0) ∧ (maxIdLen ≥ 0) ∧ (maxPremiseLen ≥ 0) ∧ (maxReasonLen ≥ 0) ∧ (maxSymbolLen ≥ 0) ∧ (maxStatusLen ≥ 0) ∧ (result ≥ 0) ∧ includeUnattempted = true ∨ includeUnattempted = false
proc renderAxReportLines*(reportNode: JsonNode; includeUnattempted: bool = false; stateFilePath: string = ""; useColor: bool = false): seq[string] {.axiom, axiomImpl.} =
  let summary = reportNode.getOrDefault("summary")
  if summary.isNil or summary.kind != JObject:
    return @["status=none symbol=none depth=0 impactIndex=0 premises=0"]
  result = renderAxWorkflowReportLines(reportNode)
  if stateFilePath.len > 0:
    result.add("stateFile=" & stateFilePath)
  result.add(@[
    "target=" & reportNode.getOrDefault(targetKey).getStr(),
    "sourceRoot=" & reportNode.getOrDefault(sourceRootKey).getStr(),
    "timestamp=" & reportNode.getOrDefault(timestampKey).getStr(),
    "totalNodes=" & $summary.getOrDefault(totalNodesKey).getInt(),
    "attemptedNodes=" & $summary.getOrDefault(attemptedNodesKey).getInt(),
    "verified=" & $summary.getOrDefault(verifiedKey).getInt(),
    "counterExamples=" & $summary.getOrDefault(counterExamplesKey).getInt(),
    "timedOut=" & $summary.getOrDefault(timedOutKey).getInt(),
    "unverifiable=" & $(if summary.hasKey("unverifiable"): summary["unverifiable"].getInt() else: 0),
    "unattempted=" & $summary.getOrDefault(unattemptedKey).getInt()
  ])
  # T3 — 2축 표시 한 줄: only when the namespaced display block is present in
  # the report document; the lines project display labels only and are never
  # machine verdict values (glossary §2.4). Display v3: ONE line per unit of
  # the `units` array (the per-unit projection), in the block's deterministic
  # unit order. Legacy v2 shape (a pre-units persisted state file with a
  # single top-level block) still renders its one line. 기계 상태 병기: the
  # consumed machine spellings co-display on the same line (display-owned
  # namespace).
  block:
    let displayNode = reportNode.getOrDefault("display")
    if not displayNode.isNil and displayNode.kind == JObject:
      let unitsNode = displayNode{"units"}
      if not unitsNode.isNil and unitsNode.kind == JArray:
        for unitNode in unitsNode:
          if unitNode.isNil or unitNode.kind != JObject:
            continue
          if unitNode.hasKey("bugAttribution"):
            result.add(bugVerdictLine(unitNode))
      elif displayNode.hasKey("bugAttribution"):
        result.add(bugVerdictLine(displayNode))
  if not reportNode.hasKey(entriesKey) or reportNode[entriesKey].kind != JArray or reportNode[entriesKey].elems.len == 0:
    result.add("No proof entries found. Run 'ax prove' to generate verification data.")
    return result
  result.add("proofStatusMatrix:")

  var entriesToRender: seq[JsonNode]
  var blockedCount = 0
  for entry in reportNode[entriesKey].elems:
    let statusValue = entry[statusKey].getStr()
    if statusValue == "blocked":
      inc blockedCount
    if statusValue == unattemptedKey and not includeUnattempted:
      continue
    entriesToRender.add(entry)

  if entriesToRender.len == 0:
    result.add("status=none symbol=none depth=0 impactIndex=0 premises=0")
    return result

  # Compute maximum widths for each field
  var maxStatusLen = 0
  var maxEngineLen = 0
  var maxSymbolLen = 0
  var maxDepthLen = 0
  var maxImpactLen = 0
  var maxPremiseLen = 0
  var maxReasonLen = 0
  var maxIdLen = 0
  var maxObligationTerminalLen = 0

  for entry in entriesToRender:
    let idValue =
      if entry.hasKey("id") and entry["id"].kind == JString:
        entry["id"].getStr()
      else:
        ""
    maxStatusLen = max(maxStatusLen, entry.getOrDefault(statusKey).getStr().len)
    maxEngineLen = max(maxEngineLen, axStateEntryEngine(entry).len)
    maxSymbolLen = max(maxSymbolLen, entry.getOrDefault(labelKey).getStr().len)
    maxDepthLen = max(maxDepthLen, ($entry.getOrDefault(dependencyDepthKey).getInt()).len)
    maxImpactLen = max(maxImpactLen, ($entry.getOrDefault(impactIndexKey).getInt()).len)
    maxPremiseLen = max(maxPremiseLen, ($entry.getOrDefault(premiseCountKey).getInt()).len)
    maxIdLen = max(maxIdLen, idValue.len)
    if entry.hasKey("staleReason") and entry["staleReason"].kind == JString:
      maxReasonLen = max(maxReasonLen, entry["staleReason"].getStr().len)
    ## P5: obligation_terminal column — extract from evidenceLogJson
    ## when status is "not_verifiable" (orchestrationNotVerifiable).
    if entry.getOrDefault(statusKey).getStr() == "not_verifiable":
      let evJson = entry.getOrDefault("evidenceLogJson")
      if evJson.kind == JString and evJson.getStr().len > 0:
        maxObligationTerminalLen = max(maxObligationTerminalLen, evJson.getStr().len)

  # Render each entry with aligned columns
  for entry in entriesToRender:
    let statusValue = entry.getOrDefault(statusKey).getStr()
    let engineValue = axStateEntryEngine(entry)
    let labelValue = entry.getOrDefault(labelKey).getStr()
    let depthValue = entry.getOrDefault(dependencyDepthKey).getInt()
    let impactValue = entry.getOrDefault(impactIndexKey).getInt()
    let premiseValue = entry.getOrDefault(premiseCountKey).getInt()
    let idValue =
      if entry.hasKey("id") and entry["id"].kind == JString:
        entry["id"].getStr()
      else:
        ""
    let staleReason =
      if entry.hasKey("staleReason") and entry["staleReason"].kind == JString:
        " reason=" & alignLeft(entry["staleReason"].getStr(), maxReasonLen)
      else:
        ""

    ## P5: obligation_terminal column
    let obligationTerminal =
      if statusValue == "not_verifiable":
        let evJson = entry.getOrDefault("evidenceLogJson")
        if evJson.kind == JString and evJson.getStr().len > 0:
          " obligation_terminal=" & alignLeft(evJson.getStr(), maxObligationTerminalLen)
        else:
          ""
      else:
        ""

    let coloredStatus = colorizeStatus(statusValue, useColor)
    let statusStr = alignLeft(coloredStatus, maxStatusLen)
    let engineStr = alignLeft(engineValue, maxEngineLen)
    let symbolStr = alignLeft(labelValue, maxSymbolLen)
    let depthStr = alignLeft($depthValue, maxDepthLen)
    let impactStr = alignLeft($impactValue, maxImpactLen)
    let premiseStr = alignLeft($premiseValue, maxPremiseLen)
    let idStr =
      if idValue.len > 0:
        " id=" & alignLeft(idValue, maxIdLen)
      else:
        ""

    result.add(
      "status=" & statusStr & " engine=" & engineStr & " symbol=" & symbolStr & " " &
      "depth=" & depthStr & " impactIndex=" & impactStr & " " &
      "premises=" & premiseStr & idStr & staleReason & obligationTerminal
    )

  let unverifiableCount = if summary.hasKey("unverifiable"): summary["unverifiable"].getInt() else: 0
  let preSievedCount = if summary.hasKey("preSieved"): summary["preSieved"].getInt() else: 0
  result.add("")
  result.add(renderGateSectionHeader(ngkSieve))
  result.add("  Verified: " & $summary.getOrDefault(verifiedKey).getInt() & " | Unverifiable: " & $unverifiableCount & " | Pre-Sieved: " & $preSievedCount)
  result.add(renderGateSectionHeader(ngkDiagnosis))
  result.add("  Counter-examples: " & $summary.getOrDefault(counterExamplesKey).getInt() & " | Timed-out: " & $summary.getOrDefault(timedOutKey).getInt())
  result.add(renderGateSectionHeader(ngkGuidance))
  result.add("  Blocked: " & $blockedCount & " | Unattempted: " & $summary.getOrDefault(unattemptedKey).getInt())
  if summary.hasKey("refactoringTemplates"):
    let templates = summary["refactoringTemplates"]
    if templates.kind == JArray and templates.len > 0:
      result.add("  Refactoring guidance:")
      for tmpl in templates:
        result.add("    → " & tmpl.getOrDefault("description").getStr() & " (" & tmpl.getOrDefault("nimHint").getStr() & ")")

  if reportNode.hasKey(shortcutStateKey) and reportNode[shortcutStateKey].kind == JString:
    result.add("shortcutState=" & reportNode[shortcutStateKey].getStr())

## Render Pseudo-Verified Warning.
## Generates a human-readable warning for nodes isolated as pseudo-verified.
func renderPseudoVerifiedReport*(pseudoVerifiedCount: int): seq[string] {.raises: [], axiom: ["(assert (and (>= pseudoVerifiedCount -9223372036854775808) (<= pseudoVerifiedCount 9223372036854775807) (and (>= pseudoVerifiedCount -9223372036854775808) (<= pseudoVerifiedCount 9223372036854775807)) (<= pseudoVerifiedCount 0) (>= result 0)))", "pseudoVerifiedCount ≥ -9223372036854775808 ∧ pseudoVerifiedCount ≤ 9223372036854775807 ∧ pseudoVerifiedCount ≥ -9223372036854775808 ∧ pseudoVerifiedCount ≤ 9223372036854775807 ∧ pseudoVerifiedCount ≤ 0 ∧ (result ≥ 0)"].} =
  if pseudoVerifiedCount <= 0:
    return @[]
  result = @[
    "Lack of Substantive Evidence: " & $pseudoVerifiedCount & " node(s) isolated as pseudo-verified",
    "  These nodes passed solver checks but failed substantive scrutiny (tautology or vacuity).",
    "  They are excluded from VKD calculation. Run 'ax prove --heal --filter <node>' for re-proof."
  ]

## top Proof Targets From Topology Output variable.
## Render Ax Scan Lines.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
let topProofTargetsFromTopologyOutput* = proc (outputJson: string; limit: int = 3): Result[seq[string], string] =
  let parsed = try:
    json.parseJson(outputJson)
  except CatchableError:
    return err("topology output JSON parse failed")
  if not parsed.hasKey("verificationQueue") or parsed["verificationQueue"].kind != JArray:
    return err("topology output missing verificationQueue")
  var targets: seq[string] = @[]
  for entry in parsed["verificationQueue"].elems:
    if entry.kind != JObject:
      continue
    if not entry.hasKey(labelKey) or entry[labelKey].kind != JString:
      continue
    targets.add(entry[labelKey].getStr())
    if targets.len >= max(1, limit):
      break
  ok(targets)
## Render Recent Batch Context.
## Generates a human-readable summary of status changes since the last report run.
## Uses transitionLog timestamps in proof state entries to detect recent activity.
func renderRecentBatchContext*(reportNode: JsonNode; lastRunTs: string): seq[string] {.raises: [], axiom: ["(assert (and (>= (str.len lastRunTs) 0) (or (= (str.len ts) 0) (<= ts lastRunTs)) (and (> (str.len label) 0) (> (str.len toStatus) 0)) (= changeCount 0) (> (str.len recentChanges) 5) (>= result 0)))", "lastRunTs.length ≥ 0 ∧ ts.length = 0 ∨ ts ≤ lastRunTs ∧ label.length > 0 ∧ toStatus.length > 0 ∧ changeCount = 0 ∧ recentChanges.length > 5 ∧ (result ≥ 0)"].} =
  result = @[]
  let entriesNode = reportNode{entriesKey}
  if entriesNode.kind != JArray:
    return
  var changeCount = 0
  var recentChanges = newSeq[tuple[label: string, fromStatus: string, toStatus: string, actor: string]]()
  for entry in entriesNode.elems:
    if entry.kind != JObject:
      continue
    let transitionLog = entry{"transitionLog"}
    if transitionLog.isNil or transitionLog.kind != JArray:
      continue
    for t in transitionLog.elems:
      if t.kind != JObject:
        continue
      let ts = t{"ts"}.getStr("")
      if ts.len == 0 or ts <= lastRunTs:
        continue
      let label = entry{labelKey}.getStr("")
      let fromStatus = t{"from"}.getStr("")
      let toStatus = t{"to"}.getStr("")
      let actor = t{"actor"}.getStr("prove")
      if label.len > 0 and toStatus.len > 0:
        recentChanges.add((label: label, fromStatus: fromStatus, toStatus: toStatus, actor: actor))
        inc changeCount
  if changeCount == 0:
    result.add("Recent Batch Context:")
    result.add("  Since last report: 0 status changes")
    result.add("  All nodes stable.")
  else:
    result.add("Recent Batch Context:")
    result.add("  Since last report: " & $changeCount & " status change(s)")
    for i in 0 ..< min(5, recentChanges.len):
      let change = recentChanges[i]
      let fromStr = if change.fromStatus.len > 0: change.fromStatus & " → " else: "→ "
      result.add("    - " & change.label & ": " & fromStr & change.toStatus & " (" & change.actor & ")")
    if recentChanges.len > 5:
      result.add("    ... and " & $(recentChanges.len - 5) & " more")


## Helpers for jsonFromOrchestrationReport (migrated from verify_workflow_cli.nim).
func verifyWorkflowStatusValue(status: OrchestrationNodeStatus): string {.raises: [].} =
  case status
  of orchestrationVerified:
    result = "verified"
  of orchestrationInductiveValid:
    result = "inductive_valid"
  of orchestrationProofFailed:
    result = "failed"
  of orchestrationVacuousContradiction:
    result = "vacuous_contradiction"
  of orchestrationTimedOut:
    result = "timeout"
  of orchestrationBlocked:
    result = "blocked"
  of orchestrationPreSievedUnverifiable:
    result = "pre_sieved"
  of orchestrationSkippedByTheory:
    result = "skipped_by_theory"
  of orchestrationNotVerifiable:
    result = "not_verifiable"
  of orchestrationNoObligation:
    result = "no_obligation"
func jsonAxiomArray(values: seq[AxiomFormula]): JsonNode {.raises: [].} =
  result = newJArray()
  for value in values:
    result.add(newJString(axiomFormulaString(value)))
func jsonFromOrchestrationReport*(report: OrchestrationReport; totalSourceFunctions: int = 0): JsonNode {.raises: [CatchableError].} =
  let finalState = report.finalState
  var rawVerified = 0
  var inductiveValidCount = 0
  var failedCount = 0
  var vacuousCount = 0
  var timeoutCount = 0
  var blockedCount = 0
  var preSievedCount = 0
  var skippedByTheoryCount = 0
  var classifiedNodes = 0  ## nodes with a resolved (non-empty) assuranceTier
  var reusedCount = 0      ## DEBT#459: cache-hit rows = REUSED satisfactions, not failures
  var tierCounts = initTable[string, int]()
  for k in ["z3-verified", "dual-verified", "lean-verified", "none", "k-induction", "uf-abstract", "unknown"]:
    tierCounts[k] = 0
  var statusCounts = initTable[string, int]()
  for k in ["failed", "skipped", "timeout", "blocked", "vacuous", "verified", "inductive_valid", "pre_sieved", "reused"]:
    statusCounts[k] = 0
  let nodeReports = newJArray()
  for nodeReport in report.nodeReports:
    case nodeReport.status
    of orchestrationVerified:
      inc rawVerified
    of orchestrationInductiveValid:
      inc inductiveValidCount
    of orchestrationProofFailed:
      # DEBT#459: a cache-hit row is a REUSED satisfaction (canonical
      # accounting classifies the (status, cacheHit=true) pair as SATISFIED +
      # REUSED + NOT_ATTEMPTED) — it must not inflate failedCount/exit code.
      # The runtime status stays fail-closed (cache hit ≠ kernel acceptance).
      if nodeReport.cacheHit:
        inc reusedCount
      else:
        inc failedCount
    of orchestrationVacuousContradiction:
      inc vacuousCount
    of orchestrationTimedOut:
      inc timeoutCount
    of orchestrationBlocked:
      inc blockedCount
    of orchestrationPreSievedUnverifiable:
      inc preSievedCount
    of orchestrationSkippedByTheory:
      inc skippedByTheoryCount
    of orchestrationNotVerifiable:
      inc preSievedCount
    of orchestrationNoObligation:
      inc preSievedCount
    # statusCounts: failed/skipped/timeout are tracked separately per contract.
    case nodeReport.status
    of orchestrationProofFailed:
      if nodeReport.cacheHit:
        inc statusCounts["reused"]
      else:
        inc statusCounts["failed"]
    of orchestrationSkippedByTheory:
      inc statusCounts["skipped"]
    of orchestrationTimedOut:
      inc statusCounts["timeout"]
    of orchestrationBlocked:
      inc statusCounts["blocked"]
    of orchestrationVacuousContradiction:
      inc statusCounts["vacuous"]
    of orchestrationVerified:
      inc statusCounts["verified"]
    of orchestrationInductiveValid:
      inc statusCounts["inductive_valid"]
    of orchestrationPreSievedUnverifiable:
      inc statusCounts["pre_sieved"]
    of orchestrationNotVerifiable:
      inc statusCounts["pre_sieved"]
    of orchestrationNoObligation:
      inc statusCounts["pre_sieved"]
    # Phase 1 Tier semantics: project assuranceTier + tierResolution verbatim.
    if nodeReport.assuranceTier.len > 0:
      inc classifiedNodes
      if tierCounts.hasKey(nodeReport.assuranceTier):
        inc tierCounts[nodeReport.assuranceTier]
      else:
        tierCounts[nodeReport.assuranceTier] = 1
    nodeReports.add(%*{
      "nodeId": sorterNodeIdString(nodeReport.nodeId),
      "label": verifyWorkflowLabelFromNodeId(finalState, nodeReport.nodeId),
      "dependencyDepth": nodeReport.dependencyDepth,
      "usesDependencyVault": nodeReport.usesDependencyVault,
      "readsDependencySource": nodeReport.readsDependencySource,
      "injectedAxioms": jsonAxiomArray(nodeReport.injectedAxioms),
      "status": verifyWorkflowStatusValue(nodeReport.status),
      "vaultPath": nodeReport.vaultPath,
      "cacheHit": nodeReport.cacheHit,
      "remediationHint": nodeReport.remediationHint,
      "mathematicalRationale": nodeReport.mathematicalRationale,
      "timeoutComplexityWeight": nodeReport.timeoutComplexityWeight,
      "timeoutHotspots": jsonNodeStringArray(nodeReport.timeoutHotspots),
      "selfHealingGuidance": jsonNodeStringArray(nodeReport.selfHealingGuidance),
      "evidenceLogJson": nodeReport.evidenceLogJson,
      "assuranceTier": nodeReport.assuranceTier,
      "tierResolution": nodeReport.tierResolution
    })
  let verifiedCount = int(computeVerified(rawVerified, inductiveValidCount, vacuousCount))
  let nodeExecutionStats = newJArray()
  for nodeStat in report.executionStats.nodeStats:
    nodeExecutionStats.add(%*{
      "nodeId": sorterNodeIdString(nodeStat.nodeId),
      "label": verifyWorkflowLabelFromNodeId(finalState, nodeStat.nodeId),
      "dependencyDepth": nodeStat.dependencyDepth,
      "solverElapsedMs": nodeStat.solverElapsedMs,
      "wallElapsedMs": nodeStat.wallElapsedMs,
      "cacheHit": nodeStat.cacheHit,
      "status": verifyWorkflowStatusValue(nodeStat.status),
      "timeoutMs": nodeStat.timeoutMs,
      "failureReason": nodeStat.failureReason
    })
  let depthExecutionStats = newJArray()
  for depthStat in report.executionStats.depthStats:
    depthExecutionStats.add(%*{
      "dependencyDepth": depthStat.dependencyDepth,
      "startedAtMs": depthStat.startedAtMs,
      "endedAtMs": depthStat.endedAtMs,
      "elapsedMs": depthStat.elapsedMs,
      "solverElapsedMs": depthStat.solverElapsedMs,
      "parallelOverheadMs": depthStat.parallelOverheadMs,
      "activeNodeCount": depthStat.activeNodeCount,
      "workerCount": depthStat.workerCount,
      "speedupRatio": depthStat.speedupRatio,
      "availableMemoryBytes": depthStat.availableMemoryBytes,
      "cpuLoadRatio": depthStat.cpuLoadRatio,
      "recommendedWorkerCount": depthStat.recommendedWorkerCount
    })
  ## R7 determinism: wall-clock timing values are separated from
  ## canonical output into runtimeMeta (excluded from byte-comparison).
  let runtimeMetaJson = %*{
    "totalWallTimeMs": report.executionStats.totalWallTimeMs,
    "hotspotElapsedMs": report.executionStats.hotspotElapsedMs,
    "hotspotLabel": verifyWorkflowLabelFromNodeId(finalState, report.executionStats.hotspotNodeId)
  }
  result = %*{
    "summary": {
      verifiedKey: verifiedCount,
      "failedCount": failedCount,
      "reusedCount": reusedCount,
      "vacuousCount": vacuousCount,
      "timeoutCount": timeoutCount,
      "blockedCount": blockedCount,
      "staleCount": report.staleDependencyNodes.len,
      "reproofCount": report.reproofNodes.len,
      "cacheHitCount": report.executionStats.cacheHitCount,
      "solverInvocationCount": report.executionStats.solverInvocationCount,
      "totalSourceFunctions": totalSourceFunctions,
      "verificationSuccessRate": if verifiedCount + failedCount + vacuousCount + timeoutCount + blockedCount > 0: initAsiRatio(verifiedCount.float / float(verifiedCount + failedCount + vacuousCount + timeoutCount + blockedCount)).get(defaultAsiRatio()).toFloat else: 0.0,
      "preSieved": preSievedCount,
      "classifiedNodes": classifiedNodes,
      "tierCounts": %*{
        "z3-verified": %tierCounts["z3-verified"],
        "dual-verified": %tierCounts["dual-verified"],
        "lean-verified": %tierCounts["lean-verified"],
        "none": %tierCounts["none"],
        "k-induction": %tierCounts["k-induction"],
        "uf-abstract": %tierCounts["uf-abstract"],
        "unknown": %tierCounts["unknown"]
      },
      "statusCounts": %*{
        "verified": %statusCounts["verified"],
        "inductive_valid": %statusCounts["inductive_valid"],
        "failed": %statusCounts["failed"],
        "skipped": %statusCounts["skipped"],
        "timeout": %statusCounts["timeout"],
        "blocked": %statusCounts["blocked"],
        "vacuous": %statusCounts["vacuous"],
        "pre_sieved": %statusCounts["pre_sieved"],
        "reused": %statusCounts["reused"]
      }
    },
    "nodeReports": nodeReports,
    "blockedNodes": jsonNodeStringArray(nodeIdsToLabels(finalState, report.blockedNodes)),
    "staleDependencyNodes": jsonNodeStringArray(nodeIdsToLabels(finalState, report.staleDependencyNodes)),
    "reproofNodes": jsonNodeStringArray(nodeIdsToLabels(finalState, report.reproofNodes)),
    "timeoutNodes": jsonNodeStringArray(nodeIdsToLabels(finalState, report.timeoutNodes)),
    "timeoutImpactNodes": jsonNodeStringArray(nodeIdsToLabels(finalState, report.timeoutImpactNodes)),
    "executionStats": %*{
      "totalWallTimeMs": report.executionStats.totalWallTimeMs,
      "totalSolverTimeMs": report.executionStats.totalSolverTimeMs,
      "serialBaselineMs": report.executionStats.serialBaselineMs,
      "parallelSpeedupRatio": report.executionStats.parallelSpeedupRatio,
      "cpuEfficiency": report.executionStats.cpuEfficiency,
      "cacheHitCount": report.executionStats.cacheHitCount,
      "solverInvocationCount": report.executionStats.solverInvocationCount,
      "maxWorkerCount": report.executionStats.maxWorkerCount,
      "timeoutCount": report.executionStats.timeoutCount,
      "hotspotNodeId": sorterNodeIdString(report.executionStats.hotspotNodeId),
      "hotspotLabel": verifyWorkflowLabelFromNodeId(finalState, report.executionStats.hotspotNodeId),
      "hotspotElapsedMs": report.executionStats.hotspotElapsedMs,
      "nodeStats": nodeExecutionStats,
      "depthStats": depthExecutionStats,
      "obligationGeneratedCount": report.executionStats.obligationGeneratedCount,
      "obligationAttemptedCount": report.executionStats.obligationAttemptedCount,
      "targetsWithObligations": report.executionStats.targetsWithObligations,
      "eligibleTargets": report.executionStats.eligibleTargets
    }
  }
  ## R7 determinism: attach runtimeMeta (timing) outside canonical payload.
  result["runtimeMeta"] = runtimeMetaJson
func verifyWorkflowStatusLabel(status: OrchestrationNodeStatus): string {.raises: [].} =
  case status
  of orchestrationVerified:
    result = "VERIFIED"
  of orchestrationInductiveValid:
    result = "INDUCTIVE_VALID"
  of orchestrationProofFailed:
    result = "FAILED"
  of orchestrationVacuousContradiction:
    result = "VACUOUS_CONTRADICTION"
  of orchestrationTimedOut:
    result = "TIMEOUT"
  of orchestrationBlocked:
    result = "BLOCKED"
  of orchestrationPreSievedUnverifiable:
    result = "PRE-SIEVED"
  of orchestrationSkippedByTheory:
    result = "SKIPPED_BY_THEORY"
  of orchestrationNotVerifiable:
    result = "NOT_VERIFIABLE"
  of orchestrationNoObligation:
    result = "NO_OBLIGATION"
func verifyWorkflowResultLabel(status: OrchestrationNodeStatus; cacheHit: bool): string {.raises: [].} =
  if cacheHit and status == orchestrationVerified:
    return "CACHED"
  result = verifyWorkflowStatusLabel(status)
func verifyWorkflowTotalDepths(state: SorterState): int {.raises: [].} =
  let plan = buildSorterPlan(state)
  var maxDepth = 0
  for workItem in plan.workItems:
    if workItem.dependencyDepth > maxDepth:
      maxDepth = workItem.dependencyDepth
  result = maxDepth + 1
func renderVerifyWorkflowProgressLines*(report: OrchestrationReport): seq[string] {.raises: [CatchableError].} =
  let totalDepths = verifyWorkflowTotalDepths(report.finalState)
  for nodeReport in report.nodeReports:
    result.add(fmt"[Depth {nodeReport.dependencyDepth + 1}/{totalDepths}] Checking: {verifyWorkflowLabelFromNodeId(report.finalState, nodeReport.nodeId)}... [{verifyWorkflowResultLabel(nodeReport.status, nodeReport.cacheHit)}]")
func renderVerifyWorkflowProgressEventLine*(
  state: SorterState;
  event: OrchestrationProgressEvent
): string {.raises: [CatchableError].} =
  case event.kind
  of orchestrationDepthStarted:
    result = fmt"[Depth {event.dependencyDepth + 1}/{event.totalDepths}] Parallel Processing: {event.activeNodeCount} nodes in progress..."
  of orchestrationNodeStarted:
    result = fmt"[Depth {event.dependencyDepth + 1}/{event.totalDepths}] Solving: {verifyWorkflowLabelFromNodeId(state, event.nodeId)}..."
  of orchestrationNodeFinished:
    result = fmt"[Depth {event.dependencyDepth + 1}/{event.totalDepths}] Checking: {verifyWorkflowLabelFromNodeId(state, event.nodeId)}... [{verifyWorkflowResultLabel(event.status, event.cacheHit)}]"
  of orchestrationPrimingProgress:
    result = fmt"[Priming {event.primedCount}/{event.workerCount}] Loading: {verifyWorkflowLabelFromNodeId(state, event.nodeId)}..."

## Refactor strategy display name.
func refactorStrategyName*(s: RefactorStrategy): string {.raises: [].} =
  case s
  of stratStructuralAST: "structural_ast"
  of stratInvariantInference: "invariant_inference"

## Refactor rule display name.
func refactorRuleName*(r: SieveRuleKind): string {.raises: [].} =
  case r
  of srkTopology: "topology"
  of srkAstAnalysis: "ast_analysis"
  of srkUnsatCore: "unsat_core"
  of srkIoBoundary: "io_boundary"

## Render per-task refactor info lines.
## Shows REFACTOR status for each task with entropy, strategy, rule, templates, and attempt.
func renderRefactorTaskLines*(tasks: seq[RefactorTask]; softMisses: seq[string] = @[]): seq[string] {.raises: [].} =
  if tasks.len == 0:
    return @[]
  result.add(fmt"Refactoring Tasks ({tasks.len}):")
  for task in tasks:
    result.add(fmt"  REFACTOR: {task.functionName} (E={task.currentEntropy:.2f})")
    result.add(fmt"    Strategy: {refactorStrategyName(task.strategy)}  Rule: {refactorRuleName(task.dominantRule)}")
    result.add(fmt"    Templates: {task.templates.len}  Attempt: {task.attempt}/{task.maxAttempts}")
  if softMisses.len > 0:
    result.add("    Soft misses: " & softMisses.join(", ") & " (proceeding with Z3)")

## Render escalation reason line.
func renderEscalationLine*(taskName: string; reason: string): string {.raises: [].} =
  "  ESCALATED: " & taskName & " — " & reason

## Human-readable layer outcome label (unlike the raw enum stringification).
func layerOutcomeLabel*(o: LayerOutcome): string {.raises: [].} =
  case o
  of leSucceeded: "succeeded"
  of leFailedSat: "rejected (counterexample)"
  of leFailedRlimit: "failed (resource limit)"
  of leFailedUnknown: "failed (unknown)"

proc dispatchRefactorReport*(results: openArray[RefactorResult]; taskNames: openArray[string]) {.axiomEffect: IOEffect.} =
  ## template로 제로 카피 보장: =copy 훅 호출 없이 컴파일 타임에 치환
  for i in 0..<results.len:
    template res: untyped = results[i]
    case res.status
    of rsVerified:
      # Truthful rendering contract: rsVerified on the refactor path is a
      # structural refactor-integrity claim (Z3 equivalence, layer "StructuralAST"),
      # NOT a Lean kernel acceptance. Label it as the verdict class it actually is
      # so it is never conflated with canonical Lean verification ("verified").
      stdout.writeLine("  ✓ " & taskNames[i] & " — structural verification")
    of rsSkipped:
      stdout.writeLine("  ⚠ " & taskNames[i] & " — skipped: " & $res.skipReason)
      if res.softMisses.len > 0:
        stdout.writeLine("    Soft misses: " & res.softMisses.join(", "))
    of rsEscalated:
      stdout.writeLine("  ✗ " & taskNames[i] & " — escalated: " & $res.escalateReason)
      if res.contextLog.len > 0:
        stdout.writeLine("    Context: " & res.contextLog)
    if res.evidence.layerTrace.len > 0:
      for layer in res.evidence.layerTrace:
        stdout.writeLine("    ↳ " & layer.layerName & ": " & layerOutcomeLabel(layer.outcome))

## Render refactor summary for JSON report.
func jsonRefactorSummary*(tasks: seq[RefactorTask]): JsonNode {.raises: [].} =
  let summary = newJObject()
  summary["totalTasks"] = %tasks.len
  var successCount = 0
  var escalatedCount = 0
  for task in tasks:
    case task.strategy
    of stratStructuralAST:
      inc successCount  # structural tasks are deterministic
    of stratInvariantInference:
      inc escalatedCount  # AI tasks are phase 2
  summary["structuralTasks"] = %successCount
  summary["aiInvariantTasks"] = %escalatedCount
  let taskArray = newJArray()
  for task in tasks:
    taskArray.add(%*{
      "functionName": task.functionName,
      "modulePath": task.modulePath,
      "entropy": task.currentEntropy,
      "strategy": refactorStrategyName(task.strategy),
      "dominantRule": refactorRuleName(task.dominantRule),
      "templates": task.templates.len,
      "attempt": task.attempt,
      "maxAttempts": task.maxAttempts,
      "belief": task.belief,
      "uncertainty": task.uncertainty
    })
  summary["tasks"] = taskArray
  summary

func jsonRefactorResultSummary*(results: seq[RefactorResult]): JsonNode =
  ## Serialize RefactorResult sequence with evidence
  result = newJArray()
  for res in results:
    var entry = %*{"status": $res.status}
    if res.evidence.layerTrace.len > 0:
      entry["evidence"] = res.evidence.toCanonicalJson()
    result.add(entry)

## Render refactor task summary lines appended to the progress report.
func renderRefactorSummaryLines*(tasks: seq[RefactorTask]): seq[string] {.raises: [].} =
  if tasks.len == 0:
    return @[]
  result.add("")
  result.add(renderGateSectionHeader(ngkSieve))
  result.add("  Refactoring: " & $tasks.len & " task(s) queued")
  for task in tasks:
    result.add(fmt"    → {task.functionName}: {refactorStrategyName(task.strategy)} ({refactorRuleName(task.dominantRule)})")

{.pop.}

