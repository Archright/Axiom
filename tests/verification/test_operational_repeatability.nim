import std/[os, json, sequtils, strutils, sets, tables, options, algorithm]
import core/trusted/layer_declaration
import core/trusted/axiom_ir_helpers
import core/trusted/specification_artifact
import core/trusted/evidence_capture
import core/trusted/evidence_calculus
import core/trusted/claim_authority
import core/trusted/assurance_profile
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

func makeProvedClaim(): VerifiedClaim =
  let funcDef = makeAbsValFuncDef()
  let origin = soExplicit
  let bundle = captureEvidence(funcDef, origin, "v1", @["repeat-dep"], "repeat-scope")
  let spec = bundle.specificationArtifact
  let ctx = ClaimContext(
    subjectId: "repeat-subject",
    sourceIdentity: "repeat-source",
    specification: spec,
    semanticProfileId: spec.specIdentity,
    obligationGenerated: true,
    supported: true,
    dependenciesSatisfied: true,
    proofSignal: psUnsat,
    evidenceBundle: bundle,
    policyId: "apV1"
  )
  deriveClaim(ctx, apV1)

func makeUnknownClaim(): VerifiedClaim =
  let funcDef = makeAbsValFuncDef()
  let origin = soExplicit
  let bundle = captureEvidence(funcDef, origin, "v1", @["repeat-dep"], "repeat-scope")
  let spec = bundle.specificationArtifact
  let ctx = ClaimContext(
    subjectId: "unknown-subject",
    sourceIdentity: "repeat-source",
    specification: spec,
    semanticProfileId: spec.specIdentity,
    obligationGenerated: true,
    supported: true,
    dependenciesSatisfied: true,
    proofSignal: psUnknown,
    evidenceBundle: bundle,
    policyId: "apV1"
  )
  deriveClaim(ctx, apV1)

type ClaimSetEntry = tuple[claimId: string, outcome: string]

proc runSlice(): seq[ClaimSetEntry] =
  let provedClaim = makeProvedClaim()
  let unknownClaim = makeUnknownClaim()
  let tempDir = getTempDir() & "/axiom_repeat_test"
  if dirExists(tempDir): removeDir(tempDir)
  createDir(tempDir & "/claims")
  let storePath = tempDir & "/claims/claims.jsonl"
  doAssert appendClaim(storePath, provedClaim), "appendClaim must succeed for proved claim"
  doAssert appendClaim(storePath, unknownClaim), "appendClaim must succeed for unknown claim"
  let records = readRecords(storePath)
  doAssert records.len == 2, "append-store must have exactly two records"
  var entries: seq[ClaimSetEntry]
  for record in records:
    let node = parseJson(record)
    let cid = node.getOrDefault("claimId").getStr()
    let outcome = node.getOrDefault("outcome").getStr()
    entries.add((cid, outcome))
  entries.sort(proc(a, b: ClaimSetEntry): int = cmp(a.claimId, b.claimId))
  entries

proc main() =
  echo "=== T5 Operational Repeatability ==="

  let set1 = runSlice()
  let set2 = runSlice()
  doAssert set1 == set2, "OperationalRepeatability: ClaimSets must be identical across clean runs"
  echo "OperationalRepeatability invariant holds: ClaimSet(run1) == ClaimSet(run2)"

  let bundle1 = captureEvidence(makeAbsValFuncDef(), soExplicit, "v1", @["repeat-dep"], "repeat-scope")
  let bundle2 = captureEvidence(makeAbsValFuncDef(), soExplicit, "v1", @["repeat-dep"], "repeat-scope")
  let rk1 = replayKey(bundle1.solverInvocation)
  let rk2 = replayKey(bundle2.solverInvocation)
  doAssert rk1.len > 0, "replayKey must not be empty"
  doAssert rk1 == rk2, "replayKey must be identical for same SolverInvocation across runs"
  echo "ReplayKey determinism holds: replayKey(run1) == replayKey(run2)"

  echo "=== T5 Operational Repeatability PASSED ==="

main()