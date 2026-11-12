# ADR-0013: Identity Algebra — Single Authoritative Identity System (C19)

## Status
Accepted

## Context
The Axiom project previously maintained two parallel identity systems — `verification_identity.nim` and `semantic_identity.nim` — with overlapping and conflicting type definitions. This duplication was the true architectural smell; the observed LCOM of 0.73 was a symptom, not a design goal. The two systems exported conflicting `Identity`-derived types, creating ambiguity about which module owned which notion of identity and making the import graph cyclic.

## Invariants

- **identity ≠ mapping ≠ ordering ≠ hash.** Each concept has a distinct semantic role and a distinct module home.
- `semantic_identity` MUST NOT import `canonical_identity` or `evidence_identity`.
- `identity_mapping` is separate from all identity modules — it holds mapping tables only.
- `fingerprint` is a content-derived integrity value, not an identity. It derives from canonical CHC bytes, not from any identity type.
- `TransitionOrdinal` stays in `semantic_identity` — identity is not ordering expressed structurally.
- `NodeId` stays in `verification_model_types.nim` (leaf).

## Decision
Split the identity model into a single authoritative system with a unidirectional import DAG:

```
identity_core.nim
  → {semantic_identity.nim, canonical_identity.nim, evidence_identity.nim}
    → identity_mapping.nim
```

### Module responsibilities

| Module | Exports | Notes |
|--------|---------|-------|
| `identity_core.nim` | `RelationId` | Leaf. Real consumers: `canonical_chc_compiler`, `verification_obligations`. |
| `semantic_identity.nim` | `TransitionIdentity`, `TransitionOrdinal` + `transitionIdentityOf`, `canonicalKey` | Mapping types removed; `verification_identity` export removed. |
| `canonical_identity.nim` | `StateSignature`, `RelationIdentity`, `CanonicalIdentity` | |
| `evidence_identity.nim` | `CertificateIdentity`, `EvidenceIdentity(certificate)` | |
| `identity_mapping.nim` | `SemanticToCanonicalMap` + `setNodeMapping` | Dead `CanonicalToEvidenceMap`, `lookupNode`, `lookupRelation` deleted. |

### Dead-code decisions
- **Deleted**: `BackendId`, `ObligationFamily`, `ObligationIdentity`, `SemanticIdentity` (zero real-code consumers).
- **Deleted**: `CanonicalToEvidenceMap`, `lookupNode`, `lookupRelation` (dead symbols in `identity_mapping.nim`).
- **Removed entirely**: `verification_identity.nim` and all its symbols (`SemanticEncodingMap`, `EncodingEvidenceMap`, `setMapping`, `lookupEncoding`, `lookupSemantic`, `mapEvidence`, `lookupEvidence`, `EncodingIdentity`, `SemanticNodeId`, `SemanticTransitionId`, `SemanticObligationId`, `CandidateEvidenceId`, `EvidenceFingerprint`, `EvidenceIdentity-vi`).

### Placement decisions
- `NodeId` stays in `verification_model_types.nim` (leaf module, no identity-module dependency).
- `TransitionOrdinal` stays in `semantic_identity.nim` (identity is not ordering; ordering is expressed structurally).

### Anti-patterns prohibited
- **LCOM ≤ 0.6 is NOT a design goal.** LCOM is an observational diagnostic, not a splitting criterion.
- No metric-driven further splitting.
- No metric gaming (e.g., type-only modules passing via `lcom=0.0` when `functionCount < 2`).
- No `lcomOverrides`.
- Dead-code principle: "Do not pre-create types for future use; only the contract needed now exists."

## Consequences
1. **Single identity ownership** — every identity concept has exactly one canonical home module.
2. **Dead code removed** — `BackendId`, `ObligationFamily`, the entire `verification_identity.nim`, and dead mapping symbols are deleted.
3. **Unidirectional import DAG** — no cycles; mapping imports identity, never the reverse.
4. **Consumer semantics unchanged** — `canonical_chc_compiler` and `verification_obligations` still receive `RelationId` from `identity_core`; no behavioral change for existing consumers.
5. **Deterministic serialization preserved** — the C8 determinism boundary (see `docs/spec/identity_algebra_determinism.md`) remains intact: same SemanticModel + same EncodingConfig + same CompilerSchemaVersion → same Canonical CHC bytes → same fingerprint.

## References
- `src/core/trusted/private/identity_core.nim`, `src/core/trusted/private/semantic_identity.nim`, `src/core/trusted/private/canonical_identity.nim`, `src/core/trusted/private/evidence_identity.nim`, `src/core/trusted/private/identity_mapping.nim`
- `docs/spec/z3_pool_determinism.md` — Z3 non-determinism exclusion
- ADR-0001 (Fail-Closed Result Type) — fail-closed pattern applied to identity resolution errors