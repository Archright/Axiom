# Axiom_Enterprise — Technical Debt Comprehensive Audit
# Date: 2026-05-26
# Dimensions Audited: 9 (compiler hygiene, markers, non-Nim, tests, architecture, complexity, deps, docs, existing debt)

===============================================================================
## EXECUTIVE SUMMARY
===============================================================================

Total source files: ~357 .nim in src/
Test files: ~154 real test files
Debt Severity: 3 CRITICAL, 12 HIGH, 25+ MEDIUM, 40+ LOW

===============================================================================

## SCORE CARD (per dimension, A-F)

| Dimension                  | Grade | Critical Items | High | Med | Low |
|----------------------------|-------|---------------|------|-----|-----|
| Compiler Hygiene           | C-    | 4             | 3    | 2   | 1   |
| TODO/HACK/Dead Code        | A-    | 0             | 1    | 2   | 2   |
| Non-Nim Code Porting       | C     | 0             | 1    | 1   | 0   |
| Test Coverage              | F     | 2             | 4    | 3   | 1   |
| Architecture Layers        | A     | 0             | 1    | 0   | 0   |
| Code Complexity            | C-    | 1             | 3    | 2   | 0   |
| Dependency Health          | B     | 1             | 0    | 1   | 1   |
| Documentation              | D+    | 0             | 2    | 2   | 1   |
| OVERALL                    | C-    | 8             | 15   | 13  | 6   |

===============================================================================
## 1. COMPILER HYGIENE — GRADE B+
## 1. COMPILER HYGIENE — GRADE C- (DOWNGRADED)

FULL SCAN RESULT: 549 .nim files. Multiple files DO NOT COMPILE.

CRITICAL — COMPILE ERRORS (exit=1) IN SOURCE FILES:

  CASCADE A: basic_commands_cli.nim:214-216
    → `summaryJson` undeclared, `renderThoughtDashboard` undeclared
    → Breaks 5 CLI modules: basic_commands_cli.nim, action_dispatch_cli.nim,
      action_interpreter_cli.nim, ax.nim, main.nim

  CASCADE B: asset_collector.nim:58
    → `declarationTags` undeclared
    → Breaks 5 modules: asset_collector.nim, cert_builder.nim,
      cert_writer.nim, lean_spec_generator.nim, rebuild_assets.nim

  CASCADE C: thought_dashboard.nim:1
    → Unused strformat, sequtils (error with --warningAsError:UnusedImport)
    → Breaks thought_render.nim, and cascades through CLI modules

  CASCADE D: thought_render.nim:25-31
    → `formatFloat` undeclared (6 call sites), unused reporter, json_utils
    → 23 issues total

  ISOLATED BREAKAGES:
    src/core/cross_validator.nim:53
      → Ambiguous z3OutputToSolverStatus (smt_to_lean_codegen vs translate)
    src/core/gateway_constraint.nim:125-141
      → makeStateConstraint, makeInputConstraint undeclared (18 issues)
    src/core/parsers/tree_sitter/tree_sitter_parser.nim:7
      → Cannot open file: text_utils. 4 unused imports. 12 issues.
    src/core/solver/type_serialize.nim (via types.nim:82)
      → solverStatusString, logicKindString undeclared
    src/mcp/protocol.nim:1 → unused options (cascades to server.nim)
    src/types/symbolic_types_lean.nim:22
      → seImplies undeclared. 5 issues.

  src/core/trusted/path.nim:4 → Deprecated sha1 (use checksums/sha1 instead)
  src/core/trusted/cbor_rfc8949.nim:126 → HoleEnumConv warning
  src/metrics/asi_replayer.nim:104 → duplicate import of 'os'

CASCADING WARNINGS (propagate through 40+ dependent files):
  - orchestrator_topology_emit.nim:19 → unused 'e'
  - global_symbol_graph_builder.nim:14 → unused 'moduleStem'
  - report_render.nim → 10 XCannotRaiseY hints
  - stage_08_reporter.nim:70,75 → deprecated ASI functions
  - asi_cli.nim:371,378,384 → deprecated ASI functions

BROKEN TEST FILES (exit=1 — cannot compile):
  - tests/audit_unification_test.nim (cannot open core/state_manager)
  - tests/ax_tui_reporter_test.nim (cannot open cli/report, 51 issues)
  - tests/unit/topology_engine_test.nim (sorterNodeIdString undeclared)
  - tests/unit/transition_log_test.nim (cannot open core/integrity_ledger)
  - tests/unit/type_system_subdomain_test.nim (no unittest import)
  - tests/unit/wave2_relocation_test.nim (61 issues — multiple undeclared symbols)
  - tests/unit/wf_runners_test.nim (type mismatches, unused import)
  - tests/unit/ula_tautology_bridge_test.nim (type mismatches)
  - tests/unit/universal_assembler_test.nim (type mismatches)

