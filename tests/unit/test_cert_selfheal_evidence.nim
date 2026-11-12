import std/unittest
import std/json
import verification/analyzer/stage_02_fingerprint
import core/types/certificate_types

# W2-D regression guard: stage-02 self-healing must be evidence-based.
#
# P0 invariant (docs/spec/verification_density.md): certGreen requires dual
# (Z3 AND Lean) validated evidence. The stage-02 fingerprint-matched
# self-healing path previously promoted ANY non-pending certificate to a blind
# certGreen default, silently upgrading e.g. certZ3Verified to certificate
# certGreen without checking stored evidence. selfHealMatchedStatus derives the
# healed status from the canonical evidence chain
# (certificateEvidenceFromJson -> tierFromEvidence -> tierToCertStatus) and
# leaves the status unchanged when evidence is missing or unparseable.

proc mkCert(status: string; leanVerified: bool; z3Unsat: bool = false): JsonNode =
  ## Minimal certificate JSON fixture: evidence lives in solverStatus/solverMeta.
  let solverMeta = %*{"leanCompilerVerified": leanVerified}
  result = %*{
    "status": status,
    "solverMeta": solverMeta
  }
  if z3Unsat:
    result["solverStatus"] = newJString("unsat")

suite "stage_02 self-heal (fingerprint-matched) evidence-based status":
  test "certZ3Verified certificate with matching fingerprint does NOT become certGreen (stays Z3-tier)":
    # The audited regression: Z3-only evidence + matching fingerprint must keep
    # the certificate at its Z3 tier, never promote it to certGreen.
    let z3Only = mkCert("certZ3Verified", leanVerified = false, z3Unsat = true)
    check selfHealMatchedStatus(certZ3Verified, z3Only) == certZ3Verified

  test "certificate with dual evidence + matching fingerprint may become certGreen":
    # Dual (Z3 AND Lean) evidence is the ONLY route to certGreen on self-heal.
    let dual = mkCert("certZ3Verified", leanVerified = true, z3Unsat = true)
    check selfHealMatchedStatus(certZ3Verified, dual) == certGreen

  test "missing evidence -> no promotion (status unchanged)":
    let bare = mkCert("certZ3Verified", leanVerified = false)
    check selfHealMatchedStatus(certZ3Verified, bare) == certZ3Verified
    check selfHealMatchedStatus(certRed, bare) == certRed

  test "unparseable evidence node -> status unchanged":
    check selfHealMatchedStatus(certZ3Verified, newJNull()) == certZ3Verified
    check selfHealMatchedStatus(certZ3Verified, newJArray()) == certZ3Verified
    check selfHealMatchedStatus(certRed, newJNull()) == certRed

  test "certGreen overclaim demoted to evidence tier (fail-closed)":
    # A certificate claiming certGreen while holding only Z3 evidence is
    # corrected to its honest tier instead of being rubber-stamped.
    let z3OnlyGreen = mkCert("certGreen", leanVerified = false, z3Unsat = true)
    check selfHealMatchedStatus(certGreen, z3OnlyGreen) == certZ3Verified

  test "certVerifiedAxiom preserved (axiom trust, not Z3/Lean evidence)":
    let dual = mkCert("certVerifiedAxiom", leanVerified = true, z3Unsat = true)
    check selfHealMatchedStatus(certVerifiedAxiom, dual) == certVerifiedAxiom

  test "lean-only evidence heals to certLeanVerified":
    let leanOnly = mkCert("certRed", leanVerified = true)
    check selfHealMatchedStatus(certRed, leanOnly) == certLeanVerified