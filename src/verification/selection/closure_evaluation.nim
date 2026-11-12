import core/trusted/layer_declaration
axiomLayer "verification"
{.push raises: [].}

## closure_evaluation — post-wave verification-closure evaluation (I-C / I-F)
##
## Independent judgment path built on the selector-independent oracle
## (request_oracle.computeRequiredRequestsFull) and the closure completeness
## evaluation (request_completeness.evaluateClosureCompleteness).
##
## I-C: ClosureComplete ⇔ DiscoveryFixedPoint ∧ (RequiredRequests ⊆
##      CompletedRequests ∪ JustifiedDisposition) — frontier.empty alone is
##      only an execution-termination signal (never semantic completion).
## I-F: universe-freshness guard — the kernel scope snapshot taken at pipeline
##      start must still match at evaluation time; drift ⇒ fail-closed.
## blocked_by: only when there is a dependency EDGE (A→B) AND failed-node
##      execution evidence (status/hint) — scheduler-level blocks are excluded.

import std/[algorithm, json, sequtils, sets, strutils, tables]
import core/crypto/hash_kernel
import core/sorter/sorter_core
import core/topology/topology_types
import core/topology/symbol_interning
import core/topology/verified_set
import core/proof/proof_integrity
import core/orchestrator/orchestrator_report_types
import core/types/request_id
import core/types/request_derivation_types
import verification/selection/request_oracle
import verification/selection/request_completeness

# ---------------------------------------------------------------------------
# collectClosureState — verified/universe/completed projections
# ---------------------------------------------------------------------------

func collectClosureState*(
  analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
; verifiedSet: VerifiedSet
; internSnapshot: InternPoolSnapshot
; nodeReports: seq[OrchestrationNodeReport]
): tuple[verifiedStr: HashSet[string], universeList: seq[string], completed: seq[RequestId]] =
  ## Project the execution state into the oracle/completeness input domains.
  ## universeList is restricted to kernel-scope members (so completion is judged
  ## against the ADMISSIBLE universe, not the whole symbol table) — this keeps
  ## the oracle required-set and the executed frontier in the same domain.
  result.verifiedStr = initHashSet[string]()
  result.universeList = @[]
  # universeList is the ADMISSIBLE universe. The authority is the kernel scope
  # itself (verification_scope.lock kernel_symbols) rather than the whole state
  # node table — closure is judged against the same admissible scope the
  # frontier/executor uses, not against every symbol the topology scanned.
  if kernelScope.kernelSymbols.len == 0:
    # Degraded mode (no lock): fall back to state nodes as the universe.
    for node in analysis.state.nodes:
      result.universeList.add(sorterNodeIdString(node.id))
  else:
    for sym in kernelScope.kernelSymbols:
      if sym in kernelScope.kernelExemptSymbols:
        continue
      result.universeList.add(sym)
  for node in analysis.state.nodes:
    let nodeIdOpt = nodeIdForSorter(internSnapshot, node.id)
    if nodeIdOpt.isSome and verifiedSet.contains(nodeIdOpt.get()):
      result.verifiedStr.incl(sorterNodeIdString(node.id))
  result.completed = nodeReports.filterIt(
    it.status in [orchestrationVerified, orchestrationNoObligation, orchestrationInductiveValid]
  ).mapIt(RequestId(sorterNodeIdString(it.nodeId)))

# ---------------------------------------------------------------------------
# emitBlockedBy — evidence-gated blocked_by dispositions
# ---------------------------------------------------------------------------

func emitBlockedBy*(
  uncompleted: seq[RequestId]
; analysis: TopologyAnalysis
; nodeReports: seq[OrchestrationNodeReport]
): seq[Disposition] {.raises: [].} =
  ## For each uncompleted required request, emit a blocked_by disposition ONLY
  ## when there is (a) a dependency EDGE from a failed node A to the request unit
  ## (A.dependencyIds contains B) and (b) A's failure execution evidence
  ## (status/hint). Scheduler-level blocks without a failing dependency edge are
  ## NOT blocked_by — they stay uncompleted (fail-closed, never silent-resolved).
  var nodeIndex: Table[string, SorterNode] = initTable[string, SorterNode]()
  for n in analysis.state.nodes:
    nodeIndex[sorterNodeIdString(n.id)] = n
  for req in uncompleted:
    let reqUnitId = string(req)
    var hasDepEdge = false
    var hasFailedNodeEvidence = false
    var blockedByEvidence = ""
    for nr in nodeReports:
      if nr.status notin [orchestrationProofFailed, orchestrationTimedOut,
                          orchestrationBlocked, orchestrationPreSievedUnverifiable,
                          orchestrationNotVerifiable, orchestrationVacuousContradiction,
                          orchestrationSkippedByTheory]:
        continue
      let failedNode = nodeIndex.getOrDefault(sorterNodeIdString(nr.nodeId))
      for depId in failedNode.dependencyIds:
        if sorterNodeIdString(depId) == reqUnitId:
          hasDepEdge = true
          break
      if hasDepEdge:
        let hint = if nr.remediationHint.len > 0: nr.remediationHint else: $nr.status
        blockedByEvidence = "depEdge includes " & reqUnitId &
          "; failedNodeEvidence=" & $nr.status & ":" &
          sorterNodeIdString(nr.nodeId) & ":" & hint
        hasFailedNodeEvidence = true
        break
    if hasDepEdge and hasFailedNodeEvidence:
      result.add(Disposition(
        kind: dkSkip, requestId: req, evidence: blockedByEvidence, basis: "blocked_by"))

