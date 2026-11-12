# Full Debt Scan — 2026-06-12

> **Scope**: Entire Axiom-core codebase (543 src/ modules, 221 test modules, 76,053 lines)
> **Method**: 7 parallel explore agents + direct shell scans
> **Previous scan**: 2026-06-07 (verifications/*_debt_scan_2026_06_07.txt)

---

## Executive Summary

| Category | Open Findings | Critical | High | Medium | Low |
|----------|--------------|----------|------|--------|-----|
| Architecture | 8 | 2 | 2 | 3 | 1 |
| Code Complexity | 5 | 0 | 2 | 2 | 1 |
| Test Coverage | 6 | 1 | 3 | 2 | 0 |
| Effect System | 8 | 1 | 2 | 3 | 2 |
| Documentation | 7 | 1 | 2 | 3 | 1 |
| Structural | 5 | 0 | 1 | 3 | 1 |
| Gate Infrastructure | 5 | 1 | 1 | 2 | 1 |
| **TOTAL** | **44** | **6** | **13** | **18** | **7** |

---

## 1. Architecture Debt

### 🔴 Critical

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| A1 | **Import Encapsulation Violations** | 270 files | `core/orchestration/`, `core/gateway/` directly import `verification/` modules instead of going through hub modules. Worst: `cli_bridge.nim` (81 imports), `verification_facade.nim` (49 imports) |
| A2 | **SoC Layer Breach (core→verification)** | 5 files, 18+ imports | `core/orchestration/`, `core/gateway/` importing from `verification/` breaks Domain←Infrastructure boundary |

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| A3 | **SoC Layer Breach (core→sieve)** | 2 files | `core/solver/` and `core/diagnostics/` importing from `sieve/` |
| A4 | **500+ Line Files** | 1 file | `verification/batch_uap_orchestrator.nim` (513 lines) — only 1 file over threshold (down from 30+) |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| A5 | **Include Statements Remain** | 1 file | `core/encoding/smt_to_lean_codegen.nim:192` — `include core/encoding/smt_to_lean_codegen_part1` (should be import/export) |
| A6 | **SoC Violation (cli→gate)** | 1 file | Minor CLI→gate import |
| A7 | **Triple-import Redundancy** | 3 files | `scribe.nim`, `detective.nim`, `swat.nim` each import `core/types/persona_interface` 3 times |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| A8 | **Forwarding Stubs Clean** | src/core/*.nim | 18 stubs in src/core/ root — all contain only import+export ✅ |

---

## 2. Code Debt

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| C1 | **High Coupling Modules** | 15 files | Modules with 21-81 imports: `cli_bridge.nim`(81), `verification_facade.nim`(49), `wf_runners_common.nim`(48), `universal_pipeline.nim`(44), `batch_uap_orchestrator.nim`(35) |
| C2 | **Orphan Modules (Zero Importers)** | 20+ files | `src/cli/convergence_sidecar.nim`, `src/cli/execution_policy.nim`, `src/mcp/server.nim`, `src/core/telemetry/trace_normalizer.nim`, 8 `verification/analyzer/stage_*.nim`, `verification/cert_builder.nim`, `verification/lean_spec_generator.nim`, etc. |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| C3 | **Hardcoded Paths** | 2 files | `core/identity/tree_sitter_path.nim` has `/usr/local/lib/tree-sitter-nim/parser` and `/usr/local/lib/tree-sitter-lean/parser` |
| C4 | **TODO/FIXME Comments** | 1 src file | `verification/pipeline_transition_engine.nim:115` — `TODO(postArt.resultArtifact.len > 0)` |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| C5 | **Empty Directories** | 0 | Clean ✅ |

---

## 3. Test Debt

### 🔴 Critical

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| T1 | **@executable Features Without Runners** | 92 of 128 | 75.8% of non-@manual features have no gateway test runner. 139 features total, 11 @manual, only 36 runners exist |

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| T2 | **Stub Test Files** | 3 files | `tests/unit/sorter_test.nim` (discard-only), `tests/unit/architecture_gate_test.nim` (stub), `tests/unit/example.nim` (not a test) |
| T3 | **Zombie Imports** | 7+ test files | `asi_cache_test`, `asi_repair_test`, `auto_recertify_test`, `bundle_compiler_test`, `bundle_compiler_bdd_test`, `axiom_contract_test`, `domain_types_test` import deleted modules |
| T4 | **`check true` Placeholders** | 5 occurrences in 3 files | `ax_cached_flag_feature_test`, `ax_command_surface_feature_test`, `axiom_pragmas_test` |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| T5 | **TODO in Tests** | 5 occurrences | Remaining TODO markers in test files |
| T6 | **`when isMainModule` in Core** | 4 violations | Non-I/O-boundary modules using `when isMainModule` |

---

## 4. Effect System Debt

### 🔴 Critical

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| E1 | **Missing `{.raises: [].}`** | 1,729 / 2,923 (59%) | Systematic annotation pass needed across all layers |

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| E2 | **`{.raises: [Exception].}`** | 16 occurrences | Should use specific error types, not broad Exception |
| E3 | **Bare `except:` Clauses** | 17 occurrences in 3 files | `core/audit/governance_engine.nim` (4), `core/audit/sad_gate.nim` (9), `gate/runners/hotspot_enforcement_gate.nim` (6). Should be `except CatchableError:` |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| E4 | **`proc` → `func` Candidates** | 205 in src/core/ | Pure computation procs that should be converted to func |
| E5 | **Missing `{.acyclic.}`** | 5 ref object types | `pipeline_types.nim`, `tree_sitter_ast_bridge.nim`, `type_registry.nim`, `layer_guard.nim`, `universal_pipeline.nim` |
| E6 | **`cast(gcsafe)`** | 8 occurrences | 5 justified (gate_registry, judge), 3 need review |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| E7 | **`except Exception`** | 7 (5 justified, 2 concern) | `stdlib_shield.nim` (intentional isolation), `nimtry_extract_part3_part2.nim` (1 unexplained) |
| E8 | **`cast(noSideEffect)`** | 1 | `sieve/ast_inspector.nim:137` — hides file I/O |

---

## 5. Documentation Debt

### 🔴 Critical

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| D1 | **GUARDIAN.md Missing** | Referenced 10+ times | AGENTS.md and docs/agents/ reference a non-existent "absolute law" document |

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| D2 | **AGENTS.md Stale Paths** | 5 paths | `bin/nimtry`, `tools/check_import_encapsulation.py`, `bin/validate-architecture`, `bin/architecture_gate`, `src/gate/architecture_guard.nim` — referenced but may not exist |
| D3 | **docs/spec Stale References** | 28 stale paths across 10 files | Misleading for agents reading specs |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| D4 | **Missing Specs** | 3 subsystems | `gate/`, `api/`, `cli/` lack dedicated spec docs |
| D5 | **Missing Module Docs** | ~15 non-stub files | Legislator, Lean LSP client, etc. lack ## module-level doc comments |
| D6 | **i18n Incomplete** | ~6 sections | Korean localization partial (~48 keys, needs ~150+) |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| D7 | **verifications/ Naming** | 20 files | Files without date in filename — auditability issue |

---

## 6. Structural Debt

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| S1 | **Orphan Analyzer Stages** | 8 files | `verification/analyzer/stage_01~08_*.nim` — zero importers. May be dynamically loaded or dead code |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| S2 | **Quarantine Approaching Expiry** | 2 dirs | `2026_06_07/` (4 days), `2026_06_08/` (3 days) — approaching 5-day quarantine period |
| S3 | **`allowed_imports.lock` Missing** | gate/ | Referenced in AGENTS.md but file does not exist |
| S4 | **Forwarding Stubs Clean** | 18 files | src/core/ root stubs all contain only import+export ✅ |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| S5 | **Empty Directories** | 0 | Clean ✅ |

---

## 7. Gate Infrastructure Debt

### 🔴 Critical

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| G1 | **16 Missing Binary Entry Points** | bin/ | `nimtry`, `architecture-guard`, `nim-check`, `spec-binding-gate`, `gateway-test`, etc. — all bin/* gates are compiled at build time, not present in repo |

### 🟡 High

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| G2 | **72+ Features Without Runners** | tests/features/ → tests/gateway/ | Only 36 runners for 128 non-@manual features (28% coverage) |

### 🟡 Medium

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| G3 | **DRY Violation** | 2 files | `wrapWithCgroupsIfAvailable` defined in both `orchestrator_hook_part1.nim` and `gate_hook.nim` |
| G4 | **No Per-Gate Timeout in GateConfig** | orchestrator_hook_part1.nim | Timeouts hardcoded via gate-id checks, not data-driven |

### 🟢 Low

| # | Finding | Location | Detail |
|---|---------|----------|--------|
| G5 | **gate_self_check Threshold Mismatch** | gate_self_check.nim | `fileSize < 100_000` check flags hooks that are intentionally <5KB |

---

## Priority Action Items (Top 10)

| Priority | ID | Action | Effort | Impact |
|----------|----|--------|--------|--------|
| P0 | E1 | Systematic `{.raises: [].}` annotation pass (1,729 funcs) | Large | Effect safety |
| P0 | T1 | Implement missing test runners or downgrade features to @manual | Large | Test coverage |
| P0 | A1 | Fix import encapsulation violations in core/orchestration/ | Medium | Architecture integrity |
| P1 | E3 | Convert 17 bare `except:` to `except CatchableError:` | Small | Effect safety |
| P1 | T2 | Delete 3 stub test files | Small | Test quality |
| P1 | T3 | Fix 7 zombie test imports | Small | Build health |
| P1 | D1 | Resolve GUARDIAN.md references (create or remove) | Small | Documentation |
| P2 | E5 | Add `{.acyclic.}` to 5 ref object types | Small | Performance |
| P2 | C1 | Reduce coupling in top-5 high-import modules | Medium | Maintainability |
| P2 | S3 | Create or remove `allowed_imports.lock` | Small | Gate integrity |

---

## Compared to Previous Scan (2026-06-07)

| Category | 2026-06-07 | 2026-06-12 | Trend |
|----------|------------|------------|-------|
| Architecture | 12 findings | 8 findings | ✅ Improved |
| Code | 8 findings | 5 findings | ✅ Improved |
| Test | 10 findings | 6 findings | ✅ Improved |
| Effect System | 10 findings | 8 findings | ✅ Slightly improved |
| Documentation | 10 findings | 7 findings | ✅ Improved |
| Structural | 8 findings | 5 findings | ✅ Improved |
| Gate | 8 findings | 5 findings | ✅ Improved |

**Overall**: 66 → 44 findings (33% reduction). Major wins in architecture (include elimination, stub cleanup) and test (stub deletion). The largest remaining debt is effect system annotations (1,729 missing `{.raises: [].}`) and test runner coverage (72+ features without runners).

---

*Generated: 2026-06-12T11:25:00+09:00*
*Method: 7 parallel explore agents + direct shell analysis*