try/except anti-patterns in src/core/:
  - 100 try blocks across 31 files
  - 113 `discard` in except blocks (silent failure swallowing) — HIGH severity

CRITICAL: the previous audit's claim of "27/30 largest clean" ignored the fact
that many CLI entry points and transitive dependencies are BROKEN. The 5 main
CLI modules (main.nim, ax.nim, basic_commands_cli.nim, etc.) cannot be compiled
today.

===============================================================================
## 2. TODO/FIXME/HACK/DEAD CODE — GRADE A-
===============================================================================

CODEBASE_INVENTORY.md written to project root.

| Category           | Count | Severity |
|--------------------|-------|----------|
| TODO               | 2     | Low      |
| FIXME              | 0     | —        |
| HACK               | 0     | —        |
| WORKAROUND         | 2     | Low      |
| DEPRECATED markers | 13    | Medium   |
| when false: blocks | 1     | HIGH     |
| Commented-out code | 3     | Low      |

HIGH: src/cli/wf_runners.nim:245-279 — 35 lines of dead code behind `when false:`
that registers entire CLI workflow commands (scan, prove, verify, report).
Must either re-enable or remove.

MEDIUM: src/core/metrics.nim — 8 deprecated ASI calculation functions
accumulating. src/core/trusted/cbor.nim:35 — Korean TODO for unimplemented
"path restoration logic" in critical CBOR parsing code.

2 WORKAROUND markers in src/gate/macros/cohesion_enforce.nim for Nim 2.x
type inference workaround.

===============================================================================
## 3. NON-NIM CODE PORTING DEBT — GRADE C
===============================================================================

7 files (1,349 lines) must be ported to Nim per AGENTS.md §1.1:

Python scripts (1,045 lines):
  1. analyze_docs.py (323 lines) — documentation coverage analysis
  2. analyze_docs_v2.py (279 lines) — function-level doc analysis
  3. analyze_docs_v3.py (289 lines) — refined doc analysis
  4. coverage_analysis.py (270 lines) — test coverage gap analysis
  5. spot_check.py (84 lines) — manual spot-check validation

Bash scripts (304 lines):
  6. run_nimcheck_all.sh (89 lines) — batch nim check runner
  7. .agents/skills/axiom-quality-gate/scripts/four_dimension_audit.sh (215 lines)

NOTE: vendor/tree-sitter-nim/ contains non-Nim bindings for other ecosystems
(Python, JS, Rust, Go, Swift) — these are third-party, not project debt.
Consider replacing tree-sitter with pure-Nim Dr.Nim compiler API to eliminate
this vendor dependency entirely.

===============================================================================
## 4. TEST COVERAGE — GRADE F (CRITICAL)
===============================================================================

Overall: ONLY 42.3% of source modules have any test import.

| Layer          | Source Files | Tested | Covered % | Uncovered |
|----------------|:-----------:|:------:|:---------:|:---------:|
| src/core/      | 159         | 70     | 44%       | 89        |
| src/verification/ | 70       | 37     | 53%       | 33        |
| src/gate/      | 44          | 8      | 18%       | 36        |
| src/cli/       | 61          | 26     | 43%       | 35        |
| src/mcp/       | 5           | 2      | 40%       | 3         |
| Other          | 18          | 4      | 22%       | 14        |
| TOTAL          | 357         | 147    | 41.2%     | 210       |

CRITICAL GAPS:

a) Entire solver subsystem (12 files under core/solver/) — ZERO test coverage.
   This includes: induction.nim, encoding_properties.nim, smtlib_emitter.nim,
   z3_pool.nim, all expr/construct_*.nim files. This is the mathematical
   verification CORE.

b) Entire verification analyzer pipeline (8 stages: stage_01 through stage_08)
   — ZERO test coverage. These are the core verification workflow stages.

c) Gate modules at 18% coverage — the worst-covered major category.
   Only 4 of 44 gate modules have tests.

d) 3 placeholder test files (1 line each): asi_ssot_unify_test.nim,
   cli_build_test.nim, reasoning_recorder_test.nim

e) 23 test files with zero actual test cases — shell files with setup code
   but no `test "..."` blocks.

f) 38.5% of test files have ≤3 test cases — insufficient coverage depth.

