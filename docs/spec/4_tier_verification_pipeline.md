# 4-Tier Deterministic Verification Pipeline

## Overview

Axiom uses a 4-tier verification pipeline to balance speed, cost, and completeness.

## Tier 1: Fast Deterministic Tactic (0ms)

- Tactic: `simp [*]`, `rfl`, `omega`
- Condition: Simple theorems without inductive types
- Implementation: `generateOptimalTactic()`

## Tier 1.5: AST Type-Driven Inductive Tactic (< 0.1s)

- Tactic: `by induction x <;> simp [*]`
- Condition: Parameters with inductive types (seq[T], Nat, List[T])
- Implementation: `tryInductiveTactics()`
- Guard: Multi-parameter loop with REPL verification

## Tier 2: REPL-Verified LLM Engine (1-3s)

- Providers: Claude API (primary), Ollama (fallback)
- Guard 2: `extractTacticBlock()` for Markdown fence parsing
- Guard 3: `isTier2Available()` fast-skip
- Cache: AST Hash-based tactic cache

## Tier 3: Z3 SMT/BMC Fallback (2-5s)

- Condition: All previous tiers failed
- Result: UNSAT (Promoted), SAT (Failed), UNKNOWN (dsInductiveDebt)
- Implementation: `handleZ3BmcResult()`

## Soundness Classification

- `z3Unsat`: Bounded verification up to K=20
- `z3Sat`: Counterexample found (build blocked)
- `z3Unknown`: Inductive gap (dsInductiveDebt)
