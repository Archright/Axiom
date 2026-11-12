# 2026-04 Changelog

## 7. ax report Consolidation (2026-04-29)

`ax report` was unified into a single TUI path via `renderTuiReport` to resolve SOLID/DRY/SSOT/SoC violations:
- **Single Renderer**: `renderTuiReport` (CRITICAL/WARNING/VERIFIED/UNATTEMPTED/UNKNOWN) is the only human-readable renderer.
- **Dual Source, Single Model**: Certificate vault (`buildProofReportFromCertificates`) and proof state (`parseAxProofReportFromJson`) both normalize to `AxProofReport` before rendering.
- **Zero Required Flags**: `ax report` no longer requires `--calculate-asi` or `--state-file`. It auto-detects proof state files and falls back to certificate vault.
- **Symlink Bug Fixed**: `paramStr(0)` replaces `getAppFilename()` so `~/.local/bin/ax` correctly routes through `planAxActions`.
- **SoC Restored**: `syncCertificatesWithProofState` and `archiveStaleProofState` extracted from rendering functions. `renderAxStateReportStdoutLines` removed; `renderAsiReportTui` removed.
- **Routing Simplified**: `cliCommandReport`, `cliDispatchAxReportAlias`, `cliRunAxStateReport` merged into one `cliCommandReport` path. `usesAxStateReportFlags/Path/Mode` eliminated.
- **Bug Fix (follow-up)**: TUI was rendered to both stdout and stderr because `logLines` and `outputJson` were both empty/non-empty in conflicting ways. Fixed by placing TUI content in `outputJson` and leaving `logLines` empty in TUI mode, ensuring single stdout output.

## 8. Audit Trail Unification & Z3 Persistence (2026-04-29)

Z3 solver responses were previously parsed in memory and discarded, leaving no reproducible audit trail. This gap violated the Evidence-over-Narrative constitutional principle.

- **Content-Addressed Storage**: `proveAxiomNode` now writes `logs/evidence/<nodeId>.z3out` on every successful solver invocation.
- **SHA1 Hash in Result**: `AxiomProofResult` carries `z3outHash` (SHA1 of solver stdout) for later correlation.
- **Orchestrator Correlation**: `ParallelTaskResult.evidenceLogJson` carries `{"z3outHash":"..."}` for verified nodes and `{"error":"..."}` for failures.
- **NodeId Propagation**: `AxiomProofRequest` now requires `nodeId` so that solver output can be correlated back to the originating function.
- **Orchestrator Propagation**: `OrchestrationNodeReport` now carries `evidenceLogJson`, threaded through `buildWorkerNodeReport` and `registerTerminalNodeStatus`. `jsonFromOrchestrationReport` serializes it into the proof state JSON, making Z3 evidence discoverable from the proof state file.
- **Audit Stream Unification**: `appendAuditEvent` accepts an `extra` JsonNode parameter. `saveProofState` extracts `evidenceLogJson` from each proof entry, parses it, and merges `z3outHash` into the `status_changed` audit event written to `logs/audit/stream.jsonl`. The audit stream is now the single SSOT for both status transitions and solver evidence.
- **Lean 4 Evidence Integrated**: `analyzer.nim` no longer writes to ad-hoc files. `context_injected_synthesis_success`, `semantic_equivalence_confirmed`, and `lean_validation_cache` events now flow through `appendGenericAuditEvent` into `stream.jsonl`. Cache hit/miss is explicitly auditable.
- **Certificate Fingerprint Audited**: `certificate_fingerprint_matched` and `certificate_fingerprint_mismatch` events are emitted by `analyzer.nim` (hydrateCertificate) and `main.nim` (writeRecertifiedCertificate) into `stream.jsonl`.
- **Dead Code Removed**: `src/core/audit_store.nim` (ad-hoc evidence store) removed. All audit flows through `state_manager.nim`.
- **Architecture Principle Gate**: New pre-commit gate `Axiom-architecture-principle-gate` blocks new violations:
  - `src/core/*.nim` writing directly to `logs/` (must use `state_manager`)
  - Direct `cert.status = ...` mutation outside `certificate_manager.nim` / `analyzer.nim`
  - New `logs/*.json(l)` stores from `src/core/` (must use `stream.jsonl` or content-addressed naming)
