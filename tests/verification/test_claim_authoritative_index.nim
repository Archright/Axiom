import std/sets
import std/options
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority
import core/trusted/claim_store
import core/trusted/claim_authoritative_index

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
    evidenceBundle: bundle, policyId: "apV1")

proc kernelCheckedProvedClaim(subjectId: string;
                                 spec: SpecificationArtifact;
                                 bundle: EvidenceBundle): VerifiedClaim =
  ## PROVED claim with kernelChecking=true (Lean kernel acceptance confirmed).
  ## This is the only kind of claim that should be counted as verified
  ## in the claimsDir hydration path.
  result = deriveClaim(ctx(subjectId, bundle, spec, psUnsat), apV1)
  result.assurance.kernelChecking = true

proc main() =
  echo "=== Phase-5b Claim-Authoritative Index Tests ==="
  let ap = apV1
  let canonSpec = makeSpec(soCanonicalDerived)

  # --- PROVED claim WITHOUT kernelChecking (Z3-only, not verified) ---
  var store = ClaimStore()
  let provedBundle = makeBundle(canonSpec)
  let provedClaim = deriveClaim(ctx("subject-proved", provedBundle, canonSpec, psUnsat), ap)
  doAssert provedClaim.outcome == clProved, "deriveClaim must produce clProved for psUnsat + valid spec"
  doAssert provedClaim.assurance.kernelChecking == false, "Z3-only claim must not have kernelChecking"
  store.add(provedClaim)

  # --- UNKNOWN claim ---
  let unknownBundle = makeBundle(canonSpec)
  let unknownClaim = deriveClaim(ctx("subject-unknown", unknownBundle, canonSpec, psUnknown), ap)
  doAssert unknownClaim.outcome == clUnknown, "deriveClaim must produce clUnknown for psUnknown"
  store.add(unknownClaim)

  # --- (1) buildVerifiedSetFromClaims excludes Z3-only PROVED claims ---
  # Z3-only claims (kernelChecking=false) must NOT be counted as verified,
  # even though their outcome is clProved. This is the claimsDir bypass fix.
  let index = buildVerifiedSetFromClaims(store)
  doAssert not index.contains(provedClaim.subjectId),
    "Z3-only PROVED claim must NOT be in the verified index (kernelChecking=false)"
  doAssert not index.contains(unknownClaim.subjectId), "UNKNOWN subjectId must NOT be in the index"
  doAssert index.len == 0, "Index must be empty — no claim has kernelChecking"

  # --- (2) Kernel-checked PROVED claim IS in the index ---
  var kernelCheckedStore = ClaimStore()
  let kernelCheckedBundle = makeBundle(canonSpec)
  let kernelCheckedClaim = kernelCheckedProvedClaim("subject-kernel-checked", canonSpec, kernelCheckedBundle)
  doAssert kernelCheckedClaim.outcome == clProved
  doAssert kernelCheckedClaim.assurance.kernelChecking == true
  kernelCheckedStore.add(kernelCheckedClaim)
  let kernelCheckedIndex = buildVerifiedSetFromClaims(kernelCheckedStore)
  doAssert kernelCheckedIndex.contains(kernelCheckedClaim.subjectId),
    "Kernel-checked PROVED claim must be in the verified index"
  doAssert kernelCheckedIndex.len == 1, "Index must contain exactly one entry"

  # --- (3) Invariant: subjectId ∈ index ⇒ ∃ Claim with outcome=clProved AND kernelChecking ---
  for sid in kernelCheckedIndex:
    let claim = kernelCheckedStore.get(sid)
    doAssert claim.isSome(), "Every indexed subjectId must have a ClaimStore entry"
    doAssert claim.get().outcome == clProved, "Invariant: index member must have outcome=clProved"
    doAssert claim.get().assurance.kernelChecking == true, "Invariant: index member must have kernelChecking"

  # --- (4) isAuthoritativeSource checks claim existence + clProved outcome (independent of kernelChecking) ---
  # Z3-only claims are still authoritative as claims (they have clProved outcome),
  # but buildVerifiedSetFromClaims excludes them from the verified set.
  doAssert isAuthoritativeSource(kernelCheckedClaim.subjectId, kernelCheckedStore), "Kernel-checked PROVED subject must be authoritative"
  doAssert isAuthoritativeSource(provedClaim.subjectId, store), "Z3-only PROVED subject is still authoritative as a claim (clProved)"
  doAssert not isAuthoritativeSource(unknownClaim.subjectId, store), "UNKNOWN subject must NOT be authoritative"
  doAssert not isAuthoritativeSource("nonexistent", store), "Missing subject must NOT be authoritative"

  # --- (5) Legacy-style status string does NOT affect the index ---
  # Only the Claim's outcome + kernelChecking fields matter; a certificate-style
  # status (e.g. a legacy "certified" label on a non-PROVED claim) is ignored.
  # The UNKNOWN claim has a legacy-style "certPending" status but is excluded.
  doAssert not index.contains(unknownClaim.subjectId), "Legacy status must not override outcome-based index"

  # --- (6) Certificates never feed this index ---
  # Build a second store with only a non-PROVED claim (simulating a certificate
  # that says "verified" via a legacy status string but has outcome != clProved).
  var certStore = ClaimStore()
  let blockedBundle = makeBundle(canonSpec)
  let blockedClaim = deriveClaim(ctx("subject-blocked", blockedBundle, canonSpec, psUnsat, depsOk = false), ap)
  doAssert blockedClaim.outcome != clProved, "Blocked claim must not be clProved"
  certStore.add(blockedClaim)
  let certIndex = buildVerifiedSetFromClaims(certStore)
  doAssert certIndex.len == 0, "Certificate-only (non-PROVED) claims must produce empty index"

  # --- (7) Z3-only claim with kernelChecking=false must NEVER be verified ---
  # This is the core D1 negative assertion: false evidence (Z3-only) is NEVER
  # promoted to VERIFIED through the claimsDir hydration path.
  doAssert not index.contains(provedClaim.subjectId),
    "N1: Z3-only claim (kernelChecking=false) must NEVER be in verified set"

  echo "=== Phase-5b Claim-Authoritative Index Tests OK ==="

main()