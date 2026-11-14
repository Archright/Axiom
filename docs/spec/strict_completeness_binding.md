# Strict Completeness Binding — SSOT (schema, dual-write, admission)

**Status**: Normative contract (v1, 2026-10-20 — documents the merged behavior of PR #961, `feat/operational-strict-closure`, landed at commit `7ac99157ffed5f5725a0573bb213f310628900df`)
**Created**: 2026-10-20
**Related**: [docs/spec/obligation_semantics.md](obligation_semantics.md) §2.1a (subject binding measurement), [docs/spec/productization_contract.md](productization_contract.md) §6a, [docs/spec/verification_density.md](verification_density.md) (VKD), [docs/spec/lean_sorry_gate.md](lean_sorry_gate.md), companion SSOT [docs/spec/verifier_build_identity.md](verifier_build_identity.md)

**Source SSOT (code)**: this document describes code; the code is authoritative on any divergence.

- Schema + digest + source-identity composition: `src/core/trusted/completeness_binding.nim`
- Artifact IO + strict loader + generation marker: `src/infrastructure/evidence_artifact_io.nim`
- Producer dual-write: `src/infrastructure/external_ir_materializer.nim` (`saveCompletenessEvidenceDual`, `measureCompletenessSourceCapture`)
- Strict-first reader + two-anchor search: `src/verification/obligation/canonical_verification.nim` (`measureCompletenessRecordDigest`)
- Certificate/claim admission + generation cutover: `src/verification/cert_reconcile.nim`
- Promotion downgrade refusal: `src/verification/cert_promotion.nim`
- Claim marker + v3 identity extension: `src/verification/certificate_identity.nim`, `src/verification/cert_writer.nim`

---

## 1. Purpose and scope

The legacy 5-field `CompletenessEvidence` artifact carried no key equality, no re-hash and
silent defaults on load: any parseable bytes at the anchor path were accepted as the evidence
for that anchor. The strict-completeness contract replaces that for canonical use with an
authenticated admission artifact — the **`CompletenessBinding`** — and wires it into the
single approval path: the strict-first evidence reader, the certificate claim identity, the
journal-driven VKD admission, and canonical promotion.

This document defines: the schema and its digest preimage (§2), the producer dual-write and
the generation marker semantics (§3), the reader anchors (§4), the admission checks at both
the loader and the certificate layer, including why the pre-synthesis CAS anchor is **not**
compared against the certified `irHash` (§5), the generation cutover rules (§6), legacy
compatibility (§7), and the negative controls with their expected observations (§8).

---

## 2. Schema

### 2.1 `CompletenessBinding` (`completeness-binding-v1`)

`schemaVersion` is pinned to the constant `CompletenessBindingSchemaVersion =
"completeness-binding-v1"`. Loaders reject unknown versions.

| Field | Meaning |
|---|---|
| `schemaVersion` | always `"completeness-binding-v1"` |
| `evidenceKey` | the EXACT load anchor — the artifact filename stem; a loader refuses an artifact whose stored key differs from the key it was asked for |
| `irDigest` | IR digest **flavor ③** — `computeDeterministicCasKey(serializeIRFuncDef(preSynthesisFuncDef))`, the materializer save-key flavor; in the produced artifact this equals `evidenceKey` |
| `irDigestCanonical` | IR digest **flavor ②** — `computeIrDigest` (canonicalized); RECORDED for audit, never cross-checked against `irDigest` (keeps the two-anchor search expressible) |
| `sourceIdentity` | the canonical source-identity composite at capture time (§2.3) |
| `subjectModuleSha256` | sha256 of the subject module bytes at capture |
| `semanticProfileId` | `SemanticProfileV1Hash` — intentionally the SINGLE config identity; there is deliberately no separate `configDigest` (a second config identity would fork the writer/verifier pair) |
| `toolchainFingerprint` | pinned toolchain fingerprint at capture (the shared bundle digest composition, §5.4) |
| `payload` | the legacy 5-field `CompletenessEvidence` embedded **by value**, so the digest covers the evidence itself |
| `evidenceDigest` | sha256 over the canonical serialization of all other fields (§2.2) |

The only sanctioned constructor is `makeCompletenessBinding`: it pins `schemaVersion` to the
constant and computes `evidenceDigest` over the given content.

### 2.2 Digest preimage

`completenessBindingContentJson(b)` is the canonical serialization of every field EXCEPT
`evidenceDigest` — the exact preimage of `computeCompletenessBindingDigest`. Field order is
fixed (the object is built in a fixed key order), and strings are JSON-escaped, so no
delimiter-collision ambiguity exists. The nested `payload` object serializes the five legacy
evidence fields in fixed order (`translationLossFree`, `bindingUniverseComplete`,
`opaqueExpansionStatus`, `sourceBindingCount`, `irBindingCount`).

`evidenceDigest = sha256Hex($completenessBindingContentJson(b))` — integrity, not identity:
recomputation on load detects any unaccompanied mutation of the stored artifact. A stored
binding whose recomputed digest differs is refused — no silent defaults, ever.

### 2.3 Source identity composite

`composeCompletenessSourceIdentity(subjectGitRef, subjectTreeMerkleRoot,
subjectModuleSha256)` is the canonical `sourceIdentity` composite:

```
sha256Hex("completeness-source-identity-v1|" & gitRef & "|" & treeMerkle & "|" & moduleSha256)
```

Versioned, domain-separated. Producer sites and `measureCompletenessRecordDigest` alike call
this single proc — no site composes the string by hand. Any unmeasurable component yields a
composite that the capturing side refuses to save and the loading side cannot match — never a
downgraded identity. The subject tree merkle root is measured by
`measureSubjectTreeMerkleRoot` (`src/verification/obligation/canonical_verification.nim`):
a SHA-256 merkle over repo-relative `"<path>:<sha256(content)>"` records of the subject module
(resolver-authorised bytes) plus its one-hop first-party import closure, sorted by path;
absolute paths are normalized to repo-relative at this single point so producer and reader
measure the same root, and an absolute path outside the subject root is unmeasurable.

### 2.4 `CompletenessBindingRef` — the authenticated strict evidence identity

What a strict-first reader carries out of a successful load:

| Field | Meaning |
|---|---|
| `evidenceKey` | the exact load anchor the binding was found under; `""` marks the LEGACY representation (no strict binding exists; the record digest came from a legacy 5-field artifact) |
| `evidenceDigest` | the strict `CompletenessBinding.evidenceDigest` — the authenticated identity, recomputable by any reader that can load the binding artifact |
| `payloadDigest` | sha256 over `evidenceToJson(payload)`, the LEGACY 5-field serialization |

`payloadDigest` — NOT the strict `evidenceDigest` — is the value bound into
`ObligationSubjectBinding.completenessRecordDigest`, so the bound-obligation representation is
byte-compatible across the legacy and strict generations.

### 2.5 CLE evidenceId contract

`CanonicalLeanEvidence.evidenceId`
(`src/verification/obligation/kernel_acceptance_authority.nim:433-459`) is the cryptographic
binding of the whole evidence envelope. The exact preimage:

- **Legacy formula (six components joined by `|`, in this exact order)**:

  ```
  evidenceId = sha256Hex(obligationId | propositionHash | leanSourceHash |
                         kaaDigest | toolchainFingerprint | executionContractDigest)
  ```

  `executionContractDigest` and `toolchainFingerprint` are intentionally duplicated at the
  evidence envelope even though the KAA identity already transitively binds them, so external
  verifiers can recompute the top-level identity without traversing the KAA chain.

- **Strict extension (Phase 1A)**: when the evidence carries a strict `CompletenessBinding`
  (`completenessBindingDigest` non-empty — a 64-hex digest), that digest is appended as a
  seventh component **to the same six-component preimage**:

  ```
  evidenceId = sha256Hex(<six legacy components> | completenessBindingDigest)
  ```

  The strict digest is appended to the PREIMAGE, never to the legacy hash: hashing the
  already-hashed legacyId would double-hash and can never equal the implementation (the
  pre-#961 expectation computed exactly that double hash; see
  [docs/evidence/go_critical_recovery_2026-10-20.md](../evidence/go_critical_recovery_2026-10-20.md)).

- **Legacy byte-identical rule**: when `completenessBindingDigest` is empty (the legacy
  representation — no strict binding was bound at seal time), the formula above is
  byte-for-byte unchanged, so every evidence sealed before the strict generation keeps its
  identity. The empty-digest branch is a compatibility boundary only: a producer environment
  that cannot land the strict dual-write must not silently pass a strict-contract claim on it
  (the s1a golden suite fail-closes its materializer setup on exactly this condition).

**SSOT**: the formula's single source of truth is the doc comment on `evidenceId` in
`src/verification/obligation/kernel_acceptance_authority.nim:433-459`; the code is
authoritative on any divergence with this section. **Docs-gap note (2026-10-20)**: before this
section was added, the contract existed only in that code doc-comment and in the pinning test
— this is the first spec-side record, and it restates the code without adding semantics.
Pinned by `tests/unit/test_s1a_lean_golden.nim` ("evidenceId = H(6 components) and identity
components are distinct spaces" — including the 64-hex `completenessBindingDigest` guard and
the binding-removed negative control).

---

## 3. Producer dual-write and marker semantics

### 3.1 Artifact layout

All artifacts live under `$AXIOM_STATE_DIR/.axiom/cache/evidence/` (fallback base:
`getCurrentDir()` when `AXIOM_STATE_DIR` is unset):

| Path | Artifact |
|---|---|
| `<irDigest>.json` | legacy 5-field `CompletenessEvidence` (`saveEvidenceArtifact` / `loadEvidenceArtifact`) |
| `<evidenceKey>.binding.json` | strict `CompletenessBinding` (`saveCompletenessBinding` / `loadCompletenessBinding`) |
| `<evidenceKey>.strict-gen` | generation marker (`markStrictGeneration` / `hasStrictGenerationMarker`) |
| `<irDigest>.witness.json` | instantiation witnesses (distinct artifact; separate files prevent overwriting each other) |

The `.binding.json` extension is load-bearing on both sides: the strict loader can never read
a legacy 5-field artifact, and the legacy loader's silent-default parser can never project a
binding onto all-false defaults.

### 3.2 The dual-write entry point

`saveCompletenessEvidenceDual(evidenceKey, funcDef, capture, payload)`
(`src/infrastructure/external_ir_materializer.nim`) is the single dual-write entry point every
strict-generation producer uses:

1. **Mark first**: `markStrictGeneration(evidenceKey)` is written BEFORE the binding write is
   attempted. A measurement/IO failure therefore leaves a permanent generation tag: the
   reader then refuses the legacy fallback for this anchor even when `AXIOM_EVIDENCE_STRICT`
   is unset. Without the marker an older legacy-only record keeps the compatibility path; the
   tag is what distinguishes "this generation tried and could not measure" from
   "pre-generation record".
2. **Fail-closed identity gate**: `capture.sourceIdentity` or `capture.moduleSha256` empty →
   return false (an identity-less binding is never fabricated). `measureCompletenessSourceCapture`
   resolves the subject root under the SAME rule the reader applies (`resolveSubjectRepoRoot`
   with the caller's `contentCarried` flag: a content-carried subject binds ONLY to a threaded
   root, never the process CWD) and leaves `sourceIdentity` "" when any component is
   unmeasurable — the capture degrades to the legacy generation instead of a forged strict
   record.
3. **Strict sibling write**: `saveStrictCompletenessBinding(evidenceKey,
   computeIrDigest(funcDef), sourceIdentity, moduleSha256,
   measureCanonicalCaptureToolchainFingerprint(), payload)` records `irDigest` = the SAME
   flavor-③ anchor the legacy artifact is keyed by (`evidenceKey`), `irDigestCanonical` =
   flavor-② `computeIrDigest`, `semanticProfileId` = `SemanticProfileV1Hash`, and the
   toolchain fingerprint from the shared bundle measurement
   (`measureCanonicalCaptureToolchainFingerprint` in
   `src/verification/obligation/toolchain_capture.nim` — the SAME
   `measureToolchainBundleFingerprint` composition the kernel receipt computes, over the SAME
   resolution and the canonical 120_000 ms timeout; never a forked formula). The caller keeps
   its legacy `saveEvidenceArtifact` write regardless.

The binding write itself (`saveCompletenessBinding`) is atomic (PID-unique temp file + rename
within the cache dir) and fails closed at the write boundary: refuses a non-v1
`schemaVersion`, an empty anchor, any non-canonical sha256-hex digest field
(`evidenceKey`, `irDigest`, `irDigestCanonical`, `subjectModuleSha256`,
`semanticProfileId`, `toolchainFingerprint`, `evidenceDigest`), and a binding whose
`evidenceDigest` does not match its own recomputed content.

### 3.3 Marker semantics

- The marker records **WHICH GENERATION produced the record**, never the evidence: admission
  still requires the binding artifact and re-verifies its full digest/context contract.
- Written as `StrictCompletenessGenerationTag = "strict-completeness-generation-v1"` + `\n`,
  atomically (temp + rename); `markStrictGeneration` returns false on any IO failure (marker
  IO failure is non-blocking; strict mode still fails closed, and the absence of a marker
  never admits anything by itself).
- Judged by CONTENT, not existence: `hasStrictGenerationMarker` reads the file and requires
  the tag prefix — a truncated or foreign file is not a marker.

---

## 4. Reader anchors (strict-first, two-anchor search)

`measureCompletenessRecordDigest(funcDef, preSynthesisIrDigest, currentSourceIdentity,
currentSubjectModuleSha256)` (`src/verification/obligation/canonical_verification.nim`) is the
§2.1a `completeness` measurement. Its anchor set is the same deterministic two-anchor search
the runner cache uses:

1. `preSynthesisIrDigest` — the CAS key of the PRE-synthesis funcDef serialization (the
   completeness-artifact anchor the materializer wrote), threaded from the pipeline entry;
   skipped when empty.
2. `computeDeterministicCasKey(serializeIRFuncDef(funcDef))` — the current funcDef's key.

Anchors are deduplicated, then consulted IN ORDER:

1. **Strict first**: `loadCompletenessBinding(key, ...)` at each anchor (§5.1). A strict hit
   returns a `CompletenessBindingRef` whose `payloadDigest` re-serializes the binding's
   embedded payload with `evidenceToJson` and hashes it — the EXACT digest the legacy reader
   would have computed.
2. **Marked anchor → never legacy**: if `hasStrictGenerationMarker(key)` holds, the search
   continues at the next anchor in BOTH env modes. A missing, corrupt or stale-context binding
   on a marked anchor is UNKNOWN for that anchor — never a legacy fallback.
3. **`AXIOM_EVIDENCE_STRICT` set → legacy refused** at every anchor: the search continues
   strictly; no strict artifact anywhere → none (fail-closed) — never a fabricated record.
4. **Legacy fallback (env unset, unmarked anchor)**: `loadEvidenceArtifact(key)`; a legacy
   record yields a ref with `evidenceKey = ""`, `evidenceDigest = ""` and the legacy
   `payloadDigest`.

Absent file, unreadable or malformed bytes are equally "no record" at every step.

---

## 5. Admission checks

### 5.1 Loader checks (`loadCompletenessBinding`)

Every check is fail-closed — a single failure yields `none`, never a defaulted record:

1. Strict parse: exact top-level key set (no missing, no unknown), string kind for the nine
   scalar fields (the eight content fields plus `evidenceDigest`), and a strict payload parse
   (exact 5-key set, exact JSON types — bool/bool/string/int/int, no defaults).
2. `schemaVersion == CompletenessBindingSchemaVersion` (unknown → none).
3. Key equality: stored `evidenceKey` == the requested load anchor.
4. `evidenceDigest` recomputed from the parsed content == the stored digest.
5. `sourceIdentity` == caller-provided current source identity (a comment-only source edit
   changes the module sha256, hence the composite → stale → none).
6. `subjectModuleSha256` == caller-provided current module digest.
7. `semanticProfileId` == current profile (`SemanticProfileV1Hash`).
8. `toolchainFingerprint` == caller-provided current pinned fingerprint.

### 5.2 Current-context measurement (admission side)

`measureStrictCompletenessContext(projectRoot, modulePath, moduleSource)`
(`src/verification/cert_reconcile.nim`) measures the CURRENT admission context a strict
binding must match — measured, not taken from the claim:

- `subjectModuleSha256`: raw sha256 of the CURRENT module bytes;
- `sourceIdentity`: `composeCompletenessSourceIdentity` over the subject git ref
  (`measureSubjectGitRef`), the subject tree merkle root (`measureSubjectTreeMerkleRoot`) and
  the module sha256 — THE single producer-side capture composition (composing a raw join here
  would make every strict binding unloadable);
- `toolchainFingerprint`: `computeBundleDigest(leanExe, lakePath, 120_000, resolvedCmd)` —
  the SAME composition the kernel receipt records at capture (same resolution, same canonical
  timeout).

Every component fails closed to "" when unmeasurable.

### 5.2a Operational consequence — strict evidence is verifier-build- and commit-bound

Two independent fail-closed gates make every strict claim valid ONLY for the exact context
that captured it:

1. `sourceIdentity` includes `measureSubjectGitRef` (`git rev-parse HEAD` of the subject
   root, `src/verification/obligation/canonical_verification.nim`). When Axiom verifies
   itself the subject root IS the Axiom clone, so ANY commit — including a docs-only commit
   that leaves every module byte and the tree merkle root unchanged — changes `sourceIdentity`
   and makes every previously captured strict binding unloadable (loader check 5).
2. `toolchainIdentityMatchesPin` (`src/verification/cert_reconcile.nim`) requires the
   claim's `toolchainIdentity` (including `engineBuild` and `axiomVersion`) to equal the
   RUNNING verifier's `verifierToolchainIdentityJson()`. A verifier-build move — any change
   to the `computeVerifierBuildId` manifest (`src/**/*.nim`, `config.nims`, `axiom.nimble`,
   `axiom.lock`) — drops every prior claim.

Neither gate is a regression: a downgraded identity is never accepted. The operational
consequence is that VKD reads `0/23` after any commit or verifier-build move until the
evidence is re-captured at the new context; VKD is a runtime measurement over the local
TrustCommit journal + binding cache, not a git-carried artifact. Measured A/B (2026-11-14,
same binary): HEAD `107ef8a` → `2/23`; HEAD `ec09197` (docs-only) → `0/23`; main
`78b4f1f8c` with verifier `dd1f769f…` → `2/23` after a 23-symbol re-proof campaign —
evidence: `docs/evidence/vs_vkd1_current_engine_recovery_campaign_2026-11-13.md` §4.

### 5.3 Certificate/claim admission (`strictCompletenessAdmits`)

A journal/certificate claim belongs to the strict generation when
`claim.completenessContract == CompletenessContractStrictV1` (`"strict-v1"`). For such a
claim, `isFullCertClaim` additionally requires the FULL anchor set
(`completenessEvidenceKey`, `completenessBindingDigest`, `completenessPayloadDigest` all
non-empty); legacy claims (no marker) keep exactly the legacy required fields.

`strictCompletenessAdmits(claim, ctx)` then enforces, fail-closed (any failure → the claim is
never counted):

1. The claim carries the full anchor set (guarded by `isFullCertClaim`).
2. `loadCompletenessBinding(key, ctx...)` returns SOME — the strict binding artifact exists at
   the claim's key, parses strictly, its `evidenceDigest` recomputes, AND its
   `sourceIdentity` / `subjectModuleSha256` / `semanticProfileId` / `toolchainFingerprint`
   equal the CURRENT measured context (missing/corrupt/stale → none).
3. The binding's `evidenceDigest` equals the claim's `completenessBindingDigest`
   (claim ↔ artifact binding).
4. The binding payload's legacy 5-field digest (sha256 over `evidenceToJson(payload)`) equals
   the claim's `completenessPayloadDigest` (the legacy completeness commitment).
5. The binding's flavor-③ CAS anchor equals the claim's recorded
   `completenessEvidenceKey` (`b.irDigest == key`).

### 5.4 Why `irDigestCanonical` is NOT compared to the certified `irHash`

The binding is keyed by the producer's **PRE-synthesis** IR (flavor ③ CAS key of the
pre-synthesis serialization — the anchor the materializer saved under). The certified
post-synthesis `irHash` is bound by the proof and the certificate identity, not by this
anchor: the two IR flavors are deliberately both recorded but never cross-checked, precisely
so the two-anchor evidence search (pre-synthesis, then current funcDef) stays expressible.
Comparing `irDigestCanonical` to the claim's `irHash` would reject every legitimate
pre-synthesis binding. What admission instead binds is: the claim names the exact anchor key
(check 5) and the exact binding content (checks 3–4), and the binding re-verifies against the
CURRENT source/profile/toolchain context (check 2).

