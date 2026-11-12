import std/[json, os, strutils, unittest]
import ../../src/core/types/verification_tier
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/trust_commit
import ../../src/core/proof/source_fingerprint
import ../../src/verification/certificate_verifier
import ../../src/verification/certificate_identity

suite "Phase 2 — Certificate trust closure (R4, v1 local replay-bound contract)":

  proc makeFixtureCert(tmp: string): (string, JsonNode, string) =
    ## Build a KAA-less z3-verified cert (current canonical vocabulary:
    ## status=certZ3Candidate, kernel=false — DECISION-0630: persistent
    ## kernel=true comes only from a real KernelAcceptanceAttestation via
    ## bindReceipt, so a hand-built fixture must not claim it) + journal
    ## commit; returns (certPath, certNode, sourceContent).
    let modulePath = "module_target.nim"
    let sourceContent = "proc probe(x: int): int = x + 1"
    writeFile(tmp / modulePath, sourceContent)
    let irHash = "ir-hash-test-001"
    let solverStatus = "unsat"
    var cert = %*{
      "modulePath": modulePath,
      "functionName": "probe",
      "fingerprint": computeVerificationFingerprint(irHash, ""),
      "sourceHash": computeStableSourceFingerprint(sourceContent),
      "trusted": true,
      "status": "certZ3Candidate",
      "reason": "z3-verified",
      "claimId": "claim-test-1",
      "specificationId": "spec-test-1",
      "policyId": "policy-test-1",
      "schemaVersion": "1",
      "kernel": false,
      "solverStatus": solverStatus,
      "winningStrategy": "none",
      "solverMeta": %*{
        "leanCompilerVerified": true,
        "negativeTestResult": false,
        "vacuityChecked": true,
        "vacuityProven": true,
        "solverVersion": "4.13.3",
        "solverProvenance": "spZ3SAT",
        "z3Executed": true
      },
      "verificationTier": "z3-verified",
      "leanProposition": "",
      "smtlib2": "(assert true)",
      "irHash": irHash,
      "translationVersion": "axiom-ir-smt-v1",
      "inputHash": "sha256:fixture-input",
      "solverInputDigest": "sha256:fixture-sinput",
      "solverResultDigest": "sha256:fixture-sresult"
    }
    # identityDigest via the SHARED canonical v3 semantic-state function —
    # must equal what verifyCertificateClosure recomputes (v3IdentityFromJson).
    cert["identityDigest"] = newJString(v3IdentityFromJson(cert))
    let commitRes = commitVerification(tmp, certificateTrustCommit(
      cert, modulePath, "probe", solverStatus, irHash, "", ""))
    check commitRes.ok
    cert["trustCommitId"] = newJString(commitRes.value)
    let certPath = tmp / "cert_probe.json"
    writeFile(certPath, $cert)
    (certPath, cert, sourceContent)

  template withHermeticJournalRoot(tmpDir: string; body: untyped) =
    ## cert_lifecycle_contracts.md §5 dual-root rule: the closure's journal leg
    ## (trustCommitId) ALWAYS resolves at the product repo root, while the
    ## source-staleness leg reads `projectRoot`. Inject this test's tmpDir as
    ## the product root (AXIOM_ROOT) so the minted journal under tmpDir is the
    ## one the closure resolves — same idiom as
    ## tests/unit/test_certificate_lifecycle_v3_test.nim.
    let origAxiomRoot = getEnv("AXIOM_ROOT", "")
    putEnv("AXIOM_ROOT", tmpDir)
    try:
      body
    finally:
      if origAxiomRoot.len > 0: putEnv("AXIOM_ROOT", origAxiomRoot)
      else: delEnv("AXIOM_ROOT")

  test "valid cert + journal -> PASS, replayMatched=true":
    let tmpDir = getTempDir() / "ax_p2_valid_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsPass
        check res.replayMatched == true
        check res.semanticHash.len > 0
    finally:
      removeDir(tmpDir)

  test "tampered cert (evidence field) -> FAIL":
    let tmpDir = getTempDir() / "ax_p2_tamper_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        cert["solverStatus"] = newJString("unsat")
        cert["winningStrategy"] = newJString("none")
        # tamper: flip solverMeta evidence post-commit — identityDigest untouched.
        # solverMeta is NOT one of the 13 identity fields (certificate_identity
        # V3IdentityState), so the closure contract stage that must catch this is
        # the journal replay-equality leg: the committed journal claim still
        # carries the original solverMeta projection.
        cert["solverMeta"]["leanCompilerVerified"] = newJBool(false)
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsReplayMismatch
    finally:
      removeDir(tmpDir)

  test "journal missing -> JOURNAL_REQUIRED":
    let tmpDir = getTempDir() / "ax_p2_journal_missing_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        # break the journal: delete the commit file from the hermetic product
        # root journal (the only root the closure's journal leg resolves at)
        let journal = journalDir(tmpDir)
        for kind, path in walkDir(journal):
          if kind == pcFile and path.endsWith(".json"):
            removeFile(path)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsJournalRequired
    finally:
      removeDir(tmpDir)

  test "cert without trustCommitId -> JOURNAL BINDING ABSENT":
    let tmpDir = getTempDir() / "ax_p2_nobinding_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        cert.delete("trustCommitId")
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsJournalBindingAbsent
    finally:
      removeDir(tmpDir)
