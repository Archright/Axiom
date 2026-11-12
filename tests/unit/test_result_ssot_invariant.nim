import std/[unittest, options]
import core/trusted/verification_result_types
import core/types/solver_types
import verification/obligation/obligation_types

suite "VerificationResult SSOT invariant":
  test "makeProved always produces rkNone reason":
    check makeProved(smCHC, pkSpacer, psUnbounded).reason == rkNone
    check makeProved(smBMC, pkSpacer, psBounded).reason == rkNone
    check makeProved(smCHC, pkZ3Bmc, psUnbounded).reason == rkNone

  test "makeProved requires mandatory proofScope (compile-time invariant)":
    check not compiles(makeProved())
    check not compiles(makeProved(smCHC))
    check not compiles(makeProved(smCHC, pkSpacer))

  test "makeNoObligation produces vsNoObligation status":
    check makeNoObligation().status == vsNoObligation
    check makeNoObligation().reason == rkNoObligation

  test "makeNoApplicableObligation (P5 formal) -> vsNoObligation, reason coerced to rkNoObligation":
    let r = makeNoApplicableObligation()
    check r.status == vsNoObligation
    ## deriveVerdict coerces rkNoApplicableObligation → rkNoObligation for
    ## VerificationResult consistency; semantic distinction preserved in
    ## ObligationVerdictInfo.kind downstream.
    check r.reason == rkNoObligation

  test "rkObligationUnsupported / rkObligationIllFormed are distinct from legacy reasons":
    check rkObligationUnsupported != rkNoObligation
    check rkObligationUnsupported != rkNotEncodable
    check rkObligationUnsupported != rkUnsupportedTheory
    check rkObligationIllFormed != rkNoObligation
    check rkObligationIllFormed != rkNotEncodable
    check rkObligationIllFormed != rkObligationUnsupported

  test "makeCandidateCounterexample produces rkCandidateCounterexample reason":
    let ce = makeCandidateCounterexample("x=5", smBMC, pkSpacer)
    check ce.reason == rkCandidateCounterexample

  test "makeCandidateCounterexample produces vsInconclusive NOT vsDisproved":
    let ce = makeCandidateCounterexample("x=5", smBMC, pkSpacer)
    check ce.status == vsInconclusive
    check ce.status != vsDisproved

  test "makeCandidateCounterexample carries solverSat solverStatus":
    let ce = makeCandidateCounterexample("x=5", smBMC, pkSpacer)
    check ce.solverStatus == solverSat
    check ce.model == "x=5"

  test "makeSolverUnknown produces rkSolverUnknown reason":
    check makeSolverUnknown().reason == rkSolverUnknown
    check makeSolverUnknown().status == vsInconclusive

  test "makeTimeout produces rkSolverTimeout reason":
    check makeTimeout().reason == rkSolverTimeout
    check makeTimeout().status == vsInconclusive
    check makeTimeout().termination == tkTimedOut

  test "makeNotEncodable produces rkNotEncodable reason":
    check makeNotEncodable().reason == rkNotEncodable
    check makeNotEncodable().status == vsInconclusive

  test "makeNoProperty produces rkNoProperty reason":
    check makeNoProperty().reason == rkNoProperty
    check makeNoProperty().status == vsInconclusive

  test "deriveVerdict coerces vsProved+rkNoObligation to rkNone":
    let result = deriveVerdict(vsProved, rkNoObligation)
    check result.reason == rkNone
    check result.status == vsProved

  test "deriveVerdict coerces vsInconclusive+rkNone to rkEvidenceRejected":
    let result = deriveVerdict(vsInconclusive, rkNone)
    check result.reason == rkEvidenceRejected
    check result.status == vsInconclusive

  test "deriveVerdict coerces vsDisproved+rkNotEncodable to rkCandidateCounterexample":
    let result = deriveVerdict(vsDisproved, rkNotEncodable)
    check result.reason == rkCandidateCounterexample
    check result.status == vsDisproved

  test "makeDisproved produces vsDisproved with rkNone":
    check makeDisproved(smBMC, pkZ3Bmc, psBounded).status == vsDisproved
    check makeDisproved(smCHC, pkSpacer, psUnbounded).reason == rkNone

  test "makeProved carries explicit solverMethod and provenance":
    let r = makeProved(smCHC, pkSpacer, psUnbounded)
    check r.solverMethod == smCHC
    check r.provenance == pkSpacer

  test "makeCandidateCounterexample carries explicit smBMC solverMethod":
    let ce = makeCandidateCounterexample("m", smBMC, pkZ3Bmc)
    check ce.solverMethod == smBMC
    check ce.provenance == pkZ3Bmc

  test "proofScope discriminates bounded from unbounded proofs":
    let unbounded = makeProved(smCHC, pkSpacer, psUnbounded)
    let bounded = makeProved(smBMC, pkZ3Bmc, psBounded)
    check isProved(unbounded) == true
    check isUnboundedProved(unbounded) == true
    check isBoundedProved(unbounded) == false
    check isProved(bounded) == true
    check isUnboundedProved(bounded) == false
    check isBoundedProved(bounded) == true

  test "BoundedEvidence is structurally distinct from UnboundedProven":
    let bounded = makeProved(smBMC, pkZ3Bmc, psBounded)
    check bounded.proofScope == psBounded
    check isProved(bounded) == true       ## verdict is still "proved"
    check isUnboundedProved(bounded) == false  ## but NOT genuine kernel
    check isBoundedProved(bounded) == true