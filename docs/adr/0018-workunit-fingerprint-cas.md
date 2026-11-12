# ADR-0018: WorkUnitFingerprint + CAS Contract

## Status

**Proposed.** This ADR defines the WorkUnitFingerprint schema and Content-Addressable Store (CAS) contract for Axiom work-unit caching. The normative specification is in `docs/spec/workunit_fingerprint_cas_contract.md`. Implementation is deferred to a subsequent phase; no code is modified by this ADR.

## Context

Axiom's P2 incremental verification engine (`docs/spec/incremental_ci_contract.md`) defines the `reusable(U)` invariant — a work unit is reusable only when its fingerprint matches a cached entry. However, the P2 contract leaves the fingerprint schema, CAS storage semantics, conflict resolution, and authoritative promotion rules underspecified. This creates three risks:

1. **Fingerprint ambiguity**: Without a fixed field order and serialization, different implementations could produce different fingerprints for identical inputs, breaking determinism.
2. **CAS conflict silent reuse**: If a same-key-different-content entry is silently reused instead of discarded and re-executed, incorrect results propagate through CI — a theater violation (AGENTS.md §0.9).
3. **Unreviewed authority**: If CI trusts cached results without a human review gate, automated systems could approve their own incorrect outputs.

The existing gate memo CAS in `src/core/gate/gate_memo.nim` (lines 609–641) provides a proven pattern: contentHash==filename integrity verification, gateId/compositeLockHash re-derivation on load, and CAS addressing via `computeCasAddress`. The `loadAndValidateCache` function in `src/gate/cache/soundness_cache_io.nim` (lines 114–149) provides the fail-closed template: missing/corrupted/legacy → empty cache → force full execution. The `atomicWrite` primitive in `src/engine/atomic_ops.nim` (line 58) provides crash-safe file writes via temp+fsync+rename.

This ADR adopts these existing patterns and extends them to the WorkUnitFingerprint + CAS contract.

## Decision

We adopt the WorkUnitFingerprint + CAS contract defined in `docs/spec/workunit_fingerprint_cas_contract.md`:

### 1. WorkUnitFingerprint Schema

The fingerprint is `SHA256(sourceClosureDigest ∥ toolchainDigest ∥ contractDigest ∥ executionConfigDigest)` where each constituent is a 32-byte SHA-256 digest concatenated in byte order, then hex-encoded. The four fields are:

- **sourceClosureDigest**: SHA-256 of the dependency closure of input files (from `docs/spec/incremental_ci_contract.md` §3).
- **toolchainDigest**: Output of `canonicalExecutionBundleFingerprint` in `src/verification/obligation/identity.nim:188` — covers axiom executable/source digests, Lean/Z3/Lake/Nim versions, dependency digests, runtime digest, and evaluation implementation digest.
- **contractDigest**: Output of `executionContractDigest` in `src/verification/obligation/identity.nim:141` — covers invocation, platform, workdir, allowedEnv (sorted), fsBoundary, networkPolicy, mountedInputs, resourcePolicy.
- **executionConfigDigest**: SHA-256 of per-work-unit execution configuration (resource limits, timeout, working directory assertion, execution parameters not in `ExecutionContract`).

### 2. CAS Contract

- **Key**: `WorkUnitFingerprint` (§1).
- **Value**: `{canonicalResult, contentDigest, workUnitFingerprint, promotionStatus}` where `contentDigest = SHA256(canonicalResult)`.
- **Conflict resolution**: Same-key-different-content → **DISCARD + RE-EXECUTE**. Never silently reuse. This is enforced by content digest verification on every read (§3.4 of the spec).
- **Integrity**: CAS entries follow the `epoch_<N>/<hash[:2]>/<hash[2:]>` directory layout with filename == SHA-256(content), matching the existing gate memo CAS pattern in `src/core/gate/gate_memo.nim:649–677`.

### 3. Authoritative Promotion Rules

- A CAS entry becomes authoritative only after a **separate human review step** (not automated).
- CI trusts **only** `promotionStatus = authoritative` entries. `pending` and `superseded` entries are cache misses.
- **The promotion gate is NOT wired into CI.** It is a human-in-the-loop process outside the CI pipeline. This prevents automated systems from approving their own incorrect results (theater risk).

### 4. Deterministic Write Semantics

All CAS writes use `atomicWrite` from `src/engine/atomic_ops.nim:58` (temp file + fsync + POSIX rename). The write protocol is:

1. Serialize `CASValue` to canonical JSON (sorted keys, no whitespace variation).
2. Compute `contentDigest = SHA256(serialized)`.
3. Write to temp file via `atomicWrite` in the CAS directory.
4. The temp file's name is the CAS address (`contentDigest`).

### 5. Reusable Invariant

