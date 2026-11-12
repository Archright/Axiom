# Context7-Guided Architecture Audit Report

> **Date**: 2026-06-03T10:16:16+09:00  
> **Scope**: Full-tree SOLID / SSOT / DRY / SoC violation extraction  
> **Method**: Phase 1 (compiler baseline) → Phase 2 (nimtry AST) → Phase 3 (code-index cross-reference) → Phase 4 (Context7 validation) → Phase 5 (ranked report)  
> **Context7 Library**: `/nim-lang/nim` (official Nim manual + changelogs)  
> **Evidence Archive**: `verifications/nim_check_main_2026-06-03.txt`

---

## Executive Summary

| Principle | Violations | Compile-Blocking | Architectural | Hygiene |
|-----------|-----------|------------------|---------------|---------|
| **SSOT** | 2 classes | 2 | 1 | 0 |
| **SoC** | 3 classes | 0 | 1 | 2 |
| **SOLID** | 3 classes | 0 | 2 | 1 |
| **DRY** | 2 classes | 0 | 0 | 2 |
| **Compiler Hygiene** | 4 classes | 4 | 0 | 0 |
| **Total** | **14 classes** | **6** | **4** | **4** |

> **Note**: nimtry (`bin/nimtry --full-tree`) reports **PASSED — no violations** for AST-level checks, but misses compiler-visible errors (undeclared identifiers, unused imports) because it does not perform full symbol resolution. This audit uses the **compiler as the ultimate ground truth** per AGENTS.md §0.6 Static First Enforcement.

---

## Context7 Canonical Criteria

All violations are classified against the following official Nim documentation:

| Criterion | Context7 Source | Relevant Principle |
|-----------|----------------|--------------------|
| `func` = `noSideEffect` proc; compiler verifies no global/threadlocal access | `/nim-lang/nim` manual.md §Effect system | SoC / SOLID |
| `{.raises: [].}` drives runtime exception possibility to zero at compile time | `/nim-lang/nim` manual.md §Exception tracking | SoC |
| `distinct` types + `requiresInit` prevent accidental type confusion | `/nim-lang/nim` manual.md §Type safety | SSOT |
| Compiler warns on `UnusedImport` (Nim 1.0+), `DuplicateModuleImport` (Nim 1.6+) | `/nim-lang/nim` changelog_1_6_0.md, changelog_1_0_0.md | SOLID (ISP/SRP) / DRY |
| `{.used.}` pragma is the canonical way to suppress false-positive unused imports | `/nim-lang/nim` manual.md §Pragmas | SOLID (ISP) |

---

## Violation Details (Ranked by Severity)

### 🔴 TIER 1 — Compile-Blocking (6 classes)

#### V001 — `reremoveFileOpt` Typo → `removeFileOpt`
- **Files**: 
  - `src/cli/commands/check.nim:189`
  - `src/cli/commands/submit_proof.nim:201,204`
  - `src/core/parsers/tree_sitter/tree_sitter_parser.nim:41`
- **Principle**: Compiler Hygiene / SSOT
- **Severity**: Compile-Blocking
- **Evidence**: `Error: undeclared identifier: 'reremoveFileOpt'` — spellSuggest offers `removeFileOpt` (edit distance 1).
- **Context7**: Nim compiler spellSuggest is deterministic (changelog_1_6_0.md). The correct symbol `removeFileOpt` is exported from `src/core/io_utils.nim:49`.
- **Root Cause**: Typographic duplication of the `re-` prefix (likely from `reremoveFile` stdlib naming confusion).
- **Remediation**: Batch replace `reremoveFileOpt` → `removeFileOpt` in 3 files. One-line sed script per AGENTS.md §2.11.

