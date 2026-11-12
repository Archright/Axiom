import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import cli/cli_types
import core/orchestrator/orchestrator_report_types
import core/utils/constants
import core/contracts/universal_pipeline_contract
import core/diagnostics/diagnostics_engine
import core/topology/node_filter
import core/json/json_utils
import core/json/std_redirect
import core/results
import core/sorter/sorter_core
import core/axiom_pragmas
import core/topology/topology_engine
import core/topology/merkle_cache
import core/utils/file_utils
import std/json
import std/monotimes
import std/options
import std/os
import std/sequtils
import std/strutils
import std/tables
import infrastructure/logging_facade
type
  VerifyTopologyLogSink* = proc(line: string) {.gcsafe, closure, raises: [CatchableError].}

  TopologyCliAnalysisBundle* = object
    sourceRoot*: string
    sourceFileCount*: int
    analysis*: TopologyAnalysis
    diagnoses*: seq[StructuralDiagnosis]
    effectiveQueueLimit*: int
    effectiveDiagnosisDepth*: int
    totalSourceFunctions*: int  ## proc/func count from topology scan (UniverseRegistry denominator)
    sourceContentCache*: Table[string, string]  ## modulePath -> source content, populated during scan

  AxFrontierEntry* = object
    nodeId*: SorterNodeId
    label*: string
    dependencyDepth*: int
    impactIndex*: int
    topologyScore*: int
    centralityScore*: int
    couplingScore*: int
    interfaceDistance*: int
    dependentNodeCount*: int
    transitiveDependentCount*: int

  TopologyScanProgressSink* = proc(
    processed: int;
    total: int;
    currentLabel: string;
    actionLabel: string
  ) {.closure, raises: [CatchableError].}

  TopologyDiagnosisProgressSink* = proc(
    processed: int;
    total: int;
    currentLabel: string
  ) {.closure, raises: [CatchableError].}
## Compute Topology Node Depths.
# @axiom-hint: lean="dependencyIdx ≥ 0 ∧ (depth ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= dependencyIdx 0) (>= depth 0) (>= result 0)))"
proc computeTopologyNodeDepths*(
  state: SorterState;
  nodeIndexTable: Table[string, int]
): seq[int] =
  var output = newSeq[int](state.nodes.len)
  for idx in countdown(state.nodes.high, 0):
    var depth = 0
    for dependencyId in state.nodes[idx].dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx >= 0:
        depth = max(depth, output[dependencyIdx] + 1)
    output[idx] = depth
  output

## Topology Impact Index.
proc topologyImpactIndex*(metric: TopologyNodeMetric): int =
  metric.transitiveDependentCount * 5 +
    metric.dependentCount * 3 +
    metric.centralityScore +
    metric.couplingScore

## Ax Proof Status Value.
# @axiom-hint: lean="axProofVerified ∧ axProofCounterExampleFound ∧ axProofTimedOut ∧ axProofUnverifiable ∧ axProofUnattempted ∧ axProofVacuousContradiction ∧ axProofBlocked ∧ axProofUnknown" smt="(assert (and axProofVerified axProofCounterExampleFound axProofTimedOut axProofUnverifiable axProofUnattempted axProofVacuousContradiction axProofBlocked axProofUnknown))"
proc axProofStatusValue*(status: AxProofStatus): string =
  case status
  of axProofVerified: verifiedKey
  of axProofCounterExampleFound: "counter_example_found"
  of axProofTimedOut: "timed_out"
  of axProofUnverifiable: "unverifiable"
  of axProofUnattempted: unattemptedKey
  of axProofVacuousContradiction: "vacuous_contradiction"
  of axProofBlocked: "blocked"
  of axProofUnknown: "unknown"

## Map Ax Proof Status.
# @axiom-hint: lean="orchestrationVerified ∧ orchestrationProofFailed ∧ orchestrationTimedOut ∧ orchestrationVacuousContradiction" smt="(assert (and orchestrationVerified orchestrationProofFailed orchestrationTimedOut orchestrationVacuousContradiction))"
proc mapAxProofStatus*(status: OrchestrationNodeStatus): AxProofStatus =
  case status
  of orchestrationVerified: axProofVerified
  of orchestrationProofFailed: axProofCounterExampleFound
  of orchestrationTimedOut: axProofTimedOut
  of orchestrationVacuousContradiction: axProofVacuousContradiction
  else: axProofUnknown

