# Z3 Replay Evidence Capture — Design

**Status**: Draft  
**Scope**: Minimal capture of deterministic RE-RUN replay evidence at the certificate writer.  
**Principle**: Z3 replay evidence = deterministic re-run evidence, NOT kernel-checked proof. Do not relabel it as a proof.

---

## 1. Definitions

- **Z3 evidence**: The raw SMT-LIB2 script (`smtlib2`) and Z3 stdout output, both of which are deterministic inputs/outputs of a Z3 invocation. Re-running the same script with the same Z3 version and timeout produces the same stdout (absent non-determinism in Z3's internal heuristics, which is acceptable for replay evidence).
- **Replay evidence**: Evidence that a certificate can be reproduced by re-executing the same Z3 command. It does NOT imply the proof was checked by Z3's kernel.
- **Proof artifact**: The S-expression proof term Z3 emits in stdout when `enableProofs=true`. This is a raw term, not a kernel-checked proof.

---

## 2. Anchor Point: `writeCertificateFromUapResult`

**File**: `src/verification/cert_writer.nim` lines 353-437

The `smtlib2` parameter (passed from `stages.nim:455` as `uapOutput.translation.smt2`) is already available at this function. This is the anchor point for computing both hash fields.

### Anchor row per write

| Field | Computation | Source |
|-------|-------------|--------|
| `smtHash` | `SHA256(smtLib2)` | `smtlib2` param (already present) |
| `proofArtifactDigest` | `SHA256(z3stdout)` | `solverMetadata` / `diagnostics` in `SolverOutcome` |

Both fields already exist on `CertificateIdentity` (see section 5) but are **never populated** in the current `writeCertificateFromUapResult` body (lines 422-428 construct `CertificateIdentity` without setting them).

---

## 3. Enable Proof Capture in `runZ3CheckViaIR`

**File**: `src/verification/batch_uap/ir_pipeline_runner.nim` lines 207, 229

Currently:
```nim
let res = z3ExecPersistent(smtScript, timeoutMs = budget.timeoutMs)
```

**Edit**: Pass `enableProofs = true`:
```nim
let res = z3ExecPersistent(smtScript, timeoutMs = budget.timeoutMs, enableProofs = true)
```

**Effect**: Z3 emits proof terms (raw S-expressions) in stdout when status is `unsat`. This makes `proofArtifactDigest` richer — it now hashes the proof term, not just the raw stdout.

**Caveat (no-side-effect replay semantics)**: Enabling proofs changes Z3's stdout content (proof terms are appended). This is deterministic for a given script/Z3 version/timeout. The replay semantics remain "deterministic re-run" — no kernel validation is claimed. The `solver.proof.save` option (see section 4) is NOT enabled by this change.

---

## 4. Options Wiring: `solver.proof.save` vs stdout extraction

Z3 has two mechanisms for proof output:

| Option | Behavior | Status |
|--------|----------|--------|
| `:print-certificate true` / `solver.proof.save` | Writes `.proof` file to disk | Experimental (Z3 RELEASE_NOTES) |
| `enableProofs=true` (CLI flag) | Emits proof S-exprs in stdout | Stable |

**Recommendation**: Use stdout term extraction (`enableProofs=true`) as the primary mechanism. The `solver.proof.save` file-saving path should be deferred — it introduces file I/O at the solver boundary and is still replay-evidence only (not kernel-checked).

The stdout path is already wired: `extractCertificate` (solver_adapter.nim:42-81) parses the top-level parenthesized S-expression from stdout into `result.certificate.predicateInvariants`. When `enableProofs=true`, Z3 emits proof terms in stdout that `extractCertificate` can capture.

---

## 5. Chain Gap: `predicateInvariants` Does NOT Reach `writeCertificateFromUapResult`

**Verified: NO.** The `predicateInvariants` term extracted by `extractCertificate` is lost before reaching the cert writer.

### Data flow trace

1. **Extraction** (`ir_pipeline_runner.nim:213,237`):
   ```nim
   let cert = extractCertificate(output)
   if cert.len > 0:
     result.certificate.predicateInvariants[canonicalStateRelationKey] = cert
   ```
   The extracted S-expression is stored in `SolverOutcome.certificate.predicateInvariants` (solver_adapter.nim:25).

2. **Conversion** (`solver_adapter.nim:167-174`):
   `toCandidateEvidence()` converts `predicateInvariants` into `CandidateEvidence` for the evidence calculus. This is a separate data path.

3. **Gap** (`stages.nim:449-459`):
   `FinalReportCertInput` (defined at stages.nim:59-68) has NO `predicateInvariants` field. The construction at stages.nim:449-459 passes `smtlib2`, `solverStatus`, etc. but NOT the extracted certificate term.

4. **Cert writer** (`cert_writer.nim:353-366`):
   `writeCertificateFromUapResult` accepts `smtlib2` and `solverStatus` but has no parameter for `predicateInvariants`. The extracted term is never written to the certificate.

**The term is lost at the `FinalReportCertInput` construction boundary** (stages.nim:59-68, 449-459). To close this gap, either:
- (a) Add `predicateInvariant*: string` to `FinalReportCertInput` and thread it through, OR
- (b) Compute `smtHash` from `smtlib2` alone (the SMT script) and `proofArtifactDigest` from the proof term in stdout — the script itself is the replay anchor, and the proof term is the enrichment.

Option (b) is the minimal approach: the SMT script (`smtlib2`) is the replay input, and its SHA256 is the replay-evidence anchor. The proof term (when `enableProofs=true`) enriches `proofArtifactDigest` but is not required for replay.

---

## 6. V2 Fields and `CertificateIdentity` Shape

### 6.1 Fields to add/populate on `CertificateIdentity`

| Field | Type | Population |
|-------|------|------------|
| `smtHash` | `string` | `SHA256(smtLib2)` — computed from the SMT script at write time |
| `proofArtifactDigest` | `string` | `SHA256(z3stdout)` when `enableProofs=true`; empty string otherwise |
| `specHash` | `string` | SHA256 of the specification source (to be added) |
| `specOrigin` | `string` | Origin identifier for the spec (to be added) |
| `schemaVersion` | `string` | `"2"` (bump from `"1"` at cert_writer.nim:421) |

### 6.2 `CertificateIdentity` shape

**File**: `src/core/trusted/private/evidence_identity.nim` lines 22-29

```nim
CertificateIdentity* {.axiomDecision(
  id = "DECISION-0605",
  reason = "Provenance-complete certificate identity binding the full chain",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v37").} = object
  formula*             : string
  schemaVersion*       : string
  functionId*          : string
  specOrigin*          : string
  propertyFormula*     : string
  sourceHash*          : string
  irHash*              : string
  smtHash*             : string        # <-- exists, never populated
  translationVersion*  : string
  solverIdentity*      : string
  proofArtifactDigest* : string        # <-- exists, never populated
```

### 6.3 `EvidenceIdentity` wrapper

**File**: `src/core/trusted/private/evidence_identity.nim` lines 31-36

```nim
EvidenceIdentity* {.axiomDecision(
  id = "DECISION-0606",
  reason = "Evidence identity binding a certificate",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v37").} = object
  certificate*: CertificateIdentity
```

No changes needed to this wrapper.

### 6.4 `identityDigest` computation

**File**: `src/core/trusted/private/evidence_identity.nim` line 38+

The `identityDigest` function already includes `cert.smtHash` and `cert.proofArtifactDigest` in its digest computation (evidence_identity.nim:46,49). Once these fields are populated at the write point, the digest will automatically incorporate them.

---

## 7. Edit Point List

| # | File | Line(s) | Change |
|---|------|---------|--------|
| 1 | `src/verification/batch_uap/ir_pipeline_runner.nim` | 207 | Add `enableProofs = true` to `z3ExecPersistent` call (first overload) |
| 2 | `src/verification/batch_uap/ir_pipeline_runner.nim` | 229 | Add `enableProofs = true` to `z3ExecPersistent` call (second overload) |
| 3 | `src/verification/cert_writer.nim` | 422-428 | Populate `smtHash` and `proofArtifactDigest` in `CertificateIdentity` construction |
| 4 | `src/verification/cert_writer.nim` | 421 | Bump `schemaVersion` from `"1"` to `"2"` |
| 5 | `src/verification/batch_uap/stages.nim` | 59-68 | Optionally add `predicateInvariant*: string` to `FinalReportCertInput` if chain closure is desired |
| 6 | `src/verification/batch_uap/stages.nim` | 449-459 | Optionally pass `predicateInvariant` from `uapOutput` to `FinalReportCertInput` |
| 7 | `src/verification/cert_writer.nim` | 353-366 | Optionally add `predicateInvariant` parameter to `writeCertificateFromUapResult` |
| 8 | `src/verification/cert_writer.nim` | 353-366 | Optionally write `predicateInvariant` into the cert JSON |
| 9 | `docs/design/z3_replay_evidence_capture.md` | — | This design document |

Items 1-4 are the minimal V2 capture. Items 5-8 are optional chain-closure work for `predicateInvariants`.

---

## 8. Summary of Design Decisions

1. **Replay evidence, not proof**: Z3 stdout proof terms are deterministic re-run evidence. They are NOT kernel-checked. Do not relabel as "proof" in the certificate — use `proofArtifactDigest` (the field name already signals this).
2. **Anchor at write time**: Both `smtHash` and `proofArtifactDigest` are computed at `writeCertificateFromUapResult` (cert_writer.nim:353-437) from data already available in scope (`smtlib2` param and `solverMetadata`/`diagnostics`).
3. **Stdout-first**: Enable `enableProofs=true` in `z3ExecPersistent` to capture proof S-exprs in stdout. Defer `solver.proof.save` (file-based, experimental).
4. **`predicateInvariants` gap confirmed**: The extracted inductive invariant term is lost at the `FinalReportCertInput` construction boundary (stages.nim:59-68). The minimal V2 does not require closing this gap — `smtHash` from `smtlib2` is sufficient for replay anchoring.
5. **Schema version bump**: `schemaVersion` moves from `"1"` to `"2"` to signal the new fields.
