# Phase 4: Certificate V2 — Projection of VerifiedClaim

**Status**: Design  
**Date**: 2026-08-14  
**Applies to**: Axiom integrity engine — Phase 4 cert projection  
**Extends**: `docs/design/phase3_evidence_claiming.md` (Phase 3 `VerifiedClaim` model), `docs/design/cert_v2_issuance_boundary.md` (issuance boundary)

---

## 0. Root Invariant

**Certificate never determines the Claim; written as `serialize(claim)`.**

The certificate is a *persisted projection* of a `VerifiedClaim`. The Claim is the authority; the Certificate is the persist. No field on the certificate may be used to *derive* or *override* the claim's authority. The `outcome` field on a CertV2 blob is a mirror of `claim.outcome`, never an independent decision.

---

## 1. CertificateV2 Type

```nim
CertificateV2* = object {.axiomDecision(
  id = "DECISION-0701",
  reason = "CertV2 = projection of VerifiedClaim; identity refs + optional evidence per AssuranceProfile",
  adr = "docs/spec/certv2_projection.md",
  introduced = "v40").}
  identityDigest*: string            # H(schemaVersion + claim fields)
  schemaVersion*: string             # "2"
  claimId*: string                   # deterministic: H(claimProps)
  subjectId*: string                 # function under verification
  specId*: string                    # H(canonicalSpecIR, origin, ruleVersion)
  semanticProfileId*: string         # ProfileHash(SemanticProfileV1)
  policyId*: string                  # content-addressed policy digest
  obligationId*: string              # opaque obligation set reference
  evidenceId*: string                # opaque evidence bundle reference
  depSnapshotId*: string             # dependency snapshot reference
  outcome*: VerificationOutcomeRef   # derived from claim, NOT written by cert writer
  assurance*: AssuranceProfile       # vector; drives evidence presence
  smtHash*: Option[string]           # optional; populated only when profile requires SMT evidence
  proofArtifactDigest*: Option[string] # optional; populated only when profile requires proof artifact
```

**Key design decisions**:

- `smtHash` and `proofArtifactDigest` are `Option[string]` — they are **NOT mandatory fields**. Their presence is driven by the `AssuranceProfile` dimensions (`adSolved`, `adKernelChecked`, `adReplayable`, `adProvenanceComplete`), not by a schema requirement. See `assurance_profile.nim:69` (`proofArtifactRequired`) which decides artifact necessity from the profile, not from the certificate schema.
- `outcome` is a **read-only projection** of `claim.outcome`. The cert writer never selects or sets it.
- `identityDigest` is computed over all identity fields (see §3).

---

## 2. Write Gate — Writer Must NOT Set Outcome

### 2.1 Gate Rule

