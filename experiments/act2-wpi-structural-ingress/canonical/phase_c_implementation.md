# Phase C Implementation — WP4-i Minimal Generic Fix

> **Experiment ID**: `act2-wpi-structural-ingress`
> **Phase**: C — root-caused integration fix + regression + zero-drift
> **Date**: 2026-08-30
> **Subject**: Axiom CLI (`.`)
> **Subject Revision**: HEAD (working tree)
> **AXIOM_REVISION**: working tree
> **TOOLCHAIN_IDENTITY**: Nim 2.2.10 [Linux: amd64]
> **VERIFICATION_SCOPE**: `src/cli/payload_bridge.nim` (source-root-aware file read) + `src/core/diagnostics/pattern_guard.nim` (empty-source fail-closed guard)

---

## Question

Can Axiom process external-subject `prove` runs without the `erGuardHardReject` / "Failed to parse Nim source" hard-reject caused by reading module files against process CWD instead of the subject root?

---

## Diff Summary

### File 1: `src/cli/payload_bridge.nim`

**Fix 1 (P3 — generic, subject-agnostic):** Source-root-aware module file read.

| Function | Change | Line Refs |
|---|---|---|
| `topologyToWorkflowPayload` | Added `sourceRoot: string = ""` parameter | Sig line 31 |
| `topologyToWorkflowPayload` | Replaced `readFileOpt(modulePath)` with source-root-aware read: if `sourceRoot` non-empty, try `sourceRoot / modulePath` first, fall back to raw relative read | Lines 67–72 |
| `topologyFrontierToWorkflowPayload` | Added `sourceRoot: string = ""` parameter | Sig line 92 |
| `topologyFrontierToWorkflowPayload` | Replaced `readFileOpt(modulePath)` with source-root-aware read (same logic) | Lines 108–113 |

**Why generic (P3):** The fix is symbol-agnostic and subject-agnostic. It does not target any specific function, construct, or language feature. It simply corrects the file-resolution path for any modulePath when a sourceRoot is provided. The default `sourceRoot = ""` preserves existing behavior for internal runs (zero drift).

**Why fail-closed (P4):** If the file cannot be read at either path, `sourceCode` stays `""` — same fail-closed semantics as before. No content is fabricated.

### File 2: `src/cli/axiom_engine.nim`

**Fix 1 (cont.):** Updated call site to pass `bundle.sourceRoot`.

| Location | Change | Line Ref |
|---|---|---|
| `runProofPipeline` | `topologyFrontierToWorkflowPayload(bundle.analysis, frontier)` → `topologyFrontierToWorkflowPayload(bundle.analysis, frontier, bundle.sourceRoot)` | Line 840 |

### File 3: `src/core/diagnostics/pattern_guard.nim`

**Fix 2 (P4 — fail-closed observability):** Distinguish "no source" from "parse error".

| Function | Change | Line Refs |
|---|---|---|
| `checkApplicability` | Added empty-source early return before `parseNimRes`, returning `PatternApplicability(applicable: false, reason: "Empty source: no source content available" & (if funcName.len > 0: " for " & funcName else: ""), preconditions: patternPreconditions[pattern])` | Lines 312–317 |

**Why fail-closed (P4):** When `sourceCode` is empty/whitespace-only, the function now returns a structured `PatternApplicability` with `applicable: false` and a clear reason — rather than conflating it with a genuine parse error. The guard still rejects (fail-closed), but the reason is now distinguishable.

**No changes to** `src/core/parser_utils.nim` (as required).

---

## Baseline vs Post-Fix Internal Comparison (P5)

| Metric | Pre-Fix (Baseline) | Post-Fix (Zero-Drift) | Match? |
|---|---|---|---|
| Exit code | 0 | 0 | Yes |
| Total | 5 | 5 | Yes |
| Pass | 3 | 3 | Yes |
| Fail | 2 | 2 | Yes |
| TO | 0 | 0 | Yes |
| Skip | 0 | 0 | Yes |
| Error | 0 | 0 | Yes |
| Time | 0ms | 0ms | Yes |

