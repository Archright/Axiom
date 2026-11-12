# ACT 2 — WP4-h-3 ProofIR: Typed Proof-Obligation Lowering — Report

Date: 2026-08-30.
AGENTS.md §14 reporting contract for the WP4-h-3 experiment
("로컬/외부 proof pipeline 내 canonical predicate → 문자열 → 재파싱 → SMT 우회 구조 폐기,
  typed semantic expression IR 도입").

---

## Question

Can the intrinsic safety obligation `okSafetyDiv(resultBits != 0)` — produced
for the external symbol `stew/bitops2.nim::getBitsBE` — be carried through the
Axiom pipeline as a **typed semantic IR expression** (`IRExpr`) instead of a
serialized string, and be lowered deterministically into an executable SMT
goal that actually reaches Z3?

The working hypothesis was that the empty-SMT "TheaterGuard" stop for this
class of obligation was caused by the obligation being transported as a string
whose re-parse into SMT failed, i.e. an integration/carrier defect.

## Context

- PROJECT_UNDER_TEST: nim-stew (immutable subject `nim-stew-clean-c75502c`).
- SUBJECT_SYMBOL: `stew/bitops2.nim:559 :: getBitsBE`
  `func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T`.
- AXIOM_REVISION: Axiom experimental variant, WP4-h-3 (typed ProofIR) applied
  on top of the working tree under test. Baseline Axiom = unmodified revision.
- AXIOM_CONFIGURATION: `nimble build` / `nim c -d:release -o:bin/ax src/cli/main.nim`; CLI `prove`.
- TOOLCHAIN_IDENTITY: Nim (hermetic layered build), Z3 (solver), Lean (kernel — not reached this WP).
- EXPERIMENT_ID: `act2-wp4h3-proofir` (dir `experiments/act2-wp4h3-proofir/`).
- Classification taxonomy per AGENTS.md §5.

## Scope

In scope (Area 1–5, done):
- Add `VerificationObligation.proposition: IRExpr` + single producer
  `makeVerificationObligation(...)` (positional args) guaranteeing
  `predicate = canonicalizePredicate(proposition)`.
- Migrate the canonical obligation generator + semantic target extractor to the
  producer, preserving `proposition` across all 7 candidate generation sites.
- New module `src/core/trusted/private/obligation_smt_lowering.nim`:
  `lowerObligationToSmt(proposition: IRExpr, context): SmtLoweringResult`.
- Route `ogrGenerated` obligations in `ir_pipeline_runner.nim` through the typed
  lowering to a real SMT script; keep TheaterGuard byte-identical.
- Invariant evidence I-1..I-5 + typed-lowering determinism + `axiomDecision` audit.

In scope (Area 6, done): P1–P7 verification + `getBitsBE` end-to-end replay.

Out of scope (deliberately NOT done): structural/signature ingress
generalization (`openArray`, `HSlice`, `typedesc`, generic signature),
postcondition synthesis, contract injection into the subject, generic-type
redesign, Lean/KAA/Trust rework, Track B debt. getBitsBE is used as-is.

## Procedure

1. Implement typographic carrier change (proposal: replace string transport with
   typed `IRExpr`, single `lowerToSmt` authority). Delivered as `obligation_ir`,
   `obligation_smt_lowering`, wiring in `ir_pipeline_runner`.
2. Unit verification: `test_obligation_ir`, `test_obligation_adapters`,
   `proof_state_machine_test`, `candidate_eligibility_test`,
   `test_ir_pipeline_theaterguard` — all green.
3. Audit: add `{.axiomDecision.}` to `smtTermFor`; rebuild engine — 2 pre-existing
   violations remain, 0 from our module; engine compiles exit 0.
4. Lowering probe (`probe/lowering_probe.nim`): lower `resultBits != 0` (BitVec64)
   twice; compare byte-identical SMT scripts; run Z3 on both.
5. End-to-end replay (this report's headline observation):
   `AXIOM_STATE_DIR=/tmp/axanchor/state bin/ax prove --project <subject> --target 'stew/bitops2.nim::getBitsBE' --limit 1`
   from repo root, output to `runs/prove_getBitsBE_run1.log`.

## Result

1. Typed lowering (probe): `resultBits ≠ 0` (BitVec64) lowers to a valid,
   non-empty SMT goal; `run1.smt2 == run2.smt2` byte-identical (DETERMINISM
   PASS); Z3 returns `sat` on both. `sat` is correct semantics — the goal is
   `(assert (not (not (= resultBits 0))))` = `resultBits == 0`, which is
   satisfiable, i.e. there exist inputs where `resultBits == 0`, so `resultBits ≠ 0`
   is a non-tautological precondition-class safety obstruction.

2. End-to-end replay for `getBitsBE`: **the pipeline never reaches Z3.**
   Admission/exact-target succeeded (`--target filter: 1 node(s) match`, `eligible=1`),
   but the Sieve-Gate hard-rejects the symbol at the **structural ingress** stage:
   ```
   getBitsBE: structural_ast (topology)
   ✗ getBitsBE — escalated: erGuardHardReject
     Context: Failed to parse source: Failed to parse Nim source
     ↳ StructuralAST: rejected (counterexample)
   ```
   Canonical trajectory (`state/logs/ax_prove_trajectory.jsonl`), every run:
   `layerTrace=[{StructuralAST, leFailedSat, stepCount:0}]`, `smtlib2Query:""`,
   `solverInvocationCount:0`, `obligationAttemptedCount:0`, status `pre_sieved`,
   tier `unknown`. Verified: 0/40, `verifiedRatio=0.0000`.
   Cross-validation reported `vacuous — no postconditions` (getBitsBE has no
   postcondition; it is an intrinsic-safety target).

## Evidence

- `canonical/area6_invariants.md` — I-1..I-5 (production projection holds;
  test-fixture caveat at `candidate_eligibility_test.nim:183` hardcoded
  `predicate:"x ≠ 0"`), id-immutability, type-completeness, TheaterGuard
  unchanged, mutation boundary (0 direct `src/` mutations of
  `.predicate=`/`.proposition=`/`.assumptions=`).
- `probe/lowering_probe.nim`, `probe/run1.smt2`, `probe/run2.smt2`,
  `probe/z3_output.txt`, `probe/wp4h3_lowered.smt2` — determinism + Z3 evidence.
- `runs/prove_getBitsBE_run1.log` — full replay log; `runs/README.md` — command,
  state, classification.
- Trajectory + z3 telemetry preserved in `/tmp/axanchor/state/logs/`.

## Classification

- Typed lowering capability: **established** (deterministic, non-empty SMT,
  reaches Z3) — measured by probe at the unit level.
- End-to-end `getBitsBE` prove: **Unsupported** (structural/signature ingress).
  The source→(structural)admission step fails closed on `openArray[byte]`,
  `HSlice`, `type[SomeUnsignedInt]` before any obligation reaches SMT. Not
  Verified; not Vacuous-at-proof; not SolverFailure; not ToolchainFailure;
  not InfrastructureFailure (tool ran, exit 0, canonical report produced).

## Interpretation

- The typed carrier (proposition-as-IRExpr) works: lowering is deterministic and
  produces sound SMT. The original string-reparse carrier hypothesis is
  supported at the lowering unit — an `IRExpr` goal reaches Z3 without the
  parse round-trip.
- However, for the designated anchor `getBitsBE`, the WP4-h-3 capability boundary
  sits **upstream of the lowered obligation**: the structural AST sieve cannot
  admit the symbol's signature, so the typed SMT path is never exercised on the
  end-to-end run. This is a pre-existing, deliberately-deferred **signature/
  structural ingress** capability gap, not a regression from this WP.
- Consequently, for `getBitsBE`: source → (structural) admission → [STOP].
  The stages Obligation/SMT/Z3/Lean/KAA/Trust are not reached.

## Non-Conclusions

- This WP did NOT verify getBitsBE, and did NOT produce a kernel-accepted
  external proof. `obligation→SMT` works at the lowering-unit level but is not
  observed on the end-to-end anchor.
- Z3 `sat` on the probe is not a proof and not a failure — it is the expected
  truth value of a satisfiable safety-precondition goal.
- The `Unsupported` replay result must not be re-read as "obligation synthesis
  fails": obligation synthesis and typed lowering both function; the gate that
  stops is signature ingress.
- No claim is made about Lean/KAA/Trust in this WP — they were never reached.

## Next Experiment

Smallest useful next step (WP4-h-3 successor): **signature/structural ingress
generalization** so that `openArray[byte]`, `HSlice`, and
`type[SomeUnsignedInt]` (generic signature) can be admitted past the Sieve-Gate
into the IR pipeline, at which point the typed `IRExpr → SMT` lowering produced
here can be re-run end-to-end for `getBitsBE` and the next boundary
(solver/Lean/KAA) measured. Keep the invariant evidence and the immutable
subject. Alternatively, select an anchor whose signature the current ingress
already admits, to observe the typed-lowering-to-Z3 boundary end-to-end sooner;
per scope discipline this must be an explicit, recorded re-scoping, not a
silent anchor switch mid-campaign.
