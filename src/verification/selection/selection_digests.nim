import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Selection digests — moved from core/types/ leaf modules.
##
## These functions are verification-layer (may import core/*,
## infrastructure/*, engine/*). They are consumed by the selection
## engine, builders, harness, report, and tests.

import std/[algorithm, json, sequtils, strutils]
import infrastructure/cas_index
import core/topology/topology_types
import core/sorter/sorter_core_index_base
import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/types/request_id
import core/types/result_identity
import verification/run_identity

# ---------------------------------------------------------------------------
# Conversion: TopologyUnresolvedEdge → GraphUnresolvedEdge
# ---------------------------------------------------------------------------

func toGraphUnresolvedEdge*(e: TopologyUnresolvedEdge): GraphUnresolvedEdge {.raises: [].} =
  GraphUnresolvedEdge(
    fromNodeId: sorterNodeIdString(e.fromNodeId),
    targetName: e.targetName,
    modulePath: e.modulePath,
    resolutionKind: $e.resolutionKind)

# ---------------------------------------------------------------------------
# Digest computation — moved from core/types/canonical_change_set.nim
# ---------------------------------------------------------------------------

func computeChangeSetDigest*(cs: CanonicalChangeSet): string {.raises: [].} =
  ## Deterministic digest of the CanonicalChangeSet.
  ## Uses combineHashes with \x03 domain separators over canonical parts.
  let sortedMergeBase = cs.mergeBase.sorted(cmp).join("|")
  combineHashes([
    cs.baseCommit,
    cs.headCommit,
    sortedMergeBase,
    cs.canonicalDiffDigest,
    flagsToString(cs.diffInterpretationPolicy.flags)
  ])

# ---------------------------------------------------------------------------
# Digest computation — moved from core/types/graph_artifact.nim
# ---------------------------------------------------------------------------

func resolvePolicyDigest*(policy: GraphInterpretationPolicy): string {.raises: [].} =
  ## Deterministic digest of the interpretation policy itself.
  let sortedSemantics = policy.edgeSemantics.mapIt($it).sorted(cmp).join("|")
  combineHashes([
    policy.extractionMode,
    sortedSemantics,
    policy.builderVersion,
    $(policy.unresolvedRetention)
  ])

func computeGraphDigest*(ga: GraphArtifact): string {.raises: [].} =
  ## Deterministic digest of the canonical GraphArtifact.
  ## Uses combineHashes over canonical parts.
  ## Contract sentence 2: unresolvedEdges is PART of the digest.
  let sortedEdges = ga.unresolvedEdges.mapIt(
    it.fromNodeId & "|" & it.targetName & "|" & it.modulePath & "|" & $it.resolutionKind
  ).sorted(cmp)
  combineHashes([
    ga.structureDigest,
    ga.constructionInputsDigest,
    ga.interpretationPolicyDigest,
    sortedEdges.join(";"),
    ga.builderVersion
  ])

# ---------------------------------------------------------------------------
# Digest computation — moved from core/types/selection_derivation.nim
# ---------------------------------------------------------------------------

func computeSelectionDerivationDigest*(sd: SelectionDerivation): string {.raises: [].} =
  ## Deterministic digest of the SelectionDerivation.
  combineHashes([$sd.toCanonicalJson])

func verifySelectionWitness*(sd: SelectionDerivation): bool {.raises: [].} =
  ## Recompute the witness digest and compare with the stored value.
  ## Returns false on any mismatch (fail-closed).
  let computed = computeSelectionDerivationDigest(sd)
  computed == sd.witnessDigest

# ---------------------------------------------------------------------------
# Composition — moved from core/types/execution_plan.nim
# ---------------------------------------------------------------------------

func composeWithBaseRun*(base: BaseRunIdentity; plan: PlanIdentity): string {.raises: [].} =
  ## Combine BaseRunIdentity's semantic identity with PlanIdentity into
  ## a single combined digest. Does NOT modify BaseRunIdentity.
  combineHashes([
    base.semanticIdentity.identityDigest,
    plan.selectionDigest,
    plan.changeSetDigest,
    plan.graphDigest,
    plan.universeDigest,
    plan.policyDigest,
    plan.planDigest
  ])

