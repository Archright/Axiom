# WorkUnitFingerprint + CAS (Content-Addressable Store) Contract

> **종류**: Normative design contract (P4). This document defines the canonical
> fingerprinting and content-addressed storage contract for Axiom work units.
> It is a **specification only** — no implementation code is defined here. A
> later phase implements the contract in `src/`.
>
> **작성일**: 2026-08-28.
> **권위 입력**: `src/engine/atomic_ops.nim` (§5.1), `src/verification/obligation/identity.nim` (§5.2),
> `src/core/gate/gate_memo.nim` (§5.3), `src/gate/cache/soundness_cache_io.nim` (§5.4),
> `config/artifact_spec.json` (§5.5), P2 계약 §4 (§5.6 — 원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제, 보존된 ADR-0017이 참조본).
> **범위**: WorkUnit fingerprint schema, CAS key-value contract, authoritative promotion rules,
> deterministic write semantics. Does NOT modify CI wiring or any immutable file.

---

## 1. Purpose

This contract specifies:

1. The **WorkUnitFingerprint** — a deterministic hash of the inputs, contract, and
   toolchain that uniquely identifies a work unit's execution context.
2. The **CAS contract** — how fingerprints map to canonical results, and how
   same-key-different-content conflicts are resolved.
3. **Authoritative promotion rules** — when a CAS entry may be trusted by CI,
   gated by a separate human review step.
4. **Deterministic write semantics** — how CAS entries are written using the
   existing `atomic_ops.atomicWrite` primitive.

The contract is normative: any implementation MUST satisfy these rules.

---

## 2. WorkUnitFingerprint Definition

### 2.1 Field Types

The fingerprint is a SHA-256 hex digest (64-char lowercase hex string). It is
computed as:

```
WorkUnitFingerprint = SHA256(sourceClosureDigest ∥ toolchainDigest ∥ contractDigest ∥ executionConfigDigest)
```

where `∥` denotes byte-level concatenation (NOT string concatenation — each
constituent digest is already a fixed-length byte sequence).

| Field | Type | Description |
|---|---|---|
| `sourceClosureDigest` | `string` (64-char hex) | SHA-256 of the closure of source files that the work unit reads. Determined by the dependency closure algorithm in the P2 contract §3 (anchor `docs/spec/incremental_ci_contract.md` deleted with CI=0 cutover, 2026-09-20; preserved ADR-0017 is the reference copy). |
| `toolchainDigest` | `string` (64-char hex) | SHA-256 of the canonical execution bundle. Computed by `canonicalExecutionBundleFingerprint` in `src/verification/obligation/identity.nim:188`. |
| `contractDigest` | `string` (64-char hex) | SHA-256 of the `ExecutionContract` for this work unit. Computed by `executionContractDigest` in `src/verification/obligation/identity.nim:141`. |
| `executionConfigDigest` | `string` (64-char hex) | SHA-256 of execution configuration: resource limits, timeout, working directory assertion, and any per-work-unit execution parameters that are NOT part of the `ExecutionContract`. |

### 2.2 Serialization Order

The four digests are concatenated in **lexicographic field-order** (not arbitrary):

```
serialized = sourceClosureDigest_bytes ∥ toolchainDigest_bytes ∥ contractDigest_bytes ∥ executionConfigDigest_bytes
```

Each digest is the raw 32-byte SHA-256 output (not the hex-encoded string) at the
point of concatenation. The final `WorkUnitFingerprint` is the hex encoding of
`SHA256(serialized)`.

**Why this order**: `sourceClosureDigest` is the primary input discriminant
(changed files → different closure → different digest). `toolchainDigest` is
second because toolchain changes invalidate all cached results. `contractDigest`
is third because the execution contract captures hermeticity constraints.
`executionConfigDigest` is last because it is the most fine-grained and most
likely to change between runs of the same work unit on different runners.

### 2.3 Relationship to Existing Identity Primitives

The `WorkUnitFingerprint` composes existing primitives from
`src/verification/obligation/identity.nim`:

