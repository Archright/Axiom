# Axiom Technical Debt Full Audit Report — 2026-06-01

> **Scope**: Full codebase (`src/`, `tests/`, `scripts/`) — 496 `.nim` source files  
> **Method**: 6 parallel scan agents covering 8 debt categories  
> **Baseline**: Previous audit 2026-05-30 (88 items, 86 Closed, 2 Partial)

---

## Executive Summary

| Metric | Previous (2026-05-30) | Current (2026-06-01) | Delta |
|--------|----------------------|---------------------|-------|
| Total registered items | 88 | 88 (existing) + **16 new** | +16 |
| Critical (P0) | 0 open | **3 new** | +3 |
| High (P1) | 0 open | **5 new** | +5 |
| Medium (P2) | 0 open | **5 new** | +5 |
| Low (P3) | 0 open | **3 new** | +3 |

**Previous 88 items remain Closed.** No regressions detected.

### Top 3 Critical Findings

1. **`{.raises: [].}` coverage at 33%** — 1,889 of 2,801 funcs/procs lack the annotation (AGENTS.md §0.6 violation)
2. **373 `except Exception` catches** — 83 in `src/core/` domain layer alone (over-broad, catches Defects)
3. **52 proc→func conversion candidates** — 26 Tier 1 (no I/O, no raises pragma)

---

## Category 1: Code Size (Large Files)

**Result**: 1 open debt item (down from prior audit)

| File | Lines | Status |
|------|-------|--------|
| `src/cli/cst_cli.nim` | 517 | 🔴 **DEBT** — should be split into `_parts/` |
| `src/verification/analyzer.nim` | 505 | ✅ EXEMPTED (already split) |
| `src/core/verified_axioms_catalog.nim` | 505 | ✅ EXEMPTED (pure data table) |

Threshold-adjacent files (490-499 lines): `architecture_ast_extractor.nim` (499), `recertify_lean.nim` (493), `lean_lsp.nim` (491).

---

## Category 2: TODO/FIXME/HACK Markers

**Result**: 4 actionable items (down from prior 481+ stubs)

| Location | Marker | Content |
|----------|--------|---------|
| `tests/gateway/asi_hard_gate_feature_test.nim` | TODO | `implement actual verification` (stub placeholder) |
| `tests/gateway/asi_ssot_feature_test.nim` | TODO | `implement actual verification` (stub placeholder) |
| `tests/gateway/topology_cache_feature_test.nim` | TODO | `implement actual verification` (stub placeholder) |
| `tests/gateway/proof_preserving_fingerprint_feature_test.nim` | TODO | `implement actual verification` (stub placeholder) |

All 4 are outputs of `scripts/fix_medium_debt.py` (stub→placeholder conversion). `src/` tree is **clean — zero markers**.

---

## Category 3: proc→func Conversion (AGENTS.md §0.6)

**Result**: 52 actionable conversions identified

### Layer Health

| Layer | Procs | Funcs | func:proc | Health |
|-------|-------|-------|-----------|--------|
| `src/core/` | 210 | 1,068 | 5.1:1 | ✅ Best |
| `src/cli/` | 205 | 405 | 2.0:1 | ⚠️ I/O-heavy |
| `src/verification/` | 206 | 283 | 1.4:1 | ⚠️ |
| `src/gate/` | 219 | 115 | 0.5:1 | ❌ More procs than funcs |
| `src/mcp/` | 25 | 26 | 1.0:1 | ⚠️ |
| **Total** | **895** | **1,981** | **2.2:1** | |

### Tier 1: No I/O + Missing Raises (26 procs)

| File | Count |
|------|-------|
| `orchestrator_parts/orchestrator_part1.nim` | 6 |
| `orchestrator_parts/orchestrator_part2.nim` | 4 |
| `orchestrator_topology_emit.nim` | 4 |
| `reasoning_recorder.nim` | 2 |
| `solver/wrappers.nim` | 2 |
| `architecture_policy_parts/architecture_policy_part1.nim` | 2 |
| `the_judge_eval.nim` | 2 |
| Others (6 files) | 4 |

### Tier 2: Has `{.raises: [].}` But Still `proc` (26 procs)

| File | Count |
|------|-------|
| `provider_interface.nim` | 5 |
| `solver/wrappers.nim` | 3 |
| `the_judge_eval.nim` | 3 |
| `reasoning_recorder.nim` | 2 |
| `logic/pipeline_trace_artifacts.nim` | 2 |
| Others | 11 |

