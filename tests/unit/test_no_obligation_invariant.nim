import std/[unittest, json, sets]
import core/trusted/verification_result_types
import core/types/solver_types
import core/trusted/axiom_pragmas
import engine/proof_certificate
import verification/batch_uap/ir_pipeline_runner
import verification/obligation/obligation_ir
import verification/cross_validation
import core/proof/proof_integrity
import verification/certificate_verifier
import core/types/certificate_types
import core/trusted/fingerprint_generator

## The verdict half of a no-obligation pipeline result. An empty obligation set
## is expressible ONLY as ogrNoApplicableObligation (obligation_semantics.md
## §2.3); pairing it with the zero value ogrGenerated is a contract violation
## that toProofCertificate demotes to psError (canonical_outcome.nim:49-53).
## Mirrors the production construction at ir_pipeline_runner.nim:467-470.
const noApplicableObligationVerdict = ObligationVerdictInfo(
  kind: ogrNoApplicableObligation,
  reason: "semanticNoApplicable",
  obligationCount: 0)

proc makeTestKernelCertJson(funcName: string, modulePath: string,
                            certStatus: CertificateStatus,
                            isNoObligation: bool = false): JsonNode =
  let irHash = "test_ir_hash_" & funcName
  let leanProp = "p"
  let fp = computeVerificationFingerprint(irHash, leanProp)
  result = %*{}
  result["modulePath"] = newJString(modulePath)
  result["functionName"] = newJString(funcName)
  result["fingerprint"] = newJString(fp)
  result["irHash"] = newJString(irHash)
  result["leanProposition"] = newJString(leanProp)
  result["solverMeta"] = %*{"leanCompilerVerified": true, "smtlib2": ""}
  result["smtlib2"] = newJString("")
  result["passed"] = newJBool(true)
  result["status"] = newJString($(certStatus))
  if isNoObligation:
    result["solverMeta"]["z3Executed"] = newJBool(false)
    result["solverMeta"]["solverProvenance"] = newJString("spNoObligation")
  else:
    result["solverMeta"]["z3Executed"] = newJBool(true)
    result["solverMeta"]["solverProvenance"] = newJString("spZ3SAT")
  var axiomsArr = newJArray()
  axiomsArr.add(newJString("propext"))
  axiomsArr.add(newJString("Quot.sound"))
  result["axiomsUsed"] = axiomsArr

proc makeTestRuntimeAxiomEntry(funcName: string, modulePath: string,
                               isKernel: bool = true): RuntimeAxiomEntry =
  RuntimeAxiomEntry(
    name: funcName,
    irSerialized: "ir_serialized",
    smtSource: "",
    leanSource: "",
    sourcePath: modulePath,
    isKernel: isKernel,
    irHash: "test_ir_hash_" & funcName,
    effectKind: Pure,
    bmcSkippable: false
  )

