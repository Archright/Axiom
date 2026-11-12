# Phase 5: ClaimStore Index — Rich Per-Symbol Claim Records alongside VerifiedSet

**Status**: Design
**Date**: 2026-08-14
**Applies to**: Axiom integrity engine — Phase 5 claim-store index
**Extends**: `docs/design/phase3_evidence_claiming.md` (Phase 3 claim model), `docs/design/cert_v2_issuance_boundary.md`

---

## 0. Source Grounding

| Source | Key type / function | Used in |
|--------|---------------------|---------|
| `src/core/topology/verified_set.nim:15-16` | `VerifiedSet*` — `seq[uint64]` dense bitset over `NodeId` | Production fast-membership index |
| `src/verification/verified_set_hydration.nim:150` | `hydrateVerifiedSetFromProofVault*` — single chokepoint that builds VerifiedSet from proof vault JSON | Both VerifiedSet and ClaimStore are built here |
| `src/core/types/certificate_types.nim:176-206` | `FunctionCertificate*` — closest existing per-symbol record (functionName, modulePath, status, fingerprint, etc.) | Template for ClaimStore record shape |
| `src/verification/proof_state_projection.nim:16-22` | `CertificateProjection*` — per-node map (`Table[string, CertificateProjection]`) loaded from cert dir | Per-node projection used by convergence + frontier |
| `src/core/topology/verified_frontier.nim:38-93` | `computeVerifiedFrontier*` — consumes `VerifiedSet` for dependency-satisfied candidate selection | READ consumer: frontier |
| `src/core/gate/scheduler.nim:17-25` | `SchedulerState*` — per-node duration tracking, priority queue | READ consumer: scheduler |
| `src/cli/axiom_engine.nim:616-732` | Orchestrator: calls `hydrateVerifiedSetFromProofVault`, then `computeVerifiedFrontier`, then `runBatchVerification` | Primary READ consumer site |

---

## 1. Current State

### 1.1 VerifiedSet — Production Bitset

`VerifiedSet` (`verified_set.nim:15-16`) is a dense bitset over interned `NodeId` handles using `seq[uint64]`. It provides O(1) `contains`, `incl`, `popcount`, and `isEmpty` — all `func`/`noSideEffect` to satisfy Axiom's static-effect discipline. It is the **production fast-membership index**: every `ax prove` call builds it via `hydrateVerifiedSetFromProofVault` and then queries it in the frontier, scheduler, and batch-verification paths.

### 1.2 Single Chokepoint: `hydrateVerifiedSetFromProofVault`

`hydrateVerifiedSetFromProofVault` (`verified_set_hydration.nim:150-199`) is the sole function that scans `vaultDir/*.json`, applies `certificateAccepted` filtering (status, evidence, soundness mode, vcHash/sourceHash validation, kernel scope filter), interns node IDs, and populates a `VerifiedSet`. This is the exact site where a parallel `ClaimStore` can also be built — the same loop that decides "is this node verified?" can simultaneously decide "what is the rich claim for this node?"

### 1.3 FunctionCertificate — Closest Per-Symbol Record

`FunctionCertificate` (`certificate_types.nim:176-206`) is the closest existing per-symbol record. It carries `functionName`, `modulePath`, `certificatePath`, `fingerprint`, `status` (`CertificateStatus`), `reason`, `calls`, `accessedResources`, `mutatedResources`, `imports`, `constraints`, `selfHealingAsserts`, `recoveredDefects`, `retryCount`, `winningStrategy`, `axiomId`, `axiomVersion`, `axiomHash`, `leanArtifactHash`, `linkageVerified`, `informationGain`, `verificationTier`, `irHash`. It is the natural template for a `ClaimStore` record.

### 1.4 proof_state_projection — Per-Node Map

