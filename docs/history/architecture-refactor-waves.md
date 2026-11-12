# Architecture Refactor Waves — Historical Documentation

> **Status**: COMPLETE  
> **Migrated from**: `tests/features/architecture_refactor.feature`  
> **Date**: 2026-05-30  
> **Authority**: Plan Phase 3 — migration tracker consolidation

This document preserves the architecture refactor BDD scenarios that verified
file existence and module boundaries during the 8-wave decomposition.
These are **historical contracts**, not active regression guards.

---


Feature: Architecture Refactor Executable Contracts

  As an Axiom maintainer
  I want architecture refactor BDD scenarios to have an executable runner
  So that refactor contracts cannot remain as non-running documentation

  Background:
    Given architecture refactor feature runner is executing

  Scenario: Pipeline split modules compile and export their direct contracts
    When nim check is run on src/core/logic/pipeline_healing_logic.nim
    And nim check is run on src/verification/proof_synthesis_engine.nim
    And nim check is run on src/verification/healing_orchestrator.nim
    Then all compilations should succeed
    And mergeInvariantClauses should be importable from core/logic/pipeline_healing_logic
    And injectNimAssertions should be importable from core/logic/pipeline_healing_logic
    And runSemanticProofReplay should be importable from verification/proof_synthesis_engine
    And runSelfHealingLoop should be importable from verification/healing_orchestrator
    And runLeanProofRefinementLoop should be importable from verification/healing_orchestrator

  Scenario: Universal pipeline facade does not re-export healing orchestration
    Given file src/verification/universal_pipeline_core.nim
    Then file should not contain "export healing_orchestrator"
    And file should not contain "proc runSelfHealingLoop*("
    And file should not contain "proc runLeanProofRefinementLoop*("
    And file should contain "import verification/proof_synthesis_engine"

  Scenario: Healing consumers declare direct orchestration dependencies
    Given file src/personas/swat.nim
    Then file should contain "import verification/healing_orchestrator"
    Given file src/personas/judge.nim
    Then file should contain "import verification/healing_orchestrator"
    Given file src/verification/pipeline_core_runner.nim
    Then file should contain "import verification/healing_orchestrator"
    And file should contain "import core/logic/pipeline_healing_logic"

  Scenario: Architecture refactor feature has a dedicated executable runner
    Given file tests/gateway/architecture_refactor_feature_test.nim
    Then file should contain "proc runArchitectureRefactorFeature"
    And file should contain "tests/features/architecture_refactor.feature"

  Scenario: Architecture gate enforces layer policy from the src allowlist SSOT
    Given file src/gate/architecture_guard.nim
    Then file should contain "architecturePolicyPath*"
    And file should contain "src/allowed_imports.lock"
    And file should contain "proc loadArchitecturePolicy*"
    And file should contain "parseModuleRole"
    And file should contain "extractStringConstants"
    And file should contain "proc runArchitectureGate*"
    Given file allowed_imports.lock
    Then file should not exist
    Given file tests/gateway/architecture_gate_test.nim
    Then file should contain "stale root allowlist cannot override src allowlist"
    And file should contain "unregistered public API sprawl is rejected"
    And file should contain "duplicate long named constants are rejected"
    Given file tests/gateway/architecture_principles_gate_test.nim
    Then file should contain "dependency budget still blocks ordinary over-coupled functions"
    And file should contain "dependency budget permits explicit vault storage boundary"
    And file should contain "dependency budget permits architecture gate composition root"
    And file should contain "DRY gate ignores stale duplicate fingerprints"
    And file should contain "DRY gate rejects current verified duplicate fingerprints"

  Scenario: Architecture gate blocks SSOT and SOLID red-line violations
    Given file src/gate/architecture_guard.nim
    Then file should contain "hasDirectCertificateMutation"
    And file should contain "hasDirectSolverDependency"
    And file should contain "hasConcreteEngineBranch"
    Given file tests/gateway/architecture_gate_test.nim
    Then file should contain "direct certificate mutation is rejected outside certificate_manager"
    And file should contain "direct core solver dependency is rejected outside provider boundary"

  Scenario: Core modules use compiler-verified purity without cast bypasses
    Given file src/core/json_utils.nim
    Then file should not contain "{.cast(noSideEffect).}"
    Given file src/core/solver/z3_pool.nim
    Then file should not contain "{.cast(noSideEffect).}"
    When nim check is run on src/core/json_utils.nim
    And nim check is run on src/core/solver/z3_pool.nim
    Then all compilations should succeed

  Scenario: Z3Provider is wired to persistent pool instead of returning stub
    Given file src/core/provider_interface.nim
    Then file should contain "z3ExecPersistent"
    And file should not contain "Z3Provider not yet wired"

  Scenario: gate_rules classifier uses exception-safe wrappers instead of bare discard
    Given file src/verification/gate_rules_module_classifier.nim
    Then file should contain "readFileOpt"
    And file should contain "parseNimRes"
    And file should not contain "except CatchableError:\n      discard"
    When nim check is run on src/verification/gate_rules_module_classifier.nim
    Then all compilations should succeed

  Scenario: Z3 prover calls go through ProverInterface instead of direct z3ExecPersistent
    Given file src/core/intrinsic_filter.nim
    Then file should not contain "z3ExecPersistent"
    And file should contain "type TrivialityOracle"
    Given file src/verification/analyzer.nim
    Then file should not contain "z3ExecPersistent"
    Given file src/cli/commands/observability.nim
    Then file should not contain "z3ExecPersistent"
    Given file src/core/provider_interface.nim
    Then file should contain "proc prove*(provider: Z3Provider"
    And file should contain "z3ExecPersistent"

  Scenario: Physically impure modules are exempted from noSideEffect audit
    Given file src/core/.physically_impure_modules
    Then file should contain "sync_utils"
    And file should contain "z3_pool"
    And file should contain "symbolic_engine"
    Given file src/verification/.physically_impure_modules
    Then file should contain "translation_validator"
    And file should contain "policy_engine"
    And file should contain "rebuild_assets"

  Scenario: Procedure gate enforces 4-step integrity for source changes
    Given file src/cli/procedure_gate.nim
    Then file should contain "4-Step Integrity Enforcement"
    And file should contain "Intent → Specification → Test → Code"
    And file should contain "hasIntent"
    And file should contain "hasSpecification"
    And file should contain "hasTest"
    Given file src/core/file_utils.nim
    Then file should contain "isBddEvidence"
    And file should contain "isTestEvidence"
    And file should contain "isHistoryFile"
    When nim check is run on tests/unit/procedure_gate_test.nim
    Then all compilations should succeed

  Scenario: Lean4Provider is wired to runLeanCompiler instead of returning stub
    Given file src/core/provider_interface.nim
    Then file should not contain "Lean4Provider not yet wired"
    Given file src/verification/lean_lsp.nim
    Then file should contain "proc prove*(provider: Lean4Provider"
    And file should contain "runLeanCompiler"

  Scenario: Type mapping proof obligations include auto-proof fallback instead of bare sorry
    Given file src/core/spec_generator.nim
    Then file should not contain "by sorry"
    And file should contain "first | intros; rfl"
    When nim check is run on tests/unit/spec_generator_test.nim
    Then all compilations should succeed

  Scenario: Verify workflow vault preload uses request SMT-LIB2 instead of placeholder
    Given file src/cli/verify_workflow_cli.nim
    Then file should not contain 'smtlib2 = "placeholder"'
    And file should contain "smtlib2 = request.expectedSmtlib2"
    When nim check is run on tests/unit/vault_manager_test.nim
    Then all compilations should succeed

  Scenario: Ecosystem linkage resolves standard library contract from local manifest
    Given file src/core/ecosystem_linkage.nim
    Then file should not contain "func resolveStandardLibraryContract"
    And file should contain "proc resolveStandardLibraryContract"
    And file should contain "fileExists"
    And file should contain "readJsonFile"
    When nim check is run on tests/unit/ecosystem_linkage_test.nim
    Then all compilations should succeed

  Scenario: Rebuild assets defers proposition synthesis to leanstral instead of bare stub
    Given file src/verification/rebuild_assets.nim
    Then file should not contain "stub-awaiting-proposition-generation"
    And file should contain "awaiting-leanstral-proof-synthesis"

  Scenario: Core gateway module is exempted from noSideEffect audit
    Given file src/core/.physically_impure_modules
    Then file should contain "gateway"
    Given file src/core/gateway.nim
    Then file should not contain "{.push noSideEffect.}"

  Scenario: SemanticGraph uses value object instead of ref object
    Given file src/core/semantic_graph.nim
    Then file should not contain "SemanticGraph* = ref object"
    And file should contain "SemanticGraph* = object"
    When nim check is run on src/core/semantic_graph.nim
    Then all compilations should succeed

  Scenario: ast_extractor returns Result instead of swallowing exceptions with discard
    Given file src/verification/ast_extractor.nim
    Then file should not contain "proc collectModuleFunctions*(source: string): HashSet[string]"
    And file should not contain "proc collectGlobalSymbols*(source: string): HashSet[string]"
    And file should not contain "proc extractFunctionBody*(source: string; functionName: string): tuple[found: bool; body: string]"
    And file should contain "Result[HashSet[string], string]"
    And file should contain "Result[tuple[found: bool; body: string], string]"
    And file should contain "proc getCachedFunctionNodeIndex*(source: string): Result[Table[string, XmlNode], string]"
    And file should contain "proc getCachedNimAst*(source: string): Result[XmlNode, string]"
    When nim check is run on src/verification/ast_extractor.nim
    Then all compilations should succeed

  Scenario: IO utility wrappers provide exception-safe alternatives to bare discard
    Given file src/core/io_utils.nim
    Then file should contain "proc readFileOpt"
    And file should contain "proc getFileInfoOpt"
    And file should contain "proc walkDirRecOpt"
    When nim check is run on src/core/io_utils.nim
    Then all compilations should succeed

  Scenario: Hint persistence uses an explicit domain manager
    Given file src/cli/commands/heal_injection.nim
    Then file should contain "type HintManager"
    And file should contain "proc writeHeader"
    And file should contain "proc writeBody"
    And file should contain "proc saveHint*("
    When nim check is run on src/cli/main.nim
    Then all compilations should succeed

  Scenario: Universal Lean sanitizer is table driven
    Given file src/translator/universal_assembler.nim
    Then file should contain "type LeanReplacementRule"
    And file should contain "func applyReplacementRules"
    And file should contain "bodyArtifactRules"
    And file should contain "bodyReservedWordRules"
    When nim check is run on src/translator/universal_assembler.nim
    Then all compilations should succeed

  Scenario: Cpp tokenization flows through boundary scanners
    Given file src/core/tree_sitter_bridge.nim
    Then file should contain "func skipCppLineComment"
    And file should contain "func skipCppBlockComment"
    And file should contain "func scanCppIdentifier"
    And file should contain "func scanCppNumber"
    When nim check is run on src/core/tree_sitter_bridge.nim
    Then all compilations should succeed

  Scenario: Path condition extraction uses focused collectors
    Given file src/core/boundary_extractor.nim
    Then file should contain "func addUniquePathCondition"
    And file should contain "func collectControlFlowConditions"
    And file should contain "func collectAssignmentConditions"
    And file should contain "func collectConditionalReturnConditions"
    When nim check is run on src/core/boundary_extractor.nim
    Then all compilations should succeed

  Scenario: Heal node execution passes explicit command state
    Given file src/cli/commands/heal.nim
    Then file should contain "type HealContext"
    And file should contain "proc runSourceHintCommand"
    And file should contain "proc runBoundaryExtractorCommand"
    And file should contain "proc executeHealNode"
    When nim check is run on src/cli/main.nim
    Then all compilations should succeed

  Scenario: Primitive Lean proof assembly uses explicit proof builders
    Given file src/core/smt_to_lean_bridge.nim
    Then file should contain "func primitiveProofIndent"
    And file should contain "func primitiveBulletProof"
    And file should contain "func buildPrimitiveAndTactics"
    And file should contain "func assemblePrimitiveProof"
    When nim check is run on src/core/smt_to_lean_bridge.nim
    Then all compilations should succeed

  Scenario: SMT assertions bind every Lean replay hypothesis
    Given file src/core/smt_to_lean_bridge.nim
    Then file should contain "hypotheses.add"
    And file should contain "hExpr"
    And file should not contain "asserts[i].expr.children[0].atom == \"not\""
    Given file tests/gateway/smt_to_lean_type_aware_test.nim
    Then file should contain "top-level not assertion binds h0 for proof replay"

  Scenario: Force heal reopens legacy vacuity quarantine
    Given file src/cli/wf_state.nim
    Then file should contain "resetForceHealQuarantine"
    And file should contain "extractor_limitation"
    And file should contain "vacuous_primitive"
    Given file src/cli/commands/heal.nim
    Then file should contain "resetForceHealQuarantine"
    Given file src/cli/ax_workflow_shortcuts.nim
    Then file should contain "--force-heal"

  Scenario: Global symbol graph uses frozen topology order
    Given file src/core/global_symbol_graph.nim
    Then file should contain "canonicalizeGlobalSymbolGraph"
    And file should contain "paths.sort(cmp[string])"
    And file should contain "sortedSymbolKeys"
    Given file tests/unit/global_symbol_graph_test.nim
    Then file should contain "canonical graph ordering is stable"

  Scenario: Certified exemptions leave the proof denominator
    Given file src/core/smtlib2_util.nim
    Then file should contain "isCertifiedExemptFunctionSource"
    And file should contain "vacuous_primitive"
    Given file src/cli/wf_state_vacuity.nim
    Then file should contain "certified_exempt"
    Given file src/cli/wf_state.nim
    And file should contain "applyCertifiedExemptionsFromSource"

  Scenario: Local proof workflows can request soft gate failure
    Given file src/cli/ax_workflow_shortcuts.nim
    Then file should contain "allowSoftFail"
    And file should contain "--allow-soft-fail"
    Given file src/cli/wf_runners.nim
    Then file should contain "allowSoftFail"

  Scenario: Leanstral self-correction uses explicit correction context
    Given file src/cli/commands/heal_leanstral.nim
    Then file should contain "type LeanstralCorrectionContext"
    And file should contain "proc initLeanstralCorrectionContext"
    And file should contain "proc buildLeanstralCorrectionPrompt"
    And file should contain "proc handleRejectedLeanstralRound"
    When nim check is run on src/cli/main.nim
    Then all compilations should succeed

  Scenario: Pure logic modules enforce noSideEffect at module scope
    Given file src/core/logic/pipeline_fingerprint_engine.nim
    Then file should contain "{.push noSideEffect.}"
    Given file src/core/logic/pipeline_healing_logic.nim
    Then file should contain "{.push noSideEffect.}"
    Given file src/core/logic/semantic_theorem_builder.nim
    Then file should contain "{.push noSideEffect.}"

  Scenario: Verification modules with physical side effects are exempted
    Given file src/verification/.physically_impure_modules
    Then file should contain "ast_extractor"
    And file should contain "analyzer"
    And file should contain "dependency_analyzer"
    And file should contain "discovery_error"
    And file should contain "gate_registry"
    And file should contain "gate_rules"
    And file should contain "healing_orchestrator"
    Given file src/verification/ast_extractor.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/analyzer.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/dependency_analyzer.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/discovery_error.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/gate_registry.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/gate_rules.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/healing_orchestrator.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/integrity_guard.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/lean_lsp.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/leanstral_gateway.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/leanstral_prompt.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/pipeline_core_runner.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/pipeline_lean_spec_inference.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/pipeline_negative_scan.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/proof_summarizer.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/proof_synthesis_engine.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/static_rules.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/thought_dashboard.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/translation_validator.nim
    Then file should contain "{.push noSideEffect.}"
    Given file src/verification/universal_pipeline.nim
    Then file should not contain "{.push noSideEffect.}"
    Given file src/verification/universal_pipeline_core.nim
    Then file should not contain "{.push noSideEffect.}"

  Scenario: No source file contains bare discard in exception handlers
    When grep is run for "except.*: discard" in src/
    Then grep output should be empty

  Scenario: Result[T,E] maps to Lean Except E T
    Given mapNimTypeToLean is called with "Result[int, string]"
    Then it should return "Except String Int"

  Scenario: VerifiedAxiom trust layer replaces intrinsic certificates
    Given file src/core/verified_axioms.nim
    Then file should contain "VerifiedAxiom"
    And file should contain "approved*: bool"
    Given file src/core/domain_types.nim
    Then file should contain "certVerifiedAxiom"
    And file should contain "axiomaticIntegrityIndex"
    And file should contain "formalProofIntegrityIndex"
    Given file src/verification/analyzer.nim
    Then file should contain "certverifiedaxiom"
    And file should contain "certintrinsic"
    Given file src/cli/cst_cli.nim
    Then file should contain "axiomaticIntegrityFixed4"
    And file should contain "formalProofIntegrityFixed4"

  Scenario: Lean skeleton generation leaves only tactic choice to Leanstral
    Given file src/verification/lean_skeleton.nim
    Then file should contain "buildLeanSignaturePrefix"
    And file should contain ":= by"
    And file should not contain "sorry"
    Given file src/core/the_judge.nim
    Then file should contain "leanDeterministicTacticBlock"
    And file should contain "simpa using h_sys"
    And file should not contain "(expected typ : Int)"

  Scenario: Macro and template declarations are indexed alongside procs and funcs
    Given a Nim source containing macro ok and template debug
    When indexFunctionNodes indexes the AST
    Then ok should be present in the index
    And debug should be present in the index

  Scenario: ASI denominator must reflect actual source function count
    Given the global symbol graph is built from src/
    When countSourceFunctions is called
    Then the result should be greater than the number of certificates
    And verifyCertificates should set totalTrustedFunctions to that count
    And missingCertificates should equal totalTrustedFunctions minus certificates count

  Scenario: Sparse certificate vault cannot inflate ASI to 1.0000
    Given only 4 certificates exist in src/verification/certificates/
    When ax report --calculate-asi is executed
    Then asiFixed4 should be less than "1.0000"
    And blockingFailure should be true

  Scenario: Prelude and orphan certificates do not masquerade as source blockers
    Given a certVerifiedAxiom certificate names a Lean prelude symbol
    And a stale certificate names a function removed from source
    When verifyCertificates hydrates certificate sources
    Then the prelude certificate should remain certVerifiedAxiom
    And the removed function certificate should become certStale
    And neither certificate should appear as function-not-found red

  Scenario: Same-module recursion is not an architecture cycle
    Given two functions in one module call each other
    When verifyCertificates evaluates architecture cycles
    Then no architecture-cycle red certificate should be emitted

  Scenario: ax prove accepts ax scan output directly via axiomaticFrontier
    Given ax scan produces JSON with axiomaticFrontier
    When the JSON is piped to ax prove
    Then ax prove should convert frontier to workflow nodes and proofRequests
    And each proofRequest should contain minimal two-gate SMT-LIB2

  Scenario: ax prove is the canonical scan prove heal workflow
    Given file src/cli/wf_runners.nim
    Then file should contain "workflowPhase=scan"
    And file should contain "workflowPhase=prove"
    And file should contain "workflowPhase=heal"
    And file should contain "runAxHealCli"
    Given file tests/gateway/gateway_topology_verify_test.nim
    Then file should contain "ax prove shortcut runs scan prove and heal as one command"

  Scenario: Tree-sitter parser paths remain runtime configurable
    Given file src/core/tree_sitter_bridge.nim
    Then file should contain "proc nimParserLib*()"
    And file should contain "AXIOM_TS_NIM_PARSER"
    And file should contain "proc leanParserLib*()"
    And file should contain "AXIOM_TS_LEAN_PARSER"
    And file should contain "Axiom_Enterprise-core/vendor/tree-sitter-nim/nim.so"

  Scenario: Verification facade encapsulates rebuild_assets dependencies
    Given file src/verification/rebuild_assets.nim
    Then file should contain "import verification_facade"
    And file should not contain "import ast_extractor"
    And file should not contain "import fingerprint_engine"
    And file should not contain "import certificate_manager"
    Given file src/verification/verification_facade.nim
    Then file should contain "export ast_extractor"
    And file should contain "export fingerprint_engine"
    And file should contain "export certificate_manager"
    When nim check is run on src/verification/rebuild_assets.nim
    Then all compilations should succeed

  Scenario: Analyzer blockingFailure is independent of missingCertificates
    Given file src/verification/analyzer.nim
    Then file should not contain "summary.missingCertificates > 0 or"
    And file should contain "summary.mismatchedFingerprints > 0 or"

  Scenario: Axiom prelude includes DecidableEq instances for containers
    Given file src/core/axiom_prelude.nim
    Then file should contain "DecidableEq (NimSeq α)"
    And file should contain "DecidableEq (NimOption α)"
    And file should contain "DecidableEq (Table K V)"
    When nim check is run on src/core/axiom_prelude.nim
    Then all compilations should succeed

  Scenario: Heal batch scheduler extracts scheduling functions from heal.nim
    Given file src/cli/commands/heal.nim
    Then file should contain "import ./heal_batch_scheduler"
    And file should not contain "func healScheduleTier"
    And file should not contain "func dedupeHealScheduleNodes"
    And file should not contain "proc isAlreadyCertGreen"
    And file should not contain "proc isStaleNode"
    Given file src/cli/commands/heal_batch_scheduler.nim
    Then file should contain "func healScheduleTier"
    And file should contain "func dedupeHealScheduleNodes"
    And file should contain "proc isAlreadyCertGreen"
    And file should contain "proc isStaleNode"
    When nim check is run on src/cli/commands/heal_batch_scheduler.nim
    And nim check is run on src/cli/commands/heal.nim
    Then all compilations should succeed

  Scenario: Type-system subdomain is coalesced into core/type_system directory
    Given file src/core/type_system/liquid_inference.nim
    Then file should contain "import ../symbolic_engine"
    And file should contain "import ../refinement_types"
    And file should contain "import ../tree_sitter_bridge"
    When nim check is run on src/core/type_system/liquid_inference.nim
    Then all compilations should succeed
    Given file src/core/type_system/context_aware_type_inferencer.nim
    Then file should contain "import ./liquid_inference"
    And file should contain "import ../refinement_types"
    And file should contain "import ../smart_search"
    When nim check is run on src/core/type_system/context_aware_type_inferencer.nim
    Then all compilations should succeed
    Given file src/core/boundary_extractor.nim
    Then file should contain "import ./type_system/liquid_inference"
    And file should contain "import ./type_system/context_aware_type_inferencer"
    When nim check is run on src/core/boundary_extractor.nim
    Then all compilations should succeed
    Given file src/verification/analyzer.nim
    Then file should contain "import ../core/type_system/liquid_inference"
    When nim check is run on src/verification/analyzer.nim
    Then all compilations should succeed

  Scenario: Persona interface centralizes artifact types
    Given file src/personas/persona_interface.nim
    Then file should contain "DetectiveArtifact*"
    And file should contain "JudgeArtifact*"
    And file should contain "LegislatorArtifact*"
    And file should contain "SwatArtifact*"
    And file should contain "PersonaKind*"
    Given file src/personas/detective.nim
    Then file should not contain "type DetectiveArtifact* = object"
    And file should contain "import ./persona_interface"
    Given file src/personas/judge.nim
    Then file should not contain "type JudgeArtifact* = object"
    And file should contain "import ./persona_interface"
    Given file src/personas/legislator.nim
    Then file should not contain "type LegislatorArtifact* = object"
    And file should contain "import ./persona_interface"
    Given file src/personas/swat.nim
    Then file should not contain "type SwatArtifact* = object"
    And file should contain "import ./persona_interface"
    When nim check is run on src/personas/persona_interface.nim
    And nim check is run on src/personas/detective.nim
    And nim check is run on src/personas/judge.nim
    And nim check is run on src/personas/legislator.nim
    And nim check is run on src/personas/swat.nim
    And nim check is run on src/verification/universal_pipeline.nim
    And nim check is run on src/mcp/tools.nim
    Then all compilations should succeed

  Scenario: integrity_ledger type-behavior split preserves compilation
    Given file src/core/types/ledger_types.nim
    Then file should contain "IntegrityLedgerEntry*"
    And file should contain "StateTransition*"
    And file should contain "func buildIntegrityLedger*"
    And file should contain "func detectFingerprintMismatches*"
    Given file src/verification/integrity_ledger.nim
    Then file should contain "GlobalAuditBuffer*"
    And file should contain "proc flushGlobalAuditBufferToCertificates*"
    And file should not contain "type IntegrityLedgerEntry* = object"
    Given file src/core/integrity_ledger.nim
    Then file should not exist
    When nim check is run on src/core/types/ledger_types.nim
    And nim check is run on src/verification/integrity_ledger.nim
    And nim check is run on src/verification/proof_universe_lock.nim
    And nim check is run on src/cli/wf_runners.nim
    And nim check is run on src/cli/commands/heal.nim
    And nim check is run on src/cli/wf_state.nim
    And nim check is run on src/cli/report_cli.nim
    Then all compilations should succeed

  Scenario: semantic_graph and ecosystem_linkage relocate to verification
    Given file src/core/semantic_graph.nim
    Then file should contain "## Semantic Graph"
    And file should contain "proc buildSemanticGraph*"
    Given file src/core/ecosystem_linkage.nim
    Then file should contain "## Ecosystem Linkage"
    And file should contain "proc integrateExternalNodes*"
    Given file src/verification/semantic_graph.nim
    Then file should contain "proc buildSemanticGraph*"
    And file should contain "func computeGlobalAsi*"
    Given file src/verification/ecosystem_linkage.nim
    Then file should contain "import ./semantic_graph"
    And file should contain "proc integrateExternalNodes*"
    Given file src/cli/commands/status_graph.nim
    Then file should contain "import ../../verification/semantic_graph"
    When nim check is run on src/verification/semantic_graph.nim
    And nim check is run on src/verification/ecosystem_linkage.nim
    And nim check is run on src/cli/commands/status_graph.nim
    Then all compilations should succeed

  Scenario: state_manager relocates to verification layer
    Given file src/core/state_manager.nim
    Then file should not exist
    Given file src/verification/state_manager.nim
    Then file should contain "proc loadProofState*"
    And file should contain "proc saveProofState*"
    And file should contain "proc appendThoughtTrajectory*"
    And file should contain "proc appendAuditEvent*"
    When nim check is run on src/verification/state_manager.nim
    And nim check is run on src/cli/wf_runners.nim
    And nim check is run on src/cli/commands/heal.nim
    And nim check is run on src/verification/proof_state_convergence.nim
    And nim check is run on src/verification/lean_lsp.nim
    And nim check is run on src/verification/certificate_cli.nim
    And nim check is run on src/verification/gateway.nim
    And nim check is run on src/verification/proof_universe_lock.nim
    Then all compilations should succeed

  Scenario: gateway.nim rollback to core prevents Domain->Infra violations
    Given file src/verification/gateway.nim
    Then file should not exist
    Given file src/core/gateway.nim
    Then file should contain "proc axiomQuery*"
    And file should contain "proc axiomProofRequest*"
    And file should contain "import core/domain_types"
    Given file src/verification/universal_pipeline.nim
    Then file should contain "import ../core/gateway"
    Given file src/verification/universal_pipeline_core.nim
    Then file should contain "import ../core/gateway"
    Given file src/verification/pipeline_negative_scan.nim
    Then file should contain "import ../core/gateway"
    And file should contain "import ../core/domain_types"
    When nim check is run on src/core/gateway.nim
    And nim check is run on src/verification/universal_pipeline.nim
    And nim check is run on src/verification/universal_pipeline_core.nim
    And nim check is run on src/verification/pipeline_negative_scan.nim
    Then all compilations should succeed

  Scenario: persona_interface re-export restores artifact type visibility
    Given file src/personas/persona_interface.nim
    Then file should contain "LegislatorArtifact* = object"
    And file should contain "DetectiveArtifact* = object"
    And file should contain "JudgeArtifact* = object"
    And file should contain "SwatArtifact* = object"
    Given file src/personas/legislator.nim
    Then file should contain "export persona_interface"
    Given file src/personas/detective.nim
    Then file should contain "export persona_interface"
    Given file src/personas/judge.nim
    Then file should contain "export persona_interface"
    Given file src/personas/swat.nim
    Then file should contain "export persona_interface"
    When nim check is run on src/mcp/axiom_mcp.nim
    Then compilation should succeed

  Scenario: symbolic_engine two-phase split preserves compilation
    Given file src/core/symbolic_engine.nim
    Then file should not exist
    Given file src/core/types/symbolic_types.nim
    Then file should contain "type SymSExpr* = ref SymSymSExprObj"
    And file should contain "func sVar*"
    And file should contain "func sExprToString*"
    And file should contain "func executeSymbolically*"
    Given file src/verification/loop_invariant_synthesis.nim
    Then file should contain "proc synthesizeLoopInvariant*"
    And file should contain "import core/types/symbolic_types"
    Given file src/core/boundary_extractor.nim
    Then file should contain "import core/types/symbolic_types"
    Given file src/core/refinement_types.nim
    Then file should contain "import core/types/symbolic_types"
    Given file src/verification/analyzer.nim
    Then file should contain "import ../core/types/symbolic_types"
    And file should contain "import ./loop_invariant_synthesis"
    When nim check is run on src/core/types/symbolic_types.nim
    And nim check is run on src/verification/loop_invariant_synthesis.nim
    And nim check is run on src/core/boundary_extractor.nim
    And nim check is run on src/core/refinement_types.nim
    And nim check is run on src/verification/analyzer.nim
    And nim check is run on src/verification/abstract_provider.nim
    And nim check is run on src/verification/translation_validator.nim
    Then all compilations should succeed

  Scenario: global_symbol_graph two-phase split preserves compilation
    Given file src/core/global_symbol_graph.nim
    Then file should not exist
    Given file src/core/types/global_symbol_graph_types.nim
    Then file should contain "type GlobalSymbolGraph* = object"
    And file should contain "func referenceEdgeCmp*"
    And file should contain "func indexDeclarationsInAst*"
    Given file src/verification/global_symbol_graph.nim
    Then file should contain "proc buildGlobalSymbolGraph*"
    And file should contain "proc loadGlobalSymbolGraphCache*"
    Given file src/core/global_symbol_graph_query.nim
    Then file should contain "import core/types/global_symbol_graph_types"
    Given file src/verification/analyzer.nim
    Then file should contain "import ../core/types/global_symbol_graph_types"
    And file should contain "import ./global_symbol_graph"
    When nim check is run on src/core/types/global_symbol_graph_types.nim
    And nim check is run on src/verification/global_symbol_graph.nim
    And nim check is run on src/core/global_symbol_graph_query.nim
    And nim check is run on src/verification/analyzer.nim
    And nim check is run on src/verification/semantic_graph.nim
    And nim check is run on src/verification/proof_universe_lock.nim
    Then all compilations should succeed

  Scenario: smt_hint_validation extraction from heal_injection
    Given file src/verification/smt_hint_validation.nim
    Then file should contain "func nimTypeToSmtType*"
    And file should contain "func buildNegativeSmtQuery*"
    And file should contain "proc extractZ3ProofTrace*"
    And file should contain "proc checkSemanticContrast*"
    Given file src/cli/commands/heal_injection.nim
    Then file should contain "import verification/smt_hint_validation"
    And file should contain "smt_hint_validation.checkSemanticContrast"
    And file should contain "smt_hint_validation.extractZ3ProofTrace"
    When nim check is run on src/verification/smt_hint_validation.nim
    And nim check is run on src/cli/commands/heal_injection.nim
    Then all compilations should succeed

  Scenario: heal_analysis extraction from heal.nim
    Given file src/cli/commands/heal_analysis.nim
    Then file should contain "proc analyzeBottleneck*"
    And file should contain "proc runSourceHintCommand*"
    Given file src/cli/commands/heal_parsing.nim
    Then file should contain "proc initHealContext*"
    And file should contain "proc initHealOutput*"
    And file should contain "func isVacuousHint*"
    And file should contain "func sourceHintFromFileContext*"
    Given file src/cli/commands/heal.nim
    Then file should contain "import ./heal_analysis"
    And file should contain "import ./heal_parsing"
    When nim check is run on src/cli/commands/heal_analysis.nim
    And nim check is run on src/cli/commands/heal_parsing.nim
    And nim check is run on src/cli/commands/heal.nim
    Then all compilations should succeed

  Scenario: heal_node_executor extraction from heal.nim
    Given file src/cli/commands/heal_node_executor.nim
    Then file should contain "proc executeHealNode*"
    And file should contain "proc tryStaticRuleMatch"
    And file should contain "proc tryStrategyRotation"
    And file should contain "proc tryLeanstralSynthesis"
    And file should contain "proc runBoundaryExtractorCommand"
    Given file src/cli/commands/heal.nim
    Then file should contain "import ./heal_node_executor"
    And file should not contain "proc executeHealNode"
    When nim check is run on src/cli/commands/heal_node_executor.nim
    And nim check is run on src/cli/commands/heal.nim
    Then all compilations should succeed

  Scenario: 3-way decomposition of heal.nim and heal_injection.nim
    Given file src/core/types/heal_types.nim
    Then file should contain "type HealNodeInput*"
    And file should contain "type HealNodeOutput*"
    And file should contain "type HintManagerState*"
    And file should contain "type HintValidationResult*"
    Given file src/verification/certificate/cert_writer.nim
    Then file should contain "proc writeCertGreenCertificate*"
    And file should contain "proc writePseudoVerifiedCertificate*"
    And file should contain "proc writeCertificateFromManager*"
    Given file src/core/contracts/heal_hint_manager.nim
    Then file should contain "proc acceptVerifiedAxiom*"
    And file should not contain "import verification/"
    Given file src/verification/hint_processor.nim
    Then file should contain "proc validateHintSemantics*"
    And file should contain "proc verifyLeanArtifacts*"
    And file should contain "proc writeZ3ProofTrace*"
    Given file src/cli/commands/heal_scheduler.nim
    Then file should contain "proc runHealScheduler*"
    And file should contain "type HealSchedulerResult*"
    Given file src/cli/commands/heal_state_applier.nim
    Then file should contain "proc applyHealOutputs*"
    Given file src/cli/commands/heal.nim
    Then file should contain "import ./heal_scheduler"
    And file should contain "import ./heal_state_applier"
    And file should not contain "proc executeHealNode"
    And file should not contain "proc writeZ3ProofTrace"
    Given file src/cli/commands/heal_injection.nim
    Then file should contain "import verification/hint_processor"
    And file should contain "import verification/certificate/cert_writer"
    And file should not contain "proc validateHintSemantics"
    And file should not contain "proc verifyLeanArtifacts"
    When nim check is run on src/core/types/heal_types.nim
    And nim check is run on src/verification/certificate/cert_writer.nim
    And nim check is run on src/core/contracts/heal_hint_manager.nim
    And nim check is run on src/verification/hint_processor.nim
    And nim check is run on src/cli/commands/heal_scheduler.nim
    And nim check is run on src/cli/commands/heal_state_applier.nim
    And nim check is run on src/cli/commands/heal.nim
    And nim check is run on src/cli/commands/heal_injection.nim
    Then all compilations should succeed

  Scenario: final architectural violation purge
    Given file src/core/types/semantic_types.nim
    Then file should contain "type SemanticNodeStatus*"
    And file should contain "type SemanticGraphNode*"
    And file should contain "type SemanticGraph*"
    Given file src/core/types/universe_types.nim
    Then file should contain "type ProofUniverseLock*"
    Given file src/core/integrity_refinement_loop.nim
    Then file should contain "import core/tree_sitter_bridge"
    And file should contain "import core/integrity_refinement_types"
    And file should contain "import core/logic/refinement_base"
    Given file src/core/provider_interface.nim
    Then file should contain "import core/domain_types"
    And file should contain "import core/solver/z3_pool"
    Given file src/core/metrics.nim
    Then file should contain "import core/verified_axioms"
    And file should contain "import core/topology_engine"
    And file should contain "import core/sorter_core"
    When nim check is run on src/core/types/semantic_types.nim
    And nim check is run on src/core/types/universe_types.nim
    And nim check is run on src/core/integrity_refinement_loop.nim
    And nim check is run on src/core/provider_interface.nim
    And nim check is run on src/core/metrics.nim
    Then all compilations should succeed

  Scenario: analyzer 8-stage decomposition
    Given file src/verification/analyzer.nim
    Then file should contain "proc verifyCertificates*"
    And file should not contain "proc runSymbolicGcExtract"
    And file should not contain "proc hydrateCertificate"
    And file should not contain "proc runSymbolicAnalysis"
    Given file src/verification/analyzer/analyzer_shared.nim
    Then file should contain "func keyToStatus*"
    And file should contain "func firstStringField*"
    And file should contain "func collectKnownFunctions*"
    Given file src/verification/analyzer/stages/stage_01_ast_extract.nim
    Then file should contain "proc getInMemoryCachedGraph*"
    And file should contain "proc runSymbolicGcExtract*"
    Given file src/verification/analyzer/stages/stage_02_fingerprint.nim
    Then file should contain "proc loadCertificateFromFile*"
    And file should contain "proc hydrateCertificate*"
    Given file src/verification/analyzer/stages/stage_03_dependency.nim
    Then file should contain "proc runInfluenceGate*"
    And file should contain "proc runAuditInfluence*"
    Given file src/verification/analyzer/stages/stage_04_gate_check.nim
    Then file should contain "proc runCanonicalizeAndArchGate*"
    And file should contain "proc runTypeGate*"
    And file should contain "proc runSymbolicAudit*"
    And file should contain "proc runSemanticAudit*"
    Given file src/verification/analyzer/stages/stage_05_lean_bridge.nim
    Then file should contain "proc runSymbolicAnalysis*"
    Given file src/verification/analyzer/stages/stage_06_proof_synth.nim
    Then file should contain "proc runHydrationExtract*"
    Given file src/verification/analyzer/stages/stage_07_certificate.nim
    Then file should contain "proc runVaultSync*"
    And file should contain "proc runCertLoad*"
    And file should contain "proc runVaultEnrich*"
    And file should contain "proc loadVaultIndex*"
    Given file src/verification/analyzer/stages/stage_08_reporter.nim
    Then file should contain "proc finalizeStatusCounts*"
    And file should contain "proc runFinalize*"
    And file should contain "proc auditVerificationStep*"
    When nim check is run on src/verification/analyzer.nim
    And nim check is run on src/verification/analyzer/analyzer_shared.nim
    And nim check is run on src/verification/analyzer/stages/stage_01_ast_extract.nim
    And nim check is run on src/verification/analyzer/stages/stage_02_fingerprint.nim
    And nim check is run on src/verification/analyzer/stages/stage_03_dependency.nim
    And nim check is run on src/verification/analyzer/stages/stage_04_gate_check.nim
    And nim check is run on src/verification/analyzer/stages/stage_05_lean_bridge.nim
    And nim check is run on src/verification/analyzer/stages/stage_06_proof_synth.nim
    And nim check is run on src/verification/analyzer/stages/stage_07_certificate.nim
    And nim check is run on src/verification/analyzer/stages/stage_08_reporter.nim
    Then all compilations should succeed

  Scenario: Analyzer 8-stage decomposition has zero unused imports
    Given file src/verification/analyzer.nim
    Then file should not contain "import core/results as res"
    And file should not contain "import core/metrics"
    And file should not contain "import core/json_utils"
    And file should not contain "import ../core/cfg_builder"
    And file should not contain "import ../core/provider_interface"
    And file should not contain "import ../core/tree_sitter_bridge"
    Given file src/verification/analyzer/analyzer_shared.nim
    Then file should not contain "import std/[hashes"
    Given file src/verification/analyzer/stages/stage_04_gate_check.nim
    Then file should not contain "import ../../gate_registry"
    And file should not contain "import ../analyzer_shared"
    Given file src/verification/analyzer/stages/stage_05_lean_bridge.nim
    Then file should not contain "import core/results as res"
    Given file src/verification/analyzer/stages/stage_06_proof_synth.nim
    Then file should not contain "import core/results as res"
    When nim check is run on src/verification/analyzer.nim
    And nim check is run on src/verification/analyzer/analyzer_shared.nim
    And nim check is run on src/verification/analyzer/stages/stage_01_ast_extract.nim
    And nim check is run on src/verification/analyzer/stages/stage_02_fingerprint.nim
    And nim check is run on src/verification/analyzer/stages/stage_03_dependency.nim
    And nim check is run on src/verification/analyzer/stages/stage_04_gate_check.nim
    And nim check is run on src/verification/analyzer/stages/stage_05_lean_bridge.nim
    And nim check is run on src/verification/analyzer/stages/stage_06_proof_synth.nim
    And nim check is run on src/verification/analyzer/stages/stage_07_certificate.nim
    And nim check is run on src/verification/analyzer/stages/stage_08_reporter.nim
    Then all compilations should succeed

  Scenario: Heal orchestrator shell compiles with zero unused imports
    Given file src/cli/commands/heal.nim
    Then file should not contain "import std/[json"
    And file should not contain "import std/[strutils"
    And file should not contain "import malebolgia"
    And file should not contain "import ../../core/smart_search"
    When nim check is run on src/cli/commands/heal.nim
    Then all compilations should succeed

  Scenario: Status graph command compiles after semantic_graph relocation
    Given file src/cli/commands/status_graph.nim
    Then file should contain "import ../../core/types/semantic_types"
    When nim check is run on src/cli/commands/status_graph.nim
    And nim check is run on src/cli/main.nim
    Then all compilations should succeed

  Scenario: Wave 7 topological stratification separates core from verification
    Given file src/core/global_symbol_graph_builder.nim
    Then file should contain "proc buildGlobalSymbolGraph*"
    And file should contain "proc computeSourceMerkleRoot*"
    And file should not contain "import verification/"
    And file should not contain "import ../verification/"
    Given file src/verification/global_symbol_graph.nim
    Then file should contain "import ../core/global_symbol_graph_builder"
    And file should contain "export global_symbol_graph_builder"
    Given file src/core/proof_universe_lock.nim
    Then file should contain "proc computeProofUniverseLock*"
    And file should contain "proc verifyProofUniverseLock*"
    And file should not contain "import verification/"
    And file should not contain "import ../verification/"
    Given file src/verification/proof_universe_lock.nim
    Then file should contain "proc writeProofUniverseLock*"
    And file should contain "proc writeGlobalSymbolGraphSnapshot*"
    Given file src/verification/proof_universe_commit.nim
    Then file should contain "proc commitUniverseIntegrityAndLock*"
    Given file src/verification/proof_universe_lock.nim
    Then file should contain "import ./proof_universe_lock_io"
    And file should contain "import ./proof_universe_commit"
    Given file src/core/asset_collector.nim
    Then file should contain "proc collectFunctions*"
    And file should contain "proc normalizeModulePath*"
    And file should not contain "import verification/"
    And file should not contain "import ../verification/"
    Given file src/verification/cert_builder.nim
    Then file should contain "proc writeCertificates*"
    And file should contain "proc cleanOrphanCertificates*"
    Given file src/verification/lean_spec_generator.nim
    Then file should contain "proc writeLeanSpec*"
    And file should contain "proc writeMissingList*"
    Given file src/verification/rebuild_assets.nim
    Then file should contain "import core/asset_collector"
    And file should contain "import verification/cert_builder"
    And file should contain "import verification/lean_spec_generator"
    And file should not contain "proc collectFunctions"
    And file should not contain "proc writeCertificates"
    And file should not contain "proc writeLeanSpec"
    When nim check is run on src/core/global_symbol_graph_builder.nim
    And nim check is run on src/verification/global_symbol_graph.nim
    And nim check is run on src/core/proof_universe_lock.nim
    And nim check is run on src/verification/proof_universe_lock.nim
    And nim check is run on src/verification/proof_universe_commit.nim
    And nim check is run on src/verification/proof_universe_lock.nim
    And nim check is run on src/core/asset_collector.nim
    And nim check is run on src/verification/cert_builder.nim
    And nim check is run on src/verification/lean_spec_generator.nim
    And nim check is run on src/verification/rebuild_assets.nim
    Then all compilations should succeed

  Scenario: Wave 7 Phase 1 — Zombie debt entries purged from baseline
    When grep is run for "heal.nim" in src/gate/architecture_debt_baseline.toml
    Then grep output should be empty
    When grep is run for "analyzer.nim" in src/gate/architecture_debt_baseline.toml
    Then grep output should be empty

  Scenario: Wave 7 Phase 2 — Native syntax realignment in rebuild_assets
    Given file src/verification/rebuild_assets.nim
    Then file should contain "import std/sets"
    And file should not contain "import collections/sets"

  Scenario: Wave 7 Phase 3 — Orchestrator exemption in architecture_gate
    Given file src/gate/architecture_guard.nim
    Then file should contain "_commit.nim"
    And file should contain "_facade.nim"

  Scenario: Wave 7 Phase 4 — Dual-domain split of cert_builder
    Given file src/verification/cert_fingerprinter.nim
    Then file should exist
    And file should contain "proc fingerprintFunction*"
    Given file src/verification/cert_writer.nim
    Then file should exist
    And file should contain "proc writeCertificateWithFingerprint*"
    Given file src/verification/cert_builder.nim
    Then file should contain "import cert_fingerprinter"
    And file should contain "import cert_writer"
    And file should not contain "proc computeFingerprint"
    When nim check is run on src/verification/cert_fingerprinter.nim
    And nim check is run on src/verification/cert_writer.nim
    And nim check is run on src/verification/cert_builder.nim
    Then all compilations should succeed

  Scenario: Wave 7 Phase 5 — Debt baseline fully clean
    Given file src/gate/architecture_debt_baseline.toml
    Then file should not contain "certificates"
    And file should not contain "cert_builder.nim"
    And file should not contain "rebuild_assets.nim"
    And file should not contain "proof_universe_commit.nim"
