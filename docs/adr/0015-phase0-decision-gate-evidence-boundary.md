# ADR-0015: Phase-0 Decision Gate — Closing the Unified Evidence Boundary (R4+R7+R8)

## Status
Proposed (decision gate). No implementation is authorized by this ADR alone; Phase 1–3 remain locked
pending explicit architect re-approval.

## Context

An independent readiness audit of Axiom (HEAD `2e31b2587`, Nim 2.2.10 / Lean 4.29.0 / Z3 4.13.3)
returned **NO-GO** with three critical blockers:
- **R4 — Evidence/Certificate Integrity**: `proofDigest` absent; promotion does not re-validate v3
  completeness or kernel/tool acceptance.
- **R7 — CLI Product Contract**: internal-error exit contract open (no handler, SIGSEGV out-of-contract),
  invalid-input exit drifts 3(contract)→1(actual), exit authority scattered.
- **R8 — Blocking Surface**: canonical vault has 0 v3 certs; no staging/reload/reverify; VKD 0/23 with
  `ObliSemanticNoApplicable` obligation failures.

This ADR is the **Phase-0 decision gate** (per architectural review): before any code, answer five
questions with exactly one single answer each, and branch only on F4. Evidence was collected by five
parallel sensor subagents (F1–F5, observations only) plus context7 external-doc corroboration.

## Decision — The Five Questions with Single Answers

### F1 — What is the current Evidence SSOT? → **C: reuse existing structure as-is.**

The TrustCommit journal + certificate writer + EvidenceCapture already constitute a coherent evidence
bundle. **Do not create a new EvidenceBundle type.**
- **TrustCommit journal** = authoritative ledger (SSOT): 3964 content-addressed records, mutated only by
  `commitVerification()`, persisted to `data/trusted/journal/<commitId>.json` (atomic tmp→fsync→rename),
  gitignored. (`src/core/trusted/trust_commit.nim:47-66,332-349`)
- **Certificate writer** = projection layer: writes v3 cert with `trustCommitId` (→ journal), and
  `claim / inputHash / toolchainIdentity / solverInvocation / solverInputDigest / solverResultDigest /
  attestation / provenance / identityDigest`. (`src/verification/cert_writer.nim:178-420`)
- **EvidenceCapture** = internal in-memory evidence bundle collector; `proofDigest = ""` is an explicit
  T0 placeholder. (`src/core/trusted/evidence_capture.nim:40-75`)

Canonical vault is empty because no promotion has run — structure is complete, not broken.

### F2 — Is there a real proof artifact? → **No genuine proof object exists today.**

- `solverResultDigest` is **derived** `sha256("status="&solverStatus&"\\ntier="&tier)` from
  solverStatus+tier, **not** from real solver stdout (`.z3out` files exist but their hash is unused).
  (`cert_writer.nim:320-327` vs `state_manager.nim:61-69`)
- `proofDigest` is always `""` (empty placeholder; "only a T2/kernel check fills this").
  (`evidence_capture.nim:58`, `evidence_calculus.nim:37,44`)
- `leanArtifactHash` is a stub, never populated; `kernelAcceptance`/`toolAcceptance` digest fields do
  not exist (only boolean `lookupIsKernel`, `leanCompilerVerified`, `solverProvenance` heuristic).
