# R4 — Promotion Eligibility Aggregate — Design (Phase 1)

**Status**: Draft (design only — NO implementation in Phase 1)
**Gates on**: Phase-0 ADR-0015 → F1=C (reuse existing SSOT), F2=EvidenceBundle (no real proof object), F3=scattered partial gates → single aggregate.
**Out of scope**: Phase 2 / R8 (persistence + real certGreen) is a separate research blocker (F4=B). This design does not create a proof pipeline; it only binds the existing evidence into a single promotion-eligibility authority.

---

## 1. Objective

Make **one promotion/write authority** the single gate through which a certificate may be written to or promoted in the canonical vault — without inventing a new evidence store and **without making `aggregate()` a new source of truth**. `aggregate()` is a **policy reducer**, not an evidence verifier.

> Single authority ≠ single monolithic predicate. Verification is done by the existing small verifiers; `aggregate()` only combines their structured results + `reasons[]`.

---

## 2. Inputs — the existing Evidence SSOT (reuse, do not duplicate)

| Input | Reused from | Role in the aggregate |
|---|---|---|
| `CertificateEvidence { z3Passed, leanVerified }` | `src/core/types/verification_tier.nim:94` — extracted via `certificateEvidenceFromJson(node)` (`:98`, fail-closed) | canonical base evidence (`solverbuilder` + Lean) |
| `EvidenceBundle` | `src/core/trusted/evidence_calculus.nim:76` — via `toEvidenceBundle(CertificateEvidence)` (`:86`) | structured evidence: `facts{solverProved, translationProved, kernelScoped, provenanceComplete, specProved, replayProved}`, `certificateEvidence`, `solverInvocation` |
| `admissibleEvidence(bundle)` | `evidence_calculus.nim:110` = `solverProved ∧ translationProved` (dual) | is the evidence dual-admissible? |
| `tierFromEvidence(ev)` / `tierFromResults` | `verification_tier.nim:118,32` | tier is a pure function of evidence, not of a status string |
| `statusConsistentWithEvidence(node)` | `verification_tier.nim:122` (lower-bound: certGreen ⟹ dual, certZ3Verified ⟹ z3, certLeanVerified ⟹ lean) | status never exceeds stored evidence |
| `isDeepVerified(cert, certPath)` | `src/verification/certificate_verifier.nim:46`, `src/core/proof/proof_integrity.nim:127` (DIP) | deep verification (vacuity / source-staleness / kernel) |
| `validateCertGreenWritable(node)` | `src/verification/certificate_manager.nim:121` (winningStrategy + evidence) | write-time syntactic gate (repurposed as a verifier conjunct) |
| identity binding | `src/verification/certificate_identity.nim:15-44` `V3IdentityState → compV3Identity()` vs stored `identityDigest` | certificate identity is canonical and matches |
| v3 completeness | required fields present/non-empty (per `provenance_contract_v3.md`: claim, attestation, inputHash, provenance, toolchainIdentity, solverInvocation, solverInputDigest, solverResultDigest, identityDigest) | completeness conjunct |

**No new `EvidenceBundle` type, no new evidence storage, no fabricated `proofDigest`.** The digest set remains the honest evidence digests (`solverInputDigest`, `solverResultDigest`, `inputHash`, `identityDigest`); a real proof object does not exist yet (F2), so there is no `proofDigest` to bind — that binding is reserved until real proof artifacts are wired in (a separate capability change, not part of R4).

---

## 3. Verifier decomposition + aggregate (purposes only; signatures at design level)

Verifiers each consume the certificate JSON + EvidenceBundle and return a **structured result** `{passed: bool, reasons: seq[string]}`:

1. `verifySemanticEvidence(cert) → {passed, reasons}` — evidence exists and is consistent: `certificateEvidenceFromJson`, `tierFromEvidence`, `statusConsistentWithEvidence`.
2. `verifyProofArtifact(cert) → {passed, reasons | NOT_APPLICABLE}` — **structural placeholder for the future**: since F2 = no real proof object, this verifier returns NOT_APPLICABLE ("no proof artifact in v1; no proofDigest claimed"), never fabricates a pass. (Wired to a real proof-object check only when Z3 PROOF_MODE / real proof artifacts land in the pipeline.)
3. `verifyAcceptance(cert, bundle) → {passed, reasons}` — `isDeepVerified(cert)` and `admissibleEvidence(bundle)` (dual acceptance present, non-vacuous).
4. `verifyIdentityBinding(cert) → {passed, reasons}` — `compV3Identity(...)` equals stored `identityDigest`; `inputHash`/`sourceHash`/`irHash` consistent (no cycle; identity carries no timestamp).
5. `verifyCertificateCompleteness(cert) → {passed, reasons}` — all required v3 fields present and non-empty; `validateCertGreenWritable` syntactic gate.

Which verifiers are **required** is tied to the target status (certGreen requires 1,2?,3,4,5; Z3-only/Lean-only require the corresponding subset). This is the only policy branch; it lives in the policy layer, not in any verifier.

