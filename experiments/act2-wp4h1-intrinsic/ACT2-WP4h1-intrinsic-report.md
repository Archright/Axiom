# ACT 2 / WP4-h-1 — Intrinsic Safety Obligation Inventory & Proof Anchor #1

## Question

Can Axiom, without any injected specification, automatically extract a
*non-tautological intrinsic safety obligation* from an ordinary legacy Nim
module (nim-stew), deterministically rank candidate anchors, and select the
most capability-revealing single proof target?

Sub-questions:

- Which of the 6 v4-eligible candidates carry a *symbolic* (input-linked)
  safety obligation rather than a constant-folded / tautological one?
- What is the deterministic Anchor #1 under the intrinsic-safety ranking?
- What IR behavior (constant folding, unsupported ops) shapes that choice?

---

## Context

- Project under test: `nim-stew` (`stew/`, Nim standard-ecosystem utility library)
- Subject revision: `nim-stew-clean-c75502c` (immutable, `nim-stew-clean-c75502c`)
- Axiom revision: local repo `.../Axiom` (Nim), workspace `<workspace>`
- Toolchain: Nim 2.2.10 (`-d:release`)
- Axiom configuration: default (no contract injection, no annotation added)
- Verification scope: intrinsic safety operations only — division/modulo,
  indexing, slice/range, shift, overflow-prone arithmetic. Postcondition-derived
  contracts are deliberately NOT part of the baseline path (comparison variant only).
- Experiment id: `act2-wp4h1-intrinsic-safety`
- Predecessor: `act2-wp22-proof-slice-discovery` (v4 hard-eligibility = 6 clarified;
  `postconditionCount>0` was a probe bug, not a v4 hard gate)

---

## Scope

Analyzed: the 6 v4-eligible `elProofCandidate` symbols from the fixed v4 run:

- `stew/base32.nim::decodedLength`
- `stew/base32.nim::encodedLength`
- `stew/base36.nim::decodedLength`
- `stew/base36.nim::encodedLength`
- `stew/base58.nim::encodedLength`
- `stew/bitops2.nim::getBitsBE`

Selected: the single deterministic Anchor #1 via intrinsic ranking.

Excluded: Track B (evidence / historical debt), contract injection as a baseline
path, repository-wide coverage, generic/overload/multi-module generalization.

---

## Procedure

1. Forked the wp22 inventory probe into `wp4h1_intrinsic_inventory.nim`
   (measurement only — no Axiom semantic changes).
2. For each intrinsic operation discovered in a candidate body, the probe records:
   `source expression`, `inferred obligation`, `obligation kind`, `operands`,
   `symbolic?` (input-linked non-constant), `tautological?`, `IR representation`,
   `SMT support`.
3. Classification change (essential vs non-essential):
   - **essential** safety ops: division/modulo denominator, index/slice/range bounds.
   - **non-essential** safety ops: overflow arithmetic, casts.
   - The `symbolic` flag for *ranking* is driven by **essential** ops only,
     preventing an overflow-only false "symbolic" from inflating a candidate.
4. Ranking (deterministic, no manual cherry-picking):
   1. has symbolic essential obligation (first)
   2. reject unsupported-op anchors (last)
   3. dependency surface ASC
   4. vtSmtNative over vtStructural
   5. body node count ASC
   6. module::function lexicographic
5. Ran probe 3x on the immutable subject; verified byte-identical canonical
   artifacts across `run1/run2/run3`.

Commands:

```sh
nim c -d:release --hints:off -o:/tmp/wp4h1_intrinsic_bin \
  experiments/act2-wp4h1-intrinsic/wp4h1_intrinsic_inventory.nim
/tmp/wp4h1_intrinsic_bin <workspace>/nim-stew-clean-c75502c <outdir>
```

---

## Result

Canonical, machine-generated (byte-identical across 3 runs):

- hard-eligible count: **6**
- deterministic Anchor #1: **`stew/bitops2.nim::getBitsBE`**
  - eligibility `elProofCandidate`, `materialized: moMaterialized`
  - dependency surface: **1**, body node count 31
  - intrinsic op: division `(a boDiv resultBits)`
  - **inferred obligation: `denom != 0` where `denom = resultBits` (symbolic, live variable)**
  - other ops: overflow (boMul/boAdd/boSub) — non-essential, `requires-overflow-model`
  - `hasTautologicalOnly: false`, `hasSymbolicIntrinsicObligation: true`, `vacuousSignal: false`

Full ranking (symbolic-first):