- **`CanonicalExecutionBundle`** (line 177) and its fingerprint function
  `canonicalExecutionBundleFingerprint` (line 188) produce `toolchainDigest`.
  The bundle covers: `axiomExecutableDigest`, `axiomSourceDigest`, `leanVersion`,
  `z3Version`, `lakeVersion`, `nimVersion`, `dependencyDigests`, `runtimeDigest`,
  `evaluationImplementationDigest` (lines 178–186).

- **`ExecutionContract`** (line 106) and its digest function
  `executionContractDigest` (line 141) produce `contractDigest`. The contract
  covers: `invocation`, `platform`, `workdir`, `allowedEnv` (sorted by name),
  `fsBoundary`, `networkPolicy`, `mountedInputs`, `resourcePolicy` (lines 107–114).

- **`ExecutionIdentity`** (line 212, function `executionIdentity`) computes
  `SHA256(inputIdentity + executionContractDigest + bundleFingerprint)`. The
  `WorkUnitFingerprint` extends this pattern by adding `sourceClosureDigest` and
  `executionConfigDigest` as additional inputs to the outer hash.

---

## 3. CAS (Content-Addressable Store) Contract

### 3.1 Key-Value Schema

The CAS is a persistent mapping:

```
CAS : Map<Fingerprint, CASValue>
```

where:

```
CASValue = {
  canonicalResult : string,     -- the verified/canonical result artifact (serialized)
  contentDigest   : string,     -- SHA-256 of canonicalResult (the content address)
  workUnitFingerprint : string, -- the key (redundant with the CAS key, stored for integrity)
  promotionStatus : PromotionStatus  -- see §4
}
```

The **key** is the `WorkUnitFingerprint` (§2). The **value** contains the
canonical result and its own content digest. The `contentDigest` field enables
integrity verification independent of the key.

### 3.2 Content-Addressing Integrity (CAS Key == Content Hash)

The CAS follows the same integrity pattern as the existing gate memo CAS in
`src/core/gate/gate_memo.nim:609–641`:

- The **filename IS the SHA-256 hash of the file content** (CAS address).
- On load (`loadGateMemo`, line 609), the store verifies:
  1. `SHA-256(content) == filename` (CAS integrity check, lines 626–630).
  2. `gateId` matches the requested gate ID (line 633).
  3. `compositeLockHash` matches the re-derived composite lock hash (line 635).

The WorkUnitFingerprint CAS MUST adopt the same pattern: the content digest
(`contentDigest` in `CASValue`) MUST equal `SHA-256(canonicalResult)`, and this
must be verified on every read. If the content digest does not match the stored
value, the entry is treated as corrupted (see §3.3).

### 3.3 Same-Key-Different-Content = CONFLICT

**Invariant**: If a CAS lookup finds an entry whose key (fingerprint) matches
the requested fingerprint but whose `contentDigest` does not match the content
that would be produced by executing the work unit, this is a **CONFLICT**.

Conflict resolution:

1. **DISCARD** the existing CAS entry entirely.
2. **RE-EXECUTE** the work unit from scratch.
3. **NEVER** silently reuse the stale entry. Silent reuse of a same-key
   different-content entry is a theater violation (§0.9 of AGENTS.md).

This is the same fail-closed philosophy as `loadAndValidateCache` in
`src/gate/cache/soundness_cache_io.nim:114–149`:

- Missing/corrupted/invalid cache → empty cache (force full execution).
- Legacy schema version → empty cache (auto-invalidate).
- Unknown status → treated as unchecked.

The CAS MUST NOT return a stale entry when the fingerprint matches but the
content has diverged. The cost of re-execution is always less than the cost of
an incorrect result.

### 3.4 Conflict Detection Protocol

On CAS read for fingerprint `F`:

```
1. Lookup entry E with key F.
2. If E does not exist → MISS → execute work unit.
3. If E exists:
   a. Compute contentDigest' = SHA256(read E.canonicalResult).
   b. If contentDigest' ≠ E.contentDigest → CORRUPTED → DISCARD E, execute work unit.
   c. If contentDigest' == E.contentDigest → HIT → return E.canonicalResult.
```

