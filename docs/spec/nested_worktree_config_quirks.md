# Nested Worktree config.nims Double-Load Quirk

**Discovered**: 2026-09-29 (CI Phase 0 probe, worktree `.worktrees/ci-probe`)
**Class**: Nim toolchain / project config loading
**Immutable constraint**: `config.nims` is §-1 immutable (AGENTS.md) — the quirk
cannot be fixed in the config file itself; only the placement rule changes.
**Invariant**: no `config.nims` in any strict ancestor of the worktree root
(§Invariant below). "Nesting" is not the rule; the ancestor chain is.

## Symptom

A git worktree whose strict ancestor directory chain contains a `config.nims`
(typically one created INSIDE the main checkout, e.g. `.worktrees/<name>/`)
cannot build any Nim target. Failures appear as ambiguous/overloaded module
resolution errors (double registration of every module under `src/`), even on
a pristine tree.

## Cause

Nim loads `config.nims` from **every ancestor directory** of the project being
compiled — not just the worktree root. For a nested worktree the chain
contains both the main checkout's `config.nims` and the worktree's
`config.nims`; both execute, so `switch("path", "src")` registers BOTH
`<main>/src` and `<worktree>/src`. The compiler then sees two copies of every
module.

Evidence (compile output):

```
Hint: used config file '…/Axiom/config.nims' [Conf]
Hint: used config file '…/Axiom/.worktrees/ci-probe/config.nims' [Conf]
```

Building the same tree from a directory OUTSIDE the main checkout loads a
single `config.nims` and succeeds (same sources, same compiler).

## Invariant (the actual rule)

> **A worktree root must have no `config.nims` in any strict ancestor directory.**

The prohibition is **not** "no nesting" and **not** "must be a sibling of the
checkout". Those are heuristics that happen to satisfy the invariant. The
physical cause is the ancestor `config.nims` double-load described above, so the
rule is stated over the ancestor chain because that is what the compiler
actually reads.

- **Sibling placement of the checkout** (checkout `<workspace>/Axiom` → worktree
  at `<workspace>/Axiom-worktree`) is a **sufficient condition** only: the parent
  directory is outside the checkout, so only a single `config.nims` is on the
  worktree's ancestor chain. It is convenient, not necessary.
- **`.worktrees/` inside the tree** violates the invariant directly (the
  checkout's own `config.nims` is a strict ancestor), and is therefore
  **build-incapable**: fine for pure file edits, unusable for any
  compile/test/gate run.
- Any other location is admissible **iff** no strict ancestor holds a
  `config.nims` — the layout is unconstrained beyond that.

## Verification

| Setup | Strict ancestor `config.nims` | Result |
|---|---|---|
| nested worktree `.worktrees/ci-probe` | present (checkout's own) | config double-load → build FAIL |
| same content at `~/.cache/axiom/ci-probe` | none | single config → build PASS |

Placements that satisfy the invariant by ancestor-chain inspection (no build
re-measured): the sibling `<workspace>/Axiom-worktree`, and the linked worktrees
`<user-home>/orca/workspaces/Axiom/{A,B,surface-v50}`.

The orca worktrees are the counterexample that makes the invariant precise: they
live in a different tree from the checkout, are **not** siblings of it, and work
normally — because their ancestor chain carries no `config.nims`. Any rule stated
as "no nesting" or "must be a sibling" is therefore both too strong (it bans
these) and too weak (it states a cause that is not the mechanism).

## Bootstrap note

A fresh worktree or branch switch has no content-fresh gate binaries. The
canonical prescription is a single command — `bin/build_all_gates --release`
([docs/agents/rules_workflow.md](../agents/rules_workflow.md) §2.8). Worktree
*bootstrap tools* (`gate_hook`, `precompile_gates`, `ax`, `install_ax_cas`) are a
different concern: `make ci-compile` ([ci/checker.mk](../../ci/checker.mk)), and
`bin/precompile_gates` populates the AOT CAS under `.axiom/cache/gates/`, not
`bin/`. None of these substitute for `bin/build_all_gates --release`; observed
failure mode without it: stale `bin/epoch_transaction_gate` false-fail.

## Recurrence (2026-10-13) — the preflight itself is the first casualty

Re-confirmed during PR #801 staging: a worktree at `.worktrees/recovery-appendix` (inside the
checkout) could not even run the mandated GIT IMMUNITY preflight — the inner
`feature_manifest_generator` build failed with ambiguous
`discard_result_linter.checkDiscardResult` while the main checkout's
`config/integrity.nims` chain was on the stack (ancestor config double-load, the
mechanism above). Relocation to `<user-home>/worktrees/recovery-appendix`
(clean ancestor chain) → preflight PASS, gates green, PR landed. Operational
corollary: placement must satisfy the invariant BEFORE step 1 of any procedure —
the preflight is the first thing a nested worktree breaks, so a preflight failure
is where this quirk now typically surfaces. Measured admissible placement added:
`<user-home>/worktrees/*`.