- **No New File Stores**: No additional JSON/JSONL files were created. Z3 output lives in `logs/evidence/*.z3out`; its hash lives in `logs/audit/stream.jsonl`.


Z3 solver responses were previously parsed in memory and discarded, leaving no reproducible audit trail. This gap violated the Evidence-over-Narrative constitutional principle.

- **Content-Addressed Storage**: `proveAxiomNode` now writes `logs/evidence/<nodeId>.z3out` on every successful solver invocation.
- **SHA1 Hash in Result**: `AxiomProofResult` carries `z3outHash` (SHA1 of solver stdout) for later correlation.
- **Orchestrator Correlation**: `ParallelTaskResult.evidenceLogJson` carries `{"z3outHash":"..."}` for verified nodes and `{"error":"..."}` for failures.
- **NodeId Propagation**: `AxiomProofRequest` now requires `nodeId` so that solver output can be correlated back to the originating function.
- **Orchestrator Propagation**: `OrchestrationNodeReport` now carries `evidenceLogJson`, threaded through `buildWorkerNodeReport` and `registerTerminalNodeStatus`. `jsonFromOrchestrationReport` serializes it into the proof state JSON, making Z3 evidence discoverable from the proof state file.
- **Audit Stream Unification**: `appendAuditEvent` accepts an `extra` JsonNode parameter. `saveProofState` extracts `evidenceLogJson` from each proof entry, parses it, and merges `z3outHash` into the `status_changed` audit event written to `logs/audit/stream.jsonl`. The audit stream is now the single SSOT for both status transitions and solver evidence.
- **Lean 4 Evidence Integrated**: `analyzer.nim` no longer writes to ad-hoc files. `context_injected_synthesis_success`, `semantic_equivalence_confirmed`, and `lean_validation_cache` events now flow through `appendGenericAuditEvent` into `stream.jsonl`. Cache hit/miss is explicitly auditable.
- **Certificate Fingerprint Audited**: `certificate_fingerprint_matched` and `certificate_fingerprint_mismatch` events are emitted by `analyzer.nim` (hydrateCertificate) and `main.nim` (writeRecertifiedCertificate) into `stream.jsonl`.
- **No New File Stores**: No additional JSON/JSONL files were created. Z3 output lives in `logs/evidence/*.z3out`; its hash lives in `logs/audit/stream.jsonl`.

## 9. Principle Violation Remediation (2026-04-30)

