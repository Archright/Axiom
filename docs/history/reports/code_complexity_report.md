# Axiom_Enterprise Code Complexity & Size Hotspots Report

Generated: 2026-05-26

---

## 1. Top 20 Largest .nim Files by Line Count

| # | Lines | File |
|---|-------|------|
| 1 | 1408 | src/core/axiom_api.nim |
| 2 | 1204 | src/core/boundary_extractor.nim |
| 3 | 1166 | src/verification/lean_lsp.nim |
| 4 | 926 | src/core/topology_engine.nim |
| 5 | 850 | src/verification/pipeline_lean_spec_inference.nim |
| 6 | 801 | src/core/gateway.nim |
| 7 | 776 | src/cli/certificate_cli.nim |
| 8 | 772 | src/cli/commands/observability.nim |
| 9 | 741 | src/core/spec_generator.nim |
| 10 | 732 | src/verification/pipeline_negative_scan.nim |
| 11 | 724 | src/core/verified_axioms_catalog.nim |
| 12 | 706 | src/core/smt_to_lean_codegen.nim |
| 13 | 697 | src/cli/wf_state.nim |
| 14 | 644 | src/cli/topology_cli.nim |
| 15 | 628 | src/ui/ax_tui_reporter.nim |
| 16 | 627 | src/cli/verify_workflow_cli.nim |
| 17 | 612 | src/gate/architecture_policy.nim |
| 18 | 583 | src/mcp/axiom_mcp.nim |
| 19 | 579 | src/translator/universal_mapper.nim |
| 20 | 577 | src/core/orchestrator.nim |

---

## 2. Top 20 Largest Functions/Procs by Line Count

| # | Lines | Function | Location |
|---|-------|----------|----------|
| 1 | 399 | certificateStatusToProofEntryStatus | src/cli/report_cli.nim:136 |
| 2 | 310 | parseAssignmentLine | src/gate/architecture_policy.nim:177 |
| 3 | 270 | runRecertifyLeanCli | src/cli/commands/recertify_lean.nim:219 |
| 4 | 263 | extractBoundaries | src/core/boundary_extractor.nim:709 |
| 5 | 258 | buildStructuralDiagnoses | src/cli/topology_cli.nim:319 |
| 6 | 254 | cmdRecertifyCertificates | src/cli/certificate_cli.nim:404 |
| 7 | 225 | runUniversalAcceptancePipelineCore | src/verification/pipeline_core_runner.nim:301 |
| 8 | 220 | isValidJsonBlob | src/core/session_parser.nim:46 |
| 9 | 203 | inferLeanSpec | src/verification/pipeline_lean_spec_inference.nim:647 |
| 10 | 202 | buildAsiCache | src/cli/cst_cli.nim:241 |
| 11 | 193 | smtExprToLeanExpr | src/core/smt_to_lean_codegen.nim:323 |
| 12 | 187 | convertExpressionToSmtLean | src/core/boundary_extractor.nim:186 |
| 13 | 185 | runDynamicProofSearch | src/verification/lean_lsp.nim:981 |
| 14 | 174 | writeProofArtifact | src/verification/pipeline_core_runner.nim:70 |
| 15 | 174 | jsonFromAxProofEntries | src/cli/wf_state.nim:140 |
| 16 | 171 | cmdDynamicProofSearch | src/cli/certificate_cli.nim:71 |
| 17 | 156 | mapAstJsonToUniversalTranslation | src/translator/universal_mapper.nim:366 |
| 18 | 153 | runSemanticProofReplay | src/verification/proof_synthesis_engine.nim:362 |
| 19 | 140 | isTrivialConstraint | src/core/boundary_extractor.nim:972 |
| 20 | 125 | generateKInductionProofFromSessionId | src/core/axiom_api.nim:1130 |

Total functions exceeding 50 lines: **73 functions** across the codebase.

---

## 3. Files with Deepest Nesting Levels (max indentation depth)

