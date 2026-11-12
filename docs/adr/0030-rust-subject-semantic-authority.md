# ADR-0030: Rust subject semantic authority

## Status

**PROPOSED (2026-10-12)** — Rust subject workstream (`feat/rust-subject-v1`) Phase 0 ADR record.
It mirrors the precedent of [ADR-0029](0029-nim-semantic-authority-and-unresolved-facts.md) for
the Rust subject and records verdicts only; it changes no code and wires no gate. It fixes
(i) the authority for Rust language semantics within the declared certified subset,
(ii) the reimplementation ban and its bypass clause, (iii) the status of compiler-derived facts
together with the channel that tool trust must travel through, and (iv) the assurance ceiling
that holds while the rustc→LLBC channel remains Qualified.

**Scope boundary**: the certified subset itself is declared in
`docs/spec/rust_certified_subset.md` (referenced by `docs/spec/productization_contract.md:11`
§1). Machine enforcement of this ADR's verdicts is NOT part of this ADR — see
Residual Limits U1–U4.

---

## Context

### The Rust subject inherits ADR-0029's gaps with no Rust-specific instrument in place

ADR-0029 closed the authority / reimplementation / fact-status gaps **for Nim** by naming the
pinned Nim frontend as authority (D1), banning reimplementation including the bypass path (D2),
and demoting compiler-derived facts to assumptions (D3). For **Rust** no repository instrument
makes any of those verdicts today:

| Instrument (Nim) | Rust counterpart (today) |
|---|---|
| TCB row naming the frontend **Qualified** (`docs/spec/certification_continuity_contract.md:71`) | none — no Rust row exists |
| Scope lock `data/verification_scope.lock` (schema v3: `kernel_symbols` / `vksTotal`) | none — no `vks_rust` declaration exists |
| Fail-closed codec boundary (`src/verification/ast_wire.nim:60-68`, `aweUnsupportedKind` `:79-83`) | none on a Rust path |
| INV-9 forbidden-claim static scan (`docs/spec/certification_continuity_contract.md:252`) | scanner unimplemented (U2) |

This is the same reading hazard ADR-0029 §Context U1 identified for Nim: a documented gap reads
as **permission**. Without a Rust verdict, nothing forbids Axiom from estimating unresolved
Rust facts into verification candidates, or from claiming Rust semantic assurance that the
machinery never produced.

### Tool trust must not leak into the program-premise channel

`docs/spec/obligation_semantics.md:42` defines `assumptions` as the canonical semantic facts
**assumed about the program**; the extractor pins that channel to the program's own path —
"its assumptions are the enclosing path condition"
(`src/verification/obligation/semantic_target_extractor.nim:15`). A claim such as
"rustc→LLBC preserved Rust semantics" is a fact **about the toolchain**, not a premise **about
the subject program**. The identity channels that legitimately carry tool trust already exist:
`toolchainFingerprint` (`docs/spec/productization_contract.md:368`, §10.2) binding evidence via
`canonicalizeKaa → kaaDigest → evidenceId`
(`src/verification/obligation/kernel_acceptance_authority.nim:56`), and the
`computeBoundObligationId` preimage (`src/verification/obligation/obligation_types.nim:437`,
fail-closed on malformed components — `docs/spec/obligation_semantics.md:114`).

---

## Decision

### D1. rustc is the semantic authority for the Rust subject subset — Axiom is a consumer and may NOT reimplement Rust semantics

- **Authority** = the pinned rustc toolchain. Axiom is a **consumer**, never the authority.
  This mirrors ADR-0029 D1 (`docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md:99`)
  and extends the same reimplementation ban ADR-0029 D2 (`:113`) applies to Nim language
  semantics.
- **Banned reimplementations** — in any form:

| Banned | Banned example |
|---|---|
| Rust type/trait inference evaluator | resolving a trait selection or inference result with Axiom's own rules and lowering it to IR |
| Borrow-check / drop-order evaluator | computing borrowck or drop outcomes inside Axiom |
| const-evaluator | evaluating `const` items or `const fn` bodies itself and substituting results |
| Target-layout constants | hardcoding `size_of::<u32>()`-style target-dependent values |
| **Bypass clause** | promoting an *estimated* unresolved Rust fact into candidate eligibility — estimation is reimplementation in effect (ADR-0029 D2 bypass clause) |

- A placeholder `check true` at any such evaluator position is additionally a stub violation
  (AGENTS.md §0.8) and counts as reimplementation under this verdict.
- Linking rustc as a library would not raise the authority's grade either — same authority,
  same grade (ADR-0029 D1 derived-authority clause).

### D2. Compiler-derived facts are consumed as ASSUMPTIONS only — never evidence. Tool trust does NOT travel in `assumptions`

- **consume-as-assumption**: facts derived from the Rust toolchain enter verification only as
  program preconditions. They never substitute IR, never replace a solver result, never make an
  obligation discharged. On the evidence ladder (`FactStatus`,
  `src/core/trusted/semantic_fact_types.nim:29-33`) a toolchain-derived Rust fact is capped at
  `fsObserved` (ADR-0029 D3, `:140`).
