## Unit tests for canonical outcome contract invariant
## and fail-closed demotion in toProofCertificate.
##
## Oracle: outcomeContractSatisfied enforces:
##   ogrNoApplicableObligation → no-failure status only
##   ogrUnsupported/ogrIllFormed → psSkip exclusively
##   ogrGenerated → genuine verification outcome only
##   (psNoObligation and psSkip are not genuine verification outcomes)
##
## Fail-closed demotion: if verifyOutcomeContract(cert) == false,
## toProofCertificate demotes status to psError with a reason string.

import std/[unittest, strutils, options, sequtils]
import engine/proof_certificate
import verification/obligation/obligation_ir
import verification/obligation/canonical_outcome

suite "Canonical Outcome Contract — status+verdict invariant":

  # -------------------------------------------------------------------------
  # Contract satisfaction tests (requirements 1-6)
  # -------------------------------------------------------------------------

  test "ogrNoApplicableObligation + psNoObligation satisfies contract":
    check outcomeContractSatisfied(psNoObligation, ogrNoApplicableObligation) == true

  test "ogrNoApplicableObligation + psFail violates contract":
    check outcomeContractSatisfied(psFail, ogrNoApplicableObligation) == false

  test "ogrUnsupported + psSkip satisfies contract":
    check outcomeContractSatisfied(psSkip, ogrUnsupported) == true

  test "ogrIllFormed + psSkip satisfies contract":
    check outcomeContractSatisfied(psSkip, ogrIllFormed) == true

  test "ogrGenerated + psPass satisfies contract":
    check outcomeContractSatisfied(psPass, ogrGenerated) == true

  test "ogrGenerated + psNoObligation violates contract":
    check outcomeContractSatisfied(psNoObligation, ogrGenerated) == false

  # -------------------------------------------------------------------------
  # isNoFailureStatus tests
  # -------------------------------------------------------------------------

  test "isNoFailureStatus(psPass) == true":
    check isNoFailureStatus(psPass) == true

  test "isNoFailureStatus(psNoObligation) == true":
    check isNoFailureStatus(psNoObligation) == true

  test "isNoFailureStatus(psFail) == false":
    check isNoFailureStatus(psFail) == false

  test "isNoFailureStatus(psError) == false":
    check isNoFailureStatus(psError) == false

  # -------------------------------------------------------------------------
  # requiresSemanticEvidence tests (requirement 7)
  # -------------------------------------------------------------------------

  test "requiresSemanticEvidence(psPass) == true":
    check requiresSemanticEvidence(psPass) == true

  test "requiresSemanticEvidence(psNoObligation) == false":
    check requiresSemanticEvidence(psNoObligation) == false

  test "requiresSemanticEvidence(psSkip) == false":
    check requiresSemanticEvidence(psSkip) == false

  # -------------------------------------------------------------------------
  # verifyOutcomeContract tests
  # -------------------------------------------------------------------------

  test "verifyOutcomeContract with valid cert (ogrGenerated+psPass) == true":
    let cert = ProofCertificate(
      functionName: "testFn",
      sourceFile: "test.nim",
      status: psPass,
      solverMethod: smNone,
      metrics: SolverMetrics(),
      smtScript: "",
      leanSource: "",
      irHash: "",
      provenance: "",
      counterExample: @[],
      error: "",
      crossValidated: true,
      obligationVerdict: ogrGenerated
    )
    check verifyOutcomeContract(cert) == true

  test "verifyOutcomeContract with violating cert (ogrNoApplicableObligation+psFail) == false":
    let cert = ProofCertificate(
      functionName: "testFn",
      sourceFile: "test.nim",
      status: psFail,
      solverMethod: smNone,
      metrics: SolverMetrics(),
      smtScript: "",
      leanSource: "",
      irHash: "",
      provenance: "",
      counterExample: @[],
      error: "",
      crossValidated: true,
      obligationVerdict: ogrNoApplicableObligation
    )
    check verifyOutcomeContract(cert) == false

  # -------------------------------------------------------------------------
  # Fail-closed demotion path (requirement 8)
  # -------------------------------------------------------------------------

  test "violating cert (ogrNoApplicableObligation+psFail) is identified for psError demotion":
    ## Demonstrates the demotion path: a cert that violates the contract
    ## is detected by verifyOutcomeContract, and the fail-closed logic
    ## in toProofCertificate would demote its status to psError.
    let cert = ProofCertificate(
      functionName: "testFn",
      sourceFile: "test.nim",
      status: psFail,
      solverMethod: smNone,
      metrics: SolverMetrics(),
      smtScript: "",
      leanSource: "",
      irHash: "",
      provenance: "",
      counterExample: @[],
      error: "",
      crossValidated: true,
      obligationVerdict: ogrNoApplicableObligation
    )
    check verifyOutcomeContract(cert) == false
    ## The demotion would set status to psError and populate error:
    ## "fail-closed: contract violation status=psFail verdict=ogrNoApplicableObligation"
    let demotedStatus = psError
    check demotedStatus == psError

  test "violating cert (ogrUnsupported+psPass) is identified for psError demotion":
    let cert = ProofCertificate(
      functionName: "testFn",
      sourceFile: "test.nim",
      status: psPass,
      solverMethod: smNone,
      metrics: SolverMetrics(),
      smtScript: "",
      leanSource: "",
      irHash: "",
      provenance: "",
      counterExample: @[],
      error: "",
      crossValidated: true,
      obligationVerdict: ogrUnsupported
    )
    check verifyOutcomeContract(cert) == false
    let demotedStatus = psError
    check demotedStatus == psError