# Certificate Divergence Findings — Phase 0 (observed facts, no version verdict)

> Scope: Phase 0 of the NO-GO resolution. Records **measured** divergence between a
> committed tracked certificate and a fresh regeneration at the current HEAD.
> This is a findings/observation document, NOT a decision document — no canonical
> toolchain verdict is asserted here.
>
> HEAD: `f470422cf0b238c095cbec7762091ac835a9ed49` (branch `main`, worktree clean).

## 1. Focal artifact

- Committed: `src/verification/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json`
- Fresh (regenerated at current HEAD): `build/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json`

> **Superseded (2026-10-19):** the focal artifact was regenerated when
> `normalizeMaxWorkers` moved to the certified early-return wire shape; the
> live projection is `e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200`. The finding above is preserved as recorded.

## 2. Field-level diff (measured)

| field | committed | fresh | equal? |
|---|---|---|---|
| `canonicalKaa.observedAxiomSet` | `[]` | `["propext","Quot.sound"]` | NO |
| `identityDigest` | `391a550f…` | `3f7e2ce4…` | NO |
| `evidenceId` | `e64af282…` | `bf54ffd3…` | NO |
| `kaaDigest` | `d29756a0…` | *(recomputed)* | NO |
| `toolchainFingerprint` | `cc949784…` | `cc949784…` | **YES (identical)** |
| `executionContractDigest` | `5b960f87…` | `5b960f87…` | **YES (identical)** |
| `canonicalKaa.executionIdentity` | `5b960f87…` | `5b960f87…` | **YES (identical)** |

## 3. Key measured facts

1. The committed and fresh certs carry the **same `toolchainFingerprint`
   (`cc949784…`)** — i.e. the same declared execution label
   (`nim-2.2.10|lean-4.33.0|lake env lean|<timeout>`).
   **Resolution note (2026-10-06)**: this observation is historical — it
   describes certificates issued under the retired hardcoded label. The
   current fingerprint composition is fully measured
   (`computeBundleDigest`, lean_kernel_boundary.nim; normative in
   `docs/spec/obligation_semantics.md` §2.1a) and labels can no longer be
   produced, so this drift class cannot recur for new certificates.
2. Despite the identical toolchain label, `observedAxiomSet` differs (`[]` vs
   `[propext, Quot.sound]`), which drives `kaaDigest → evidenceId → identityDigest`.
3. Current canonical invocation is `lake env lean --threads=1` 
   (`lean_kernel_boundary.nim:170`). Measured resolution:
   - `lake env lean` → **Lean 4.33.0** (commit `d8b18978…`)
   - `findExe("lake")` → `~/.elan/bin/lake` → **4.33.0**
   - bare `lean` (default PATH shim) → **4.29.0** (commit `98dc76e3…`)
   - Axiom's canonical path uses `lake env lean`/`findExe("lake")`, i.e. **4.33.0**,
     NOT the bare `lean` 4.29 shim.
4. External docs (Lean 4 official): `propext` and `Quot.sound` are kernel built-in
   axioms that appear in ordinary proofs using quotients/propositional
   extensionality. A genuinely-executed kernel check of such a proof is expected to
   observe them.

## 4. Divergence interpretation (hypotheses, not verdict)

The identical toolchain label on both certs means the `[]` vs `[propext, Quot.sound]`
difference at this HEAD is **not explained by a toolchain-label drift**. The candidate
explanations, to be settled by source-level diagnosis:

- **(a) Evidence/hydration gap**: the committed cert was persisted with an empty
  `observedAxiomSet` because the axiom capture was not populated at persist time
  (`cert_writer` writes `axiomsUsed` only when evidence is present). This would be a
  provenance hole, not a toolchain difference.
- **(b) Old-toolchain artifact**: the committed cert was generated under a genuinely
  different execution whose `#print axioms` produced no output, but still received the
  same `4.33.0` label string — i.e. the label did not reflect the real binary
  (the "notation 제거" problem targeted by Phase 1).
- **(c) Canonical-representation gap**: even for identical kernel output, the stored
  `observedAxiomSet` ordering/canonicalization differs (`kaaIdentity` and `kaaDigest`
  are order-sensitive; the JSON serializer preserves array order).

All three converge on the same product requirement: the toolchain/execution contract
must be bound to the **real resolved binary content**, the axiom observation must be
**canonically serialized**, and the certificate's provenance must be **complete and
genuinely evidence-bearing**. A `certLeanVerified` cert with an empty observed axiom
set is not trustworthy as current product truth regardless of which hypothesis holds.

## 5. What this does NOT assert

- This document does NOT assert a canonical toolchain version verdict (4.33 vs 4.29).
- This document does NOT assert whether any cert is "stale" — that is Phase 5
  lineage classification.
- Observed measurement commands and hashes are reproduced in the Phase 0 audit trail.