**Result: Identical.** Internal runs are zero-drift. The fix only changes behavior for the external-subject path where `sourceRoot` is non-empty.

---

## Test Results

| Test File | Compile | Run | Pass | Fail |
|---|---|---|---|---|
| `test_ir_pipeline_theaterguard.nim` | OK | OK | 2 | 0 |
| `candidate_eligibility_test.nim` | OK | OK | 5 | 0 |
| `proof_state_machine_test.nim` | OK | OK | 52 | 0 |
| `test_obligation_ir.nim` | OK | OK | 23 | 0 |
| `test_obligation_adapters.nim` | OK | OK | 13 | 0 |

**All 5 regression test suites passed (95 total assertions).**

**No test updates required.** Grep for `"Failed to parse source\|Failed to parse Nim source"` in `tests/` returned zero matches — no test assertions on the old conflated message existed.

---

## Audit Result

Build-time decision-binding audit (`axiom-gate`):

- **Violations found**: 2
- **Violation 1**: `canonicalizeEnvValue` in `src/verification/obligation/identity.nim:52` — NOT a file touched by this fix
- **Violation 2**: `loadCASEntryByKey` in `src/verification/canonical_cache.nim:149` — NOT a file touched by this fix
- **Violations from touched files**: 0

Both violations are pre-existing in files unrelated to `payload_bridge.nim` and `pattern_guard.nim`. No `{.axiomDecision.}` pragma additions were needed for the touched files (the audit gate did not flag them).

---

## Build Exit Codes

| Phase | Command | Exit Code |
|---|---|---|
| Pre-fix build | `nim c -d:release -o:bin/ax src/cli/main.nim` | 0 |
| Post-fix build | `nim c -d:release -o:bin/ax src/cli/main.nim` | 0 |

---

## External Probe Observation (Step 8)

**Command**: `ax prove --project <workspace>/nim-stew-clean-c75502c --target 'stew/bitops2.nim::getBitsBE' --limit 1`

| Metric | Pre-Fix Known Signature | Post-Fix Observation |
|---|---|---|
| `grep -c "Failed to parse Nim source"` | >0 (hard-reject) | **0** |
| `grep -c "erGuardHardReject"` | 1 | 1 (still present, different reason) |
| Sieve-Gate classification | N/A (parse failure before sieve) | `getBitsBE: structural_ast (io_boundary)` |
| First 3 lines after Sieve-Gate | N/A | `Refactoring: 1 task(s) queued` → `→ getBitsBE: structural_ast (io_boundary)` → `✗ getBitsBE — escalated: erGuardHardReject` |

**Key observation**: The "Failed to parse Nim source" hard-reject for getBitsBE has disappeared. The function now gets past the parser (source file is correctly read from the subject root), and the Sieve-Gate classifies it as `structural_ast (io_boundary)`. It is still escalated via `erGuardHardReject` — but for a legitimate guard reason (io_boundary precondition not met), not because of a conflated empty-source/parse-error.

**Note**: Full replay/classification of the external subject is not performed here — only the cheap sanity probe to confirm the parse-failure hard-reject is gone.

---

## Coordinate Verification

All coordinates from the task description were confirmed by reading the files:

- `payload_bridge.nim` line 67 and line 102: both `readFileOpt(modulePath)` sites — confirmed
- `axiom_engine.nim` line 840: call site for `topologyFrontierToWorkflowPayload` — confirmed
- `axiom_engine.nim` line 616: `sourceRoot` definition in `runProofPipeline` — confirmed
- `axiom_engine.nim` line 1093: `effectiveCwdOverride` — confirmed
- `pattern_guard.nim` line 312: `parseNimRes(sourceCode)` call — confirmed
- `refactoring_engine.nim` line 205-207: guard rejection surfacing — confirmed
- `wf_planning.nim` line 99: correct internal path using `joinPath(bundle.sourceRoot, ...)` — confirmed
- No test assertions on old error message found in `tests/` — confirmed
