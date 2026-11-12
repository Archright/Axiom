import std/json
import std/os
import std/strutils
import std/options

import core/crypto/hash_kernel
import core/results
import core/trusted/scope_identity
import core/trusted/trust_commit
import verification/integrity_ledger

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc tmpBase(): string =
  let d = getTempDir() / ("axiom_wave3_ledger_test_" & $getCurrentProcessId())
  if dirExists(d):
    removeDir(d)
  createDir(d)
  d

proc expectedClaim(): string =
  var claim = newJObject()

  var reasoningTrail = newJArray()
  reasoningTrail.add(%*{"phase": "symbolic_analysis"})
  reasoningTrail.add(%*{"phase": "verdict", "verdict": "certGreen"})
  claim["reasoningTrail"] = reasoningTrail

  var provenanceLog = newJArray()
  provenanceLog.add(%*{"source": "unit", "action": "append"})
  claim["provenanceLog"] = provenanceLog

  var transitionLog = newJArray()
  transitionLog.add(%*{"from": "", "to": "certGreen"})
  claim["transitionLog"] = transitionLog

  pretty(claim, 2) & "\n"

proc expectedTrustCommit(claim: string; certDir: string = ".axiom/vault"): TrustCommit =
  let solverInvocation = "integrity-ledger-flush"
  let certificateDigest = "sha256:" & hash_kernel.sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)
  let nodeIds = @["sample.nim::testProc"]
  let scopeInput = scopeInputFromSynthetic(nodeIds, @[], nodeIds.len, nodeIds.len, solverInvocation, "wave3")
  let scopeDigest = canonicalScopeDigest(scopeInput)
  let configDigest = configIdentityDigest(solverInvocation, certDir)

  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: solverInvocation,
    attestation: "integrity-ledger-flush:v1",
    certificateDigest: certificateDigest,
    scopeDigest: scopeDigest,
    configDigest: configDigest,
    parentCommit: none(string)
  )

proc buildLedgerCommit(baseDir: string): Result[TrustCommit, string] =
  let certDir = baseDir / ".axiom" / "vault"
  createDir(certDir)
  let certPath = certDir / "sample.nim::testProc.json"
  let staleContent = """{"status":"stale","modulePath":"sample.nim","functionName":"testProc"}"""
  writeFile(certPath, staleContent)

  appendToReasoningTrail("sample.nim::testProc", %*{"phase": "symbolic_analysis"})
  appendToReasoningTrail("sample.nim::testProc", %*{"phase": "verdict", "verdict": "certGreen"})
  appendToProvenanceLog("sample.nim::testProc", %*{"source": "unit", "action": "append"})
  setTransitionLog("sample.nim::testProc", @[%*{"from": "", "to": "certGreen"}])

  flushGlobalAuditBufferToCertificates(certDir)
  result = readCommit(baseDir, listCommitIds(baseDir).value[0])

echo "=== wave3 integrity ledger TrustCommit tests ==="

# --- 1. Flush routes durable state to TrustCommit journal and leaves legacy cert untouched ---
block:
  let baseDir = tmpBase()
  let claim = expectedClaim()
  let certDir = baseDir / ".axiom" / "vault"
  let tc = expectedTrustCommit(claim, certDir)
  let val = validateCommit(tc)
  expect(val.ok, "expected TrustCommit validates")

  let commitRes = commitVerification(baseDir, tc)
  expect(commitRes.ok, "expected commitVerification succeeds: " & (if commitRes.isErr: commitRes.error else: ""))
  let cid = commitRes.value

  let flushed = buildLedgerCommit(baseDir)
  expect(flushed.ok, "flushGlobalAuditBufferToCertificates records a TrustCommit: " & (if flushed.isErr: flushed.error else: ""))
  let flushedCommit = flushed.value
  expect(fileExists(baseDir / ".axiom" / "vault" / "sample.nim::testProc.json"), "legacy cert directory still exists")
  expect(readFile(baseDir / ".axiom" / "vault" / "sample.nim::testProc.json") ==
    """{"status":"stale","modulePath":"sample.nim","functionName":"testProc"}""",
    "legacy cert content remains unchanged")
  expect(flushedCommit.kind == tcVerifiedProof, "flushed record kind is tcVerifiedProof")
  expect(flushedCommit.claim == claim, "flushed claim round-trips")
  expect(flushedCommit.solverInvocation == "integrity-ledger-flush", "solverInvocation round-trips")
  expect(flushedCommit.certificateDigest == "sha256:" & hash_kernel.sha256Hex(claim),
         "certificateDigest is SHA-256 of claim")
  expect(flushedCommit.evidenceId == computeEvidenceId(claim, "integrity-ledger-flush",
    "sha256:" & hash_kernel.sha256Hex(claim)), "evidenceId round-trips")
  expect(validateCommit(flushedCommit).ok, "persisted flushed commit re-validates")
  expect(listCommitIds(baseDir).value == @[cid],
         "journal contains exactly the expected commit id")
  echo "Test 1 PASSED: TrustCommit journal flush and legacy cert immutability"