`CertificateProjection` (`proof_state_projection.nim:16-22`) is a per-node projection (`path`, `label`, `modulePath`, `functionName`, `status`, `node: JsonNode`) loaded from certificate JSON files. `loadCertificateProjections` (`proof_state_projection.nim:123-148`) returns `Table[string, CertificateProjection]` keyed by label. This is the existing per-node map that `proof_state_convergence.nim` and `proof_state_projection.nim` consumers use. The ClaimStore will supersede this as the "rich" per-symbol store, while `CertificateProjection` remains the lean projection for convergence/sync.

---

## 2. Proposed ClaimStore Type

### 2.1 Type Definition

```nim
## ClaimStore — rich per-symbol claim records, parallel to VerifiedSet.
##
## Invariant: s ∈ VerifiedSet  ⇒  ∃ ClaimStore entry with outcome=PROVED.
## The ClaimStore is built at the same chokepoint as VerifiedSet
## (hydrateVerifiedSetFromProofVault) and is consumed by the
## "rich" readers (evidence queries, audit, reporting) while
## VerifiedSet serves the hot-path membership checks.

type
  ClaimOutcome* = enum
    coProved      ## Verified — PROVED (matches VerifiedSet entry)
    coDisproved   ## Verified — DISPROVED (counterexample found)
    coUnknown     ## Verified — outcome unknown (e.g. timeout, resource limit)
    coUnsupported ## Not verified — unsupported by current prover stack
    coPending     ## Certificate present but not yet resolved

  ClaimRecord* = object
    ## Per-symbol claim record — the "rich" alternative to the bitset.
    ## Reuses FunctionCertificate fields where applicable; adds
    ## claim-specific fields (outcome, evidence refs, proof artifact).
    functionName*: string
    modulePath*: string
    certificatePath*: string
    status*: CertificateStatus          # from certificate_types.nim
    outcome*: ClaimOutcome              # PROVED / DISPROVED / UNKNOWN / UNSUPPORTED / PENDING
    fingerprint*: string                # source fingerprint (stable across re-hydration)
    leanArtifactHash*: string           # SHA-256 of the .lean proof artifact
    axiomId*: string                    # referenced axiom identifier
    axiomHash*: string                  # SHA-256 of axiom definition at certification time
    verificationTier*: VerificationTier # Phase 4A tier
    irHash*: string                     # IR hash for cross-validation
    evidenceBundleId*: string           # opaque ID linking to EvidenceBundle (Phase 3)
    claimId*: string                    # deterministic: H(functionName + modulePath + outcome + ...)

  ClaimStore* = object
    ## Map from interned NodeId string key → ClaimRecord.
    ## Parallel to VerifiedSet: same population loop, different access pattern.
    claims*: Table[string, ClaimRecord]

  ClaimStoreSnapshot* = object
    ## Immutable snapshot for read-side consumers.
    ## Built once per hydration pass, shared across frontier/scheduler/readers.
    byNodeId*: Table[string, ClaimRecord]
    byFunction*: Table[string, ClaimRecord]  # keyed by functionName for fast lookup
```

### 2.2 Design Rationale

| Decision | Reason |
|----------|--------|
| `Table[string, ClaimRecord]` keyed by NodeId string | Matches `VerifiedSet`'s interned NodeId key space; enables O(1) lookup alongside `contains` |
| `ClaimOutcome` enum (not `CertificateStatus`) | Separates verification *outcome* (PROVED/DISPROVED) from certificate *status* (certGreen/certRed); the invariant maps `coProved` → `VerifiedSet membership`, not `certGreen` → membership |
| `claimId` deterministic hash | Follows Phase 3 `VerifiedClaim` convention (`claimId = H(claimProps)`); no random/timestamp IDs |
| `ClaimStoreSnapshot` as immutable read side | Readers (frontier, scheduler, convergence) get a frozen view; writers only mutate during hydration |
| `byFunction` secondary index | Enables lookup by `functionName` without iterating — needed by `collectVerifiedFuncNames`-style consumers |

---

## 3. Build / Hydration Alongside VerifiedSet

### 3.1 Modified Chokepoint

