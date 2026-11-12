# ADR: Prevention of Vacuous Truth via Dual-pass Pipeline

## 1. Context
In the existing static analysis/SMT proof path, when invariants or preconditions contain contradictions, the entire implication (`A => B`) could be evaluated as always true, causing "Vacuous Truth" problems. This created a critical risk of "False Positives" where SMT Solver returns `unsat` (safe) result even when there are actual logic errors or memory defects.

## 2. Decision
- Introduce **dual-pass verification logic** in the SMT-LIB query execution process to fundamentally block the possibility of Vacuous Truth.
- 1st pass: First check the standalone Satisfiability of preconditions and environment model (must be `sat`). If contradiction exists here, it is determined as a precondition issue.
- 2nd pass: Only after passing the 1st pass, check the Satisfiability of the main proposition (Negated Assertion) and accept `unsat` result as real proof (Real Unsat).
- Failed SMT-LIB queries in this process are explicitly included in logs and trace outputs for debugging and integrity inference (Observability).
- Enforce that 2-pass checks are not omitted in CLI parallel builds and integrity certificate (`prek` gate) synchronization pipelines.

## 3. Consequences
- Verification bypass due to Vacuous Truth became structurally impossible, establishing the Mathematical Integrity principle.
- Even when invariant hints with incorrect preconditions enter the system, it immediately rejects them and requests re-refinement from The Judge persona.
- Global Mutex and Device Guard-compatible sleep logic were added to `refresh_cli_binaries.ps1` and other parallel compilation/verification scripts, resolving Race Conditions during parallel verification.

## 4. Evidence Log (Related Commits)
- `dbe0d807` feat: integrate vacuous contradiction handling, parallelize pre-commit gates, and sync integrity certificates
- `e561db8c` fix: implement 2-pass check-sat logic and fix CLI build concurrency
- `c3c5eb0e` fix(core): block vacuous truth via dual-pass pipeline and observability updates