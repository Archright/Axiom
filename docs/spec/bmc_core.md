# BMC Core Specification

## Purpose
- Defines deterministic transition models, SMT encoding, solver execution, timeout, and replay rules for the `src/core` BMC path.

## Execution Model
- The verification core proves race existence in bounded execution space through Bounded Model Checking (BMC).
- The default execution model is a transition system with step bound `N=10`, and the reference model covers read→write patterns of 2 threads and 1 shared integer variable.
- Race violation is defined when the final state does not belong to the set of all valid sequential execution results.
- External write rules must be expressed only through `TransitionRule(op, delta)` injection models, not hardcoded constants.
- The SSOT of safety properties is `TransitionRule.invariant`, and the property encoder transforms this into SMT expressions for injection.

## Transition and Invariant Promotion
- Built-in rules take the form `x[t+1] = ite(r_i[t] >= d, r_i[t] - d, r_i[t])`, maintaining state on guard failure.
- String-based rule promotion parses only allowed patterns (`x = x ± n`, `x ±= n`) without eval and promotes them to `TransitionRule`.
- Natural language constraints are extracted as `InvariantRule` and combined as a single source of truth during transition rule injection.
- General inductive verification must operate with injected `TransitionRule` and `InvariantRule` combinations, not fixed examples.

## SMT Encoding and Z3 Wrapper
- `src/core/solver` and `src/core/solver/solver_bridge.nim` encode transitions and safety properties as SMT-LIB (QF_LIA).
- Z3 output is normalized from SAT/UNSAT/UNKNOWN to `AxiomError` and `ProofArtifact` promotion paths.
- Final state symbols are propagated through `SolverRequest.finalStateSymbol`, and bridges and proof artifacts must not use hardcoded symbols.
- All invariants and implications must be encoded as `(! ... :named id)` assertions to preserve `get-unsat-core` results on UNSAT.
- Z3 calls must only be performed through structured wrappers including query tag, fixed seed, single-thread settings, model capture, and result capture.

## Induction and Counterexample Promotion
- `verify induction --rule ... --invariant ...` must immediately return external rule injection and inductive proof results (JSON).
- k-induction generates Base/Step separation queries, proving safety inductively only when both queries are UNSAT.
- If Base or Step is SAT, verdict is promoted to `race_detected`, and model bindings must be included in `witness.finalState.counterExample`.
- Conditional invariants like `size > 0 => valid(top)` must be promoted as `ImplicationRule` sequences.

## Timeout and Resource Control
- The same `dependencyDepth` level can be verified in parallel with up to `CPU cores - 1` workers, but barriers must be enforced before moving to the nextdepth.
- Solver call count must belimited through `ResourceSemaphore` to suppress memory and process pressure.
- Each node verification has a default 30-second timebox, and `calcDynamicTimeout` combines dependency depth, impact scope, and SMT-LIB2 logic complexity to assign variable timeouts between 5 and 120 seconds.
- Each attempt in `dynamic-proof-search` has a 120-second hard timeout; on timeout, Lean/Z3 process trees must be safely reclaimed, and the result `reason` must be standardized to `timeout_exceeded`.

## Orchestration and Replay
- Immediately after leaf proof success, detailed AST and intermediate analysis data must be released, leaving only short axioms with fingerprints in the Vault.
- Upper-level verification must use only Vault axioms and dependency summaries without reloading lower-level source ASTs.
- On fingerprint mismatch, do not discard the entire branch but promote only changed functions and upper impact paths as stale re-proof targets.
- When stale dependencies or proof failures occur, the corresponding node and upper branch must be maintained as `blockedNodes`.
- At each branching point, solver result, seed, refinement action, and counterexample fingerprint must be recorded in sequence to enable exact replay of the solve → refine → revalidate loop.

## Deterministic Extension Rules
- Bitcoin Script MVP verification loop must only run with single worker, fixed seed, and single-thread solver settings without parallelization.
- `interpreter.cpp` target verification must beable to reconstruct identical SMT queries using only source snapshot strings and paths.
- Opcode blocks must extract stack push/pop, net stack delta, and minimum required depth as transition signatures and expose them together in solver queries and CLI JSON.