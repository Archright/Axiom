## Authoritative Hydration Integration Tests — Phase-5b
##
## Verifies the claim-authoritative path of hydrateVerifiedSetFromProofVault:
##   1. When claimsDir is non-empty and contains PROVED claims, the claim
##      path wins over the certificate scan (even with an empty vaultDir).
##   2. When claimsDir is empty, the legacy certificate fallback is used
##      without crashing (backward compatibility).

import std/[unittest, os, json, sets, tables]
import core/sorter/sorter_core
import core/topology/topology_engine
import core/topology/topology_types
import core/topology/symbol_interning
import core/topology/verified_set
import core/utils/io_utils
import core/crypto/hash_kernel
import core/trusted/claim_store
import core/trusted/claim_store_persist
import core/trusted/claim_authority
import core/trusted/assurance_profile
import core/proof/proof_integrity
import verification/verified_set_hydration

func makeHydrationSymbol(
  modulePath, functionName: string
): TopologySymbol =
  TopologySymbol(
    modulePath: modulePath,
    functionName: functionName,
    nodeType: "func",
    nodeId: sorterNodeId(modulePath & "::" & functionName),
    declarationLine: 1,
    bodyStartLine: 1,
    bodyEndLine: 2,
    exported: false,
    boundaryKind: topologyBoundaryNone,
    rawCallTargets: @[],
    branchCount: 0,
    nestingDepth: 0,
    lineSpan: 2
  )

func computeClaimId(
  subjectId: string;
  outcome: VerificationOutcomeRef;
  assurance: AssuranceProfile;
  specificationId, semanticProfileId, obligationId, evidenceId,
  dependencySnapshotId, policyId: string
): string =
  sha256Hex(
    subjectId & "|" & $outcome &
    "|" & $assurance.specificationAuthority & $assurance.translationTrust &
        $assurance.solverEvidence & $assurance.replayability & $assurance.kernelChecking &
    "|" & specificationId & "|" & semanticProfileId &
    "|" & obligationId & "|" & evidenceId &
    "|" & dependencySnapshotId & "|" & policyId)

func makeProvedClaim(subjectId: string): VerifiedClaim =
  let assurance = AssuranceProfile(
    specificationAuthority: true,
    translationTrust: true,
    solverEvidence: true,
    replayability: true,
    kernelChecking: false
  )
  let obligationId = "obl:" & subjectId
  let evidenceId = "ev:" & subjectId
  let dependencySnapshotId = "dep:" & subjectId
  let policyId = "policy-default"
  let specificationId = "spec-" & subjectId
  let semanticProfileId = "sem-" & subjectId
  let claimId = computeClaimId(
    subjectId, clProved, assurance,
    specificationId, semanticProfileId, obligationId, evidenceId,
    dependencySnapshotId, policyId)
  VerifiedClaim(
    subjectId: subjectId,
    outcome: clProved,
    assurance: assurance,
    specificationId: specificationId,
    semanticProfileId: semanticProfileId,
    obligationId: obligationId,
    evidenceId: evidenceId,
    dependencySnapshotId: dependencySnapshotId,
    policyId: policyId,
    claimId: claimId
  )

func makeUnknownClaim(subjectId: string): VerifiedClaim =
  let assurance = AssuranceProfile(
    specificationAuthority: true,
    translationTrust: true,
    solverEvidence: false,
    replayability: false,
    kernelChecking: false
  )
  let obligationId = "obl:" & subjectId
  let evidenceId = "ev:" & subjectId
  let dependencySnapshotId = "dep:" & subjectId
  let policyId = "policy-default"
  let specificationId = "spec-" & subjectId
  let semanticProfileId = "sem-" & subjectId
  let claimId = computeClaimId(
    subjectId, clUnknown, assurance,
    specificationId, semanticProfileId, obligationId, evidenceId,
    dependencySnapshotId, policyId)
  VerifiedClaim(
    subjectId: subjectId,
    outcome: clUnknown,
    assurance: assurance,
    specificationId: specificationId,
    semanticProfileId: semanticProfileId,
    obligationId: obligationId,
    evidenceId: evidenceId,
    dependencySnapshotId: dependencySnapshotId,
    policyId: policyId,
    claimId: claimId
  )

proc writeClaimsFile(dir: string; store: ClaimStore) =
  let json = serializeClaims(store)
  let path = dir / "claims.json"
  writeFile(path, $json)

proc buildSnapshot(analysis: TopologyAnalysis): InternPoolSnapshot =
  var pool = initInternPool(analysis.state.nodes.len)
  for node in analysis.state.nodes:
    discard nodeIdForSorter(pool, node.id)
  freezeInternPool(pool)

proc makeContentResolver(content: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [], noSideEffect.} =
    some(content)

suite "AuthoritativeHydration":

  let moduleContent = "proc proved*() = discard\nproc unknown*() = discard\n"
  let analysis = buildTopologyAnalysis(@[
    makeHydrationSymbol("src/authoritative.nim", "proved"),
    makeHydrationSymbol("src/authoritative.nim", "unknown")
  ])
  let snapshot = buildSnapshot(analysis)

  test "claim-authoritative path returns ONLY proved subject when claimsDir is set":
    let tmpDir = getTempDir() / ("axiom_claim_auth_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)

    var store = ClaimStore()
    store.claims["src/authoritative.nim::proved"] = makeProvedClaim("src/authoritative.nim::proved")
    store.claims["src/authoritative.nim::unknown"] = makeUnknownClaim("src/authoritative.nim::unknown")
    writeClaimsFile(tmpDir, store)

    let resolver = makeContentResolver(moduleContent)

    let verified = hydrateVerifiedSetFromProofVault(
      "", snapshot, analysis, resolver, KernelScopeInfo(),
      claimsDir = tmpDir
    )

    let provedNodeId = nodeIdForSorter(snapshot, sorterNodeId("src/authoritative.nim::proved"))
    let unknownNodeId = nodeIdForSorter(snapshot, sorterNodeId("src/authoritative.nim::unknown"))

    check provedNodeId.isSome and verified.contains(provedNodeId.get())
    check unknownNodeId.isNone or not verified.contains(unknownNodeId.get())

    removeDir(tmpDir)

  test "empty claimsDir falls back to certificate scan without crashing":
    let tmpDir = getTempDir() / ("axiom_claim_fallback_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)

    let resolver = makeContentResolver(moduleContent)

    let verified = hydrateVerifiedSetFromProofVault(
      "", snapshot, analysis, resolver, KernelScopeInfo(),
      claimsDir = ""
    )

    check verified.isEmpty()

    removeDir(tmpDir)