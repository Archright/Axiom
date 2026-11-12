# Lean Proof Specification

## Purpose
- Defines Lean 4-based transitionsemantics, tactic search, Nim↔Lean metadata bridge, Proof Vault warm-start, and replay verification rules.

## Mathematical Constitution and Semantics SSOT
- `src/verification/spec.lean` is the Lean-side SSOT providing mathematical definitions of `Invariant` and `Transition`.
- Core theorems must fix safety propositions like `balance can never be negative` at theorem level.
- State, transition, and guard extracted from source must be promoted as Lean 4 `inductive Step` constructor sets to regenerate the complete transition system.
- Transition axioms like `axiom transition` are prohibited in Lean artifacts; semantics must be solely owned by `def nextState ... := match ... with` and `inductive Step`.
- Lean specifications must include not only safety theorems but also termination arguments, progress/no-deadlock theorems, and rank decrease theorems.

## Nim↔Lean Metadata Bridge
- Nim `TransitionRule` and `InvariantRule` must be promoted as structured metadata with 1:1 mapping to Lean theorem identifiers, assumptions, and boundary values.
- Spec Generator must provide a standard input path that 1:1 converts Nim `object` to Lean `structure` and Nim `func/proc` to Lean `def`.
- `range[A..B]` and `static[A..B]` constraints must be promoted to Lean `Subtype` lower/upper bound propositions, with `uint` and `PositiveInt` preferentially mapped to `Nat` or positive subtypes.
- `UniversalTranslation` must generate `stepFunctionCases` and `envInputConstructors` that can be directly inserted into Lean `match`, not just string summaries.
- When Spec Generator detects I/O calls or mutable global state references, the corresponding proc must be marked as `Untrusted` and excluded from Lean `def` generation targets.

## Dynamic Proof Search
- Lean proof search must be a self-healing loop that reads compiler feedback (Error/Goals) and regenerates tactics, not a one-time script.
- `src/verification/lean_lsp.nim` must communicate with `lean --server` via JSON-RPC (`didOpen`, `didChange`) and parse diagnostics and goal states in real time.
- During proof search termination or server shutdown, if streams are closed, reader threads must not propagate I/O exceptions like `Bad file descriptor` but silently clean up.
- On proof failure, LSP must generate customized single tactics or tactic sequences based on error locations and unsolved goals provided, to reflect in the next attempt.
- Initial tactics must analyze recursion, branching, and pattern signals to prioritize `induction`, `cases`, and `simp` combinations.
- Unsolved goals and diagnostics must be able to back-propose missing assumption candidates as `Nim invariant` or `pre-condition`.

## Proof Vault and Warm-start
- On proof success, tactic sequences must be stored in `src/verification/proof_vault/` to be reused as initial strategies for verifying the same theorem/fingerprint.
- If multiple success paths exist for the same theorem/fingerprint, paths with fewer attempts and shorter tactic paths must be prioritized.
- Proof vault summary JSON must save Z3 result snapshot, replay method (`native_decide` or equivalent tactic), replay verdict, and `proofReplayTactics` together.
- Semantic proof artifacts must fix `proofDependencies` and `minimalProofPath` to retain only the minimum replay path based on MemorySafety lemmas.

## Replay and Soundness
- Z3's UNSAT must only be used as a hint; final safe promotion requires Lean kernel-verifiable proof terms or successful tactic replay together.
- `refinementProven` cannot be promoted based solely on SMT's lack of counterexamples but must be cross-verified with Lean replay success.
- Default proof replay strategy is `simp`-based proof terms; when needed, `aesop`, `omega`, and selective `smt` replay plans must be recorded together.
- Complex state structure verification must use tactic expansion strategies including `cases`, `unfold`, and `simp` by default.

## Refinement Feedback Loop and Operational Artifacts
- `inferMissingHypotheses` proposals must be fed back as Nim refinement at the CLI stage through `range/assert`-based feedback.
- `dynamic-proof-search --apply-refinement` on failure must reflect proposed constraints in Nim function signatures or top-of-body `assert` and immediately re-explore.
- Each attempt must leave tactics, diagnostics, goals, and results as structured logs reusable for Reasoning Ledger and trajectory KPIs.
- `thought_trajectory.jsonl` is the input SSOT for internal dashboards that aggregate Proof Success Rate and average attempt count.
- When intentions like `balance >= 0` are promoted to Lean `example : balance >= 0` and proof succeeds, the pipeline must explicitly output `Proof Accomplished`.

## Semantic Proofs (`src/semantic_proofs/`)

Lean 4 proof scripts for semantic verification of C++ source behavior via the Nim↔Lean bridge. These files are the Lean-side artifacts of the hybrid verification pipeline — they consume invariants and SMT UNSAT evidence extracted by Nim, then produce kernel-verified proof terms.

### Directory Structure

| File | Purpose |
|------|---------|
| `main.lean` | Entry point — imports `lib.MemorySafety`, `univalue_cpp_checkType`, `univalue_cpp_otherFunc` |
| `lib/MemorySafety.lean` | Foundational memory safety theorems: `BoundsCheck`, `vectorRead`, `pointerRead`, `pointerSegmentRead`, `MemoryRegion`, `disjoint`, `pointerAliasIsolation` |
| `smt_reconstruction.lean` | Z3 proof trace → Lean 4 kernel `Expr` translation (`Z3Rule` inductive, `parseZ3Rule`, `ruleToLeanExpr`, `reconstruct_z3` elab tactic) |
| `univalue_cpp_checkType.lean` | Positive test: `throwsruntimeerror` — equal `UniValueVType` enum values do not throw (with SMT UNSAT premise) |
| `univalue_cpp_checkType.lean.negative.lean` | Negative test: same theorem statement but with `False` goal — demonstrates expected proof failure path |
| `univalue_cpp_otherFunc.lean` | Positive test: `returnssemanticerror` — equal `UniValueVType` enum values do not return semantic error |

### Key Design Patterns

1. **Hybrid proof structure**: Each proof file defines `semanticCandidateInvariantHints`, `proofDependencies`, and `minimalProofPath` as structured Lean `List String` metadata. The Nim bridge reads these to validate proof trace completeness.

2. **SMT→Lean reconstruction**: `smt_reconstruction.lean` maps Z3 proof rules (`rewrite`, `mp`, `trans`, `linearArith`, `quantInst`, `lemma`, `asserted`, `unitResolution`) to Lean kernel constructors (`Eq.refl`, `id`, `Eq.trans`, `sorryAx`, `forallE`, `Or.elim`). The `sorryAx` mapping for `linearArith` is tracked as DEBT#052.

3. **Axiom-guarded theorems**: Theorems requiring SMT evidence use an explicit `axiom ..._smt_unsat_premise` parameter, ensuring the proof kernel does not implicitly trust Z3 — the premise must be supplied by the Nim bridge with verified UNSAT evidence.

4. **Negative test files**: `*.negative.lean` files intentionally pose unprovable goals (e.g., `False` instead of the correct invariant) to validate that the proof pipeline correctly distinguishes success from failure.

### Lean Toolchain

- Lean 4.29.0, Lake 5.0.0
- `lean-toolchain` file at `proofs/lean-toolchain`
- Build: `lake build` from the Lean project directory
