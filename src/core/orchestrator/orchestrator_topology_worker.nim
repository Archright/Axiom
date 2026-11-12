import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/utils/constants
import core/diagnostics/diagnostics_engine
import core/orchestrator/cegar_types
import core/orchestrator/cfg_builder
import core/orchestrator/orchestrator_topology_depth
import core/orchestrator/orchestrator_types
import core/orchestrator/protocols
import core/sorter/sorter_core
import core/symbolic/symbolic_types_expr
import core/utils/text_utils
import core/vault/vault_manager_spec
## Sort Work Items By Depth.
  ## axiom-smt: (assert (and (>= (seq.len workItems) 0) (< (str.len result) 2) (not (= aImpact bImpact)) (= result workItems) result (- bImpact aImpact) (=> (< (str.len result) 2) (= result result)) (=> (not (= aImpact bImpact)) (= result (- bImpact aImpact))) (>= result 0)))
  ## axiom-lean: workItems.size ≥ 0 ∧ result.length < 2 ∧ aImpact ≠ bImpact ∧ result = workItems ∧ result ∧ bImpact - aImpact ∧ result.length < 2 → result = result ∧ aImpact ≠ bImpact → result = bImpact - aImpact ∧ (result ≥ 0)
func clampTimeoutMs(timeoutMs: int): int {.axiom, axiomImpl, used.} =
  if timeoutMs < minDynamicTimeoutMs: minDynamicTimeoutMs
  elif timeoutMs > maxDynamicTimeoutMs: maxDynamicTimeoutMs
  else: timeoutMs

## Pure integer core of the dynamic timeout computation.
## All-int closed form, no string analysis, QF_BV-friendly.
func calcDynamicTimeoutCore(
  requestTimeoutMs: int;
  dependencyDepth: int;
  impactedNodeCount: int;
  complexityWeight: int
): int {.axiom,
  axiomImpl,
  axiom: [pre: (dependencyDepth >= 0 and impactedNodeCount >= 0 and complexityWeight >= 0),
          post: (result >= 5000 and result <= 120000)]
.} =
  let rawTimeoutMs =
    if requestTimeoutMs > 0:
      requestTimeoutMs
    else:
      minDynamicTimeoutMs +
      dependencyDepth * 10_000 +
      min(impactedNodeCount, 6) * 6_000 +
      min(complexityWeight * 500, 57_000)
  if rawTimeoutMs < minDynamicTimeoutMs: minDynamicTimeoutMs
  elif rawTimeoutMs > maxDynamicTimeoutMs: maxDynamicTimeoutMs
  else: rawTimeoutMs

## Calc Dynamic Timeout.
func calcDynamicTimeout*(
  request: OrchestrationProofRequest;
  dependencyDepth: int;
  impactedNodeCount: int
): int =
  ## axiom-smt: (assert (and (and (>= dependencyDepth -9223372036854775808) (<= dependencyDepth 9223372036854775807)) (and (>= impactedNodeCount -9223372036854775808) (<= impactedNodeCount 9223372036854775807))))
  ## axiom-lean: dependencyDepth ≥ -9223372036854775808 ∧ dependencyDepth ≤ 9223372036854775807 ∧ impactedNodeCount ≥ -9223372036854775808 ∧ impactedNodeCount ≤ 9223372036854775807
  if request.timeoutMs > 0:
    return calcDynamicTimeoutCore(
      request.timeoutMs, dependencyDepth, impactedNodeCount, 0
    )
  let diagnosis = buildTimeoutDiagnosis(
    request.nodeId,
    request.sourceCode,
    request.expectedSmtlib2,
    dependencyDepth,
    impactedNodeCount,
    defaultAxiomProofTimeoutMs
  )
  result = calcDynamicTimeoutCore(
    request.timeoutMs,
    dependencyDepth,
    impactedNodeCount,
    diagnosis.complexityWeight
  )
## Resolve Proof Fingerprint.
  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func resolveProofFingerprint*(request: OrchestrationProofRequest): string {.axiom, axiomImpl.} =
  if request.currentFingerprint.len > 0:
    return request.currentFingerprint
  let payload = compactWhitespace(request.sourceCode)
  result = computeSourceFingerprint(payload)