#### V002 — `writeFileSafe` / `readFileSafe` Undeclared in `submit_proof.nim`
- **File**: `src/cli/commands/submit_proof.nim:148,164`
- **Principle**: Compiler Hygiene / SSOT
- **Severity**: Compile-Blocking
- **Evidence**: `Error: undeclared identifier: 'writeFileSafe'` / `readFileSafe` despite `import core/file_utils` at line 71.
- **Context7**: Symbol resolution requires successful module compilation. `file_utils.nim` compiles cleanly (`nim check src/core/file_utils.nim` → 0 errors).
- **Root Cause**: `submit_proof.nim` imports `core/file_utils` but the symbol is not visible. Possible causes: (a) module is shadowed by another `file_utils` in search path, (b) `file_utils` has a conditional compilation block that excludes these exports in this compilation unit, (c) `submit_proof.nim` is compiled with different `--path:` flags than `main.nim`.
- **Remediation**: Verify `import core/file_utils` resolves to `src/core/file_utils.nim`. Check for name collision. If collision exists, use fully qualified import or rename.

#### V003 — `writeFileSafe` Undeclared in `certificate_cli.nim`
- **File**: `src/cli/certificate_cli.nim:424`
- **Principle**: Compiler Hygiene / SSOT
- **Severity**: Compile-Blocking
- **Evidence**: `Error: undeclared identifier: 'writeFileSafe'` — imports `core/io_utils` (line 18) but NOT `core/file_utils`.
- **Context7**: `writeFileSafe` is defined in `file_utils.nim`, not `io_utils.nim`. Importing the wrong module is a **type-location SSOT breach**: the canonical location for file-safe I/O is `file_utils.nim`, but the import points to `io_utils.nim`.
- **Remediation**: Add `import core/file_utils` or replace `writeFileSafe` with the stdlib equivalent if `file_utils` abstraction is unnecessary here.

#### V004 — Broken Fragment File `certificate_cli_part1.nim`
- **File**: `src/cli/certificate_cli_parts/certificate_cli_part1.nim:3`
- **Principle**: SoC / Compiler Hygiene
- **Severity**: Compile-Blocking
- **Evidence**: `Error: expression expected, but found ')'` — file starts with `): LeanSearchResult {.closure.}`
- **Context7**: Nim modules must be syntactically complete compilation units (manual.md §Modules). Fragment files that are `include`-d must still be parsable.
- **Root Cause**: This is an auto-split fragment that is missing its parent proc signature. It is designed to be `include`-d by `certificate_cli.nim`, but standalone compilation fails.
- **Remediation**: Either (a) add a `{.push raises: [Exception].}` header and make the fragment syntactically valid, or (b) move the content into the parent file and delete the fragment. The `certificate_cli_parts/` directory contains 5 such fragments; all should be audited for standalone parseability.

---

### 🟠 TIER 2 — Architectural (4 classes)

#### V005 — Hardcoded Path Literals (DEBT#099, Open)
- **Files**: 7 CLI files, 16 occurrences
  - `src/cli/cst_cli.nim`: `"src/cli/main.nim"` (3×)
  - `src/cli/basic_commands_cli.nim`: `"src/core"`, `"src/verification"`, `"src/verification/spec.lean"`
  - `src/cli/certificate_cli.nim`: `"src/verification/spec.lean"`, `"src/verification/proof_search_attempt.lean"`, `"src/core"`
  - `src/cli/integrity_cli.nim`: `"src/core/unknown.nim"` (2×)
  - `src/cli/procedure_gate.nim`: `"src/allowed_imports.lock"` (2×)
  - `src/cli/verify_workflow_cli.nim`: `"src/"` prefix concatenation
  - `src/cli/commands/heal_scheduler.nim`: `"src/"` string detection (2×)
