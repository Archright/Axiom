# soc-surface-area 위반 분석 리포트

> 총 위반: 224개 (기준: nimtry baseline 1123)

## 디렉토리별 분포

| src/verification | 58 |
| src/gate/nimtry | 25 |
| src/gate/runners | 22 |
| src/core/topology | 9 |
| src/core/translator | 8 |
| src/cli | 7 |
| src/core/api | 6 |
| src/core/judge | 5 |
| src/core/diagnostics | 5 |
| src/personas | 5 |
| src/verification/analyzer | 4 |
| src/core/symbolic | 4 |
| src/core/symbol_graph | 4 |
| src/gate | 3 |
| src/sieve | 3 |
| src/verification/batch_uap | 3 |
| src/core/codec | 3 |
| src/core/spec | 3 |
| src/core/type_system | 3 |
| src/core/boundary | 3 |
| src/mcp | 3 |
| src/infrastructure | 2 |
| src/verification/solver | 2 |
| src/core/logic | 2 |
| src/core/audit | 2 |
| src/core/orchestrator | 2 |
| src/core/json | 2 |
| src/core/types | 2 |
| src/core/gateway | 2 |
| src/core/contracts | 2 |
| src/core/encoding | 2 |
| src/core/integrity | 2 |
| src/core/solver | 2 |
| src/ui | 2 |
| src/engine | 1 |
| src/verification/proof | 1 |
| src/core/profiles | 1 |
| src/core/trusted | 1 |
| src/core/sync | 1 |
| src/core/sorter | 1 |
| src/core/io | 1 |
| src/core/parsers | 1 |
| src/core/ast | 1 |
| src/core/session | 1 |
| src/core/contract | 1 |
| src/cli/commands | 1 |

## Top 30 분해 대상 (함수 긴 순)

| Lines | File | Function |
|-------|------|----------|
| 403 | src/verification/batch_uap/private/loop_driver.nim | runBatchUapOrchestration |
| 399 | src/core/boundary/boundary_extractor_part1.nim | extractBoundaries |
| 246 | src/gate/nimtry/nimtry_cli.nim | main |
| 237 | src/verification/proof_state_builder.nim | hydrateProofStateFromCertificateVault |
| 219 | src/verification/lean_lsp_proof_search.nim | runDynamicProofSearch |
| 214 | src/gate/runners/validate_architecture.nim | main |
| 207 | src/verification/pipeline_lean_spec_inference_part3.nim | inferLeanSpec |
| 191 | src/gate/nimtry/safety_queries.nim | scanFileForForbiddenPatterns |
| 189 | src/core/encoding/smt_to_lean/private/parser.nim | smtExprToLeanExpr |
| 185 | src/core/boundary/boundary_extraction_helpers.nim | convertExpressionToSmtLean |
| 184 | src/verification/analyzer/stage_05_lean_bridge.nim | runSymbolicAnalysis |
| 180 | src/core/judge/smart_search.nim | generateSemanticHintWithStrategy |
| 178 | src/personas/judge.nim | certify |
| 167 | src/verification/pipeline_core_types.nim | jsonFromUniversalPipelineResult |
| 160 | src/verification/pipeline_core_runner_part1.nim | writeProofArtifact |
| 160 | src/verification/analyzer/stage_02_fingerprint.nim | hydrateCertificate |
| 160 | src/core/contract/contract_ast_extractor.nim | extractContractFromAst |
| 158 | src/verification/proof_synthesis_engine_part2.nim | runSemanticProofReplay |
| 156 | src/gate/nimtry/feature_universe.nim | scanFeatureUniverse |
| 153 | src/core/translator/universal_mapper_part2.nim | mapAstJsonToUniversalTranslation |
| 150 | src/core/orchestrator/cfg_builder.nim | buildCfgFromStatementList |
| 149 | src/core/contracts/universal_pipeline_contract.nim | buildSemanticHybridUniversalPipelineResult |
| 142 | src/gate/orchestrator_hook_part2.nim | runAllGatesParallel |
| 140 | src/core/diagnostics/refactoring_engine.nim | applyRefactoringTemplate |
| 139 | src/core/diagnostics/pattern_guard.nim | checkApplicability |
| 133 | src/cli/wf_semantic.nim | buildSemanticHybridUniversalPipelineResult |
| 131 | src/core/type_system/liquid_inference.nim | inferLiquidTypeEnv |
| 129 | src/gate/nimtry/solid_queries.nim | registerSolidQueries |
| 128 | src/core/translator/universal_assembler.nim | sanitizeLeanSource |
| 126 | src/verification/solver/z3_pool.nim | z3ExecPersistent |
