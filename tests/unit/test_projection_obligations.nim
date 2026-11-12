import std/[unittest, json, options, strutils]
import core/trusted/verification_result_types
import core/types/solver_types
import core/trusted/axiom_pragmas
import engine/proof_certificate
import verification/batch_uap/ir_pipeline_runner
import verification/obligation/obligation_ir
import verification/obligation/obligation_types
import core/types/certificate_types
import verification/cross_validation

# ---------------------------------------------------------------------------
# Helpers — mirror the IrPipelineResult construction pattern from
# test_no_obligation_invariant.nim
# ---------------------------------------------------------------------------

func makeTestIrResult*(
  funcName: string;
  modulePath: string;
  irDigest: string;
  verification: VerificationResult;
  provenance: VerificationProvenance;
  success: bool;
  skipped: bool;
  obligationKind: ObligationGenerationResultKind;
  obligationReason: string = ""
): IrPipelineResult =
  IrPipelineResult(
    funcName: funcName,
    modulePath: modulePath,
    irDigest: irDigest,
    smtScript: "",
    leanSource: "",
    crossValidation: CrossValidationResult(consistent: false),
    z3Sat: false,
    success: success,
    skipped: skipped,
    verification: verification,
    provenance: provenance,
    backend: vbCanonicalChc,
    actualBackend: vbCanonicalChc,
    fallbackOccurred: false,
    fallbackReason: "",
    requestedBackend: vbCanonicalChc,
    selectedBackend: vbCanonicalChc,
    complexity: 0.0,
    obligationVerdict: ObligationVerdictInfo(
      kind: obligationKind,
      reason: obligationReason
    )
  )

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "P5: Obligation Verdict Projection Tests":

  # (a) NoApplicable → psNoObligation + reason=ObliSemanticNoApplicable → exit 0
  test "(a) NoApplicable obligation verdict → psNoObligation, exit 0, provenance contains ObliSemanticNoApplicable":
    let vr = makeNoApplicableObligation()
    let result = makeTestIrResult(
      "testNoApplicable", "test/module.nim", "test_ir_hash_na",
      vr, vpNone, true, true,
      ogrNoApplicableObligation, "semanticNoApplicable"
    )
    let cert = toProofCertificate(result)
    check cert.status == psNoObligation
    check cert.provenance.find("ObliSemanticNoApplicable") >= 0
    check statusToExitCode(cert.status) == 0

  # (b) Unsupported → psSkip with not_verifiable provenance
  test "(b) Unsupported obligation verdict → psSkip with not_verifiable provenance, exit 0":
    let vr = makeInconclusive(rkUnsupportedTheory)
    let result = makeTestIrResult(
      "testUnsupported", "test/module.nim", "test_ir_hash_unsup",
      vr, vpNone, true, true,
      ogrUnsupported, "scopedRecursiveHeapNotModeled"
    )
    let cert = toProofCertificate(result)
    check cert.status == psSkip
    check cert.provenance.find("not_verifiable:unsupported") >= 0
    check statusToExitCode(cert.status) == 0

  # (c) IllFormed → psSkip with not_verifiable provenance
  test "(c) IllFormed obligation verdict → psSkip with not_verifiable provenance, exit 0":
    let vr = makeInconclusive(rkNotEncodable)
    let result = makeTestIrResult(
      "testIllFormed", "test/module.nim", "test_ir_hash_if",
      vr, vpNone, true, true,
      ogrIllFormed, "ifTypeMismatch"
    )
    let cert = toProofCertificate(result)
    check cert.status == psSkip
    check cert.provenance.find("not_verifiable:illFormed") >= 0
    check statusToExitCode(cert.status) == 0

  # (d) Certificate has obligationVerdict field set correctly
  test "(d) Certificate obligationVerdict field matches IrPipelineResult obligationVerdict":
    let vr = makeNoApplicableObligation()
    let result = makeTestIrResult(
      "testJsonVerdict", "test/module.nim", "test_ir_hash_json",
      vr, vpNone, true, true,
      ogrNoApplicableObligation, "semanticNoApplicable"
    )
    let cert = toProofCertificate(result)
    check cert.obligationVerdict == ogrNoApplicableObligation

  # (e) R5 regression: psError still maps to exit code 3
  test "(e) R5 regression: psError still maps to exit code 3":
    let vr = makeInconclusive(rkNone)
    let result = makeTestIrResult(
      "", "", "",
      vr, vpNone, false, false,
      ogrGenerated, ""
    )
    let cert = toProofCertificate(result)
    check cert.status == psError
    check statusToExitCode(cert.status) == 3

  # (f) R5 regression: psFail still maps to exit code 1
  test "(f) R5 regression: psFail still maps to exit code 1":
    let vr = makeInconclusive(rkCandidateCounterexample)
    let result = makeTestIrResult(
      "testFail", "test/module.nim", "test_ir_hash_fail",
      vr, vpNone, false, false,
      ogrGenerated, ""
    )
    let cert = toProofCertificate(result)
    check cert.status == psFail
    check statusToExitCode(cert.status) == 1

  # (g) ogrGenerated (normal case) is unaffected — maps to psPass when success
  test "(g) ogrGenerated with success → psPass, exit 0":
    let vr = makeProved(smCHC, pkSpacer, psUnbounded)
    let result = makeTestIrResult(
      "testGenerated", "test/module.nim", "test_ir_hash_gen",
      vr, vpInductiveLoop, true, false,
      ogrGenerated, ""
    )
    let cert = toProofCertificate(result)
    check cert.status == psPass
    check statusToExitCode(cert.status) == 0
    check cert.obligationVerdict == ogrGenerated
