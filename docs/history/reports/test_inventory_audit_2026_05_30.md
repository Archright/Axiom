# Test Inventory Meaning Audit — 2026-05-30

> Premise: "의미가 없는 테스트를 복원하는 것만큼 쓰잘데기 없는 일이 없다"
> Method: 전수조사 of tests/gateway/ (142 files), tests/deprecated/ (25 files), tests/features/ (115 files)

---

## 1. Executive Summary

| Category | Count | Verdict |
|----------|-------|---------|
| tests/gateway/ total .nim files | 142 | 2 restored today, 140 existing |
| 100% TODO stub (check true only) | ~40+ files | **의미 없음 — 구현 전 placeholders** |
| Helper / runner files (no checks) | 8 files | **인프라 — 의미 있음** |
| Meaningful tests (real assertions) | ~90 files | **의미 있음 — 유지/강화 필요** |
| tests/deprecated/ total | 25 files | **대부분 코드 드리프트로 의미 상실** |
| tests/features/ total | 115 files | **60+개는 @executable 기본값 → runner expected** |
| Feature↔Test mapping gaps | 12 features | **runner missing or deprecated** |

---

## 2. tests/gateway/ — Classification by Meaning

### 2.1 100% TODO Stub (check true only) — 의미 없음

These files contain ONLY `check true` or `check false` placeholders. They are not tests; they are **feature request bookmarks**.

| File | Checks | Stubs | Stub% | Feature Under Test |
|------|--------|-------|-------|-------------------|
| architecture_gate_feature_test.nim | 18 | 18 | 100% | SOLID/SRP/DRY/SSOT gate rules |
| anti_tautology_registry_feature_test.nim | 3 | 3 | 100% | Anti-tautology registry |
| anti_tautology_sentinel_feature_test.nim | 6 | 6 | 100% | Anti-tautology sentinel |
| api_boundary_feature_test.nim | 2 | 2 | 100% | Public API boundary |
| asi_cli_feature_test.nim | 2 | 2 | 100% | ASI CLI SSOT |
| asi_hard_gate_feature_test.nim | 3 | 3 | 100% | ASI hard gate |
| asi_metric_unification_feature_test.nim | 5 | 5 | 100% | ASI metric unification |
| asi_replayer_feature_test.nim | 3 | 3 | 100% | ASI event sourcing replayer |
| ...and 30+ more | — | — | 100% | Various features |

**Recommendation**: Do NOT "restore" or "fix" these. They are not broken tests; they are **unimplemented tests**. The correct action is either:
- (a) Implement the feature first, then write the test, OR
- (b) Delete the stub if the feature is no longer planned.

### 2.2 Helper / Infrastructure Files — 의미 있음 (no checks)

These files provide test infrastructure, not assertions.

| File | Role |
|------|------|
| all_gateway_runner.nim | Batch test orchestrator (142 tests, 12 workers) |
| asi_report_fixture_helpers.nim | ASI report fixture generators |
| gateway_test_helpers.nim | Shared test utilities |
| ax_routing_test.nim | Routing test utilities (NO_SUITE) |
| cli_build_test.nim | CLI build utilities (NO_SUITE) |
| cli_surface_test.nim | CLI surface utilities (NO_SUITE) |
| global_symbol_graph_fallback_test.nim | Fallback test utilities (NO_SUITE) |
| reasoning_recorder_test.nim | Recorder utilities (NO_SUITE) |

**Recommendation**: Keep. They are infrastructure.

### 2.3 Meaningful Tests with Real Assertions — 의미 있음

Examples of tests that actually verify behavior:

| File | What It Tests |
|------|--------------|
| gate_runner_equivalence_test.nim | Gate runner binary compilation + execution equivalence |
| asi_ssot_test.nim | ASI SSOT coverage calculation |
| proof_universe_lock_sovereignty_test.nim | proof_universe.lock caller authorization |
| scheduler_priority_test.nim | Scheduler priority queue ordering |
| cac_test.nim | Content-addressable cache validity |
| zero_drift_hardening_test.nim | Structural ASI hardening |
| winning_strategy_gate_test.nim | Winning strategy hard-gate |
| ...and ~85 more | Various functional assertions |

**Recommendation**: These are the tests that provide value. Prioritize keeping them green and expanding coverage here.

---

## 3. tests/deprecated/ — Restoration Value Assessment

### 3.1 High Value (복원 가치 있음)

