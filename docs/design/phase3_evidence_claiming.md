# Phase 3: Evidence→Claim Threading + Claim Model

**Status**: Design
**Date**: 2026-08-13
**Applies to**: Axiom integrity engine — Phase 3 claim-centric refactor
**Extends**: `docs/design/contract_freeze_phase1.md` (Phase 1 freeze: `SpecificationArtifact`, `SemanticProfileV1`, `AssuranceProfile`), `docs/design/cert_v2_issuance_boundary.md` (spec provenance gap map)

---

## 0. Source Grounding

| Source | Key type / function | Used in |
|--------|---------------------|---------|
| `src/core/trusted/evidence_calculus.nim:55-83` | `EvidenceBundle*`, `EvidenceFact*`, `deriveAssurance(int):int` | Contract 3 (assurance vector) |
| `src/core/trusted/private/evidence_identity.nim:14-51` | `CertificateIdentity*`; `smtHash`/`specOrigin`/`propertyFormula` OPTIONAL-empty today | Contract 4 (cert identity) |
| `src/verification/batch_uap/stages.nim:59-69` | `FinalReportCertInput*` — no spec fields | Spec-drop gap (§1) |
| `src/verification/batch_uap/loop_driver.nim:854` | `writeCertificateFromUapResult` call site — `leanProposition=""` default | Spec-drop gap (§1) |
| `src/verification/batch_uap/loop_depth_scheduler.nim:511` | Same call site — `leanProposition=""` default | Spec-drop gap (§1) |
| `src/verification/cert_writer.nim:80-164` | `writeCertificateFromUapResult` — constructs `CertificateIdentity` at line 149 without spec fields | Weld point (§1) |
| `src/core/trusted/specification_artifact.nim` | `SpecificationArtifact*`, `SpecID*`, `specIdentity()` | Claim `specId` source |
| `src/core/trusted/assurance_profile.nim` | `AssuranceProfile*`, `VerificationOutcomeRef*` | Claim `assurance` + `outcome` |
| `src/core/types/pipeline_core_types.nim:164` | `UniversalPipelineRequest.preConditions`/`postConditions: seq[string]` | IR pre/post evidence source |
| `src/core/ir/ir_types.nim:47-48` | `AxiomIRNode.preConditions*: seq[IRExpr]`, `postCondition*: Option[IRExpr]` | Evidence threading target |

---

## 1. Evidence Threading — The Spec-Drop Gap

### 1.1 Current Flow (pre-Phase 3)

IR functions carry `preConditions` (`seq[IRExpr]`) and `postCondition` (`Option[IRExpr]`) on `AxiomIRNode` (`ir_types.nim:47-48`). These are serialized to `seq[string]` (SMT-LIB2 assertions) and flow through the pipeline as follows:

```
AxiomIRNode.preConditions/postCondition (seq[IRExpr] / Option[IRExpr])
  → UniversalPipelineRequest.preConditions/postConditions (pipeline_core_types.nim:175-176, string-serialized)
  → UniversalPipelineResult.preConditions/postConditions (universal_pipeline_contract.nim:293-294)
  → buildFinalNodeReport constructs FinalReportCertInput     (stages.nim:449-459)
  → writeCertificateFromUapResult(certDir, ..., leanProposition="")  (loop_driver.nim:854, loop_depth_scheduler.nim:511)
  → CertificateIdentity constructed with formula: leanProposition (cert_writer.nim:149-155)
```

### 1.2 The Drop Points

| Drop | File | Line | What is lost |
|------|------|------|-------------|
| D1 | `stages.nim:59-69` | `FinalReportCertInput*` has no `specOrigin`, `specIdentity`, `preConditions`, `postConditions` fields | IR pre/post and spec identity never enter the cert input |
| D2 | `loop_driver.nim:854` | `writeCertificateFromUapResult` called with `leanProposition=""` (default) | The postcondition formula P is never passed to the cert writer |
| D3 | `loop_depth_scheduler.nim:511` | Same — `leanProposition=""` default | Same drop as D2 |
| D4 | `cert_writer.nim:149-155` | `CertificateIdentity` constructed with `formula: leanProposition` (always `""`) and `smtHash`/`specOrigin` never set | Identity digest computes over empty spec fields |

### 1.3 Weld Point — Where Phase 3 Must Thread Evidence

The exact weld point is `stages.nim:449-459` (`buildFinalNodeReport`) → `cert_writer.nim:80` (`writeCertificateFromUapResult`).

**What must ride into the claim at this weld point:**

1. `SpecificationArtifact.specOrigin` / `specIdentity` — the spec's provenance and content-addressed identity (`specification_artifact.nim:32-43`)
2. `IRExpr` pre/post conditions — the IR-level preconditions and postconditions from the verified function (`ir_types.nim:47-48`)
3. `SemanticProfileID` — the semantic profile hash that governed the verification (`semantic_profile.nim`)
4. `AssuranceProfile` — the multidimensional assurance vector derived from evidence (`assurance_profile.nim:36-42`)

