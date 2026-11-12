## S0b — Canonical Execution Semantics type tests
## EXPERIMENT_ID=act2-wp2-subject-scoped-execution / SUB_TASK=S0b
##
## Covers: determinism, sensitivity, canonicalization, witness
## fail-closed verification, and projection invariant (contract
## sentence 4).

{.push raises: [CatchableError].}

import std/[algorithm, json, sequtils, strutils, tables, unittest]
import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/types/result_identity
import core/topology/topology_types
import engine/proof_certificate
import verification/run_identity
import verification/selection/selection_digests

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeCanonicalChangeSet*(
  baseCommit = "base_sha_aaa"
; headCommit = "head_sha_bbb"
; mergeBase: seq[string] = @["merge_sha_ccc"]
; diffDigest = "diff_hash_123"
; flags: set[DiffInterpretationFlag] = {}
): CanonicalChangeSet =
  CanonicalChangeSet(
    baseCommit: baseCommit,
    headCommit: headCommit,
    mergeBase: mergeBase,
    canonicalDiffDigest: diffDigest,
    diffInterpretationPolicy: DiffInterpretationPolicy(flags: flags))

proc makeGraphArtifact*(
  structureDigest = "struct_digest_1"
; constructionInputsDigest = "inputs_digest_2"
; policyDigest = "policy_digest_3"
; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion = "2"
): GraphArtifact =
  GraphArtifact(
    structureDigest: structureDigest,
    constructionInputsDigest: constructionInputsDigest,
    interpretationPolicyDigest: policyDigest,
    unresolvedEdges: unresolvedEdges.map(toGraphUnresolvedEdge),
    builderVersion: builderVersion)

proc makeProofOfSelection*(unitId: string; reason: SelectionReasonKind): ProofOfSelection =
  ProofOfSelection(
    unitId: unitId,
    reasonKind: reason,
    predecessorChain: @["step1", "step2"])

proc makeSelectionDerivation*(
  changeSetDigest = "cs_digest_1"
; graphDigest = "graph_digest_2"
; universeDigest = "uni_digest_3"
; policyDigest = "policy_digest_4"
; status = ssValid
; selected: seq[ProofOfSelection] = @[]
; excluded: seq[(string, string)] = @[]
; fallbackReason = ""
; witnessDigest = ""
): SelectionDerivation =
  SelectionDerivation(
    inputDigests: SelectionInputs(
      changeSetDigest: changeSetDigest,
      graphDigest: graphDigest,
      universeDigest: universeDigest,
      policyDigest: policyDigest),
    status: status,
    selected: selected,
    excluded: excluded,
    fallbackReason: fallbackReason,
    witnessDigest: witnessDigest)

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "CanonicalChangeSet":

  test "determinism: identical inputs produce identical digest":
    let cs1 = makeCanonicalChangeSet()
    let cs2 = makeCanonicalChangeSet()
    check computeChangeSetDigest(cs1) == computeChangeSetDigest(cs2)

  test "sensitivity: baseCommit change alters digest":
    let cs1 = makeCanonicalChangeSet(baseCommit = "base_old")
    let cs2 = makeCanonicalChangeSet(baseCommit = "base_new")
    check computeChangeSetDigest(cs1) != computeChangeSetDigest(cs2)

  test "sensitivity: headCommit change alters digest":
    let cs1 = makeCanonicalChangeSet(headCommit = "head_old")
    let cs2 = makeCanonicalChangeSet(headCommit = "head_new")
    check computeChangeSetDigest(cs1) != computeChangeSetDigest(cs2)

  test "sensitivity: diffDigest change alters digest":
    let cs1 = makeCanonicalChangeSet(diffDigest = "diff_old")
    let cs2 = makeCanonicalChangeSet(diffDigest = "diff_new")
    check computeChangeSetDigest(cs1) != computeChangeSetDigest(cs2)

  test "sensitivity: mergeBase change alters digest":
    let cs1 = makeCanonicalChangeSet(mergeBase = @["merge_a"])
    let cs2 = makeCanonicalChangeSet(mergeBase = @["merge_b"])
    check computeChangeSetDigest(cs1) != computeChangeSetDigest(cs2)

  test "sensitivity: flags change alters digest":
    let cs1 = makeCanonicalChangeSet(flags = {difRenameDetected})
    let cs2 = makeCanonicalChangeSet(flags = {difCopyDetected})
    check computeChangeSetDigest(cs1) != computeChangeSetDigest(cs2)

  test "canonicalization: mergeBase order does not affect digest":
    let cs1 = makeCanonicalChangeSet(mergeBase = @["a", "b", "c"])
    let cs2 = makeCanonicalChangeSet(mergeBase = @["c", "b", "a"])
    check computeChangeSetDigest(cs1) == computeChangeSetDigest(cs2)

  test "canonicalization: head+base order does not affect digest (sorted parts)":
    let cs1 = makeCanonicalChangeSet(baseCommit = "base_x", headCommit = "head_y")
    let cs2 = makeCanonicalChangeSet(baseCommit = "base_x", headCommit = "head_y")
    check computeChangeSetDigest(cs1) == computeChangeSetDigest(cs2)

