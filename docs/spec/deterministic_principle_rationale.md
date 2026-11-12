# Deterministic Principle Rationale

> SSOT for why Axiom's core engine rejects probabilistic / non-deterministic methods
> (Bayesian Optimization, stochastic gradient descent, Monte-Carlo tree search, etc.)
> regardless of their average-case performance advantage.
>
> Approved: 2026-06-04
> Authority: AGENTS.md §0.2 First-Principles Elegance

---

## 1. The Reproducibility Principle — Failure Must Be Decidable

Suppose a probabilistic approach (e.g. Bayesian Optimization) fails the final Lean 4 kernel check. What does this failure mean to the engine?

- **Option A**: There is a fundamental contradiction in the core logic, making the proof impossible in principle?
- **Option B**: The probabilistic model simply "got unlucky" and missed the correct invariant this round?

If determinism is abandoned, the engine collapses into an **"unknown" state**. The same code, under identical conditions, may succeed yesterday and fail today. The operator cannot distinguish between a genuine logical impossibility and a sampling artefact.

By contrast, deterministic unsat-core monotonic reduction guarantees:

> When the engine reports failure, it means: *"This logic is mathematically unprovable under the current constraint set."*

There is no ambiguity. The failure is 100% reproducible, and the next step (Stagnation report + targeted refactoring) is unambiguously defined.

---

## 2. Oscillation Prevention and Halting Guarantee

Probabilistic meta-heuristics may converge faster **on average**, but they provide **no mathematical guarantee of convergence (or halting)**. Exploration-exploitation trade-offs can trap the search in local minima, or cause it to oscillate between similar failure states indefinitely.

Deterministic unsat-core monotonicity forces unidirectional progress:

```
UnsatCoreSize_{n+1} ≤ UnsatCoreSize_n
```

Because the defect count is a non-negative integer, this inequality guarantees one of two outcomes in finite time:

1. **UnsatCoreSize reaches 0** → Lean 4 kernel approves → QED.
2. **UnsatCoreSize plateaus for 3 consecutive rounds** → `stagnation.escalated` triggers → engine halts with a deterministic diagnostic.

There is no third option. The engine **cannot wander forever**.

---

## 3. Static First and Architectural Philosophical Integrity

Axiom is not a "convenient wrapper around Lean 4". It is a **self-evolving engine whose own operation must be as trustworthy as the proofs it produces**.

The principle that *identical input → identical output* and the static enforcement of `func` / `{.raises: [].}` in Nim means every pipeline stage must behave like a gear in a clockwork mechanism: no exceptions, no surprises, no hidden state.

If the process is non-deterministic, debugging the engine itself becomes impossible. A failure in round 5 cannot be replayed, root-caused, or fixed with confidence. The engine's internal state tracking, provenance logging, and certificate chain all assume determinism as their foundational axiom.

Even when Lean 4 delivers the final verdict, **the journey to that verdict must be controlled with zero randomness**. Only then is the system fully controllable.

---

## 4. Accepted Trade-off: Performance

Determinism has a cost. See `docs/DEBT_REGISTRY.md` DEBT#143 for the quantified performance overhead and long-term mitigation roadmap.

> **Core tenet**: Axiom optimises for *predictable correctness*, not *average-case speed*. A slower deterministic engine is preferred over a faster probabilistic one, because speed without reproducibility is indistinguishable from noise.