Step 3b detects both storage corruption and the same-key-different-content
conflict case. The content digest is the ground truth for entry validity.

---

## 4. Authoritative Promotion Rules

### 4.1 Promotion Gate (Separate Review Step)

A CAS entry becomes **authoritative** only after passing a separate human review
step. The promotion gate is NOT automated and is NOT wired into CI.

The promotion flow:

1. **Execution**: Work unit executes and produces a result.
2. **CAS Write**: Result is written to CAS with `promotionStatus = pending`.
3. **Review**: A designated reviewer inspects the result (e.g., for a new gate
   configuration or a changed verification contract). This is a manual, auditable
   step.
4. **Promotion**: Reviewer marks the CAS entry as `promotionStatus = authoritative`.
5. **CI Trust**: CI may trust authoritative entries only. Pending entries are
   re-executed on every CI run.

### 4.2 CI Trust Boundary (Do NOT Wire Into CI)

**This contract does NOT wire the promotion gate into CI.** CI must treat all
non-authoritative entries as cache misses. The promotion decision is a separate,
human-in-the-loop process that exists outside the CI pipeline.

Rationale: Automating promotion would create a theater risk — an automated
system could approve its own incorrect results. The separate review step ensures
that authority is granted by a human who can verify the result's correctness.

This is consistent with the theater prohibition in AGENTS.md §0.9 and the
fail-closed pattern in `soundness_cache_io.nim:114–149`.

### 4.3 PromotionStatus Values

| Value | Meaning | CI Behavior |
|---|---|---|
| `pending` | Entry exists but has not been reviewed | Treat as cache miss; re-execute |
| `authoritative` | Entry has been reviewed and approved | Trust the cached result |
| `superseded` | A newer authoritative entry exists for the same fingerprint | Treat as cache miss; re-execute |

### 4.4 Soundness-Certified Gate (P8.4) — Pass-Only Promotion

Per P8.4, **authoritative promotion now also requires `soundnessCertified == true`**.
This is an additional, prior gate on top of the separate-review requirement (§4.1):

- Every freshly written CAS entry has `soundnessCertified = false` (default).
- `promote(casDir, key, soundnessCertified)` **rejects** promotion unless the caller
  passes `soundnessCertified = true`.
- `soundnessCertified = true` is set **only by a human reviewer** in a
  **soundness-certified review commit** that confirms:
  1. **P8.1 selector-soundness PASS** (mutation harness exit 0; all classified
     mutations contained; UNCLASSIFIED = 0), and
  2. a separate human review of the entry (as in §4.1).

This makes the CAS layer enforce the umbrella rule *"no authoritative execution
until selector soundness is proven"*: until the selector passes mutation
soundness and a reviewer certifies it, **no CAS entry can become reusable**.

Behavior matrix:

| `soundnessCertified` | Result of `promote` | Entry status |
|---|---|---|
| `false` (default) | `err` (gate rejected) | remains `pending` → cache miss |
| `true` (reviewer) | `ok` | becomes `authoritative` → reusable |

This mirrors the pass-only, fail-closed pattern of the whole CAS: uncertainty is
never converted to reuse — it is converted to re-execution (cache miss).

### 4.5 Target Design — SoundnessAttestation (SLSA model; future implementation)

The boolean `soundnessCertified` is the **minimal now-gate**. The target design
replaces it with a structured, verifiable attestation following the
**SLSA attestation model** (`subject / predicate / verifier`), so `promote` can
drop-in consume a *valid attestation* instead of a bare bool:

```
SoundnessAttestation = {
  subject*: {          // what is being certified
    workUnitFingerprint*: string,
    selectorVersion*: string        // impact_closure_selector.nim version/commit
  },
  predicate*: {        // what the claim asserts
    graphDigest*: string,             // buildCoreImportGraph() content digest
    mutationCatalogDigest*: string,   // data/selector_soundness/mutation_catalog.json digest
    evidenceDigest*: string,          // harness output + oracle result digest
    reviewerApproval*: string,        // reviewer identity + review-commit reference
    soundnessResult*: string          // "PASS" only
  },
  verifier*: {          // who/which signed it
    verifierId*: string,
    signatureDigest*: string          // SLSA-compliant signature
  }
}
```

