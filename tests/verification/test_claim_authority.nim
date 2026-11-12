# Phase-3 Claim Authority — acceptance (8 cases).
# deriveClaim is the single semantic authority; certificate labels never feed it.

import std/strutils
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority

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

proc ctx(bundle: EvidenceBundle; spec: SpecificationArtifact;
         signal: ClaimSignal; supported = true; depsOk = true; obligation = true): ClaimContext =
  ClaimContext(
    subjectId: "foo", sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: obligation,
    supported: supported, dependenciesSatisfied: depsOk, proofSignal: signal,
    evidenceBundle: bundle, policyId: "apV1")

proc main() =
  echo "=== Phase-3 Claim Authority ==="
  let authSpec = makeSpec(soCanonicalDerived)
  let minedSpec = makeSpec(soMined)
  let corruptSpec = makeSpec(soCanonicalDerived, corrupt = true)

  # 1. PROVED
  block:
    let b = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(b, makeSpec(soCanonicalDerived), psUnsat), apV1).outcome == clProved
  # 2. DISPROVED
  block:
    let b = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(b, makeSpec(soCanonicalDerived), psCounterexample), apV1).outcome == clDisproved
  # 3. NO_SPECIFICATION (MINED spec -> NOT PROVED even with Z3 unsat)
  block:
    let b = makeBundle(minedSpec)
    doAssert deriveClaim(ctx(b, minedSpec, psUnsat), apV1).outcome == clNoSpecification
  # 4. UNSUPPORTED
  block:
    let b = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(b, makeSpec(soCanonicalDerived), psNotEncodable, supported = false), apV1).outcome == clUnsupported
  # 5. BLOCKED
  block:
    let b = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(b, makeSpec(soCanonicalDerived), psUnsat, depsOk = false), apV1).outcome == clDependencyBlocked
  # 6. UNKNOWN (solver inconclusive)
  block:
    let b = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(b, makeSpec(soCanonicalDerived), psUnknown), apV1).outcome == clUnknown
  # 7. INVALID_EVIDENCE (corrupt spec identity)
  block:
    let b = makeBundle(corruptSpec)
    doAssert deriveClaim(ctx(b, corruptSpec, psUnsat), apV1).outcome == clInvalidEvidence
  # 8. MALFORMED vs INCONCLUSIVE boundary:
  #    missing solver identity -> UNKNOWN (incomplete); corrupt spec identity -> INVALID_EVIDENCE
  block:
    let bNoSolver = makeBundle(makeSpec(soCanonicalDerived), solverIdentity = "")
    doAssert deriveClaim(ctx(bNoSolver, makeSpec(soCanonicalDerived), psUnsat), apV1).outcome == clUnknown
    let bCorruptSpec = makeBundle(makeSpec(soCanonicalDerived, corrupt = true))
    doAssert deriveClaim(ctx(bCorruptSpec, corruptSpec, psUnsat), apV1).outcome == clInvalidEvidence

  # Invariant: exactly one well-defined outcome per context + claimId distinct across outcomes
  block:
    let a = deriveClaim(ctx(makeBundle(makeSpec(soCanonicalDerived)), makeSpec(soCanonicalDerived), psUnsat), apV1)
    let b = deriveClaim(ctx(makeBundle(makeSpec(soCanonicalDerived)), makeSpec(soCanonicalDerived), psCounterexample), apV1)
    doAssert a.claimId != b.claimId
  echo "=== Phase-3 Claim Authority OK (8 conditions) ==="