- **SSOT (Certificate Status)**: `analyzer.nim` and `gate_rules.nim` no longer mutate `cert.status` directly. All changes flow through `certificate_manager.markCertificateInvalid`.
- **SoC (Lean LSP)**: `lean_lsp.nim` removed direct `logs/lsp_audit.jsonl` writes. Key RPC events (`publishDiagnostics`, `initialize`, `shutdown`) now flow through `appendGenericAuditEvent` into `stream.jsonl`.
- **DRY (JSON Serialization)**: Extracted `renderJsonMultiline`, `jsonNodeStringArray`, `syncStringArrayField` from `main.nim` into new `src/core/json_utils.nim` shared module.
- **SRP (Partial)**: `main.nim` reduced from 7,211 to 3,562 lines by extracting JSON helpers, procedure gate logic, report CLI, ASI/purity logic, certificate commands, integrity/UAP commands, evidence view/trace commands, topology analysis/rendering helpers, topology verify command execution, and CLI dispatch types. `AxCommandCliResult`, `AxViewEvidence`, `AxTraceStep`, `VerifyWorkflowCliResult`, `VerifyTopologyCliResult`, `AuditProofBinaryCliResult`, `CliActionKind`, `CliCommandKind`, `AxSubcommandKind`, and `CliAction` extracted to `src/cli/cli_types.nim`. `verifyWorkflowLabelFromNode`, `verifyWorkflowLabelFromNodeId`, and shared sorter node helpers extracted to `src/core/sorter_core.nim`. Report CLI extracted to `src/cli/report_cli.nim`. ASI/purity analysis extracted to `src/cli/cst_cli.nim`. Certificate and proof-search commands extracted to `src/cli/certificate_cli.nim`. Integrity/UAP commands extracted to `src/cli/integrity_cli.nim`. Evidence view/trace commands extracted to `src/cli/evidence_cli.nim`. Topology source scanning, structural diagnosis, frontier ranking, `verify topology` CLI execution, and topology JSON/rendering helpers extracted to `src/cli/topology_cli.nim`. Topology structural diagnosis is statically bound as an exported `proc`, and topology metric/symbol lookup now flows through `SorterNodeId`-typed `Option` helpers instead of runtime-rebindable proc variables or raw string comparison at call sites. Shared CLI progress display constants live in `src/cli/progress_reporter.nim`. The procedure gate rejects staged topology diffs that reintroduce runtime-rebindable structural diagnosis variables, raw string node identity comparisons, or exposed `-1` lookup sentinels in topology CLI call sites.
- **SRP (Final CLI shell pass)**: `main.nim` reduced from 3,562 to 30 lines by extracting action planning, side-effect interpretation, basic command wrappers, proof JSON serialization, proof-binary audit commands, symbolic/k-induction commands, and ax workflow/proof-state orchestration. `main.nim` now only selects the executable name and delegates to `mainLoop` plus `interpretCliActions`, preserving public re-exports for gateway tests and `src/cli/main.nim`.
- **DRY/SoC/SRP/OCP (Architecture Audit Pass)**: A full architecture scan checked high-line-count modules, `src/core` layer inversions, certificate mutation ownership, and concrete solver/backend coupling. No new `src/core -> src/cli|src/ui` imports or direct `cert.status`/`cert.reason` writes outside `certificate_manager.nim` were found. The immediate duplicated-output hotspot was `action_interpreter_cli.nim`, where ax shortcut, check, observability, monitor, status, and submit-proof branches repeated error handling, stdout/stderr routing, and exit-code termination. That output policy now lives in `src/cli/action_output_cli.nim`. Canonical `CliCommandKind` execution now flows through `src/cli/action_command_registry.nim` using `registerCommand`; command owner modules register their own handlers, and `src/cli/action_dispatch_cli.nim` only assembles the default registry and invokes registered commands without owning enum branches or an enum-indexed handler table. The `ax heal` Ctrl-C/progress/ASI loop is isolated in `src/cli/ax_heal_action_cli.nim`, where ASI snapshots are read from `asi_cli` instead of reparsing report TUI output. `action_interpreter_cli.nim` is responsible for typed action sequencing only. The largest CLI orchestration hotspot, `ax_workflow_cli.nim`, was reduced from 2,206 to 1,752 lines by moving verify workflow payload parsing, orchestration report serialization, progress rendering, and workflow vault preload helpers into `src/cli/verify_workflow_cli.nim`.
- **SRP ( analyzer.nim )**: `analyzer.nim` reduced from 1,088 to 872 lines by extracting AST parsing to `src/verification/ast_extractor.nim` and fingerprint computation to `src/verification/fingerprint_engine.nim`.
- **New Modules**:
  - `src/core/json_utils.nim`: shared JSON serialization helpers
  - `src/core/file_utils.nim`: shared CLI utilities (normalizePath, import extraction, patch analysis)
  - `src/cli/procedure_gate.nim`: pre-commit procedure gate logic extracted from main.nim
  - `src/cli/cli_types.nim`: CLI result types extracted from main.nim
  - `src/cli/report_cli.nim`: report CLI entry point, certificate vault scanner, proof state sync, and rendering helpers extracted from main.nim
  - `src/cli/cst_cli.nim`: ASI calculation and purity audit report generation extracted from main.nim
  - `src/cli/certificate_cli.nim`: certificate and proof-search CLI commands extracted from main.nim
  - `src/cli/integrity_cli.nim`: integrity loop and universal acceptance pipeline CLI commands extracted from main.nim
  - `src/cli/evidence_cli.nim`: ax view and ax trace CLI commands, evidence/trace parsing and rendering extracted from main.nim
  - `src/cli/topology_cli.nim`: topology analysis helpers, structural diagnosis, vertex rendering, and verify topology command execution extracted from main.nim
  - `src/cli/action_plan_cli.nim`: CLI command parsing, ax alias planning, usage lines, and pure `CliAction` generation extracted from main.nim
  - `src/cli/action_interpreter_cli.nim`: side-effecting typed action sequencer and executable output encoding extracted from main.nim
  - `src/cli/action_command_registry.nim`: OCP command registry API (`registerCommand`, `runRegisteredCommand`) for `CliCommandKind` execution
  - `src/cli/action_dispatch_cli.nim`: default command registry assembly and registered command invocation extracted from action_interpreter_cli.nim
  - `src/cli/action_output_cli.nim`: stdout/stderr routing, command result emission, and exit-code handling extracted from action_interpreter_cli.nim
  - `src/cli/ax_heal_action_cli.nim`: `ax heal` Ctrl-C handling, progress display integration, ASI loop checks, and continuation prompting extracted from action_interpreter_cli.nim
  - `src/cli/basic_commands_cli.nim`: capture/generate/export/import/validate/init/report/thought-dashboard thin command wrappers extracted from main.nim
  - `src/cli/ax_workflow_cli.nim`: ax scan/prove workflow, proof-state construction/merge, semantic payload workflow, and verify workflow execution extracted from main.nim
  - `src/cli/verify_workflow_cli.nim`: verify workflow payload parsing, orchestration report serialization, progress/log rendering, and workflow vault preload helpers extracted from ax_workflow_cli.nim
  - `src/cli/proof_json_cli.nim`: ProofArtifact, symbolic, semantic payload, and Nim-Lean bridge JSON serializers extracted from main.nim
  - `src/cli/symbolic_cli.nim`: symbolic transition, runtime-zero, k-induction, Nim-Lean bridge, and symbolic proof command execution extracted from main.nim
  - `src/cli/git_cli.nim`: proof binary audit CLI execution and EmbeddedProofAudit JSON rendering extracted from main.nim
  - `src/verification/ast_extractor.nim`: AST extraction, function body parsing, call/resource inference extracted from analyzer.nim
  - `src/verification/fingerprint_engine.nim`: fingerprint computation, structural canonicalization extracted from analyzer.nim