# ---------------------------------------------------------------------------
# evaluateUniverseFreshness — I-F guard
# ---------------------------------------------------------------------------

func evaluateUniverseFreshness*(
  kernelScope: KernelScopeInfo
; universeDigestStart: string
; digestEndOverride: string = ""
): tuple[fresh: bool, digestEnd: string] =
  ## Universe-freshness guard: the kernel scope snapshot captured at pipeline
  ## start must still match at closure evaluation. Drift ⇒ stale-required risk
  ## (frontierEmpty ∧ closureComplete could otherwise be a false positive).
  ## §13.1: ``digestEndOverride`` is the I-F disk re-derivation — the caller
  ## re-reads the scope lock from disk (fail-closed) and supplies the digest;
  ## a digest recomputed from the in-memory snapshot can never observe a
  ## mid-run scope change, which is what this guard exists to catch.
  result.digestEnd = if digestEndOverride.len > 0: digestEndOverride
                     else: sha256Hex(kernelScope.kernelSymbols.sorted(cmp).join("|"))
  result.fresh = universeDigestStart == result.digestEnd

# ---------------------------------------------------------------------------
# runClosureEvaluation — orchestrator with additive report fields
# ---------------------------------------------------------------------------

func closureFields*(
  required: seq[RequestId]
; completedCount: int
; uncompleted: seq[RequestId]
; blockedByCount: int
; universeFresh: bool
; frontierEmpty: bool
; wavesExecuted: int
; kernelScopeSize: int
; universeCount: int
): JsonNode {.raises: [].} =
  ## Pure assembly of the closure report fields (I-C / I-F additive record).
  let closureComplete = uncompleted.len == 0 and blockedByCount == 0 and universeFresh
  let uncompletedRequired = uncompleted
  %*{
    "frontierEmpty": frontierEmpty,
    "closureComplete": closureComplete,
    "requiredCount": required.len,
    "completedCount": completedCount,
    "uncompletedRequired": uncompletedRequired.mapIt(string(it)),
    "wavesExecuted": wavesExecuted,
    "kernelScopeSize": kernelScopeSize,
    "universeCount": universeCount}

func evaluateClosure*(
  analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
; verifiedSet: VerifiedSet
; nodeReports: seq[OrchestrationNodeReport]
; frontier: seq[SorterNodeId]
; wavesExecuted: int
; universeDigestStart: string
; internSnapshot: InternPoolSnapshot
; universeDigestEndOverride: string = ""
): JsonNode {.raises: [].} =
  ## Post-wave closure evaluation: independent-oracle completeness (I-C),
  ## evidence-gated blocked_by dispositions, and the additive closure fields.
  ## §13.1: ``universeDigestEndOverride`` carries the disk-re-derived scope
  ## digest (I-F); empty keeps the in-memory recomputation.
  let state = collectClosureState(analysis, kernelScope, verifiedSet, internSnapshot, nodeReports)
  let requiredRequests = computeRequiredRequestsFull(
    state.universeList, analysis, kernelScope, state.verifiedStr)
  let closureResult = evaluateClosureCompleteness(
    requiredRequests, state.completed, @[], nodeReports)
  let blockedByDispositions = emitBlockedBy(closureResult.uncompleted, analysis, nodeReports)
  let freshness = evaluateUniverseFreshness(kernelScope, universeDigestStart,
    universeDigestEndOverride)
  let uncompletedRequired =
    if not freshness.fresh: requiredRequests else: closureResult.uncompleted
  closureFields(
    requiredRequests, state.completed.len, uncompletedRequired,
    blockedByDispositions.len, freshness.fresh, frontier.len == 0, wavesExecuted,
    kernelScope.kernelSymbols.len, state.universeList.len)

{.pop.}