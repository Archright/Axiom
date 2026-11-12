import std/[json, os, strutils, unittest]
import ../../src/verification/certificate_eligibility
import ../../src/core/types/verification_tier
import ../../src/core/trusted/evidence_calculus
import ../../src/verification/certificate_identity

suite "CertificateEligibility aggregate":

  # ─── Helper: build a minimal valid v3 cert JSON ───────────────
  proc makeValidCert(status: string = "certGreen"): JsonNode =
    result = %* {
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "sourceHash": "sha256:abc123source",
      "irHash": "ir-hash-test-001",
      "leanProposition": "(assert true)",
      "solverStatus": "unsat",
      "status": status,
      "winningStrategy": "lean-replay",
      "inputHash": "sha256:abc123input",
      "solverInputDigest": "sha256:solverinput",
      "solverResultDigest": "sha256:solverresult",
      "identityDigest": "",  # filled below
      "claim": {"type": "verification", "status": status},
      "attestation": {"authority": "axiom", "policyVersion": "axiom.certificate.v3"},
      "provenance": {"journalCommitId": "commit-001"},
      "toolchainIdentity": {"axiomVersion": "v0.3.7", "nim": "2.2.10", "z3": "4.13.3", "lean": "4.29.0"},
      "solverInvocation": {"engine": "z3", "version": "4.13.3", "strategy": "lean-replay"},
      "smtlib2": "(assert true)",
      "kernel": true,  # production cert_writer always emits this (KAA-derived)
      "solverMeta": {"leanCompilerVerified": true, "leanKernelVerified": true}
    }
    # Compute and set identityDigest so verifyIdentityBinding passes
    let state = V3IdentityState(
      schemaVersion: "axiom.certificate.v3",
      modulePath: "src/test.nim",
      functionName: "testFn",
      sourceHash: "sha256:abc123source",
      irHash: "ir-hash-test-001",
      leanProposition: "(assert true)",
      solverStatus: "unsat",
      status: status,
      winningStrategy: "lean-replay",
      inputHash: "sha256:abc123input",
      solverInputDigest: "sha256:solverinput",
      solverResultDigest: "sha256:solverresult"
    )
    result["identityDigest"] = %* compV3Identity(state)

  # ─── aggregate: all required pass → ELIGIBLE ──────────────────
  test "aggregate passes when all required verifiers pass":
    let cert = makeValidCert()
    let results = @[
      VerifierResult(passed: true, verifier: "verifySemanticEvidence", reasons: @[]),
      VerifierResult(passed: true, verifier: "verifyIdentityBinding", reasons: @[]),
      VerifierResult(passed: true, verifier: "verifyCertificateCompleteness", reasons: @[])
    ]
    let policy = @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    let elig = aggregate(policy, results)
    check elig.eligible == true
    check elig.reasons.len == 0

  # ─── aggregate: one required fails → NOT_ELIGIBLE ─────────────
  test "aggregate is NOT eligible when one required verifier fails":
    let cert = makeValidCert()
    let results = @[
      VerifierResult(passed: true, verifier: "verifySemanticEvidence", reasons: @[]),
      VerifierResult(passed: false, verifier: "verifyIdentityBinding", reasons: @["identityDigest mismatch"]),
      VerifierResult(passed: true, verifier: "verifyCertificateCompleteness", reasons: @[])
    ]
    let policy = @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    let elig = aggregate(policy, results)
    check elig.eligible == false
    check elig.reasons.len > 0
    var foundIdentityReason = false
    for r in elig.reasons:
      if r.contains("verifyIdentityBinding"):
        foundIdentityReason = true
    check foundIdentityReason == true

  # ─── aggregate: non-required verifier failure is ignored ──────
  test "aggregate ignores failures from non-required verifiers":
    let cert = makeValidCert()
    let results = @[
      VerifierResult(passed: true, verifier: "verifySemanticEvidence", reasons: @[]),
      VerifierResult(passed: false, verifier: "verifyProofArtifact", reasons: @["NOT_APPLICABLE"]),
      VerifierResult(passed: true, verifier: "verifyIdentityBinding", reasons: @[]),
      VerifierResult(passed: true, verifier: "verifyCertificateCompleteness", reasons: @[])
    ]
    # policy does not include verifyProofArtifact → its failure is ignored
    let policy = @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    let elig = aggregate(policy, results)
    check elig.eligible == true

  # ─── aggregate: empty policy → ELIGIBLE ───────────────────────
  test "aggregate with empty policy is ELIGIBLE":
    let results = @[
      VerifierResult(passed: false, verifier: "verifySemanticEvidence", reasons: @["fail"])
    ]
    let policy: seq[string] = @[]
    let elig = aggregate(policy, results)
    check elig.eligible == true

  # ─── tamper test: flip identityDigest → NOT_ELIGIBLE ─────────
  test "tamper test: flipped identityDigest makes promotion rejected":
    let cert = makeValidCert()
    # Flip the identityDigest to simulate tampering
    cert["identityDigest"] = %* "sha256:tampered-digest"
    let results = @[
      verifySemanticEvidence(cert),
      verifyIdentityBinding(cert),
      verifyCertificateCompleteness(cert)
    ]
    let policy = @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    let elig = aggregate(policy, results)
    check elig.eligible == false
    var foundIdentityReason2 = false
    for r in elig.reasons:
      if r.contains("verifyIdentityBinding"):
        foundIdentityReason2 = true
    check foundIdentityReason2 == true

  # ─── aggregate performs no verification (pure reducer test) ──
  test "aggregate performs no verification — only combines precomputed results":
    # This test feeds arbitrary precomputed results and asserts aggregate
    # never reads evidence or computes digests. It only combines results.
    let results = @[
      VerifierResult(passed: true, verifier: "verifySemanticEvidence", reasons: @["precomputed-pass"]),
      VerifierResult(passed: false, verifier: "verifyAcceptance", reasons: @["precomputed-fail: acceptance missing"])
    ]
    let policy = @["verifySemanticEvidence", "verifyAcceptance"]
    let elig = aggregate(policy, results)
    check elig.eligible == false
    check elig.reasons.len == 1
    check elig.reasons[0].contains("verifyAcceptance")
    check elig.reasons[0].contains("precomputed-fail")

  # ─── verifySemanticEvidence: valid dual evidence → pass ──────
  test "verifySemanticEvidence passes for certGreen with dual evidence":
    let cert = makeValidCert("certGreen")
    let result = verifySemanticEvidence(cert)
    check result.passed == true

  # ─── verifySemanticEvidence: no evidence → fail ──────────────
  test "verifySemanticEvidence fails when no Z3 or Lean evidence":
    let cert = makeValidCert("certGreen")
    # Override solverStatus to something that yields no evidence
    cert["solverStatus"] = %* "unknown"
    cert["smtlib2"] = %* ""
    cert["solverMeta"] = %* {"leanCompilerVerified": false, "leanKernelVerified": false}
    let result = verifySemanticEvidence(cert)
    check result.passed == false

  # ─── verifyProofArtifact: always NOT_APPLICABLE ──────────────
  test "verifyProofArtifact returns NOT_APPLICABLE in v1":
    let cert = makeValidCert()
    let result = verifyProofArtifact(cert)
    check result.passed == false
    check result.reasons.len == 1
    check result.reasons[0].contains("NOT_APPLICABLE")
    check result.reasons[0].contains("no real proof artifact in v1")

  # ─── verifyCertificateCompleteness: all fields present → pass ─
  test "verifyCertificateCompleteness passes for complete v3 cert":
    let cert = makeValidCert()
    let result = verifyCertificateCompleteness(cert)
    check result.passed == true

  # ─── verifyCertificateCompleteness: missing field → fail ─────
  test "verifyCertificateCompleteness fails when required field is missing":
    let cert = makeValidCert()
    # Construct a cert without modulePath by building a new JSON object
    let incompleteCert = %* {
      "schemaVersion": "axiom.certificate.v3",
      "functionName": "testFn",
      "sourceHash": "sha256:abc123source",
      "irHash": "ir-hash-test-001",
      "leanProposition": "(assert true)",
      "solverStatus": "unsat",
      "status": "certGreen",
      "winningStrategy": "lean-replay",
      "inputHash": "sha256:abc123input",
      "solverInputDigest": "sha256:solverinput",
      "solverResultDigest": "sha256:solverresult",
      "identityDigest": cert["identityDigest"].getStr(),
      "claim": {"type": "verification", "status": "certGreen"},
      "attestation": {"authority": "axiom", "policyVersion": "axiom.certificate.v3"},
      "provenance": {"journalCommitId": "commit-001"},
      "toolchainIdentity": {"axiomVersion": "v0.3.7", "nim": "2.2.10", "z3": "4.13.3", "lean": "4.29.0"},
      "solverInvocation": {"engine": "z3", "version": "4.13.3", "strategy": "lean-replay"},
      "smtlib2": "(assert true)"
    }
    let result = verifyCertificateCompleteness(incompleteCert)
    check result.passed == false
    var foundModulePath = false
    for r in result.reasons:
      if r.contains("modulePath"):
        foundModulePath = true
    check foundModulePath == true

  # ─── verifyCertificateCompleteness: empty string field → fail ─
  test "verifyCertificateCompleteness fails when required field is empty":
    let cert = makeValidCert()
    cert["functionName"] = %* ""
    let result = verifyCertificateCompleteness(cert)
    check result.passed == false
    var foundFunctionName = false
    for r in result.reasons:
      if r.contains("functionName"):
        foundFunctionName = true
    check foundFunctionName == true

  # ─── verifyCertificateCompleteness: certGreen without winningStrategy → fail ──
  test "verifyCertificateCompleteness fails for certGreen without winningStrategy":
    let cert = makeValidCert()
    let incompleteCert = %* {
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "sourceHash": "sha256:abc123source",
      "irHash": "ir-hash-test-001",
      "leanProposition": "(assert true)",
      "solverStatus": "unsat",
      "status": "certGreen",
      "inputHash": "sha256:abc123input",
      "solverInputDigest": "sha256:solverinput",
      "solverResultDigest": "sha256:solverresult",
      "identityDigest": cert["identityDigest"].getStr(),
      "claim": {"type": "verification", "status": "certGreen"},
      "attestation": {"authority": "axiom", "policyVersion": "axiom.certificate.v3"},
      "provenance": {"journalCommitId": "commit-001"},
      "toolchainIdentity": {"axiomVersion": "v0.3.7", "nim": "2.2.10", "z3": "4.13.3", "lean": "4.29.0"},
      "solverInvocation": {"engine": "z3", "version": "4.13.3", "strategy": "lean-replay"},
      "smtlib2": "(assert true)"
    }
    let result = verifyCertificateCompleteness(incompleteCert)
    check result.passed == false

  # ─── verifyIdentityBinding: matching digest → pass ───────────
  test "verifyIdentityBinding passes when identityDigest matches":
    let cert = makeValidCert()
    let result = verifyIdentityBinding(cert)
    check result.passed == true

  # ─── verifyIdentityBinding: mismatched digest → fail ─────────
  test "verifyIdentityBinding fails when identityDigest does not match":
    let cert = makeValidCert()
    cert["identityDigest"] = %* "sha256:wrong-digest"
    let result = verifyIdentityBinding(cert)
    check result.passed == false

  # ─── verifyIdentityBinding: missing identityDigest → fail ────
  test "verifyIdentityBinding fails when identityDigest is missing":
    let cert = makeValidCert()
    let incompleteCert = %* {
      "schemaVersion": "axiom.certificate.v3",
      "modulePath": "src/test.nim",
      "functionName": "testFn",
      "sourceHash": "sha256:abc123source",
      "irHash": "ir-hash-test-001",
      "leanProposition": "(assert true)",
      "solverStatus": "unsat",
      "status": "certGreen",
      "winningStrategy": "lean-replay",
      "inputHash": "sha256:abc123input",
      "solverInputDigest": "sha256:solverinput",
      "solverResultDigest": "sha256:solverresult",
      "claim": {"type": "verification", "status": "certGreen"},
      "attestation": {"authority": "axiom", "policyVersion": "axiom.certificate.v3"},
      "provenance": {"journalCommitId": "commit-001"},
      "toolchainIdentity": {"axiomVersion": "v0.3.7", "nim": "2.2.10", "z3": "4.13.3", "lean": "4.29.0"},
      "solverInvocation": {"engine": "z3", "version": "4.13.3", "strategy": "lean-replay"},
      "smtlib2": "(assert true)"
    }
    let result = verifyIdentityBinding(incompleteCert)
    check result.passed == false

  # ─── hasSemanticEvidence: dual evidence → true ──────────────
  test "hasSemanticEvidence returns true for certGreen with dual evidence":
    let cert = makeValidCert("certGreen")
    check hasSemanticEvidence(cert) == true

  # ─── hasSemanticEvidence: Z3-only evidence → true ────────────
  test "hasSemanticEvidence returns true for certZ3Candidate with Z3 evidence":
    let cert = makeValidCert("certZ3Candidate")
    # Override solverMeta to indicate Z3 passed but Lean not verified
    cert["solverMeta"] = %* {"leanCompilerVerified": false, "leanKernelVerified": false}
    cert["solverStatus"] = %* "unsat"
    cert["smtlib2"] = %* "(assert true)"
    check hasSemanticEvidence(cert) == true

  # ─── hasSemanticEvidence: no evidence → false ────────────────
  test "hasSemanticEvidence returns false when no Z3 or Lean evidence":
    let cert = makeValidCert("certGreen")
    cert["solverStatus"] = %* "unknown"
    cert["smtlib2"] = %* ""
    cert["solverMeta"] = %* {"leanCompilerVerified": false, "leanKernelVerified": false}
    check hasSemanticEvidence(cert) == false

  # ─── hasSemanticEvidence: Lean-only evidence → true ──────────
  test "hasSemanticEvidence returns true for certLeanVerified with Lean evidence":
    let cert = makeValidCert("certLeanVerified")
    cert["solverMeta"] = %* {"leanCompilerVerified": true, "leanKernelVerified": true}
    cert["solverStatus"] = %* "unknown"
    cert["smtlib2"] = %* ""
    cert["kernel"] = newJBool(true)
    check hasSemanticEvidence(cert) == true

  # ─── hasSemanticEvidence: nil cert → false ───────────────────
  test "hasSemanticEvidence returns false for nil certificate":
    check hasSemanticEvidence(nil) == false

  # ─── hasSemanticEvidence: non-object cert → false ────────────
  test "hasSemanticEvidence returns false for non-object certificate":
    let cert = %* "not-an-object"
    check hasSemanticEvidence(cert) == false