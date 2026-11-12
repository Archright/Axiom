import std/[json, unittest]
import ../../src/core/trusted/trust_boundary
import ../../src/core/trusted/evidence_calculus
import ../../src/core/types/verification_tier
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/private/evidence_identity

# Axiom Evidence Calculus — Phase 0/1/1.5/2 invariants (I1–I8).
#
# Verifies the machine-fixed trust boundary, the canonical evidence model, the
# evidence-derived VKD predicate, and the provenance-complete certificate
# identity. These are the architecture-convergence invariants that unify
# Axiom's verification evidence into one closed computation.

suite "Phase 0 — Trust Boundary Freeze":
  test "Z3 result is Recorded, NOT Trusted (recorded != trusted)":
    check categoryOf("Z3 result") == tcRecorded
    check isTrusted("Z3 result") == false
    check isRecorded("Z3 result") == true

  test "SHA-256 implementation is Trusted":
    check categoryOf("SHA-256 implementation") == tcTrusted
    check isTrusted("SHA-256 implementation") == true

  test "Lean kernel is Trusted":
    check isTrusted("Lean kernel") == true

  test "unknown component defaults fail-closed to Recorded":
    check categoryOf("no-such-component") == tcRecorded
    check isTrusted("no-such-component") == false

  test "not-yet-existing trusted components are not over-claimed":
    # I-note: exists=false → not present, so trust is not claimed yet.
    check existsInTrustBoundary("CanonicalIRSemantics") == false
    check existsInTrustBoundary("Proof checker") == false

  test "Rust subject boundaries are recorded, not trusted, not yet implemented":
    # ADR-0029 D3: rustc-derived material is consumed as an assumption, never
    # as evidence. The three Rust boundaries are declared tcRecorded with
    # exists=false — flipping exists=true without an implementation fails here.
    check AxiomTrustBoundary.len == 11
    for name in ["rustc to LLBC lowering",
                 "LLBC to shared canonical translation",
                 "dual IR derivation from shared canonical"]:
      check isRecorded(name) == true
      check categoryOf(name) == tcRecorded
      check isTrusted(name) == false
      check existsInTrustBoundary(name) == false

suite "Phase 1 — Canonical Evidence Model":
  test "toEvidenceBundle promotes CertificateEvidence":
    let ev = CertificateEvidence(z3Passed: true, leanVerified: false)
    let bundle = toEvidenceBundle(ev)
    check bundle.certificateEvidence.z3Passed == true
    check bundle.facts.solverProved == true
    check bundle.facts.translationProved == false
    check bundle.facts.provenanceComplete == false

  test "admissibleEvidence requires dual established evidence (I6: recorded != proof)":
    # dual → admissible
    check admissibleEvidence(toEvidenceBundle(
      CertificateEvidence(z3Passed: true, leanVerified: true))) == true
    # z3-only (recorded solver result) → NOT admissible (I6)
    check admissibleEvidence(toEvidenceBundle(
      CertificateEvidence(z3Passed: true, leanVerified: false))) == false
    # lean-only → NOT admissible
    check admissibleEvidence(toEvidenceBundle(
      CertificateEvidence(z3Passed: false, leanVerified: true))) == false
    # no evidence → NOT admissible
    check admissibleEvidence(toEvidenceBundle(
      CertificateEvidence(z3Passed: false, leanVerified: false))) == false

  test "deriveAssurance is deterministic and conservative":
    let bundle = toEvidenceBundle(CertificateEvidence(z3Passed: true, leanVerified: false))
    check deriveAssurance(bundle, apV1) == deriveAssurance(bundle, apV1)
    check deriveAssurance(bundle, apV1) >= 0
    check deriveAssurance(bundle, apV1) <= 3

suite "Phase 2 — Certificate Identity":
  test "computeCertificateIdentity is deterministic":
    let fields = @["schema:v1", "fn:f", "src:h1", "ir:h2"]
    check computeCertificateIdentity(fields) == computeCertificateIdentity(fields)
    check computeCertificateIdentity(fields).len > 0

  test "computeCertificateIdentity fails closed on empty input":
    check computeCertificateIdentity(@[]) == ""

  test "identityDigest binds translationVersion (I5: translationVersion in identity)":
    let a = CertificateIdentity(
      schemaVersion: "1", functionId: "f", sourceHash: "s",
      irHash: "i", translationVersion: "v1")
    let b = CertificateIdentity(
      schemaVersion: "1", functionId: "f", sourceHash: "s",
      irHash: "i", translationVersion: "v2")
    check identityDigest(a) == identityDigest(a)
    check identityDigest(a) != identityDigest(b)   # translationVersion changes identity
    check identityDigest(a).len > 0

  test "legacy fingerprint is separate from canonical identity":
    # computeVerificationFingerprint(irHash, leanProp) is the legacy path;
    # computeCertificateIdentity is the canonical provenance-complete path.
    # The full-chain identity (which binds schema/function/source/IR/SMT/
    # translation/solver/proof) MUST differ from the legacy (irHash+leanProp)
    # fingerprint, because it binds a strictly larger provenance chain.
    check computeVerificationFingerprint("abc", "p").len > 0
    check computeCertificateIdentity(@["abc", "p"]).len > 0
    let fullChain = computeCertificateIdentity(@[
      "schema:1", "fn:f", "spec:o", "src:s",
      "ir:i", "smt:t", "translation:v1", "solver:z3", "proof:d"])
    check fullChain != computeVerificationFingerprint("abc", "p")

suite "Evidence Calculus invariants I1–I8 (layer-testable subset)":
  test "I1 status is not authority — evidence governs (admissibleEvidence is evidence-based)":
    # A z3-only cert that might carry a certGreen label is NOT admissible;
    # evidence (not label) decides.
    check admissibleEvidence(toEvidenceBundle(
      CertificateEvidence(z3Passed: true, leanVerified: false))) == false

  test "I2 tier is derived only (deriveAssurance is a pure function of evidence)":
    check deriveAssurance(toEvidenceBundle(CertificateEvidence(z3Passed: true, leanVerified: true)), apV1) ==
      deriveAssurance(toEvidenceBundle(CertificateEvidence(z3Passed: true, leanVerified: true)), apV1)

  test "I3 VKD ⊆ derive(evidence) — status-only admission forbidden":
    # admissibleEvidence is the evidence predicate; it does not look at any
    # status string.
    check admissibleEvidence(toEvidenceBundle(CertificateEvidence(z3Passed: true, leanVerified: false))) == false