## 9.1 Architecture Remediation Follow-up (2026-05-01)

- **SSOT (Graph Status Ownership)**: `src/core/semantic_graph.nim` now exports the only semantic node status mutation helpers used for dependency invalidation. `src/core/ecosystem_linkage.nim` no longer writes `graph.nodes[..].status` directly.
- **SSOT (SolverStatus)**: `src/core/domain_types.nim` now owns the only `SolverStatus` enum, using the solver-facing labels `solverSat`, `solverUnsat`, `solverUnknown`, and `solverVacuousContradiction`. `src/core/solver/types.nim` imports and re-exports that canonical type instead of defining a second enum, while `provider_interface.nim` and solver parsers use the shared labels.
- **DRY (JSON Scanner / MCP Params)**: duplicated raw JSON traversal logic moved to `src/core/json_safe.nim`; duplicated MCP request parameter helpers moved to `src/mcp/mcp_params.nim`. `axiom_api.nim`, `trusted_base.nim`, `axiom_mcp.nim`, and `tools.nim` now consume those shared modules.
- **Determinism (Graph Hash / Certificate Rebuild)**: `src/core/global_symbol_graph.nim` now sorts edge payloads before hashing so `graphHash` is stable across runs. `src/verification/rebuild_assets.nim` now generates collision-free, path-safe certificate filenames from full `modulePath` and removes legacy certificate filenames during regeneration, restoring `verify-certificates` to a clean green state.

## 9.2 Verification Output Policy Follow-up (2026-05-01)

- **Semantic warning scope alignment**: `verifyCertificates` in `src/verification/analyzer.nim` now evaluates `applySemanticIntegrityGate` only when `enableSymbolic=true`. Non-symbolic certificate verification no longer emits mass `missing-semantic-validation` warnings for functions that were never subjected to semantic replay in that run.

### /leanprover/lean4
- Lean 4 theorem statement must evaluate to `Prop`; function types (`String -> String`) trigger "type mismatch, is not a proposition" -- classified as `dekTypeMismatch`
- `import Std` only; unknown constants outside `Std` namespace trigger `dekUnknownConstant`
- Tactic block incompleteness triggers `dekUnsolvedGoals`; redundant tactics after proof completion trigger `dekNoGoals`

## 10. Dead Code Removal and Type Unification (2026-04-30)

