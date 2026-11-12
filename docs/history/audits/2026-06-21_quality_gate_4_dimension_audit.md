# Axiom Quality Gate 4-Dimension Audit Report
## Date: 2026-06-21
## Auditor: Automated Audit Script

---

## 1. Objective Metrics

| Metric | Value |
|--------|-------|
| Total .nim files | 890 |
| Total functions | 5136 |

### Modules Exceeding 15 Exported Functions

| Exported | Module |
|----------|--------|
| 39 | git_schema.nim |
| 36 | task_schema.nim |
| 36 | git_operations.nim |
| 31 | orchestrator_hook_part1.nim |
| 30 | pipeline_lean_spec_inference_part2.nim |
| 30 | symbolic_types_expr.nim |
| 24 | universal_mapper_part1.nim |
| 24 | symbol_interning.nim |
| 23 | canonical_hub_lint_runner.nim |
| 22 | healing_orchestrator.nim |
| 22 | pbt_engine.nim |
| 21 | io_schema.nim |
| 20 | cst_schema.nim |
| 20 | session_parser_validators.nim |
| 19 | topology_executor.nim |
| 19 | gate_memo.nim |
| 18 | architecture_config_gate.nim |
| 18 | wp_simplifier.nim |
| 18 | spec_generator_helpers.nim |
| 17 | leanstral_cli.nim |
| 16 | pipeline_transition.nim |
| 16 | merkle_vfs.nim |
| 16 | axiom_protocol.nim |
| 16 | file_utils.nim |

## 2. Gate Execution Results

### architecture_gate --full-tree

```

```

## 3. Debt Baseline Status

Debt baseline file not found or empty.

## 4. Binary Freshness

**WARNING**: Gate binary is stale. Newer source files:
  - orchestrator_hook.nim
  - gate_rules_module_classifier.nim
  - gate_dependency_extractor.nim
  - orchestrator_hook_part1.nim
  - git.nim
  - logic_binding_gate.nim
  - policy_loader.nim
  - gate_rules_architecture.nim
  - debug_mode_state.nim
  - gate_dag.nim

## 5. Compilation Status

### nim check src/cli/main.nim

```
../Axiom-core/src/cli/wf_semantic.nim(76, 6) Hint: 'buildSemanticTranslation' is declared but not used [XDeclaredButNotUsed]
.
Hint: 
200404 lines; 4.988s; 531.613MiB peakmem; proj: ../Axiom-core/src/cli/main.nim; out: unknownOutput [SuccessX]

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
1. Verify why 24 modules exceed exported function threshold
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