`writeCertificateFromUapResult` (`cert_writer.nim:80`) and any CertV2 writer **must not** set the `outcome` field. The writer populates identity + evidence fields only. `outcome` is written exclusively by the Judge role (the `ax prove` runtime's verification result, derived from solver status + spec presence).

### 2.2 Enforcement

At the `persist(claim: VerifiedClaim)` boundary, the writer calls `deriveCert(claim, profile)` which projects the claim into a `CertificateV2` with `outcome` taken **only** from `claim.outcome`. The writer's own status-selection logic (currently `tierToCertStatus` at `cert_writer.nim:52-69`) is bypassed for CertV2 — the `outcome` comes from the claim, not from the tier/status enum.

```nim
# Writer gate pseudocode (enforced at compile time via role separation):
proc persist*(claim: VerifiedClaim; profile: AssuranceProfile): CertificateV2 =
  let cert = deriveCert(claim, profile)   # outcome ← claim.outcome ONLY
  serialize(cert)                          # writes to disk; never re-derives outcome
```

Any code path that attempts to set `outcome` from a `CertificateStatus` or `VerificationTier` in the writer is a **gate violation** and must be rejected by the static gate scanner.

---

## 3. Identity Digest & Schema Version

### 3.1 schemaVersion = "2"

`schemaVersion` is `"2"` for CertV2 (up from `"1"` in `cert_writer.nim:148`). The `identityDigest` (`evidence_identity.nim:38-51`) is extended to include CertV2-specific fields:

```nim
func identityDigest*(cert: CertificateV2): string {.raises: [].} =
  let fields = @[
    cert.schemaVersion,
    cert.claimId,
    cert.subjectId,
    cert.specId,
    cert.semanticProfileId,
    cert.policyId,
    cert.obligationId,
    cert.evidenceId,
    cert.depSnapshotId,
    $cert.outcome,
    $cert.assurance
  ]
  computeCertificateIdentity(fields)     # fingerprint_generator.nim:16-23
```

### 3.2 Legacy Handling → `csbNotCurrent`

CertV1 certificates (`schemaVersion = "1"` or absent) are classified as `csbNotCurrent` in the status field. `csbNotCurrent` is a new `CertificateStatusBase` value to be added to `certificate_types.nim:10-26` (currently **not yet present** — this is a Phase 4 addition).

| `schemaVersion` | Classification | Behavior |
|-----------------|---------------|----------|
| `"2"` | **CertV2** — full claim projection | Full processing; `outcome` sourced from claim only |
| `"1"` (or absent) | **CertV1 / Legacy** — `csbNotCurrent` | Readable but **not a promotion basis**; must be re-issued via `ax prove` to produce CertV2 |
| Missing key | **Corrupt / Unknown** | Treat as legacy (`csbNotCurrent`); logged as warning |

---

## 4. deriveCert (Projection) vs serialize

Two distinct operations separate projection from persistence:

| Operation | Input | Output | Role |
|-----------|-------|--------|------|
| `deriveCert(claim, profile)` | `VerifiedClaim`, `AssuranceProfile` | `CertificateV2` (in-memory) | **Projection** — maps claim fields to cert schema; `outcome` comes from claim |
| `serialize(cert)` | `CertificateV2` | JSON blob on disk | **Persistence** — writes identity + evidence fields; never re-derives `outcome` |

`deriveCert` is the **only** place where claim fields are mapped to certificate fields. `serialize` is a pure write with no logic. This separation ensures the writer cannot introduce a new `outcome` decision — the projection has already resolved it.

---

## 5. Anti-Stale: Content-Addressed Invalidation

`specId`, `semanticProfileId`, and `policyId` are **content-addressed** digests:

- `specId` = `H(canonicalSpecIR, origin, ruleVersion)` — see `specification_artifact.nim:41` (`SpecID = string`) and `specification_artifact.nim:43-47` (`specIdentity`)
- `semanticProfileId` = `ProfileHash(SemanticProfileV1)` — see `semantic_profile.nim:90`
- `policyId` = content hash of the policy rule set in effect at claim time

**Auto-invalidation rule**: If any of `specId`, `semanticProfileId`, or `policyId` in an existing CertV2 does not match the current system state, the certificate is **automatically invalid** — it cannot be promoted, extended, or used as a basis for further verification. A re-run of `ax prove` is required to produce a fresh CertV2 with updated content-addressed IDs.

This means a spec change, policy change, or semantic profile change **immediately invalidates** all existing certificates that reference the old content — no manual expiry needed.

---

## 6. Schema Table

| Field | Type | Required | Source | Notes |
|-------|------|----------|--------|-------|
| `identityDigest` | `string` | Yes | Computed | SHA-256 over all identity fields |
| `schemaVersion` | `string` | Yes | Literal `"2"` | Distinguishes CertV2 from CertV1 |
| `claimId` | `string` | Yes | `H(claimProps)` | Deterministic; same claim → same ID |
| `subjectId` | `string` | Yes | `VerifiedClaim.subjectId` | Function under verification |
| `specId` | `string` | Yes | `SpecificationArtifact.specIdentity()` | Content-addressed; auto-invalid on change |
| `semanticProfileId` | `string` | Yes | `ProfileHash(SemanticProfileV1)` | Content-addressed; auto-invalid on change |
| `policyId` | `string` | Yes | Policy rule set hash | Content-addressed; auto-invalid on change |
| `obligationId` | `string` | Yes | Obligation set reference | Opaque; carried from claim |
| `evidenceId` | `string` | Yes | Evidence bundle reference | Opaque; carried from claim |
| `depSnapshotId` | `string` | Yes | Dependency snapshot reference | Opaque; carried from claim |
| `outcome` | `VerificationOutcomeRef` | Yes | `claim.outcome` | **Writer must NOT set**; projected from claim |
| `assurance` | `AssuranceProfile` | Yes | `claim.assurance` | Vector; drives evidence presence |
| `smtHash` | `Option[string]` | No | Profile-driven | Only when `adSolved` dimension is true |
| `proofArtifactDigest` | `Option[string]` | No | Profile-driven | Only when `proofArtifactRequired(profile)` is true |

---

## 7. Migration / Legacy Policy

### 7.1 CertV1 → CertV2 Migration

1. Existing CertV1 certificates (`schemaVersion = "1"`) are **not automatically upgraded**.
2. They are classified as `csbNotCurrent` on load.
3. Migration requires re-running `ax prove` on the source function, which produces a new CertV2 certificate with full claim threading.
4. CertV1 certificates remain readable for audit/inspection but **cannot serve as promotion basis** for CertV2 paths.

### 7.2 Legacy → `csbNotCurrent`

- `csbNotCurrent` is added to `CertificateStatusBase` in `certificate_types.nim:10-26` (after `csbSoundnessDebt`).
- All CertV1 certs loaded without `schemaVersion = "2"` receive `csbNotCurrent` status.
- `parseCertificateStatus` in `certificate_types.nim:65-83` is extended with `"certNotCurrent"` → `csbNotCurrent`.

### 7.3 Negative-Trust Seeds for Phase 4

Negative-Trust seeds define the **failure modes** that Phase 4 must detect and reject:

| Seed | Condition | Action |
|------|-----------|--------|
| **Legacy → NOT_CURRENT** | `schemaVersion = "1"` or absent | Classify as `csbNotCurrent`; exclude from CertV2 promotion paths; require re-issuance via `ax prove` |
| **specHash mismatch → reject** | `specId` in cert does not match current `specification_artifact.specIdentity()` | Certificate is **auto-invalidated**; cannot be used as verification basis; must be re-proved |
| **semanticProfileId mismatch → reject** | `semanticProfileId` in cert does not match current `ProfileHash(globalProfile)` | Certificate is **auto-invalidated**; same as specHash mismatch |
| **policyId mismatch → reject** | `policyId` in cert does not match current policy hash | Certificate is **auto-invalidated**; same as specHash mismatch |
| **Writer sets outcome → gate violation** | CertV2 writer attempts to set `outcome` from `CertificateStatus` or `VerificationTier` | **Reject at write gate**; static gate scanner flags this as a theater violation (§0.9) |
| **Empty claimId → reject** | `claimId` is empty or `""` | Certificate is malformed; reject at write time |

---

## 8. References

| Source | Key type / function | Used in |
|--------|---------------------|---------|
| `src/verification/cert_writer.nim:80` | `writeCertificateFromUapResult` | Cert writer entry point; must not set `outcome` for CertV2 |
| `src/core/trusted/private/evidence_identity.nim:14-51` | `CertificateIdentity`; `identityDigest` | Identity digest computation; extended for CertV2 |
| `src/core/types/certificate_types.nim:10-26` | `CertificateStatusBase` | `csbNotCurrent` to be added here |
| `src/core/trusted/assurance_profile.nim:13-20` | `VerificationOutcomeRef` | `outcome` type on `CertificateV2`; also the claim authority |
| `src/core/trusted/assurance_profile.nim:36-42` | `AssuranceProfile` | Drives optional evidence presence (`smtHash`, `proofArtifactDigest`) |
| `src/core/trusted/assurance_profile.nim:69` | `proofArtifactRequired` | Decides if proof artifact is needed from profile, not schema |
| `src/core/trusted/specification_artifact.nim:41-47` | `SpecID`; `specIdentity` | `specId` content-addressing |
| `src/core/trusted/semantic_profile.nim:90` | `ProfileHash` | `semanticProfileId` content-addressing |
| `src/core/trusted/evidence_calculus.nim:34-38` | `EvidenceBundle` with `smtHash`, `proofArtifactDigest` | Evidence optional fields on CertificateV2 |
| `src/core/trusted/fingerprint_generator.nim:16-23` | `computeCertificateIdentity` | Deterministic identity digest |
| `docs/design/phase3_evidence_claiming.md` | `VerifiedClaim` type (§2.1) | Claim authority; `outcome` sourced from here |
| `docs/design/cert_v2_issuance_boundary.md` | Issuance boundary gap map | Context for Phase 4 projection |