- **subject**: the work-unit fingerprint being promoted.
- **predicate**: the soundness evidence — selector version, dependency-graph
  digest, mutation-catalog digest, harness/oracle evidence digest, and the
  reviewer's explicit approval.
- **verifier**: the reviewing authority and its signature.

Long-term, `promote` consumes a `SoundnessAttestation` whose predicate is
independently re-derivable (recompute `evidenceDigest` from current harness
state) — exactly the fail-closed re-derivability principle used by the P8.5
certification-checker. **Implementation is deferred**; this section documents the
target so the now-gate (§4.4) does not harden into a permanent bool-only
shortcut.

---

## 5. Deterministic Write Semantics

### 5.1 Reuse of `atomic_ops.atomicWrite`

All CAS writes MUST use the existing `atomicWrite` primitive from
`src/engine/atomic_ops.nim:58`:

```nim
proc atomicWrite*(path: string, content: string): Result[void, string]
  ## Write `content` to `path` atomically.
  ## 1. Create temp file in same directory as `path` (same-filesystem guarantee).
  ## 2. Write content via POSIX write(2).
  ## 3. fsync to durable storage.
  ## 4. Rename temp → target (atomic on POSIX).
  ## On any failure the temp file is cleaned up and an error returned.
```

The CAS write protocol MUST follow this exact sequence:

1. Serialize `CASValue` to a canonical JSON representation (sorted keys, no
   whitespace variation).
2. Compute `contentDigest = SHA256(serialized)`.
3. Write to a temp file in the CAS directory using `atomicWrite`.
4. The temp file's name is the CAS address (`contentDigest`), following the
   same `epoch_<N>/<hash[:2]>/<hash[2:]>` directory layout as the existing gate
   memo CAS in `src/core/gate/gate_memo.nim:649–677`.

### 5.2 Write Atomicity Guarantees

- **Same-filesystem rename**: `atomicWrite` creates the temp file in the same
  directory as the target, guaranteeing the rename is atomic on POSIX.
- **fsync before rename**: `atomicWrite` calls `fsync` on the temp file before
  renaming, ensuring durability even on power loss.
- **Cleanup on failure**: If `atomicWrite` fails, the temp file is removed and
  an error is returned. The CAS entry is NOT partially written.
- **No partial reads**: A reader that opens a file after the rename either sees
  the complete old content or the complete new content — never a partial write.

### 5.3 Determinism Requirements

- The serialized `CASValue` MUST be deterministic: the same inputs MUST always
  produce the same byte sequence.
- JSON serialization MUST use sorted keys and no trailing whitespace.
- Timestamps in `CASValue` (e.g., `writtenAt`) are NOT part of the content
  digest used as the CAS key. They are metadata only.
- The `WorkUnitFingerprint` key MUST NOT include host-specific or
  runner-specific identifiers (consistent with `ExecutionIdentity` in
  `src/verification/obligation/identity.nim` which excludes `observedAt` and
  timestamps).

---

## 6. Invariants

### 6.1 Reusable Invariant (Primary)

> **reusable(U)**: A work unit U is reusable from the CAS if and only if its
> fingerprint matches a cached entry with identical content.

```
reusable(U) ≡ Fingerprint(U.inputs, U.contract, U.toolchain) == CachedFingerprint ∧
               contentDigest(CachedResult) == SHA256(CachedResult)
```

This is the central invariant. It is derived from and extends the `reusable(U)`
invariant in the P2 contract §4.2 (anchor `docs/spec/incremental_ci_contract.md`
deleted with CI=0 cutover, 2026-09-20; preserved ADR-0017 is the reference copy):

```
reusable(U) ≡ Fingerprint(U.inputs, U.contract, U.toolchain) == CachedFingerprint(U)
```

The WorkUnitFingerprint contract strengthens this by adding:
- `executionConfigDigest` as a fourth component of the fingerprint.
- `contentDigest` verification on every read (§3.2).
- `promotionStatus` gating — only `authoritative` entries are reusable by CI.

### 6.2 Non-Theater Invariants

