import std/strutils
import std/tables
import std/options
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority
import core/trusted/claim_store

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

proc main() =
  echo "=== Phase-5 ClaimStore Invariant Tests ==="

  let ap = apV1
  let canonSpec = makeSpec(soCanonicalDerived)

  # --- (a) PROVED claim → verifiedMemberCount increments ---
  var store = ClaimStore()
  let provedBundle = makeBundle(canonSpec)
  let provedClaim = deriveClaim(ctx("subject-proved", provedBundle, canonSpec, psUnsat), ap)
  doAssert provedClaim.outcome == clProved, "deriveClaim must produce clProved for psUnsat + valid spec"
  store.add(provedClaim)
  doAssert store.verifiedMemberCount() == 1, "PROVED claim must increment verifiedMemberCount"
  doAssert store.contains(provedClaim.subjectId), "store must contain the PROVED subjectId"
  doAssert store.outcomeFor(provedClaim.subjectId) == some(clProved), "outcomeFor must return clProved"

  # --- (b) UNKNOWN claim → does NOT count as verified ---
  let unknownBundle = makeBundle(canonSpec)
  let unknownClaim = deriveClaim(ctx("subject-unknown", unknownBundle, canonSpec, psUnknown), ap)
  doAssert unknownClaim.outcome == clUnknown, "deriveClaim must produce clUnknown for psUnknown"
  store.add(unknownClaim)
  doAssert store.verifiedMemberCount() == 1, "UNKNOWN claim must NOT increment verifiedMemberCount"
  doAssert store.outcomeFor(unknownClaim.subjectId) == some(clUnknown), "outcomeFor must return clUnknown"

  # --- (b) BLOCKED claim → does NOT count as verified ---
  let blockedBundle = makeBundle(canonSpec)
  let blockedClaim = deriveClaim(ctx("subject-blocked", blockedBundle, canonSpec, psUnsat, depsOk = false), ap)
  doAssert blockedClaim.outcome == clDependencyBlocked, "deriveClaim must produce clDependencyBlocked when depsOk=false"
  store.add(blockedClaim)
  doAssert store.verifiedMemberCount() == 1, "BLOCKED claim must NOT increment verifiedMemberCount"
  doAssert store.outcomeFor(blockedClaim.subjectId) == some(clDependencyBlocked), "outcomeFor must return clDependencyBlocked"

  # --- (c) Invariant: s ∈ VerifiedSet ⇒ ∃ Claim(s, outcome=clProved) ---
  # Simulate VerifiedSet as a set of subjectIds that are "verified".
  # Only the PROVED claim's subjectId is in the VerifiedSet.
  let verifiedSet: seq[string] = @[provedClaim.subjectId]
  for sid in verifiedSet:
    let claim = store.get(sid)
    doAssert claim.isSome(), "Every VerifiedSet member must have a ClaimStore entry"
    doAssert claim.get().outcome == clProved, "Invariant: s∈VerifiedSet ⇒ outcome=clProved"

  # Also verify reverse: every clProved entry has its subjectId in the VerifiedSet
  for sid, claim in store.claims:
    if claim.outcome == clProved:
      doAssert sid in verifiedSet, "Every clProved claim must correspond to a VerifiedSet member"

  # --- get returns none for missing subjectId ---
  doAssert store.get("nonexistent").isNone(), "get must return none for unknown subjectId"
  doAssert store.outcomeFor("nonexistent").isNone(), "outcomeFor must return none for unknown subjectId"
  doAssert not store.contains("nonexistent"), "contains must return false for unknown subjectId"

  echo "=== Phase-5 ClaimStore Invariant Tests OK ==="

main()