# Local Exact Gate — Usage Guide

## Overview

`local-ci-gates` is a canonical CLI tool that runs a gate **locally** with the
exact same semantics as the Makefile CI-gate targets (`make ci-gates`). It gives a developer
a deterministic PASS/FAIL without waiting through the full local pipeline.

The tool is the fast-path complement to `make ci-gates`: it runs a single gate
directly (not through `gate_hook`), bypasses result caching, and uses a fresh
detached worktree so the substrate is clean and reproducible.

## CLI Grammar

```
local-ci-gates --ref <git-ref | pr N> \
               --gate <gate> \
               --substrate <full|shallow>
```

### Options

| Option | Required | Default | Description |
|---|---|---|---|
| `--ref` | Yes (unless `--pr` used) | — | Git refname or full SHA. Resolved to an immutable 40-char SHA. |
| `--pr N` | Yes (unless `--ref` used) | — | PR number. Resolved to the PR merge commit SHA via `gh api` (fallback: `git fetch origin pull/N/merge` + `rev-parse FETCH_HEAD`). |
| `--gate` | No | `verification-auditor` | Gate runner to execute. Matches the runner filename under `src/gate/runners/`. |
| `--substrate` | No | `full` | `full` = detached worktree at the immutable ref (clean parity). `shallow` = depth-1 clone + `refs/pull/N/merge` fetch (reproduces a GitHub-style shallow checkout default). |

### Examples

```bash
# Run verification-auditor on the clean merge commit of PR #28
local-ci-gates --pr 28 --gate verification-auditor --substrate full

# Reproduce a FAIL scenario (shallow substrate)
local-ci-gates --pr 28 --gate verification-auditor --substrate shallow

# Run on a specific ref
local-ci-gates --ref main --gate verification-auditor --substrate full

# Run a different gate
local-ci-gates --ref abc123def --gate readiness-start --substrate full
```

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Gate PASS — observed delta is within the declared transition |
| 1 | Gate FAIL — observed delta is outside the declared transition |
| 2 | Tool error — invalid arguments, ref resolution failure, worktree creation failure, gate source not found |

## Determinism Contract

The tool guarantees the following invariants for every invocation:

1. **Immutable ref**: The `--ref`/`--pr` argument is resolved to a full 40-char SHA before any worktree is created. The SHA is the sole identity of the substrate.

2. **Fresh worktree**: A new detached worktree is created under `$TMPDIR` for every run. No state from previous runs is carried forward. The worktree is removed on exit (even on error).

3. **CI-identical env**: The environment variables `AXIOM_CI=1` and `AXIOM_CI_PRESERVE_CACHE=1` are set verbatim, matching the Makefile `ci-gates` target (gate environment parity).

4. **CI-identical argv**: The gate is invoked with the exact same command-line arguments as the Makefile target. For `verification-auditor`:
   ```
   nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim <repoRoot> <mode> 2
   ```

5. **No cache reuse**: The tool runs the gate runner directly (not through `gate_hook`), which bypasses `src/gate/gate_cache.nim` entirely. Every execution is fresh — no cached PASS/FAIL result is ever reused.

6. **No network push**: The tool never pushes to any remote. All git operations are local (fetch, worktree, rev-parse).

## Substrate Modes

### `full` (default)

Creates a detached worktree at the resolved SHA. This is a clean, complete
checkout of the commit — all history is present. This mode is used for parity
testing (verifying that the gate produces the same result as the Makefile `ci-gates` pipeline on a clean
merge commit).

### `shallow`

Creates a depth-1 clone and fetches only `refs/pull/N/merge`. This reproduces
a GitHub-style shallow checkout default (`fetch-depth: 1`), which only has
the merge commit SHA available — not the PR head commit or its ancestors. This
mode is used to reproduce substrate depth issues (e.g.,
the `axiom-transition:` trailer being unreachable because the PR head commit
is not in the shallow history).

## Architecture

```
local-ci-gates
  ├── §1 CLI argument parsing
  ├── §2 Git operations (ref→SHA, PR→SHA via gh api / git fetch)
  ├── §3 Worktree management (create detached, remove on exit)
  ├── §4 Gate execution (build source, run with CI env+argv)
  ├── §5 Result reporting (exit code + observables)
  └── §6 Main orchestration
```

## Relation to `make ci-gates`

The `make ci-gates` target runs the full CI gate pipeline including
`gate_hook ci` (which uses `gate_cache.nim` for result caching). The
`local-ci-gates` tool runs a single gate directly, bypassing the cache,
for fast developer iteration.

```
make ci-gates          # Full CI pipeline (40 steps, uses gate_cache)
local-ci-gates --pr N  # Single gate, fresh execution, no cache
```
