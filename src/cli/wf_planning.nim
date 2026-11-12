import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Proof planning and request building.
## Extracted from ax_workflow_cli.nim — SMT formula generation, work item selection.

import std/algorithm
import std/options
import std/os
import std/strformat
import std/strutils
import std/tables

import core/orchestrator/orchestrator_request_types
import core/sorter/sorter_core
import core/topology/topology_engine
import core/results
import core/utils/text_utils
import core/encoding/smt_hints
import verification/cli_bridge

import cli/topology_cli
import cli/selection_state
import core/utils/file_utils

type
  TopologySelectionProgressSink* = proc(
    processed: int;
    total: int;
    currentLabel: string
  ) {.closure, raises: [CatchableError].}

## Build Ax Proof Plan.
# @axiom-hint: lean="workItems.size ≥ 0" smt="(assert (and (>= (seq.len workItems) 0)))"
# @axiom-hint: lean="result = workItems ∧ (result ≥ 0)" smt="(assert (and (= result workItems) (>= result 0)))"
func buildAxProofPlan*(workItems: seq[SorterWorkItem]): seq[SorterWorkItem] =
  result = workItems
  result.sort(proc(left: SorterWorkItem; right: SorterWorkItem): int =
    if left.dependencyDepth != right.dependencyDepth:
      return cmp(left.dependencyDepth, right.dependencyDepth)
    cmp(sorterNodeIdString(left.nodeId), sorterNodeIdString(right.nodeId))
  )

## Build Sorter Work Item Index Table.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func buildSorterWorkItemIndexTable*(plan: SorterPlan): Table[string, int] =
  for idx, item in plan.workItems:
    result[sorterNodeIdString(item.nodeId)] = idx

## Find Sorter Work Item.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="workItemIdx ≥ 0" smt="(assert (and (>= workItemIdx 0)))"
func findSorterWorkItem*(
  plan: SorterPlan;
  workItemIndexTable: Table[string, int];
  nodeId: SorterNodeId
): Option[SorterWorkItem] =
  let workItemIdx = workItemIndexTable.getOrDefault(sorterNodeIdString(nodeId), -1)
  if workItemIdx >= 0:
    return some(plan.workItems[workItemIdx])
  none(SorterWorkItem)

## Source Has Counter Example Marker.
# @axiom-hint: lean="sourceCode.length ≥ 0" smt="(assert (and (>= (str.len sourceCode) 0)))"
func sourceHasCounterExampleMarker*(sourceCode: string): bool =
  let tokens = tokenizeLowered(sourceCode)
  "throw" in tokens or "panic" in tokens or "raise" in tokens or
    "fatal" in tokens or "abort" in tokens or "assert" in tokens or
    "unreachable" in tokens

## Build Ax Proof Expected Formula.
# @axiom-hint: lean="nodeLabel.length ≥ 0 ∧ dependencyDepth ≥ -9223372036854775808 ∧ dependencyDepth ≤ 9223372036854775807 ∧ impactIndex ≥ -9223372036854775808 ∧ impactIndex ≤ 9223372036854775807 ∧ external_io_isolated" smt="(assert (and (>= (str.len nodeLabel) 0) (and (>= dependencyDepth -9223372036854775808) (<= dependencyDepth 9223372036854775807)) (and (>= impactIndex -9223372036854775808) (<= impactIndex 9223372036854775807)) external_io_isolated))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func buildAxProofExpectedFormula*(nodeLabel: string; dependencyDepth: int; impactIndex: int): string =
  var customConstraint = ""

  let symbolName = sanitizeAxiomToken(nodeLabel)
  result = buildAxProofSmtAssertions(nodeLabel, symbolName, dependencyDepth, impactIndex, customConstraint)
  if nodeLabel.endsWith("::getStr"):
    result &= "\n" & fmt"(assert (>= {symbolName}_json_len 0))"
    result &= "\n" & fmt"(assert (>= {symbolName}_key_len 0))"
    result &= "\n" & fmt"(assert (>= {symbolName}_value_len 2))"

