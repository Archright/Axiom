# WP4-h-3 Area 6 — Invariant Evidence (P1~P7)

Date: 2026-08-30. Repo: `Axiom` (experimental variant). Subject (immutable): `nim-stew-clean-c75502c`.

Scope: WP4-h-3 typed ProofIR. This file records the invariant evidence for the
accretion checks I-1..I-5, the typed-lowering determinism check, and the
`axiomDecision` audit cleanup. Evidence is observed facts from this workspace;
where a check is a grep/code audit, the exact command/result is noted.

---

## I-1 — `predicate` = projection of `proposition`

Definition: for every obligation produced by the canonical producer
`makeVerificationObligation`, `predicate == canonicalizePredicate(proposition)`.

Observed:
- `src/` production path: exactly **one** `VerificationObligation(` literal exists,
  inside the producer itself (`src/verification/obligation/obligation_ir.nim:50`).
  There, `predicate = canonicalizePredicate(proposition)` is assigned (line 49),
  so the producer guarantees the projection.
- `src/verification/obligation/canonical_obligation_generator.nim:248` constructs
  through the producer (`makeVerificationObligation(cand.kind, cand.subject,
  canonAssumptions, cand.derivationRule, provenance, cand.proposition)`), never via
  a direct literal. Projection holds by construction.
- `src/` has **no** other obligation-literal construction and **no** direct
  `.predicate=` / `.proposition=` mutation outside the producer (see I-5).

Test fixtures (by design, acceptable):
- `tests/unit/test_obligation_ir.nim:79` sets `predicate: ""`, `proposition: nil`
  (a hand-built enum-variant fixture; predicate chosen by the test, not projected).
- `tests/unit/test_obligation_ir.nim:208,223,229` set `predicate` by hand with
  `proposition: nil` (producer is not used; predicate is controlled test data).
- `tests/unit/candidate_eligibility_test.nim:183` (**caveat, disclosed**): sets
  `predicate: "x ≠ 0"` with a NON-nil proposition built from
  `irUnaryOp(uoNot, irBinOp(boEq, irVar("x", irTypeBitVec64()), ...))`. The
  hardcoded predicate string is a test-channel fixture feeding downstream field
  reads (`inVerifiedFragmentV1`); it is NOT produced by `makeVerificationObligation`,
  so the I-1 projection invariant of the producer is untouched. It is recorded here
  so this is a known, disclosed test data channel rather than a silent producer
  bypass. No production path depends on this fixture's predicate.
- `tests/unit/proof_state_machine_test.nim:38` and
  `tests/unit/test_obligation_adapters.nim:40` construct literals likewise with
  hand-set predicates for state-machine/adapter tests (fixtures, not producer).

Verdict: **I-1 holds on the production producer path.** Test-only fixtures set
predicate by hand as controlled data (expected; disclosed caveat at
`candidate_eligibility_test.nim:183`).

---

## I-2 — id immutability

Definition: the producer computes
`id = computeObligationId(subject, kind, assumptions, canonicalizePredicate(proposition), derivationRule)`
and stores it, so a recompute from the same fields reproduces the same id.

Observed:
- `src/verification/obligation/obligation_ir.nim:49-51`:
  `let pred = canonicalizePredicate(proposition)` then
  `VerificationObligation(id: computeObligationId(subject, kind, assumptions, pred, derivationRule), ...)`.
- Recompute path exists: `obligation_ir.nim:118-123` `computeId(obl)` recomputes
  from `obl.predicate` (which the producer always set to the projection).
- Unit coverage: `tests/unit/test_obligation_ir.nim` "VerificationObligation
  computeId is deterministic" and "computeId differs for different subjects" — both
  PASS (see test run: 23 passed / 0 failed).