### 5.5 VKD journal admission and the ambiguity keys

`computeJournalVkdAdmission` (per-symbol pipeline over a fixed journal snapshot): v1 flat
full-cert claims only (v2 compact `entries[]` checkpoints are catalog, never admission);
context filter `status == certGreen`, `sourceHash` == fingerprint of the CURRENT module bytes,
`toolchainIdentity` == current pin (engineBuild included,
`toolchainIdentityMatchesPin`), `semanticProfileId == SemanticProfileV1Hash`; quarantine
exclusion; `verifyCertificateClosure` PASS; `proof_integrity.isVkdAdmissible` admit;
deduplication by evidence key. Step 3b is the strict gate: strict-contract claims must
additionally admit through `strictCompletenessAdmits`; under `AXIOM_EVIDENCE_STRICT=1`
(`evidenceStrictModeActive`) legacy-generation claims are excluded entirely — the env only
tightens, it can never relax the strict-contract requirements.

Two distinct keys matter:

- `journalEvidenceKey(claim)` — the function-level evidence identity (WHAT was proved about
  WHICH subject bytes). VKD ambiguity is decided on this key's strict descendant: two keys =
  two genuinely different claims (UNKNOWN, never a count); one key = the same claim
  re-attested on a different tree snapshot (count once).
- `journalEvidenceKeyStrict(claim)` — the admission-ambiguity key: the function-level key
  PLUS, for a strict-generation claim, its `completenessBindingDigest`. Two strict claims that
  differ only in the anchor are different evidence (the artifact can be present for one and
  absent/corrupt for the other) and must not collapse into one entry; a strict and a legacy
  claim for the same function-level evidence are likewise NOT silently merged. This key is
  deliberately NOT used by canonical promotion replacement: `journalEvidenceKey` stays
  byte-compatible there so a strict candidate can supersede an older legacy projection for the
  same `irHash` (§6).

