import std/[unittest, json]
import ../../src/core/proof/proof_integrity
import ../../src/core/types/certificate_types
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/verification_result_types
import verification/obligation/obligation_types
import verification/obligation/no_obligation_provenance

# P1.2 — Explicit expected-obligation contract for cnaNoObligations classification.
#
# cnaNoObligations is "no safety/semantic obligation was derived", which is NOT
# automatically a scope inconsistency. The promotion to noObligationScopeMismatch
# requires an explicit `expectedObligation: true` contract on the proof-mode symbol;
# defaulting to `expectedObligation: false` preserves the legitimate no-op path.
#
# P5 update: vsNoObligation now has two distinct provenance paths:
#   (1) rkNoObligation — legacy path (no obligation expected)
#   (2) rkNoApplicableObligation — P5 formal path (obligation generator determined
#       no applicable obligation; deriveVerdict coerces reason to rkNoObligation for
#       VerificationResult consistency, but ObligationVerdictInfo.kind preserves the
#       semantic distinction downstream).

suite "NoObligation Classification (P1.2)":
  test "expectedObligation := false keeps legitimate no-op":
    let c = classifyNoObligation(false)
    check c == noObligationLegitimate

  test "expectedObligation := true -> scope mismatch signal":
    let c = classifyNoObligation(true)
    check c == noObligationScopeMismatch

  test "makeNoObligation (legacy) -> vsNoObligation with rkNoObligation reason":
    let r = makeNoObligation()
    check r.status == vsNoObligation
    check r.reason == rkNoObligation

  test "makeNoApplicableObligation (P5 formal) -> vsNoObligation with rkNoObligation reason":
    let r = makeNoApplicableObligation()
    check r.status == vsNoObligation
    ## deriveVerdict coerces rkNoApplicableObligation → rkNoObligation for
    ## VerificationResult consistency; the semantic distinction is carried by
    ## ObligationVerdictInfo.kind downstream.
    check r.reason == rkNoObligation

  test "NoObligationProvenance carries excludedClasses and derivationRule":
    let provenance = makeNoApplicableProvenance(
      @[okSafetyDiv, okSafetyIndex],
      "obs:division",
      @["b ≠ 0", "0 ≤ idx"]
    )
    check provenance.applicableClasses.len == 0
    check provenance.excludedClasses.len == 2
    check provenance.derivationRule == "obs:division"
    check provenance.semanticFacts.len == 2