- **Dead Code Removal (main.nim)**: Removed 8 unused functions/procs: `isCommentOrStyleLine`, `axProofEntryIsAttempted`, `axProofDisplayId`, `writeStructuralBaseline`, `certificateRefreshKey`, `startsWithDeclarationKeyword`, `isImplementationFile`, `isFeatureEvidence`, `renderAxFrontierLines`, `assignAxProofDisplayIds`, `zeroAbovePhrase`, `lowerBoundPhrase`. `main.nim` reduced from 7,211 to 6,259 lines.
- **Dead Code Removal (analyzer.nim)**: Removed 7 unused functions: `statusLabel`, `statusHtmlClass`, `statusIcon`, `toTimelineAscii`, `coveragePercent`, `functionDeclName`, `isFunctionHeader`. `analyzer.nim` reduced from 1,088 to 653 lines.
- **Type Unification**: Removed duplicate type definitions (`CertificateStatus`, `FunctionCertificate`, `VerificationReportSummary`, `ArchitecturePrinciplesGate`, `AuditTrailGate`, `GlobalInfluenceGate`, `TypeIntegrityGate`, `SymbolicInvariantGate`, `SemanticIntegrityGate`) from `reporter.nim`. All modules now import exclusively from `core/domain_types.nim`.
- **Dependency Analyzer Extraction**: Extracted `buildReverseDependencies`, `detectCyclicFunctions`, `invalidateDependents`, `canonicalizeCallsAcrossModules` from `analyzer.nim` to `src/verification/dependency_analyzer.nim`. `invalidateDependents` now requires a non-nil `markPending` closure, eliminating the direct `cert.status` mutation fallback path.

## 11. Import and Dead Code Cleanup (2026-04-30)

- **Unused import removal**: Removed 23 unused imports across 15 files (sync_utils, cli_utils, domain_types, cfg_builder, abstract_provider, reporter, leanstral_gateway, leanstral_prompt, proof_summarizer, static_rules, integrity_guard, submit, submit_proof, status_graph, observability).
- **Unused function removal**: Removed 22 unused functions across 14 files (bmc_race, gateway, expression_parser, axiom_api, sorter_core, integrity_refinement_loop, spec_generator, lean_lsp, symbolic_engine, abstract_provider, gate_rules, observability, the_judge, heal, procedure_gate).
- **Duplicate import elimination**: Removed 12 duplicate imports from analyzer.nim and translation_validator.nim caused by reporter.nim's include chain.
- **Cascade cleanup**: Removing collectDependencyAxioms and hasVaultIntegrityBlock overloads in sorter_core.nim cascaded to remove lookupVaultAxiom and allDependenciesInVault unused overloads.
- **Grouped import expansion**: Expanded abstract_provider.nim grouped import to individual lines to avoid procedure gate parser limitation with std/[...] syntax.

## 12. Dependency Cleanup and sha1 Migration (2026-04-30)

- **sha1 deprecation fix**: Replaced deprecated `std/sha1` with `checksums/sha1` in `src/core/gateway.nim`. Installed `checksums` package via nimble. Updated `src/allowed_imports.lock` with `/nim-lang/checksums checksums/sha1` entry.
- **Cascade dead code removal**: Removing `parseLeanCompilerDiagnosticLine` from `lean_lsp.nim` cascaded to remove `parseLeanCompilerDiagnostics`. Removing `parseAliasLine` body from `spec_generator.nim` cascaded to remove `splitNameAndGenericParams` and `stripTopLevelAssignment`.
- **threadpool deprecation**: `std/threadpool` remains in `orchestrator.nim` and `heal.nim`. Migration to `malebolgia` or `taskpools` requires `FlowVar` API replacement and is deferred to a dedicated parallelization refactoring commit.

## 13. Shadow and Unreachable Code Fixes (2026-04-30)

- **submit.nim**: Renamed shadowed `result` variable to `theoremSrc` in `sanitizeTheoremSource` to eliminate `ResultShadowed` warning.
- **submit_proof.nim**: Removed unreachable `return ok(res)` after `try/except/finally` block where all paths already return.

## 14. main.nim Partial Decomposition and Progress Extraction (2026-04-30)