## Map Semantic Proof Status.
proc mapSemanticProofStatus*(res: SemanticPayloadVerificationResponse): AxProofStatus =
  if res.verified: axProofVerified
  elif res.status.toLowerAscii() == "sat": axProofCounterExampleFound
  else: axProofTimedOut

## Semantic Proof Node Id.
proc semanticProofNodeId*(payload: SemanticEqualityPayload): string =
  semanticModulePathString(payload.modulePath) & "::" & semanticFunctionNameString(payload.functionName)

## Semantic Proof Label.
proc semanticProofLabel*(payload: SemanticEqualityPayload): string =
  extractFilename(semanticModulePathString(payload.modulePath)) & "::" & semanticFunctionNameString(payload.functionName)

## Semantic Proof Failure Reason.
proc semanticProofFailureReason*(res: SemanticPayloadVerificationResponse): string =
  if res.verified: ""
  elif res.status.toLowerAscii() == "sat": "semantic proof failed"
  elif res.status.toLowerAscii() == "unknown": "semantic solver returned unknown"
  else: "semantic proof inconclusive"

## Json String Array.
## DELETED: Use json_utils.jsonNodeStringArray instead.
## This function was a duplicate of jsonNodeStringArray and violated DRY.

## Node Ids To Labels.
# @axiom-hint: lean="(nodeIds ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= nodeIds 0) (>= result 0)))"
proc nodeIdsToLabels*(state: SorterState; nodeIds: seq[SorterNodeId]): seq[string] =
  var output = newSeqOfCap[string](nodeIds.len)
  for nodeId in nodeIds:
    output.add(verifyWorkflowLabelFromNodeId(state, nodeId))
  output
## Compute Smart Queue Limit.
# @axiom-hint: lean="plannedNodeCount ≥ -9223372036854775808 ∧ plannedNodeCount ≤ 9223372036854775807 ∧ processorCount ≥ -9223372036854775808 ∧ processorCount ≤ 9223372036854775807" smt="(assert (and (and (>= plannedNodeCount -9223372036854775808) (<= plannedNodeCount 9223372036854775807)) (and (>= processorCount -9223372036854775808) (<= processorCount 9223372036854775807))))"
proc computeSmartQueueLimit*(plannedNodeCount: int; processorCount: int): int {.raises: [].} =
  ## Compute optimal queue depth based on planned work and available processors.
  max(1, min(plannedNodeCount, processorCount * 4))
## Compute Smart Diagnosis Depth.
# @axiom-hint: lean="repairTargetCount ≥ -9223372036854775808 ∧ repairTargetCount ≤ 9223372036854775807 ∧ processorCount ≥ -9223372036854775808 ∧ processorCount ≤ 9223372036854775807" smt="(assert (and (and (>= repairTargetCount -9223372036854775808) (<= repairTargetCount 9223372036854775807)) (and (>= processorCount -9223372036854775808) (<= processorCount 9223372036854775807))))"
proc computeSmartDiagnosisDepth*(repairTargetCount: int; processorCount: int): int {.raises: [].} =
  ## Compute optimal diagnosis depth based on repair targets and available processors.
  max(1, min(repairTargetCount, processorCount * 2))
# @axiom-hint: lean="diagnoses.size ≥ 0" smt="(assert (and (>= (seq.len diagnoses) 0)))"
# @axiom-hint: lean="idx ∧ (diagnoses ≥ 0)" smt="(assert (and idx (>= diagnoses 0)))"
proc findStructuralDiagnosisIndex(
  diagnoses: seq[StructuralDiagnosis];
  nodeId: SorterNodeId
): int =
  for idx, diagnosis in diagnoses:
    if nodeIdEquals(diagnosis.nodeId, nodeId):
      return idx
  -1