---

## 6. Generation cutover

**Strict supersedes legacy; legacy never resurrects.**

1. **Claim level (VKD)**: once a symbol has ANY strict-generation claim in the fixed journal
   snapshot, an older legacy claim for the SAME symbol is never a valid fallback — not even
   with `AXIOM_EVIDENCE_STRICT` unset (`symbolHasStrictGeneration` check). This closes the
   "remove the strict binding and let legacy resurrect the symbol" path: a symbol whose strict
   binding is missing/corrupt/stale is `jvNoCurrentEvidence` (UNKNOWN for admission), not a
   legacy count.
2. **Promotion level**: `promoteToCanonical` refuses to replace an existing strict-generation
   canonical certificate with a legacy projection for the same `irHash` (one-way cutover); a
   strict re-verification may supersede a strict projection, and (via the byte-compatible
   `journalEvidenceKey`) a strict candidate may supersede an older LEGACY projection.
3. **Artifact level**: a `.strict-gen` marker on an anchor permanently removes the legacy
   fallback for that anchor, in both env modes (§3.2, §4).

---

## 7. Legacy compatibility

- The legacy 5-field save/load path is unchanged and kept for the compatibility boundary
  only; `loadCompletenessBinding` is the only canonical admission path.
- Dual-write keeps the legacy `<irDigest>.json` write untouched; an unmeasured capture
  degrades to the legacy generation (admissible only while `AXIOM_EVIDENCE_STRICT` is unset
  and no marker/strict claim exists for the anchor).
