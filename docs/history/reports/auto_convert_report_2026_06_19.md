# proc→func Auto-Conversion Report — 2026-06-19T12:43:55.507416

## Summary

| Metric | Count |
|--------|-------|
| Files scanned | 407 |
| Procs converted to func | 365 |
| Whitelist entries (impure) | 377 |
| Iterations to convergence | 6 |

## Whitelist (to add to architecture_policy.lock)

```
src/core/api/axiom_api_session_proof.nim:generateProofFromSession
src/core/application/verification_orchestration.nim:runFullVerificationCycle
src/core/application/verification_orchestration.nim:runLeanProofRefinement
src/core/application/verification_orchestration.nim:runSelfHealing
src/core/audit/burn_down_queue.nim:buildPriorityQueue
src/core/audit/burn_down_queue.nim:computeSadScore
src/core/audit/burn_down_queue.nim:findTestFile
src/core/audit/governance_engine.nim:checkFacadeExpirations
src/core/audit/governance_engine.nim:countTelemetryRecords
src/core/audit/governance_engine.nim:evaluateSystemState
src/core/audit/governance_engine.nim:formatStateReport
src/core/audit/governance_engine.nim:readTopologyLockModules
src/core/audit/governance_engine.nim:runGovernanceCycle
src/core/audit/governance_engine.nim:shouldTriggerAutotuning
src/core/audit/hotspot_analyzer.nim:computeChurnScores
src/core/audit/hotspot_analyzer.nim:computeChurnScoresCached
src/core/audit/hotspot_analyzer.nim:getHeadHash
src/core/audit/hotspot_analyzer.nim:runGitLog
src/core/audit/hotspot_analyzer.nim:tryReadChurnCache
src/core/audit/hotspot_analyzer.nim:writeChurnCache
src/core/audit/hotspot_gate.nim:runHotspotCheck
src/core/audit/sad_gate.nim:auditChangedFiles
src/core/audit/sad_gate.nim:auditChangedFilesWithHotspotAwareness
src/core/audit/sad_gate.nim:auditFile
src/core/audit/sad_gate.nim:calculateEnforcementRadius
src/core/audit/sad_gate.nim:daysUntilEnforcement
src/core/audit/sad_gate.nim:formatHardeningNotice
src/core/audit/sad_gate.nim:isExempt
src/core/audit/sad_gate.nim:isOverrideActive
src/core/audit/sad_gate.nim:logHardeningAudit
src/core/audit/sad_gate.nim:readOverrideConfig
src/core/audit/sad_gate.nim:sadScore
src/core/audit/sad_gate.nim:writeBackRegistry
src/core/boundary/axiom_registry_loader.nim:loadAxiomRegistry
src/core/boundary/boundary_extraction_helpers.nim:loadSourceFromNodeId
src/core/boundary/boundary_extraction_main.nim:logRefactorHint
src/core/boundary/boundary_extractor_part1.nim:extractBoundaries
src/core/boundary/boundary_extractor_part1_part1.nim:generateHintFromParamTypes
src/core/boundary/boundary_extractor_part1_part1.nim:injectVirtualHintToSource
src/core/boundary/boundary_extractor_part1_part1.nim:rewriteVirtualHintComment
src/core/boundary/type_registry.nim:buildTypeRegistry
src/core/contract/contract_ast_extractor.nim:extractContractFromNimBody
src/core/contract/contract_ast_extractor.nim:tryExtractContractViaAst
src/core/contracts/universal_pipeline_contract.nim:buildSemanticHybridUniversalPipelineResult
src/core/diagnostics/diagnostics_engine_main.nim:buildStructuralDiagnosis
src/core/diagnostics/diagnostics_engine_main.nim:extractProcName
src/core/diagnostics/diagnostics_engine_main.nim:hasLoopStructure
src/core/diagnostics/diagnostics_engine_main.nim:hasRecursiveShape
src/core/diagnostics/pattern_guard.nim:checkApplicability
src/core/diagnostics/refactoring_engine.nim:applyRefactoringTemplate
src/core/encoding/smt_to_lean/private/arithmetic_expr.nim:generateAndWriteSmtQuery
src/core/encoding/smt_to_lean_translate.nim:extractZ3ProofTrace
src/core/encoding/smt_to_lean_translate.nim:generateAndWriteLeanTheorem
src/core/encoding/vfs.nim:clearVfs
src/core/encoding/vfs.nim:initVfs
src/core/encoding/vfs.nim:readVfs
src/core/encoding/vfs.nim:vfsExists
src/core/encoding/vfs.nim:writeVfsLean
src/core/encoding/vfs.nim:writeVfsZ3
src/core/gate/file_hash_cache.nim:collectHashes
src/core/gate/file_hash_cache.nim:computeFileHash
src/core/gate/file_hash_cache.nim:computeMerkleRootCached
src/core/gate/file_hash_cache.nim:getFileMtime
src/core/gate/file_hash_cache.nim:getOrComputeHash
src/core/gate/file_hash_cache.nim:loadFileHashCache
src/core/gate/file_hash_cache.nim:save
src/core/gate/gate_cas.nim:compileGateToCas
src/core/gate/gate_cas.nim:computeCasKey
src/core/gate/gate_cas.nim:computeSourceHash
src/core/gate/gate_cas.nim:execWithBond
src/core/gate/gate_cas.nim:installStableEntry
src/core/gate/gate_cas.nim:resolveCasDir
src/core/gate/gate_cas.nim:resolveCasPath
src/core/gate/gate_cas_gc.nim:entryAgeSec
src/core/gate/gate_cas_gc.nim:isBeingWritten
src/core/gate/gate_cas_gc.nim:isGcLockStale
src/core/gate/gate_cas_gc.nim:recordCasGcRun
src/core/gate/gate_cas_gc.nim:runCasGc
src/core/gate/gate_cas_gc.nim:shouldRunCasGc
src/core/gate/gate_cas_gc.nim:triggerBackgroundCasGc
src/core/gate/gate_memo.nim:acquireMigrationLock
src/core/gate/gate_memo.nim:advanceCacheEpoch
src/core/gate/gate_memo.nim:computeBuildEnvHash
src/core/gate/gate_memo.nim:computeCompositeLockHash
src/core/gate/gate_memo.nim:computeMerkleRoot
src/core/gate/gate_memo.nim:computeMerkleRootFromPaths
src/core/gate/gate_memo.nim:currentCacheEpoch
src/core/gate/gate_memo.nim:flushFileHashCache
src/core/gate/gate_memo.nim:garbageCollectOldEpochs
src/core/gate/gate_memo.nim:initFileHashCache
src/core/gate/gate_memo.nim:isLockStale
src/core/gate/gate_memo.nim:loadGateMemo
src/core/gate/gate_memo.nim:migrateFromFlat
src/core/gate/gate_memo.nim:releaseMigrationLock
src/core/gate/gate_memo.nim:saveGateMemo
src/core/gate/gate_memo.nim:shouldSkipGate
src/core/gate/git_snapshot.nim:captureGitLines
src/core/gate/git_snapshot.nim:captureGitOutput
src/core/gate/git_snapshot.nim:newGitSnapshot
src/core/gate/layer_guard.nim:runAxiomEngineCli
src/core/gate/layer_guard.nim:z3ExecPersistent
src/core/gate/resource_limits.nim:raiseRlimitNoFile
src/core/gate/scheduler.nim:recordDuration
src/core/gate/workspace_receipt.nim:computeReceipt
src/core/gate/workspace_receipt.nim:execGit
src/core/gateway/gateway_main.nim:proveAxiomNode
src/core/gateway/gateway_main.nim:registerEvidenceWriter
src/core/gateway/gateway_main.nim:registerZ3PersistentProver
src/core/identity/axiom_env.nim:treeSitterNimAvailable
src/core/identity/axiom_env.nim:treeSitterNimPath
src/core/identity/tree_sitter_path.nim:leanParserLib
src/core/identity/tree_sitter_path.nim:nimParserLib
src/core/identity/tree_sitter_path.nim:parserLibPath
src/core/interfaces/io_executor.nim:execute
src/core/interfaces/io_executor.nim:executeGit
src/core/io/file_utils.nim:computeFileHash
src/core/io/file_utils.nim:readFileSafe
src/core/io/file_utils.nim:reremoveFileOpt
src/core/io/file_utils.nim:writeFileSafe
src/core/io/io_utils.nim:appendFileLineOpt
src/core/io/io_utils.nim:existsOrCreateDirOpt
src/core/io/io_utils.nim:getFileInfoOpt
src/core/io/io_utils.nim:moveFileOpt
src/core/io/io_utils.nim:readFileOpt
src/core/io/io_utils.nim:removeFileOpt
src/core/io/io_utils.nim:walkDirOpt
src/core/io/io_utils.nim:walkDirRecOpt
src/core/io/io_utils.nim:writeFileAtomic
src/core/io/io_utils.nim:writeFileOpt
src/core/io/io_utils.nim:writeStderrLine
src/core/json/json_safe.nim:safeParseJson
src/core/json/json_safe.nim:safeParseJsonFile
src/core/json/json_utils.nim:readJsonFile
src/core/json/json_utils.nim:readJsonFileNode
src/core/json/json_utils.nim:writePrettyJsonFile
src/core/judge/lean_replay.nim:runLeanReplay
src/core/judge/lean_replay.nim:sanitizeAndWriteLeanSource
src/core/judge/smart_search.nim:generateSemanticHint
src/core/judge/smart_search.nim:generateSemanticHintWithStrategy
src/core/judge/the_judge_eval.nim:executeProof
src/core/judge/the_judge_eval.nim:runLeanReplay
src/core/logging/log_compaction.nim:archiveOldCompacted
src/core/logging/log_compaction.nim:compactAll
src/core/logging/log_compaction.nim:compactAndArchive
src/core/logging/log_compaction.nim:compactGate
src/core/logging/log_compaction.nim:countShards
src/core/logging/log_compaction.nim:enforceShardLimit
src/core/logging/log_compaction.nim:oldestShardTimestamp
src/core/logging/sharded_log.nim:append
src/core/logging/sharded_log.nim:moveFileSafe
src/core/logging/sharded_log.nim:readAll
src/core/logging/sharded_log.nim:recentEntries
src/core/logic/lean_diagnostic.nim:analyzeSpecComplexity
src/core/orchestration/pipeline_dispatch.nim:handleDetectiveStage
src/core/orchestration/pipeline_dispatch.nim:handleJudgeStage
src/core/orchestration/pipeline_dispatch.nim:handleLegislatorStage
src/core/orchestration/pipeline_dispatch.nim:handlePostProcessStage
src/core/orchestration/pipeline_dispatch.nim:handleScribeStage
src/core/orchestration/pipeline_dispatch.nim:handleSwatStage
src/core/orchestrator/cfg_builder.nim:buildControlFlowGraph
src/core/orchestrator/orchestrator_topology_worker.nim:applyCegarAbstraction
src/core/orchestrator/orchestrator_vault.nim:finalizeExecutionStats
src/core/orchestrator/orchestrator_vault.nim:hydrateVaultRecord
src/core/orchestrator/orchestrator_vault.nim:primeTransitiveFingerprintCache
src/core/parsers/cst_adapter.nim:newCstDocument
src/core/parsers/cst_adapter.nim:rootNode
src/core/parsers/cst_offset_extractor.nim:extractFuncSpan
src/core/parsers/cst_offset_extractor.nim:extractSymbolSpans
src/core/parsers/cst_offset_extractor.nim:extractTypeSpan
src/core/parsers/cst_offset_extractor.nim:findChildAfterEquals
src/core/parsers/cst_offset_extractor.nim:findFuncName
src/core/parsers/cst_offset_extractor.nim:findTypeName
src/core/parsers/cst_offset_extractor.nim:findUnnamedChildByType
src/core/parsers/cst_offset_extractor.nim:processNode
src/core/parsers/cst_offset_extractor.nim:walkChildren
src/core/parsers/cst_offset_extractor.nim:walkTypeSection
src/core/parsers/cst_offset_extractor.nim:walkWhen
src/core/parsers/tree_sitter/bindings.nim:tree_sitter_nim
src/core/parsers/tree_sitter/bindings.nim:tree_sitter_nim_raw
src/core/parsers/tree_sitter/bindings.nim:ts_parser_delete
src/core/parsers/tree_sitter/bindings.nim:ts_parser_new
src/core/parsers/tree_sitter/bindings.nim:ts_parser_parse_string
src/core/parsers/tree_sitter/bindings.nim:ts_parser_set_language
src/core/parsers/tree_sitter/bindings.nim:ts_tree_edit
src/core/parsers/tree_sitter/cache.nim:c_free
src/core/parsers/tree_sitter/cache.nim:clearCache
src/core/parsers/tree_sitter/cache.nim:parseIncremental
src/core/parsers/tree_sitter/cache.nim:parseWithCache
src/core/parsers/tree_sitter/node.nim:ts_node_child
src/core/parsers/tree_sitter/node.nim:ts_node_child_count
src/core/parsers/tree_sitter/node.nim:ts_node_end_byte
src/core/parsers/tree_sitter/node.nim:ts_node_is_named
src/core/parsers/tree_sitter/node.nim:ts_node_named_child
src/core/parsers/tree_sitter/node.nim:ts_node_named_child_count
src/core/parsers/tree_sitter/node.nim:ts_node_start_byte
src/core/parsers/tree_sitter/node.nim:ts_node_string
src/core/parsers/tree_sitter/node.nim:ts_node_type
src/core/parsers/tree_sitter/node.nim:ts_tree_delete
src/core/parsers/tree_sitter/node.nim:ts_tree_root_node
src/core/parsers/tree_sitter/nodes.nim:getChildByType
src/core/parsers/tree_sitter/nodes.nim:getChildrenByType
src/core/parsers/tree_sitter/nodes.nim:isExported
src/core/parsers/tree_sitter/parser.nim:newNimParser
src/core/parsers/tree_sitter/parser.nim:parseSource
src/core/parsers/tree_sitter_parse.nim:parseLean
src/core/parsers/tree_sitter_parse.nim:parseNim
src/core/parsers/tree_sitter_parse.nim:parseNimRes
src/core/parsers/tree_sitter_parse.nim:parseNimResSafe
src/core/parsers/tree_sitter_parse.nim:parseWithTreeSitter
src/core/parsers/tree_sitter_parser.nim:leanParserLib
src/core/parsers/tree_sitter_parser.nim:nimParserLib
src/core/parsers/tree_sitter_parser.nim:parseLean
src/core/parsers/tree_sitter_parser.nim:parseNim
src/core/parsers/tree_sitter_parser.nim:parseNimRes
src/core/parsers/tree_sitter_parser.nim:parseNimResSafe
src/core/parsers/tree_sitter_parser.nim:parseWithTreeSitter
src/core/parsers/tree_sitter_parser.nim:parserLibPath
src/core/policy/architecture_policy_part1.nim:parseAssignmentLine
src/core/policy/architecture_policy_part2.nim:loadArchitecturePolicy
src/core/policy/architecture_policy_part2.nim:parseArchitecturePolicy
src/core/policy/parsers/parse_canonical.nim:registerCanonicalSections
src/core/policy/parsers/parse_cohesion.nim:registerCohesionSections
src/core/policy/parsers/parse_dry.nim:registerDrySections
src/core/policy/parsers/parse_forbidden.nim:registerForbiddenSections
src/core/policy/parsers/parse_impure_procedures_whitelist.nim:registerImpureProceduresWhitelistSection
src/core/policy/parsers/parse_informational.nim:registerInformationalSections
src/core/policy/parsers/parse_interfaces.nim:registerInterfaceSections
src/core/policy/parsers/parse_layers.nim:registerLayerSections
src/core/policy/parsers/parse_meta.nim:registerMetaSections
src/core/policy/parsers/parse_ocp.nim:registerOcpSections
src/core/policy/parsers/parse_surface_area.nim:registerSurfaceAreaSections
src/core/policy/section_parsers.nim:getHandler
src/core/policy/section_parsers.nim:isRegistered
src/core/policy/section_parsers.nim:registerSection
src/core/policy/section_parsers.nim:validateRegistry
src/core/proof/function_source_extractor.nim:extractFunctionSource
src/core/proof/proof_budget.nim:checkBudget
src/core/proof/proof_budget.nim:elapsedMs
src/core/proof/proof_budget.nim:initProofBudget
src/core/proof/proof_universe_lock.nim:buildProofUniverseLockGraph
src/core/proof/proof_universe_lock.nim:collectJsonFiles
src/core/proof/proof_universe_lock.nim:computeDeterministicCertHash
src/core/proof/proof_universe_lock.nim:computeGraphMerkleHash
src/core/proof/proof_universe_lock.nim:computeProofUniverseLock
src/core/proof/proof_universe_lock.nim:copyFileResult
src/core/proof/proof_universe_lock.nim:parseAsiFromStateFile
src/core/proof/proof_universe_lock.nim:readFileResult
src/core/proof/proof_universe_lock.nim:readProofUniverseLock
src/core/proof/proof_universe_lock.nim:rejectProofUniverseLock
src/core/proof/proof_universe_lock.nim:removeFileIfExists
src/core/proof/proof_universe_lock.nim:sha256FileResult
src/core/proof/proof_universe_lock.nim:verifyProofUniverseLock
src/core/proof/proof_universe_lock.nim:writeStderr
src/core/protocol/axiom_protocol.nim:error
src/core/protocol/axiom_protocol.nim:fail
src/core/protocol/axiom_protocol.nim:newProtocol
src/core/protocol/axiom_protocol.nim:ok
src/core/protocol/axiom_protocol.nim:safeTimestamp
src/core/protocol/axiom_protocol.nim:skip
src/core/protocol/axiom_protocol.nim:timeout
src/core/protocol/protocol_compat.nim:fromJsonString
src/core/protocol/protocol_compat.nim:fromLegacy
src/core/runtime/axiom_runner.nim:execute
src/core/runtime/axiom_task.nim:fail
src/core/runtime/axiom_task.nim:ok
src/core/runtime/golden_version.nim:computeGateRunnerHash
src/core/runtime/golden_version.nim:computePolicyHash
src/core/runtime/golden_version.nim:loadGoldenManifest
src/core/runtime/golden_version.nim:updateGoldenFile
src/core/runtime/golden_version.nim:validateGoldenFreshness
src/core/runtime/golden_version.nim:validateSingleGolden
src/core/runtime/script_wrapper.nim:execute
src/core/solver/equivalence_checker.nim:buildEquivalenceQuery
src/core/solver/equivalence_checker.nim:verifySemanticEquivalence
src/core/solver/shell_bridge.nim:checkToolAvailable
src/core/solver/shell_bridge.nim:runCommandInDir
src/core/solver/shell_bridge.nim:runCommandSeqInDir
src/core/solver/solver_bridge.nim:checkWithTelemetry
src/core/solver/solver_bridge.nim:dumpEvidence
src/core/solver/solver_bridge.nim:runKInductionCheck
src/core/solver/z3_telemetry.nim:appendZ3Telemetry
src/core/sorter/sorter_core_algo.nim:syncNodeAxiomFromVault
src/core/spec/spec_generator_helpers.nim:parseAliases
src/core/spec/spec_generator_helpers.nim:parseEnums
src/core/spec/spec_generator_helpers.nim:parseFunctions
src/core/spec/spec_generator_helpers.nim:parseGlobalVars
src/core/spec/spec_generator_helpers.nim:parseStructures
src/core/spec/spec_generator_main.nim:generateLeanSpecFromSources
src/core/symbol_graph/global_symbol_graph_builder_part1.nim:loadIncrementalGraphCache
src/core/symbol_graph/global_symbol_graph_builder_part2.nim:buildGlobalSymbolGraph
src/core/symbol_graph/global_symbol_graph_builder_part2.nim:computeSourceMerkleRoot
src/core/symbol_graph/global_symbol_graph_builder_part2.nim:loadGlobalSymbolGraphCache
src/core/symbol_graph/global_symbol_graph_builder_part2.nim:saveGlobalSymbolGraphCache
src/core/symbol_graph/global_symbol_graph_builder_part2.nim:saveIncrementalGraphCache
src/core/sync/sync_utils_process.nim:acquireResourceSemaphoreTimeout
src/core/sync/sync_utils_process.nim:acquireTicket
src/core/sync/sync_utils_process.nim:epochMilliseconds
src/core/sync/sync_utils_process.nim:getCurrentThreadId
src/core/sync/sync_utils_process.nim:killManagedProcess
src/core/sync/sync_utils_process.nim:readCurrentRssBytes
src/core/sync/sync_utils_process.nim:readSystemCpuLoadRatio
src/core/sync/sync_utils_process.nim:runProcessWithTimeout
src/core/sync/sync_utils_process.nim:terminateProcessForce
src/core/sync/sync_utils_resource.nim:acquireResourceSemaphore
src/core/sync/sync_utils_resource.nim:acquireResourceSemaphoreTimeout
src/core/sync/sync_utils_resource.nim:acquireTicket
src/core/sync/sync_utils_resource.nim:readAvailableMemoryBytes
src/core/sync/sync_utils_resource.nim:readCpuLoadRatio
src/core/sync/sync_utils_resource.nim:refreshResourceSemaphore
src/core/sync/sync_utils_resource.nim:sampleSystemResources
src/core/telemetry/trace_normalizer.nim:detectProjectRoot
src/core/test_support/sandbox_guard.nim:captureEnv
src/core/test_support/sandbox_guard.nim:restoreEnv
src/core/testing/pbt_engine.nim:checkProperty
src/core/testing/pbt_engine.nim:emitPbtMarker
src/core/testing/pbt_engine.nim:initSeed
src/core/testing/pbt_engine.nim:shrinkToMinimal
src/core/topology/declaration.nim:isForwardingStub
src/core/topology/declaration.nim:listGhostPaths
src/core/topology/declaration.nim:parseTopologyDeclaration
src/core/topology/import_graph.nim:buildImportGraph
src/core/topology/import_graph.nim:countCoreModules
src/core/topology/import_graph.nim:extractCoreImports
src/core/topology/import_graph.nim:resolveModuleName
src/core/topology/lock.nim:checkLockCompliance
src/core/topology/lock.nim:checkTransitionalTTL
src/core/topology/lock.nim:parseTopologyLock
src/core/topology/lock.nim:reconcileLockModel
src/core/topology/lock.nim:syncLockToFilesystem
src/core/topology/plan.nim:computeDrift
src/core/topology/plan.nim:computePlan
src/core/topology/plan.nim:computeRewrites
src/core/topology/plan.nim:fileExistsRelative
src/core/topology/plan.nim:findConsumers
src/core/topology/plan.nim:scanSourceFiles
src/core/topology/policy.nim:parseTopologyPolicy
src/core/topology/suggest.nim:runDeclarationAudit
src/core/topology/suggest.nim:runTopologyAuditWithSuggestions
src/core/topology/topology_engine.nim:loadTopologyCache
src/core/topology/topology_engine.nim:saveTopologyCache
src/core/topology/topology_engine.nim:updateBoundaryKinds
src/core/translator/nim_ast_to_json_nodes.nim:sourceCodeToJsonNodes
src/core/trusted/asset_collector.nim:collectFunctions
src/core/trusted/effect_shim.nim:safeParseJson
src/core/trusted/provenance_guard.nim:drainThreadProvenanceLog
src/core/trusted/provenance_guard.nim:enforceProvenanceBeforeWrite
src/core/trusted/provenance_guard.nim:isProvenanceProtected
src/core/trusted/provenance_guard.nim:recordProvenanceOverwriteAttempt
src/core/trusted/provider_interface.nim:executeProof
src/core/trusted/reasoning_recorder.nim:drainThreadReasoningTrail
src/core/trusted/reasoning_recorder.nim:recordPhase
src/core/trusted/reasoning_recorder.nim:recordReasoningEvent
src/core/trusted/reasoning_recorder.nim:recordVerdict
src/core/trusted/stdlib_shield.nim:safeDirExists
src/core/trusted/stdlib_shield.nim:safeMoveFile
src/core/trusted/stdlib_shield.nim:safeParseFile
src/core/trusted/stdlib_shield.nim:safeParseJson
src/core/trusted/stdlib_shield.nim:safeParseXml
src/core/trusted/stdlib_shield.nim:safeParseXmlFromString
src/core/trusted/stdlib_shield.nim:safeReadFile
src/core/trusted/stdlib_shield.nim:safeWalkDirRec
src/core/utils/io_utils_isolation.nim:isolatedMoveFile
src/core/utils/io_utils_isolation.nim:isolatedParseXml
src/core/utils/io_utils_isolation.nim:isolatedWriteFile
src/core/utils/repo_root.nim:findRepoRoot
src/core/utils/test_helper.nim:runGateInRepo
src/core/vault/vault_factory.nim:findTraceByRef
src/core/vault/vault_factory.nim:getProof
src/core/vault/vault_factory.nim:listSessions
src/core/vault/vault_factory.nim:loadVaultStore
src/core/vault/vault_factory.nim:persistVaultStore
src/core/vault/vault_factory.nim:saveProof
src/core/vault/vault_factory.nim:saveSession
src/core/vault/vault_manager_spec.nim:currentVaultTimestamp
src/core/vault/vault_manager_storage.nim:loadAxiomSpecFile
src/core/vault/vault_manager_storage.nim:readAxiomSpecFile
src/core/vault/vault_manager_storage.nim:storeAxiomSpec
```

