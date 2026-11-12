# Base36 Sizing Relational Binding — Product Contract (S0)

> **Status**: Committed product contract — S0 of the `feat/base36-sizing-binding` slice
> **Created**: 2026-10-06
> **Revised**: 2026-10-07 — modelprofile identity bind (§4.1), §4 item 2 bound, §9 projection status
> **AGENTS.md 참조**: §0.12 (제품 계약 선행), §0.9 (극장 금지), §0.3 (신뢰 경계), §4 (GUARDIAN)
> **Related**: [obligation_semantics.md](./obligation_semantics.md), [lean_sorry_gate.md](./lean_sorry_gate.md), [productization_contract.md](./productization_contract.md), [verification_density.md](./verification_density.md), [decision_binding_framework.md](./decision_binding_framework.md)
> **Spec registry**: `SPEC-B36-RELATIONAL` (docs/spec/spec_registry.json)

---

## 1. Scope

**Subject**: `stew/base36.nim` lines 52–60 of an **unmodified** clone of status-im/nim-stew v0.5.2 (READ-ONLY subject; `git -C <nim-stew> status --porcelain` must remain empty at all times — Zero-Footprint Integrity).

**Claim under verification** — a relational theorem about the two sizing functions:

```nim
func encodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 277) div 179 + 1          # :52-55
func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277              # :57-60
```

```
∀ n : Int,  0 ≤ n ∧ n ≤ 33297371974204966 →
    decodedLength (encodedLength n) = n          -- equality, exact (not ≥)
  ∧ encodedLength n ≥ 1
  ∧ ¬ overflowAt encodedLength n
  ∧ ¬ overflowAt decodedLength (encodedLength n)
```

The bound is `high(int) div 277` on a 64-bit `int` and is **exactly tight**: at `n = 33297371974204966` the intermediate `277*n = 9223372036854775582 ≤ high(int)` (headroom 225), and at `n+1` it is `9223372036854775859 > high(int)` — overflow.

**Tracks**: S0 (this contract) + I4 (canonical-path honest policy) + I5 (the out-of-tree `soExplicit` spec) are owned by this slice's contract track. The **semantic binding** (Nim implementation semantics → IR → Lean) is owned by a separate track and is a handoff, not a deliverable of this contract (§9).

**Hard constraint**: the binding closes with EXISTING machinery. No new verifier, no new effect analyzer, no new merge authority, no new gate, no new required check.

## 2. The claim — origin and placement (I5)