| Depth | File |
|-------|------|
| 38 | src/verification/lean_skeleton.nim |
| 32 | src/core/contract_ast_extractor.nim |
| 31 | src/verification/state_manager.nim |
| 27 | src/cli/verify_workflow_cli.nim |
| 27 | src/cli/commands/heal_node_executor.nim |
| 26 | src/core/smt_to_lean_codegen.nim |
| 25 | src/cli/procedure_gate.nim |
| 24 | src/verification/translation_validator.nim |
| 23 | src/gate/orchestrator.nim |
| 23 | src/core/contract_types.nim |
| 23 | src/cli/commands/heal_leanstral.nim |
| 23 | src/cli/commands/heal_analysis.nim |
| 22 | src/verification/proof_state_builder.nim |
| 22 | src/verification/pipeline_negative_scan.nim |
| 22 | src/verification/analyzer/stages/stage_05_lean_bridge.nim |
| 22 | src/core/contract_text_extractor.nim |
| 22 | src/core/contract_smtlib2.nim |
| 21 | src/verification/gate_rules.nim |
| 21 | src/core/orchestrator_topology_worker.nim |
| 20 | src/frontend/nim/weaver.nim |

---

## 4. Files with Most Imports (Highest Coupling / Fan-Out)

| Imports | File |
|---------|------|
| 21 | src/cli/wf_state.nim |
| 18 | src/verification/analyzer/stages/stage_05_lean_bridge.nim |
| 17 | src/verification/universal_pipeline_core.nim |
| 17 | src/verification/universal_pipeline.nim |
| 17 | src/verification/hint_processor.nim |
| 17 | src/core/orchestrator.nim |
| 17 | src/cli/basic_commands_cli.nim |
| 16 | src/verification/pipeline_core_runner.nim |
| 16 | src/cli/report_cli.nim |
| 16 | src/cli/commands/heal_state_applier.nim |
| 16 | src/cli/commands/heal_node_executor.nim |
| 16 | src/cli/commands/heal_leanstral.nim |
| 15 | src/mcp/axiom_mcp.nim |
| 14 | src/verification/proof_synthesis_engine.nim |
| 14 | src/mcp/tools.nim |
| 14 | src/cli/wf_semantic.nim |
| 14 | src/cli/topology_cli.nim |
| 14 | src/cli/commands/heal_scheduler.nim |
| 14 | src/cli/certificate_cli.nim |
| 13 | src/verification/analyzer/stages/stage_02_fingerprint.nim |

---

## 5. Modules with Highest Fan-In (Most Widely Imported)

| Ref count | Module | File |
|-----------|--------|------|
| 82 | core.results | src/core/results.nim |
| 45 | core.constants | src/core/constants.nim |
| 44 | core.json_utils | src/core/json_utils.nim |
| 38 | core.domain_types | src/core/domain_types.nim |
| 34 | core.text_utils | src/core/text_utils.nim |
| 28 | core.gateway | src/core/gateway.nim |
| 23 | core.solver.types | src/core/solver/types.nim |
| 21 | core.io_utils | src/core/io_utils.nim |
| 19 | core.vault_manager_spec | src/core/vault_manager_spec.nim |
| 17 | core.sorter_core | src/core/sorter_core.nim |
| 17 | cli.cli_types | src/cli/cli_types.nim |
| 16 | core.tree_sitter_bridge | src/core/tree_sitter_bridge.nim |
| 16 | core.file_utils | src/core/file_utils.nim |
| 16 | core.axiom_api | src/core/axiom_api.nim |
| 14 | core.types.global_symbol_graph_types | src/core/types/global_symbol_graph_types.nim |
| 14 | core.smart_search | src/core/smart_search.nim |
| 13 | translator.universal_mapper | src/translator/universal_mapper.nim |
| 12 | core.metrics | src/core/metrics.nim |
| 12 | cli.cli_io | src/cli/cli_io.nim |
| 11 | verification.pipeline_core_types | src/verification/pipeline_core_types.nim |

---

## 6. Files >500 Lines Recommended for Splitting

28 files exceed 500 lines and should be considered for splitting:

| Lines | File |
|-------|------|
| 1408 | src/core/axiom_api.nim |
| 1204 | src/core/boundary_extractor.nim |
| 1166 | src/verification/lean_lsp.nim |
| 926 | src/core/topology_engine.nim |
| 850 | src/verification/pipeline_lean_spec_inference.nim |
| 801 | src/core/gateway.nim |
| 776 | src/cli/certificate_cli.nim |
| 772 | src/cli/commands/observability.nim |
| 741 | src/core/spec_generator.nim |
| 732 | src/verification/pipeline_negative_scan.nim |
| 724 | src/core/verified_axioms_catalog.nim |
| 706 | src/core/smt_to_lean_codegen.nim |
| 697 | src/cli/wf_state.nim |
| 644 | src/cli/topology_cli.nim |
| 628 | src/ui/ax_tui_reporter.nim |
| 627 | src/cli/verify_workflow_cli.nim |
| 612 | src/gate/architecture_policy.nim |
| 583 | src/mcp/axiom_mcp.nim |
| 579 | src/translator/universal_mapper.nim |
| 577 | src/core/orchestrator.nim |
| 577 | src/cli/commands/recertify_lean.nim |
| 560 | src/cli/report_cli.nim |
| 554 | src/core/session_parser.nim |
| 534 | src/cli/cst_cli.nim |
| 531 | src/core/the_judge_query.nim |
| 526 | src/verification/pipeline_core_runner.nim |
| 515 | src/verification/proof_synthesis_engine.nim |
| 513 | src/core/global_symbol_graph_builder.nim |

---

## 7. Functions >50 Lines Recommended for Refactoring

73 functions exceed 50 lines. Top candidates (top 20 shown here; full list in report):

| Lines | Function | Location |
|-------|----------|----------|
| 399 | certificateStatusToProofEntryStatus | src/cli/report_cli.nim:136 |
| 310 | parseAssignmentLine | src/gate/architecture_policy.nim:177 |
| 270 | runRecertifyLeanCli | src/cli/commands/recertify_lean.nim:219 |
| 263 | extractBoundaries | src/core/boundary_extractor.nim:709 |
| 258 | buildStructuralDiagnoses | src/cli/topology_cli.nim:319 |
| 254 | cmdRecertifyCertificates | src/cli/certificate_cli.nim:404 |
| 225 | runUniversalAcceptancePipelineCore | src/verification/pipeline_core_runner.nim:301 |
| 220 | isValidJsonBlob | src/core/session_parser.nim:46 |
| 203 | inferLeanSpec | src/verification/pipeline_lean_spec_inference.nim:647 |
| 202 | buildAsiCache | src/cli/cst_cli.nim:241 |
| 193 | smtExprToLeanExpr | src/core/smt_to_lean_codegen.nim:323 |
| 187 | convertExpressionToSmtLean | src/core/boundary_extractor.nim:186 |
| 185 | runDynamicProofSearch | src/verification/lean_lsp.nim:981 |
| 174 | writeProofArtifact | src/verification/pipeline_core_runner.nim:70 |
| 174 | jsonFromAxProofEntries | src/cli/wf_state.nim:140 |
| 171 | cmdDynamicProofSearch | src/cli/certificate_cli.nim:71 |
| 156 | mapAstJsonToUniversalTranslation | src/translator/universal_mapper.nim:366 |
| 153 | runSemanticProofReplay | src/verification/proof_synthesis_engine.nim:362 |
| 140 | isTrivialConstraint | src/core/boundary_extractor.nim:972 |
| 125 | generateKInductionProofFromSessionId | src/core/axiom_api.nim:1130 |

---

## Key Insights

1. **Monolith files**: `src/core/axiom_api.nim` (1408 lines) is the largest single file and the most imported (fan-in 16) -- it's a critical hub that should be split first.

2. **God functions**: `certificateStatusToProofEntryStatus` (399 lines) and `parseAssignmentLine` (310 lines) are extreme outliers. A function over 50 lines is a refactoring candidate; these are 6-8x that threshold.

3. **Deep nesting hotspots**: `src/verification/lean_skeleton.nim` (depth 38) and `src/core/contract_ast_extractor.nim` (depth 32) have excessive nesting suggesting deeply nested conditionals/match statements that need simplification.

4. **High coupling**: `src/cli/wf_state.nim` imports 21 modules (fan-out) and appears in several function size leaders -- it's both broad and deep. `core.results` is imported by 82 other files, making it the most foundational module.

5. **Top refactoring priorities**: 
   - `src/core/boundary_extractor.nim` (1204 lines, 4 functions >100 lines)
   - `src/cli/report_cli.nim` (has the #1 largest function)
   - `src/core/axiom_api.nim` (largest file, also high fan-in)
   - `src/cli/wf_state.nim` (highest coupling + multiple large functions)