These four items are currently available at the UAP request level (`UniversalPipelineRequest.preConditions`/`postConditions` at `pipeline_core_types.nim:175-176`) but are **discarded** at `stages.nim:449-459` when constructing `FinalReportCertInput`. Phase 3 adds them to `FinalReportCertInput` and threads them through `writeCertificateFromUapResult` into the `CertificateIdentity` construction at `cert_writer.nim:149-155`.

---

## 2. Small Claim — `VerifiedClaim`

### 2.1 Type Definition

```nim
VerifiedClaim* = object
  subjectId*: string                    # function under verification
  outcome*: VerificationOutcome          # PROVED / DISPROVED / UNKNOWN / UNSUPPORTED
  assurance*: AssuranceProfile           # vector, not tier — derived, not stored
  specId*: SpecID                        # H(canonicalSpecIR, origin, ruleVersion)
  semanticProfileId*: SemanticProfileID  # hash of the semantic contract
  dependencySnapshotId*: DependencySnapshotID
  obligationSetId*: ObligationSetID
  evidenceBundleId*: EvidenceBundleID
  policyId*: PolicyID
  claimId*: string                       # optional: H(claimProps) — deterministic receipt
```

(`claimId = H(claimProps)` optional — deterministic, not randomly generated.)

### 2.2 Derivation Rules (Phase 4, not Phase 3)

The following are DERIVED in Phase 4, not stored in the cert field store:

- `outcome` — derived from solver result + spec presence (`VerificationOutcomeRef` from `assurance_profile.nim:13-20`: `clProved`, `clDisproved`, `clUnknown`, `clUnsupported`)
- `assurance` — derived from `EvidenceBundle` via `deriveAssurance(int)` (`evidence_calculus.nim:88-101`)
- `claimId` — `H(subjectId + outcome + assurance + specId + semanticProfileId + dependencySnapshotId + obligationSetId + evidenceBundleId + policyId)`

### 2.3 What Phase 3 Defines vs Reuses

| Symbol | Status | Phase 3 Action |
|--------|--------|---------------|
| `VerifiedClaim*` | DOES NOT EXIST | **Define** — new type in `src/core/trusted/claim_model.nim` |
| `VerificationOutcome` | EXISTS as `VerificationOutcomeRef` enum (`assurance_profile.nim:13-20`) | **Reuse** — alias to `VerificationOutcome` for claim context |
| `AssuranceProfile` | EXISTS (`assurance_profile.nim:36-42`) | **Reuse** — Phase 3 stores it as a field; Phase 4 derives it |
| `SpecID` | EXISTS (`specification_artifact.nim:38`) | **Reuse** |
| `SemanticProfileID` | EXISTS (profile hash from `semantic_profile.nim`) | **Reuse** |
| `DependencySnapshotID` | DOES NOT EXIST | **Define** — opaque string ID; Phase 6 implements store |
| `ObligationSetID` | DOES NOT EXIST | **Define** — opaque string ID; Phase 6 implements store |
| `EvidenceBundleID` | DOES NOT EXIST | **Define** — opaque string ID; Phase 6 implements store |
| `PolicyID` | DOES NOT EXIST | **Define** — opaque string ID; Phase 6 implements store |
| `deriveAssurance` | EXISTS (`evidence_calculus.nim:88`) | **Reuse** — Phase 4 calls this to populate `assurance` |
| `EvidenceBundle` | EXISTS (`evidence_calculus.nim:72-74`) | **Reuse** — Phase 3 creates bundles from IR pre/post + spec |

---

## 3. CertV2 Schema = persist(claim)

### 3.1 Schema Version

- `schemaVersion = "2"` for CertV2 (up from `"1"` in `cert_writer.nim:148`)
- CertV2 is the **persisted form of `VerifiedClaim`** — the certificate blob IS the claim record

### 3.2 OUTCOME Not Writable by Writers (Phase 5)

- Writers (cert writer, UAP pipeline) may set: `subjectId`, `specId`, `semanticProfileId`, `dependencySnapshotId`, `obligationSetId`, `evidenceBundleId`, `policyId`, `assurance`
- Writers may NOT set `outcome` — it is computed by the verifier (Phase 4/5) and written to the certificate by the Judge role only
- The `claimId` is computed by the verifier from all other fields; writers must not fabricate it

### 3.3 Legacy → `csbNotCurrent` (Phase 5)

