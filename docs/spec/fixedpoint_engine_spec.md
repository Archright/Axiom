# Fixedpoint Engine Specification

## Overview

The fixedpoint engine (`src/verification/solver/fixedpoint_engine.nim`) implements a
CHC (Constrained Horn Clauses) encoding for loop verification backed by Z3's
Fixedpoint / PDR (Property Directed Reachability) solver.  It translates Axiom's
internal Control Flow Graph (CFG) representation of loops into an SMT-LIB2 Horn
clause program, dispatches it to Z3, and interprets the result as either a proof
(UNSAT + inductive invariant) or a counterexample (SAT + model trace).

**Design principles** (per AGENTS.md §0.2):
- All CHC emission functions are `func` — pure string construction with `{.raises: [].}`.
- The Z3 I/O boundary is the single `proc solveFixedpoint*` at the outermost layer.
- CFG integration functions are split: pure lookup helpers (`func`) vs. I/O-capable
  proof entry point (`proc proveWithFixedpoint*`).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  ControlFlowGraph (from core/cfg_builder)               │
│    └─ loop header block + predecessors + successors      │
└────────────┬────────────────────────────────────────────┘
             │ proveWithFixedpoint(cfg, headerId, variables)
             ▼
┌─────────────────────────────────────────────────────────┐
│  CFG → SMT Translation Layer (func blockToSmtCondition) │
│    • init rule:      entry predecessors' conditions      │
│    • transition rule: header + successor conditions      │
│    • property rule:  variable non-negativity default     │
└────────────┬────────────────────────────────────────────┘
             │ emitHornClauses(variables, init, trans, prop)
             ▼
┌─────────────────────────────────────────────────────────┐
│  CHC Emission (all func, pure string ops)               │
│    • emitVarDeclarations — declare-var for each var      │
│    • emitRelDeclarations — state / error predicates      │
│    • emitRule            — single Horn clause            │
│    • emitHornClauses     — full SMT-LIB2 program         │
└────────────┬────────────────────────────────────────────┘
             │ SMT-LIB2 string
             ▼
┌─────────────────────────────────────────────────────────┐
│  Z3 Fixedpoint Solver (proc — I/O boundary)             │
│    • solveFixedpoint → Z3PoolProver.proveRaw             │
│    • parseFixedpointOutput → FixedpointResult            │
└─────────────────────────────────────────────────────────┘
```

### CHC Rule Structure

The engine emits three Horn clauses per loop:

| Rule   | SMT-LIB2 Form                                      | Semantics                         |
|--------|-----------------------------------------------------|-----------------------------------|
| init   | `(rule (=> <init> (state x ...)))`                  | Entry conditions imply state      |
| trans  | `(rule (=> (and (state x ...) <body>) (state x! ...)))` | Loop body transitions        |
| prop   | `(rule (=> (and (state x ...) <bad>) error))`       | Safety property violation         |

A `(query error)` asks Z3 whether `error` is reachable.  UNSAT = safe, SAT = property violated.

## Key Types

### HornClause

```nim
type HornClause* = object
  name*: string        # Clause identifier (e.g. "init", "transition", "property")
  body*: string        # SMT-LIB2 boolean expression (premise, may be empty)
  head*: string        # SMT-LIB2 atom (conclusion)
```

When `body` is empty the clause is an axiom: `(rule <head>)`.
Otherwise it is an implication: `(rule (=> <body> <head>))`.

### FixedpointResult

```nim
type FixedpointResult* = object
  sat*: bool              # true = property violated (SAT), false = safe (UNSAT)
  invariant*: string      # Generated inductive invariant (when safe)
  counterexample*: string # Model / counterexample trace (when violated)
  rawOutput*: string      # Raw Z3 output for diagnostics
