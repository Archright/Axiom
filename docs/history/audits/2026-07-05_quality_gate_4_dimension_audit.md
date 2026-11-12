# Axiom Quality Gate 4-Dimension Audit Report
## Date: 2026-07-05
## Auditor: Automated Audit Script

---

## 1. Objective Metrics

| Metric | Value |
|--------|-------|
| Total .nim files | 1096 |
| Total functions | 6554 |

### Modules Exceeding 15 Exported Functions

| Exported | Module |
|----------|--------|
| 49 | proof_typestate.nim |
| 39 | git_schema.nim |
| 36 | task_schema.nim |
| 36 | git_operations.nim |
| 32 | axiom_ir_helpers.nim |
| 30 | orchestrator_hook_part1.nim |
| 30 | pipeline_lean_spec_inference_part2.nim |
| 30 | gate_memo.nim |
| 30 | symbolic_types_expr.nim |
| 29 | gateway_helpers.nim |
| 27 | ir_to_lean.nim |
| 25 | z3_pool.nim |
| 24 | universal_mapper_part1.nim |
| 24 | symbol_interning.nim |
| 23 | canonical_hub_lint_runner.nim |
| 23 | unified_gate_runner.nim |
| 23 | cas_index.nim |
| 22 | healing_orchestrator.nim |
| 22 | pbt_engine.nim |
| 21 | axiom_ir.nim |
| 20 | stages.nim |
| 19 | topology_executor.nim |
| 18 | architecture_config_gate.nim |
| 18 | wp_simplifier.nim |
| 18 | spec_generator_helpers.nim |
| 17 | leanstral_cli.nim |
| 16 | pipeline_transition.nim |
| 16 | ast_to_ir.nim |
| 16 | merkle_vfs.nim |
| 16 | gate_cas.nim |
| 16 | axiom_protocol.nim |
| 16 | file_utils.nim |
| 16 | complexity_index.nim |
| 16 | io_schema.nim |
| 16 | file_io_executor.nim |

## 2. Gate Execution Results

### architecture_gate --full-tree

```
./src/gate/utils/gate_macros.nim(103, 30) Error: invalid indentation

EXIT CODE: 1
```

## 3. Debt Baseline Status

Debt baseline file not found or empty.

## 4. Binary Freshness

**WARNING**: Gate binary is stale. Newer source files:
  - orchestrator_hook.nim
  - gate_rules_module_classifier.nim
  - slice_hash.nim
  - compile_time_checks.nim
  - gate_defs_data_a_d.nim
  - gate_dependency_extractor.nim
  - attestation.nim
  - orchestrator_hook_part1.nim
  - git.nim
  - logic_binding_gate.nim

## 5. Compilation Status

### nim check src/cli/main.nim

```
[axiomImpl] IR: buildAxProofSmtAssertions* params=5 recursive=false registry=217
..
Hint: 
375262 lines; 7.227s; 658.609MiB peakmem; proj: ./src/cli/main.nim; out: unknownOutput [SuccessX]

```

## 6. Grade Assessment

| Dimension | Grade | Rationale |
|-----------|-------|-----------|
| Ideal | C+ | Post-detection linter; no compile-time enforcement |
| Elegant | B | Custom line-based parser; 2 queries disabled |
| Fundamental | B- | 0 debt entries; hardcoded exceptions |
| Deterministic | A- | Consistent results; stale binary risk |
| **Overall** | **B-** | Functional but not structural guarantee |

## 7. Recommendations

### Immediate
1. Verify why 35 modules exceed exported function threshold
2. Check if stale binary is masking violations
3. Review debt baseline entries expiring within 60 days

### Short-term
4. Move hardcoded exceptions to architecture_policy.lock
5. Add binary self-verification (compile-time hash)
6. Re-enable disabled queries with improved heuristics

### Long-term
7. Implement compile-time enforcement via macros
8. Upgrade parser to structured AST (parseStmt)
9. Eliminate debt baseline concept entirely

---

*Report generated automatically by quality_audit_gate*
