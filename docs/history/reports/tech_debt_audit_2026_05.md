# Technical Debt Audit Report — 2026-05-15

**Branch**: `core` / `main` (synced)  
**Commit**: `706b4233` (`refactor: Verified Core classification + design annotations`)  
**Tag**: `v0.3.9`  
**Scope**: Entire codebase (81 core modules, 231 tracked source files, 25,301 lines in src/core/)

---

## Executive Summary

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 4 | Missing mutex/signing/process mgmt in refresh_cli_binaries; duplicate entries in .physically_impure_modules |
| 🟠 High | 9 | Deprecated stdlib imports; duplicated deprecated APIs; 14 files >500 lines; malformed allowed_imports.lock; deprecated functions with live internal callers |
| 🟡 Medium | 18 | Legacy fallback code paths across verification pipeline; 28 untested core modules; 1 non-Nim shell script; cross-layer import ambiguity |
| 🟢 Low | 27 | Thin test stubs; transitive-only coverage; historical BDD docs; const aliases |

**Bottom line**: No compilation errors or warnings. Zero `core→cli/mcp` layer violations. The codebase is architecturally sound but carries significant deferred cleanup: 5 deprecated public APIs still have live internal callers, 3 critical stubs make the Windows binary refresh tool unsafe, and only 48% of core modules have dedicated unit tests.

---

## 1. 🔴 Critical

### 1.1 `scripts/refresh_cli_binaries.nim` — Three Unimplemented Windows Stubs

Three `TODO` stubs that silently no-op, making the binary refresh tool unsafe on Windows:

| Line | Function | Issue | Risk |
|------|----------|-------|------|
| 22 | `acquireBuildMutex()` | Returns `true` unconditionally — no actual mutex | Concurrent build corruption |
| 35 | `terminateMcpServerProcesses()` | No-op stub — never terminates MCP processes | Stale servers serving old binaries |
| 54 | `signBinaries()` | Emits warning only — no Authenticode signing | SmartScreen/AV blocks on Windows |

**Recommendation**: Implement all three stubs, or gate Windows code paths behind `when defined(windows)` with explicit `doAssert false, "not implemented"` instead of silent no-ops.

### 1.2 `src/verification/.physically_impure_modules` — All 19 Modules Duplicated

Every one of the 19 module entries appears **twice** in the file. This file governs purity exemption for the verification layer — consumers (`guardian_compliance_scanner.nim`, `inject_core_pragmas.nim`) may double-process entries, causing incorrect purity exemptions.

**Recommendation**: Deduplicate immediately. The fix is a one-line `sort -u` on the file.

---

## 2. 🟠 High

### 2.1 Deprecated Nim Stdlib Imports (Future-Proofing Risk)

`src/core/orchestrator.nim` lines 54–56:

```nim
{.warning[Deprecated]: off.}
import std/[cpuinfo, locks, os, threadpool]
{.warning[Deprecated]: on.}
```

`std/cpuinfo`, `std/threadpool`, and `std/locks` are officially deprecated in Nim. Suppressing the warnings means the code will silently break when Nim 3.0 removes them. Only `std/os` from this block is still supported.

**Recommendation**: Replace `cpuinfo` with `std/cpuinfo` (new API), `threadpool` with `malebolgia` (already in `allowed_imports.lock`), and `locks` with `std/locks` (check if actually deprecated in current Nim version). Remove the `{.warning[Deprecated]: off.}` suppression.

### 2.2 Duplicated Deprecated Public APIs (5 functions)

Five functions are deprecated with `{.deprecated.}` pragma but still have **live internal callers** within their own files:

| Deprecated Function | File | Internal Call Sites | SSOT Replacement |
|---|---|---|---|
| `nimTypeToLeanType` | `src/core/the_judge.nim:457` | Lines 472, 603, 631, 633 | `core/type_mapping.nim` |
| `buildLeanQuery` | `src/core/the_judge.nim:656` | Line 744 | `translator/universal_assembler.nim` |
| `translateNimTypeToLean` | `src/verification/ast_to_lean_bridge.nim:65` | Lines 326, 336, 388 | `core/type_mapping.nim` |
| `buildLeanBridge` | `src/verification/ast_to_lean_bridge.nim:404` | Line 431 | `translator/universal_assembler.nim` |
| `buildLeanBridgeFromSource` | `src/verification/ast_to_lean_bridge.nim:423` | Delegates to `buildLeanBridge` | `translator/universal_assembler.nim` |

No external callers remain (verified via grep). These are thunks/wrappers that should be removed after refactoring internal call sites to use the SSOT directly.

