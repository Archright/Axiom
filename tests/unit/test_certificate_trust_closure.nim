import std/[json, os, strutils, unittest]
import ../../src/core/crypto/hash_kernel
import ../../src/core/types/verification_tier
import ../../src/core/proof/proof_budget
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/trust_commit
import ../../src/core/trusted/solver_invocation
import ../../src/core/proof/source_fingerprint
import ../../src/verification/certificate_verifier
import ../../src/verification/certificate_identity
import ../../src/verification/kernel_reexecution

suite "Phase 2 — Certificate trust closure (R4, v1 local replay-bound contract)":

  proc fixtureObservation(leanSource, smtlib2: string): KernelObservation =
    ## A self-consistent dual-kernel pass bound to the given sources. The
    ## closure verifies the recorded observation; it never executes kernels.
    KernelObservation(
      lean: LeanObservation(
        observed: true,
        theoremName: "probe_spec",
        axiomSet: @[],
        verdict: krPassed,
        leanSourceDigest: sha256Hex(leanSource),
        outputDigest: sha256Hex("closure-lean-output"),
        toolchainIdentity: "lean:test;checker:sha256:" & sha256Hex("test-checker"),
        skippedChecks: @[]),
      z3: Z3Observation(
        observed: true,
        queryDigest: sha256Hex(smtlib2),
        outputDigest: sha256Hex("closure-z3-output"),
        verdict: krPassed,
        optionsDigest: deterministicSolverOptionsDigest(),
        binaryDigest: sha256Hex("closure-z3-binary"),
        randomSeed: Z3PinnedRandomSeed,
        rlimit: z3DeterministicBudget,
        timeoutMs: z3SafetyNetMs),
      verificationMode: "lean+z3")

  proc makeFixtureCert(tmp: string; status = "certZ3Candidate";
                       leanSource = ""; observation: JsonNode = nil;
                       observationDigest = ""): (string, JsonNode, string) =
    ## Build a KAA-less z3-verified cert (current canonical vocabulary:
    ## status=certZ3Candidate, kernel=false — DECISION-0630: persistent
    ## kernel=true comes only from a real KernelAcceptanceAttestation via
    ## bindReceipt, so a hand-built fixture must not claim it) + journal
    ## commit; returns (certPath, certNode, sourceContent). A certGreen
    ## fixture must carry an observation bound to leanSource/smtlib2.
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
      "status": status,
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
    # leanSource is a v3 identity field: it must be present BEFORE the
    # identityDigest is derived.
    if leanSource.len > 0:
      cert["leanSource"] = newJString(leanSource)
    if not observation.isNil:
      cert["observation"] = observation
      cert["observationDigest"] = newJString(observationDigest)
    # A certGreen claim is a dual-verified claim: the fixture must carry the
    # kernel bit its status asserts (the P0 invariant gate rejects a
    # certGreen whose stored evidence says kernel=false).
    if status == "certGreen":
      cert["kernel"] = newJBool(true)
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

  test "certGreen without observation -> NOT deep-verified":
    let tmpDir = getTempDir() / "ax_p2_noobs_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir, status = "certGreen")
        check cert["status"].getStr == "certGreen"
        # VS-188 scope: the observation requirement binds subject-continuity
        # certificates. A legacy-shaped cert (no kind) keeps the old closure
        # semantics; this test exercises the subject contract.
        cert["kind"] = newJString("subject-continuity")
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsNotDeepVerified
    finally:
      removeDir(tmpDir)

  test "tampered observation block -> replay input mismatch":
    let tmpDir = getTempDir() / "ax_p2_obs_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let leanSource = "theorem probe_spec : True := by trivial"
        let obs = fixtureObservation(leanSource, "(assert true)")
        let (certPath, cert, _) = makeFixtureCert(tmpDir, status = "certGreen",
          leanSource = leanSource, observation = kernelObservationJson(obs),
          observationDigest = kernelObservationDigest(obs))
        # control: the observed certGreen replays cleanly
        let baseline = verifyCertificateClosure(certPath, tmpDir)
        check baseline.status == ccsPass
        # tamper ONLY the signed observation: identityDigest covers no
        # observation field, so the replay-input gate is the discriminating
        # stage that must catch it.
        cert["observation"]["lean"]["theoremName"] = newJString("other_spec")
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status == ccsReplayInputMismatch
    finally:
      removeDir(tmpDir)

  test "#246: swapped leanProposition -> FAIL (semantics are replay identity)":
    let tmpDir = getTempDir() / "ax_p2_prop_swap_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        # Keep every input hash intact; replace only the claimed proposition.
        cert["leanProposition"] = newJString("True")
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status != ccsPass
        check res.status == ccsNotDeepVerified
    finally:
      removeDir(tmpDir)

  test "#246: swapped leanSource -> FAIL (proof body is replay identity)":
    let tmpDir = getTempDir() / "ax_p2_src_swap_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        cert["leanSource"] = newJString("theorem normalizeMaxWorkers : True := by trivial")
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status != ccsPass
        check res.status == ccsReplayMismatch
    finally:
      removeDir(tmpDir)

  test "#246: swapped propositionHash -> FAIL (input digests are replay inputs)":
    let tmpDir = getTempDir() / "ax_p2_phash_swap_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let (certPath, cert, _) = makeFixtureCert(tmpDir)
        cert["propositionHash"] = newJString(repeat('a', 64))
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status != ccsPass
        check res.status == ccsReplayInputMismatch
    finally:
      removeDir(tmpDir)

  test "#246: swapped proposition and Lean source together with recomputed hashes -> FAIL":
    let tmpDir = getTempDir() / "ax_p2_both_swap_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let leanSource = "theorem probe_spec : True := by trivial"
        let obs = fixtureObservation(leanSource, "(assert true)")
        let (certPath, cert, _) = makeFixtureCert(tmpDir, status = "certGreen",
          leanSource = leanSource, observation = kernelObservationJson(obs),
          observationDigest = kernelObservationDigest(obs))
        let baseline = verifyCertificateClosure(certPath, tmpDir)
        check baseline.status == ccsPass
        let fakeProp = "True"
        let fakeSource = "theorem fake_spec : True := by trivial"
        let fakeObs = fixtureObservation(fakeSource, "(assert true)")
        cert["leanProposition"] = newJString(fakeProp)
        cert["propositionHash"] = newJString(sha256Hex(fakeProp))
        cert["leanSource"] = newJString(fakeSource)
        cert["leanSourceHash"] = newJString(sha256Hex(fakeSource))
        cert["observation"] = kernelObservationJson(fakeObs)
        cert["observationDigest"] = newJString(kernelObservationDigest(fakeObs))
        cert["identityDigest"] = newJString(v3IdentityFromJson(cert))
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status != ccsPass
        check res.status == ccsNotDeepVerified
    finally:
      removeDir(tmpDir)

  test "#246: swapped propositionHash and leanSourceHash -> FAIL (replay input mismatch)":
    let tmpDir = getTempDir() / "ax_p2_hashes_swap_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let leanSource = "theorem probe_spec : True := by trivial"
        let obs = fixtureObservation(leanSource, "(assert true)")
        let (certPath, cert, _) = makeFixtureCert(tmpDir, status = "certGreen",
          leanSource = leanSource, observation = kernelObservationJson(obs),
          observationDigest = kernelObservationDigest(obs))
        let baseline = verifyCertificateClosure(certPath, tmpDir)
        check baseline.status == ccsPass
        cert["propositionHash"] = newJString(repeat('a', 64))
        cert["leanSourceHash"] = newJString(repeat('b', 64))
        writeFile(certPath, $cert)
        let res = verifyCertificateClosure(certPath, tmpDir)
        check res.status != ccsPass
        check res.status == ccsReplayInputMismatch
    finally:
      removeDir(tmpDir)
