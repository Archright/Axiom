import std/[json, unittest]
import ../../src/core/types/verification_tier

# P0 — certGreen status-aliasing elimination.
#
# Verifies the evidence-derivation SSOT: a certificate's `status` string is a
# DERIVED function of its stored evidence, never a hardcoded label. In
# particular `certGreen` requires dual (Z3 ∧ Lean) evidence, where Lean
# evidence is the DECISION-0630 conjunction solverMeta.leanCompilerVerified ∧
# kernel; Z3-only certs must be `certZ3Candidate` (legacy: certZ3Verified,
# gated identically).

proc mkCert(status: string; leanVerified: bool; z3Unsat: bool = false;
            kernel: bool = false): JsonNode =
  let solverMeta = %*{"leanCompilerVerified": leanVerified}
  result = %*{
    "status": status,
    "solverMeta": solverMeta,
    "kernel": newJBool(kernel)
  }
  if z3Unsat:
    result["solverStatus"] = newJString("unsat")

suite "P0 — evidence-derived certificate status":
  test "certificateEvidenceFromJson extracts (z3Passed, leanVerified)":
    # Z3-only cert: solverStatus=unsat, leanCompilerVerified=false
    let cert = mkCert("certGreen", leanVerified = false, z3Unsat = true)
    let ev = certificateEvidenceFromJson(cert)
    check ev.z3Passed == true
    check ev.leanVerified == false

  test "certificateEvidenceFromJson fails closed on missing evidence":
    # A cert without solverStatus and without smtlib2+z3outPath → z3Passed=false
    let cert = mkCert("certGreen", leanVerified = false)
    let ev = certificateEvidenceFromJson(cert)
    check ev.z3Passed == false
    check ev.leanVerified == false

  test "certificateEvidenceFromJson reads leanCompilerVerified (P0 conjunction)":
    # DECISION-0630: Lean evidence = solverMeta.leanCompilerVerified ∧ kernel.
    # A naked flag without the kernel receipt is NOT Lean evidence.
    let nakedFlag = mkCert("certGreen", leanVerified = true)
    check certificateEvidenceFromJson(nakedFlag).leanVerified == false
    let kaaBacked = mkCert("certGreen", leanVerified = true, kernel = true)
    check certificateEvidenceFromJson(kaaBacked).leanVerified == true

  test "tierFromEvidence is a pure function of evidence":
    check tierFromEvidence(CertificateEvidence(z3Passed: true, leanVerified: false)) == vtZ3Only
    check tierFromEvidence(CertificateEvidence(z3Passed: false, leanVerified: true)) == vtLeanOnly
    check tierFromEvidence(CertificateEvidence(z3Passed: true, leanVerified: true)) == vtDual
    check tierFromEvidence(CertificateEvidence(z3Passed: false, leanVerified: false)) == vtNone

  test "statusConsistentWithEvidence rejects certGreen without dual evidence":
    # THE core P0 invariant: certGreen + leanCompilerVerified=false → inconsistent.
    let z3OnlyGreen = mkCert("certGreen", leanVerified = false, z3Unsat = true)
    check statusConsistentWithEvidence(z3OnlyGreen) == false
    # certGreen + dual (z3 unsat AND kernel-backed lean) → consistent.
    let dual = mkCert("certGreen", leanVerified = true, z3Unsat = true, kernel = true)
    check statusConsistentWithEvidence(dual) == true
    # KAA-less dual (naked lean flag, no kernel receipt) → still inconsistent:
    # status may never exceed what stored evidence supports.
    let kaaLessDual = mkCert("certGreen", leanVerified = true, z3Unsat = true)
    check statusConsistentWithEvidence(kaaLessDual) == false

  test "statusConsistentWithEvidence accepts Z3-only cert as certZ3Verified":
    let z3Only = mkCert("certZ3Verified", leanVerified = false, z3Unsat = true)
    check statusConsistentWithEvidence(z3Only) == true

  test "statusConsistentWithEvidence rejects certZ3Verified lacking z3 evidence":
    let weakZ3 = mkCert("certZ3Verified", leanVerified = false)
    check statusConsistentWithEvidence(weakZ3) == false

  test "statusConsistentWithEvidence rejects certLeanVerified lacking lean evidence":
    let weakLean = mkCert("certLeanVerified", leanVerified = false)
    check statusConsistentWithEvidence(weakLean) == false

  test "non-Green statuses are out of scope (true)":
    for s in ["certRed", "certYellow", "certPending", "certNoObligation", "certVerifiedAxiom"]:
      check statusConsistentWithEvidence(mkCert(s, leanVerified = false)) == true
