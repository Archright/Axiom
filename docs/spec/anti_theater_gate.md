# Anti-Theater Gate

> **Related:** the full-tree scanner `check_nim_theater` (`tools/ci/check_nim_theater.nim`)
> and the overall theater policy (allowed conventions, allowlist rationale,
> string-literal masking) are documented in
> [theater_detection_policy.md](theater_detection_policy.md).
> This gate is the commit-time (git-diff, added-lines) layer only.
>
> **Execution locus (corrected 2026-10-04).** `check_nim_theater` is **not** run by
> any GitHub Actions workflow — it is a local-only scanner. It executes on the
> push-admissibility path (`Makefile:371` inside the `push-admissibility` target,
> which `PUSH_ADMISSIBILITY_GATES` at `Makefile:54` composes) and via the
> `.githooks/pre-push` snapshot hook (`.githooks/pre-push:72,97,113,131,161`),
> plus the standalone local target `make check-nim-theater`
> (`Makefile:955-960`). It was previously described here as "the full-tree CI
> scanner", which overstated its locus: the tool is alive and enforced, but only
> on developer machines and the git pre-push hook, not in CI.

## Purpose

Enforce AGENTS.md §0.9 — the Theater Prohibition — by detecting three canonical
theater signatures on git staged additions:

- **S2 (Swallowed Failure)**: `except: discard` without justification
- **S1 (Disguised Stub)**: `check true` / `doAssert true` / `assert true` in tests
- **C (CI Theater)**: `|| true` in CI config files

Theater is defined as code that *claims or appears* to provide a guarantee while
*actually guaranteeing nothing*. This gate catches the most common patterns at
commit time, before they reach review.

## Detection Rules

### Scope

Added lines only — lines starting with `+` in `git diff --cached -U0` output,
falling back to `git diff -U0 HEAD` when nothing is staged. This follows the
Incremental Principle (§2): only changed lines are scanned, not the full tree.

### Rule A — S2 (Swallowed Failure) — `src/**/*.nim` and `tools/**/*.nim`

**Pattern**: An `except` block whose handler body is only `discard`.

Two forms detected:
1. Same-line: `except: discard` or `except CatchableError: discard` etc.
2. Multi-line: `except CatchableError:\n  discard` (consecutive added lines)

**Exemption**: The discard line or the line immediately above it contains the
tag `# axiom:best-effort(<reason>)`.

**Precision limits**: The matcher uses simple substring checks. It flags any
line containing both `except` and `discard` (separated by `:`), and any
`except:` line followed by a bare `discard` line. Braced/nested handlers,
comments between `except:` and `discard`, and multi-statement handlers that
end with `discard` are not distinguished. These limitations are acceptable
because:
- Braced handlers are rare in Nim (no `{}` blocks).
- A user who writes `except: echo "err"; discard` creates a legitimate
  handler — the gate will not fire on the echo line, only on the `discard`
  line following `except:`.
- The gate errs on the side of false positives over false negatives;
  false positives are trivially silenced with the tag.

### Rule B — S1 (Disguised Stub) — `tests/**/*.nim`

**Pattern**: A trimmed line exactly equals `check true`, `doAssert true`, or
`assert true` — the canonical "always passes" stubs.

**Exemption**: The stub line or the line immediately above it contains the
tag `# axiom:compile-check` (used for compile-time-only assertions where
the test framework requires a body).

### Rule C — CI Theater — `.circleci/*.yml`, `Makefile`, `*.mk`

**Pattern**: A line contains the substring `|| true`, which silences command
failure in CI/shell scripts without handling the error.

**Exemption**: The line or the line immediately above it contains the tag
`# axiom:best-effort(<reason>)`.

## Tag Conventions

| Tag | Context | Purpose |
|-----|---------|---------|
| `# axiom:best-effort(<reason>)` | S2, C | Best-effort error handling is intentional; reason required |
| `# axiom:compile-check` | S1 | Assertion is a compile-time check, not a vacuous test |

Tags must be placed on the same line as the violation or on the line
immediately above it.

## Rationale — Added-Lines-Only Scope

Full-tree compile-time scanning was rejected due to the same timeout
precedent that led to `signIntegrityResidueGuard`: the Nim compiler's
`gorge()` does not execute during `nim check`, and a full AST scan of the
entire `src/` tree would exceed the pre-commit time budget (<10s, per
Gate Registry architecture).

Instead, the gate operates on git diff output — deterministic, fast, and
incremental. A malicious actor could bypass detection by adding theater
through file modifications that don't appear in staged diffs (e.g., via
existing unstaged changes), but CI will catch these with the full-tree path.

## Relation to §0.9 and §0.8

- **§0.9 Theater Prohibition**: This gate is the primary enforcement
  mechanism for S2, S1, and C signatures. Other theater signatures
  (always-pass, dead gate, unenforced claim) are enforced by other gates
  (e.g., Anti-Vacuity Proof Gate, Dead Code Gate).
- **§0.8 No Stub Files**: The S1 rule specifically targets the most common
  stub pattern in test files. Full stub-file detection (proportion of
  `check true` lines in a file) is handled by the structural-safety gate.