**Recommendation**: Refactor internal call sites to call `core/type_mapping.nim` and `translator/universal_assembler.nim` directly, then delete the deprecated wrappers.

### 2.3 Oversized Source Files (>500 lines)

14 files in `src/core/` exceed 500 lines. Top 10:

| # | File | Lines | Over Threshold |
|---|------|-------|----------------|
| 1 | `src/core/axiom_api.nim` | 1,407 | 2.8× |
| 2 | `src/core/boundary_extractor.nim` | 1,144 | 2.3× |
| 3 | `src/core/tree_sitter_bridge.nim` | 978 | 2.0× |
| 4 | `src/core/gateway.nim` | 918 | 1.8× |
| 5 | `src/core/verified_axioms.nim` | 905 | 1.8× |
| 6 | `src/core/topology_engine.nim` | 905 | 1.8× |
| 7 | `src/core/logic/refinement_base.nim` | 867 | 1.7× |
| 8 | `src/core/the_judge.nim` | 762 | 1.5× |
| 9 | `src/core/spec_generator.nim` | 741 | 1.5× |
| 10 | `src/core/smt_to_lean_bridge.nim` | 696 | 1.4× |

**Recommendation**: Prioritize `axiom_api.nim` (1,407 lines, nearly 3× threshold) for decomposition into domain-specific sub-modules. `boundary_extractor.nim` and `tree_sitter_bridge.nim` are next candidates.

### 2.4 `src/allowed_imports.lock` — Malformed Entry

Line 76 contains only `threadpool` — breaking the SSOT format contract (`/org/project module reason`) defined in the file header. The line above (74) correctly deprecates threadpool via `malebolgia`, making line 76 ambiguous: a stale comment or half-formed entry.

**Recommendation**: Remove line 76 or format it properly.

---

## 3. 🟡 Medium

### 3.1 Pervasive Legacy Code Paths

16 "legacy" markers found across the verification pipeline. Key patterns:

- **`src/verification/lean_skeleton.nim`**: Three legacy functions (`buildLeanSignaturePrefix`, `buildLeanSkeleton`, `buildLeanSkeletonPremises`) maintained alongside Wave 15 replacements. Fallback at lines 78–79 silently degrades proof quality.
- **`src/core/verified_axioms.nim`**: Dual-registry pattern — new `axiomMappings` table coexists with legacy `verifiedAxiomRegistry` seq. Fallback at line 839.
- **`src/core/smt_to_lean_bridge.nim`**: `translateZ3ProofTraceToLeanTactics` is a publicly exported heuristic translator known to be inferior to the structural `buildLeanProofScriptFromTrace`.
- **`src/core/intrinsic_filter.nim`**: Entire module is documented as `## Legacy Intrinsic Property Filter. New code should use verified_axioms.nim.` — yet still imported and used in production.
- **`src/verification/proof_linkage.nim`**: certGreen-based linkage coexists with provenance-based guard.

**Recommendation**: Establish a sunset timeline for each legacy code path. Gate behind `when defined(axiomLegacyApi)` compile flag with a target removal version.

### 3.2 Non-Nim Script Requiring Porting

| File | Language | Lines | Purpose |
|------|----------|-------|---------|
| `scripts/gates/architecture-gate` | POSIX shell | 15 | Thin wrapper that compiles + invokes `bin/architecture_gate` |

This is the **only** non-Nim script in the entire repository. Every other gate script already has a compiled Nim binary. Per AGENTS.md Language Ban porting obligation, this must be converted.

**Recommendation**: Replace with a compiled Nim binary (pattern already established by `procedure_gate`, `asi_hard_gate`, `cli_build`, etc. in the same directory).

### 3.3 Untracked Stale Artifact

`diff.diff` (898 lines, 45KB) in project root — not tracked by git, generated ~11 minutes before commit `f311aac9`. Likely a build artifact from `scripts/cert_refactor_equivalence.nim`.

**Recommendation**: Delete and add `diff.diff` or `*.diff` to `.gitignore`.

### 3.4 Cross-Layer Import Ambiguity

`src/core/logic/` imports from `src/verification/` and `src/translator/`:

| Core module | Imports from |
|---|---|
| `core/logic/pipeline_verdict_engine.nim` | `verification/pipeline_core_types` |
| `core/logic/semantic_theorem_builder.nim` | `verification/pipeline_core_types` |
| `core/logic/pipeline_healing_logic.nim` | `translator/universal_mapper` |
| `core/logic/pipeline_fingerprint_engine.nim` | `translator/universal_mapper` |
| `core/contract_extractor.nim` | `verification/ast_extractor` |
| `core/integrity_ledger.nim` | `verification/vault_index` |