All invariants in this contract are **non-theater** (AGENTS.md §0.9):

- `reusable(U)` is not always-true — it requires an exact fingerprint match AND
  content digest verification AND authoritative promotion status.
- CONFLICT resolution (discard + re-execute) is not a silent no-op — it is an
  explicit, logged action that produces a fresh result.
- The promotion gate is not automatable by CI — it requires a human reviewer.
- Fail-closed: any uncertainty (missing file, corrupted JSON, schema mismatch,
  content digest mismatch) → treat as cache miss → re-execute.

### 6.3 Theater Prohibition Compliance

Per AGENTS.md §0.9 and the P2 contract §4.4 (anchor `docs/spec/incremental_ci_contract.md`
deleted with CI=0 cutover, 2026-09-20; preserved ADR-0017 is the reference copy), this
contract prohibits:

- **Always-pass claims**: The CAS does not claim all hits are correct — it
  verifies content digests on every read.
- **Swallowed failures**: A CONFLICT is never silently resolved by reusing the
  stale entry. It is always discarded and re-executed.
- **Dead gates**: The promotion gate is a live, auditable human step — not a
  pass-through.
- **Unenforced claims**: The `promotionStatus` field is checked on every CI
  read; pending entries are never trusted by CI.

---

## 7. Reference Code Locations

| Reference | Path | Lines | Description |
|---|---|---|---|
| `atomicWrite` | `src/engine/atomic_ops.nim` | 58–115 | Atomic file write primitive (temp + fsync + rename). |
| `CanonicalExecutionBundle` | `src/verification/obligation/identity.nim` | 177–206 | Toolchain fingerprint type and `canonicalExecutionBundleFingerprint` function. |
| `ExecutionContract` | `src/verification/obligation/identity.nim` | 106–157 | Hermetic execution closure type and `executionContractDigest` function. |
| `executionIdentity` | `src/verification/obligation/identity.nim` | 212–217 | `SHA256(inputIdentity + executionContractDigest + bundleFingerprint)`. |
| Gate memo CAS load | `src/core/gate/gate_memo.nim` | 609–641 | `loadGateMemo` — contentHash==filename revalidation, gateId/compositeLockHash check. |
| Gate memo CAS save | `src/core/gate/gate_memo.nim` | 643–677 | `saveGateMemo` — CAS write with `computeCasAddress` + `casPath`. |
| CAS helpers | `src/core/gate/gate_memo.nim` | 27–59 | `CasAddress`, `casSubdir`, `casFilename`, `casPath`, `computeCasAddress`. |
| Fail-closed cache load | `src/gate/cache/soundness_cache_io.nim` | 114–149 | `loadAndValidateCache` — missing/corrupted/legacy → empty cache. |
| Artifact classification | `config/artifact_spec.json` | 1–81 | A/B/C artifact classes with invariants INV-001 (C never tracked) and INV-002 (A always tracked). |
| `reusable(U)` invariant | P2 contract (ADR-0017 ref. copy) | §4.2 | Original reusable invariant definition (source `docs/spec/incremental_ci_contract.md` deleted with CI=0 cutover, 2026-09-20). |
| Theater prohibition | P2 contract (ADR-0017 ref. copy) | §4.4 | Non-theater requirements for invariants (same deletion note). |

---

## 8. Scope and Deferred Items

- **In scope**: Fingerprint schema, CAS contract, promotion rules, write semantics,
  invariants.
- **Deferred to implementation phase**: Actual CAS storage backend, `CASValue`
  serialization format, promotion review tooling, CI integration wiring (CI=0 cutover,
  2026-09-20로 CI wiring 항목은 소멸).
- **Explicitly out of scope**: CI pipeline modification (per AGENTS.md §-1 — `.github/workflows/ci.yml`은
  원 보호 대상이었으나 CI=0 cutover, 2026-09-20로 삭제됨)), `src/gate/runners/import_encapsulation_gate.nim`
  modification, `AGENTS.md` modification.

---

*This is a normative specification only. No code is defined or modified by this document. A subsequent implementation phase will produce the actual CAS and fingerprinting code.*