- The spec lives **out-of-tree** (`config/spec/base36_sizing_relational_spec.json`). Annotating nim-stew is a Zero-Footprint violation and is ruled out.
- Spec origin is **`soExplicit`** and must remain so: only `soExplicit` / `soCanonicalDerived` authorize verification (`src/core/trusted/specification_artifact.nim:48-51`); mined/LLM specs yield NOT PROVED (`src/core/trusted/claim_authority.nim:96`). This contract does not weaken that gate; the overlay loader pins origin to `soExplicit` and fails closed otherwise.
- **What the claim is**: a theorem about the **relationship of the two sizing functions** under the stated domain precondition. It is NOT a postcondition of `decodedLength` alone (its standalone input domain is bounded by `high(int) div 179`, a different envelope), and NOT a buffer-safety claim about `encode` (that requires `encode`'s write bound and is explicitly the next slice).

### 2.1a. Synthesized relational subject — binding rules (§6a extension)

The verification subject for this slice is the **synthesized relational composite** `roundtrip_dec_enc(n) := decodedLength(encodedLength(n))`, produced deterministically by β-splicing the two materialized subject bodies. It is not text present in the subject source, so the single-symbol extraction-agreement rule cannot apply to it literally. The binding rules are:

1. **EA is measured per original symbol**: the extraction agreement is measured **separately for `encodedLength` and `decodedLength`** — each against the real subject bytes of `stew/base36.nim` (§6a: `inputHash` continues to bind the subject source bytes).
2. **Composite identity** = (EA evidence of **both** originals) ∧ (the deterministic β-splice derivation rule recorded by the synthesis) ∧ (the composite IR digest). All three are part of the sealed binding.
3. **Fail-closed**: if either original's EA is absent or disagrees, the composite is **not sealable** — a binding constructed without both EA legs is a theater artifact and is refused. There is no "EA-free seal" of a synthesized subject, in any form.
4. **Reflected invariant**: the Lean evidence remains bound to the real subject meaning — both originals are EA-anchored in the subject bytes, which is **strictly stronger** than a single-symbol EA (the composite's provenance is two independent extraction agreements, not one).
5. **Division-denotation statement on the certificate**: the certificate states the division semantic profile explicitly — the renderer emits Lean `/` (floor, the `omega`-decision operator) while Nim `div` truncates (`Int.tdiv`); they coincide on the stated domain `0 ≤ n` (nonnegative operands), which is the kernel-checked correspondence proved as `Int.tdiv_eq_ediv_of_nonneg` (`proofs/IR/Denotation.lean:30-39` records the denotation scoping; the domain precondition is part of the verified proposition per §3.2).

## 3. Semantic caveats (load-bearing — part of the claim, not decoration)

1. **`int` width**: Nim `int` is pointer-width signed. The bound is width-derived: 64-bit → `33297371974204966`, 32-bit → `7752648`, 16-bit → `118`. It MUST be re-derived per target width; a certificate pinned to one width makes no claim at any other width.
2. **Division semantics**: Nim `div` truncates toward zero; Lean `Int.div` floors. They coincide **only for `n ≥ 0`**. Therefore `0 ≤ n` is a **discharged hypothesis** — dropping it changes the meaning of the Lean proof (floor/truncation divergence at `n < 0`), so it is part of the verified proposition, not an informal preamble.
3. **`{.push raises: [].}` does NOT track or prevent `OverflowDefect`**: Nim's `Defect` family is outside the effect system. `encodedLength`/`decodedLength` can defect at runtime (checked builds) with no visible effect-contract trace. The certificate must state this explicitly.

## 4. Certificate identity obligations (minimum binding set)

The certificate for this slice must bind, at minimum:

| # | Obligation |
|---|---|
| 1 | Target **int width** and the host **(cpu, os, triple)** |
| 2 | **Build/checks profile** — checked-`Defect` vs unchecked-wrap are *different program meanings*; the certificate names which one was verified — **bound 2026-10-07**: the identity carries `modelprofile=<SemanticProfileV1Hash>` (§4.1) |
| 3 | **Division semantic profile** — truncation (`Nim div`) vs floor (`Int.div`) vs `Nat` (non-negative) — the Lean encoding states which was used |
| 4 | The **domain precondition** itself as an `IRFuncDef.preConditions` entry (`0 ≤ n`, `n ≤ 33297371974204966`), not prose |
| 5 | **Pinned Nim 2.2.10** — overflow-check defaults are version behavior |
| 6 | The note that **`raises: []` does not cover `OverflowDefect`** (§3.3) |
| 7 | **Subject hash · IR digest** — the certificate binds the exact subject source bytes and the IR funcDef digest it was derived from |

### 4.1. modelprofile identity bind (added 2026-10-07)

Item 2's build/checks profile is bound in the D2 toolchain identity as a
`modelprofile` segment, produced by `captureToolchainIdentity`
(`src/verification/obligation/canonical_verification.nim:134`):

- **Value**: `modelprofile=<SemanticProfileV1Hash>/no-overflow-obligations/coincident-checked-wrap-domain`, where
  `SemanticProfileV1Hash` is the deterministic SHA-256 of the verification
  domain's semantic profile — target, int width, and the
  overflow/division/modulo/shift/float/string/uint modes
  (`src/core/trusted/semantic_profile.nim`, hash at the `SemanticProfileV1Hash`
  const; measured value `d2c44f569ef61e349a915582c4237b1b747df4d30a4701712178655bdd5bc44e`,
  regenerated 2026-10-07 by the DEBT#494 weakening — see
  `semantic_profile_verified_semantics.md`; predecessor
  `af30124e618db1dae9bc8ba95991f620f07077847a29d3f42b4fcd67b48bdf4d` named the
  former nominal generation). Since the weakening the profile **declares the
  coincidence semantics itself** (`spDivCoincidentNonnegative` /
  `spOverflowObligationDischarged`), so the segment suffix and the declarations
  agree; evidence sealed under the predecessor hash fails closed and
  re-executes (§9 epoch semantics).
  It is the SAME constant the certificate writer consumes as the
  `semanticProfileId` fallback (`src/verification/cert_writer.nim:398-411`)
  — no second semantic-state source is created.
- **Not Axiom's own compile profile**: the segment names the verified
  domain's declared model, never the compiler this binary was built with
  (the host compile profile stays in the separate `int<width>bit` and
  `hostPlatformId` segments, `canonical_verification.nim:115-116`).
- **Coincidence wording**: a no-overflow obligation (e.g. the `¬ overflowAt …`
  conjuncts of §1) discharges overflow reachability, so checked
  (`OverflowDefect`) and wrapping arithmetic coincide **in the verified
  domain** — the identity states exactly that domain, mirroring the div/rem
  precedent (`div=lean-floor/nim-trunc/coincident-nonneg-domain`,
  `canonical_verification.nim:117`). Bound 2026-10-07 (DEBT#494): the
  declarations themselves now name these coincidence domains
  (`spDivCoincidentNonnegative`, `spOverflowObligationDischarged`) — the
  former nominal Phase-2 conformance direction is withdrawn.
- **Attestation fixed identity**: `pinnedToolchainIdentity`
  (`src/verification/attestation_orchestrator.nim:111-125`) carries the same
  segment, so attestation stage (e) (`:598-599`) binds the semantic model,
  not only tool versions; the pinned evidence draft
  (`data/certification/evidence-draft.json`) is regenerated in the same
  generation, and the admission draft-shape check
  (`.github/workflows/admission-check.yml:886`) accepts the segment.

## 5. Canonical-path honest policy (I4)

Facts fixed by this contract (they were verified against the code before this slice):

- `src/verification/obligation/canonical_verification.nim` invoked `evaluate` with `VerificationPolicy(allowedAxioms: @[], sorryPolicy: spAllow)` and left `sorryScan` at its default `@[]`.
- `verification_decision_authority.nim` skipped the allowlist check entirely when `allowedAxioms.len == 0`, and `spAllow` could still return `vdVerified` — contradicting its own enum doc ("sorry markers → Candidate (not VERIFIED)") and the in-code comment ("don't upgrade to verified").

**Committed policy** (all four are acceptance-tested):

1. The canonical path uses a **non-empty axiom allowlist**: the project's existing `LeanAxiomAllowlist` (`src/verification/lean_lsp_protocol.nim:427-429`: `Classical.choice`, `Quot.sound`, `propext`, `funext`) — reused, not reinvented.
2. The canonical path uses **`sorryPolicy: spForbid`**.
3. The `bindReceipt` call site binds a **measured sorry profile** (`scanSorryMarkers` over the artifact source and the receipt's kernel observation) instead of the empty default.
4. **Doc-vs-code resolution**: the **code was wrong, the doc was right**. `spAllow` now caps sorry-bearing artifacts at `vdCandidate` (never `vdVerified`); `spIgnore` (deprecated) follows `spAllow`. The enum doc is unchanged and is now true. An empty allowlist no longer silently skips the check — it permits **no** axioms, so any axiom-bearing KAA is `vdPolicyRejected`; a KAA with an empty observed axiom set still qualifies.

**Over-grading audit result**: the only production `bindReceipt` call site is `canonical_verification.nim:624`, and its only feed is the deterministic renderer (`renderLeanForFuncDef`), which lowers IR to literals/params/binops/if/not + `omega` and cannot emit `sorry`. No sorry-bearing artifact reached the canonical path, therefore **no existing evidence was over-graded** and no `Theater/` entry is registered. The residual risk (a future caller passing a sorry-bearing artifact) is closed by items 1–4, with the strong track's `validateEvidence` discipline (`src/verification/obligation/lean_evidence.nim:270-381`) remaining the reference — this policy reuses its allowlist and scan convention, not a parallel verifier.

## 6. Terminal outcome (measurable, machine-checkable)

`구현 → 검증 → PR → merge → canonical main 실행 → acceptance` closed with real commands and observable evidence:

1. `origin/main` has the merge commit (`git fetch origin && git merge-base --is-ancestor <merge-sha> origin/main`).
2. `origin/axiom/certificates` has the certificate bound to **subject hash · IR digest · int width · Nim 2.2.10** (§4 items 1, 5, 7 present in the certificate object).
3. `git -C <nim-stew> status --porcelain` is **empty**.
4. Re-running the same canonical command yields a **byte-identical** canonical projection (compare `sha256sum` of two consecutive projections).

Declarations, PR creation, local tests, or partial CI success do NOT count as done.

## 7. Acceptance criteria (machine-checkable)

| # | Criterion | Check |
|---|---|---|
| A1 | `nim check` / `--compileOnly` passes on every module this slice touched | command output, exit 0 |
| A2 | A sorry-bearing artifact reaching the canonical policy is **rejected** | `evaluate(kaa, canonicalVerificationPolicy()) == vdPolicyRejected` for a KAA whose measured profile contains `sorryAx` / `sorry` (unit + real-Lean end-to-end) |
| A3 | An **empty allowlist does not silently skip**: KAA with a non-empty observed axiom set + empty allowlist → `vdPolicyRejected` | unit test |
| A4 | `spAllow` caps a sorry-bearing KAA at `vdCandidate` (doc == code) | unit test |
| A5 | A **mined/LLM spec still yields NOT PROVED** (`clNoSpecification`) and an explicit out-of-tree overlay yields an authorized `soExplicit` artifact | unit test over `deriveClaim` / `explicitSpecFromOverlay` |
| A6 | The canonical policy structure is committed: non-empty allowlist == `LeanAxiomAllowlist` ∧ `spForbid` | unit test on `canonicalVerificationPolicy()` |
| A7 | Subject tree untouched | `git -C <nim-stew> status --porcelain` empty |

## 8. Explicit non-claims

- NOT a postcondition of `decodedLength` alone; NOT a postcondition of `encodedLength` alone.
- NOT a buffer-safety / memory-safety claim about `encode` or `decode` (needs `encode`'s write bound — next slice).
- NOT a claim about any `int` width other than the one pinned in the certificate (§3.1).
- NOT a claim that `encodedLength`/`decodedLength` cannot raise at runtime: `OverflowDefect` is outside the effect system (§3.3); `raises: []` is not overflow safety.
- NOT a claim valid for `n < 0` (division-semantics divergence; `0 ≤ n` is a discharged hypothesis, §3.2).
- NOT a claim that nim-stew was modified, annotated, or verified in-tree (Zero-Footprint).

## 9. Handoffs (out of this track's scope)

- **Semantic binding** (`src/core/trusted/ir_to_lean.nim`, `ast_to_ir.nim`, `proofs/IR/*.lean`, `obligation_types.nim`, `kernel_acceptance_authority.nim`, `lean_kernel_boundary.nim`, `docs/spec/obligation_semantics.md`): owned by the concurrent binding track. This contract states WHAT must be bound (§3, §4); HOW is theirs.
- `IRFuncDef.preConditions` population for the base36 subject (§4 item 4) lands with the binding track's IR extraction.
- The canonical certificate writer must project §4's binding set into the certificate object; fields it cannot yet express must fail closed, not be omitted.
- **modelprofile projection (bound 2026-10-07)**: §4 item 2's build/checks profile now enters the identity chain via the `modelprofile` segment (§4.1) — D2 capture (`canonical_verification.nim:134`), attestation pinned identity (`attestation_orchestrator.nim:111-125`), and the certificate `semanticProfileId` consume the same `SemanticProfileV1Hash` (`src/core/trusted/semantic_profile.nim:123`; writer fallback `src/verification/cert_writer.nim:398-411`). The reuse/attestation identity comparisons (`src/verification/accounting/run_accounting.nim:337`, `:416`; `attestation_orchestrator.nim:598-599`) are recorded-vs-current equality, so records sealed before this bind fail closed and re-execute — an identity change invalidating old evidence is the intended epoch semantics, not a defect. The 2026-10-07 DEBT#494 weakening regenerated the hash a second time (af30124e… → d2c44f56…) under the same rule.