## Timeout Diagnosis For Node.
func timeoutDiagnosisForNode*(
  state: SorterState;
  request: OrchestrationProofRequest;
  nodeId: SorterNodeId;
  dependencyDepth: int;
  timeoutMs: int
): TimeoutDiagnosis {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (and (>= dependencyDepth -9223372036854775808) (<= dependencyDepth 9223372036854775807)) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807))))
  ## axiom-lean: dependencyDepth ≥ -9223372036854775808 ∧ dependencyDepth ≤ 9223372036854775807 ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807
  let impactedNodeCount = collectImpactedBranchNodes(state, nodeId).len
  result = buildTimeoutDiagnosis(
    nodeId,
    request.sourceCode,
    request.expectedSmtlib2,
    dependencyDepth,
    impactedNodeCount,
    timeoutMs
  )

{.pop.}  # pop raises: [] — applyCegarAbstraction needs raises: [CatchableError]
## Apply CEGAR Abstraction.
## CEGAR behavior injected via callback — Domain은 cegar_engine을 import하지 않음.
proc applyCegarAbstraction*(
  nodeId: SorterNodeId;
  cfg: ControlFlowGraph;
  headerId: int;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].};
  elapsedMs: int64;
  timeoutMs: int;
  cegarRun: CegarCallback;
  encodeSmtlib2: proc(invariants: seq[SymSExpr]): string {.raises: [], gcsafe.}
): tuple[status: OrchestrationNodeStatus, smtlib2: string, evidenceLog: string, isAbstracted: bool] {.raises: [CatchableError].} =
  let remainingMs = max(int64(timeoutMs) - elapsedMs, 1000'i64)
  let cegarResult = cegarRun(cfg, headerId, z3Check, remainingMs)
  case cegarResult.verdict
  of cegarProven:
    let smtlib2 = encodeSmtlib2(cegarResult.provedInvariants)
    let evidence = "{\"event\":\"CegarProven\",\"nodeId\":\"" & sorterNodeIdString(nodeId) &
      "\",\"iterations\":" & $cegarResult.iterations &
      ",\"provedCount\":" & $cegarResult.provedInvariants.len &
      ",\"elapsedMs\":" & $cegarResult.elapsedMs & "}"
    return (orchestrationVerified, smtlib2, evidence, true)
  of cegarCounterexample:
    let evidence = "{\"event\":\"CegarCounterexample\",\"nodeId\":\"" & sorterNodeIdString(nodeId) &
      "\",\"iterations\":" & $cegarResult.iterations & "}"
    return (orchestrationProofFailed, "", evidence, false)
  of cegarMaxIterations:
    let evidence = "{\"event\":\"CegarMaxIterations\",\"nodeId\":\"" & sorterNodeIdString(nodeId) &
      "\",\"iterations\":" & $cegarResult.iterations & "}"
    return (orchestrationTimedOut, "", evidence, false)
  of cegarBudgetExceeded:
    let evidence = "{\"event\":\"CegarBudgetExceeded\",\"nodeId\":\"" & sorterNodeIdString(nodeId) &
      "\",\"elapsedMs\":" & $cegarResult.elapsedMs & "}"
    return (orchestrationTimedOut, "", evidence, false)


## Block Branch.
## axiom-smt: (assert (and (>= depth 0) (>= impacted 0)))
## axiom-lean: depth >= 0 ∧ (impacted ≥ 0)
func blockBranch*(
  report: var OrchestrationReport;
  state: SorterState;
  nodeId: SorterNodeId
) {.axiom, axiomImpl.} =
  addUniqueNodeId(report.reproofNodes, nodeId)
  let impacted = collectImpactedBranchNodes(state, nodeId)
  for impactedNodeId in impacted:
    addUniqueNodeId(report.blockedNodes, impactedNodeId)
    addUniqueNodeId(report.reproofNodes, impactedNodeId)

## Register Timeout Impact.
## axiom-smt: (assert (and (>= depth 0) (>= impacted 0)))
## axiom-lean: depth >= 0 ∧ (impacted ≥ 0)
func registerTimeoutImpact*(
  report: var OrchestrationReport;
  state: SorterState;
  nodeId: SorterNodeId
) {.axiom, axiomImpl.} =
  addUniqueNodeId(report.timeoutNodes, nodeId)
  addUniqueNodeId(report.timeoutImpactNodes, nodeId)
  let impacted = collectImpactedBranchNodes(state, nodeId)
  for impactedNodeId in impacted:
    addUniqueNodeId(report.timeoutImpactNodes, impactedNodeId)
## Total Plan Depths.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"

