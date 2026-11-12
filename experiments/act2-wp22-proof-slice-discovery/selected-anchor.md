# ACT 2.2 — Proof Slice Discovery: Anchor Selection

> **SUPERSEDED — see `wp4-h-0-forensic-closure.md` (authoritative).**
> This file reported an empty hard-eligible set caused by a probe bug that
> added `postconditionCount>0` as a non-v4 hard gate. Under the correct v4
> contract the hard-eligible set is **6 symbols** (see the forensic closure).
> The "would-be anchor" table below remains a valid relaxed ranking, but the
> strict-v4 anchor is finalized by the intrinsic-safety ranking, not by hand.
> This file is preserved as historical evidence of the buggy run only.

## Result: STRICT closure = EMPTY (no Proof Anchor selectable)

Under the ACT 2.2 hard-filter contract, the hard-eligible candidate set is
**empty (0 candidates)**. Therefore **no Proof Anchor is selected** by the
strict protocol.

This is the honest, evidence-backed outcome. It is **not** treated as a
"pass"; the boundary it exposes is the actionable deliverable.

---

## Context

- `PROJECT_UNDER_TEST`: nim-stew
- `PROJECT_REVISION`: `c75502ceedb5ed2a37b7b5e4744fc71313682859`
  (clean worktree: `nim-stew-clean-c75502c`)
- `AXIOM_REVISION`: working tree at
  `.` (uncommitted experiment probe)
- `AXIOM_CONFIGURATION`: experiment probe only — NOT a canonical path
- `TOOLCHAIN_IDENTITY`: Nim 2.2.10 (choosenim nim-2.2.10)
- `EXPERIMENT_ID`: `act2-wp22-proof-slice-discovery`
- `PROBE`: `experiments/act2-wp22-proof-slice-discovery/wp22_inventory.nim`
- `PROBE_SCOPE`: `subject/stew/**/*.nim` (library scope only, 51 files,
  458 unique symbols) — tests/ and non-library files excluded

---

## Procedure

1. Extend the WP4b inventory probe with the ACT 2.2 axes:
   `postconditionCount` (= `irFuncDef.postConditions.len`),
   `dependencyCount` (= distinct `irCall` callee names in the IR body),
   `overloadAmbiguity`, `vacuousSignal`, `proofExecutionShape`.
2. Compile: `nim c -d:release --hints:off -o:/tmp/wp22_inventory_bin ...`
   (EXIT 0).
3. Run 3× to separate output dirs; confirm byte-identity:
   - `inventory.json` sha256 = `5881e693...2914` in all 3 runs
   - `ranking.json`   sha256 = `1ce72cff...b3b4` in all 3 runs
   - `cmp` confirmed run1 == run2. **Deterministic.**
4. Apply the ACT 2.2 HARD filter and deterministic ranking (per plan).

---

## Hard-Filter Funnel (strict)

| Stage                     | Count |
|---------------------------|-------|
| total unique symbols      | 458   |
| unique definition (==1)   | 367   |
| IR materialized (moMaterialized) | 430   |
| obligationCount > 0       | 13    |
| **postconditionCount > 0** | **0** |
| elProofCandidate          | 12    |
| no overload ambiguity     | 367   |
| proofTier != vtNonDecidable | 358 |
| **hardEligible (ALL)**    | **0** |

The failing hard-filter conjunct that eliminates the entire set is
`postconditionCount > 0`.

---

## Root Cause: no postconditions anywhere in the subject

- `postconditionCount` is **0 for all 458 symbols** (max = 0, distribution
  `{0: 458}`).
- Grep of `stew/` for `axiom|ensures|requires|postCond|{.axiom` returns only
  natural-language doc comments and Nim's `requiresInit`; **no Axiom
  `{.requires:}`/`{.ensures:}` postcondition spec exists** in the subject.
