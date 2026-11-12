import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

## Domain JSON serialization for Claim / SolverInvocation persistence.
##
## This module is the semantic layer over the generic `append_store` primitive.
## It owns the ONLY canonical JSON shape for appending a VerifiedClaim or a
## SolverInvocation line. Other readers/writers (claim_store_persist, cert_v2,
## verify_cli) should converge on a single SSOT for JSON field layout; this
## module is the append-side source of truth.
##
## Dependency direction: claim_store_append -> append_store -> filesystem.

import std/json
import std/options
import core/utils/io_utils
import core/axiom_pragmas
import core/trusted/append_store
import core/trusted/claim_authority
import core/trusted/solver_invocation

export append_store

proc appendClaim*(storePath: string; claim: VerifiedClaim): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let claimObj = newJObject()
  claimObj.add("claimId", %claim.claimId)
  claimObj.add("subjectId", %claim.subjectId)
  claimObj.add("outcome", %($claim.outcome))
  claimObj.add("policyId", %claim.policyId)
  claimObj.add("specificationId", %claim.specificationId)
  claimObj.add("semanticProfileId", %claim.semanticProfileId)
  claimObj.add("obligationId", %claim.obligationId)
  claimObj.add("evidenceId", %claim.evidenceId)
  claimObj.add("dependencySnapshotId", %claim.dependencySnapshotId)
  let assuranceObj = newJObject()
  assuranceObj.add("kernelChecking", %claim.assurance.kernelChecking)
  assuranceObj.add("replayability", %claim.assurance.replayability)
  assuranceObj.add("solverEvidence", %claim.assurance.solverEvidence)
  assuranceObj.add("specificationAuthority", %claim.assurance.specificationAuthority)
  assuranceObj.add("translationTrust", %claim.assurance.translationTrust)
  claimObj.add("assurance", assuranceObj)
  appendRecord(storePath, $claimObj)

proc appendSolverInvocation*(storePath: string; si: SolverInvocation): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let siObj = newJObject()
  siObj.add("replayKey", %si.replayKey)
  siObj.add("scriptDigest", %si.scriptDigest)
  siObj.add("solverIdentity", %si.solverIdentity)
  siObj.add("solverVersion", %si.solverVersion)
  siObj.add("solverOptionsDigest", %si.solverOptionsDigest)
  siObj.add("solverBinaryDigest", %si.solverBinaryDigest)
  siObj.add("semanticProfileId", %si.semanticProfileId)
  siObj.add("encodingIdentity", %si.encodingIdentity)
  siObj.add("env", %si.env)
  siObj.add("canonicalSourceIdentity", %si.canonicalSourceIdentity)
  siObj.add("specificationIdentity", %si.specificationIdentity)
  siObj.add("translationIdentityHash", %si.translationIdentityHash)
  siObj.add("smtScriptDigest", %si.smtScriptDigest)
  siObj.add("smtScript", %si.smtScript)
  appendRecord(storePath, $siObj)

## Read side of the projection appendSolverInvocation writes. `none` for a node
## that is not an object, and never an all-empty invocation in its place: a
## record whose solver identity cannot be recovered says nothing about which
## executable answered, so it must not be readable as evidence.
func solverInvocationFromJson*(node: JsonNode): Option[SolverInvocation] {.
  raises: [], axiomDecision(
    id = "DECISION-0823",
    reason = "Ledger read side of the SolverInvocation JSON projection: a record that does not decode is refused rather than defaulted to an empty invocation, so a lost solver identity cannot be read back as evidence",
    adr = "docs/adr/0017-trust-claim-authority.md",
    introduced = "v33").} =
  if node.isNil or node.kind != JObject:
    return none(SolverInvocation)
  some(makeSolverInvocation(
    scriptDigest = node.getOrDefault("scriptDigest").getStr(""),
    solverVersion = node.getOrDefault("solverVersion").getStr(""),
    solverOptionsDigest = node.getOrDefault("solverOptionsDigest").getStr(""),
    solverBinaryDigest = node.getOrDefault("solverBinaryDigest").getStr(""),
    semanticProfileId = node.getOrDefault("semanticProfileId").getStr(""),
    encodingIdentity = node.getOrDefault("encodingIdentity").getStr(""),
    solverIdentity = node.getOrDefault("solverIdentity").getStr(""),
    env = node.getOrDefault("env").getStr(""),
    canonicalSourceIdentity = node.getOrDefault("canonicalSourceIdentity").getStr(""),
    specificationIdentity = node.getOrDefault("specificationIdentity").getStr(""),
    translationIdentityHash = node.getOrDefault("translationIdentityHash").getStr(""),
    smtScriptDigest = node.getOrDefault("smtScriptDigest").getStr(""),
    smtScript = node.getOrDefault("smtScript").getStr("")
  ))

{.pop.}