`hydrateVerifiedSetFromProofVault` (`verified_set_hydration.nim:150`) is extended to return a tuple `(VerifiedSet, ClaimStoreSnapshot)` instead of just `VerifiedSet`. The same loop that calls `certificateAccepted` and `result.incl(nodeIdOpt.get())` simultaneously populates the `ClaimStore.claims` table with a `ClaimRecord` for every accepted certificate.

```nim
# Proposed signature change at verified_set_hydration.nim:150:
proc hydrateVerifiedSetFromProofVault*(
  vaultDir: string;
  internPool: InternPoolSnapshot;
  analysis: TopologyAnalysis;
  contentResolver: ModuleContentResolver;
  scope: KernelScopeInfo
): (VerifiedSet, ClaimStoreSnapshot) {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].}
```

### 3.2 ClaimRecord Construction

For each accepted certificate, the `ClaimRecord` is populated from the JSON node fields using the same extraction pattern as `certificateAccepted` (lines 63-148). Fields map directly from `FunctionCertificate`-compatible keys: `functionName`, `modulePath`, `certificatePath`, `status`, `fingerprint`, `leanArtifactHash`, `axiomId`, `axiomHash`, `verificationTier`, `irHash`. The `outcome` is derived from `CertificateStatus`: `certGreen`/`certVerifiedAxiom`/`certZ3Verified`/`certLeanVerified`/`certDualVerified` → `coProved`; `certRed` → `coDisproved`; `certPending`/`certYellow` → `coUnknown`; all others → `coUnsupported`.

### 3.3 ClaimStore Invariant

**I1 (Core Invariant)**: For every `s ∈ VerifiedSet`, there exists a `ClaimRecord` in `ClaimStore` with `outcome = coProved` and matching `functionName` + `modulePath`.

**I2 (Completeness)**: Every certificate accepted by `certificateAccepted` produces a `ClaimRecord` in the store. No accepted certificate is silently dropped from the ClaimStore.

**I3 (Determinism)**: Given the same `vaultDir` + `internPool` + `analysis`, `hydrateVerifiedSetFromProofVault` produces identical `(VerifiedSet, ClaimStoreSnapshot)` on every call. No randomness, no timestamps, no side effects.

**I4 (Subset)**: `ClaimStore.claims` may contain entries for symbols NOT in `VerifiedSet` (e.g., `coDisproved`, `coUnknown`), but every `VerifiedSet` member MUST have a corresponding `coProved` entry.

---

## 4. Invariant Test

A new test function `verifyClaimStoreInvariant` is added (not to source — design only) that:

1. Calls `hydrateVerifiedSetFromProofVault` on a known vault directory.
2. Iterates `VerifiedSet.bits` to enumerate all set NodeIds.
3. For each set NodeId, looks up the corresponding `ClaimRecord` in `ClaimStoreSnapshot.byNodeId`.
4. Asserts: entry exists AND `outcome == coProved`.
5. Also asserts the reverse: every `coProved` entry in `ClaimStore` has its NodeId present in `VerifiedSet`.

This is a pure `func`/`noSideEffect` check over the returned snapshot, consistent with Axiom's static-effect discipline.

---

## 5. READ Consumer Mapping

### 5.1 Frontier Consumer (`verified_frontier.nim:38-93`)

**Current**: Consumes `VerifiedSet` via `contains` to check dependency satisfaction and membership. Pure bitset — O(1) per check, no per-symbol data needed.

**Phase 5**: No change. Frontier continues to read `VerifiedSet` only. It does NOT need ClaimStore — it only asks "is this node verified?" not "what is the proof detail?"

### 5.2 Scheduler Consumer (`scheduler.nim:17-64`)

**Current**: Consutes `VerifiedSet.popcount()` as `historicalVerified` metric (`axiom_engine.nim:732`). Does not call `VerifiedSet.contains` directly.

**Phase 5**: No change. Scheduler continues to read `VerifiedSet.popcount()` only. It does NOT need ClaimStore.