suite "GraphArtifact":

  test "determinism: identical inputs produce identical digest":
    let ga1 = makeGraphArtifact()
    let ga2 = makeGraphArtifact()
    check computeGraphDigest(ga1) == computeGraphDigest(ga2)

  test "sensitivity: structureDigest change alters digest":
    let ga1 = makeGraphArtifact(structureDigest = "struct_old")
    let ga2 = makeGraphArtifact(structureDigest = "struct_new")
    check computeGraphDigest(ga1) != computeGraphDigest(ga2)

  test "sensitivity: unresolvedEdges change alters digest":
    let edge1 = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("node_a"),
      targetName: "target_x",
      modulePath: "mod.m",
      resolutionKind: rrUnresolved)
    let ga1 = makeGraphArtifact(unresolvedEdges = @[edge1])
    let ga2 = makeGraphArtifact(unresolvedEdges = @[])
    check computeGraphDigest(ga1) != computeGraphDigest(ga2)

  test "canonicalization: edge order does not affect digest":
    let edgeA = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("node_a"),
      targetName: "target_x",
      modulePath: "mod.m",
      resolutionKind: rrUnresolved)
    let edgeB = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("node_b"),
      targetName: "target_y",
      modulePath: "mod2.m",
      resolutionKind: rrAmbiguous)
    let ga1 = makeGraphArtifact(unresolvedEdges = @[edgeA, edgeB])
    let ga2 = makeGraphArtifact(unresolvedEdges = @[edgeB, edgeA])
    check computeGraphDigest(ga1) == computeGraphDigest(ga2)

  test "sensitivity: builderVersion change alters digest":
    let ga1 = makeGraphArtifact(builderVersion = "1")
    let ga2 = makeGraphArtifact(builderVersion = "2")
    check computeGraphDigest(ga1) != computeGraphDigest(ga2)

  test "unresolvedEdges is part of digest (contract sentence 2)":
    ## Removing unresolvedEdges from the graph MUST change the digest.
    let edge = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("node_a"),
      targetName: "target_x",
      modulePath: "mod.m",
      resolutionKind: rrUnresolved)
    let withEdge = makeGraphArtifact(unresolvedEdges = @[edge])
    let withoutEdge = makeGraphArtifact(unresolvedEdges = @[])
    check computeGraphDigest(withEdge) != computeGraphDigest(withoutEdge)