---

## Category 4: Unused Imports & Dead Code

### Unused Imports

**Hotspot files** (highest-confidence unused imports):

| File | Unused Imports |
|------|---------------|
| `src/core/axiom_api_session.nim` | 10 (expression_parser, domain_types, json_scan_parse, session_parser, results, bmc_race, solver_bridge, solver/types, constants, vault_factory) |
| `src/cli/action_output_cli.nim` | 10+ |
| `src/core/boundary_extractor.nim` | 9 |
| `src/core/axiom_api.nim` | 8 |
| `src/cli/action_dispatch_cli.nim` | 8 |
| `src/gate/gate_rules.nim` | 7 |
| `src/gate/ast_architecture_gate.nim` | 6 |

Total heuristic estimate: ~1,212 flagged (many false positives from qualified access patterns).

### Dead Code

| Type | Count |
|------|-------|
| `when false:` blocks | **0** ✅ |
| Commented-out code | **0** (explanatory comments only) ✅ |
| Zero-importer modules | **4-6 confirmed** (see below) |
| Stub files (< 10 lines) | **18** |

**Confirmed dead modules** (zero references in `src/`):

| File | Lines | Action |
|------|-------|--------|
| `src/api.nim` | 3 | Delete — dead entry stub |
| `src/core/cross_validator.nim` | 86 | Delete — zero importers |
| `src/core/concurrency_adapter.nim` | 23 | Delete — zero importers |
| `src/cli/sorter.nim` | 6 | Delete — dead stub |
| `src/cli/axiom_unified.nim` | ? | Verify — zero importers |
| `src/cli/progress_reporter_proof.nim` | ? | Verify — zero importers |

---

## Category 5: Missing `{.raises: [].}` Pragma

**Result**: 1,889 of 2,801 declarations (67%) missing

| Directory | Missing | Total | % Missing |
|-----------|---------|-------|-----------|
| `src/core/` | 706 | 1,278 | 55% |
| `src/cli/` | 540 | 610 | 89% |
| `src/verification/` | 313 | 489 | 64% |
| `src/gate/` | 219 | 334 | 66% |
| `src/mcp/` | 41 | 51 | 80% |
| `src/personas/` | 9 | 9 | 100% |
| `src/frontend/` | 0 | 12 | **0%** ✅ |

**Note**: 266 functions use `{.nosideeffect.}` without `{.raises: [].}` — weaker contract.

### Files With Most Missing Pragmas

| File | Missing Pragmas |
|------|----------------|
| `solver/z3_pool.nim` | 18 |
| `sync_utils_process.nim` | 9 |
| `gate_memo.nim` | 9 |
| `sync_utils_resource.nim` | 8 |
| `orchestrator_parts/orchestrator_part1.nim` | 6 |
| `orchestrator_vault.nim` | 4 |

---

## Category 6: Architecture Violations

### SoC (Separation of Concerns) — 1 Active Violation

| File | Line | Violation |
|------|------|-----------|
| `src/core/orchestrator_topology_worker.nim` | 11 | `import ../verification/cegar_engine` — Domain importing Infrastructure |

✅ No violations for `core/ → cli/`, `core/ → gate/`, `core/ → mcp/`.

### DRY — 2 Critical Duplicates

| Function | Occurrences | Files |
|----------|-------------|-------|
| `axFrontierEntryForMetric` | 8 defs | 4 `topology_cli_parts/` files |
| `getEngineAsiFixed4` | 4 defs | `asi_cli.nim` + 3 `asi_cli_parts/` files |

**Moderate duplicates** (3 each): `computeSha256Hex`, `toJsonNode`, `getFingerprintSeed` (5 files), `syncVaultToProofState`, `mergeTransitionLogIntoProofState`.

Many are artifacts of `_parts` file splitting — not logical duplicates but structural debt.

### SSOT — 2 Candidate Duplicates

| Type | Occurrences | Risk |
|------|-------------|------|
| `WorkflowResult` | 2 modules | LOW — likely different namespaces |
| `WorkflowEntry` | 2 modules | LOW |

### Hardcoded Paths — 39 Instances

| Pattern | Files | Severity |
|---------|-------|----------|
| `"src/cli/main.nim"` | 4 asi_cli_parts | MEDIUM |
| `"src/verification/spec.lean"` | certificate_cli | MEDIUM |
| `"src/verification\"` (Windows path!) | certificate_cli_part5 | **HIGH** — cross-platform bug |
| `"src/core/unknown.nim"` | integrity_cli | LOW |

