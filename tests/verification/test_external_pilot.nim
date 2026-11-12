import std/[os, json, sequtils, strutils, sets, tables, options]
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
import core/trusted/append_store
import core/trusted/claim_store_append
import core/trusted/replay_engine
import core/trusted/solver_invocation
import core/results

func makeAbsValFuncDef(): IRFuncDef =
  let bv64 = irTypeBitVec64()
  let x = irVar("x", bv64)
  let zero = irLit(0)
  let negX = irUnaryOp(uoBvNeg, x)
  let cond = irBinOp(boLt, x, zero)
  let body = irIf(cond, negX, x)
  result = irFuncDef(
    name = "absVal",
    params = @[("x", bv64)],
    ret = bv64,
    body = body
  )
  result.postConditions = @[irBinOp(boGe, irVar("result", bv64), zero)]

func makeBundle*(funcDef: IRFuncDef; origin: SpecOrigin): EvidenceBundle =
  captureEvidence(funcDef, origin, "v1", @["pilot-dep"], "pilot-scope")

func makeCtx*(bundle: EvidenceBundle; spec: SpecificationArtifact;
                signal: ClaimSignal; supported: bool;
                depsOk: bool; obligation: bool): ClaimContext =
  ClaimContext(
    subjectId: "pilot-subject",
    sourceIdentity: "pilot-source",
    specification: spec,
    semanticProfileId: spec.specIdentity,
    obligationGenerated: obligation,
    supported: supported,
    dependenciesSatisfied: depsOk,
    proofSignal: signal,
    evidenceBundle: bundle,
    policyId: "apV1"
  )

func derivePilotClaim(): VerifiedClaim =
  let funcDef = makeAbsValFuncDef()
  let origin = soExplicit
  let supported = true
  let depsOk = true
  let signal: ClaimSignal = psUnsat
  let obligation = true
  let bundle = makeBundle(funcDef, origin)
  let spec = bundle.specificationArtifact
  let ctx = makeCtx(bundle, spec, signal, supported, depsOk, obligation)
  deriveClaim(ctx, apV1)

proc runPilotSlice(): (VerifiedClaim, EvidenceBundle, string, ReplayStatus) =
  let funcDef = makeAbsValFuncDef()
  let origin = soExplicit
  let bundle = makeBundle(funcDef, origin)
  let spec = bundle.specificationArtifact
  let ctx = makeCtx(bundle, spec, psUnsat, true, true, true)
  let claim = deriveClaim(ctx, apV1)
  let proj = v2Projection(claim, "SPV1")
  doAssert proj.getOrDefault("schemaVersion").getStr() == "2", "schemaVersion must be 2"
  doAssert proj.getOrDefault("outcome").getStr() == "clProved", "PROVED outcome must be clProved"
  var store = ClaimStore()
  store.add(claim)
  let tempDir = getTempDir() & "/axiom_pilot_claims"
  if dirExists(tempDir): removeDir(tempDir)
  createDir(tempDir & "/claims")
  let storePath = tempDir & "/claims/claims.jsonl"
  writeFile(storePath & ".tmp", "")
  let appended = appendClaim(storePath, claim)
  doAssert appended, "appendClaim must succeed"
  let records = readRecords(storePath)
  doAssert records.len > 0, "append-store must have at least one record"
  let lastRecord = parseJson(records[^1])
  let storedClaimId = lastRecord.getOrDefault("claimId").getStr()
  doAssert storedClaimId == claim.claimId, "claimId must match after append+readback"
  let si = bundle.solverInvocation
  let fakeInvoke = proc(smt: string, t: int): Result[string, string] =
    ok("unsat")
  let status = runReplay(si, 1000, "unsat", fakeInvoke)
  doAssert status == rsMatch, "Replay must MATCH for unsat stored outcome"
  (claim, bundle, storedClaimId, status)