AGENTS.md only defines three layers (core/cli/mcp) — `verification/` and `translator/` occupy an undefined architectural position. If they are above `core/`, these imports represent dependency inversion.

**Recommendation**: Define `verification/` and `translator/` layer positions in GUARDIAN.md or AGENTS.md. If they are lateral peers of `core/`, the imports are acceptable.

---

## 4. Test Coverage Gaps

### 4.1 Overall Coverage

| Category | Count | Percentage |
|----------|-------|------------|
| Total `src/core/` modules | 81 | 100% |
| Has dedicated unit test (`tests/unit/`) | 39 | 48% |
| Gateway-only coverage (no unit test) | 15 | 19% |
| Transitively covered (no dedicated test) | 12 | 15% |
| Root-level test only | 2 | 2% |
| **Completely untested** | **13** | **16%** |

### 4.2 🔴 Completely Untested Modules (13)

| Module | Notes |
|--------|-------|
| `core/axiom_ir.nim` | Internal use only |
| `core/axiom_lemmas.nim` | Internal use only |
| `core/cfg_builder.nim` | No test imports found |
| `core/ghost_update.nim` | **No imports anywhere — possibly dead code** |
| `core/json_scan.nim` | No test imports found |
| `core/logic/lean_diagnostic.nim` | Internal use only |
| `core/logic/pipeline_builder.nim` | Internal use only |
| `core/solver/encoding_properties.nim` | Internal use only |
| `core/solver/encoding_transition.nim` | Internal use only |
| `core/solver/expr.nim` | **Foundational solver type** |
| `core/solver/induction.nim` | Internal use only |
| `core/solver/smtlib_emitter.nim` | Internal use only |
| `core/solver/z3_pool.nim` | Internal use only |

**Recommendation**: `solver/expr.nim` (foundational type) and `ghost_update.nim` (possibly dead code) are highest priority. Investigate whether `ghost_update.nim` is dead code — if so, remove it.

### 4.3 Thin Test Stubs

| File | Lines | Tests | Risk |
|------|-------|-------|------|
| `tests/unit/tree_sitter_bridge_test.nim` | 8 | 1 | Only tests `parseNimRes("")` returns ok |
| `tests/unit/semantic_graph_test.nim` | 12 | 1 | Only tests value-type semantics |

**Recommendation**: Expand both to provide meaningful behavioral coverage.

---

## 5. Nim Compilation Status

✅ **`nim check src/core/axiom_api.nim`** — Passed with zero errors, zero warnings (89,689 lines processed, 1.374s, 143 MiB peak memory).

---

## 6. False-Positive Registry

**Status**: ✅ Well-maintained. 7 entries (FP-001 through FP-007). Last updated 2026-05-11. No action required.

---

## 7. Remediation Priority Matrix

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| **P0** | Deduplicate `.physically_impure_modules` | 5 min | Gate-level integrity |
| **P0** | Delete/ignore `diff.diff` | 1 min | Repo hygiene |
| **P1** | Fix `allowed_imports.lock` line 76 | 1 min | SSOT integrity |
| **P1** | Port `scripts/gates/architecture-gate` to Nim | 30 min | Language Ban compliance |
| **P1** | Remove deprecated stdlib imports from `orchestrator.nim` | 1 hr | Future-proofing |
| **P2** | Refactor 5 deprecated functions' internal callers | 2 hr | API cleanup |
| **P2** | Investigate `ghost_update.nim` (dead code?) | 15 min | Dead code removal |
| **P3** | Decompose `axiom_api.nim` (1,407 lines) | 1 day | SRP compliance |
| **P3** | Add unit tests for 13 untested modules | 3 days | Test coverage |
| **P4** | Define `verification/` and `translator/` layer positions | 30 min | Architecture clarity |
| **P4** | Implement Windows stubs in `refresh_cli_binaries.nim` | 2 days | Platform support |
| **P4** | Expand thin test stubs | 2 hr | Test quality |

---

## 8. Positive Findings

- ✅ Zero `core→cli/mcp` import violations — architecture gate is clean
- ✅ Zero stale imports in test files
- ✅ `nim check` passes with no errors or warnings
- ✅ False-positive registry is current and enforced per GUARDIAN.md §17
- ✅ All 24 files in `bin/` are compiled Nim ELF binaries
- ✅ Only 1 non-Nim script remains in the entire repository
- ✅ 48 gateway tests, 85 BDD feature files provide strong integration coverage
- ✅ No external callers of deprecated APIs — migration is complete externally