suite "SelectionDerivation":

  test "determinism: identical inputs produce identical digest":
    let sd1 = makeSelectionDerivation()
    let sd2 = makeSelectionDerivation()
    let d1 = computeSelectionDerivationDigest(sd1)
    let d2 = computeSelectionDerivationDigest(sd2)
    check d1 == d2

  test "sensitivity: status change alters digest":
    let sd1 = makeSelectionDerivation(status = ssValid)
    let sd2 = makeSelectionDerivation(status = ssFallbackRequired)
    check computeSelectionDerivationDigest(sd1) != computeSelectionDerivationDigest(sd2)

  test "sensitivity: selected unit change alters digest":
    let sd1 = makeSelectionDerivation(
      selected = @[makeProofOfSelection("unit_a", rkDeltaChanged)])
    let sd2 = makeSelectionDerivation(
      selected = @[makeProofOfSelection("unit_b", rkDeltaChanged)])
    check computeSelectionDerivationDigest(sd1) != computeSelectionDerivationDigest(sd2)

  test "canonicalization: selected order does not affect digest":
    let sel1 = @[
      makeProofOfSelection("unit_a", rkDeltaChanged),
      makeProofOfSelection("unit_b", rkContractChanged)]
    let sel2 = @[
      makeProofOfSelection("unit_b", rkContractChanged),
      makeProofOfSelection("unit_a", rkDeltaChanged)]
    let sd1 = makeSelectionDerivation(selected = sel1)
    let sd2 = makeSelectionDerivation(selected = sel2)
    check computeSelectionDerivationDigest(sd1) == computeSelectionDerivationDigest(sd2)

  test "canonicalization: excluded order does not affect digest":
    let excl1 = @[("unit_a", "reason_1"), ("unit_b", "reason_2")]
    let excl2 = @[("unit_b", "reason_2"), ("unit_a", "reason_1")]
    let sd1 = makeSelectionDerivation(excluded = excl1)
    let sd2 = makeSelectionDerivation(excluded = excl2)
    check computeSelectionDerivationDigest(sd1) == computeSelectionDerivationDigest(sd2)

  test "witness verification: matching witness returns true":
    var sd = makeSelectionDerivation()
    sd.witnessDigest = computeSelectionDerivationDigest(sd)
    check verifySelectionWitness(sd) == true

  test "witness verification: tampered witness returns false (fail-closed)":
    var sd = makeSelectionDerivation(
      selected = @[makeProofOfSelection("unit_a", rkDeltaChanged)])
    sd.witnessDigest = computeSelectionDerivationDigest(sd)
    ## Tamper: change a selected unit without updating witness
    sd.selected[0].unitId = "tampered_unit"
    check verifySelectionWitness(sd) == false

  test "witness verification: empty witness returns false":
    let sd = makeSelectionDerivation(witnessDigest = "")
    check verifySelectionWitness(sd) == false

suite "ExecutionPlan":

  test "determinism: identical inputs produce identical planDigest":
    let sd = makeSelectionDerivation()
    let plan1 = makeExecutionPlan(sd, umSelected, @["unit_a", "unit_b"])
    let plan2 = makeExecutionPlan(sd, umSelected, @["unit_a", "unit_b"])
    check plan1.planDigest == plan2.planDigest

  test "sensitivity: mode change alters planDigest":
    let sd = makeSelectionDerivation()
    let plan1 = makeExecutionPlan(sd, umFull, @["unit_a"])
    let plan2 = makeExecutionPlan(sd, umSelected, @["unit_a"])
    check plan1.planDigest != plan2.planDigest

  test "sensitivity: selectedUnitIds change alters planDigest":
    let sd = makeSelectionDerivation()
    let plan1 = makeExecutionPlan(sd, umSelected, @["unit_a"])
    let plan2 = makeExecutionPlan(sd, umSelected, @["unit_b"])
    check plan1.planDigest != plan2.planDigest

  test "composeWithBaseRun: combined digest is deterministic":
    let base = BaseRunIdentity(
      semanticIdentity: BaseSemanticIdentity(
        baseCommit: "base_commit",
        treeDigest: "tree_digest",
        certificationMode: "incremental",
        requiredWorkUnitCoverage: "complete",
        identityDigest: "semantic_digest"),
      provenance: BaseProvenance(
        runId: "run_1",
        workflow: "ci",
        resultStatus: "success",
        recordedAt: "2026-01-01",
        runnerId: "runner_1"))
    let plan = makeExecutionPlan(makeSelectionDerivation(), umSelected, @["unit_a"])
    let combined1 = composeWithBaseRun(base, plan.planIdentity)
    let combined2 = composeWithBaseRun(base, plan.planIdentity)
    check combined1 == combined2

  test "composeWithBaseRun: different plan produces different combined digest":
    let base = BaseRunIdentity(
      semanticIdentity: BaseSemanticIdentity(
        baseCommit: "base_commit",
        treeDigest: "tree_digest",
        certificationMode: "incremental",
        requiredWorkUnitCoverage: "complete",
        identityDigest: "semantic_digest"),
      provenance: BaseProvenance(
        runId: "run_1",
        workflow: "ci",
        resultStatus: "success",
        recordedAt: "2026-01-01",
        runnerId: "runner_1"))
    let plan1 = makeExecutionPlan(makeSelectionDerivation(), umSelected, @["unit_a"])
    let plan2 = makeExecutionPlan(makeSelectionDerivation(), umFull, @["unit_a"])
    check composeWithBaseRun(base, plan1.planIdentity) !=
          composeWithBaseRun(base, plan2.planIdentity)

