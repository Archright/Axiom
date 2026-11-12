# Evidence Calculus — Canonical Evidence Model

## Purpose

The Evidence Calculus is a closed, deterministic computation that unifies Evidence, Provenance, Identity, VKD, Tier, and Status into a single derivation pipeline. Evidence is treated as **typed facts** (value + provenance); boolean admission flags are **derived** from those facts, never stored as authority. The calculus produces a deterministic assurance tier from evidence + policy, and a deterministic VKD count from the set of admissible certificates.

All state is frozen at certificate-creation time. The system does not re-derive evidence from external state at query time; it evaluates the typed facts carried by the certificate. This makes the computation reproducible, auditable, and independent of the runtime environment.

## Current Invariants (TRUE today)

**I1 — status is not authority; evidence governs.**
The `status` field in a certificate (e.g. `certGreen`, `certZ3Verified`) is a label, not a proof obligation. Admission is determined by `admissibleEvidence`, which inspects the typed evidence facts (`solverProved`, `translationProved`), not the status string. Enforced at `evidence_calculus.nim:110` (`admissibleEvidence`) and `proof_integrity.nim:154` (`isVkdAdmissible`).

**I2 — tier is derived from evidence + policy, not stored authority.**
`deriveAssurance(bundle, policy)` computes tier 0..3 as a pure function of the evidence facts and the policy version. A stored tier that does not equal the re-derived tier invalidates the certificate. Enforced at `evidence_calculus.nim:95` (`deriveAssurance`).

**I3 — VKD is an evidence predicate; status-only admission is forbidden.**
`isVkdAdmissible` uses `admissibleEvidence(toEvidenceBundle(certificateEvidenceFromJson(cert)))` — requiring both `solverProved` and `translationProved` — instead of checking `status == certGreen`. A Z3-only (`certZ3Verified`) or Lean-only (`certLeanVerified`) certificate is not admissible for VKD. Enforced at `proof_integrity.nim:154`.

**I4 — certificate identity binds the full provenance chain.**
The `EvidenceFact` type carries fields for source (`specOrigin`), IR (`irHash` via `TranslationEvidence`), SMT (`smtHash` via `SolverEvidence`), translation (`translationVersion`, `theoremId`), solver (`solverIdentity`, `proofDigest`), proof (`proofArtifactDigest`), and schema (`proofFormat`). A certificate with any link missing has incomplete provenance and derives to tier 0. Enforced by the structure of `EvidenceFact` and `admissibleEvidence` at `evidence_calculus.nim:62-74` and `:110`.

**I5 — `translationVersion` is a certificate-identity component.**
`TranslationEvidence.translationVersion` is a first-class field of the evidence model and participates in the provenance chain. It is not optional metadata; it is part of the typed fact that binds the translation artifact to the certificate identity. Enforced at `evidence_calculus.nim:35`.

**I6 — a recorded solver result (unsat) is not a proof-checked proof.**
`trust_boundary.nim` classifies the Z3 result as `tcRecorded` (not `tcTrusted`). `admissibleEvidence` requires both `solverProved` (Z3 unsat) **and** `translationProved` (Lean kernel acceptance). A Z3-only result alone is recorded but not admissible. Declared at `trust_boundary.nim:43-48` (Z3 = `tcRecorded`); the both-facts predicate is enforced at `evidence_calculus.nim:110` (`admissibleEvidence`) and `proof_integrity.nim:154` (`isVkdAdmissible`). **Wiring note (earlier "enforced" wording was stale)**: `evidence_calculus.nim` does not import `trust_boundary.nim`, so the `tcRecorded` classification is not consulted by the production admission predicate — the trust-boundary register (`AxiomTrustBoundary`, `categoryOf`) is currently consumed only by `tests/unit/test_evidence_calculus.nim`.

**I8 — unsupported language construct fails closed (no heuristic acceptance).**
When a component is unknown or unsupported, the system defaults to `tcRecorded` (not trusted) and `admissibleEvidence` returns false. There is no heuristic path that upgrades a recorded or unverified result to trusted or admissible. Declared at `trust_boundary.nim:100` (`categoryOf` fallback to `tcRecorded`); the fail-closed predicate is `admissibleEvidence` at `evidence_calculus.nim:110` — but see the I6 wiring note: the classification register is not consumed by the production predicate (tests-only today).

## Future Assurance Invariants / P3-P7 acceptance conditions (NOT true today)

The following invariants define the **acceptance conditions** for future assurance tiers (P3–P7). They are **not true today**; their absence is intentional and honest. The current assurance level (T0-style: recorded solver evidence, VKD=0) is different from a future T1/T2/T3, and the system does not claim otherwise.