## build Ax Proof Requests variable.
let buildAxProofRequests* = proc (
  bundle: TopologyCliAnalysisBundle;
  selectedItems: seq[SorterWorkItem]
): seq[OrchestrationProofRequest] =
  for item in selectedItems:
    let metricIdx = findTopologyMetricIndex(bundle.analysis, item.nodeId)
    let symbolIdx = findTopologySymbolIndex(bundle.analysis, item.nodeId)
    if metricIdx < 0 or symbolIdx < 0:
      continue
    let metric = bundle.analysis.metrics[metricIdx]
    let symbol = bundle.analysis.symbols[symbolIdx]
    let filePath = joinPath(bundle.sourceRoot, symbol.modulePath.replace('/', DirSep))
    let fileContent = readFileSafe(filePath)
    let extractRes = extractFunctionBody(fileContent, symbol.functionName)
    let sourceSlice = if extractRes.isOk and extractRes.value.found: extractRes.value.body else: loadSourceSlice(filePath, symbol.bodyStartLine, symbol.bodyEndLine)
    let stateValue = max(16, metric.lineSpan * 8 + metric.couplingScore + metric.centralityScore + 8)
    let nominalDelta = max(1, metric.branchCount + metric.nestingDepth + metric.dependencyCount + item.dependencyDepth + 1)
    let inputDelta =
      if sourceHasCounterExampleMarker(sourceSlice):
        stateValue + 1
      else:
        min(stateValue, nominalDelta)
    result.add(initOrchestrationProofRequest(
      item.nodeId,
      sourceSlice,
      stateValue,
      inputDelta,
      buildAxProofExpectedFormula(
        verifyWorkflowLabelFromNodeId(bundle.analysis.state, item.nodeId),
        item.dependencyDepth,
        topologyImpactIndex(metric)
      )
    ))

## select Ax Proof Work Items variable.
let selectAxProofWorkItems* = proc (
  bundle: TopologyCliAnalysisBundle;
  plan: SorterPlan;
  limit: int;
  progressSink: TopologySelectionProgressSink = nil
): seq[SorterWorkItem] =
  let selectionLimit = min(max(1, limit), bundle.analysis.verificationQueue.len)
  let progressTotal = max(1, selectionLimit)
  let workItemIndexTable = buildSorterWorkItemIndexTable(plan)
  for idx in 0 ..< selectionLimit:
    let workItem = findSorterWorkItem(plan, workItemIndexTable, bundle.analysis.verificationQueue[idx])
    if workItem.isSome():
      result.add(workItem.get())
    if not isNil(progressSink):
      progressSink(
        idx + 1,
        progressTotal,
        sorterNodeIdString(bundle.analysis.verificationQueue[idx])
      )
  result = buildAxProofPlan(result)

## select Ax Proof Work Items Ranked variable.
## Deterministic ranking-based selection: Score(s) = 1 / (Count(s) + 1).
## Nodes selected fewer times get higher priority, guaranteeing diversity.
let selectAxProofWorkItemsRanked* = proc (
  bundle: TopologyCliAnalysisBundle;
  plan: SorterPlan;
  limit: int;
  selectionState: var NodeSelectionState;
  progressSink: TopologySelectionProgressSink = nil
): seq[SorterWorkItem] =
  let selectionLimit = min(max(1, limit), bundle.analysis.verificationQueue.len)
  let workItemIndexTable = buildSorterWorkItemIndexTable(plan)

  # Build scored candidate list
  type ScoredCandidate = object
    nodeId: SorterNodeId
    score: float
    depth: int
  var candidates: seq[ScoredCandidate] = @[]
  for queueItem in bundle.analysis.verificationQueue:
    let nodeIdStr = sorterNodeIdString(queueItem)
    let count = selectionState.counts.getOrDefault(nodeIdStr, 0)
    let score = computeScore(count)
    let workItem = findSorterWorkItem(plan, workItemIndexTable, queueItem)
    let depth = if workItem.isSome: workItem.get().dependencyDepth else: 0
    candidates.add(ScoredCandidate(nodeId: queueItem, score: score, depth: depth))

  # Sort: primary=score desc, secondary=depth asc, tertiary=nodeId string asc
  candidates.sort(proc(a, b: ScoredCandidate): int =
    let scoreCmp = cmp(b.score, a.score)
    if scoreCmp != 0: return scoreCmp
    let depthCmp = cmp(a.depth, b.depth)
    if depthCmp != 0: return depthCmp
    cmp(sorterNodeIdString(a.nodeId), sorterNodeIdString(b.nodeId))
  )

  # Select top-K
  for i in 0 ..< selectionLimit:
    let workItem = findSorterWorkItem(plan, workItemIndexTable, candidates[i].nodeId)
    if workItem.isSome():
      result.add(workItem.get())
    if not isNil(progressSink):
      progressSink(i + 1, selectionLimit, sorterNodeIdString(candidates[i].nodeId))

  # Update selection counts
  var selectedIds: seq[string] = @[]
  for item in result:
    selectedIds.add(sorterNodeIdString(item.nodeId))
  incrementCount(selectionState, selectedIds)

  result = buildAxProofPlan(result)
{.pop.}