- **Channel separation (critical)**: the `assumptions` field is for **PROGRAM preconditions
  only** — "the enclosing path condition"
  (`src/verification/obligation/semantic_target_extractor.nim:15`). Tool trust — the claim that
  rustc→LLBC extraction preserved semantics — is NOT a program precondition and MUST NOT be
  placed in `assumptions`. Doing so would dress a TCB assertion up as a program fact and let it
  evade provenance checks.
- **Tool trust binds through identity instead**: `toolchainFingerprint` → `evidenceId`
  (`docs/spec/productization_contract.md:368` §10.2;
  `src/verification/obligation/kernel_acceptance_authority.nim:56`) and the
  `computeBoundObligationId` preimage
  (`src/verification/obligation/obligation_types.nim:437`; fail-closed on missing or malformed
  components — `docs/spec/obligation_semantics.md:69,:114`). Fingerprint mismatch = fail-closed,
  consumption refused (ADR-0029 D3 provenance precedent;
  `docs/spec/cfg_contract_specification.md:666`).
- **Evidence ceiling unchanged**: no Rust toolchain-derived fact alone may produce
  `Verified` / `Safe` / `Proved` — bare solver status and generator-internal equivalence are
  non-evidence (`docs/spec/cfg_contract_specification.md:663,:669-671`;
  `certification_continuity_contract.md:235` INV-4).

### D3. rustc→LLBC is a Qualified/assumption boundary — no unconditional Rust semantic assurance while it remains Qualified

- The extraction channel from rustc (MIR) into the verification IR (LLBC — Low-Level Borrow
  Calculus class) is a **tool-qualification boundary**. Its grade is **Qualified** — the same
  grade the Nim frontend already carries
  (`certification_continuity_contract.md:71`); Axiom consumes its outputs and never certifies
  the extractor's own correctness.
- While the channel remains Qualified, its outputs participate **only through the assumption
  channel** (D2), and every Rust artifact claim is bounded to the shape
  "verified w.r.t. the extracted representation under a Qualified extractor". Claiming
  unconditional Rust semantic assurance ("Rust semantics certified") is a forbidden claim —
  same vocabulary discipline as INV-9's forbidden-claim list
  (`certification_continuity_contract.md:252`).
- **Grade-inflation ban**: no trust artifact may assert a stronger claim than the strongest
  evidence actually produced (`docs/adr/0017-trust-claim-authority.md:48-51`). Discharging the
  Qualified grade later requires an independent differential or a machine-checked translation
  contract — a separate decision, not a silent upgrade.

---

## Rejected Alternatives

### R1. "Axiom models Rust semantics directly for the subset" — **rejected**

A non-authority consumer substituting the authority's decisions; widens TCB with an unverified
evaluator whose divergence would be silent — the theater zone (AGENTS §0.9). Mirrors ADR-0029
R1.

### R2. "Record rustc→LLBC preservation as an `assumptions` entry" — **rejected**

Channel misuse: `assumptions` is the program-premise channel
(`semantic_target_extractor.nim:15`). A tool-trust entry there reads as if the *subject
program's* path depended on it, and no fingerprint binding would be required for it to pass.
Tool trust must travel the identity channel (D2).

### R3. "Claim unconditional Rust assurance now; settle the extractor's grade later" — **rejected**

Grade inflation ahead of evidence (ADR-0017). INV-4 / INV-9 exist precisely to block claim
sentences that outrun the machinery (`certification_continuity_contract.md:247,:252`).

---

## Consequences

| Verdict | Fixed | Still open |
|---|---|---|
| D1 authority | rustc = authority; reimplementation + bypass banned | no Rust TCB row in the continuity contract (U4) |
| D2 fact status | assumption-only, `fsObserved` cap; tool trust via fingerprint→evidence + obligation-id preimage | Rust-path producers wiring the fingerprint binding (U3) |
| D3 grade ceiling | Qualified-bound claim shapes only | machine-enforced forbidden-claim scan (U2); trust-boundary admission (U1) |

**Positive**: the Rust subject starts with the authority, fact-status, and assurance-ceiling
questions closed from day one — the Nim gap analysis never has to be re-derived for Rust.

**Negative**: the verifiable Rust candidate set is permanently narrowed to the declared subset
(`docs/spec/rust_certified_subset.md`); overflow-input semantics is outside it by construction.
Until U1–U4 close, every clause above is **document discipline**, not machine enforcement —
and must not be described as enforced.

---

## Residual Limits (U-issues — what is NOT yet machine-enforced)

- **U1 — `AxiomTrustBoundary` is tests-only.** The trust freeze is declared
  (`src/core/trusted/trust_boundary.nim:24` — `TrustCategory` disjointness, `exists` field) but
  its only consumers are unit tests
  (`tests/unit/test_evidence_calculus.nim:17-35`). No gate reads
  `categoryOf` / `isTrusted` / `existsInTrustBoundary` at admission time, so the
  recorded≠trusted discipline is documentation + tests, not enforced admission.