CRITICAL UNTESTED: bmc_engine.nim, bmc_types.nim, cfg_builder.nim,
cross_validator.nim, tautology_checker.nim, smt_to_lean_codegen.nim,
smt_to_lean_translate.nim, the_judge_eval.nim, the_judge_lean.nim,
type_mapping.nim, loop_invariant_synthesis.nim, gate_rules.nim,
translation_validator.nim, integrity_guard.nim, policy_engine.nim.

===============================================================================
## 5. ARCHITECTURE LAYER VIOLATIONS — GRADE A
===============================================================================

1 VIOLATION found across 234 files examined:

  VIOLATION: src/gate/runners/asi_hard_gate.nim:1
  → imports cli/asi_cli (Presentation layer)
  → Gate must be read-only; must not depend on Presentation

No Domain → Infrastructure violations. No circular dependencies in core/.
Architecture enforcement is excellent — just this one outlier to fix.

===============================================================================
## 6. CODE COMPLEXITY — GRADE C-
===============================================================================

28 files exceed 500 lines (splitting threshold):

CRITICAL — function >200 lines:
  1. certificateStatusToProofEntryStatus in report_cli.nim — 399 lines (8x threshold!)
  2. parseAssignmentLine in architecture_policy.nim — 310 lines

Top 5 oversized files:
  1. src/core/axiom_api.nim — 1,408 lines
  2. src/core/boundary_extractor.nim — 1,204 lines
  3. src/verification/lean_lsp.nim — 1,166 lines
  4. src/core/tree_sitter_bridge.nim — 978 lines
  5. src/core/gateway.nim — 918 lines

Deepest nesting:
  - src/verification/lean_skeleton.nim — depth 38 (severe)
  - src/core/contract_ast_extractor.nim — depth 32

73 functions >50 lines (refactoring threshold).

Highest coupling (fan-out):
  - src/cli/wf_state.nim — 21 imports
  - 15 files import 14+ modules

Highest fan-in (most stable/most depended-on):
  - core.results — 82 importers
  - core.constants — 45 importers

===============================================================================
## 7. DEPENDENCY HEALTH — GRADE B
===============================================================================

CRITICAL:
  - `fusion` package is used (src/gate/rule_patterns.nim imports fusion/matching)
    but NOT declared in axiom.nimble `requires` section.

MEDIUM:
  - malebolgia and checksums are declared in requires but NEVER imported
    anywhere in the codebase — dead dependencies.

OK:
  - All deps at latest versions. No version conflicts. No known security issues.
  - 23 packages in ~/.nimble/pkgs2/. nimble.lock exists but missing fusion.

Fix: Add `requires "fusion >= 1.0.0"` to axiom.nimble.
     Consider removing malebolgia, checksums if truly unused.

===============================================================================
## 8. DOCUMENTATION — GRADE D+
===============================================================================

Module-level docs: 231/357 (64%) have module ##-docs. 126 (36%) missing.

Symbol (proc/func) docs: 1,124/2,514 (44%) documented. 1,390 (56%) undocumented.

Worst directories by symbol documentation rate:
  - gate/ — 0%
  - gate/generators/ — 0%
  - gate/macros/ — 0%
  - gate/runners/ — 1%
  - verification/analyzer/ — 0%
  - translator/ — 4%

Core has 103 large (>20 line) undocumented functions totaling ~4,000 lines.

20 files with ZERO documented symbols:
  cli/action_interpreter_cli.nim, cli/cli_types.nim, cli/commands/heal_batch_scheduler.nim,
  cli/evidence_cli.nim, core/asset_collector.nim, core/constants.nim,
  core/integrity_refinement_types.nim, core/logic/pipeline_core_types.nim,
  core/proof_vacuity_gate.nim, core/trusted_base.nim, and 10 others.

===============================================================================
## 9. CARRY-FORWARD: PREVIOUSLY DOCUMENTED OPEN DEBT
===============================================================================