- `completenessRecordDigest` (the bound-obligation representation) carries the legacy
  serialization digest in both generations — no fork.
- The certificate writer emits the strict marker fields (`completenessContract`,
  `completenessEvidenceKey`, `completenessBindingDigest`, `completenessPayloadDigest`) ONLY
  when the sealed evidence carries the full strict anchor set; legacy evidence never gets the
  marker, so `isFullCertClaim` and the v3 identity extension both branch on it.
- The v3 certificate identity extension is marker-conditional: strict-contract certificates
  carry a 16-field identity (the 13 legacy fields + the marker, evidence key and binding
  digest); every legacy certificate keeps its 13-field identity and its stored
  `identityDigest` stays valid. Stripping the marker from a strict cert (or adding it to a
  legacy cert) breaks the identity recompute — fail-closed both ways.

---

## 8. Negative controls and expected observations

Pinned by `tests/unit/test_strict_completeness_reader.nim`,
`tests/unit/test_verifier_build_identity.nim` and `tests/unit/test_journal_vkd_report.nim`.
Expected observations (each is a regression-failure mode, not a suggestion):

| Control | Expected observation |
|---|---|
| Strict round-trip after dual-write | reader returns the ref: `evidenceKey == key`, `evidenceDigest == stored artifact digest`, `payloadDigest ==` legacy 5-field digest of the SAME payload |
| Legacy artifact removed, strict present | strict hit persists — the legacy artifact is never consulted |
| Binding removed, marker present, env unset | `none` (no legacy fallback) |
| Pre-generation anchor (no binding, no marker), env unset | legacy ref (`evidenceKey == ""`, `evidenceDigest == ""`, legacy `payloadDigest`) |
| Binding absent, `AXIOM_EVIDENCE_STRICT=1` | `none` even though the legacy artifact exists |
| Payload-tampered binding, `AXIOM_EVIDENCE_STRICT=1` | `none` (never the legacy behind it) |
| Tampered `sourceIdentity` / `subjectModuleSha256` / `semanticProfileId` / `irDigestCanonical` / `toolchainFingerprint` | strict refused in BOTH env modes — the marker keeps the anchor off the legacy path |
| Foreign source identity passed as current context | `none` in both env modes on a marked anchor |
| Pre-synthesis anchor threaded | strict binding found at the pre-synthesis key (`evidenceKey == preSynthesisIrDigest`) |
| Missing/mismatched `engineBuild` in a claim's `toolchainIdentity` | `toolchainIdentityMatchesPin == false`; the literal string `"unmeasured"` also never matches (the guard is explicit, not incidental) |
| Journal snapshot with a strict claim whose binding artifact is deleted | symbol → `jvNoCurrentEvidence`, never counted, legacy claim not resurrected |

