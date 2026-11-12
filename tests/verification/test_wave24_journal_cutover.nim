# Wave2 + Wave4 UAP certificate durable-write cutover regression.
#
# Exercises the REAL producer procs z3outTrustCommit / v2VerifiedTrustCommit
# (exported from verification/cert_writer) directly, rather than re-implementing
# them locally as the legacy sidecar tests do. Confirms:
#   1. Both TrustCommits pass validateCommit (I5 fail-closed).
#   2. commitVerification(baseDir, tc) round-trips through the journal
#      (readCommit + replayJournal) and writes into {baseDir}/data/trusted/journal.
#   3. evidenceId is content-sensitive: changing certificateDigest changes the
#      committed evidenceId, so a tampered digest is rejected.

import std/json
import std/options
import std/os
import std/strutils
import std/tables

import core/crypto/hash_kernel
import core/results
import core/trusted/claim_authority
import core/trusted/claim_projection
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/scope_identity
import core/trusted/specification_artifact
import core/trusted/trust_commit
import core/utils/io_utils
import verification/cert_writer

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc tmpBase(): string =
  let d = getTempDir() / "ax_wave24_journal_cutover" & $getCurrentProcessId()
  if dirExists(d):
    removeDir(d)
  createDir(d)
  d

proc noSpecClaim(): VerifiedClaim =
  let s = SpecificationArtifact(canonicalSpecIR: @["(>= result x)"], origin: soMined,
                                ruleId: "s", ruleVersion: "v1")
  var ctx = ClaimContext(
    subjectId: "src/mod.nim::f", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  deriveClaim(ctx, apV1)

proc main() =
  echo "=== Wave2+Wave4 UAP cert durable-write journal cutover ==="

  let base = tmpBase()
  let modulePath = "src/mod.nim"
  let functionName = "f"
  let solverStatus = "unsat"
  let irHash = "wave24ir"

  # --- z3outTrustCommit (Wave4 .z3out sidecar → journal) ---
  let z3 = z3outTrustCommit(
    modulePath, functionName, solverStatus, "leanProposition", "SPV1",
    leanKernelVerified = false, negativeTestResult = false, vacuityProven = false,
    smtlib2 = "(set-logic QF_BV)", irHash = irHash)
  expect(z3.solverInvocation == "z3out", "z3out TrustCommit solverInvocation is 'z3out'")
  expect(validateCommit(z3).ok, "z3outTrustCommit passes validateCommit")
  expect(z3.evidenceId == computeEvidenceId(z3.claim, "z3out", z3.certificateDigest),
         "z3out evidenceId binds claim/solver/certificateDigest")
  # content-sensitivity: changing the certificate digest changes the evidenceId
  expect(z3.evidenceId != computeEvidenceId(z3.claim, "z3out", "changed-digest"),
         "z3out evidenceId is sensitive to certificateDigest")

  let z3IdRes = commitVerification(base, z3)
  expect(z3IdRes.ok, "commitVerification z3out ok: " & (if z3IdRes.isErr: z3IdRes.error else: ""))
  let z3Id = z3IdRes.value
  # durable write lands in {baseDir}/data/trusted/journal/<commitId>.json
  expect(fileExists(commitPath(base, z3Id)), "z3out journal file written under data/trusted/journal")
  expect(commitPath(base, z3Id).contains("data" / "trusted" / "journal"),
         "z3out commit path is inside {baseDir}/data/trusted/journal")
  let z3Back = readCommit(base, z3Id)
  expect(z3Back.ok, "z3out journal round-trip readCommit")
  expect(z3Back.value.claim == z3.claim, "z3out claim round-trips")
  expect(validateCommit(z3Back.value).ok, "z3out persisted commit revalidates")

  # --- v2VerifiedTrustCommit (Wave4 .v2.json sidecar → journal) ---
  let claim = noSpecClaim()
  let v2 = v2VerifiedTrustCommit(claim, "SPV1", modulePath, functionName, solverStatus, irHash)
  expect(v2.solverInvocation == "v2-verified", "v2 TrustCommit solverInvocation is 'v2-verified'")
  expect(validateCommit(v2).ok, "v2VerifiedTrustCommit passes validateCommit")
  expect(v2.evidenceId == computeEvidenceId(v2.claim, "v2-verified", v2.certificateDigest),
         "v2 evidenceId binds claim/solver/certificateDigest")
  expect(v2.evidenceId != computeEvidenceId(v2.claim, "v2-verified", "changed-digest"),
         "v2 evidenceId is sensitive to certificateDigest")
  expect(z3.evidenceId != v2.evidenceId, "z3out and v2 evidenceIds differ")

  let v2IdRes = commitVerification(base, v2)
  expect(v2IdRes.ok, "commitVerification v2 ok: " & (if v2IdRes.isErr: v2IdRes.error else: ""))
  let v2Id = v2IdRes.value
  expect(fileExists(commitPath(base, v2Id)), "v2 journal file written under data/trusted/journal")
  let v2Back = readCommit(base, v2Id)
  expect(v2Back.ok, "v2 journal round-trip readCommit")
  expect(v2Back.value.claim == v2.claim, "v2 claim round-trips")
  expect(validateCommit(v2Back.value).ok, "v2 persisted commit revalidates")

  # --- replayJournal reconstructs both Wave2/Wave4 cert commits ---
  let replay = replayJournal(base)
  expect(replay.ok, "replayJournal reconstructs cert commits")
  expect(replay.value.commitIds.len == 2, "replayJournal count == 2 (z3out + v2)")
  expect(replay.value.commitIds.contains(z3Id), "replayJournal includes z3out commit")
  expect(replay.value.commitIds.contains(v2Id), "replayJournal includes v2 commit")

  removeDir(base)

  echo ""
  if failures == 0:
    echo "=== All Wave2+Wave4 journal cutover tests PASSED ==="
  else:
    echo "=== " & $failures & " Wave2+Wave4 journal cutover test(s) FAILED ==="
    quit(1)

main()
