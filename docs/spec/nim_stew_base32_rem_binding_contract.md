# nim-stew base32 rem-range binding — Product Contract (PR-E)

> **Status**: Committed product contract — the real-external-subject E2E slice (`feat/nim-stew-rem-e2e`)
> **Created**: 2026-10-07 (revised same day: subject re-selected on measured §2.1a extraction-agreement evidence)
> **AGENTS.md reference**: §0.12 (product contract precedes), §0.9 (theater prohibition), §0.3 (trust boundary), §0.9b (Triple-Closure), §4 (GUARDIAN)
> **Related**: [base36_sizing_binding_contract.md](./base36_sizing_binding_contract.md) (overlay/identity precedent), [authority_contract.md](./authority_contract.md), [obligation_semantics.md](./obligation_semantics.md)
> **Spec registry**: `SPEC-B32-REM-RANGE` — binding overlay `config/spec/nim_stew_base32_rem_spec.json` (soExplicit); `docs/spec/spec_registry.json` entry pending (epoch-scale item — deliberately not added in this slice)

---

## 1. Scope

**Subject**: `stew/base32.nim` `decodedLength` (lines 79–83) of an **unmodified** clone of status-im/nim-stew (READ-ONLY subject; `git -C <nim-stew> status --porcelain` must remain empty at all times — Zero-Footprint Integrity). The claim-bearing body term is fixed at line 80:

```nim
func decodedLength*(btype: typedesc[Base32Types], length: int): int =
  ## Return estimated length of decoded value of Base32 encoded value of length
  ## ``length``.
  let reminder = length mod 8          # :80 — the term the claim binds onto
  result = (length div 8) * 5 + ((reminder * 5) div 8)
```

**Claim under verification** — a relational remainder-range theorem over the subject's OWN `mod` term:

```
∀ length : Int,  0 ≤ length  →
    0 ≤ length mod 8  ∧  length mod 8 ≤ 7
```

**Computation meaning** (the identity-bearing statement): Nim `mod` truncates toward zero (sign follows the dividend); Lean `Int.emod` (`%`) is always nonnegative for a nonzero divisor. They coincide **exactly on the nonnegative-dividend domain**, so `0 ≤ length` is a **discharged hypothesis** of the verified proposition, not prose. This is the `rem` twin of the base36 `div` scoping and is carried by the identity segments bound in §4 — PR #532 added the `rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` segment and PR #540 added the `modelprofile` segment; both attach to the certificate identity **automatically** through `captureToolchainIdentity` (`src/verification/obligation/canonical_verification.nim`) with no slice-specific code.

**Hard constraint**: the binding closes with EXISTING machinery. No new verifier, no new verdict authority, no new merge authority, no new gate, no new required check. The overlay follows the base36 sizing overlay's authority pattern exactly (`explicitSpecFromOverlay` pins `soExplicit`, fail-closed). The §2.1a seal is extended in the same slice-scoped way #540 extended it: `measureClaimCarrierParseBoundComponents` — ONE extraction-agreement leg for the overlay's single original symbol plus the deterministic derivation digest (`term-splice-v1|rule=<ruleId>|symbol=<symbol>`); the binding site refuses a filled `ea2` slot (a fabricated second leg is theater).

## 2. Why this subject, and why an overlay