- **U2 — INV-9 static scan unimplemented.** `certification_continuity_contract.md:252` mandates
  a static scan of forbidden claim sentences; no scanner exists. After this ADR the same scan
  must catch the Rust analogue ("Rust semantics certified"). Until then the D3 assurance
  ceiling is review-bound, not machine-bound.

  **Status update (2026-10-13, `feat/inv9-sentence-scan`)** — the scanner now exists:
  `src/verification/forbidden_claim_scan.nim` (closed 4-phrase forbidden vocabulary — the two
  INV-9 sentences, the "Rust semantics certified" analogue, and the source-semantics
  certification axis; deterministic case-sensitive word-boundary matching; JSON payload
  field-path symbol anchors) + `tools/ci/check_inv9_forbidden_claims.nim` (fail-closed CLI:
  exit 1 on forbidden claim, exit 2 on unreadable/malformed target) +
  `tests/verification/test_forbidden_claim_scan.nim`. The scan is machine-bound at the
  test/CLI layer only; the INV-9 "gate FAIL" absorption into the landing lane (pre-commit
  hook, Makefile target, gateway landing policy) touches FROZEN surfaces (`src/gate/**`,
  `Makefile`, `.githooks/**`, `config/policy/**` under `config/repository_surface.json`
  v79) and requires a policy-version PR — until that lands, enforcement is the test-side
  assertion + caller-invoked CLI, not the gate lane. Allowlist:
  `tools/ci/inv9_forbidden_claim_allowlist.json` (symbol-anchored + content-hash, currently
  empty — the repo's certificate data surfaces scan clean).
- **U3 — No `vks_rust` scope lock.** `data/verification_scope.lock` (schema v3) declares only
  the Nim kernel universe. Until a Rust scope declaration exists, no Rust claim has a
  machine-declared denominator. `docs/spec/rust_certified_subset.md` names `vks_rust` as the
  required mechanism; it does not exist yet.
- **U4 — No Rust TCB row.** `certification_continuity_contract.md:71` names the Nim frontend
  Qualified; no row names the rustc→LLBC channel. D1/D3's grade lives in this ADR text only.

**Not done by this ADR (out of scope)**: product-contract amendment beyond what
`rust_certified_subset.md` declares, waivers, baseline changes, code or gate changes.

---

## Verification record

Document-only task; no code or data artifacts produced. Observations: line anchors of every
cited file read as of 2026-10-12; `AxiomTrustBoundary` consumer search over `src/`, `tests/`
(production consumers: none); repository-wide search for `vks_rust` / LLBC references in
`docs/` (none besides this ADR and `rust_certified_subset.md`). No build or gate run was
required — nothing outside `docs/` was touched.

---

## References

- `docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md:99` — D1 authority precedent
- `docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md:113` — D2 reimplementation +
  bypass ban precedent
- `docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md:140` — D3
  consume-as-assumption precedent
- `docs/adr/0017-trust-claim-authority.md:48-51` — no claim stronger than the strongest
  evidence (D3)
- `docs/spec/productization_contract.md:11` — §1 names the declared Rust certified subset as a
  scope component (whole-Rust support is not claimed)
- `docs/spec/productization_contract.md:368` — §10.2 `toolchainFingerprint` identity row (D2)
- `docs/spec/obligation_semantics.md:42` — `assumptions` = canonical facts assumed about the
  program (D2)
- `docs/spec/obligation_semantics.md:69,:114` — `computeBoundObligationId` SSOT + fail-closed
  malformed components (D2)
- `docs/spec/certification_continuity_contract.md:71` — Nim frontend Qualified TCB row
  (D3 grade pattern; U4 gap)
- `docs/spec/certification_continuity_contract.md:235` — INV-4 structural independence (D2)
- `docs/spec/certification_continuity_contract.md:252` — INV-9 forbidden-claim static scan
  (D3; U2)
- `docs/spec/cfg_contract_specification.md:663,:666,:669-671` — bare solver status,
  provenance mismatch, bypass = theater (D2)
- `src/verification/obligation/semantic_target_extractor.nim:15` — `assumptions` = enclosing
  path condition (D2 channel separation)
- `src/verification/obligation/kernel_acceptance_authority.nim:56` —
  `canonicalizeKaa → kaaDigest → evidenceId` (D2 binding path)
- `src/verification/obligation/obligation_types.nim:437` — `computeBoundObligationId` (D2)
- `src/core/trusted/semantic_fact_types.nim:29-33` — `FactStatus` evidence ladder (D2 cap)
- `src/core/trusted/trust_boundary.nim:24` — `AxiomTrustBoundary` declaration (U1)
- `tests/unit/test_evidence_calculus.nim:17-35` — the boundary's only consumers (U1)
- `data/verification_scope.lock` — schema v3, Nim-only universe (U3)
- `docs/spec/rust_certified_subset.md` — the declared subset this ADR bounds (scope)

---

*Written 2026-10-12. PROPOSED — a verdict record; no code, token, gate, or contract-key
change. The Residual Limits U1–U4 must close before any clause here is described as machine-
enforced.*