- Consequently Axiom's IR materializer produces `postConditions = []` for
  every external symbol. The 12 `elProofCandidate` obligation-bearing
  symbols (base32/base36/base58/base64 encode/decode,
  decodedLength/encodedLength, bitops2::getBitsBE) all have
  `postconditionCount = 0`.

This matches the pre-classified boundary from ACT 2 (postcondition 없음 →
TheaterGuard). It is a **subject semantic-capability boundary**, not an Axiom
bug and not a probe artifact.

---

## Would-be Anchor (RELAXED VARIANT − prediction only)

The following is **explicitly a variant prediction, not the selected anchor**.
If the architect relaxes the hard filter `postconditionCount > 0` (globally
unsatisfiable on this unannotated external subject), the deterministic ranking
(first tie-breaks are non-vacuous, then dependency surface ASC) would yield:

| Rank | Module::Function | obl | pc | dep | tier | shape | vac | body |
|------|------------------|-----|----|-----|------|-------|-----|------|
| 1 | `stew/base36.nim::decodedLength` | 1 | 0 | 0 | vtSmtNative | direct | F | 3 |
| 2 | `stew/base32.nim::encodedLength` | 1 | 0 | 0 | vtSmtNative | direct | F | 5 |
| 3 | `stew/base36.nim::encodedLength` | 1 | 0 | 0 | vtSmtNative | direct | F | 5 |
| 4 | `stew/base58.nim::encodedLength` | 1 | 0 | 0 | vtSmtNative | direct | F | 5 |
| 5 | `stew/base32.nim::decodedLength` | 1 | 0 | 0 | vtSmtNative | direct | F | 9 |
| 6 | `stew/bitops2.nim::getBitsBE` | 1 | 0 | 1 | vtStructural | calls | F | 31 |

### Candidate-1 detail: `stew/base36.nim::decodedLength`
```nim
func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
```

### Prediction (before running any proof) for the would-be anchor

| Stage   | Predicted outcome       | Risk / note |
|---------|-------------------------|-------------|
| Discovery | 1 match                    | `::` target, exact-1 |
| Admission | admitted (relaxed variant)| vacuousSignal F |
| Obligation | 1 real obligation        | already observed obl=1 |
| Planning | ≥1 planned node           | direct shape, 3 nodes |
| UAP     | request emitted           | vtSmtNative |
| Z3      | **HIGH vacuity/tautology risk** | constant divisor `277` → synthesized `divisor != 0` precondition; SMT division semantics may be rejected as tautology or unsupported |
| Lean    | **capability risk**       | `typedesc` param may be generic-semantics gap (lost in IR) |
| KAA / canonical / trust | blocked if Z3 or Lean fails | fail-closed |

The trace confirms the handoff's earlier warning exactly: even the "simplest"
candidate carries a constant-divisor tautology risk (`decodedLength = (len*179) div 277`)
plus a `typedesc` parameter that may hit the generic-semantics capability gap.

---

## Classification

`Empty` / `Incomplete` — hard-eligible candidate set is empty under the strict
ACT 2.2 contract because `postconditionCount > 0` is unsatisfiable on this
subject (0 / 458 symbols carry any Axiom postcondition annotation).

## Decision fork (architect's call — not auto-decided)

The empty-set boundary forces an explicit choice before ACT 2.3 can proceed:

1. **(A) Relax the postcondition hard filter** for this subject (treat the
   function body as its implicit contract), select
   `stew/base36.nim::decodedLength`, and attempt the first kernel proof —
   accepting the documented constant-divisor + typedesc vacuity/capability risk.
2. **(B) Require a synthesized/spec-added variant** of nim-stew (inject
   `{.ensures:}` postconditions) → this is a **separate experimental variant**
   per AGENTS.md §13 (baseline + patch + reason recorded); the baseline subject
   stays untouched.
3. **(C) Move to a different subject** that already carries Axiom specs
   (external annotated project), keeping the strict contract intact.

The strict ACT 2.2 result (option selection deferred) is preserved unchanged;
no weakening has been applied to manufacture an anchor.