---

## 9. What is not claimed

- **No proof of user intent.** The binding authenticates that measured evidence for a subject
  exists under the current source/profile/toolchain context. It says nothing about whether
  the subject's obligations express what a human intended to verify; that judgment lives in
  the obligation synthesis contracts, not here.
- **No broad Rust/AST extraction coverage.** The contract covers the completeness evidence of
  the canonical Nim→IR→Lean verification path for its bounded certified subset. It does not
  widen the extraction-agreement subset, and it does not extend the Rust/LLBC attestation
  binding (`llbcDigest` / `rustToolchainIdentity` in `axiom.attestation.evidence.v2`) beyond
  its own all-or-nothing rule.
- **No cache authority.** The binding, legacy evidence and marker files under
  `$AXIOM_STATE_DIR/.axiom/cache/evidence/` are cache artifacts: IO failure is silently
  ignored at the boundary and never interrupts verification, and every admission re-verifies
  content and context from scratch. The authoritative state of a claim is the TrustCommit
  journal record, never the cache file.
- **No certificate-file authority.** The canonical vault cert files (and `manifest.json`)
  are materialized projections of journal records. Promotion writes the journal record first
  and rolls the cache artifacts back on materialization failure; reconciliation and VKD
  admission read the journal, not the vault, as evidence authority.

External behavior cited in this document: GitHub's merge queue merges a queued group into the
base branch once the checks required by the branch protections pass, and the `merge_group`
event (`types: [checks_requested]`) is separate from `pull_request`/`push` —
[Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue),
[Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions).
This is why a claim's measured identity must drop (rather than degrade) when its strict
binding cannot be re-verified: VKD numbers feed evidence surfaces reviewed at merge admission
whose enforcement authority is GitHub's queue, and a stale-but-plausible count under a green
check would misstate what the current verifier actually measured.