# @axiom-hint: lean="diagnoses.size ≥ 0" smt="(assert (and (>= (seq.len diagnoses) 0)))"
# @axiom-hint: lean="diagnosisIdx < 0" smt="(assert (and (< diagnosisIdx 0)))"
proc structuralDiagnosisForNode(
  diagnoses: seq[StructuralDiagnosis];
  nodeId: SorterNodeId
): StructuralDiagnosis =
  let diagnosisIdx = findStructuralDiagnosisIndex(diagnoses, nodeId)
  if diagnosisIdx < 0:
    return StructuralDiagnosis(nodeId: nodeId)
  diagnoses[diagnosisIdx]

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
proc jsonFromStructuralDiagnosis(diagnosis: StructuralDiagnosis): JsonNode =
  %*{
    nodeIdKey: sorterNodeIdString(diagnosis.nodeId),
    "diagnosticLabels": jsonNodeStringArray(diagnosis.diagnosticLabels),
    remediationHintKey: diagnosis.remediationHint,
    "mathematicalRationale": diagnosis.mathematicalRationale,
    "childNodeCount": diagnosis.childNodeCount,
    "logicalDepth": diagnosis.logicalDepth,
    "interfaceDistance": diagnosis.interfaceDistance,
    "couplingScore": diagnosis.couplingScore,
    "astNodeId": diagnosis.astNodeId,
    "parentNodeType": diagnosis.parentNodeType,
    "childIndices": diagnosis.childIndices
  }

# @axiom-hint: lean="diagnoses.size ≥ 0" smt="(assert (and (>= (seq.len diagnoses) 0)))"
proc jsonFromTopologyQueueEntry(
  analysis: TopologyAnalysis;
  diagnoses: seq[StructuralDiagnosis];
  nodeId: SorterNodeId
): Option[JsonNode] =
  let metric = findTopologyMetric(analysis, nodeId)
  if metric.isNone():
    return none(JsonNode)
  let metricValue = metric.get()
  let diagnosis = structuralDiagnosisForNode(diagnoses, nodeId)
  some(%*{
    nodeIdKey: sorterNodeIdString(nodeId),
    labelKey: verifyWorkflowLabelFromNodeId(analysis.state, nodeId),
    "interfaceDistance":
      (if metricValue.interfaceDistance > analysis.metrics.len: -1 else: metricValue.interfaceDistance),
    "topologyScore": metricValue.topologyScore,
    "centralityScore": metricValue.centralityScore,
    "couplingScore": metricValue.couplingScore,
    "complexityScore": metricValue.complexityScore,
    "childNodeCount": metricValue.dependencyCount,
    "dependentNodeCount": metricValue.dependentCount,
    "branchCount": metricValue.branchCount,
    "nestingDepth": metricValue.nestingDepth,
    "logicalDepth": metricValue.logicalDepth,
    "diagnosticLabels": jsonNodeStringArray(diagnosis.diagnosticLabels),
    remediationHintKey: diagnosis.remediationHint,
    "mathematicalRationale": diagnosis.mathematicalRationale
  })
proc jsonFromTopologyQueue(
  analysis: TopologyAnalysis;
  diagnoses: seq[StructuralDiagnosis];
  queue: seq[SorterNodeId];
  bodyLoadCount: int;
  diagnosisDepth: int
): JsonNode =
  let queueEntries = newJArray()
  for entry in queue
      .mapIt(jsonFromTopologyQueueEntry(analysis, diagnoses, it))
      .filterIt(it.isSome())
      .mapIt(it.get()):
    queueEntries.add(entry)
  let diagnosisEntries = newJArray()
  for diagnosis in diagnoses:
    diagnosisEntries.add(jsonFromStructuralDiagnosis(diagnosis))
  %*{
    "summary": {
      "topologyScanComplete": true,
      "symbolCount": analysis.symbols.len,
      "plannedNodeCount": queue.len,
      "queuePreviewCount": queue.len,
      "effectiveQueueLimit": queue.len,
      "effectiveDiagnosisDepth": diagnosisDepth,
      "structuralBottleneckCount": analysis.structuralBottlenecks.len,
      "repairPriorityCount": analysis.repairPriorityDependencies.len,
      "bodyLoadCount": bodyLoadCount,
      "symbolFirstPass": analysis.symbolFirstPass
    },
    "verificationQueue": queueEntries,
    "structuralBottlenecks": jsonNodeStringArray(nodeIdsToLabels(analysis.state, analysis.structuralBottlenecks)),
    "repairPriorityDependencies": jsonNodeStringArray(nodeIdsToLabels(analysis.state, analysis.repairPriorityDependencies)),
    "diagnostics": diagnosisEntries
  }

