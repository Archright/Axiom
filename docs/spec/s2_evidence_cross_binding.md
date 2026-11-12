# S2 — CanonicalLeanEvidence Cross-Binding (Splice Resistance)

## Purpose

`CanonicalLeanEvidence` (CLE) is the single durable evidence object whose issuance is the
**only** place `Verified` is created on the Lean path (I1: Verified requires
`executeCanonicalVerification` → genuine kernel acceptance). This document records the
cross-binding invariants that prevent **splice / mix-and-match** attacks — combining two
genuine executions into a composite evidence that no single kernel acceptance produced.

The rule of authority: **KAA ↔ Lean source ↔ Lean proposition ↔ obligation** must be
cryptographically bound as one atomic evidence. `CanonicalLeanEvidence.exists` must imply
the whole chain, not merely that *a* KAA exists.

Enforcement: `src/verification/obligation/kernel_acceptance_authority.nim`
(`newCanonicalLeanEvidence`).

## The Cross-Binding Checks (active)

`newCanonicalLeanEvidence` performs two checks before constructing the evidence, in
addition to requiring an opaque `KernelAcceptanceAttestation` (KAA):

**Check 1 — KAA ↔ Lean source.**
```
if leanSourceHash != kaa.receipt.receiptArtifactIdentity: reject
```
The artifact the kernel actually accepted (recorded in the receipt) must equal the hash of
the Lean source being bound. This prevents attaching evidence to a source the kernel never
accepted.

**Check 2 — KAA ↔ theorem.**
```
if extractTheoremName(leanSource) != kaa.receipt.receiptTheoremIdentity: reject
```
The theorem name in the bound Lean source must equal the theorem identity recorded in the
receipt. This prevents binding a receipt to a different theorem than the one the kernel
checked.

For a normally-created KAA these always hold: `receiptArtifactIdentity == sha256Hex(leanSource)`
and `receiptTheoremIdentity == extractTheoremName(leanSource)` by construction.

## Why Check 3 and Check 4 are intentionally NOT applied

These two candidate checks were evaluated and **deliberately excluded** — they are dead or
erroneous on the real product path. This is a recorded decision, not an oversight.

**Check 3 — proposition ⊆ theorem body (REJECTED).**
The `proposition` field in the product pipeline is the **canonical IR serialization**
(e.g. `boGe(var(result), lit(1))`), while `leanSource` is **Lean source text**. The two are
different languages; a substring relationship between them cannot hold in general. Applying
Check 3 would make the genuine product path's `canonicalEvidence` return `err` → `none` and
break R8. The certificate already binds the proposition via `propositionHash` and the Lean
source via `leanSourceHash`; the content-level meaning of the proposition is guaranteed by
the obligation → IR lowering (I6 body/result binding), not by a cross-language substring test.

**Check 4 — obligationId ↔ function-name match (REJECTED).**
`obligationId` is a 64-hex content hash of the canonical obligation, not the function name.
A name-match check would never fire on well-formed obligations (obligation IDs are by
construction hashes), so it would be permanently-silent dead code — a theater risk (always
passes because it never actually fires). The obligation is instead bound to the evidence via
`obligationId`/`propositionHash` in the identity graph.

## What the active checks do and do not protect

Protects:
- **Splice A**: source from execution B + KAA from execution A → Check 1 fails
  (`leanSourceHash(B) != receiptArtifactIdentity(A)`).
- **Splice B**: source from execution A + KAA from execution B → Check 1 fails.
- **Foreign theorem**: a source whose theorem name differs from the receipt → Check 2 fails.

The checks are **cryptographic** (sha256 hash equality) and **name-identity** (theorem)
comparisons — both deterministic and safe to run on every issuance. They cannot be fooled by
whitespace or encoding noise because both sides derive from the same canonical strings.

## Verification evidence

`tests/unit/test_s1a_lean_golden.nim`:
- `positive` (source A + KAA A) → `isOk`
- `spliceA` (source B + KAA A) → `isErr`
- `spliceB` (source A + KAA B) → `isErr`

The A and B executions run the real Lean 4.33.0 kernel independently, so each KAA is
genuine. The splice cases reject only because the cross-binding checks fire, not because a
KAA is missing.
