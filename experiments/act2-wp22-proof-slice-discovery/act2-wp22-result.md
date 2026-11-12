# ACT 2.2 — Proof Slice Discovery: Result Report

> **SUPERSEDED — see `wp4-h-0-forensic-closure.md` (authoritative).**
> This document reported `hardEligible = 0` because the probe incorrectly added
> `postconditionCount > 0` as a hard gate (NOT part of the v4 contract).
> Corrected v4 result: **hardEligible = 6**, with full predicate audit.
> This file is preserved as historical evidence of the buggy run only.

## Question

Can the ACT 2.2 protocol select exactly one Proof Anchor over
nim-stew@c75502c via a deterministic hard-filter + ranking, without modifying
the subject and without weakening Axiom's acceptance criteria?

## Context

- Subject revision: `c75502ceedb5ed2a37b7b5e4744fc71313682859` (nim-stew)
- Axiom revision: working tree `.`
  (probe only; no `src/` change, no subject change)
- Configuration: experiment probe `wp22_inventory.nim` (NOT canonical path)
- Toolchain: Nim 2.2.10
- Experiment identifier: `act2-wp22-proof-slice-discovery`

## Scope

Analyzed `subject/stew/**/*.nim` (51 files, 458 unique proc/func symbols).
Excluded: `tests/`, non-library files. Hard filter: unique def ∧ materialized ∧
obligationCount>0 ∧ postconditionCount>0 ∧ elProofCandidate ∧ no overload ∧
proofTier != vtNonDecidable. Ranking order per plan (non-vacuous, dependency
surface ASC, vtSmtNative, body complexity, tie-break `module::function`).

## Procedure

1. Extended WP4b probe with ACT 2.2 axes (postconditionCount, dependencyCount,
   overloadAmbiguity, vacuousSignal, proofExecutionShape).
2. Built: `nim c -d:release --hints:off` (EXIT 0).
3. Ran probe 3× to separate out dirs; verified byte-identity:
   - `inventory.json` sha256 `5881e693...2914` ×3, `cmp` run1==run2
   - `ranking.json` sha256 `1ce72cff...b3b4` ×3
4. Computed funnel + deterministic ranking.

## Result

- `inventory.json` present (458 symbols), `ranking.json` present (ordered list).
- **Hard-eligible set: 0 candidates** (see funnel in `selected-anchor.md`).
- The single hard-filter conjunct that eliminates the whole set:
  **`postconditionCount > 0`** — max postconditionCount across all 458 symbols
  is **0**; distribution `{0: 458}`.
- Full ordered hard-eligible ranking preserved in `ranking.json`
  (empty list — no cherry-picking, no suppressed candidates).

## Evidence

- `inventory.json`, `ranking.json` (byte-stable; sha256 above).
- `runs/run{1,2,3}/` — three independent probe outputs, identical.
- Grep of `stew/` confirms no Axiom `{.requires:}/{.ensures:}` postcondition
  spec in the subject source (only doc-comment/natural-language "requires").
- `wp22_inventory.nim` — probe source.

## Classification

`Empty` / `Incomplete`. The strict ACT 2.2 contract yields an empty
hard-eligible set; no anchor is selected. This is a **subject semantic
capability boundary** (unannotated external library carries no postconditions),
matching the pre-classified `postcondition 없음 → TheaterGuard` category from
ACT 2. It is NOT an Axiom defect and NOT probe malfunction (verified: 12
`elProofCandidate`, 13 obligation-bearing, 358 non-vtNonDecidable symbols all
still have `postconditionCount = 0`).

## Interpretation

This evidence establishes that **nim-stew@c75502c, as an unannotated external
functional library, produces zero postconditions in Axiom's IR for every
symbol**. Under a hard filter that requires `postconditionCount > 0`, the first
external proof cannot admit any anchor without either (a) relaxing that
condition, (b) synthesizing postconditions in a separate subject variant, or
(c) choosing an annotated subject. The deterministic ranking machinery works
and is reproducible (byte-identical across runs); it simply has an empty input
set because of the subject's missing specifications.

## Non-Conclusions

- This does NOT establish that Axiom "cannot prove nim-stew." It establishes
  only that the strict ACT 2.2 anchor-selection contract is unsatisfiable on
  this unannotated subject.
- The relaxed-variant top candidates (e.g. `base36::decodedLength`) are
  predictions, not selected anchors; they carry documented constant-divisor and
  typedesc-semantics vacuity/capability risks.
- No symbol was verified; no obligation reached Z3/Lean; nothing beyond
  inventory/ranking was produced.

## Next Experiment

The architect must resolve the decision fork in `selected-anchor.md`:
(A) relax `postconditionCount>0` for this subject and attempt
`base36::decodedLength` as the first kernel proof (accepting the documented
vacuity/capability risk), (B) create a postcondition-injected subject variant
(separate experimental variant per AGENTS.md §13, baseline preserved), or
(C) switch to an annotated external subject. That decision is the input to
ACT 2.3 — First External Kernel Proof.