```
verifySemanticEvidence → {p,reasons}
verifyProofArtifact    → {p,reasons|N_A}
verifyAcceptance       → {p,reasons}
verifyIdentityBinding  → {p,reasons}
verifyCertificateCompleteness → {p,reasons}
        │  (structured results only — these DO the verification)
        ▼
CertificateEligibility.aggregate(requiredChecks, results) → ELIGIBLE | NOT_ELIGIBLE(reasons[])
        │  (policy reducer only — combines "all required passed?" + reasons)
        ▼
           admissible / rejected
```

**`aggregate()` contract (policy reducer, performs NO new verification):**
- Input: the set of required verifier IDs + per-verifier structured results.
- Output: `ELIGIBLE` iff every required verifier reports `passed=true`; otherwise `NOT_ELIGIBLE(reasons[])` = the union of failing reasons.
- It must NOT read evidence, compute digests, or re-derive status. Add a new acceptance axis → add a verifier + a policy entry, not a longer AND-chain.

---

## 4. Completeness conditions (required v3 fields)

`verifyCertificateCompleteness(cert)` is satisfied iff **every** field below is present and non-empty (proofDigest optional/absent per contract — not a completeness failure in v1):

`claim, attestation, inputHash, provenance, toolchainIdentity, solverInvocation, solverInputDigest, solverResultDigest, identityDigest, schemaVersion, modulePath, functionName, sourceHash, irHash`.

## 5. Digest-binding conditions

- `identityDigest == compV3Identity(V3IdentityState(...))` reconstructed from the cert's own fields → **identity binding** (this is already the single identity SSOT; keep it).
- `inputHash == H(modulePath, functionName, sourceHash, irHash)` — already computed at `cert_writer.nim:288-294`.
- `solverInputDigest` / `solverResultDigest` are re-derived deterministically from the cert's stored solver input/result evidence (already at `cert_writer.nim:313-327`). **Honest note**: `solverResultDigest` is currently derived from `status+tier`, not from real solver stdout; the binding check only requires the stored digest be reproducible from stored evidence — it does NOT claim a solver-output digest. Cross-checking against a real `.z3out` hash is a follow-on improvement (gated on proving solver output persistence), not a v1 eligibility blocker.
- **Hash dependency DAG (no cycles)**: `ProofArtifactDigest → AcceptanceDigest → CertificateIdentity → CertificateDigest`. Cycles are forbidden. `CertificateIdentity` carries **no provenance timestamp** (identity ≠ execution occurrence).

## 6. Promotion reject conditions

`NOT_ELIGIBLE(reasons[])` if any required verifier fails, including:
- evidence absent/inconsistent (`verifySemanticEvidence`),
- fuzzy/deep or admissible-evidence missing (`verifyAcceptance`),
- identity digest mismatch / source/IR/input hash mismatch (`verifyIdentityBinding`),
- incomplete v3 fields (`verifyCertificateCompleteness`).

Promotion (`cert_promotion.promoteToCanonical` / `certificate_manager.writeCertificate`) must call the aggregate and refuse on `NOT_ELIGIBLE`; the existing partial gates (`validateCertGreenWritable`, `isPromotionAllowedStatus`, `promoteVerdict`) become **internal helpers/conjuncts** of the aggregate, not independent authorities. No path may promote around the aggregate.

## 7. CAS / identity relationship

Logical `CertificateIdentity (compV3Identity)` ─► canonical artifact reference (existing CAS, keyed by `irHash`) ─► vault file (`src/verification/certificates/<irHash>.json`). **Reuse the existing CAS** (ADR `0006-cas-cache-engine`); do not build a second CAS. Logical identity and physical storage stay separable; same-identity / same-path collision surface = overwrite conflict (already handled idempotently in `promoteToCanonical:229-234`).

## 8. Evaluator vs runtime-policy boundary

- The **independent evaluator is the sole arbiter of R1–R8** (`data/readiness/independent_policy.json` + `evaluate.py`). The product runtime's `aggregate()` is an **execution-layer policy reducer** — it never certifies the product, and it must NOT call the evaluator's internals (implementation → real artifact → independent evaluator → artifact inspection).
- Running only the repository's own gates is not evidence of readiness; only the independent evaluator rerun marks R1–R8.

## 9. Test surface (design-level, for the implementation phase)

- Pure unit tests per verifier: pass/fail/NOT_APPLICABLE cases.
- `aggregate()` tests: "all required passed → ELIGIBLE"; "one required failed → NOT_ELIGIBLE with its reason"; "aggregate performs no verification" (feed an aggregate only precomputed results and assert it never reads evidence).
- Tamper test: flip any digest in the DAG → identity binding fails → `NOT_ELIGIBLE` → promotion rejected.
- Invariant: no promotion path bypasses the aggregate.

---

## 10. What this design explicitly does NOT do (scope guard)

- Does NOT create a proof pipeline or enable `proofDigest` (F2: no real proof object; reserved).
- Does NOT change the canonical vault structure or persistence (Phase 2 / R8, blocked).
- Does NOT change exit codes (Phase 3 / R7).
- Does NOT lift the F4=B research blocker (obligation generation → real certGreen).
