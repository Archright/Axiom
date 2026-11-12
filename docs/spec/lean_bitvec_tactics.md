# Lean 4 BitVec64 Tactic Strategy

## Problem

Lean 4's `omega` tactic handles linear arithmetic over `Nat`/`Int` only. It does NOT handle `BitVec` operations. Using `omega` on `BitVec 64` goals causes proof failures.

## Solution

| Goal Type | Tactic | Notes |
|-----------|--------|-------|
| Translation integrity (Theorem 1) | `rfl` | Definitional equality — no change needed |
| Safety theorem (BitVec 64) | `bv_decide` | From `Std.Tactic.BVDecide` — bitblasting + SAT |
| Safety theorem (bounds/Fin) | `decide` | Decidable propositions without refinements |
| Termination (BitVec 64 measure) | `.toNat` + `omega` | Cast BitVec to Nat before omega |
| For-loop termination | `omega` | Loop bounds are already Nat |
| While-loop termination | `.toNat` + `simp` + `omega` | Cast variant to Nat |

## Generated Lean module header

The generated Lean module must include:
```lean
import Std.Tactic.BVDecide
```

## Notes
- `bv_decide` uses bitblasting + SAT — exponential worst-case but 64-bit is tractable
- `.toNat` casting preserves unsigned semantics (BitVec 64 → Nat 0..2^64-1)
- For division safety (`x ≠ 0`), no type-level encoding exists for BitVec — must prove as hypothesis