| rank | anchor | essential-symbolic | intrinsic ops | dep | tier |
|------|--------|--------------------|---------------|-----|------|
| 1 | `bitops2::getBitsBE` | **yes** `denom=resultBits` | division(sym) + overflow(non-ess) | 1 | vtStructural |
| 2 | `base36::decodedLength` | no (denom=277 literal) | division | 0 | vtSmtNative |
| 3 | `base32::encodedLength` | no (denom=5 literal) | division | 0 | vtSmtNative |
| 4 | `base36::encodedLength` | no (denom=179 literal) | div+overflow | 0 | vtSmtNative |
| 5 | `base58::encodedLength` | no (denom=100 literal) | div+overflow | 0 | vtSmtNative |
| 6 | `base32::decodedLength` | no (denom=8 literal) | rem+overflow+cast | 0 | vtSmtNative |

---

## Evidence

- `canonical/inventory.json` — sha256 `258f979bcd0622a0e38f55133bbc14cc3f41fa034130f04500357ec7384ebc98`
- `canonical/intrinsic-ranking.json` — sha256 `cc053c06aeefdc464e1f9b819b9da45746016902f6a165c000417c400c0037f0`
- `canonical/anchor.json` — sha256 `191e6588d8389d857b60ad322dc09c3114276d0246ffbb4a1e959f848cbb66dd`
- `runs_v4/run{1,2,3}/…` — byte-identical reruns
- `src/wp4h1_intrinsic_inventory.nim` — probe source (measurement, not Axiom mutation)

---

## Classification

`Incomplete` / measurement success: the inventory, non-tautological
discrimination, and deterministic ranking all succeeded and are reproducible.
A **symbolic intrinsic safety obligation** was identified
(`denom = resultBits ≠ 0` in `getBitsBE`, where `resultBits` is a live
function variable). End-to-end kernel proof was **not** attempted in this stage;
that is the next stage (ACT 2.3 / Anchor #1 A1–A10).

---

## Interpretation

Two real, capability-relevant observations emerged (not hidden):

1. **IR constant folding decouples length functions from their inputs.**
   `base36::encodedLength` source is `(length*277) div 179 + 1`, but its IR
   body folds to `((0 boDiv 179) boAdd 1)` — `length*277` collapsed to `0`.
   Similarly `base32::decodedLength` folds `length*5` to `0`, and
   `getBitsBE`'s `totalBits = data.len*8` folds `(0 boMul 8)`. As a result
   several candidates carry *tautological* or *input-decoupled* obligations,
   which is why their intrinsic safety guarantees do not connect to real inputs.
   This is a **semantic-capability boundary** (input-linked symbolic length
   arithmetic is not preserved through IR materialization), not an Axiom bug
   to be hidden.

2. **Overflow ops are non-essential for anchor selection.** Before the fix, the
   scanner treated any non-literal node as symbolic, which mislabeled
   `base36::encodedLength`'s folded `((0 boDiv 179) boAdd 1)` as "symbolic" and
   wrongly promoted it to rank 1. Scoping the ranking's symbolic axis to
   **essential** safety obligations (division denominator / index bounds)
   removed the false positive. This is a measurement-correctness fix within the
   probe, not a weakening of Axiom.

The choice of `getBitsBE` as Anchor #1 is deliberate: it carries the only
symbolic essential obligation among the eligible set, so it is the most
capability-revealing target even though its proof tier is `vtStructural`.

---

## Non-Conclusions

- The inventory does **not** claim project-wide or module-wide safety.
- A *symbolic obligation existence* does **not** prove the obligation holds; no
  kernel acceptance exists yet.
- `hasSymbolicIntrinsicObligation: true` is a candidate property, not a verified theorem.
- Nothing here establishes that `getBitsBE`'s division obligation is provable
  under the SMT/Lean/KAA path; overflow ops report `requires-overflow-model`,
  which may be unsupported.

---

## Next Experiment

ACT 2.3 / Anchor #1: drive `stew/bitops2.nim::getBitsBE` through
Discovery → Admission → Obligation → Planning → UAP → Z3 → Lean → KAA →
TrustCommit exactly once. Record the per-stage predicate (exact-1 match,
obligation ≥1, planned node ≥1, UAP request, Z3 valid result, Lean kernel
acceptance, KAA acceptance, deterministic canonical result, trustCommit
verification). First failure stage is the next WP boundary. No anchor switching.

Report ready for the external-proof / context7 comparison as a **capability
boundary** baseline, not a success claim.