# ---------------------------------------------------------------------------
# Digest computation — moved from core/types/result_identity.nim
# ---------------------------------------------------------------------------

func computeResultDigest*(ur: UnitResult): string {.raises: [].} =
  combineHashes([
    ur.unitId,
    $(ur.proofStatus),
    ur.failureClassification,
    ur.vacuityClassification,
    ur.certificateIdentityDigest
  ])

# ---------------------------------------------------------------------------
# ExecutionPlan construction — moved from core/types/execution_plan.nim
# ---------------------------------------------------------------------------

func makeExecutionPlan*(selDeriv: SelectionDerivation; mode: UniverseMode;
                        selectedIds: seq[string];
                        requests: seq[RequestId] = @[]): ExecutionPlan {.raises: [].} =
  ## Construct an ExecutionPlan from a SelectionDerivation.
  ## The planDigest is a canonical digest of the plan identity.
  let inputs = selDeriv.inputDigests
  let planId = PlanIdentity(
    selectionDigest: computeSelectionDerivationDigest(selDeriv),
    changeSetDigest: inputs.changeSetDigest,
    graphDigest: inputs.graphDigest,
    universeDigest: inputs.universeDigest,
    policyDigest: inputs.policyDigest,
    planDigest: ""  # placeholder, computed below
  )
  let sortedSelectedIds = selectedIds.sorted(cmp).join("|")
  let sortedRequests = requests.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b))).mapIt(it.toString()).join("|")
  let planDigest = combineHashes([
    planId.selectionDigest,
    planId.changeSetDigest,
    planId.graphDigest,
    planId.universeDigest,
    planId.policyDigest,
    $mode,
    sortedSelectedIds,
    sortedRequests
  ])
  let updatedPlanId = PlanIdentity(
    selectionDigest: planId.selectionDigest,
    changeSetDigest: planId.changeSetDigest,
    graphDigest: planId.graphDigest,
    universeDigest: planId.universeDigest,
    policyDigest: planId.policyDigest,
    planDigest: planDigest
  )
  ExecutionPlan(
    mode: mode,
    selectedUnitIds: selectedIds.sorted(cmp),
    planIdentity: updatedPlanId,
    planDigest: planDigest,
    requests: requests.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b)))
  )

# ---------------------------------------------------------------------------
# PlanDigest verification — new
# ---------------------------------------------------------------------------

func computePlanDigest*(plan: ExecutionPlan): string {.raises: [].} =
  ## Canonical computation of planDigest from ExecutionPlan content.
  ## This is the same algorithm used by makeExecutionPlan, so verifyPlanDigest
  ## will pass for genuine plans and fail-closed for tampered plans.
  let planId = plan.planIdentity
  let sortedSelectedIds = plan.selectedUnitIds.sorted(cmp).join("|")
  let sortedRequests = plan.requests.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b))).mapIt(it.toString()).join("|")
  combineHashes([
    planId.selectionDigest,
    planId.changeSetDigest,
    planId.graphDigest,
    planId.universeDigest,
    planId.policyDigest,
    $plan.mode,
    sortedSelectedIds,
    sortedRequests
  ])

func verifyPlanDigest*(plan: ExecutionPlan): bool {.raises: [].} =
  ## Fail-closed verification of planDigest.
  ## Recomputes planDigest from the plan's canonical content and compares
  ## against the stored planDigest. Returns false on any mismatch.
  computePlanDigest(plan) == plan.planDigest

# ---------------------------------------------------------------------------
# Run-level digests — Step 2
# ---------------------------------------------------------------------------

func runInputSnapshotDigest*(baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest: string): string {.raises: [].} =
  ## Deterministic digest of the run input snapshot.
  ## Covers pre-execution inputs only (selection_digests.nim computePlanDigest
  ## covers planDigest; ExecutionPlan.planDigest covers pre-execution inputs).
  combineHashes([baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest])

func runResultDigest*(runInputSnapshotDigest, requestResultsDigest, unitResultsDigest: string): string {.raises: [].} =
  ## Deterministic digest of the run result.
  ## Composes the run input snapshot with aggregated result digests.
  combineHashes([runInputSnapshotDigest, requestResultsDigest, unitResultsDigest])

{.pop.}
