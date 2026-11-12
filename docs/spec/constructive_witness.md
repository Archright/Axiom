# Constructive Witness — SMT ↔ Lean Mutual Supervision

## Problem

DEBT#279 C3: `verifySmtLeanConsistency` in `the_judge_eval.nim` used `"".splitLines()` as both SMT and Lean evidence, making the mutual-supervision check pass vacuously whenever both provers succeeded. The only SMT↔Lean cross-verification point in the codebase verified nothing.

## Solution

Replace heuristic boolean with a **constructive witness**: `JointProofWitness` containing concrete evidence from both provers that can be compared.

### Witness Model

The witness is a correspondence between:

- **SMT unsat core**: The subset of named assertions that Z3 identifies as the unsatisfiable core via `(get-unsat-core)`. These are `h0`, `h1`, etc. — hypothesis IDs assigned by `buildSmt2Query`.
- **Lean hypothesis binders**: The names in the theorem signature `(h0 : T0) (h1 : T1)` from the Lean replay.

**Correspondence Rule (Index-Level):**
A hypothesis `h<i>` from the SMT unsat core has a counterpart in the Lean hypothesis set iff the Lean set contains a name matching `h<i>`. This is a **name-level correspondence** only — deep semantic matching of assertion types is deferred to future work.

### Why Node-Count/Hash Comparison Was Rejected

Node-count comparison or hash-based matching would also be theater — checking a scalar aggregate (total node count, hash of concatenated cores) does not establish that individual hypotheses correspond. The only meaningful check is pairwise identifier correspondence between the two provers.

## Fail-Closed Rules

- Empty unsat core → `err("no-smt-witness")`
- Empty theorem name → `err("no-lean-witness")`
- Empty Lean hypothesis list → `err("no-lean-witness")`
- SMT core references ID not in Lean hypotheses → `err("hypothesis-mismatch")`
- Matching set → `ok(JointProofWitness(...))`

These are checked in `verifySmtLeanConsistency` and enforced at `evaluateHint` Phase 3. If the witness check fails, `evaluateHint` still approves the result (both provers succeeded) but records the degradation in the `reason` field — the mutual supervision claim is honestly reported as degraded.

## Z3 SMT-LIB Options Used

The `buildSmt2Query` function in `src/core/judge/the_judge_lean.nim`:

1. Wraps each hypothesis assertion with `(assert (! <body> :named h<idx>))` — assigns a name for unsat core tracking.
2. Appends `(get-unsat-core)` after `(check-sat)`.

The `(set-option :produce-unsat-cores true)` is auto-inserted by `z3_pool.nim`'s `buildZ3QueryEnvelope` which detects `get-unsat-core` in the query and prepends the option. The final SMT-LIB script sent to Z3 has the form:

```
(reset)
(set-option :produce-unsat-cores true)
(set-logic QF_LIA)
(declare-const expected Int)
(declare-const typ Int)
(assert (! <body> :named h0))
(assert (! <body> :named h1))
(assert (not (and ...)))
(check-sat)
(get-unsat-core)
(echo AXIOM_Z3_EOF_...)
```

## Interface Additions

### `ProverOutputInterface` (interfaces.nim)

New concept type requiring `proveWithOutput(query: string, timeoutMs: int): Result[string, string]`. Unlike `ProverInterface.prove` which returns `bool`, this preserves the raw Z3 output for unsat core parsing.

### `proveWithOutput` (provers.nim)

`Z3PoolProver` implements `ProveOutputInterface` via `z3ExecPersistent(query, timeoutMs, desiredWorkers=1)`. Returns the full Z3 response including `unsat` + `(h0 h1)` lines.

### `Z3QueryResult.unsatCore` (the_judge_eval.nim)

New `seq[string]` field holding parsed hypothesis IDs from `(get-unsat-core)`.

### `LeanReplayResult.theoremName` + `.hypotheses` (lean_replay.nim)

Fields populated by parsing the Lean source: `extractTheoremName` and `extractHypotheses`.

## Files Changed

| File | Change |
|------|--------|
| `src/core/solver/interfaces.nim` | Added `ProverOutputInterface` concept |
| `src/core/judge/the_judge_lean.nim` | `buildSmt2Query`: named assertions (`h<idx>`), appended `(get-unsat-core)` |
| `src/core/judge/the_judge_eval.nim` | `parseUnsatCore`, `JointProofWitness`, `verifySmtLeanConsistency` rewrite, `buildJudgeLeanTheorem`, `evaluateHint` signature + Phase 3 |
| `src/core/judge/lean_replay.nim` | `extractHypotheses`, populated `theoremName` + `hypotheses` in `LeanReplayResult` |
| `src/verification/solver/provers.nim` | `proveWithOutput` for `Z3PoolProver` |
| `tests/unit/test_constructive_witness.nim` | 15 tests covering parse, verify, extract, build |