proc main() =
  echo "=== T4 External Pilot ==="

  # Separability: explicit-spec pure function under psUnsat must be PROVED
  let claim1 = derivePilotClaim()
  doAssert claim1.outcome == clProved, "Explicit-spec pure function under psUnsat must be PROVED (authorized spec, not MINED)"

  # Determinism: run the whole slice twice → identical claimId + replay outcome
  let (claimA, _, idA, statusA) = runPilotSlice()
  let (claimB, _, idB, statusB) = runPilotSlice()
  doAssert idA == idB, "Determinism: claimId must be identical across runs"
  doAssert statusA == statusB, "Determinism: replay status must be identical across runs"
  doAssert claimA.claimId == claimB.claimId, "Determinism: claimId must match"

  # v2Projection schemaVersion and outcome
  let proj = v2Projection(claim1, "SPV1")
  doAssert proj.getOrDefault("schemaVersion").getStr() == "2", "schemaVersion must be 2"
  doAssert proj.getOrDefault("outcome").getStr() == "clProved", "PROVED outcome must be clProved"

  # ClaimStore round-trip
  var store = ClaimStore()
  store.add(claim1)
  doAssert store.contains("pilot-subject"), "ClaimStore must contain pilot-subject"
  doAssert store.outcomeFor("pilot-subject").get() == clProved, "outcome must be clProved"
  doAssert store.verifiedMemberCount() == 1, "verifiedMemberCount must be 1"

  # Append-store round-trip
  let tempDir = getTempDir() & "/axiom_pilot_roundtrip"
  if dirExists(tempDir): removeDir(tempDir)
  createDir(tempDir & "/claims")
  let apPath = tempDir & "/claims/claims.jsonl"
  let appended = appendClaim(apPath, claim1)
  doAssert appended, "appendClaim must succeed"
  let records = readRecords(apPath)
  doAssert records.len == 1, "append-store must have exactly one record"
  let parsed = parseJson(records[0])
  doAssert parsed.getOrDefault("claimId").getStr() == claim1.claimId, "claimId must match"
  doAssert parsed.getOrDefault("subjectId").getStr() == "pilot-subject", "subjectId must match"
  doAssert parsed.getOrDefault("outcome").getStr() == "clProved", "outcome must be clProved"

  # Replay determinism: same solverInvocation → same replayKey
  let bundle = makeBundle(makeAbsValFuncDef(), soExplicit)
  let rk1 = replayKey(bundle.solverInvocation)
  let rk2 = replayKey(bundle.solverInvocation)
  doAssert rk1.len > 0, "replayKey must not be empty"
  doAssert rk1 == rk2, "replayKey must be deterministic for same bundle"

  # Full round-trip: deriveClaim → v2Projection → ClaimStore → serialize → temp dir → hydrate → lossless deserialize
  let claimFull = derivePilotClaim()
  let projFull = v2Projection(claimFull, "SPV1")
  doAssert projFull.getOrDefault("schemaVersion").getStr() == "2", "schemaVersion must be 2"
  doAssert projFull.getOrDefault("outcome").getStr() == "clProved", "PROVED outcome must be clProved"
  var storeFull = ClaimStore()
  storeFull.add(claimFull)
  let serializedFull = serializeClaims(storeFull)
  let fullTempDir = getTempDir() & "/axiom_pilot_full_roundtrip"
  if dirExists(fullTempDir): removeDir(fullTempDir)
  createDir(fullTempDir & "/claims")
  writeFile(fullTempDir & "/claims/claims.json", $serializedFull)
  let hydratedFull = hydrateVerifiedSetFromClaims(fullTempDir & "/claims")
  doAssert "pilot-subject" in hydratedFull.verified, "PROVED subject must be in verified set"
  let fileContent = readFile(fullTempDir & "/claims/claims.json")
  let fileNode = parseJson(fileContent)
  let deserializedFull = deserializeClaims(fileNode)
  doAssert deserializedFull.claims.hasKey("pilot-subject"), "Deserialized store must contain subject"
  doAssert deserializedFull.claims["pilot-subject"].claimId == claimFull.claimId, "Round-trip must be lossless (claimId)"
  removeDir(fullTempDir)

  # Replay via fake invoke returning "unsat" → rsMatch
  let replayFuncDef = makeAbsValFuncDef()
  let replayBundle = makeBundle(replayFuncDef, soExplicit)
  let replaySpec = replayBundle.specificationArtifact
  let replayCtx = makeCtx(replayBundle, replaySpec, psUnsat, true, true, true)
  discard deriveClaim(replayCtx, apV1)
  let siReplay = replayBundle.solverInvocation
  let fakeInvokeReplay = proc(smt: string, t: int): Result[string, string] =
    ok("unsat")
  let replayStatus = runReplay(siReplay, 1000, "unsat", fakeInvokeReplay)
  doAssert replayStatus == rsMatch, "Replay must MATCH for unsat stored outcome"

  removeDir(tempDir & "/claims")
  removeDir(tempDir)

  echo "=== T4 External Pilot PASSED ==="

main()