- A real proof-object type exists (`ProofArtifact`, `proof_artifact_types.nim:21-29` with
  `treeSha/z3Proof/leanOleanHash/toolchainHash/proofHash`) but is used only in gate-signing IPC, not the
  certificate pipeline; `writeProofArtifact` is dead code (DEBT#412).

**context7 corroboration (Z3)**: Z3 only emits a genuine proof object when `PROOF_MODE` is set
(1 or 2); an `unsat` result is a solver result, not a proof certificate. Axiom's current pipeline does
not enable Z3 proof mode. **context7 corroboration (Lean 4)**: "verified" means the Lean kernel accepts
a proof term; `sorry`/axioms are explicitly unsound and must not count.

**Consequence**: using the name `proofDigest` for a digest of `solverStatus+result` would be a misnomer.
Per the architectural review rule 2, represent an **EvidenceBundle** with honest evidence digests:
`proofInputDigest, proofResultDigest, kernelAcceptanceDigest, toolAcceptanceDigest, provenance`; the
word `proofDigest` is only legitimate if/when a real proof object (Z3 PROOF_MODE / a real Lean artifact)
is wired into the certificate pipeline — which is out of current scope and would itself be a capability
change, not a persistence fix.

### F3 — Where is the actual promotion authority? → **Scattered; no single function is a full aggregate.**

Multiple partial gates exist; none checks all criteria together (checks matrix F3-14):
- `cert_writer.writeCertificateFromUapResult` — writes v3 fields; checks claim-derived + evidence
  consistency; omits proofDigest/acceptance/vacuity/kernel/tool. (`cert_writer.nim:178`)
- `certificate_manager.writeCertificate` / `validateCertGreenWritable` — status + winningStrategy +
  `statusConsistentWithEvidence` only. (`certificate_manager.nim:57-64,121-122,222-233`)
- `cert_promotion.promoteVerdict` / `promoteToCanonical` / `isPromotionAllowedStatus` — identity +
  fingerprint + contentHash + status whitelist; omits proof/acceptance/v3-completeness. (`cert_promotion.nim:57-112,199-310`)
- `proof_integrity.isVkdAdmissible` — deep-verify (DIP) + admissibleEvidence (dual) + status certGreen. (`proof_integrity.nim:154-182`)

**Consequence**: a single promotion gate is needed BUT it must be a **decomposition + `aggregate()`
policy-reducer**, not a new god-predicate doing new verification. Given F1=C (reuse existing SSOT), the
aggregate routes through the existing fragments (`validateCertGreenWritable`, `isVkdAdmissible` deep
verify, identityDigest binding) as small verifiers (`verifySemanticEvidence / verifyProofArtifact /
verifyAcceptance / verifyIdentityBinding / verifyCertificateCompleteness → structured results` →
`aggregate()` = policy reducer over `all required passed?` + `reasons[]`). No new verification inside
the aggregator.

### F4 — Does a real admissible golden target exist without new verification semantics? → **B: No — research blocker.**

- `metrics.vkd = 0/23`, kernel scope 40 (exempt 17, VKS 23), `kernelVerified = 0`. (`data/baseline.json:24-33`)
- **All 35 non-exempt kernel targets** produce `psNoObligation`/`ObliSemanticNoApplicable`; IR pipeline
  `Pass 0 / Skip 35`. Root cause DEBT#416 (CHC/Spacer declines all kernel symbols; fix applied
  2026-08-11 but UNRESOLVED). (`tmp/col_probe_a.err`, `data/debt_registry.json:2438`)
- No certGreen exists in runtime artifacts (test fixtures only).
- `isVkdAdmissible` requires `isDeepVerified ∧ admissibleEvidence(solverProved ∧ translationProved) ∧
  status=certGreen`; with zero obligations, `solverProved=false ∧ translationProved=false` — no target
  is admissible.

**context7 corroboration**: Lean "verified" requires a kernel-accepted proof term (F2), reinforcing that
admissibility cannot be met while obligation generation yields no obligations.

**Consequence (the ONLY branch)**: **F4 = B ⇒ R8 is a separate verification-research blocker.** Do NOT
implement R8 as a persistence task. Closing R8 requires fixing CHC/obligation generation semantics to
produce real obligations for at least one admissible kernel target, which is a research effort
separate from the evidence-boundary redesign. The Phase-0 decision is therefore that **the R4/R7
closure can be designed, but R8 (persist/reload + real certGreen) cannot be executed as pure
persistence work and is deferred/blocked pending the obligation-semantics blocker.**

### F5 — What is the actual persistence + CLI boundary? → **Partially atomic persist; no reload/reverify; exit authority scattered.**

**Persistence**:
- `promoteToCanonical` is partially atomic: journal-first → `writeFileOpt` cert → manifest via
  tmp+`safeMoveFile` → rollback cert on manifest failure. (`cert_promotion.nim:240-309`)
- **No staging→reload→reverify step exists** (grep 0 matches). Certificate verification is in-process
  (`cert_cli.nim:47 → isDeepVerified`); **no `ax cert verify` subprocess exists**. The only subprocess
  path is `readiness_start_gate` compiling+running `tests/gateway/productization_start*` E2E.