```

Interpretation:
- `sat == false` and `invariant.len > 0` → proof succeeded with an inductive invariant.
- `sat == true` and `counterexample.len > 0` → violation with a concrete trace.
- `sat == false` and `invariant.len == 0` → inconclusive (Z3 returned unknown or error).

## Key Functions

### emitRule (func)

```nim
func emitRule(clause: HornClause): string {.raises: [].}
```

Emits a single Horn clause as an SMT-LIB2 `(rule ...)` command.
If `body` is empty, emits a bare axiom; otherwise emits `(=> body head)`.

### emitHornClauses (func)

```nim
func emitHornClauses*(variables, initBody, transBody, propBody: seq[string]): string {.raises: [].}
```

Assembles a complete SMT-LIB2 Horn clause program from component parts:
1. CHC prelude (`set-logic HORN`, `set-option :produce-proofs true`)
2. Variable declarations (original + primed with `!` suffix)
3. Relation declarations (`state` with Int args, `error` with no args)
4. Init rule, transition rule, property rule
5. `(query error)`

### solveFixedpoint (proc)

```nim
proc solveFixedpoint*(chcSource: string; timeoutMs: int = 30000): FixedpointResult {.raises: [].}
```

Sends the CHC source string to Z3 via `Z3PoolProver` and parses the result.
Returns an error `FixedpointResult` if the prover fails.

### proveWithFixedpoint (proc)

```nim
proc proveWithFixedpoint*(cfg: ControlFlowGraph; headerId: int; variables: seq[string]): FixedpointResult {.raises: [].}
```

High-level proof entry point.  Given a CFG, a loop header block ID, and a set of
program variables, it:

1. **Validates** the header exists and is marked as `loopHeader`.
2. **Builds init** from predecessor blocks (excluding back edges) joined by `or`.
3. **Builds transition** from the header block condition and successor block conditions joined by `and`.  Falls back to an identity frame (`x! = x`) when no explicit conditions exist.
4. **Builds property** as the disjunction of negative variable checks (`< v 0`).
5. Calls `emitHornClauses` then `solveFixedpoint`.

## CFG Integration

### Loop Header Detection

The engine relies on `BasicBlock.loopHeader` from `core/cfg_builder`.  A block is
a loop header if it has a back-edge predecessor (a successor block that dominates it).

### Block-to-SMT Translation

`blockToSmtCondition` extracts a conjunction of statement texts from a `BasicBlock`.
Each statement's XML node is recursively flattened to text.  Empty blocks produce `"true"`.
Single-statement blocks emit the raw text; multi-statement blocks emit `(and ...)`.

### Predecessor/Successor Traversal

- **Init rule**: iterates `headerBlock.predecessors`, excluding back edges (where `predId == headerId`).
- **Transition rule**: iterates `headerBlock.successors`, excluding the CFG exit block.
- **Property rule**: synthesizes default non-negativity checks for all variables.

## Constants

| Constant        | Value                                  | Purpose                          |
|-----------------|----------------------------------------|----------------------------------|
| `chcPrelude`    | `(set-logic HORN)\n(set-option ...)`   | SMT-LIB2 header for CHC programs |
| `stateRelation` | `"state"`                              | Name of the state predicate      |
| `errorRelation` | `"error"`                              | Name of the error predicate      |

## Scenarios

Scenario: Simple loop safety verification

- **Input**: CFG with a counter loop (`while (i < n) { i++ }`) where `i` and `n` are
  program variables.  Header block has condition `(< i n)`, successor has `(= i! (+ i 1))`.
- **Generated CHC**:
  ```smt2
  (set-logic HORN)
  (set-option :produce-proofs true)
  (declare-var i Int)
  (declare-var i! Int)
  (declare-var n Int)
  (declare-var n! Int)
  (declare-rel state (Int Int))
  (declare-rel error ())

  (rule (=> (< i n) (state i n)))
  (rule (=> (and (state i n) (< i n) (= i! (+ i 1))) (state i! n!)))
  (rule (=> (and (state i n) (or (< i 0) (< n 0))) error))
  (query error)
  ```
- **Expected**: `UNSAT` with an inductive invariant such as `(define-fun inv ((i Int) (n Int)) Bool (>= i 0))`.

Scenario: Buffer overflow detection

- **Input**: CFG with an array access `a[i]` inside a loop where `i` is not bounded
  above by `len(a)`.  The property rule includes `(< i 0)` and `(>= i len)` checks.
- **Generated CHC**: similar structure but `propBody` includes `(or (< i 0) (>= i len))`.
- **Expected**: `SAT` with a counterexample trace showing the variable assignments
  that lead to the out-of-bounds access (e.g., `i = len`, `a = ...`).

Scenario: Missing loop header block

- **Input**: `proveWithFixedpoint(cfg, headerId=99, variables=["x"])` where block 99
  does not exist in the CFG.
- **Expected**: `FixedpointResult` with `sat == false`, `rawOutput` containing
  `"ERROR: block 99 not found in CFG"`.  No Z3 invocation occurs.

Scenario: Non-loop-header block

- **Input**: `proveWithFixedpoint(cfg, headerId=5, variables=["x"])` where block 5
  exists but `loopHeader == false`.
- **Expected**: `FixedpointResult` with `sat == false`, `rawOutput` containing
  `"ERROR: block 5 is not a loop header"`.