## Non-Side-Effect Errors (manual review)

- ../Axiom-core/src/core/types/domain_utils.nim(78, 41) Error: undeclared identifier: 'certYellow'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 20) Error: undeclared identifier: 'extractRuleBundle'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 37) Error: attempting to call routine: 'extractRuleBundle'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 37) Error: attempting to call routine: 'extractRuleBundle'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 37) Error: attempting to call undeclared routine: 'extractRuleBundle'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 37) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(64, 7) Error: 'let' symbol requires an initialization
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 53) Error: expression 'ruleBundle' has no type (or is ambiguous)
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 63) Error: undeclared field: 'transition'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 63) Error: undeclared field: '.'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 63) Error: undeclared field: '.'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 63) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 76) Error: expression 'ruleBundle' has no type (or is ambiguous)
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 86) Error: undeclared field: 'invariant'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 86) Error: undeclared field: '.'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 86) Error: undeclared field: '.'
- ../Axiom-core/src/core/orchestration/pipeline_dispatch.nim(65, 86) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(227, 29) Error: nodeTypeKindMap[ntype] can raise an unlisted exception: ref KeyError
- ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(314, 6) Error: public implementation 'cst_offset_extractor.sourceText(node: TSNode, source: string)' has non-public forward declaration at ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(74, 6)
- ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(323, 6) Error: public implementation 'cst_offset_extractor.calcIndent(source: string, byteOffset: int)' has non-public forward declaration at ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(75, 6)
- ../Axiom-core/src/core/parsers/cst_offset_extractor.nim(66, 6) Error: implementation of 'cst_offset_extractor.extractFuncSpan(node: TSNode, source: string, depth: int, inWhen: bool)' expected
- ../Axiom-core/src/core/runtime/axiom_runner.nim(59, 16) Error: undeclared field: 'isOk' for type results.Result [type declared in ../Axiom-core/src/core/types/results.nim(9, 3)]
- ../Axiom-core/src/core/runtime/axiom_runner.nim(59, 16) Error: undeclared field: '.' for type results.Result [type declared in ../Axiom-core/src/core/types/results.nim(9, 3)]
- ../Axiom-core/src/core/runtime/axiom_runner.nim(59, 16) Error: undeclared field: '.' for type results.Result [type declared in ../Axiom-core/src/core/types/results.nim(9, 3)]
- ../Axiom-core/src/core/runtime/axiom_runner.nim(59, 16) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/runtime/axiom_runner.nim(61, 34) Error: attempting to call undeclared routine: 'get'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(61, 34) Error: attempting to call undeclared routine: '.'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(61, 34) Error: attempting to call undeclared routine: '.'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(61, 38) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/runtime/axiom_runner.nim(64, 40) Error: attempting to call undeclared routine: 'error'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(64, 40) Error: attempting to call undeclared routine: '.'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(64, 40) Error: attempting to call undeclared routine: '.'
- ../Axiom-core/src/core/runtime/axiom_runner.nim(64, 46) Error: expression '' has no type (or is ambiguous)
- ../Axiom-core/src/core/runtime/axiom_runner.nim(64, 26) Error: type mismatch: got 'seq[Error Type]' for '@[]' but expected 'seq[string]'