- **Progress reporter extraction**: Moved topology/proof progress calculation constants and functions (axProgressScale, axTopologyReservedStepWeight, axProofPreparationWeight, axProofExecutionWeight, axProofFinalizationWeight, clampProgressInt, scaleProgressUnits, topologyScanProgress, topologyPhaseProgress, topologyReservedProgress, proofExecutionProgress, proofFinalizationProgress, etc.) from `main.nim` to new `src/cli/progress_reporter.nim`. Reduces `main.nim` by ~100 lines.
- **Shortcut renderer extraction**: Moved `usesAxShortcutJsonFlag`, `renderAxShortcutStdoutLines`, `renderAxShortcutStderrLines` from `main.nim` to `src/cli/report_cli.nim`.
- **`main.nim` line count**: 6,193 -> 6,069 lines.
- **threadpool deprecation**: `std/threadpool` remains in `orchestrator.nim` and `heal.nim`. Evaluated `malebolgia`, `taskpools`, and `weave` as replacements. All three require `FlowVar` API redesign and `supportsCopyMem` constraints that are incompatible with `ParallelTaskResult` and `HealNodeOutput` (which contain `string` fields). Migration requires either: (a) pointer indirection wrapper with manual memory management, or (b) redesign of parallel result types to exclude GC-managed types. Deferred to dedicated parallelization refactoring commit.

## 16. main.nim Decomposition: Certificate CLI Extraction

**Date**: 2026-04-28
**Commit**: (pending)
**Status**: Completed -- prek gates passed, ASI 1.0000

### Changes

- **`src/cli/certificate_cli.nim` created**: Extracted ~812 lines from `main.nim` containing:
  - Refinement helpers (`buildRefinementFeedback`, `applyRefinementSuggestionsToSource`, `applyRefinementSuggestionsToCore`, `executeRefinementRetryLoop`, `DynamicProofSearchRunner`)
  - `cmdDynamicProofSearch`
  - Certificate helpers (`loadJsonObjectOrEmpty`, `writeRecertifiedCertificate`, `findCertByTheorem`, `findCertForRefresh`, `loadCertificateTactics`, `canAutoRepairCertificateFingerprint`, `refreshCertificateFingerprint`, `hydrateCertificateMetadata`)
  - `cmdRecertifyCertificates`
  - File scaffold helpers (`ensureFileWithContent`, `ensureFileContainsLines`, `updateGitignoreForArchright`, `updateReadmeForArchright`, `applyInitScaffold`)
  - `cmdVerifyCertificates`
- **`src/cli/cli_io.nim` created**: Extracted shared CLI I/O utilities (`die`, `readAllStdin`, `parseRequiredIntArg`, `parseRequiredIntArgOrDie`) from `main.nim`.
- **`tests/gateway_test.nim` updated**: References to moved symbols updated to use `certificate_cli` module (`applyRefinementSuggestionsToSource`, `executeRefinementRetryLoop`, `DynamicProofSearchRunner`, `applyInitScaffold`).

### Results

- `main.nim`: 6,069 -> 5,260 lines (-809)
- `nim check`: clean (2 existing threadpool deprecation warnings only)
- `nim c`: success
- `gateway_test.nim`: compiles successfully
- ASI: 1.0000 (PASSED)

## 17. main.nim Decomposition: Integrity CLI Extraction

**Date**: 2026-04-28
**Commit**: (pending)
**Status**: Completed -- prek gates passed, ASI 1.0000

### Changes

- **`src/cli/integrity_cli.nim` created**: Extracted ~565 lines from `main.nim` containing:
  - `verificationEngineLabel`
  - `jsonFromUniversalPipelineResult`
  - `jsonFromTrackedInvariant`
  - `jsonFromOpcodeBlock`
  - `jsonFromIntegrityLoopResult`
  - `runUniversalAcceptancePipelineCliJson`
  - `runIntegrityLoopCliJson`
  - `cmdUniversalAcceptancePipeline`
  - `cmdIntegrityLoop`
- **`src/cli/cli_io.nim` updated**: Added `parseRequiredIntCliArg` to shared CLI I/O utilities.

### Results

- `main.nim`: 5,260 -> 4,680 lines (-580)
- `nim check`: clean (2 existing threadpool deprecation warnings only)
- `nim c`: success
- ASI: 1.0000 (PASSED)