- CertV1 (`schemaVersion = "1"`) certificates remain readable but are tagged `csbNotCurrent` in the status field
- `csbNotCurrent` is a new `CertificateStatus` value (`certificate_types.nim:10-26`) indicating a V1 cert that has not been upgraded to V2
- Phase 5 migration: re-run `ax prove` on V1 certs to produce V2 certs with full claim threading

### 3.4 CertificateIdentity Extension for CertV2

Add to `CertificateIdentity` (`evidence_identity.nim:14-51`):

- `specOrigin*: string` — populated from `SpecificationArtifact.origin`
- `specIdentity*: string` — populated from `SpecificationArtifact.specIdentity()`
- `claimId*: string` — the deterministic claim hash (Phase 3 populates; Phase 5 locks)
- `schemaVersion*: string` — `"2"` for CertV2, `"1"` for CertV1

The `identityDigest` function (`evidence_identity.nim:38-51`) already includes all `CertificateIdentity` fields in its hash, so adding these fields automatically extends the digest scope.

---

## 4. Phase Roadmap

### 4.1 Phase 3 Deliverables (this document)

| Deliverable | Location |
|-------------|----------|
| `VerifiedClaim*` type definition | New: `src/core/trusted/claim_model.nim` |
| `FinalReportCertInput` extended with spec fields | `src/verification/batch_uap/stages.nim:59-69` |
| `writeCertificateFromUapResult` extended with spec + pre/post params | `src/verification/cert_writer.nim:80-164` |
| `CertificateIdentity` extended with `specOrigin`, `specIdentity`, `claimId`, `schemaVersion` | `src/core/trusted/private/evidence_identity.nim:14-51` |
| Weld point: `buildFinalNodeReport` passes spec + pre/post into `FinalReportCertInput` | `src/verification/batch_uap/stages.nim:449-459` |
| Weld point: both call sites pass `leanProposition` from `FinalReportCertInput` | `loop_driver.nim:854`, `loop_depth_scheduler.nim:511` |
| `DependencySnapshotID`, `ObligationSetID`, `EvidenceBundleID`, `PolicyID` type aliases | New: `src/core/trusted/claim_model.nim` |

### 4.2 Phase 3 Must NOT Touch

| Item | Reason |
|------|--------|
| `VerifiedSet` index | Phase 6: `ClaimStore` + `VerifiedSet` index + invariant |
| `ClaimStore` persistence | Phase 6 |
| T0 replay | Phase 7 |
| Baseline + classifier | Phase 8 |
| `outcome` writer logic | Phase 5 — writers must not set `outcome` |
| CertV1→V2 migration | Phase 5 |
| `csbNotCurrent` status | Phase 5 |

### 4.3 Phase 4 (next)

- Wire `deriveAssurance` into the claim population path
- Compute `outcome` from solver result + spec presence
- Compute `claimId = H(claimProps)` deterministically
- Populate `EvidenceBundle` from IR pre/post + solver result + spec

### 4.4 Phase 5 (next)

- CertV2 issuance: `schemaVersion = "2"`, `claimId` in `CertificateIdentity`
- Writers cannot set `outcome` — enforced by role separation
- `csbNotCurrent` for legacy V1 certs
- Migration path for existing V1 certificates

### 4.5 Phase 6 (next)

- `ClaimStore` — persistent store for `VerifiedClaim` records
- `VerifiedSet` index — dense bitset over verified node IDs
- Invariant: every claim in `ClaimStore` has a corresponding entry in `VerifiedSet`

### 4.6 Phase 7 (next)

- T0 replay: deterministic reproduction of verification results from claim + evidence bundle
- Replay evidence captured via `smtHash`/`proofArtifactDigest` anchors

### 4.7 Phase 8 (next)

- Baseline + classifier: compare new claims against historical baselines
- Classify claims by risk tier using `AssuranceProfile` dimensions

---

## 5. Invariants

1. **I1**: `VerifiedClaim.assurance` is a vector (`AssuranceProfile`), not a scalar tier. The tier is a projection computed by `deriveAssurance` in Phase 4.
2. **I2**: `outcome` is never written by a certificate writer. Writers populate identity + evidence fields only; the Judge writes `outcome`.
3. **I3**: `claimId` is deterministic — same claim props always produce the same `claimId`. No random or timestamp-based IDs.
4. **I4**: `FinalReportCertInput` is the single data structure that carries evidence from the UAP pipeline to the certificate writer. All spec/IR evidence must pass through it.
5. **I5**: `CertificateIdentity` fields `smtHash`, `specOrigin`, `propertyFormula` are OPTIONAL-empty today (Phase 1 freeze). Phase 3 populates them; Phase 5 locks them as non-optional in CertV2.
6. **I6**: `EvidenceBundle` facts (`solverProved`, `translationProved`, `specProved`, etc.) are populated from the UAP result, not from the certificate writer. The writer persists the bundle; it does not fabricate facts.