## Json From Topology Analysis.
# @axiom-hint: lean="(diagnoses ≥ 0)" smt="(assert (and (>= diagnoses 0)))"
proc jsonFromTopologyAnalysis*(
  analysis: TopologyAnalysis;
  diagnoses: seq[StructuralDiagnosis];
  queueLimit: int;
  bodyLoadCount: int;
  diagnosisDepth: int
): JsonNode =
  ## queueLimit <= 0 means "no limit" — process entire verification queue.
  ## Convention: 0 = unlimited, positive N = cap at N.
  let previewLimit = if queueLimit <= 0: analysis.verificationQueue.len
                     else: min(queueLimit, analysis.verificationQueue.len)
  let previewQueue = analysis.verificationQueue[0 ..< previewLimit]
  jsonFromTopologyQueue(analysis, diagnoses, previewQueue, bodyLoadCount, diagnosisDepth)

## Json From Topology Frontier.
# @axiom-hint: lean="(diagnoses ≥ 0)" smt="(assert (and (>= diagnoses 0)))"
proc jsonFromTopologyFrontier*(
  analysis: TopologyAnalysis;
  diagnoses: seq[StructuralDiagnosis];
  frontier: seq[SorterNodeId];
  bodyLoadCount: int;
  diagnosisDepth: int
): JsonNode =
  ## Like jsonFromTopologyAnalysis but uses a pre-computed verified frontier
  ## instead of slicing the front of the topology queue.
  jsonFromTopologyQueue(analysis, diagnoses, frontier, bodyLoadCount, diagnosisDepth)

## Render Verify Topology Summary Lines.
# @axiom-hint: lean="diagnoses.length > 0 ∧ (result ≥ 0)" smt="(assert (and (> (str.len diagnoses) 0) (>= result 0)))"
proc renderVerifyTopologySummaryLines*(
  analysis: TopologyAnalysis;
  diagnoses: seq[StructuralDiagnosis]
): seq[string] =
  let bottlenecks =
    if analysis.structuralBottlenecks.len == 0:
      "None"
    else:
      nodeIdsToLabels(analysis.state, analysis.structuralBottlenecks).join(", ")
  let repairTargets =
    if analysis.repairPriorityDependencies.len == 0:
      "None"
    else:
      nodeIdsToLabels(analysis.state, analysis.repairPriorityDependencies).join(", ")
  var output = @[
    "Topology Scan: Complete",
    "Structural Bottlenecks: " & bottlenecks,
    "Top Dependencies Needing Repair: " & repairTargets
  ]
  if diagnoses.len > 0:
    let lead = diagnoses[0]
    if lead.diagnosticLabels.len > 0:
      output.add("Top Priority Structural Diagnosis: " & verifyWorkflowLabelFromNodeId(analysis.state, lead.nodeId) & " -> " & lead.diagnosticLabels.join(", "))
  output
const
  ## Directories excluded from topology source discovery.
  excludedTopologyDirs* = [
    "build", "nimcache", ".nimcache", ".nimcache_gate_hook", ".lake", "vendor",
    "logs", "bin", ".git", "node_modules", "semantic_proofs",
    "verifications", "experimental"
  ]

## collect Topology Source Files — git ls-files whitelist with fallback.
let collectTopologySourceFiles* = proc (sourceRoot: string): seq[string] =
  collectGitTrackedSources(sourceRoot)

## normalize Topology Module Path variable.
let normalizeTopologyModulePath* = proc (sourceRoot: string; filePath: string): string =
  normalizePath(relativePath(filePath, sourceRoot))

## load Source Slice variable.
let loadSourceSlice* = proc (filePath: string; startLine: int; endLine: int): string =
  if not fileExists(filePath):
    return ""
  let lines = readFileSafe(filePath).splitLines()
  if lines.len == 0:
    return ""
  let firstLine = max(1, startLine)
  let lastLine = min(lines.len, max(firstLine, endLine))
  var output: string
  for idx in firstLine .. lastLine:
    output.add(lines[idx - 1])
    if idx < lastLine:
      output.add("\n")
  output