### Build Artifacts in `src/`

15 ELF binaries found in `src/` (not git-tracked). Root cause: `nim c -o:src/...` placement.

---

## Category 7: Exception Handling

| Pattern | Count | Assessment |
|---------|-------|------------|
| `except Exception` | **373** | ❌ Over-broad — catches Defects |
| `except CatchableError` | 54 | ✅ Correct |
| Bare `except:` | 0 | ✅ None |

**By layer**:

| Layer | `except Exception` | Severity |
|-------|-------------------|----------|
| `src/core/` | 83 | 🔴 CRITICAL — domain must be pure |
| `src/verification/` | 100 | 🔴 HIGH |
| `src/cli/` | 128 | 🟡 MEDIUM (presentation boundary) |
| `src/gate/` | 37 | 🟡 MEDIUM |
| `src/mcp/` | 16 | 🟡 LOW |

Only 13% of exception handlers use the correct `CatchableError`.

---

## Category 8: Deprecated Code

**5 deprecated functions in `src/core/metrics.nim`** — all point to `computeInformationGainWeightedAsi`, zero external callers except a self-ref on line 100. **Safe to delete.**

No other active deprecated symbols with live callers found.

---

## Consolidated Priority Matrix

| Priority | ID | Issue | Count | Effort | Action |
|----------|----|-------|-------|--------|--------|
| **P0** | DEBT#089 | Missing `{.raises: [].}` | 1,889 | Batch script | Add to all `func`; revert failures |
| **P0** | DEBT#090 | `except Exception` in core/ | 83 | Manual | → `except CatchableError` |
| **P0** | DEBT#091 | Pure procs without raises (Tier 1) | 26 | Batch | proc→func + add raises |
| **P1** | DEBT#092 | `except Exception` in verification/ | 100 | Manual | → `except CatchableError` |
| **P1** | DEBT#093 | SoC violation: core→verification | 1 | Manual | Extract adapter |
| **P1** | DEBT#094 | DRY: `axFrontierEntryForMetric` ×8 | 8 | Manual | Extract to shared module |
| **P1** | DEBT#095 | DRY: `getEngineAsiFixed4` ×4 | 4 | Manual | Deduplicate |
| **P1** | DEBT#096 | `asi_cli.nim` 517 lines (over threshold) | 1 | Manual | Split into `_parts/` |
| **P2** | DEBT#097 | Hotspot unused imports (top 7 files) | ~68 | Manual | Remove confirmed unused |
| **P2** | DEBT#098 | Dead modules (cross_validator, etc.) | 4-6 | Trivial | Delete |
| **P2** | DEBT#099 | Hardcoded paths (39 instances) | 39 | Semi-auto | Extract to constants |
| **P2** | DEBT#100 | Windows-style path in certificate_cli_part5 | 1 | Trivial | Fix path separator |
| **P2** | DEBT#101 | 15 build artifacts in src/ | 15 | Trivial | Redirect -o: to build/ |
| **P3** | DEBT#102 | Deprecated functions in metrics.nim | 5 | Trivial | Delete |
| **P3** | DEBT#103 | 4 TODO stubs in test files | 4 | Low | Implement or delete |
| **P3** | DEBT#104 | SSOT candidates (WorkflowResult/Entry) | 2 | Low | Verify namespaces |

---

## Comparison With Previous Audit

| Category | 2026-05-30 | 2026-06-01 | Trend |
|----------|-----------|-----------|-------|
| Large files (500+) | Multiple | **1 open** | ✅ Improved |
| TODO/FIXME markers | 481+ stubs | **4 placeholders** | ✅ Improved |
| Dead code | Multiple | **4-6 modules** | ✅ Improved |
| Architecture violations | Multiple | **1 SoC + 2 DRY** | ✅ Improved |
| `{.raises: [].}` coverage | Unknown | **33%** (measured) | 🆕 Baseline |
| `except Exception` | Unknown | **373** (measured) | 🆕 Baseline |
| proc→func candidates | Unknown | **52** (measured) | 🆕 Baseline |

**Key insight**: Prior audit resolved 86/88 items. This audit surfaces deeper systemic debt (effect system coverage, exception hygiene) that was not measured before. The codebase structural quality (file size, dead code, architecture) has improved significantly; the remaining debt is primarily in **effect system compliance**.
