# Solver Infrastructure — Specification

> DEBT#188 — Last updated: 2026-06-05

## Purpose

The solver subsystem provides the **SMT-LIB2 expression representation, serialization, and solver
interface layer** used throughout the verification pipeline. It defines the domain types for
SMT expressions, emit SMT-LIB2 queries, parse Z3 results, verify semantic equivalence of
refactored code, and expose abstract prover interfaces for DIP compliance.

Per AGENTS.md §1.2: Domain (`src/core/solver/`) never imports Infrastructure. Concrete
prover implementations (Z3 pool, Lean prover) live in `verification/solver/provers.nim`.

## Module Map

| File | Responsibility |
|------|---------------|
| `types.nim` | **SSOT**: all solver domain types — `SmtSExpr`, `SolverRequest`, `SolverEvidence`, `SolverCounterExample`, `SolverStatus`, `KInductionRequest` |
| `interfaces.nim` | Compile-time concept types: `ProverInterface`, `GateInterface`. Violations = compiler errors. |
| `wrappers.nim` | **DIP bridge** — re-exports `ProverInterface` from `interfaces.nim`. Domain files import this. |
| `smtlib_emitter.nim` | `emitSmt2(req) → string` — deterministic `SolverRequest` → SMT-LIB2 text |
| `z3_result_parser.nim` | `parseStatusLine`, `normalizeBindingValue`, model/unsat core parsing from Z3 output |
| `equivalence_checker.nim` | `buildEquivalenceQuery(original, refactored, name) → string` — SMT-LIB2 equivalence query for refactoring safety |
| `expr/construct_base.nim` | Base S-expression constructors (`sVar`, `sConst`, `sExprToString`) |
| `expr/construct_arithmetic.nim` | Arithmetic constructors (`sAdd`, `sSub`, `sMul`, `sEq`, `sLt`, `sLe`, `sGt`, `sGe`) |
| `expr/construct_logical.nim` | Logical constructors (`sAnd`, `sOr`, `sNot`, `sImplies`) |
| `expr_serialize.nim` | `toSmt(expr) → string` — recursive S-expression → SMT-LIB2 string serialization |
| `type_serialize.nim` | `solverStatusString`, `logicKindString` — enum → string serialization |
| `encoding_properties.nim` | Property encoding: safety properties → SMT-LIB2 assertions |
| `encoding_transition.nim` | Transition relation encoding: state transitions → SMT-LIB2 |

## Key Types

| Type | Module | Description |
|------|--------|-------------|
| `SmtSExpr` | `types` | Recursive S-expression: `kind` (enum) + `text` + `args: seq[SmtSExpr]` |
| `SmtExprKind` | `types` | Enum: `exprIntLit`, `exprBoolLit`, `exprSymbol`, `exprIte`, `exprAdd/Sub/Mul`, `exprEq/Lt/Le/Gt/Ge`, `exprAnd/Or/Not/Implies` |
| `SolverRequest` | `types` | Logic, declarations, preconditions, assertions, flags for check-sat/get-model/get-unsat-core |
| `SolverEvidence` | `types` | Solver name, logic, status, query hash, SMT-LIB2 text, model, unsat core |
| `SolverCounterExample` | `types` | Violated property, trace, variable bindings |
| `SolverBinding` | `types` | Name-value pair for counterexample model |
| `SymbolicFailure` | `types` | Error code + optional solver status + optional counterexample + optional SMT-LIB2 |
| `KInductionRequest` | `types` | k-induction wrapper: base case + step case + uniqueness constraints |
| `ProverInterface` | `interfaces` | Concept: `prove(query, timeout) → bool`, `name() → string` |
| `GateInterface` | `interfaces` | Concept: `inspect(source) → bool`, `ruleName() → string` |
| `LogicKind` | `types` | Enum: `logicQfLia` (quantifier-free linear integer arithmetic) |
| `SolverStatus` | `domain_types` | Enum: `solverSat`, `solverUnsat`, `solverUnknown`, `solverVacuousContradiction` |

## Entry Points

