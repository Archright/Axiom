# Phase-5b Claim-authoritative hydration tests.

import std/os
import std/json
import std/strutils
import std/sets
import std/tables
import std/times
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority
import core/trusted/claim_store
import core/trusted/claim_store_persist
import core/trusted/claim_authoritative_index
import core/trusted/authoritative_hydration

proc makeSpec(origin: SpecOrigin; corrupt = false): SpecificationArtifact =
  if corrupt:
    SpecificationArtifact(canonicalSpecIR: @[], origin: origin, ruleId: "s", ruleVersion: "v1")
  else:
    SpecificationArtifact(
      canonicalSpecIR: @["(>= result x)"],
      origin: origin, ruleId: "synthesizeContracts", ruleVersion: "v1")

proc makeBundle(spec: SpecificationArtifact; solverIdentity = "z3"; smtHash = "abc123"): EvidenceBundle =
  result.specificationArtifact = spec
  result.facts.solver.solverIdentity = solverIdentity
  result.facts.solver.smtHash = smtHash

proc ctx(subjectId: string; bundle: EvidenceBundle; spec: SpecificationArtifact;
         signal: ClaimSignal; supported = true; depsOk = true; obligation = true): ClaimContext =
  ClaimContext(
    subjectId: subjectId, sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: obligation,
    supported: supported, dependenciesSatisfied: depsOk, proofSignal: signal,
    evidenceBundle: bundle, policyId: "policy-001")

proc makeClaim(subjectId: string; outcome: VerificationOutcomeRef;
                spec: SpecificationArtifact; bundle: EvidenceBundle): VerifiedClaim =
  let signal = case outcome
    of clProved: psUnsat
    of clUnknown: psUnknown
    of clDisproved: psCounterexample
    of clUnsupported: psNotEncodable
    of clNoSpecification: psUnknown
    of clDependencyBlocked: psUnknown
    of clInvalidEvidence: psUnknown
  deriveClaim(ctx(subjectId, bundle, spec, signal), apV1)

proc storeWithClaims(): ClaimStore =
  let spec = makeSpec(soCanonicalDerived)
  let bundle = makeBundle(spec)
  let c1 = makeClaim("subject-1", clProved, spec, bundle)
  let c2 = makeClaim("subject-2", clUnknown, spec, bundle)
  result.add(c1)
  result.add(c2)

proc main() =
  let store = storeWithClaims()
  let jsonNode = serializeClaims(store)

  # --- write claims to temp dir ---
  let tmpDir = getTempDir() / "axiom_hydration_test_" & $epochTime().int
  createDir(tmpDir)
  defer: removeDir(tmpDir)
  writeFile(tmpDir / "claims.json", $jsonNode)

  # --- hydrate from temp dir ---
  let result = hydrateVerifiedSetFromClaims(tmpDir)

  # After the claimsDir bypass fix (kernelChecking gate), Z3-only claims
  # (kernelChecking=false) are excluded from the verified set.
  # subject-1 has clProved outcome but kernelChecking=false (Z3-only),
  # so it must NOT be in the verified set.
  doAssert not result.verified.contains("subject-1"),
    "Z3-only claim (kernelChecking=false) must NOT be in verified set after claimsDir bypass fix"
  doAssert not result.verified.contains("subject-2"),
    "UNKNOWN subject must NOT be in verified set"

  # The verified set is now empty for Z3-only claims — this is the
  # correct behavior: false evidence (Z3-only) is NEVER promoted to VERIFIED.

  # invariant holds
  doAssert isLegacyFree(result.store),
    "Store must be legacy-free"

  # --- tamper test: flip an outcome in the JSON ---
  let jsonStr = $jsonNode
  let tamperedStr = jsonStr.replace("clProved", "clInvalidEvidence")
  let tamperedNode = parseJson(tamperedStr)
  let tamperedStore = deserializeClaims(tamperedNode)

  # tampered claim is rejected by claimId integrity check
  doAssert tamperedStore.claims.len < store.claims.len,
    "Tampered store must have fewer claims (claimId integrity rejects tampered outcome)"

  # write tampered store to temp dir
  let tmpDir2 = getTempDir() / "axiom_hydration_tamper_" & $epochTime().int
  createDir(tmpDir2)
  defer: removeDir(tmpDir2)
  writeFile(tmpDir2 / "claims.json", $serializeClaims(tamperedStore))

  let tamperedResult = hydrateVerifiedSetFromClaims(tmpDir2)

  # tampered subject must NOT be in verified (no cert-derived trust)
  doAssert not tamperedResult.verified.contains("subject-1"),
    "Tampered store must NOT produce verified claims (no cert-derived trust)"

  echo "=== Authoritative Hydration Tests OK ==="

main()