- **Measured subject selection (2026-10-07)**: the instruction's first-priority window is `stew/base32.nim:71-82` — two `mod`-using subjects live there: `encodedLength` (`length mod 5`, :71) and `decodedLength` (`length mod 8`, :80). The §2.1a extraction-agreement differential MEASURED the window:
  - `encodedLength`: **EA_UNSUPPORTED** — `eaAgreed=false`, Nim leg absent, `detail=EA_UNSUPPORTED: unsupported AST node (ckWhenStmt) outside the certified-subset wire set` (its `when btype is Base32NoPadTypes:` result selection). No seal over any claim about it is possible; stating one would be unverifiable theater.
  - `decodedLength`: **EA_AGREE** — `eaAgreed=true`, byte-equal serialized IR between the Nim and Lean reference extractors.
  `decodedLength` is therefore the mod-using subject in the first-priority window whose verification can close. The other instructed alternatives (`base36.nim:83` `carry mod 36`, `base10.nim:153`, `base58.nim:90`) are loop-carried remainders inside `while` bodies — outside the bounded synthesis subset (and base36 sizing is the previous slice's subject).
- **Why the census alone cannot prove it**: the base eligibility classifies `decodedLength` as `elProofCandidate`, but rule F (the constant-divisor probe) excludes a candidate whose only obligations are `¬(8 == 0)`-shaped division guards — proving them says nothing about the subject. The honest route to a non-trivial obligation is an **explicit out-of-tree spec** (`soExplicit` — the only origin that authorizes verification), stating the relational claim the subject's source implies. Annotating nim-stew is a Zero-Footprint violation and is ruled out.
- **What the claim is NOT**: not a sizing theorem about `decodedLength`'s result; not a claim about `encodedLength` (`mod 5` — measured EA-blocked, §7); not valid for `length < 0`.

## 3. Synthesis contract (D1–D4)

`synthesizeBase32RemRangeCandidate` (`src/cli/axiom_engine.nim`) synthesizes ONE candidate per overlay subject, following the base36 overlay's D1–D4 pattern:

1. **D1 (load)**: `config/spec/nim_stew_base32_rem_spec.json` is read through `explicitSpecFromOverlay` — origin pinned to `soExplicit`, anything else fails closed and blocks the run.
2. **D2 (materialize)**: the subject body is materialized UNCHANGED from the read-only tree for term extraction. The claim is bound onto the body's OWN `<param> mod <divisor>` term (first match, deterministic walk) — never onto a re-modeled expression. The claim CARRIER's body is that spliced subject term itself (the same carrier-body pattern as the base36 overlay, whose carrier body is the β-spliced composition of subject terms): the claim is result-free, so the theorem never references the carrier body. A candidate is produced only if such a term exists and its free variables are exactly the subject parameter (fail-closed shadowing guard — measured: a `shadowOffset mod 8` term over a non-parameter name is rejected, the examined symbol falls back to its own census record, and nothing verifies).
   - **§2.1a carrier binding (single origin)**: the carrier name never appears in the subject source, so name correspondence cannot apply; the carrier is sealed through `measureClaimCarrierParseBoundComponents` — ONE extraction-agreement leg for the overlay's original symbol (the same fail-closed differential the single-symbol path uses) plus the deterministic derivation digest `sha256("term-splice-v1|rule=<ruleId>|symbol=<symbol>")`. The `ea2` slot must be EMPTY at the binding site (`buildSubjectBinding` refuses a filled one — a fabricated second leg is theater). This is the single-symbol analog of the base36 composite's two-leg measurement, added in the same slice-scoped way #540 added the composite measurement.
3. **D3 (claim shape)**: `preConditions = [0 ≤ length]` (the coincidence domain), `postConditions = [0 ≤ length mod 8 ∧ length mod 8 ≤ 7]` with each conjunct splicing a fresh structural clone of the matched term. The carrier body is the spliced subject term (D2); `translationLossFree` measures the carrier (every region it carries is fully spelled — the renderers re-decide fail-closed downstream), while `bindingUniverseComplete` and `lossOutsideBindingRegions` keep the subject-measured bits. The candidate name is `decodedLength_rem_range` — never a subject symbol name.
4. **D4 (admission)**: the census classifies the composite (`classifyCandidateForCensus`); only a census-eligible composite enters the frontier. The wave-facing entry name is the examined symbol (`decodedLength`); the claim identity stays the overlay candidate name everywhere else (census record, funcDef name, obligation ids).

**Verified-proposition integrity (single verdict)**: the canonical artifact's theorems are rendered from the carrier's `postConditions` — exactly the relational claim. The tautological division guards (`¬(8 == 0)`-shaped, from rule-F constant divisors) are generated and counted, and rule F excludes them from the non-trivial count; they never constitute the verified proposition (measured: the guard alone reaches Z3 and its UNSAT yields only `certZ3Candidate` — never VERIFIED).

## 4. Certificate identity obligations (minimum binding set)

| # | Obligation | Where it comes from |
|---|---|---|
| 1 | Target int width + host (cpu, os, triple) | `int<width>bit`, `hostPlatformId` segments |
| 2 | Nim 2.2.10 pin + Lean/Z3 pins | `captureToolchainIdentity` |
| 3 | **rem semantic profile** — `rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` | PR #532 segment (automatic) |
| 4 | **modelprofile** — `modelprofile=<SemanticProfileV1Hash>` | PR #540 segment (automatic) |
| 5 | The domain precondition as an `IRFuncDef.preConditions` entry (`0 ≤ length`), not prose | this slice's synthesis |
| 6 | Subject hash · IR digest · §2.1a subject binding (subjectTreeMerkleRoot, subjectGitRef, EA legs, completeness record) | `buildSubjectBinding` (single-origin carrier mode) |
| 7 | Single verdict — VERIFIED only via canonicalLeanKernelCheck → bindReceipt → evaluate (non-empty axiom allowlist + `spForbid`) | C20 canonical path (existing) |

## 5. Terminal outcome (measurable, machine-checkable)

1. `bin/ax prove --project <nim-stew>` (AXIOM_STATE_DIR set) reaches the rem candidate **VERIFIED** and the certificate identity carries the `rem=` and `modelprofile=` segments.
2. Two consecutive runs produce **byte-identical** canonical projections (`sha256sum` equal).
3. `git -C <nim-stew> status --porcelain` is **empty** before and after every run.
4. The evidence lands in this PR and rides the repository's existing Axiom required-check path (verdict/admission-check) to merge.

Declarations, PR creation, or partial CI success do NOT count as done.

## 6. Acceptance criteria (machine-checkable)

| # | Criterion | Check |
|---|---|---|
| A1 | rem candidate VERIFIED with identity segments (§4 items 3, 4) present | run output + certificate |
| A2 | Determinism: two runs, identical sha256 of canonical projection | `sha256sum` comparison |
| A3 | Zero-footprint: subject tree porcelain-empty after all runs | `git -C <nim-stew> status --porcelain` |
| A4 | Negative (a): a shadow-modeled claim (term over a non-parameter) is rejected fail-closed; VERIFIED unreachable | run output |
| A5 | Negative (b): solver UNSAT alone cannot promote — the certificate stays `certZ3Candidate` (C20 single-verdict path) | certificate status |
| A6 | Negative (c): a stale certificate is rejected (fail-closed) | stale-cert gate output |
| A7 | `ax admission accept` exit 1 on unsigned input | PR #548 measured — cited, not re-measured |
| A8 | Overlay absence/failure blocks the run (fail-closed) | loader error path |

## 7. Explicit non-claims

- NOT a claim about `decodedLength`'s return value or about base32 encoding correctness.
- NOT a claim about `encodedLength` (`mod 5`, stew/base32.nim:71): its `when btype is …` result selection is outside the certified-subset extraction wire set (measured 2026-10-07: `EA_UNSUPPORTED: unsupported AST node (ckWhenStmt)`, `eaAgreed=false`) — the §2.1a seal is structurally unavailable; a claim over it would be unverifiable theater.
- NOT a claim about `base36.nim:83` / `base10.nim:153` / `base58.nim:90` remainders: loop-carried state the bounded subset does not model.
- NOT valid for negative `length` (truncated-mod sign divergence; `0 ≤ length` is discharged inside the proposition).
- NOT a claim that nim-stew was modified, annotated, or verified in-tree (Zero-Footprint).
- NOT a widening of the base36 sizing slice's claim.