- F4=B ⇒ this staging/reload/reverify/promote work is gated behind the research blocker (F4).

**CLI**: no `CliOutcome` type; **85 `quit()` call sites across 16 files + 28 `exitCode != 0` guards**;
invalid-input contract 3 vs actual 1; no top-level signal handler. (`productization_contract.md:258`,
`action_plan_cli.nim:242,251`, `main.nim`)

**Consequence**: R7 is a self-contained presentation-contract fix (independent of R4/R8): introduce
`CliOutcome` (Success→0, VerificationFailure→1, InternalError→2, InvalidInput→3) mapped in one place;
parseInput→InvalidInputError→exit(3); keep SIGSEGV as out-of-contract crash (never shim signal→2);
4-state gold matrix with invariant "no internal error converts to success(0)."

## Locked decisions (ratified, independent of F4)

1. **Storage identity model**: logical `CertificateIdentity ─► canonical artifact reference ─► existing
   CAS/vault`, **reusing the existing CAS** (no second CAS). certificateIdentity-keyed paths are the
   documented v1 representation; logical identity and physical storage remain separable.
2. **Hash dependency DAG (cycle-free)**: `ProofArtifactDigest ─► AcceptanceDigest ─► CertificateIdentity
   ─► CertificateDigest`. Cycles (`CertificateIdentity ─► Acceptance ─► CertificateIdentity`) are
   FORBIDDEN. `CertificateIdentity` (via `V3IdentityState → compV3Identity()`) carries **no provenance
   timestamp** — identity ≠ execution occurrence.
3. **Independent-evaluator boundary**: the product implementation may NOT call the independent
   evaluator's internal helpers to generate R4/R8 evidence; evidence flows
   `implementation → real artifact → independent evaluator → artifact inspection`. The evaluator is the
   sole GO/NO-GO arbiter (R1–R8), and it must rerun unchanged.

## Consequences

- Phase 1 (R4) is designable now: evidence-digest binding into the existing TrustCommit/certificate
  structure + `aggregate()` policy-reducer promotion gate, without new abstractions (F1=C) and without
  fabricating `proofDigest` (F2).
- Phase 3 (R7) is designable now: `CliOutcome` single exit mapping (independent presentation contract).
- **Phase 2 (R8) is BLOCKED by F4=B** (obligation-semantics research). It must NOT proceed as
  persistence engineering. Re-approval is required after the obligation-generation research blocker is
  resolved.
- The independent evaluator remains the arbiter; VKD 0% stays a post-start maturity item.

## Evidence map
- F1: `trust_commit.nim`, `evidence_capture.nim`, `cert_writer.nim:178-420`, `cert_promotion.nim`, `src/verification/certificates/`, `data/proof_cache/`
- F2: `cert_writer.nim:313-327`, `evidence_capture.nim:58`, `evidence_calculus.nim:37,44`, `proof_artifact_types.nim:21-29`, DEBT#412, Z3 PROOF_MODE (external), Lean "verified" (external)
- F3: `cert_writer.nim:178,438`, `certificate_manager.nim:47-64,121-122,222-233`, `cert_promotion.nim:57-112,199-310,327`, `proof_integrity.nim:154-182`
- F4: `data/baseline.json:24-33`, `tmp/col_probe_a.err`, `data/debt_registry.json:2438`, `proof_integrity.nim:154-182`, `evidence_calculus.nim:110-116`
- F5: `cert_promotion.nim:240-309`, `cert_cli.nim:47`, `readiness_start_gate.nim:84-112`, `productization_contract.md:258`, `action_plan_cli.nim:242,251`, `main.nim`, `src/cli/` quit() scan

## Decision surface (final)
| ID | Answer | Branch |
|----|--------|--------|
| F1 | C — reuse existing SSOT (no new EvidenceBundle) | — |
| F2 | No real proof object → EvidenceBundle evidence digests; `proofDigest` name reserved for real proof object | — |
| F3 | Scattered partial gates → single `aggregate()` policy-reducer over existing verifiers | — |
| F4 | **B — no admissible golden target (research blocker)** | **R8 deferred to obligation-semantics research** |
| F5 | Atomic persist exists; no reload/reverify; exit authority scattered | R7 independent fix |