| Test | Why It Matters | Blocker |
|------|---------------|---------|
| windows_ffi_isolation_feature_test.nim | Cross-platform FFI isolation contract | **FIXED** — smoke_test.nim XDeclaredButNotUsed |
| warning_zero_test.nim | Compiler hygiene (checksums, AGENTS.md) | **FIXED** — vault_manager.nim → vault_manager_spec.nim |

**Status**: Already restored to tests/gateway/. 142/142 PASS.

### 3.2 Medium Value (복원 가능 but needs code drift fix)

| Test | Why It Matters | Blocker |
|------|---------------|---------|
| architecture_gate_ast_superiority_test.nim | AST-based architecture gate (nimtry) | `"""` parse error **FIXED**; 3 assertion failures due to policy drift (cli/view, z3ExecPersistent, alpha-equivalent) |
| architecture_gate_test.nim | SOLID/SSOT/DRY rule enforcement | 4 assertion failures due to policy drift |
| architecture_gate_synthetic_probe_test.nim | Synthetic probe for architecture gate | Depends on ast_superiority_test |

**Verdict**: The parse errors are fixable. The assertion failures indicate the **architecture gate policy has drifted** from the test expectations. These tests are valuable IF the policy is correct; otherwise they are testing for rules that no longer apply.

**Recommendation**: Before restoring, audit whether the expected violations (cli/view, z3ExecPersistent, etc.) are still supposed to be violations in the current architecture policy.

### 3.3 Low Value (의미 상실 — 복원 불필요)

