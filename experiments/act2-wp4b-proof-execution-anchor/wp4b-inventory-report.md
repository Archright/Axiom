# WP4-b Phase 1 — Full-Tree Candidate Inventory Report (corrected)

## Question

Can Axiom instrument a full-tree candidate inventory over nim-stew, computing a
per-symbol predicate vector and ranking candidates by proof tier, vacuity,
symbolic-divisor presence, and body-node count? What is the candidate landscape,
and does any symbol survive the shortlist funnel?

## Context

| Field | Value |
|---|---|
| `PROJECT_UNDER_TEST` | nim-stew (`<workspace>/nim-stew-clean-c75502c`) |
| `PROJECT_REVISION` | `nim-stew-clean-c75502c` (`c75502ceedb5ed2a37b7b5e4744fc71313682859`) |
| `AXIOM_REVISION` | Axiom from `.` (HEAD `089251924`) |
| `AXIOM_CONFIGURATION` | `-d:release --hints:off`, `axiomLayer "tools"`, per-probe `generateAxiomInit` |
| `TOOLCHAIN_ID` | Nim 2.2.10 via choosenim |
| `EXPERIMENT_ID` | `act2-wp4b-proof-execution-anchor` |
| `VERIFICATION_SCOPE` | Every `nkProcDef`/`nkFuncDef` in every `.nim` file under `stew/` (tests excluded) |
| `PROBE` | `experiments/act2-wp4b-proof-execution-anchor/wp4b_inventory.nim` |

> **Correction note.** The first run walked both `subjectRoot/stew` and `subjectRoot`,
> so `stew/` files were collected twice and every `definitionCount` was doubled →
> the shortlist collapsed to 0. This report reflects the **fixed** single-root walk.

## Scope

- Subject root: nim-stew-clean-c75502c, scanned under `stew/` only.
- Files scanned: **51** `.nim` files (under `stew/`; tests excluded).
- Unique symbols: **458** (deduplicated module::function).
- Parse failures: 0.
- Per-symbol vector: `module`, `function`, `definitionCount`, `irDigest`,
  `obligationCount`, `obligationKinds`, `vacuous`, `assessAdmissibilityDecision`,
  `inVerifiedFragmentV1`, `eligibility`, `proofTier`, `proofTierSource`,
  `materialized`, `mkExcluded`, `symbolicDivisor`, `bodyNodeCount`, `status`.

## Procedure

1. Compile probe:
   `nim c -d:release --hints:off -o:/tmp/wp4b_inventory_bin experiments/act2-wp4b-proof-execution-anchor/wp4b_inventory.nim`
2. Run probe: `/tmp/wp4b_inventory_bin <subjectRoot> /tmp/wp4b-inventory.json` — exit 0.
3. `bodyHasSymbolicDivisor` scans IR for `boDiv/boRem/boRemU` with a non-literal RHS.
4. Ranking: `vtSmtNative` < `vtStructural` < `vtNonDecidable`; non-vacuous first;
   `symbolicDivisor=true` first; fewer body nodes first.

## Result (canonical machine-observed)

```json
{
  "nimFileCount": 51,
  "uniqueSymbols": 458,
  "fileParseFailures": 0,
  "funnel": {
    "total": 458,
    "obligationGreaterThan0": 13,
    "eligibilityElProofCandidate": 12,
    "uniqueDefinitionCount1": 367,
    "materializedMoMaterialized": 358,
    "shortlistFinal": 6
  }
}
```

### 6-symbol shortlist

| module::function | tier | vacuous | symbolicDivisor | bodyNodes | admissibility | obligation |
|---|---|---|---|---|---|---|
| base36::decodedLength | vtSmtNative | no | no | 3 | ADMISSIBLE | okSafetyDiv (1) |
| base36::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE | okSafetyDiv (1) |
| base32::decodedLength | vtSmtNative | no | no | 9 | ADMISSIBLE | okSafetyDiv (1) |
| base32::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE | okSafetyDiv (1) |
| base58::encodedLength | vtSmtNative | no | no | 5 | ADMISSIBLE | okSafetyDiv (1) |
| bitops2::getBitsBE | vtStructural | no | **yes** | 31 | DEFER_TO_RUNTIME | okSafetyDiv (1) |

All six are single-definition, `elProofCandidate`, `inVerifiedFragmentV1`, generate
exactly one `okSafetyDiv` obligation, and are non-vacuous.

## Interpretation

1. **The shortlist is NOT empty** after the double-walk fix: 6 single-definition,
   non-vacuous, `elProofCandidate` candidates exist.
2. **IR materialization is high**: 358/458 (78%) symbols materialized IR; the 13
   obligation-bearing symbols all materialize.
3. **The only symbolic-divisor candidate** is `getBitsBE` (vtStructural,
   DEFER_TO_RUNTIME). It is the sole non-constant-divisor obligation candidate —
   the constant-denominator div in the encoded/decodedLength members is the known
   A6-tautology hazard (see `wp4b-result.md`).

## Classification

**Result type**: `Verified` (the corrected probe executed successfully and produced
complete, valid evidence — this is a measurement-instrument result, not a proof claim
about nim-stew).

## Non-Conclusions

- An empty/partial shortlist would not itself prove verifiability; the funnel is a
  measurement, not a proof.
- `proofTier`/eligibility/admissibility are Axiom's current classification model;
  they do not assert nim-stew's functions are (or are not) provable.
- The probe does **not** modify `src/` or `nim-stew/`.

## Next Experiment

See `wp4b-result.md`: apply the generic `axiom_engine.nim:719` slice guard, then
re-run the `getBitsBE` ladder; separately target `base36::encodedLength` A6 behavior
(the constant-denominator `synthesizeContracts` limitation).