# --- 2. evidenceId is deterministic and content-sensitive ---
block:
  let claim = expectedClaim()
  let tc = expectedTrustCommit(claim)
  let same = expectedTrustCommit(claim)
  expect(tc.evidenceId == same.evidenceId, "evidenceId deterministic for same claim/solver/cert digest")

  var changedSolver = expectedTrustCommit(claim)
  changedSolver.solverInvocation = "integrity-ledger-flush-v2"
  changedSolver.evidenceId = computeEvidenceId(claim, changedSolver.solverInvocation, changedSolver.certificateDigest)
  expect(tc.evidenceId != changedSolver.evidenceId, "evidenceId sensitive to solverInvocation")

  var changedClaim = expectedTrustCommit(claim)
  changedClaim.claim = claim.replace("certGreen", "certAmber")
  changedClaim.certificateDigest = "sha256:" & hash_kernel.sha256Hex(changedClaim.claim)
  changedClaim.evidenceId = computeEvidenceId(changedClaim.claim, changedClaim.solverInvocation, changedClaim.certificateDigest)
  expect(tc.evidenceId != changedClaim.evidenceId, "evidenceId sensitive to claim/certificateDigest")

  var tampered = expectedTrustCommit(claim)
  tampered.evidenceId = "tampered-evidence-id"
  expect(validateCommit(tampered).isErr, "tampered evidenceId rejected")
  echo "Test 2 PASSED: evidenceId determinism, sensitivity, and validation"

# --- 3. commitVerification round-trip and journal replay ---
block:
  let baseDir = tmpBase()
  let claim = expectedClaim()
  let tc = expectedTrustCommit(claim)
  let cid = commitVerification(baseDir, tc)
  expect(cid.ok, "commitVerification succeeds: " & (if cid.isErr: cid.error else: ""))

  let readBack = readCommit(baseDir, cid.value)
  expect(readBack.ok, "readCommit succeeds: " & (if readBack.isErr: readBack.error else: ""))
  expect(readBack.value.kind == tcVerifiedProof, "kind round-trips")
  expect(readBack.value.claim == claim, "claim round-trips")
  expect(readBack.value.scopeDigest == expectedTrustCommit(claim).scopeDigest, "scopeDigest round-trips")
  expect(readBack.value.configDigest == expectedTrustCommit(claim).configDigest, "configDigest round-trips")
  expect(validateCommit(readBack.value).ok, "read commit re-validates")

  let state = replayJournal(baseDir)
  expect(state.ok, "replayJournal succeeds: " & (if state.isErr: state.error else: ""))
  expect(state.value.commitIds == @[cid.value], "replay returns committed id: " & $state.value.commitIds)
  expect(state.value.scopeDigest == tc.scopeDigest, "replay carries scopeDigest")
  expect(state.value.configDigest == tc.configDigest, "replay carries configDigest")
  echo "Test 3 PASSED: TrustCommit round-trip and replay"

echo ""
if failures == 0:
  echo "=== All wave3 integrity ledger TrustCommit tests PASSED ==="
else:
  echo "=== " & $failures & " wave3 integrity ledger TrustCommit test(s) FAILED ==="
  quit(1)
