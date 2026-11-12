import std/[os, json, sequtils, strutils, sets, tables]
import core/trusted/layer_declaration
import core/trusted/axiom_ir_helpers
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/evidence_capture
import core/trusted/claim_authority
import core/trusted/assurance_profile
import core/trusted/claim_projection
import core/trusted/claim_store
import core/trusted/claim_store_persist
import core/trusted/authoritative_hydration
import core/trusted/solver_invocation

func makeAddFuncDef(): IRFuncDef =
  let bv64 = irTypeBitVec64()
  let x = irVar("x", bv64)
  let y = irVar("y", bv64)
  let body = irBinOp(boAdd, x, y)
  result = irFuncDef(
    name = "add",
    params = @[("x", bv64), ("y", bv64)],
    ret = bv64,
    body = body
  )
  result.postConditions = @[irBinOp(boGe, irVar("result", bv64), irAdd(x, y))]

func makeBundle*(funcDef: IRFuncDef; origin: SpecOrigin): EvidenceBundle =
  captureEvidence(funcDef, origin, "v1", @["e2e-dep"], "e2e-scope")

func makeCtx*(bundle: EvidenceBundle; spec: SpecificationArtifact;
               signal: ClaimSignal; supported: bool;
               depsOk: bool; obligation: bool): ClaimContext =
  ClaimContext(
    subjectId: "e2e-subject",
    sourceIdentity: "e2e-source",
    specification: spec,
    semanticProfileId: spec.specIdentity,
    obligationGenerated: obligation,
    supported: supported,
    dependenciesSatisfied: depsOk,
    proofSignal: signal,
    evidenceBundle: bundle,
    policyId: "apV1"
  )

func deriveClaimFromSource(source: string): VerifiedClaim =
  let funcDef = makeAddFuncDef()
  let origin: SpecOrigin = case source
    of "proved": soCanonicalDerived
    of "disproved": soCanonicalDerived
    of "unknown": soCanonicalDerived
    of "unsupported": soCanonicalDerived
    of "no_specification": soMined
    of "blocked": soCanonicalDerived
    else: soCanonicalDerived
  let supported = source != "unsupported"
  let depsOk = source != "blocked"
  let signal: ClaimSignal = case source
    of "proved": psUnsat
    of "disproved": psCounterexample
    of "unknown": psUnknown
    of "unsupported": psUnsat
    of "no_specification": psUnsat
    of "blocked": psUnsat
    else: psUnsat
  let obligation = true
  let bundle = makeBundle(funcDef, origin)
  let spec = bundle.specificationArtifact
  let ctx = makeCtx(bundle, spec, signal, supported, depsOk, obligation)
  deriveClaim(ctx, apV1)

func runRealE2E*(source: string): VerificationOutcomeRef =
  let funcDef = makeAddFuncDef()
  let origin: SpecOrigin = case source
    of "proved": soCanonicalDerived
    of "disproved": soCanonicalDerived
    of "unknown": soCanonicalDerived
    of "unsupported": soCanonicalDerived
    of "no_specification": soMined
    of "blocked": soCanonicalDerived
    else: soCanonicalDerived
  let supported = source != "unsupported"
  let depsOk = source != "blocked"
  let signal: ClaimSignal = case source
    of "proved": psUnsat
    of "disproved": psCounterexample
    of "unknown": psUnknown
    of "unsupported": psUnsat
    of "no_specification": psUnsat
    of "blocked": psUnsat
    else: psUnsat
  let obligation = true
  let bundle = makeBundle(funcDef, origin)
  let spec = bundle.specificationArtifact
  let ctx = makeCtx(bundle, spec, signal, supported, depsOk, obligation)
  let claim = deriveClaim(ctx, apV1)
  claim.outcome

const
  SourceProved = "proved"
  SourceDisproved = "disproved"
  SourceUnknown = "unknown"
  SourceUnsupported = "unsupported"
  SourceNoSpecification = "no_specification"
  SourceBlocked = "blocked"