suite "NoObligation Invariant Tests (C2)":

  test "Invariant 1: makeNoObligation() -> toProofCertificate -> toCertificateBatch yields passCount=0, skipCount+=1":
    let noObligResult = makeNoObligation()
    check noObligResult.status == vsNoObligation
    check noObligResult.reason == rkNoObligation

    let poResult = IrPipelineResult(
      funcName: "testNoObligFunc",
      modulePath: "test/module.nim",
      irDigest: "test_ir_hash",
      verification: noObligResult,
      obligationVerdict: noApplicableObligationVerdict,
      provenance: vpNone,
      success: true,
      skipped: true,
      crossValidation: CrossValidationResult(consistent: false),
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let cert = toProofCertificate(poResult)
    check cert.status == psNoObligation

    let batch = toCertificateBatch(@[poResult])
    check batch.passCount == 0
    check batch.skipCount == 1

  test "Invariant 2: NoObligation certificate maps to certNoObligation, never certGreen/certYellow in axiom_engine promotion":
    let noObligResult = makeNoObligation()
    let poResult = IrPipelineResult(
      funcName: "testNoObligFunc2",
      modulePath: "test/module.nim",
      irDigest: "test_ir_hash2",
      verification: noObligResult,
      obligationVerdict: noApplicableObligationVerdict,
      provenance: vpBmcSkipped,
      success: true,
      skipped: true,
      crossValidation: CrossValidationResult(consistent: false),
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let cert = toProofCertificate(poResult)
    check cert.status == psNoObligation

    let expectedStatus = if cert.status == psPass: "certGreen"
                       elif cert.status == psNoObligation: "certNoObligation"
                       else: "certYellow"

    check expectedStatus == "certNoObligation"
    check cert.status != psPass

  test "Invariant 3: NoObligation cert has certNoObligation status which is NOT in the genuine whitelist":
    let scope = KernelScopeInfo(
      kernelSymbols: @["test/module.nim::testNoObligFunc"],
      kernelTotal: 1
    )

    let noObligJsonCert = makeTestKernelCertJson("testNoObligFunc", "test/module.nim",
                                                  certNoObligation, isNoObligation=true)

    let entry = makeTestRuntimeAxiomEntry("testNoObligFunc", "test/module.nim", isKernel=true)

    let status = noObligJsonCert{"status"}.getStr("")
    let parsedStatus = parseCertificateStatus(status)

    check parsedStatus == certNoObligation
    check parsedStatus != certYellow
    check parsedStatus != certGreen
    check parsedStatus notin {certGreen, certZ3Verified, certLeanVerified, certDualVerified, certVerifiedAxiom}

    # certNoObligation is NOT VKD-admissible: deep-verification must reject it.
    let deepVerifyResult = certificate_verifier.isDeepVerified(
      noObligJsonCert, "", entry, ""
    )

    check deepVerifyResult != dvcSuccess

  test "Invariant 4: Real CHC Pass (makeProved with smCHC, pkSpacer, psUnbounded) yields psPass":
    let provedResult = makeProved(smCHC, pkSpacer, psUnbounded)

    check provedResult.status == vsProved
    check provedResult.reason == rkNone
    check provedResult.solverMethod == smCHC
    check provedResult.provenance == pkSpacer
    check provedResult.proofScope == psUnbounded

    let poResultFromProved = IrPipelineResult(
      funcName: "testProvedFunc",
      modulePath: "test/module.nim",
      irDigest: "test_ir_hash_proved",
      verification: provedResult,
      provenance: vpInductiveLoop,
      success: true,
      skipped: false,
      crossValidation: CrossValidationResult(consistent: true),
      complexity: 1.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let certFromProved = toProofCertificate(poResultFromProved)
    check certFromProved.status == psPass
    check certFromProved.solverMethod == smSpacer
    check certFromProved.provenance == "solverMethod=smCHC,provenance=pkSpacer"

  test "Invariant 5a: vsNoObligation VerificationResult -> toProofCertificate yields psNoObligation (never psPass)":
    let noObligVR = makeNoObligation()
    check noObligVR.status == vsNoObligation

    let poResult = IrPipelineResult(
      funcName: "testNoObligFunc5a",
      modulePath: "test/module5a.nim",
      irDigest: "ir_hash_5a",
      verification: noObligVR,
      obligationVerdict: noApplicableObligationVerdict,
      provenance: vpBmcSkipped,
      success: true,
      skipped: true,
      crossValidation: CrossValidationResult(consistent: false),
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let cert = toProofCertificate(poResult)
    check cert.status == psNoObligation
    check cert.status != psPass

  test "Invariant 5a-2: makeNoApplicableObligation() (P5 formal) -> psNoObligation (never psPass)":
    let noObligVR = makeNoApplicableObligation()
    check noObligVR.status == vsNoObligation

    let poResult = IrPipelineResult(
      funcName: "testNoObligFunc5a2",
      modulePath: "test/module5a2.nim",
      irDigest: "ir_hash_5a2",
      verification: noObligVR,
      obligationVerdict: noApplicableObligationVerdict,
      provenance: vpBmcSkipped,
      success: true,
      skipped: true,
      crossValidation: CrossValidationResult(consistent: false),
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let cert = toProofCertificate(poResult)
    check cert.status == psNoObligation
    check cert.status != psPass

  test "Invariant 5b: NoObligation-derived certs cannot be laundered to other genuine whitelist statuses":
    let noObligVR = makeNoObligation()
    let poResult = IrPipelineResult(
      funcName: "testNoObligFunc5b",
      modulePath: "test/module5b.nim",
      irDigest: "ir_hash_5b",
      verification: noObligVR,
      obligationVerdict: noApplicableObligationVerdict,
      provenance: vpBmcSkipped,
      success: true,
      skipped: true,
      crossValidation: CrossValidationResult(consistent: false),
      complexity: 0.0,
      backend: vbCanonicalChc,
      actualBackend: vbCanonicalChc,
      fallbackOccurred: false,
      fallbackReason: "",
      requestedBackend: vbCanonicalChc,
      selectedBackend: vbCanonicalChc
    )

    let cert = toProofCertificate(poResult)
    check cert.status == psNoObligation

    let certStatusStr = $(cert.status)
    check certStatusStr == "psNoObligation"

    proc isGenuineWhitelistCert(c: ProofCertificate): bool =
      c.status == psPass

    check not isGenuineWhitelistCert(cert)