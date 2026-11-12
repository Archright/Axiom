import std/[json, os, strutils, unittest]
import ../../src/verification/cert_writer
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/trust_commit
import ../../src/core/crypto/hash_kernel
import ../../src/core/proof/source_fingerprint
import ../../src/core/release/version_derive
import ../../src/core/types/verification_tier
import ../../src/verification/cert_vault_role
import ../../src/verification/cert_promotion

suite "Phase 2 — Certificate v3 writer (cert_writer.nim)":

  proc readEmittedCert(certDir, irHash: string): JsonNode =
    ## Read the emitted portable certificate projection file (irHash.json).
    ## The projection file carries the fully bound certificate (attestation +
    ## provenance populated after the journal commit resolves).
    parseFile(joinPath(certDir, irHash & ".json"))

  test "v3 fields present and correct in emitted certificate":
    let tmpDir = getTempDir() / "ax_v3_cert_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      let modulePath = "module_v3_test.nim"
      let functionName = "probeV3"
      let sourceCode = "proc probeV3(x: int): int = x + 1"
      let irHash = "ir-hash-v3-test-001"
      let leanProposition = "(assert true)"
      let smtlib2 = "(assert true)"
      let solverStatus = "unsat"
      var logLines: seq[string] = @[]

      setPromotionActive()
      defer: clearPromotionActive()

      let ok = writeCertificateFromUapResult(
        tmpDir, modulePath, functionName, sourceCode,
        leanKernelVerified = true,
        smtlib2 = smtlib2,
        solverStatus = solverStatus,
        logLines = logLines,
        vacuityProven = true,
        irHash = irHash,
        leanProposition = leanProposition,
        semanticProfileId = "test-profile"
      )
      check ok

      let certJson = readEmittedCert(tmpDir, irHash)

      # schemaVersion
      check certJson["schemaVersion"].getStr() == "axiom.certificate.v3"

      # claim
      let claim = certJson["claim"]
      check claim.kind == JObject
      check claim["type"].getStr() == "verification"
      check claim["status"].getStr() == "certGreen"
      check claim["modulePath"].getStr() == modulePath
      check claim["functionName"].getStr() == functionName

      # attestation
      let attestation = certJson["attestation"]
      check attestation.kind == JObject
      check attestation["authority"].getStr() == "axiom"
      check attestation["policyVersion"].getStr() == "axiom.certificate.v3"
      check attestation["claimDigest"].getStr().startsWith("sha256:")
      check attestation["claimDigest"].getStr().len > 7
      check attestation["journalRef"].getStr().len > 0

      # inputHash
      let inputHash = certJson["inputHash"].getStr()
      check inputHash.startsWith("sha256:")
      let expectedInputHashRaw = join([
        "modulePath", modulePath,
        "functionName", functionName,
        "sourceHash", computeStableSourceFingerprint(sourceCode),
        "irHash", irHash
      ], "\x1f")
      check inputHash == "sha256:" & hash_kernel.sha256Hex(expectedInputHashRaw)

      # toolchainIdentity
      let toolchain = certJson["toolchainIdentity"]
      check toolchain.kind == JObject
      check toolchain["axiomVersion"].getStr() == axiomVersionWithPrefix
      check toolchain["nim"].getStr() == "2.2.10"
      check toolchain["z3"].getStr() == "4.13.3"
      # Canonical toolchain pin (proofs/lean-toolchain: leanprover/lean4:v4.33.0);
      # the writer records the pinned version, so the fixture must track it.
      check toolchain["lean"].getStr() == "4.33.0"

      # solverInvocation
      let solverInv = certJson["solverInvocation"]
      check solverInv.kind == JObject
      check solverInv["engine"].getStr() == "z3"
      check solverInv["version"].getStr() == "4.13.3"
      check solverInv["strategy"].getStr() == "lean-replay"
      check solverInv["mode"].getStr() == "lean-replay"

      # solverInputDigest
      let solverInputDigest = certJson["solverInputDigest"].getStr()
      check solverInputDigest.startsWith("sha256:")
      check solverInputDigest == "sha256:" & hash_kernel.sha256Hex(smtlib2)

      # solverResultDigest
      let solverResultDigest = certJson["solverResultDigest"].getStr()
      check solverResultDigest.startsWith("sha256:")

      # proofDigest: must be absent
      check not certJson.hasKey("proofDigest")

      # provenance
      let provenance = certJson["provenance"]
      check provenance.kind == JObject
      check provenance["journalCommitId"].getStr().len > 0
      check provenance["certificateDigest"].getStr() == certJson["identityDigest"].getStr()

      # identityDigest is present and non-empty
      check certJson["identityDigest"].getStr().len > 0

      # All original fields still present
      check certJson["modulePath"].getStr() == modulePath
      check certJson["functionName"].getStr() == functionName
      check certJson["sourceHash"].getStr().len > 0
      check certJson["irHash"].getStr() == irHash
      check certJson["trusted"].getBool() == true
      # DECISION-0630 canonical evidence contract: KAA-less dual (raw lean flag
      # without a genuine KAA/kernel receipt cannot set kernel=true) is
      # P0-inconsistent with certGreen — the writer's
      # statusConsistentWithEvidence demotion emits the honest tier status
      # certZ3Candidate (z3Passed ∧ ¬leanVerified) with reason
      # "evidence-corrected". Status follows P0; only winningStrategy/
      # verificationTier carry the A2-gated promotion.
      check certJson["status"].getStr() == "certZ3Candidate"
      check certJson["kernel"].getBool() == false  # probeV3 is not a kernel function
      check certJson["solverStatus"].getStr() == solverStatus
      check certJson["winningStrategy"].getStr() == "lean-replay"
      check certJson["leanProposition"].getStr() == leanProposition
      check certJson["smtlib2"].getStr() == smtlib2
      check certJson["trustCommitId"].getStr().len > 0
    finally:
      removeDir(tmpDir)

  test "v3 deterministic: identical inputs produce identical identityDigest":
    let tmpDir1 = getTempDir() / "ax_v3_det1_" & $getCurrentProcessId()
    let tmpDir2 = getTempDir() / "ax_v3_det2_" & $getCurrentProcessId()
    createDir(tmpDir1)
    createDir(tmpDir2)
    try:
      let modulePath = "module_det_test.nim"
      let functionName = "probeDet"
      let sourceCode = "proc probeDet(x: int): int = x + 1"
      let irHash = "ir-hash-det-test-001"
      let leanProposition = "(assert true)"
      let smtlib2 = "(assert true)"
      let solverStatus = "unsat"

      var logLines1: seq[string] = @[]
      var logLines2: seq[string] = @[]

      setPromotionActive()
      defer: clearPromotionActive()

      let ok1 = writeCertificateFromUapResult(
        tmpDir1, modulePath, functionName, sourceCode,
        leanKernelVerified = true,
        smtlib2 = smtlib2,
        solverStatus = solverStatus,
        logLines = logLines1,
        vacuityProven = true,
        irHash = irHash,
        leanProposition = leanProposition
      )
      check ok1

      let ok2 = writeCertificateFromUapResult(
        tmpDir2, modulePath, functionName, sourceCode,
        leanKernelVerified = true,
        smtlib2 = smtlib2,
        solverStatus = solverStatus,
        logLines = logLines2,
        vacuityProven = true,
        irHash = irHash,
        leanProposition = leanProposition
      )
      check ok2

      let cert1 = readEmittedCert(tmpDir1, irHash)
      let cert2 = readEmittedCert(tmpDir2, irHash)

      check cert1["identityDigest"].getStr() == cert2["identityDigest"].getStr()
    finally:
      removeDir(tmpDir1)
      removeDir(tmpDir2)

  test "v3 proofDigest is absent (not null, not empty string)":
    let tmpDir = getTempDir() / "ax_v3_noproof_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      let modulePath = "module_noproof.nim"
      let functionName = "probeNoProof"
      let sourceCode = "proc probeNoProof(x: int): int = x"
      let irHash = "ir-hash-noproof-001"
      var logLines: seq[string] = @[]

      setPromotionActive()
      defer: clearPromotionActive()

      let ok = writeCertificateFromUapResult(
        tmpDir, modulePath, functionName, sourceCode,
        leanKernelVerified = false,
        smtlib2 = "",
        solverStatus = "unknown",
        logLines = logLines,
        irHash = irHash,
        leanProposition = ""
      )
      check ok

      let certJson = readEmittedCert(tmpDir, irHash)
      check not certJson.hasKey("proofDigest")
    finally:
      removeDir(tmpDir)