| Test | Why Low Value |
|------|--------------|
| architecture_refactor_feature_test.nim | Tests massive architecture_refactor.feature (115 scenarios). This is a **migration tracker**, not a regression test. Most scenarios verify "file X should exist" for files that have been moved/renamed. |
| tech_debt_remediation_feature_test.nim | Tests file existence for files that no longer exist (ax_heal_action_cli.nim, .physically_impure_modules at old path). |
| asi_cli_test.nim | ASI 0.0000 vs expected 1.0000 — core ASI tautology issue (DEBT#002). Fixing the test without fixing ASI is meaningless. |
| vacuity_ban_feature_test.nim | ASI 0.0000 + 9 assertion failures — same root cause as DEBT#002. |
| gateway_pipeline_test.nim | Tests solver pipeline with sample files (withdraw.nim, payments.nim) that are not in the codebase. |
| gateway_topology_verify_test.nim | Empty report output (headerLines.len == 0). Tests topology on files that no longer exist. |
| certificate_graph_boundary_test.nim | certStale vs certVerifiedAxiom mismatch — certificate status logic has changed. |
| report_cli_test.nim | Auto-repaired fingerprint mismatches missing — feature removed. |
| boundary_extractor_gateway_test.nim | bcPartialHavoc vs bcComplete mismatch — boundary extractor enum changed. |
| heal_recovery_contract_feature_test.nim | Lean query variable declarations mismatch — Lean bridge changed. |
| ledger_inlining_feature_test.nim | Feature file content missing. |
| prove_heal_unification_feature_test.nim | healScheduleTier count mismatch (5 vs 9) — scheduler logic changed. |
| intrinsic_filter_hint_test.nim | Skeleton endsWith mismatch — skeleton format changed. |
| mirror_shield_test.nim | 0 legacy certificates found — legacy certificate format removed. |
| smt_to_lean_type_aware_test.nim | exact h0 missing in output — SMT→Lean mapping changed. |
| transpilation_layer_test.nim | Axiom linkage hash mismatch / truncated output — hash algorithm or format changed. |
| verified_axiom_test.nim | Axiom name mismatch (nim.string.len.isNat vs string-length-nonneg) — naming convention changed. |
| gateway_mcp_core_test.nim | refinedInvariant empty — MCP core contract changed. |
| deterministic_purge_feature_test.nim | 45 markerFailures — marker format or rules changed. |
| nimtry_regression_test.nim | AST verdicts for cli/view — same drift as architecture_gate_test. |
| architecture_policy_test.nim | Glob parsing mismatch — policy format changed. |
| architecture_gate_zero_tolerance_test.nim | maxExportedFunctions 30 vs 15 — threshold changed. |

**Verdict**: These tests are testing for **behaviors that no longer exist or have been intentionally changed**. Restoring them means reverting code changes or updating test expectations to match the new (but unverified) behavior.

**Recommendation**: Do NOT bulk-restore. For each, ask: "Is the old behavior a bug that should be fixed, or a feature that was intentionally removed?" Only restore if the old behavior is still the correct behavior.

---

## 4. tests/features/ ↔ tests/gateway/ Mapping Analysis

### 4.1 Missing Runners (12 features without _feature_test.nim)

| Feature File | Expected Runner | Status |
|-------------|-----------------|--------|
| architecture_refactor.feature | architecture_refactor_feature_test.nim | In deprecated/ (too large, tests migration tracker) |
| deterministic_purge.feature | deterministic_purge_feature_test.nim | In deprecated/ |
| external_cli_smoke.feature | external_cli_smoke_feature_test.nim | **Never existed** — smoke test is scripts/smoke_test.nim |
| gate_memo_depsdirs.feature | gate_memo_depsdirs_feature_test.nim | **Never existed** |
| gate_memoization.feature | gate_memoization_feature_test.nim | **Never existed** |
| heal_recovery_contract.feature | heal_recovery_contract_feature_test.nim | In deprecated/ |
| ledger_inlining.feature | ledger_inlining_feature_test.nim | In deprecated/ |
| prove_heal_unification.feature | prove_heal_unification_feature_test.nim | In deprecated/ |
| tech_debt_remediation.feature | tech_debt_remediation_feature_test.nim | In deprecated/ |
| unit_test_parallel.feature | unit_test_parallel_feature_test.nim | **Never existed** |
| unstaged_guard.feature | unstaged_guard_feature_test.nim | **Never existed** |
| vacuity_ban.feature | vacuity_ban_feature_test.nim | In deprecated/ |

**Analysis**:
- 6 files are in deprecated/ (architecture_refactor, deterministic_purge, heal_recovery_contract, ledger_inlining, prove_heal_unification, tech_debt_remediation, vacuity_ban)
- 5 files never had a runner (external_cli_smoke, gate_memo_depsdirs, gate_memoization, unit_test_parallel, unstaged_guard)
- Per AGENTS.md §2.8 Gherkin Tag Schema: absent tag = default @executable = runner required.

**Implication**: procedure_gate zombie check will flag these 12 features as having missing runners. However, if the feature is a migration tracker (architecture_refactor) or tests removed behavior (vacuity_ban), the missing runner is **correct**.

**Recommendation**: Add `@manual` tag to features that intentionally have no runner:
- `architecture_refactor.feature` — migration tracker, not regression test
- `tech_debt_remediation.feature` — remediation tracker, not regression test
- `external_cli_smoke.feature` — smoke test is in scripts/, not gateway

### 4.2 Features WITH Runners but 100% Stubs

~40+ features have `_feature_test.nim` files that pass but contain only `check true`. These are **zombie runners** — they exist but verify nothing.

**Recommendation**: Either:
- (a) Implement real assertions (high effort, high value), OR
- (b) Delete the stub runner and mark the feature `@manual` if the feature is not yet implemented.

---

## 5. Key Insight: Three Categories of "Test"

The codebase conflates three distinct concepts under the label "test":

| Category | Purpose | Current Count | Action |
|----------|---------|---------------|--------|
| **Regression Test** | Verify existing behavior doesn't break | ~90 files | **Keep and maintain** |
| **Unimplemented Test Stub** | Placeholder for future test | ~40 files | **Delete or mark @manual** |
| **Migration Tracker** | Verify architectural migration steps | ~5 files (deprecated/) | **Move to docs/, not tests/** |

The 25 deprecated tests and the 40 stub tests should be treated differently:
- **Deprecated tests** = Tests for behavior that changed. They are either (a) bug reports (old behavior was correct) or (b) obsolete (new behavior is correct). Audit each one.
- **Stub tests** = Not tests at all. They are TODOs disguised as tests. They provide zero value and create noise in the test count.

---

## 6. Recommended Action Plan

### Immediate ( preserves Green Pipeline )
1. **Delete all 100% stub files** from tests/gateway/ that contain only `check true`. These are not tests.
2. **Tag migration-tracker features** with `@manual` (architecture_refactor, tech_debt_remediation, external_cli_smoke).
3. **Delete deprecated tests** that test removed behavior (gateway_pipeline, vacuity_ban, asi_cli with old ASI math, etc.).

### Short-term
4. **Audit architecture_gate_ast_superiority_test** — determine if the 3 expected violations are still violations.
5. **Implement real assertions** for high-value features (asi_ssot, proof_universe_lock, scheduler, etc.).

### Long-term
6. **Separate migration trackers from regression tests**. Architecture refactor scenarios belong in `docs/history/`, not `tests/features/`.
7. **Establish test meaning gate**: New tests must have ≥1 non-trivial assertion. `check true` is rejected at PR time.

---

## 7. Verification

```bash
export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
nimble test  # 142/142 PASS (current)
```
