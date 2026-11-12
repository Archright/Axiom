# WP4-h-0 — ACT 2.2 Forensic Closure
## Why `hardEligible = 0`? Predicate-by-predicate audit of the 12 candidates

## Question

The ACT 2.2 inventory reported `obligation>0 = 13`, `elProofCandidate = 12`,
`postcondition>0 = 0`, `hardEligible = 0`. Is this collapse to 0 consistent
with the v4 hard-filter contract, or is it an inventory-implementation defect?
Exactly which hard predicate eliminated each of the 12 `elProofCandidate`
symbols?

## v4 hard-filter contract (authoritative)

Per the architect, the v4 contract has **exactly 6 hard predicates**:

```
unique(1) ∧ materialized ∧ obligationCount>0 ∧ elProofCandidate ∧
¬vtNonDecidable ∧ exact-target=1
```

`postconditionCount>0` is **NOT** a hard predicate. It is a ranking-only axis.

## Procedure

1. Enumerate all 12 `elProofCandidate` symbols from `inventory.json`.
2. For each, dump the full hard-predicate vector
   (definitionCount, materialized, irAvailable, obligationCount,
   postconditionCount, eligibility, overloadAmbiguity, proofTier).
3. Compare each against the 6-predicate v4 contract.
4. Fix the probe if it deviates, re-run 3×, confirm byte-identity.

## Result — the 12 candidates split into TWO distinct failure groups

### Group A — eliminated by OVERLOAD AMBIGUITY (exact-target=1 fails), 6 symbols

These are the `decode`/`encode` variants defined twice (defs=2) across the
current walk scope → `overloadAmbiguity=true` → v4 `exact-target=1` fails.

| Module::Function      | defs | mat | obl | elProofCandidate | overload | vtNonDec | postcond |
|-----------------------|------|-----|-----|------------------|----------|----------|----------|
| base32::decode        | 2    | ✓   | 1   | ✓                | **✗**    | ✓(Structural) | 0 |
| base32::encode        | 2    | ✓   | 1   | ✓                | **✗**    | ✓(Structural) | 0 |
| base36::decode        | 2    | ✓   | 2   | ✓                | **✗**    | ✓(Structural) | 0 |
| base58::decode        | 2    | ✓   | 2   | ✓                | **✗**    | ✓(Structural) | 0 |
| base58::encode        | 2    | ✓   | 1   | ✓                | **✗**    | ✓(Structural) | 0 |
| base64::decode        | 2    | ✓   | 1   | ✓                | **✗**    | ✓(Structural) | 0 |

These 6 are correct hard-exclusions under v4 (overload / exact-target>1).

### Group B — satisfies ALL 6 v4 hard predicates, 6 symbols

| Module::Function      | defs | mat | obl | elProofCandidate | overload | vtNonDec | postcond |
|-----------------------|------|-----|-----|------------------|----------|----------|----------|
| base32::decodedLength | 1    | ✓   | 1   | ✓                | ✓        | ✓(Native) | 0 |
| base32::encodedLength | 1    | ✓   | 1   | ✓                | ✓        | ✓(Native) | 0 |
| base36::decodedLength | 1    | ✓   | 1   | ✓                | ✓        | ✓(Native) | 0 |
| base36::encodedLength | 1    | ✓   | 1   | ✓                | ✓        | ✓(Native) | 0 |
| base58::encodedLength | 1    | ✓   | 1   | ✓                | ✓        | ✓(Native) | 0 |
| bitops2::getBitsBE    | 1    | ✓   | 1   | ✓                | ✓        | ✓(Structural) | 0 |

All 6 pass every v4 hard predicate. Under the correct v4 contract they ARE
hard-eligible.

## Conclusion: the `hardEligible = 0` was an inventory bug, not the subject

**Confirmed.** My ACT 2.2 probe added `postconditionCount > 0` as a 7th hard
gate, which is NOT in the v4 contract. Because `postconditionCount = 0` for
every one of the 458 symbols, this extra gate silently collapsed
`hardEligible` to 0.

The **postcondition count was indeed a hidden hard gate** in my implementation,
exactly the internal-inconsistency the architect suspected. `postcondition` is
rank-only in v4.

### Corrected funnel (v4 contract)

| Stage | Count |
|-------|-------|
| total | 458 |
| uniqueDef(1) | 367 |
| materialized | 430 |
| obligationCount>0 | 13 |
| elProofCandidate | 12 |
| ¬overload (exact-target=1) | 367 |
| ¬vtNonDecidable | 358 |
| **hardEligible (v4)** | **6** |

### Corrected v4 hard-eligible ranking (byte-identical across 3 runs)

| Rank | Module::Function | pc | obl | dep | tier | shape | body |
|------|------------------|----|-----|-----|------|-------|------|
| 1 | base36::decodedLength | 0 | 1 | 0 | vtSmtNative | direct | 3 |
| 2 | base32::encodedLength | 0 | 1 | 0 | vtSmtNative | direct | 5 |
| 3 | base36::encodedLength | 0 | 1 | 0 | vtSmtNative | direct | 5 |
| 4 | base58::encodedLength | 0 | 1 | 0 | vtSmtNative | direct | 5 |
| 5 | base32::decodedLength | 0 | 1 | 0 | vtSmtNative | direct | 9 |
| 6 | bitops2::getBitsBE | 0 | 1 | 1 | vtStructural | calls | 31 |

## Evidence

- Corrected runs: `runs_v4/run{1,2,3}/` — byte-identical
  (`inventory.json` sha256 `90003a2c…9f56`, `ranking.json` sha256 `e5de0f77…e3c`).
- Buggy ∅ run preserved (not deleted): `superseded_v4bug/inventory_v4bugged_empty.json`
  and `ranking_v4bugged_empty.json` (the ∅ that motivated the audit).
- Source of the 6 Group-B symbols read to confirm obligation character
  (`base36.nim:52-60`, `bitops2.nim:559-597`).

## Classification

`ConfigurationError` (experiment-side) — resolved. The earlier `Empty/Incomplete`
classification in `act2-wp22-result.md` is **superseded** by this correction.
The subject was never the cause of hardEligible=0; the probe's non-v4 hard gate
was.

## Interpretation / next step

Under the v4 contract the ACT 2.2 anchor pool is **6 symbols**, not 0. Per the
architect's §7 order, the next step is the **intrinsic-safety obligation
inventory** (WP4-h-1) which re-ranks these 6 by **symbolic vs tautological
obligation** — prioritizing real input-linked constraints (`y != 0`,
`0 <= i < n`) over constant-divisor identities (`277 != 0`). Preliminary read
(low-risk, honest): the `decodedLength`/`encodedLength` sextet are
constant-divisor (`C != 0`, weak/near-vacuous); `bitops2::getBitsBE` carries a
genuine symbolic bounds obligation (`a < b ∧ sliceLen ≤ resultBits ∧ b ≤
totalBits`, tied to `data.len` and `slice`) — the strongest measurement target.
That choice is finalized by the deterministic intrinsic ranking, not by hand.