(From docs/reports/* technical debt audits — items NOT yet resolved.)

CRITICAL (3 items):
  LV-001: core/gateway.nim imports verification/state_manager — SoC violation with hardcoded exemption
  LV-002: core/provider_interface.nim calls z3ExecPersistent — DIP violation with hardcoded exemption
  Windows stubs (3): acquireBuildMutex, terminateMcpServerProcesses, signBinaries — all no-op stubs

HIGH (from prior audits, still open):
  1. 6 architecture gate hardcoded exemptions (LV-001 through LV-006)
  2. 14+ oversized files >500 lines (not line-count gated)
  3. 5 deprecated public APIs with live internal callers
  4. Duplicated .physically_impure_modules (19 entries duplicated)
  5. Malformed allowed_imports.lock (threadpool entry, missing strtabs/unicode/malebolgia/Lake)
  6. Deprecated stdlib imports (cpuinfo, threadpool, locks) with warning suppression
  7. ~170 try/except blocks violating GUARDIAN.md §4 (Result/Option-only policy)
  8. Direct file I/O in core (violates GUARDIAN.md §11) — 10+ files
  9. 9 cross-module code duplication pairs
  10. Hardcoded "z3" string branches in gateway, certificate_cli, pipeline_core_types
  11. 16 "legacy" code path markers maintained alongside replacements
  12. FFI outside dedicated wrappers — 5 modules with raw ptr/importc
  13. stale diff.diff (898 lines) in project root
  14. architecture-gate POSIX shell script (15 lines) — non-Nim in scripts/gates/
  15. 8 ACI-heavy functions (ACI >100) needing decomposition

===============================================================================
## PRIORITIZED ACTION LIST (in order of impact)
===============================================================================

=== PHASE 1: IMMEDIATE (this sprint) ===

P1-C0: **FIX BROKEN COMPILATION — 5 CLI entry points + cascading cascade** 
       → basic_commands_cli.nim (`summaryJson`, `renderThoughtDashboard` undeclared)
       → thought_dashboard.nim (unused imports strformat, sequtils)
       → thought_render.nim (`formatFloat` undeclared, 23 issues)
       → asset_collector.nim (`declarationTags` undeclared, cascades to 5 files)
       → gateway_constraint.nim (`makeStateConstraint`, `makeInputConstraint` undeclared)
       → cross_validator.nim (ambiguous z3OutputToSolverStatus)
       → tree_sitter_parser.nim (missing text_utils import)
       → solver/types.nim (solverStatusString, logicKindString undeclared)
       → These are NOT just warnings — these files CANNOT BE COMPILED today.
P1-C1: Write tests for solver/ subsystem (12 files, ZERO coverage)
       → This is the mathematical verification core. Untested = unverified.
P1-C2: Split the 399-line certificateStatusToProofEntryStatus function
       → In report_cli.nim. 8x over threshold.
P1-H1: Fix gate/runners/asi_hard_gate.nim:1 importing cli/asi_cli
       → Only architecture violation found.
P1-C3: Add `requires "fusion >= 1.0.0"` to axiom.nimble
       → Missing dependency that's actively used.

=== PHASE 2: HIGH PRIORITY (next 2 sprints) ===

P2-1: Write tests for verification analyzer pipeline (stage_01 through stage_08)
P2-2: Port 7 non-Nim scripts to Nim (1,349 lines total)
P2-3: Remove dead code: when false block in wf_runners.nim:245-279
P2-4: Address 113 silently swallowed exceptions (discard in except blocks)
P2-5: Split oversized files: axiom_api.nim (1408), boundary_extractor.nim (1204),
      lean_lsp.nim (1166), tree_sitter_bridge.nim (978), gateway.nim (918)
P2-6: Document 20 zero-doc-symbol files + gate/ entire directory (0% docs)

=== PHASE 3: MEDIUM PRIORITY ===

P3-1: Refactor 5 deprecated APIs with live callers to use replacements
P3-2: Clean up duplicated .physically_impure_modules entries
P3-3: Fix malformed allowed_imports.lock
P3-4: Remove dead deps (malebolgia, checksums) or document why kept
P3-5: Extract 73 functions >50 lines
P3-6: Reduce nesting in lean_skeleton.nim (depth 38), contract_ast_extractor.nim (32)

=== PHASE 4: LOW PRIORITY ===

P4-1: Remove stale diff.diff
P4-2: Fix 3 placeholder test files (1-liners)
P4-3: Add tests for 23 test shells with zero assertions
P4-4: Replace hardcoded "z3" strings with config-driven provider selection
P4-5: Resolve 9 cross-module code duplication pairs

===============================================================================
## METRICS DASHBOARD
===============================================================================

Source files:        357 .nim (src/)
Total lines:         ~85,000 (estimated)
Test files:          154 real, 3 placeholder, 23 zero-assertion
Coverage rate:       42.3% (by module import)
nim check warnings:  12 (all deprecated APIs)
Architecture violations: 1
TODO markers:        2
DEPRECATED markers:  13
when false: blocks:  1
Silent exceptions:   113
Non-Nim files:       7 (1,349 lines to port)
Functions >50 lines: 73
Files >500 lines:    28
Missing docs:        126 files (36%), 1,390 symbols (56%)
try/except blocks:   ~170
===============================================================================
