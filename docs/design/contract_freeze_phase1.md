# Phase 1 — Contract Freeze: SemanticProfileV1, SpecificationArtifact, AssuranceProfile, CertificateV2

**Status**: Design (Contract Freeze)  
**Date**: 2026-08-13  
**Applies to**: Axiom integrity engine — Phase 1 semantics boundary  
**Extends**: `docs/design/cert_v2_issuance_boundary.md` (spec provenance), `docs/design/z3_replay_evidence_capture.md` (replay evidence capture)

---

## 0. Source Grounding

| Source | Key type / function | Used in |
|--------|---------------------|---------|
| `src/core/trusted/evidence_calculus.nim` | `EvidenceBundle`, `EvidenceFact`, `deriveAssurance:int`, `specProved`, `provenanceComplete` | Contract 3 (AssuranceProfile) |
| `src/core/trusted/private/evidence_identity.nim:14-51` | `CertificateIdentity`; `smtHash`/`proofArtifactDigest` optional-empty | Contract 4 (CertificateV2) |
| `src/core/types/certificate_types.nim` | `CertificateStatus`; `csbNotCurrent` NOT yet added | Contract 4 (legacy → `csbNotCurrent`) |
| `src/verification/cert_writer.nim` | `certJSON` persists `status`/`smtlib2`/`solverVersion` only | Contract 4 (persist scope) |
| `docs/design/cert_v2_issuance_boundary.md` | Spec provenance gap map; V2 schemaVersion="2" | Extended by Contract 2 & 4 |
| `docs/design/z3_replay_evidence_capture.md` | `smtHash`/`proofArtifactDigest` anchor at write time | Extended by Contract 4 |

---

## 1. Contract C1 — SemanticProfileV1 (DESIRED semantics)

**Purpose**: Define the target execution semantics that the encoder MUST conform to in Phase 2. This is the semantics contract, not encoder documentation.

### 1.1 SemanticProfileV1 enum

| Field | Value |
|-------|-------|
| `targetArchitecture` | `x86_64` |
| `intWidth` | `64` |
| `uintWidth` | `64` |
| `overflowMode` | `spOverflowBounded` (checked → `OverflowDefect`, Nim default) |
| `divisionMode` | `truncTowardZero` (Nim-defined signed division) |
| `moduloMode` | `spModuloSigned` (Nim `mod`, signed, truncation-toward-zero); `%%` is a SEPARATE unsigned operator (`spModuloUnsigned`, Phase 2 `%%→bvurem`) |
| `shiftMode` | `UNSUPPORTED` |
| `floatMode` | `UNSUPPORTED` |
| `stringMode` | `UNSUPPORTED` |

### 1.2 ProfileHash

```
ProfileHash = H(SemanticProfileV1)
```

where `H` is SHA-256 over the canonical serialization of the profile table above. `ProfileHash` is the content-addressed identity of this contract.

### 1.3 Normative constraint

- The encoder (Phase 2) MUST be conformed to this profile. The profile is the spec; the encoder is the implementation.
- This document does NOT describe the current encoder. Any deviation between the current encoder and this profile is a Phase 2 conformance gap, not a Phase 1 defect.
- `ProfileHash` is used as `semanticProfileId` in CertificateV2 (Contract 4).

---

## 2. Contract C2 — SpecificationArtifact (thin view)

**Purpose**: Define the canonical spec artifact identity, independent of source/IR hashes. Extends `cert_v2_issuance_boundary.md` §2 (spec provenance) and `z3_replay_evidence_capture.md` §6 (V2 fields).

### 2.1 Shape

```
SpecificationArtifact = { canonicalSpecIR, origin, ruleId, ruleVersion }
```

| Field | Type | Description |
|-------|------|-------------|
| `canonicalSpecIR` | `string` | Normalized SMT-LIB2 / Lean spec IR (canonical form) |
| `origin` | `Origin` | Where the spec came from (see §2.2) |
| `ruleId` | `string` | Identifier of the verification rule |
| `ruleVersion` | `string` | Version of the rule |

### 2.2 Origin enum

| Value | Meaning | Authorized for V1 verification input? |
|-------|---------|---------------------------------------|
| `EXPLICIT` | Human-authored spec, explicitly provided | YES |
| `CANONICAL_DERIVED` | Derived from explicit spec via canonical transformation | YES |
| `MINED` | Extracted/mined from source heuristically | **NO** — forbidden in V1 |

