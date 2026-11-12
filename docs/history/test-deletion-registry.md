# Test Deletion Registry

> Append-only registry of permanently deleted test files.  
> Purpose: Prevent accidental restoration by future session agents.  
> Authority: AGENTS.md §0.7 (Business-Only Test Scope), §0.8 (No Stub Files).

---

## Batch 1 — 2026-05-30: Drifted Deprecated Tests (20 files)

**Commit**: `delete(tests): remove 20 drifted deprecated tests`  
**Authority**: AGENTS.md §0.7, §0.8  
**Reason**: These tests verify behaviors that were intentionally changed or removed. Restoring them would require reverting correct code changes.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/deprecated/asi_cli_test.nim` | ASI tautology (DEBT#002); behavior intentionally changed | HIGH — would revert ASI hard gate suspension |
| `tests/deprecated/boundary_extractor_gateway_test.nim` | `bcPartialHavoc` vs `bcComplete` enum changed | HIGH — would revert boundary enum redesign |
| `tests/deprecated/certificate_graph_boundary_test.nim` | `certStale` vs `certVerifiedAxiom` logic changed | HIGH — would revert certificate status model |
| `tests/deprecated/deterministic_purge_feature_test.nim` | Marker format/rules changed; 45 markerFailures obsolete | HIGH — would revert marker policy |
| `tests/deprecated/gateway_mcp_core_test.nim` | MCP core contract changed | HIGH — would revert MCP protocol |
| `tests/deprecated/gateway_pipeline_test.nim` | `withdraw.nim`, `payments.nim` sample files removed | MEDIUM — sample files permanently deleted |
| `tests/deprecated/gateway_topology_verify_test.nim` | Topology targets moved; report empty by design | MEDIUM — topology engine redesigned |
| `tests/deprecated/heal_recovery_contract_feature_test.nim` | Lean query variable declarations mismatch (bridge changed) | HIGH — would revert Lean bridge |
| `tests/deprecated/intrinsic_filter_hint_test.nim` | Skeleton `endsWith` mismatch (format changed) | MEDIUM — skeleton format evolved |
| `tests/deprecated/ledger_inlining_feature_test.nim` | Feature file content missing; migration tracker | LOW — migration complete |
| `tests/deprecated/mirror_shield_test.nim` | Legacy certificate format removed | HIGH — would revert certificate format |
| `tests/deprecated/nimtry_regression_test.nim` | AST verdicts drifted; policy changed | HIGH — would revert nimtry policy |
| `tests/deprecated/prove_heal_unification_feature_test.nim` | `healScheduleTier` count mismatch (scheduler logic changed) | HIGH — would revert scheduler |
| `tests/deprecated/report_cli_test.nim` | Auto-repaired fingerprint mismatches feature removed | MEDIUM — feature intentionally removed |
| `tests/deprecated/smt_to_lean_type_aware_test.nim` | `exact h0` missing (SMT→Lean mapping changed) | HIGH — would revert SMT→Lean mapping |
| `tests/deprecated/tech_debt_remediation_feature_test.nim` | Migration tracker; remediation complete | LOW — migration complete |
| `tests/deprecated/transpilation_layer_test.nim` | Axiom linkage hash algorithm changed | HIGH — would revert hash algorithm |
| `tests/deprecated/vacuity_ban_feature_test.nim` | ASI tautology (DEBT#002); behavior intentionally changed | HIGH — would revert ASI hard gate suspension |
| `tests/deprecated/verified_axiom_test.nim` | Axiom name mismatch (`nim.string.len.isNat` vs `string-length-nonneg`) | HIGH — would revert axiom naming |
| `tests/deprecated/architecture_refactor_feature_test.nim` | Migration tracker; architecture refactor complete | LOW — refactor complete |

**DO NOT RESTORE** without: (a) root-cause analysis proving the behavior change was a bug, AND (b) `bin/procedure_gate` pass after restoration.

---

## Batch 2 — 2026-05-30: Zombie Test (1 file)

**Commit**: `delete(tests): remove zombie test ssot_convergence_feature_test`  
**Authority**: AGENTS.md §0.7  
**Reason**: No matching `tests/features/*.feature` file exists. Test is untraceable.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/gateway/ssot_convergence_feature_test.nim` | No matching `.feature` file | MEDIUM — would require creating a new feature file |

---

## Batch 3 — 2026-05-30: Stub Files (~109 files)

**Commit**: `delete(tests): remove 109 stub files (≥50% check true/false)`  
**Authority**: AGENTS.md §0.8  
**Reason**: Unimplemented stubs with >50% `check true/false` density. They are feature-request bookmarks, not regression guards.

| File Pattern | Count | Deletion Reason |
|--------------|-------|-----------------|
| `tests/gateway/*_feature_test.nim` with stub ratio ≥ 50% | 109 | AGENTS.md §0.8 automatic FAIL |

**Partial list of representative stubs**:
- `orchestrator_feature_test.nim` (22/22 check true)
- `architecture_gate_feature_test.nim` (18/18 check true)
- `header_body_split_feature_test.nim` (17/17 check true)
- `smt_to_lean_direct_mapping_feature_test.nim` (15/15 check true)
- `transpilation_layer_feature_test.nim` (15/15 check true)
- `boundary_extractor_feature_test.nim` (12/12 check true)
- `integrity_guard_feature_test.nim` (10/12 check true)
- `final_extinction_feature_test.nim` (10/10 check true)
- `refinement_types_feature_test.nim` (10/10 check true)
- `wave10_pdc_feature_test.nim` (10/10 check true)

**Full list**: See git diff for commit.

**DO NOT RESTORE** without: (a) real assertions replacing all `check true/false`, AND (b) traceable `.feature` scenario, AND (c) `bin/procedure_gate` pass.

---

## Protected Files (Anti-Resurrection Guard)

The following files remain as canonical evidence and MUST NOT be deleted:

| File | Purpose |
|------|---------|
| `tests/deprecated/README.md` | Sentinel — lists deleted files with rationale |
| `docs/history/test-deletion-registry.md` | This file — append-only deletion registry |
| `src/gate/deleted_tests.lock` | Gate-level resurrection detection (future) |

---

## Resurrection Prevention Checklist

If a future agent proposes restoring a deleted test, require ALL of the following:

1. [ ] The test is listed in this registry with a documented deletion reason.
2. [ ] The agent provides evidence that the deletion reason no longer applies.
3. [ ] The agent runs `src/gate/nimtry/nimtry_cli.nim` (if architecture-related) or `bin/procedure_gate` (if procedure-related) and shows PASS.
4. [ ] The agent updates this registry with a "Restored" entry (date, agent, justification).
5. [ ] `nimble test` passes after restoration.

---

## Batch 4 — 2026-05-30: Stub Deprecated Tests (3 files)

**Commit**: `delete(tests): remove 3 stub deprecated tests`  
**Authority**: AGENTS.md §0.8  
**Reason**: After Phase 2 nimtry audit, these tests were found to be 100% `check true` stubs with no meaningful assertions. They were already non-functional before deprecation.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/deprecated/architecture_gate_ast_superiority_test.nim` | 100% stub (9/9 `check true`) | LOW — no assertions to restore |
| `tests/deprecated/architecture_gate_synthetic_probe_test.nim` | Includes ast_superiority (stub) | LOW — no independent assertions |
| `tests/deprecated/architecture_gate_test.nim` | 100% stub (8/8 `check true`) | LOW — no assertions to restore |

**DO NOT RESTORE** without: real assertions, traceable `.feature`, and `src/gate/nimtry/nimtry_cli.nim` PASS.

---

## Restored Tests (2026-05-30)

The following tests were moved from `tests/deprecated/` back to `tests/gateway/` after repair:

| File | Repair Description |
|------|-------------------|
| `tests/gateway/architecture_gate_zero_tolerance_test.nim` | Updated `coreLimit.maxExportedFunctions` expectation from 30 to 15 (policy change) |
| `tests/gateway/architecture_policy_test.nim` | Fixed `layer` parsing bug in `src/gate/architecture_policy.nim` (now parses arrays correctly); re-enabled `malformed glob` validation |

**Restoration Authority**: Plan Phase 2 audit — `src/gate/nimtry/nimtry_cli.nim` reports 0 violations on current codebase; test expectations were stale, not gate code.

## 2026-06-03 — Zombie Gateway Tests Removed

### Deleted Files
- `tests/gateway/architecture_policy_test.nim`
- `tests/gateway/architecture_gate_feature_test.nim`

### Deletion Reason
`architecture_policy` gate was completely removed from `src/gate/manifest.d/_index.json` SSOT. The module `gate/architecture_policy` no longer exists, making these tests un-compilable zombies per AGENTS.md §0.7 (Business-Only Test Scope). No replacement module exists.

### Restoration Risk
Low. If `architecture_policy` is reintroduced as a gate, the tests must be rewritten against the new module path and schema.

### SSOT Authority
`src/gate/manifest.d/_index.json` (active gate registry) — `architecture_policy` absent from `allGates()` sequence.

---

## 2026-06-05 — T-004: Zombie Session Parser Test Removed

### Deleted Files
- `tests/unit/session_parser_test.nim`

### Deletion Reason
Resurrected zombie per DEBT#119. 9-line stub: empty test body + `check true`. Verifies nothing.

### Restoration Risk
None. Test was a stub with zero assertions.

### SSOT Authority
AGENTS.md §0.7 (Business-Only Test Scope), §0.8 (No Stub Files).

---

## 2026-06-05 — A-010: Unused `src/metrics/asi_replayer.nim` Quarantined

### Quarantined Files
- `src/metrics/asi_replayer.nim` → `experimental/pending_deprecation/2026_06_05/asi_replayer.nim`

### Quarantine Reason
Zero imports across entire `src/` tree. No module references `metrics/asi_replayer`. Ghost directory `src/metrics/` contained only this file.

### Restoration Risk
Low. Module was dead code. If ASI replayer functionality is needed, it should be integrated into the existing `core/metrics` SSOT.

### SSOT Authority
AGENTS.md §1.2 (Experimental Zone Sub-structure), §2.2 #3a (Annals Write-Back).

---

## Batch 5 — 2026-06-12: Zombie Runners (56 files)

**Authority**: AGENTS.md §0.7 (Business-Only Test Scope), §2.7 (Gherkin Tag Schema)
**Reason**: All matching `tests/features/*.feature` files are tagged `@legacy` or `@manual`. Per the Gherkin Tag Schema, `@manual` features require no automated runner, and `@legacy` features are retired. These runners are zombies — they execute against retired or manual-only feature specifications.
**Note**: nimtry policy parsing error prevented automated detection. Deletion performed via manual tag analysis of all feature files.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/gateway/anti_tautology_sentinel_feature_test.nim` | Feature `anti_tautology_sentinel.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/asi_hard_gate_feature_test.nim` | Feature `asi_hard_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/asi_ssot_test.nim` | Feature `asi_ssot.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/ax_cached_flag_feature_test.nim` | Feature `ax_cached_flag.feature` is `@manual` | LOW — manual feature |
| `tests/gateway/ax_command_surface_feature_test.nim` | Feature `ax_command_surface.feature` is `@manual` | LOW — manual feature |
| `tests/gateway/ax_help_feature_test.nim` | Feature `ax_help.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/ax_prove_heal_feature_test.nim` | Feature `ax_prove_heal.feature` is `@manual` | LOW — manual feature |
| `tests/gateway/ax_routing_test.nim` | Feature `ax_routing.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/ax_workflow_shortcuts_feature_test.nim` | Feature `ax_workflow_shortcuts.feature` is `@manual` | LOW — manual feature |
| `tests/gateway/axiom_prelude_status_test.nim` | Feature `axiom_prelude_status.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/axiom_pure_promotion_test.nim` | Feature `axiom_pure_promotion.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/axir_constraint_test.nim` | Feature `axir_constraint.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/bmc_engine_feature_test.nim` | Feature `bmc_engine.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/boundary_extractor_feature_test.nim` | Feature `boundary_extractor.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/bundle_compiler_gateway_test.nim` | Feature `bundle_compiler_gateway.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/cegar_engine_feature_test.nim` | Feature `cegar_engine.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/certificate_manager_feature_test.nim` | Feature `certificate_manager.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/cli_surface_test.nim` | Feature `cli_surface.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/detective_persona_feature_test.nim` | Feature `detective_persona.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/gate_list_feature_test.nim` | Feature `gate_list.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/gate_runner_equivalence_test.nim` | Feature `gate_runner_equivalence.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/gate_runner_feature_test.nim` | Feature `gate_runner.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/gateway_policy_test.nim` | Feature `gateway_policy.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/gateway_solver_regression_feature_test.nim` | Feature `gateway_solver_regression.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/global_symbol_graph_fallback_feature_test.nim` | Feature `global_symbol_graph_fallback.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/global_symbol_graph_fallback_test.nim` | Feature `global_symbol_graph_fallback.feature` is `@legacy` (duplicate runner) | LOW — legacy feature |
| `tests/gateway/hard_gate_feature_test.nim` | Feature `hard_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/hard_mode_test.nim` | Feature `hard_mode.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/judge_persona_feature_test.nim` | Feature `judge_persona.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/lean_compiler_compat_feature_test.nim` | Feature `lean_compiler_compat.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/lean_lsp_client_feature_test.nim` | Feature `lean_lsp_client.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/lean_skeleton_feature_test.nim` | Feature `lean_skeleton.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/lean_skeleton_test.nim` | Feature `lean_skeleton.feature` is `@legacy` (duplicate runner) | LOW — legacy feature |
| `tests/gateway/legislator_persona_feature_test.nim` | Feature `legislator_persona.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/meta_extractor_test.nim` | Feature `meta_extractor.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/omni_provenance_test.nim` | Feature `omni_provenance.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/orchestrator_feature_test.nim` | Feature `orchestrator.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/policy_validator_feature_test.nim` | Feature `policy_validator.feature` is `@manual` | LOW — manual feature |
| `tests/gateway/procedure_gate_4step_feature_test.nim` | Feature `procedure_gate_4step.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/proof_preserving_fingerprint_test.nim` | Feature `proof_preserving_fingerprint.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/proof_universe_lock_gate_feature_test.nim` | Feature `proof_universe_lock_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/proof_universe_lock_sovereignty_test.nim` | Feature `proof_universe_lock_sovereignty.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/proof_vacuity_gate_feature_test.nim` | Feature `proof_vacuity_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/scheduler_feature_test.nim` | Feature `scheduler.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/scheduler_priority_feature_test.nim` | Feature `scheduler_priority.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/scheduler_priority_test.nim` | Feature `scheduler_priority.feature` is `@legacy` (duplicate runner) | LOW — legacy feature |
| `tests/gateway/scheduler_test.nim` | Feature `scheduler.feature` is `@legacy` (duplicate runner) | LOW — legacy feature |
| `tests/gateway/scribe_persona_feature_test.nim` | Feature `scribe_persona.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/solid_complexity_gate_feature_test.nim` | Feature `solid_complexity_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/swat_persona_feature_test.nim` | Feature `swat_persona.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/topology_apply_feature_test.nim` | Feature `topology_apply.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/vault_sync_feature_test.nim` | Feature `vault_sync.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/warning_zero_test.nim` | Feature `warning_zero.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/windows_ffi_isolation_feature_test.nim` | Feature `windows_ffi_isolation.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/winning_strategy_gate_test.nim` | Feature `winning_strategy_gate.feature` is `@legacy` | LOW — legacy feature |
| `tests/gateway/z3_integrity_feature_test.nim` | Feature `z3_integrity.feature` is `@legacy` | LOW — legacy feature |

**DO NOT RESTORE** without: (a) feature tag changed to `@executable` (no `@legacy`/`@manual`), AND (b) real assertions, AND (c) `bin/procedure_gate` pass.

---

## Batch 6 — 2026-06-12: Test Hygiene Violations (7 files)

**Authority**: AGENTS.md §0.7 (Business-Only Test Scope)
**Reason**: These test files contain `when isMainModule` blocks, which violates the test hygiene principle — test files should use `unittest` suite blocks, not standalone executables. They are self-contained scripts that bypass the gateway test harness.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/performance/timeout_assert_gate.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/fuzz/topology_plan_fuzz.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/examples/async_invariant_interleaving.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/reproduction/async_deadlock.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/reproduction/double_spending.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/reproduction/commitRecord_ghost_update_repro.nim` | `when isMainModule` in test file | LOW — bypasses test harness |
| `tests/reproduction/ghost_update.nim` | `when isMainModule` in test file | LOW — bypasses test harness |

**DO NOT RESTORE** without: (a) conversion to proper `unittest` suite, AND (b) gateway integration, AND (c) traceable `.feature` scenario.

---

## Batch 7 — 2026-06-13: ADR-014 PersonaBridge PBT Replacement (1 file)

**Commit**: `refactor(persona): replace PersonaBridge PBT with deterministic wiring test (ADR-014)`  
**Authority**: AGENTS.md §0.7 (Business-Only Test Scope), §0.8 (No Stub Files), ADR-014
**Reason**: `persona_bridge_pbt.nim` generated random `PersonaBridge` values via closure PBT. ADR-014 replaces the bridge with `PersonaContext`, whose wiring is verified deterministically by `tests/unit/persona_context_wiring_test.nim`. The PBT runner no longer has a target type to generate and its assertions were replaced by concrete callback nil-checks plus per-persona compilation checks.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/generated_pbt/persona_bridge_pbt.nim` | Replaced by deterministic wiring test; `PersonaBridge` type removed | LOW — new test covers same contract |

**DO NOT RESTORE** without: (a) reverting ADR-014, AND (b) proving random closure generation adds value over deterministic wiring test, AND (c) `bin/procedure_gate` pass after restoration.

---

## Batch 8 — 2026-07-07: DEBT#170 Expired Smoke Stubs (43 files)

**Authority**: AGENTS.md §0.7 (Business-Only Test Scope), §0.8 (No Stub Files)
**Reason**: DEBT#170 ("Guard Ring Phase 2 test coverage gap") was temporary scaffolding that expired after 7 commits. All 43 files use `autoGenerateModuleSmokeTest()` from `axiom_pragmas` with a single `discard` test body. TTL expired, debt status: closed.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `tests/gateway/architecture_invariants_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/ast_builder_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/axiom_engine_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/certificate_hydration_runner_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/cert_writer_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/cli_build_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/debug_mode_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/delegation_enforcer_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/env_access_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/exception_guard_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/hotspot_analyzer_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/judge_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/judge_automation_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/judge_shadow_mode_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/leanstral_cli_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/llm_backend_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/parallel_utils_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/pbt_engine_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/proof_synthesis_engine_part2_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/quality_gate_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/repo_root_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/report_cli_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/sad_gate_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/sandbox_guard_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/scanner_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/shadow_trigger_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/shadow_verify_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/stage_01_ast_extract_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/state_hash_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/structural_safety_gate_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/test_quality_guard_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/tree_sitter_parser_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/vault_factory_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/gate_vfs_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/gate_admin_validate_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/gate_run_logger_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/gate_utils_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/git_config_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/git_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/git_ops_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/git_snapshot_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/golden_version_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |
| `tests/gateway/hermetic_sandbox_feature_test.nim` | DEBT#170 expired smoke stub | LOW — no assertions |

**DO NOT RESTORE** without: (a) real assertions replacing `discard` body, AND (b) traceable `.feature` scenario, AND (c) `bin/procedure_gate` pass.