| Function | File | Description |
|----------|------|-------------|
| `emitSmt2(req) → string` | `smtlib_emitter` | Deterministic SolverRequest → SMT-LIB2 text |
| `toSmt(expr) → string` | `expr_serialize` | Recursive S-expression → SMT-LIB2 string |
| `parseStatusLine(raw) → SolverStatus` | `z3_result_parser` | First-response-wins projection of `sat`/`unsat`/`unknown` from Z3 output |
| `readSolverStream(raw) → SolverStreamOutcome` | `contracts/z3_extraction` | Status plus the response count and the anomaly flag, using the same classifier so the count cannot measure a different grammar than the verdict it qualifies |
| `proofResultFromSolverStream(stdout) → ProofResult` | `contracts/z3_extraction` | The single stdout→`ProofResult` mapping; anomaly ⇒ `psUnknown` with the reason recorded |
| `solverResponse(raw [, exitCode]) → SolverResponse` | `trusted/solver_invocation` | The single solver-authority classification: an `(error …)` form or a non-zero exit yields `srNoDecision`, which can only remove a verdict, never add one |
| `normalizeBindingValue(raw) → string` | `z3_result_parser` | Normalize Z3 model values (bitvector, negative, etc.) |
| `buildEquivalenceQuery(orig, refactored, name) → string` | `equivalence_checker` | Build UNSAT-checkable equivalence query |
| `extractAssignments(node) → seq[(string, string)]` | `equivalence_checker` | AST → variable assignment pairs |
| `smtOp(nimOp) → string` | `equivalence_checker` | Map Nim operators to SMT-LIB2 symbols |

## S-Expression Constructor Hierarchy

```
construct_base.nim      sVar(name), sConst(int), sExprToString
├── construct_arithmetic.nim   sAdd, sSub, sMul, sEq, sLt, sLe, sGt, sGe
└── construct_logical.nim      sAnd, sOr, sNot, sImplies
```

## Integration Points

- **`core/domain_types`** — `AxiomError`, `SolverStatus` definitions
- **`verification/solver/provers.nim`** — Infrastructure-layer concrete prover implementations (Z3PoolProver, LeanProver)
- **`verification/cegar_engine`** — CEGAR loop uses `SolverRequest`/`SolverEvidence` for counterexample queries
- **`core/bmc_generic`** — BMC engine uses `KInductionRequest` for bounded model checking
- **`personas/detective`** — Detective builds tracking SMT-LIB2 and extracts unsat cores
- **`core/refactoring_engine`** — Uses `buildEquivalenceQuery` for refactoring safety verification
- **`core/type_system/liquid_inference`** — Uses `SymSExpr` for liquid type predicates

## Key Contracts

