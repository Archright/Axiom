import std/json
import std/options
import std/os
import std/strutils

import core/crypto/hash_kernel
import core/results
import core/trusted/assurance_profile
import core/trusted/trust_commit
import cli/verify_cli

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc tmpBase(): string =
  let d = getTempDir() / "axiom_journal_test" & $getCurrentProcessId()
  if dirExists(d):
    removeDir(d)
  createDir(d)
  d

echo "=== verify_cli journal lookup tests ==="

# --- 1. Journal lookup resolves a certificate from a TrustCommit ---
block:
  let base = tmpBase()
  let subjectId = "journal-subject-001"
  let identityDigest = sha256Hex("spec-j|sem-j|pol-j")
  let claimJson = %*{
    "schemaVersion": "2",
    "subjectId": subjectId,
    "outcome": "clProved",
    "specificationId": "spec-j",
    "semanticProfileId": "sem-j",
    "obligationId": "obl-j",
    "evidenceId": "ev-j",
    "dependencySnapshotId": "dep-j",
    "policyId": "pol-j",
    "identityDigest": identityDigest,
    "assurance": {
      "specificationAuthority": true,
      "translationTrust": true,
      "solverEvidence": true,
      "replayability": false,
      "kernelChecking": false
    }
  }
  let claimStr = $claimJson
  let solverInv = "solver-journal-test"
  let attestation = "attestation-journal-test"
  let certDigest = "cert-digest-journal-test"
  let evidenceId = computeEvidenceId(claimStr, solverInv, certDigest)
  let scopeDig = "scope-journal-test"
  let cfgDig = "cfg-journal-test"

  let tc = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claimStr,
    solverInvocation: solverInv,
    attestation: attestation,
    certificateDigest: certDigest,
    scopeDigest: scopeDig,
    configDigest: cfgDig,
    parentCommit: none(string)
  )
  let commitRes = commitVerification(base, tc)
  expect(commitRes.ok, "commitVerification ok: " & (if commitRes.isErr: commitRes.error else: ""))

  # locateCertFromJournal should find the cert from the journal
  let certOpt = locateCertFromJournal(base, subjectId)
  expect(certOpt.isSome, "locateCertFromJournal finds cert from journal for subject " & subjectId)
  if certOpt.isSome:
    let cert = certOpt.get()
    expect(cert.subjectId == subjectId, "cert subjectId matches")
    expect(cert.identityDigest == identityDigest, "cert identityDigest matches")
    expect(cert.outcome == clProved, "cert outcome is clProved")
    expect(cert.specificationId == "spec-j", "cert specificationId matches")
    expect(cert.schemaVersion == "2", "cert schemaVersion is 2")

  echo "Test 1 PASSED: journal lookup resolves certificate from TrustCommit"

# --- 2. Journal is preferred over a conflicting raw vault cert ---
block:
  let base = tmpBase()
  let subjectId = "conflict-subject-001"

  # Write a journal commit with one identityDigest
  let journalIdentityDigest = sha256Hex("spec-j2|sem-j2|pol-j2")
  let claimJson = %*{
    "schemaVersion": "2",
    "subjectId": subjectId,
    "outcome": "clProved",
    "specificationId": "spec-j2",
    "semanticProfileId": "sem-j2",
    "obligationId": "obl-j2",
    "evidenceId": "ev-j2",
    "dependencySnapshotId": "dep-j2",
    "policyId": "pol-j2",
    "identityDigest": journalIdentityDigest,
    "assurance": {
      "specificationAuthority": true,
      "translationTrust": true,
      "solverEvidence": true,
      "replayability": false,
      "kernelChecking": false
    }
  }
  let claimStr = $claimJson
  let solverInv = "solver-conflict"
  let certDigest = "cert-digest-conflict"
  let evidenceId = computeEvidenceId(claimStr, solverInv, certDigest)

  let tc = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claimStr,
    solverInvocation: solverInv,
    attestation: "attestation-conflict",
    certificateDigest: certDigest,
    scopeDigest: "scope-conflict",
    configDigest: "cfg-conflict",
    parentCommit: none(string)
  )
  let commitRes = commitVerification(base, tc)
  expect(commitRes.ok, "commitVerification ok for conflict test: " & (if commitRes.isErr: commitRes.error else: ""))

  # Write a conflicting raw vault cert with a DIFFERENT identityDigest
  let vaultIdentityDigest = sha256Hex("spec-vault|sem-vault|pol-vault")
  let vaultCertJson = %*{
    "schemaVersion": "2",
    "subjectId": subjectId,
    "outcome": "clDisproved",
    "specificationId": "spec-vault",
    "semanticProfileId": "sem-vault",
    "obligationId": "obl-vault",
    "evidenceId": "ev-vault",
    "dependencySnapshotId": "dep-vault",
    "policyId": "pol-vault",
    "identityDigest": vaultIdentityDigest,
    "assurance": {
      "specificationAuthority": false,
      "translationTrust": false,
      "solverEvidence": false,
      "replayability": false,
      "kernelChecking": false
    }
  }
  let vaultDir = base / ".axiom/vault"
  if not dirExists(vaultDir):
    createDir(vaultDir)
  writeFile(vaultDir / ("cert-" & subjectId & ".json"), $vaultCertJson)

  # locateCertFromJournal must return the journal cert (clProved), NOT the vault cert (clDisproved)
  let certOpt = locateCertFromJournal(base, subjectId)
  expect(certOpt.isSome, "locateCertFromJournal finds cert from journal even when vault has conflicting cert")
  if certOpt.isSome:
    let cert = certOpt.get()
    expect(cert.outcome == clProved, "journal cert outcome is clProved (not clDisproved from vault)")
    expect(cert.identityDigest == journalIdentityDigest, "journal cert identityDigest matches journal, not vault")
    expect(cert.specificationId == "spec-j2", "journal cert specificationId is from journal")

  # locateCert (public API) should also prefer journal
  let publicCertOpt = locateCert(base, subjectId)
  expect(publicCertOpt.isSome, "locateCert (public) finds cert from journal")
  if publicCertOpt.isSome:
    let publicCert = publicCertOpt.get()
    expect(publicCert.outcome == clProved, "public locateCert returns journal cert (clProved), not vault cert")

  echo "Test 2 PASSED: journal preferred over conflicting raw vault cert"

# --- 3. Missing journal returns none (non-breaking) ---
block:
  let base = tmpBase()
  # No journal directory exists
  let certOpt = locateCertFromJournal(base, "nonexistent-subject")
  expect(certOpt.isNone, "locateCertFromJournal returns none when journal directory absent")

  echo "Test 3 PASSED: missing journal returns none gracefully"

echo ""
if failures == 0:
  echo "=== All verify_cli journal lookup tests PASSED ==="
else:
  echo "=== " & $failures & " verify_cli journal lookup test(s) FAILED ==="
  quit(1)