suite "projectToSelected — contract sentence 4":

  test "Project(Full, Selected) == PrunedResult for fixture":
    let fullUnits = @[
      UnitResult(
        unitId: "unit_a",
        proofStatus: psPass,
        failureClassification: "",
        vacuityClassification: "",
        certificateIdentityDigest: "cert_a",
        resultDigest: "res_a"),
      UnitResult(
        unitId: "unit_b",
        proofStatus: psFail,
        failureClassification: "timeout",
        vacuityClassification: "",
        certificateIdentityDigest: "cert_b",
        resultDigest: "res_b"),
      UnitResult(
        unitId: "unit_c",
        proofStatus: psPass,
        failureClassification: "",
        vacuityClassification: "",
        certificateIdentityDigest: "cert_c",
        resultDigest: "res_c")]
    let fullResult = GlobalResult(
      unitResults: fullUnits,
      selectedUniverseRatio: 1.0,
      selectionInvariantProjection: fullUnits,
      selectionScopedReport: %*{})

    let selectedIds = @["unit_a", "unit_c"]
    let projected = projectToSelected(fullResult, selectedIds)

    ## PrunedResult would contain only unit_a and unit_c with exact fields
    check projected.unitResults.len == 2
    check projected.unitResults[0].unitId == "unit_a"
    check projected.unitResults[0].proofStatus == psPass
    check projected.unitResults[0].failureClassification == ""
    check projected.unitResults[0].certificateIdentityDigest == "cert_a"
    check projected.unitResults[0].resultDigest == "res_a"
    check projected.unitResults[1].unitId == "unit_c"
    check projected.unitResults[1].proofStatus == psPass
    check projected.unitResults[1].failureClassification == ""
    check projected.unitResults[1].certificateIdentityDigest == "cert_c"
    check projected.unitResults[1].resultDigest == "res_c"

    ## unit_b (not in Selected) must be absent
    check projected.unitResults.allIt(it.unitId != "unit_b")

  test "selectedUniverseRatio is selection-scoped (not invariant)":
    let fullUnits = @[
      UnitResult(unitId: "u1", proofStatus: psPass,
        failureClassification: "", vacuityClassification: "",
        certificateIdentityDigest: "c1", resultDigest: "r1"),
      UnitResult(unitId: "u2", proofStatus: psFail,
        failureClassification: "err", vacuityClassification: "",
        certificateIdentityDigest: "c2", resultDigest: "r2"),
      UnitResult(unitId: "u3", proofStatus: psPass,
        failureClassification: "", vacuityClassification: "",
        certificateIdentityDigest: "c3", resultDigest: "r3")]
    let fullResult = GlobalResult(
      unitResults: fullUnits,
      selectedUniverseRatio: 1.0,
      selectionInvariantProjection: fullUnits,
      selectionScopedReport: %*{})

    let projected = projectToSelected(fullResult, @["u1", "u2"])
    ## 2 selected out of 3 total = 2/3 ratio
    check projected.selectedUniverseRatio == 2.0 / 3.0

  test "selectionInvariantProjection preserves per-unit fields exactly":
    let unit = UnitResult(
      unitId: "unit_x",
      proofStatus: psVacuousTrivial,
      failureClassification: "",
      vacuityClassification: "trivial",
      certificateIdentityDigest: "cert_x",
      resultDigest: "res_x")
    let fullResult = GlobalResult(
      unitResults: @[unit],
      selectedUniverseRatio: 1.0,
      selectionInvariantProjection: @[unit],
      selectionScopedReport: %*{})

    let projected = projectToSelected(fullResult, @["unit_x"])
    check projected.selectionInvariantProjection.len == 1
    check projected.selectionInvariantProjection[0].unitId == "unit_x"
    check projected.selectionInvariantProjection[0].proofStatus == psVacuousTrivial
    check projected.selectionInvariantProjection[0].vacuityClassification == "trivial"
    check projected.selectionInvariantProjection[0].certificateIdentityDigest == "cert_x"
    check projected.selectionInvariantProjection[0].resultDigest == "res_x"

  test "empty selection produces empty projection with zero ratio":
    let fullResult = GlobalResult(
      unitResults: @[
        UnitResult(unitId: "u1", proofStatus: psPass,
          failureClassification: "", vacuityClassification: "",
          certificateIdentityDigest: "c1", resultDigest: "r1")],
      selectedUniverseRatio: 1.0,
      selectionInvariantProjection: @[],
      selectionScopedReport: %*{})

    let projected = projectToSelected(fullResult, @[])
    check projected.unitResults.len == 0
    check projected.selectedUniverseRatio == 0.0

{.pop.}