**F1 — formal IR semantics exists.**
`CanonicalIRSemantics` is declared in `trust_boundary.nim` with `exists: false`. No formal IR semantics (operational `evalIR` function) has been implemented. This is a P3 acceptance condition.

**F2 — Nim-subset → Canonical IR soundness theorem exists.**
`SemanticFoundation.translationTheorem` is `""` (absent) in the current `EvidenceFact` model. No Nim-subset-to-Canonical-IR soundness theorem has been proven. This is a P4 acceptance condition.

**F3 — IR → QF_BV soundness theorem exists.**
`SemanticFoundation.qfBvSoundnessTheorem` is `""` (absent). No IR-to-QF_BV soundness theorem has been proven. This is a P4 acceptance condition.

**F4 — replayable proof artifact is produced.**
`EvidenceFact.replayProved` is always `false` in `toEvidenceBundle` (provenance is not yet established). No replayable proof artifact with independent replay verification exists. This is a P5 acceptance condition.

**F5 — independent producer ≠ independent checker.**
The `Proof checker` component in `trust_boundary.nim` has `exists: false`. There is no independent checker that is distinct from the proof producer. This is a P6 acceptance condition.

**F6 — a genuine T1 certificate exists.**
VKD is 0 today. No certificate satisfies the full P7 acceptance criteria (formal spec + scalar IR + semantic proof + QF_BV + proof artifact + independent replay + complete provenance). This is a P7 acceptance condition.

## Extension Points (absent by default)

The following extension points are defined in the evidence model but have **empty/absent values** by default. A certificate with these absent is **not invalid**; it simply expresses the current assurance level, which is different from a future T1/T2/T3. This is honest and intentional.

- **`semanticFoundation`** — `{ irSemanticsVersion, translationTheorem, qfBvSoundnessTheorem }` — all `""` (absent). No formal IR semantics, no Nim→IR soundness theorem, no IR→QF_BV soundness theorem exist today.
- **`proofArtifact`** — `{ format, digest, checker }` — all `""` (absent). No replayable proof artifact contract is in effect today.
- **`replay`** (`ReplayEvidence`) — `{ checker, artifactDigest, result }` — all `""` (absent). No independent replay verification exists today.

These extension points are **not** evidence of absence of assurance; they are explicit markers of the current assurance boundary. When populated in a future phase, they will tighten the evidence predicate and raise the assurance tier.

## Trust Boundary (cross-reference: `docs/spec/formal_assurance_track.md`)

The trust boundary is defined in `src/core/trusted/trust_boundary.nim` and is frozen as part of the productization foundation (P0).

- **Recorded** (Z3 result, CLI) ≠ **Trusted** (SHA-256, Lean kernel). A recorded component carries provenance only and is not part of the trust base.
- **Not-yet-present components** are declared with `exists: false` (no trust over-claim): `Proof checker`, `CanonicalIRSemantics`, `CertificateIdentity binding`, and the 3 Rust subject boundaries (`rustc to LLBC lowering`, `LLBC to shared canonical translation`, `dual IR derivation from shared canonical` — all `tcRecorded`, ADR-0029 D3).
- The `categoryOf` function falls back to `tcRecorded` for unknown components, ensuring fail-closed behavior.

The full trust boundary is an 11-entry array (`AxiomTrustBoundary`): the original 8 entries covering SHA-256, Lean kernel, Proof checker, Z3 result, CanonicalIRSemantics, CertificateIdentity binding, BMC engine, and Axiom CLI, plus 3 declared Rust subject boundaries (ADR-0029 D3) — `rustc to LLBC lowering`, `LLBC to shared canonical translation`, `dual IR derivation from shared canonical`. All 3 Rust entries are `tcRecorded` with `exists: false` ("component not yet present, no trust over-claim") — declared but not implemented, and carrying no trust.

## Determinism

- **tier = `deriveAssurance(evidence, policyVersion)`**; the stored tier must equal the derived tier or the certificate is invalid (I2). The derivation is a pure function of the evidence facts and the policy version — no external state, no runtime environment, no mutable counters.
- **VKD** = count of certificates satisfying the evidence predicate (`admissibleEvidence`); the baseline remains monotonic. A certificate is admissible only when both solver and translation evidence are established (I3). The VKD count is a cumulative, append-only function over the certificate vault — re-running `ax prove` on already-verified functions does not change VKD.

Axiom이 현재 가진 증거가 무엇인지, 그 증거로 무엇을 주장할 수 있는지, 그 주장이 어떻게 결정론적으로 계산되는지가 완전히 고정되어 있다.