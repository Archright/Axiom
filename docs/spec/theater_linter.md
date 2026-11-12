# Theater Pattern Linter

> **Related:** the full-tree CI scanner `check_nim_theater` and the overall theater
> policy (allowed conventions, allowlist rationale, string-literal masking) are
> documented in [theater_detection_policy.md](theater_detection_policy.md).
> This module is the compile-time macro (AST) layer only.

## Overview

`src/core/audit/theater_linter.nim` is a compile-time Nim macro linter for Stage 4 theater-pattern detection. It uses an AST macro entry point and simple source-level string matching so it can run during `nim c` without spawning external tools.

## Usage

Import the module and call `lintTheaterPatterns` with the source file to scan:

```nim
import core/audit/theater_linter

lintTheaterPatterns(currentSourcePath())
```

When called from a module, pass an absolute path such as `currentSourcePath()` or an absolute file path. The macro reads that file at compile time and emits Nim warnings for detected theater patterns.

## Detected Patterns

| Pattern | Trigger |
| --- | --- |
| `tpSwallowedFailure` | `except CatchableError:` with `discard` on the same line or the next line. |
| `tpHardcodedTrueReturn` | `return true` inside a proc whose name contains `verify` or `check`. |
| `tpAlwaysTrueCondition` | `if true:` or `when true:`. |
| `tpEmptyExceptBlock` | `except ...:` blocks whose body contains only blank/comment lines. |

## Direct Scanner

The scanner is exposed for tests and tools:

```nim
import core/audit/theater_linter

let findings = scanTheaterSource(sourceText, "fixture.nim")
```

`scanTheaterSource` returns `seq[TheaterFinding]` with `pattern`, `path`, `line`, `symbol`, and `message` fields.

## Example

This source emits warnings for all four pattern categories:

```nim
proc verifyAlways(): bool =
  return true

proc alwaysTrueIf(): bool =
  if true:
    return true

proc emptyExcept(): void {.raises: [CatchableError].} =
  try:
    discard
  except CatchableError:
    # intentionally empty
```

## Notes

- The matcher is intentionally conservative and source-oriented. It does not perform full Nim semantic analysis.
- `lintTheaterPatterns` is intended for compile-time warning emission. Build systems that convert warnings to errors should treat these findings as theater debt.
- Tests live in `tests/unit/theater_linter_test.nim`.

---

## Phase 4: Static Verification Enhancements (2026-07-30)

Phase 4 adds three complementary prevention layers to stop theater patterns from re-entering the codebase at compile time or CI.

### 4A: AST-Based Result Discard Linter

**File**: `src/core/lint/discard_result_linter.nim`

Enhanced the existing compile-time macro linter with two-pass detection:

1. **Pass 1** — scans the AST body for `proc`/`func` definitions carrying `{.discardable.}` pragma, collecting their names into a set.
2. **Pass 2** — flags `discard <expr>` where `expr` has a `Result[T, E]` type, **unless** the call target matches a name collected in Pass 1.

This exempts intentionally fire-and-forget APIs (annotated `{.discardable.}`) from the theater signature #2 (swallowed failure) check, while still catching accidental Result discards.

**Usage**: Wrap proc/func blocks with `checkDiscardResult:` macro. Imported into `io_executor.nim` and any module calling Result-returning procs.

**Comment tag**: `# axiom:theater-prevention(DEBT# theater signature #2: swallowed failure via discard)`

### 4B: BareExcept Unconditional Error Enforcement

**File**: `config/effects.nims`

Added explicit `switch("warningAsError", "BareExcept")` placed **outside** the `ALLOW_WARNINGS` break-glass guard. This ensures bare `except:` clauses are always compile errors, even when `ALLOW_WARNINGS=true` suppresses the global `warningAsError: on`.

Rationale: A bare `except:` without a pattern swallows all exceptions — theater signature #2 (swallowed failure). Unlike other warnings, this must never be break-glass-able because it silently hides runtime errors.

**Comment tag**: `# AGENTS.md §0.6: Bare except = theater signature #2 (swallowed failure)`

### 4C: Gate Status Metrics Tool

**File**: `tools/gate_status_metrics.nim`

CLI tool that parses gate execution JSONL logs (`.axiom/gate_history.jsonl`) and counts results by `GateStatusKind`:

- `VerifiedPass` — clean verification success
- `VerificationFailed` — violation detected (Fail-Closed)
- `WarningViolated` — non-blocking violations requiring audit
- `SkippedInapplicable` — no triggers evaluated (NOT a success)
- `ExplicitlyDisabled` — configured disabled

Maps legacy JSONL result strings (`"pass"|"fail"|"skip"|"timeout"|"cached"`) back to GateStatusKind-equivalent categories. Exits with code 1 if any non-pass gates exist, enabling CI integration.

**Usage**:
```bash
nim c -r tools/gate_status_metrics.nim                    # default path
nim c -r tools/gate_status_metrics.nim -- .axiom/foo.jsonl  # custom path
```

**Comment tag**: `# axiom:theater-prevention(DEBT# Phase 4-C: GateStatusKind metrics)`
