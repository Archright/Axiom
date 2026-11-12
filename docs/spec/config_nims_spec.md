# config.nims Specification

## Overview

`config.nims` is the Axiom project's Nimscript build configuration file.  It runs
before every `nim` invocation (compilation, testing, REPL) and establishes the
compile-time environment: dependency paths, compiler warnings, experimental features,
and git-hook verification.

**Design principles** (per AGENTS.md §0.2):
- **Ideal**: compile-time — executed automatically by the Nim toolchain.
- **Elegant**: language-native Nimscript, no external build system.
- **Fundamental**: adding a new package is a single array entry.
- **Deterministic**: identical installed packages → identical switch set.

## injectAxiomDependencies Protocol

```nim
proc injectAxiomDependencies*(pkgs: openArray[string]) =
```

**Purpose**: Deterministically recover package paths lost due to worktree/toolchain
layout bugs.  Given a list of package name prefixes, it scans `$HOME/.nimble/pkgs2/`
for matching directories and adds each found path via `switch("path", path)`.

**Algorithm**:
1. Resolve `$HOME/.nimble/pkgs2` as the package root.
2. If the directory exists, iterate its contents with `walkDir`.
3. For each directory whose filename starts with `<pkg>-`, add it to the Nim path
   and break (first match wins).

**Current invocation**:
```nim
injectAxiomDependencies(["checksums", "fusion"])
```

This ensures `checksums` and `fusion` (required for SHA-2 hashing and pattern
matching) are always on the include path regardless of worktree configuration.

**Adding a new package**: append the package name string to the array literal.
No other changes needed.

## Compile-time Switches

### Path Configuration

| Switch | Value | Purpose |
|--------|-------|---------|
| `--path:src` | `src` | Standard library source root for all Axiom modules |
| `--path:tests/gateway` | `tests/gateway` | Gateway test modules available during test compilation |

### Warning / Error Flags

| Switch | Effect | AGENTS.md Reference |
|--------|--------|---------------------|
| `--warning:BareExcept:on` | Detect bare `except` clauses at compile time | §0.6 Static First Enforcement |
| `--warningAsError:Deprecated:on` | Treat deprecated API usage as compile errors | §0.6 |

### Experimental Features

| Switch | Effect | Purpose |
|--------|--------|---------|
| `--experimental:strictEffects` | Enable compile-time effect tracking | Enforce `{.raises: [].}` purity |
| `--experimental:caseStmtMacros` | Enable macro-based case statement matching | Required by `fusion/matching` pattern matching |

## Git Hooks Verification Block

```nim
block:
  let hooksPath = gorge("git -C " & projectRoot.quoteShell() &
                        " config --local --get core.hooksPath 2>/dev/null").strip()
  if hooksPath.len == 0:
    echo "WARNING: Git hooks not installed ... Run: make -f ci/checker.mk setup-hooks"
  elif hooksPath != ".githooks":
    echo "WARNING: Git core.hooksPath is '" & hooksPath & "', not the canonical '.githooks' ..."
```

**Purpose**: Read-only verification that git hooks are properly configured.
This block does NOT mutate git state (per AGENTS.md §0.2 determinism requirement).

**Behavior**:
1. Queries `git config --local --get core.hooksPath` via `gorge()` (compile-time shell
   execution), scoped to the repository-local config. git resolves system → global → local,
   so an unscoped read would let a developer-wide `core.hooksPath` produce a spurious warning
   about this repository.
2. If the result is empty, prints a warning directing the user to
   `make -f ci/checker.mk setup-hooks` (`ci/checker.mk:316-320`, which builds and runs
   `tools/setup_hooks.nim` — the sole writer of that key, ADR-0028).
3. If the result is a non-empty value other than the canonical `.githooks`, prints a distinct
   warning naming the same command. That is the state a retired `nimble hooks` run leaves
   behind: a non-empty value that points the repository away from the tracked hooks.
4. If the value is exactly `.githooks`, no output is produced.

**Note**: This is advisory only — compilation proceeds regardless of hook state.
The warning appears in the compiler output stream, not as a compile error. It observes the
installed value; it never asserts it. On a fresh clone the key is legitimately unset (git's
documented `$GIT_DIR/hooks` default, EXPECTED-PRE-INSTALL-DEFAULT).

## Scenarios

Scenario: Fresh worktree with missing dependencies

- **Input**: User clones Axiom into a new worktree.  `~/.nimble/pkgs2/checksums-0.2.0/`
  and `~/.nimble/pkgs2/fusion-1.2/` exist on disk.
- **Expected**:
  1. `injectAxiomDependencies` scans `~/.nimble/pkgs2/`, finds both directories,
     and adds them to the Nim path via `switch("path", ...)`.
  2. `--path:src` and `--path:tests/gateway` are set.
  3. `--warning:BareExcept:on` and `--warningAsError:Deprecated:on` are active.
  4. `--experimental:strictEffects` and `--experimental:caseStmtMacros` are active.
  5. If git hooks are not configured, a `WARNING` message appears in compiler output.

Scenario: Git hooks installed at the canonical value

- **Input**: `git config --local core.hooksPath` returns `.githooks`.
- **Expected**: The git hooks verification block produces no output.  Compilation
  proceeds silently.

Scenario: Git hooks pointed away from the canonical value

- **Input**: `git config --local core.hooksPath` returns `hooks` — the value a retired
  `nimble hooks` run wrote.
- **Expected**: The block prints a distinct warning naming `make -f ci/checker.mk
  setup-hooks`. Compilation still proceeds (advisory only).

Scenario: Missing fusion package

- **Input**: `~/.nimble/pkgs2/` contains `checksums-0.2.0/` but no directory
  starting with `fusion-`.
- **Expected**: `injectAxiomDependencies` adds `checksums` to the path.
  `fusion` is silently skipped (no error — the loop only adds matches).
  Compilation may fail later if `fusion/matching` is imported by a source module,
  producing a standard Nim import error at that point.