1. **Effect boundary**: All files in `src/core/solver/` are `{.push raises: [].}` + `{.push noSideEffect.}`. Pure domain types.
2. **DIP compliance**: Domain imports only `interfaces.nim` / `wrappers.nim`. Concrete prover implementations are in Infrastructure.
3. **Compile-time enforcement**: `ProverInterface` and `GateInterface` are Nim concepts — violations are compiler errors, not runtime failures.
4. **Deterministic emission**: `emitSmt2` produces identical output for identical input. No timestamps, no randomness.
5. **Response-stream anomaly**: `parseStatusLine` reads the FIRST `sat`/`unsat`/`unknown` line of a stream and ignores the rest, so a verdict is never taken from a line the parser did not read first. A stream carrying more than one ⟨check_sat_response⟩ is an ANOMALY, not a verdict: `readSolverStream` (`core/contracts/z3_extraction`) reports `responseCount` and `isAnomalous`, and such a stream carries no status, so no obligation is discharged. `proofResultFromSolverStream` records the reason in `ProofResult.reports` (`tsWarning`, non-blocking). A stream whose first response is `sat` keeps `solverSat`: a counter-example is adverse evidence that an anomaly never withholds. `solverVacuousContradiction` is no longer produced by the parser; it remains a `SolverStatus` member used elsewhere (e.g. `gateway_main.proveAxiomNode`'s vacuity detection) and `solverVerdictOf` projects it to `svUnknown`. This rule is sound because Axiom's production envelope emits exactly one `(check-sat)` (`z3_extraction.nim:497`); an envelope with several must gain an explicit response-pairing rule rather than relaxing this one silently.

## Layer 2b: Fixedpoint Engine & Constrained Horn Clauses

### Overview

Z3 **Spacer** is the default fixed-point engine for Constrained Horn Clauses (CHC) in the Axiom verification pipeline. Spacer generalizes the IC3 / Property Directed Reachability (PDR) algorithm to infinite-state systems modulo SMT theories (primarily Linear Integer Arithmetic). It is invoked via SMT-LIB2 text emitted by `fixedpoint_engine.nim` and solved through the `Z3PoolProver` infrastructure bridge.

### CHC Encoding Mapping

The Nim layer maps SMT-LIB2 CHC surface syntax to structured Nim types and pure string emission:

| SMT-LIB2 Command | Nim Construct | Responsibility |
|------------------|---------------|--------------|
| `declare-rel` | `emitRelDeclarations(variables)` | Declares uninterpreted state / error relation signatures (`state`, `error`) with `Int` argument sorts. |
| `declare-var` | `emitVarDeclarations(variables)` | Declares universally quantified program variables and primed next-state copies (`x`, `x!`). |
| `rule` | `emitRule(HornClause)` | Injects an implication rule. Body = premise (NNF, uninterpreted predicates occur positively); head = conclusion (uninterpreted predicate or interpreted formula). |
| `query` | `(query error)` emitted by `emitHornClauses` | Poses reachability query. Returns `sat` (error reachable / property violated) or `unsat` (safe). |
| `set-logic HORN` | `chcPrelude` constant | Forces Z3 to use the fixed-point engine rather than the standard SMT solver. |

The CHC program structure produced by @anchor(fixedpoint_engine.emitHornClauses) follows the classic verification-condition pattern:

```
Init rule:      init(x) => state(x)
Transition:     state(x) ∧ trans(x, x!) => state(x!)
Property:       state(x) ∧ propBody(x) => error
Query:          (query error)
```

- **UNSAT** → property holds (safe); Z3 may emit an inductive invariant as part of the proof.
- **SAT** → property violated; Z3 emits a counterexample trace / model.

### Spacer / PDR Dynamics

#### PDR (Property Directed Reachability)
PDR is a SAT/SMT-based model-checking algorithm that maintains a sequence of over-approximating frames `F₀, F₁, …, Fₖ` representing states reachable in ≤ *k* steps. It searches for a counterexample to safety backwards from the error predicate while simultaneously propagating lemmas (blocking clauses) forward to strengthen induction hypotheses. In Z3, the PDR engine is targeted at symbolic model checking of software and applies to Horn clauses over arithmetic, algebraic data-types, and bit-vectors.

#### MBP (Model-Based Projection)
For infinite-state systems, exact quantifier elimination is computationally expensive. Spacer uses **Model-Based Projection (MBP)** to under-approximate quantifier elimination relative to a concrete model. Given a model `M` of a formula `φ(x, y)`, MBP computes a formula `ψ(y)` such that `M ⊨ ψ` and `ψ ⇒ ∃x. φ`. This yields finite, model-driven predecessors of bad states, ensuring progress in the backward search even when the state space is unbounded. Spacer's native MBP is enabled by default (`spacer.native_mbp=true`).

#### Inductive Generalization
When Spacer discovers that a counterexample state cannot be extended to a full error trace, it constructs a **lemma** (conflict clause) that blocks the state. This lemma is then **propagated** forward through the frame sequence as far as possible (the *push* / *propagate* phase). If a lemma survives propagation to the point where it implies the safety property, it becomes an **inductive invariant**—a single formula that holds in all initial states, is preserved by the transition relation, and excludes all error states. The invariant is returned in the `FixedpointResult.invariant` field when the query is `unsat`.

### Entry Points

| Function | Description |
|----------|-------------|
| @anchor(fixedpoint_engine.emitHornClauses) | Build complete CHC SMT-LIB2 program from init / transition / property rules. Pure string construction; all `func`. |
| @anchor(fixedpoint_engine.solveFixedpoint) | Send CHC source to Z3 via `Z3PoolProver`, parse `sat`/`unsat`/model/proof into `FixedpointResult`. I/O boundary → `proc`. |
| @anchor(fixedpoint_engine.proveWithFixedpoint) | High-level CFG integration: extract loop header conditions, build init / trans / prop rules, emit, and solve. |

### Key Types

| Type | Description |
|------|-------------|
| `HornClause` | Single CHC rule: `name` + `body` (premise) + `head` (conclusion) |
| `FixedpointResult` | Solver output: `sat` (violated) + `invariant` (inductive) + `counterexample` (model) + `rawOutput` |

### Integration Points

- **`core/cfg_builder`** — `ControlFlowGraph`, `BasicBlock` for loop structure extraction
- **`verification/solver/provers.nim`** — `Z3PoolProver` for actual Z3 invocation
- **CEGAR engine** — uses `proveWithFixedpoint` for automatic invariant inference in the counterexample-guided refinement loop

---

## Known Limitations

- **QF_LIA only**: `LogicKind` currently supports only `logicQfLia`. Non-linear arithmetic, bitvectors, and arrays require extending the enum.
- **No incremental solver**: Each `SolverRequest` is a fresh Z3 process invocation. No push/pop state management.
- **Equivalence checker is AST-limited**: `extractAssignments` works only on simple assignment/declaration nodes. Complex control flow is not modeled.
- **Fixedpoint text-to-SMT**: `blockToSmtCondition` uses textual concatenation of statement content rather than proper AST-to-SMT translation. Production use requires a dedicated AST visitor.
- **Default safety property**: `proveWithFixedpoint` defaults to checking non-negativity of all variables. Callers should supply domain-specific property conditions.

## Scenario: Domain Sharding Import Resolution

```yaml
- name: "Facade Forwarding Verification"
  given: "A project with domain-sharded modules"
  when: "Forwarding stubs are generated at old locations"
  then: "All imports resolve to correct physical paths"
  expect: "nim c succeeds with zero import errors"

- name: "K-Induction Proof Pipeline"
  given: "A function with loop or recursion"
  when: "K-induction solver returns UNSAT for base and step cases"
  then: "Lean kernel verifies the generated proof script"
  expect: "leanKernelVerified == true"

- name: "Circuit Breaker Threshold Scaling"
  given: "A batch of N verification requests"
  when: "Leanstral fails consecutively"
  then: "Pipeline aborts after threshold failures"
  expect: "threshold = 2 (N<=4), 5 (N<=20), 10 (N>20)"
```

## Scenario: Fixedpoint Engine & Equivalence Verification

```yaml
- name: "CHC Fixedpoint Safety Proof"
  given: "A loop with bounded iteration and a non-negativity invariant"
  when: "proveWithFixedpoint emits init/transition/property Horn clauses to Z3 Spacer"
  then: "Spacer returns UNSAT with an inductive invariant in FixedpointResult.invariant"
  expect: "FixedpointResult.sat == false AND invariant is non-empty"

- name: "Refactoring Equivalence Query UNSAT"
  given: "An original function and its refactored counterpart"
  when: "buildEquivalenceQuery generates an SMT-LIB2 equivalence assertion"
  then: "Z3 returns UNSAT, proving semantic equivalence"
  expect: "parseStatusLine returns solverUnsat"

- name: "Contradictory Response Stream Discharges Nothing"
  given: "One invocation whose stdout carries two ⟨check_sat_response⟩ lines"
  when: "Z3 emits 'unsat' then 'sat' in sequential output"
  then: "readSolverStream marks the stream anomalous and carries no status"
  expect: "proofResultFromSolverStream(stdout).status == psUnknown AND procsProven == 0 AND reports[0].message names the anomaly"

- name: "A Counter-Example Survives A Contradictory Stream"
  given: "One invocation whose stdout carries 'sat' then 'unsat'"
  when: "the first response is the counter-example"
  then: "the anomaly does not withhold the counter-example"
  expect: "ProofStatus is psViolated AND procsViolated == 1"

- name: "The Genuine Conjunction Still Discharges"
  given: "A base case and a step case, each in its own single-response stream, both 'unsat'"
  when: "generateKInductionProofFromSessionId projects the pair"
  then: "verdict, claim and witness node are all derived from the two observed statuses"
  expect: "verdict == safe_within_bound AND claim == 'k-induction base and step are unsat' AND witness status == 'proved'"
```