Verdict: **I-2 holds** (identity derived deterministically from the typed
proposition's canonical projection; recompute reproducible).

---

## I-3 — lowering input is type-complete; slice is exactly Var/Lit/Eq/Not

Observed (code audit of `src/core/trusted/private/obligation_smt_lowering.nim`):
- `lowerObligationToSmt` (line 302) calls `recomputeTyp(proposition)` then
  `elaborateSorts(proposition)` before lowering (lines 321-322). Both are nil-safe
  preprocessing: `recomputeTyp*` defined at `src/core/trusted/axiom_ir.nim:457`,
  `elaborateSorts*` at `src/core/trusted/ir_elaborate_sorts.nim:22`; both modules
  are imported by the lowering module.
- Supported slice (function `smtTermFor`, line 265): `irLit` → bitvector hex
  literal; `irVar` → variable name; `boEq` → `(= a b)`; `uoNot` → `(not a)`.
  All other constructs hit `return ""` (fail-closed). `lowerObligationToSmt`
  converts an empty term into `empty=true, lostInformation=true, smtScript=""`,
  and a nil proposition into the same failure (line 313-318).

Verdict: **I-3 holds** — input is made type-complete before lowering, and
unsupported constructs fail closed (never silent-drop).

---

## I-4 — TheaterGuard unchanged (fail-closed preserved)

Observed: `git diff src/verification/batch_uap/ir_pipeline_runner.nim` shows the
only changes are (a) two added imports
(`core/trusted/private/obligation_smt_lowering`, `core/proof/proof_budget`) and
(b) a typed-lowering override block inserted between the `irToSmtScript` call
(line 931) and the TheaterGuard block. The TheaterGuard block itself
(`if smtScript.len == 0 and ogr.kind == ogrGenerated:` →
`return IrPipelineResult(..., rkObligationIllFormed, ...,
theaterDetectedVerdict(generatedObligationCount))`, current lines 957-978) is
byte-identical to baseline. Verified directly by diff of the guard region.
- Routing semantics: for `ogrGenerated`, if the first obligation's typed
  proposition lowers to a non-empty script (`not lowered.empty`), `smtScript` is
  overridden; otherwise the classic adapter output is kept, so an empty script
  still reaches the guard and fails closed.

Verdict: **I-4 holds** — TheaterGuard code unchanged; still the fail-closed
backstop for genuinely non-lowerable obligations.

---

## I-5 — mutation boundary

Definition: no production code mutates an obligation's derived fields
(`.predicate=` / `.proposition=` / `.assumptions=`) directly, bypassing the producer.

Observed: `grep -rn "\.predicate\s*=\|\.proposition\s*=\|\.assumptions\s*=" src/`
returns a single match, `src/verification/ecosystem_linkage.nim:165`, which is a
comparison (`newInv.predicate == oldInv.predicate`, `==`), NOT a mutation (`=`).
A direct-assignment grep (mutation operator `=`) against `src/` yields **0** sites.
(`.proposition=` as a direct assignment appears nowhere in src/ outside the
producer's object literal, which is the intended construction site.)

Verdict: **I-5 holds** — 0 direct mutations of derived obligation fields in src/.

---

## Determinism of `lowerObligationToSmt`

Observed (probe `experiments/act2-wp4h3-proofir/probe/lowering_probe.nim`,
rebuilt + rerun 2026-08-30): target expression `¬(resultBits == 0)` with
`resultBits : BitVec64`; `lowerObligationToSmt` ran twice.
- Free-var declare-fun order: canonical sorted (`resultBits` only here).
- run1.smt2 vs run2.smt2: `diff` → **IDENTICAL** (probe reports
  "DETERMINISM CHECK: PASS — byte-identical scripts across two runs").
- Script bytes:
  ```
  (set-logic QF_BV)
  (set-option :rlimit 30000000)
  (declare-fun resultBits () (_ BitVec 64))
  (assert (not (not (= resultBits #x0000000000000000))))
  (check-sat)
  ```
- Z3 (`<user-home>/.local/bin/z3`): both runs returned **sat**.

Interpretation of `sat`: the emitted assertion is `(not <term>)` where
`<term> = resultBits ≠ 0`, i.e. the solver checks satisfiability of
`resultBits == 0`, which is satisfiable (resultBits := 0). This is the CORRECT,
honest semantic result for this probe: the proposition `resultBits ≠ 0` is a
divisor-safety obligation, not a tautology, so its negation is satisfiable.
It demonstrates the typed obligation now lowers to an executable SMT goal that
reaches Z3 with a real verdict — the objective of WP4-h-3 — rather than dying in
the empty-script TheaterGuard.

Verdict: **determinism holds** (byte-identical, canonical order).

---

## `axiomDecision` audit cleanup

- Before: `[decision-binding]` reported 3 violations, including
  `smtTermFor(src/core/trusted/private/obligation_smt_lowering.nim)` — a function
  introduced by this WP.
- Fix: `smtTermFor` annotated `{.axiomDecision.}` (matching the repo's 26 plain
  usages); the module gained `import core/trusted/axiom_pragmas` (the standard
  import that provides the `axiomDecision` template, cf.
  `loop_transition_lowering.nim`, `contract_conformance.nim`). Rebuilding the
  engine (`nim c src/engine.nim`) now reports **2 violation(s)**, both pre-existing
  (`canonicalizeEnvValue` in `identity.nim:52`,
  `loadCASEntryByKey` in `canonical_cache.nim:149`) — **not** ours. Our new module
  contributes **zero** audit violations.

Verdict: **cleanup complete** for the WP-introduced function.

---

## Classification summary

- I-1 production projection: holds (test-fixture caveat disclosed).
- I-2 id immutability: holds.
- I-3 type-complete, fail-closed lowering: holds.
- I-4 TheaterGuard unchanged: holds.
- I-5 mutation boundary: holds (0 sites).
- Determinism: holds (byte-identical).
- Audit: our module clean; 2 pre-existing violations remain untouched.

## Non-conclusions
This file does NOT claim a `Verified` result. The Z3 `sat` on the lowered
`resultBits ≠ 0` probe is a capability measurement (obligation → executable SMT →
solver verdict), not a proof. Whether the full `getBitsBE` external replay reaches
Z3/Lean/KAA is recorded separately under `runs/`.