### 5.3 Hydration Consumer (`verified_set_hydration.nim:150-199`)

**Current**: This IS the build site. It produces `VerifiedSet` and returns it.

**Phase 5**: This site is extended to also produce `ClaimStoreSnapshot`. The same loop that builds the bitset also builds the claim records. The return type changes from `VerifiedSet` to `(VerifiedSet, ClaimStoreSnapshot)`.

### 5.4 "Rich" ClaimStore Consumers (new, Phase 5)

These are consumers that currently have NO access to per-symbol claim data and would benefit from `ClaimStoreSnapshot`:

| Consumer | Current Access | Phase 5 Access | What It Gains |
|----------|---------------|----------------|---------------|
| **Evidence query / audit** | None (must re-read vault JSON) | `ClaimStoreSnapshot.byNodeId` | Instant per-symbol claim lookup without I/O |
| **Proof report rendering** | `collectVerifiedFuncNames` (engine.nim:237) — only names | `ClaimStoreSnapshot.byFunction` | Full claim detail: outcome, tier, artifact hash, axiomId |
| **Convergence checker** | `CertificateProjection` (lean projection) | `ClaimStoreSnapshot` (rich record) | Outcome + evidenceBundleId + claimId for deterministic convergence |
| **VKD metrics** | `VerifiedSet.popcount()` only | `ClaimStoreSnapshot` + `VerifiedSet` | Breakdown by outcome (PROVED vs DISPROVED vs UNKNOWN) |
| **Spec drift detection** | None | `ClaimStoreSnapshot.byFunction` | Compare claim `irHash` / `axiomHash` against current spec |

### 5.5 Consumer Summary

```
hydrateVerifiedSetFromProofVault  ──→  (VerifiedSet, ClaimStoreSnapshot)
        │                                    │
        ├──→ computeVerifiedFrontier         │  (READ: bitset membership only)
        │                                    ├──→ EvidenceQuery  (READ: rich claim lookup)
        ├──→ runBatchVerification           │  (READ: bitset + popcount)
        │                                    ├──→ ProofReport   (READ: rich claim detail)
        ├──→ collectVerifiedFuncNames       │  (READ: bitset → names)
        │                                    └──→ VKDMetrics    (READ: popcount + outcome breakdown)
        └──→ loadVerifiedAxiomsFromProofVault (unchanged, separate)
```

---

## 6. Blast Radius

| File | Change | Additive? |
|------|--------|-----------|
| `src/core/topology/verified_set.nim` | **No change** — bitset stays as-is | — |
| `src/verification/verified_set_hydration.nim` | Extend return type to `(VerifiedSet, ClaimStoreSnapshot)`; populate ClaimStore in the same loop | Additive |
| `src/core/types/certificate_types.nim` or new `src/core/types/claim_store.nim` | Define `ClaimOutcome`, `ClaimRecord`, `ClaimStore`, `ClaimStoreSnapshot` | Additive (new file) |
| `src/cli/axiom_engine.nim` | Update call site at line 616 to destructure tuple; pass `ClaimStoreSnapshot` to new rich consumers | Additive |

**Total**: 2–3 additive files. No modifications to existing source files. `VerifiedSet` remains untouched as the production bitset.

---

## 7. Open Questions

1. **Persistence**: Should `ClaimStoreSnapshot` be persisted to disk (like `VerifiedSet` is rebuilt each run), or kept in-memory only? Current design: in-memory only, rebuilt each hydration pass.
2. **ClaimStore size**: For large vaults (thousands of certificates), the `Table[string, ClaimRecord]` may grow significantly. Is a `seq[ClaimRecord]` with binary search acceptable? Current design: `Table` for O(1) lookup.
3. **ClaimStore vs CertificateProjection**: Should `ClaimStore` replace `CertificateProjection` entirely, or coexist? Current design: coexist — `CertificateProjection` remains the lean projection for convergence/sync; `ClaimStore` is the rich store for evidence/audit.
