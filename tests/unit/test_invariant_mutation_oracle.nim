import std/[json, os, strutils, unittest]
import ../../src/core/types/verification_tier
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/trust_commit
import ../../src/core/proof/source_fingerprint
import ../../src/verification/certificate_verifier
import ../../src/verification/certificate_identity

# ═══════════════════════════════════════════════════════════════
# Oracle Suite A — verified⇒evidence invariant
#   statusConsistentWithEvidence must reject certGreen without
#   dual Z3∧Lean evidence.  Mutant A weakens this check so a
#   certGreen-without-evidence passes.  This suite must FAIL
#   when mutant A is injected.
# ═══════════════════════════════════════════════════════════════

suite "Oracle A — verified⇒evidence invariant (statusConsistentWithEvidence)":

  test "certGreen without Z3 and Lean evidence is rejected":
    ## A certGreen status with no evidence fields must fail the
    ## P0 invariant.  statusConsistentWithEvidence returns false
    ## for certGreen unless both z3Passed and leanVerified are true.
    let badCert = %*{
      "status": "certGreen",
      "reason": "z3-verified",
      "verificationTier": "dual-verified",
      "sourceHash": "sha256:fixture-input",
      "irHash": "ir-hash-test-001",
      "solverStatus": "unsat",
      "policyId": "policy-test-1",
      "modulePath": "module_target.nim",
      "functionName": "probe",
      "solverMeta": %*{}
    }
    check statusConsistentWithEvidence(badCert) == false

# ═══════════════════════════════════════════════════════════════
# Oracle Suite B — identityDigest binding invariant
#   verifyCertificateClosure must reject a cert whose stored
#   identityDigest does not match the recomputed v3 identity.
#   Mutant B weakens the comparison so a tampered digest passes.
#   This suite must FAIL when mutant B is injected.
# ═══════════════════════════════════════════════════════════════

suite "Oracle B — identityDigest binding invariant":

  test "tampered identityDigest is rejected (ccsIdentityDigestMismatch)":
    let tmpDir = getTempDir() / "ax_oracle_b_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      let modulePath = "module_target.nim"
      let sourceContent = "proc probe(x: int): int = x + 1"
      writeFile(tmpDir / modulePath, sourceContent)
      let irHash = "ir-hash-test-001"
      let solverStatus = "unsat"
      var cert = %*{
        "modulePath": modulePath,
        "functionName": "probe",
        "fingerprint": computeVerificationFingerprint(irHash, ""),
        "sourceHash": computeStableSourceFingerprint(sourceContent),
        "trusted": true,
        "status": "certGreen",
        "reason": "z3-verified",
        "claimId": "claim-test-1",
        "specificationId": "spec-test-1",
        "policyId": "policy-test-1",
        "schemaVersion": "1",
        "kernel": true,
        "solverStatus": solverStatus,
        "winningStrategy": "lean-replay",
        "solverMeta": %*{
          "leanCompilerVerified": true,
          "negativeTestResult": false,
          "vacuityChecked": true,
          "vacuityProven": true,
          "solverVersion": "4.13.3",
          "solverProvenance": "spZ3SAT",
          "z3Executed": true
        },
        "verificationTier": "dual-verified",
        "leanProposition": "",
        "smtlib2": "(assert true)",
        "irHash": irHash,
        "translationVersion": "axiom-ir-smt-v1",
        "inputHash": "sha256:fixture-input",
        "solverInputDigest": "sha256:fixture-sinput",
        "solverResultDigest": "sha256:fixture-sresult"
      }
      cert["identityDigest"] = newJString(v3IdentityFromJson(cert))
      let commitRes = commitVerification(tmpDir, certificateTrustCommit(
        cert, modulePath, "probe", solverStatus, irHash, "", ""))
      check commitRes.ok
      cert["trustCommitId"] = newJString(commitRes.value)

      # Tamper with identityDigest: set it to a wrong value.
      cert["identityDigest"] = newJString("tampered-digest-value")
      let certPath = tmpDir / "cert_probe.json"
      writeFile(certPath, $cert)

      let res = verifyCertificateClosure(certPath, tmpDir)
      check res.status == ccsIdentityDigestMismatch
    finally:
      removeDir(tmpDir)

# ═══════════════════════════════════════════════════════════════
# Oracle Suite C — validateCommit structural fail-closed invariant
#   validateCommit must reject empty/tampered TrustCommit records.
#   Mutant C weakens validateCommit so it always returns ok().
#   This suite must FAIL when mutant C is injected.
# ═══════════════════════════════════════════════════════════════

suite "Oracle C — validateCommit structural fail-closed invariant":

  test "empty TrustCommit is rejected by validateCommit":
    let emptyCommit = TrustCommit(kind: tcVerifiedProof)
    let result = validateCommit(emptyCommit)
    check not result.ok

  test "TrustCommit with mismatched evidenceId is rejected":
    let tampered = TrustCommit(
      kind: tcVerifiedProof,
      evidenceId: "wrong-evidence-id",
      claim: "{}",
      solverInvocation: "{}",
      attestation: "attest",
      certificateDigest: "sha256:digest",
      scopeDigest: "scope-digest",
      configDigest: "config-digest"
    )
    let result = validateCommit(tampered)
    check not result.ok

  test "valid TrustCommit is accepted by validateCommit":
    let valid = TrustCommit(
      kind: tcVerifiedProof,
      evidenceId: computeEvidenceId("{}", "{}", "sha256:digest"),
      claim: "{}",
      solverInvocation: "{}",
      attestation: "attest",
      certificateDigest: "sha256:digest",
      scopeDigest: "scope-digest",
      configDigest: "config-digest"
    )
    let result = validateCommit(valid)
    check result.ok