### 2.3 SpecID

```
SpecID = H(canonicalSpecIR, origin, ruleVersion)
```

**Critical**: `SpecID` is INDEPENDENT of `sourceHash`, `irHash`, and `semanticProfileHash`. It is computed only from the spec artifact's own fields. This decoupling ensures that spec identity is not conflated with translation identity or semantic identity.

### 2.4 Normative constraints

- `origin = MINED` MUST be rejected as verification input in V1.
- `canonicalSpecIR` MUST be the canonical form (deterministic serialization), not the raw source.
- `SpecID` is used as `specificationId` in CertificateV2 (Contract 4).

---

## 3. Contract C3 — AssuranceProfile (VECTOR)

**Purpose**: Define the assurance vector that drives proof artifact presence decisions. Extends `evidence_calculus.nim` `deriveAssurance` (which maps evidence → tier 0..3) and `EvidenceFact` dimensions.

### 3.1 Dimensions

| Dimension | Type | Description |
|-----------|------|-------------|
| `specified` | `bool` | A spec (SpecificationArtifact) exists for this claim |
| `solved` | `bool` | The solver returned a result (unsat/sat/unknown) |
| `translationTrust` | `bool` | The translation (Nim→IR) is trusted/verified |
| `replayable` | `bool` | The solver evidence is replayable (deterministic re-run yields same result) |
| `kernelChecked` | `bool` | The proof was checked by a kernel (Z3/Lean kernel) |
| `provenanceComplete` | `bool` | All provenance fields are populated and consistent |

### 3.2 Profile vector

An `AssuranceProfile` is a 6-dimensional boolean vector:

```
AssuranceProfile = (specified, solved, translationTrust, replayable, kernelChecked, provenanceComplete)
```

### 3.3 proofArtifactRequired

The presence of a proof artifact is DECIDED by the profile, not by a mandatory schema:

| Profile condition | `proofArtifactRequired` |
|-------------------|------------------------|
| `kernelChecked = true` | YES — a proof artifact MUST be present |
| `kernelChecked = false` ∧ `replayable = true` | OPTIONAL — replay evidence suffices |
| `kernelChecked = false` ∧ `replayable = false` | NO — solver result alone, no artifact |

This replaces the current rigid schema approach (where `smtHash`/`proofArtifactDigest` are always expected fields). The profile drives presence; the schema is a persistence format, not a guarantee.

### 3.4 V0 example — `assuranceSolverReplayable`

```
AssuranceProfile V0 = (specified=true, solved=true, translationTrust=true,
                        replayable=true, kernelChecked=false, provenanceComplete=true)
```

This is the V0 baseline: solver replay is trusted, but kernel checking is absent. `proofArtifactRequired = OPTIONAL`.

### 3.5 Normative constraints

- `deriveAssurance` (evidence_calculus.nim:85) maps `EvidenceBundle → int[0..3]` and is a DERIVED value from the profile, not the profile itself.
- The profile is the input; the assurance tier is the output. Do not conflate them.
- `provenanceComplete` is set to `false` initially (evidence_calculus.nim:83) and becomes `true` only when all provenance fields are populated.

---

## 4. Contract C4 — CertificateV2 as persist(Claim)

**Purpose**: Define CertificateV2 as a content-addressed persistence of a Claim. Extends `cert_v2_issuance_boundary.md` §2 (V2 schemaVersion="2") and `z3_replay_evidence_capture.md` §6 (V2 fields on CertificateIdentity).

### 4.1 Claim identity refs

A CertificateV2 is `persist(Claim)` where the Claim carries these identity references:

| Field | Type | Description |
|-------|------|-------------|
| `subjectId` | `string` | Identifier of the subject function/module |
| `outcome` | `CertificateStatus` | Current status (see §4.3) |
| `assuranceProfile` | `AssuranceProfile` | The assurance vector (Contract 3) |
| `specificationId` | `string` | `SpecID` from Contract 2 |
| `semanticProfileId` | `string` | `ProfileHash` from Contract 1 |
| `dependencySnapshotId` | `string` | Hash of the dependency snapshot at verification time |
| `evidenceBundleId` | `string` | Content hash of the EvidenceBundle |
| `policyId` | `string` | Identifier of the assurance policy applied |

### 4.2 OPTIONAL fields

These fields are OPTIONAL in the schema — their presence is governed by `AssuranceProfile.proofArtifactRequired` (Contract 3, §3.3), not by a mandatory schema:

| Field | Type | When present |
|-------|------|-------------|
| `smtHash` | `string` | When `replayable = true` or `kernelChecked = true` (SHA-256 of SMT script) |
| `proofArtifactDigest` | `string` | When `kernelChecked = true` (SHA-256 of proof artifact) |
| `translationIdentityHash` | `string` | When `translationTrust = true` (identity of the translation step) |

### 4.3 Schema version & legacy mapping

| Field | Value |
|-------|-------|
| `schemaVersion` | `"2"` |
| Legacy certs (`schemaVersion` absent or `"1"`) | Map to `csbNotCurrent` (Phase 5) |

`csbNotCurrent` is NOT yet present in `CertificateStatusBase` (certificate_types.nim:10-25). It MUST be added in Phase 5 as the classification for all V1/legacy certificates. V1 certs remain readable but are excluded from V2 promotion paths.

### 4.4 CertID (content-addressed)

```
CertID = H(specificationId, semanticProfileId, evidenceBundleId, policyId)
```

`CertID` is computed from the four identity refs only — it does NOT include optional fields (`smtHash`, `proofArtifactDigest`, `translationIdentityHash`). This ensures that adding optional evidence to a certificate does not change its identity.

### 4.5 Persist scope

Per `cert_writer.nim` (current behavior), the persisted JSON contains `status`, `smtlib2`, and `solverVersion` (from `BuildEnvZ3Version`). CertificateV2 extends this by adding the identity refs and optional fields above. The persist layer does NOT change — it remains a JSON write. The schema contract defines WHAT is written, not HOW.

---

## 5. Identity Ordering Principle

**CanonicalInput → CanonicalArtifact FIRST; hash identifies the result.**

The ordering is:

1. **CanonicalInput**: The canonical specification (SpecificationArtifact, Contract 2) is computed first. Its identity is `SpecID`.
2. **CanonicalArtifact**: The semantic profile (Contract 1) is applied to produce the canonical artifact. Its identity is `ProfileHash`.
3. **Hash of result**: The certificate identity (`CertID`, Contract 4) is computed from the canonical refs, NOT from "piling hashes together."

This principle means: do not attempt determinism by hashing a collection of sub-hashes. Instead, canonicalize the inputs first, then hash the canonicalized result. The hash identifies the result, not the process that produced it.

---

## 6. Negative Trust Seeds (Phase 9 mapping)

These contracts enable two negative trust seeds that will be formalized in Phase 9:

| Seed | Trigger | Detection | Phase 9 mapping |
|------|---------|-----------|-----------------|
| **SpecHash mismatch** | `SpecID` of the claim does not match the `specificationId` in the certificate | Recompute `SpecID` from the current spec artifact and compare | Phase 9 suite: `NegativeTrust_SpecHashMismatch` |
| **SemanticProfile mismatch** | `ProfileHash` of the claim does not match the `semanticProfileId` in the certificate | Recompute `ProfileHash` from the current SemanticProfileV1 and compare | Phase 9 suite: `NegativeTrust_SemanticProfileMismatch` |

Both seeds are ENABLED by these contracts because the contracts define the canonical computation of `SpecID` and `ProfileHash`. Without a frozen contract, there is no canonical computation to compare against.

---

## 7. GO Criteria

```
GO = ClaimIntegrity ∧ SpecProvenance ∧ SemanticSoundness ∧ DeterministicReplay ∧ FailClosed ∧ ClaimScopeIntegrity ∧ NegativeTrust ∧ ExternalE2E
```

Note: `VKS` (Verified Kernel Density) is NOT included in the GO criteria. VKS is a metric for verification density, not a gate criterion.

---

## 8. References

- `src/core/trusted/evidence_calculus.nim` — `EvidenceBundle`, `EvidenceFact`, `deriveAssurance`, `specProved`, `provenanceComplete`
- `src/core/trusted/private/evidence_identity.nim:14-51` — `CertificateIdentity`, `smtHash`/`proofArtifactDigest` optional-empty
- `src/core/types/certificate_types.nim` — `CertificateStatus`, `csbNotCurrent` (to be added in Phase 5)
- `src/verification/cert_writer.nim` — persist scope (`status`/`smtlib2`/`solverVersion`)
- `docs/design/cert_v2_issuance_boundary.md` — spec provenance gap map, V2 schemaVersion
- `docs/design/z3_replay_evidence_capture.md` — replay evidence anchor, V2 fields