proc main() =
  echo "=== Phase-9 External E2E Real Harness ==="

  let cases = @[
    SourceProved,
    SourceDisproved,
    SourceUnknown,
    SourceUnsupported,
    SourceNoSpecification,
    SourceBlocked
  ]

  for cas in cases:
    let r1 = runRealE2E(cas)
    let r2 = runRealE2E(cas)
    doAssert r1 == r2, "Determinism failure for " & cas & ": " & $r1 & " != " & $r2
    echo "  [PASS] " & cas & " deterministic: " & $r1

  let rProved = runRealE2E(SourceProved)
  doAssert rProved == clProved, "PROVED case must be clProved, got " & $rProved

  let rDisproved = runRealE2E(SourceDisproved)
  doAssert rDisproved != clProved, "DISPROVED must NOT be clProved"

  let rUnknown = runRealE2E(SourceUnknown)
  doAssert rUnknown != clProved, "UNKNOWN must NOT be clProved"

  let rUnsupported = runRealE2E(SourceUnsupported)
  doAssert rUnsupported != clProved, "UNSUPPORTED must NOT be clProved"

  let rNoSpec = runRealE2E(SourceNoSpecification)
  doAssert rNoSpec != clProved, "NO_SPECIFICATION must NOT be clProved"

  let rBlocked = runRealE2E(SourceBlocked)
  doAssert rBlocked != clProved, "BLOCKED must NOT be clProved"

  # === Full round-trip (PROVED): deriveClaim → v2Projection → ClaimStore → serialize → temp dir → hydrate → lossless deserialize ===
  let claimProved = deriveClaimFromSource(SourceProved)
  let projProved = v2Projection(claimProved, "SPV1")
  doAssert projProved.getOrDefault("schemaVersion").getStr() == "2", "schemaVersion must be 2"
  doAssert projProved.getOrDefault("outcome").getStr() == "clProved", "PROVED outcome must be clProved"

  var storeProved = ClaimStore()
  storeProved.add(claimProved)
  let serializedProved = serializeClaims(storeProved)
  let tempDir = getTempDir() & "/axiom_e2e_proved"
  if dirExists(tempDir): removeDir(tempDir)
  createDir(tempDir & "/claims")
  writeFile(tempDir & "/claims/claims.json", $serializedProved)
  let hydratedProved = hydrateVerifiedSetFromClaims(tempDir & "/claims")
  doAssert "e2e-subject" in hydratedProved.verified, "PROVED subject must be in verified set"
  let fileContent = readFile(tempDir & "/claims/claims.json")
  let fileNode = parseJson(fileContent)
  let deserializedProved = deserializeClaims(fileNode)
  doAssert deserializedProved.claims.hasKey("e2e-subject"), "Deserialized store must contain subject"
  doAssert deserializedProved.claims["e2e-subject"].claimId == claimProved.claimId, "Round-trip must be lossless (claimId)"
  removeDir(tempDir)

  # === Replay key: solverInvocation carried by EvidenceBundle → replayKey non-empty and deterministic ===
  let bundleProved = makeBundle(makeAddFuncDef(), soCanonicalDerived)
  let rk1 = replayKey(bundleProved.solverInvocation)
  let rk2 = replayKey(bundleProved.solverInvocation)
  doAssert rk1.len > 0, "replayKey must not be empty"
  doAssert rk1 == rk2, "replayKey must be deterministic for same bundle"

  # === Failure separability: 5 non-PROVED outcomes → v2Projection has corresponding non-proved value, hydrate does NOT contain subject ===
  let failureCases = @[
    (SourceDisproved, "clDisproved"),
    (SourceUnknown, "clUnknown"),
    (SourceUnsupported, "clUnsupported"),
    (SourceNoSpecification, "clNoSpecification"),
    (SourceBlocked, "clDependencyBlocked")
  ]
  var failIdx = 0
  for (src, expectedOutcome) in failureCases:
    let failClaim = deriveClaimFromSource(src)
    let failProj = v2Projection(failClaim, "SPV1")
    doAssert failProj.getOrDefault("outcome").getStr() == expectedOutcome,
      src & " projection outcome must be " & expectedOutcome
    var failStore = ClaimStore()
    failStore.add(failClaim)
    let failSerialized = serializeClaims(failStore)
    let failTempDir = getTempDir() & "/axiom_e2e_fail_" & $failIdx
    inc failIdx
    if dirExists(failTempDir): removeDir(failTempDir)
    createDir(failTempDir & "/claims")
    writeFile(failTempDir & "/claims/claims.json", $failSerialized)
    let failHydrated = hydrateVerifiedSetFromClaims(failTempDir & "/claims")
    doAssert "e2e-subject" notin failHydrated.verified, src & " must NOT be in verified set"
    removeDir(failTempDir)

  echo "=== Phase-9 External E2E Real Harness PASSED ==="

main()