# ---------------------------------------------------------------------------
# analyzeTopologySourceRoot (restored from phantom _part5)
# ---------------------------------------------------------------------------

const
  # WP2-a: resolved at use-sites against AXIOM_STATE_DIR when set (subject
  # immutability); raw constants kept for the legacy self-run zero-diff path.
  topologyMerkleCachePath* = ".axiom/cache/topology_merkle.json"
  topologyAnalysisCachePath* = ".axiom/cache/topology_analysis_cache.json"

proc stateAwareCachePath*(raw: string): string =
  ## Routes ".axiom/..." cache paths under AXIOM_STATE_DIR when set.
  block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0 and raw.startsWith(".axiom"): joinPath(sr, raw) else: raw

## Analyze Topology Source Root — incremental Merkle-cached topology scan.
## Uses MerkleQueryEngine for O(1) per-file change detection.
## Falls back to full scan if cache is missing or corrupt.
proc analyzeTopologySourceRoot*(
  sourceRoot: string;
  queueLimit: int  = 200;
  queueLimitExplicit: bool = false;
  diagnosisDepth: int = 0;
  diagnosisDepthExplicit: bool = false
): Result[TopologyCliAnalysisBundle, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not dirExists(sourceRoot):
    return err("source root not found: " & sourceRoot)
  let scanStart = getMonoTime().ticks
  # Initialize Merkle cache — load from disk if available
  let cacheLoad = loadCache(stateAwareCachePath(topologyMerkleCachePath))
  var engine = if cacheLoad.isOk: cacheLoad.get else: MerkleQueryEngine()
  # Run incremental scan — only re-parses changed files
  let incrResult = analyzeTopologySourceRootIncremental(sourceRoot, engine)
  if incrResult.isErr:
    return err(incrResult.error)
  let resultData = incrResult.get
  ## R7 determinism: wall-clock scan time is excluded from the canonical
  ## topology line (byte-identical logs across runs); counts + root are stable.
  logInfo("topology_cli", "topology: " & $resultData.sourceFileCount & " files, " &
    $resultData.changedFileCount & " changed, sourceRoot=" & sourceRoot)
  # Always rebuild analysis from pre-parsed symbols (Merkle cache handles incremental scan)
  let currentMerkleRoot = engine.merkleRoot
  let analysis = buildTopologyAnalysis(resultData.symbols)
  # Save analysis cache keyed on Merkle root
  try:
    let cacheDir = stateAwareCachePath(topologyAnalysisCachePath).parentDir()
    if not dirExists(cacheDir):
      createDir(cacheDir)
    let effectiveDepth =
      if diagnosisDepthExplicit: diagnosisDepth
      else: max(1, min(3, analysis.structuralBottlenecks.len))
    let cacheJson = %*{
      "merkleRoot": currentMerkleRoot,
      "sourceFileCount": resultData.sourceFileCount,
      "totalSourceFunctions": runtimeAxiomRegistry.len,
      "effectiveDiagnosisDepth": effectiveDepth
    }
    writeFile(stateAwareCachePath(topologyAnalysisCachePath), $cacheJson)
  except CatchableError:
    discard  # best-effort cache persistence  # axiom:best-effort(ioboundary catch)
  # Save updated Merkle cache to disk
  let saveRes = saveCache(engine, stateAwareCachePath(topologyMerkleCachePath))
  if saveRes.isErr:
    logError("topology_cli", "saveCache: " & saveRes.error.message)
  let effectiveDepth =
    if diagnosisDepthExplicit: diagnosisDepth
    else: max(1, min(3, analysis.structuralBottlenecks.len))
  let diagnoses: seq[StructuralDiagnosis] = @[]
  ok(TopologyCliAnalysisBundle(
    sourceRoot: sourceRoot,
    sourceFileCount: resultData.sourceFileCount,
    analysis: analysis,
    diagnoses: diagnoses,
    effectiveQueueLimit: queueLimit,
    effectiveDiagnosisDepth: effectiveDepth,
    totalSourceFunctions: int(countKernelFunctions()),
    sourceContentCache: resultData.sourceContentCache
  ))

{.pop.}