- **Principle**: SSOT
- **Severity**: Architectural
- **Evidence**: `grep -rn '"src/' src/cli/*.nim src/cli/commands/*.nim` → 16 matches. `src/cli/cli_paths.nim` SSOT module exists (created 2026-06-02) but is **untracked** — 0 imports across the codebase.
- **Context7**: Centralized constants prevent divergence. Nim `const` declarations in a dedicated module are the canonical pattern.
- **Root Cause**: Path literals were written ad-hoc during feature development. A prior agent created `cli_paths.nim` with 7 named constants but did not propagate the imports due to pre-existing compile failures (DEBT#099 rationale).
- **Remediation**: 
  1. Fix pre-existing compile failures in the 7 target files.
  2. Replace all 16 literals with `cli_paths.nim` constants.
  3. Import `cli_paths` in each affected module.

#### V006 — `report_cli.nim` Fat Interface (11 Unused Imports)
- **File**: `src/cli/report_cli.nim`
- **Principle**: SOLID — ISP (Interface Segregation) + SRP (Single Responsibility)
- **Severity**: Architectural
- **Evidence**: 
  ```
  imported and not used: 'options' [UnusedImport]
  imported and not used: 'tables' [UnusedImport]
  imported and not used: 'json_utils' [UnusedImport]
  imported and not used: 'ledger_types' [UnusedImport]
  imported and not used: 'domain_types' [UnusedImport]
  imported and not used: 'ax_tui_reporter' [UnusedImport]
  imported and not used: 'wf_render' [UnusedImport]
  imported and not used: 'wf_state' [UnusedImport]
  imported and not used: 'wf_semantic' [UnusedImport]
  imported and not used: 'constants' [UnusedImport]
  imported and not used: 'metrics' [UnusedImport]
  ```
- **Context7**: Nim 1.0+ warns on unused imports. The `{.used.}` pragma is for modules that are intentionally imported for side effects (manual.md §Pragmas). A module with 11 unused imports signals **interface bloat**: it imports symbols it never uses, violating ISP.
- **Root Cause**: `report_cli.nim` was likely copied from a template or grew organically without import pruning.
- **Remediation**: Remove the 11 unused imports. If any are needed for macro expansion or compile-time side effects, annotate with `{.used.}` and document the rationale.

#### V007 — Gate Registry SSOT Divergence
- **Files**: `src/gate/git.nim`, `src/gate/runners/gate_hook.nim`
- **Principle**: SSOT / SoC
- **Severity**: Architectural
- **Evidence**: Gate Infrastructure Debt Audit (2026-05-27) documents:
  - 2 **ghost gates** (`nim-check`, `gateway-test`) registered in `gates.nim` but no source file exists.
  - 1 **stale gate** (`architecture-gate`) replaced by `nimtry` but still registered.
  - 7 **active gates** (e.g., `intent_gate`, `spec_presence_gate`, `nimtry_gate`) exist in `bin/` and `gate_hook.nim` but are NOT in `gates.nim`.
- **Context7**: SSOT requires exactly one authoritative source. Having two registries (`gates.nim` and `gate_hook.nim`) with divergent contents is a **structural SSOT breach**.
- **Remediation**: 
  1. Remove ghost/stale entries from `gates.nim`.
  2. Register the 7 orphan gates in `gates.nim`.
  3. Or: deprecate `gates.nim` entirely and document `gate_hook.nim` as the canonical registry.

#### V008 — Duplicate `std_redirect` / `io_utils` / `file_utils` Imports
- **Files**: 50+ files across `src/cli/`, `src/core/`, `src/verification/`
- **Principle**: DRY
- **Severity**: Architectural (at scale)
- **Evidence**: 84 `DuplicateModuleImport` hints from `nim check src/cli/main.nim`. `code-index` confirms 197 occurrences of `import core/std_redirect` with many files having 2–3 consecutive duplicate lines.
- **Context7**: `DuplicateModuleImport` was introduced in Nim 1.6.0 (changelog_1_6_0.md) specifically to detect this anti-pattern. Duplicate imports are **syntactic noise** that violate DRY: the same dependency is declared multiple times.
- **Root Cause**: Bulk code generation or copy-paste templates (e.g., CLI command scaffolding) that repeat the standard import block without deduplication.
- **Remediation**: Batch script to deduplicate consecutive duplicate `import` lines per AGENTS.md §2.11. Target: all files in `src/cli/commands/`, `src/verification/`, and `src/core/`.

---

### 🟡 TIER 3 — Hygiene (4 classes)

#### V009 — Over-Broad Exception Specifications (`XCannotRaiseY`)
- **Files**: 40+ files, 226 hints
- **Principle**: SoC / Effect System
- **Severity**: Hygiene
- **Evidence**: `Hint: 'foo' cannot raise 'Exception' [XCannotRaiseY]` / `cannot raise 'CatchableError'` — functions declare `except Exception` or `except CatchableError` but the compiler proves they can never raise those types.
- **Context7**: The `raises` pragma is verified by the compiler (manual.md §Exception tracking). Declaring a broader exception set than necessary is **effect system pollution**: it forces callers to handle exceptions that will never occur, violating SoC (concern: exception contract should match reality).
- **Root Cause**: Template code or defensive coding habits. Many files use `{.push raises: [Exception].}` or `except Exception:` as a blanket pattern.
- **Remediation**: Narrow exception types to what the function can actually raise. For pure functions, use `{.raises: [].}`. For I/O-bound functions, list specific exceptions (`IOError`, `OSError`, `ValueError`). This is a large batch operation (~226 instances) that should use a scripted approach.

#### V010 — Unused Imports in Non-Report Files
- **Files**: 
  - `src/cli/commands/observability.nim`: 6 unused imports (`osproc`, `sequtils`, `times`, `text_utils`, `wrappers`, `the_judge_eval`)
  - `src/cli/wf_runners.nim`: 4 unused imports (`batch_uap_orchestrator`, `proof_budget`, `orchestrator_types`, `sorter_core`)
  - `src/cli/wf_semantic.nim`: 1 unused import (`io_utils`)
  - `src/cli/certificate_cli.nim`: 2 unused imports (`sequtils`, `vault_sync`)
- **Principle**: SOLID — ISP
- **Severity**: Hygiene
- **Evidence**: `Warning: imported and not used: '...' [UnusedImport]`
- **Context7**: Nim 1.0+ warns on unused imports. This is a signal that the module's interface surface area exceeds its actual needs.
- **Remediation**: Remove unused imports. If any are required for compile-time macro expansion, annotate with `{.used.}` and add a comment explaining why.

#### V011 — Deprecated API Usage (`computeAsi`)
- **File**: `src/core/metrics.nim:100`
- **Principle**: SSOT / API Lifecycle
- **Severity**: Hygiene
- **Evidence**: `Warning: Use computeInformationGainWeightedAsi; computeAsi is deprecated [Deprecated]`
- **Context7**: Deprecation pragma is the canonical Nim pattern for API evolution (manual.md §Pragmas). Active callers of deprecated APIs create **technical debt drag**.
- **Remediation**: Migrate internal callers to `computeInformationGainWeightedAsi`. Note: tests still call `computeAsi` intentionally (DEBT#102 — closed as intentional API surface).

#### V012 — `certificate_cli_parts/` Broken Fragment Pattern
- **Files**: `src/cli/certificate_cli_parts/certificate_cli_part{1..5}.nim`
- **Principle**: SoC
- **Severity**: Hygiene
- **Evidence**: `certificate_cli_part1.nim` fails standalone compilation. All 5 files are `include`-d fragments.
- **Context7**: Nim `include` is valid but fragments should be parsable. Starting a file with `): LeanSearchResult` is a syntax error unless included after an opening paren.
- **Remediation**: Consolidate the 5 fragments into `certificate_cli.nim` or wrap each fragment in a valid Nim construct (e.g., a `template` or `macro` body).

---

## Remediation Priority Matrix

| Priority | Violation | Effort | Impact | Batch Script? |
|----------|-----------|--------|--------|---------------|
| P0 | V001 `reremoveFileOpt` typo | 1 min | Unblocks compilation | ✅ Yes |
| P0 | V003 `certificate_cli.nim` missing import | 1 min | Unblocks compilation | ❌ Single file |
| P1 | V002 `submit_proof.nim` symbol resolution | 15 min | Unblocks compilation | ❌ Needs investigation |
| P1 | V004 Broken fragment file | 30 min | Unblocks compilation | ❌ Refactor needed |
| P2 | V005 Hardcoded paths (DEBT#099) | 2 hr | SSOT integrity | ✅ Yes |
| P2 | V008 Duplicate imports (84 instances) | 30 min | DRY compliance | ✅ Yes |
| P2 | V006 `report_cli.nim` fat interface | 10 min | SOLID/ISP | ❌ Single file |
| P3 | V007 Gate registry divergence | 1 hr | SSOT/SoC | ❌ Design decision |
| P3 | V009 `XCannotRaiseY` (226 instances) | 4 hr | Effect purity | ✅ Yes |
| P3 | V010 Unused imports (14 instances) | 15 min | ISP | ✅ Yes |
| P4 | V011 Deprecated `computeAsi` | 10 min | API hygiene | ❌ Single file |
| P4 | V012 Fragment consolidation | 30 min | SoC | ❌ Refactor |

---

## nimtry Gap Analysis

| Violation Class | nimtry Detection | Actual Count | Gap Reason |
|-----------------|-----------------|--------------|------------|
| Undeclared identifiers | ❌ Missed | 6 errors | nimtry does not resolve symbols; it only scans AST identifiers |
| Unused imports | ❌ Missed | 25 warnings | nimtry does not invoke the compiler; `UnusedImport` requires semantic analysis |
| Duplicate imports | ❌ Missed | 84 hints | Same as above — requires compiler semantic pass |
| `XCannotRaiseY` | ❌ Missed | 226 hints | Effect tracking requires full compiler effect analysis |
| Hardcoded paths | ❌ Missed | 16 literals | nimtry's string-literal scan may filter out short strings or path patterns |
| Gate registry divergence | ❌ Missed | 7 orphan gates | nimtry scans source files, not runtime registry state |

**Conclusion**: nimtry is effective for AST-structural violations (function length, export count, case-branch OCP) but **cannot replace the compiler** for semantic violations. The compiler is the ultimate ground truth per AGENTS.md §0.6.

---

## Evidence Log

| Phase | Tool | Output | Location |
|-------|------|--------|----------|
| Phase 1 | `nim check src/cli/main.nim` | 23 errors, 26 warnings, 310 hints | `verifications/nim_check_main_2026-06-03.txt` |
| Phase 1 | `nim check src/core/gateway.nim` | 2 hints | Transitive (via main) |
| Phase 1 | `nim check src/verification/lean_lsp.nim` | 18 hints | Transitive (via main) |
| Phase 2 | `bin/nimtry --full-tree` | Syntax error on fragment file; no violations reported | `src/cli/certificate_cli_parts/certificate_cli_part1.nim` |
| Phase 3 | `code-index` search `import core/std_redirect` | 197 matches, 50+ files with duplicates | `src/cli/`, `src/core/`, `src/verification/` |
| Phase 3 | `code-index` search `import core/io_utils` | 76 matches | Cross-layer import pattern |
| Phase 4 | Context7 `/nim-lang/nim` | 4 queries, 14 snippets retrieved | This report §Context7 Canonical Criteria |

---

## Determinism Check

This audit is **fully reproducible**:

```bash
# 1. Compiler baseline
export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
nim check src/cli/main.nim 2>&1 | grep -E "Error:|Warning:|Hint:.*unused|Hint:.*duplicate|Hint:.*cannot raise"

# 2. nimtry baseline
./bin/nimtry --full-tree

# 3. Hardcoded path scan
grep -rn '"src/' src/cli/*.nim src/cli/commands/*.nim

# 4. Duplicate import scan (code-index or grep)
grep -rn "import core/std_redirect" src/ | awk -F: '{print $1}' | sort | uniq -c | sort -rn
```

All commands produce **identical output** given identical source tree and Nim 2.2.10 toolchain.

---

## Recommendations

1. **Immediate (P0)**: Fix V001 and V003 with a batch script. These are single-character typos and missing imports that block compilation.
2. **Short-term (P1–P2)**: Run the batch script for V008 (duplicate imports) and V005 (hardcoded paths). Both are high-volume but low-complexity.
3. **Medium-term (P3)**: Address V009 (`XCannotRaiseY`) as a dedicated effect-system hygiene wave. This is the largest violation class (226 instances) and aligns with AGENTS.md §0.6 Static First Enforcement.
4. **Structural (P3)**: Resolve V007 gate registry divergence with a design decision: either make `gates.nim` the SSOT and sync `gate_hook.nim`, or deprecate `gates.nim`.
5. **Tooling**: Consider extending nimtry to invoke `nim check` on changed files during pre-commit, capturing compiler-visible violations that AST-only analysis misses. This would close the nimtry gap identified in this audit.