```
reusable(U) ≡ Fingerprint(U.inputs, U.contract, U.toolchain, U.executionConfig) == CachedFingerprint ∧
               contentDigest(CachedResult) == SHA256(CachedResult) ∧
               promotionStatus == authoritative
```

This extends the `reusable(U)` invariant from `docs/spec/incremental_ci_contract.md` §4.2 by adding `executionConfigDigest` as a fingerprint component, content digest verification, and authoritative promotion gating.

## Alternatives Considered

- **Fingerprint = ExecutionIdentity only** (no sourceClosureDigest or executionConfigDigest): Rejected — `ExecutionIdentity` in `src/verification/obligation/identity.nim:212` covers input+contract+bundle but omits the source closure (which changes with file edits) and execution config (which varies per runner). Without these, fingerprint collisions across different source sets or runner configurations would cause incorrect cache hits.

- **Auto-promotion of CAS entries** (no human review gate): Rejected — would create a theater risk where CI trusts its own cached results without human verification. The promotion gate must be a separate, auditable human step per AGENTS.md §0.9 and §0.9b.

- **Silent conflict resolution** (reuse same-key-different-content entry): Rejected — this is the definition of theater (AGENTS.md §0.9). A CONFLICT must always discard and re-execute. The fail-closed pattern in `soundness_cache_io.nim:114–149` confirms this: corrupted/invalid entries → empty cache → force full execution.

- **String concatenation for fingerprint serialization** (∥ as string concat): Rejected — string concatenation of hex digests is ambiguous (e.g., `ab` + `cd` == `abcd` vs. `a` + `bcd`). Byte-level concatenation of the raw 32-byte SHA-256 outputs eliminates this ambiguity.

- **Write CAS entries directly (no atomicWrite)**: Rejected — direct writes risk partial files on crash. `atomicWrite` in `src/engine/atomic_ops.nim:58` provides the crash-safe write-to-temp + fsync + rename protocol that guarantees atomicity on POSIX.

## Consequences

### Structural

- The `WorkUnitFingerprint` type and CAS schema are defined as normative contracts in `docs/spec/workunit_fingerprint_cas_contract.md`. Implementation MUST conform.
- The CAS storage layout (`epoch_<N>/<hash[:2]>/<hash[2:]>`) reuses the existing gate memo CAS pattern from `src/core/gate/gate_memo.nim`.
- The `promotionStatus` field adds a lifecycle state to CAS entries that does not exist today.

### Safety

- **No silent conflict reuse**: CONFLICT always discards + re-executes. This is non-negotiable and non-theater.
- **Fail-closed on uncertainty**: Missing/corrupted/invalid CAS entries → cache miss → re-execute. This mirrors `soundness_cache_io.nim:114–149`.
- **Human review gate**: No CAS entry is authoritative until a human reviewer approves it. CI never trusts unreviewed entries.

### Process

- This ADR is a **proposed** design contract. It does not modify any source code, CI configuration, or immutable file.
- The normative spec in `docs/spec/workunit_fingerprint_cas_contract.md` is the authoritative reference for implementation.
- Implementation should reference the verified code locations in §7 of the spec for integration points.

### Theater Compliance

- All invariants are non-theater: `reusable(U)` requires exact fingerprint match + content digest verification + authoritative status.
- CONFLICT resolution is explicit and logged, not a silent no-op.
- The promotion gate is a live, auditable human step — not a pass-through.

## References

- `docs/spec/workunit_fingerprint_cas_contract.md` — Normative specification (this ADR's contract).
- `src/engine/atomic_ops.nim:58` — `atomicWrite` primitive for crash-safe CAS writes.
- `src/verification/obligation/identity.nim:106–157` — `ExecutionContract` and `executionContractDigest`.
- `src/verification/obligation/identity.nim:177–206` — `CanonicalExecutionBundle` and `canonicalExecutionBundleFingerprint`.
- `src/verification/obligation/identity.nim:212–217` — `executionIdentity`.
- `src/core/gate/gate_memo.nim:609–641` — CAS load with contentHash==filename revalidation, gateId/compositeLockHash check.
- `src/core/gate/gate_memo.nim:643–677` — CAS save with `computeCasAddress` + `casPath`.
- `src/core/gate/gate_memo.nim:27–59` — `CasAddress`, `casSubdir`, `casFilename`, `casPath`, `computeCasAddress`.
- `src/gate/cache/soundness_cache_io.nim:114–149` — `loadAndValidateCache` fail-closed pattern.
- `config/artifact_spec.json` — Artifact classification A/B/C with invariants INV-001/INV-002.
- `docs/spec/incremental_ci_contract.md` §4 — `reusable(U)` invariant and theater prohibition.
- `docs/adr/0017-incremental-verification-engine.md` — ADR-0017, the P2 incremental verification engine ADR that this ADR extends.

---

*작성일: 2026-08-28. Proposed. No code is modified. Implementation deferred to a subsequent phase.*
