# Dead Code Part-File Deletion Registry

> Append-only registry of permanently deleted dead-code part files.
> Purpose: Prevent accidental restoration by future session agents.
> Authority: AGENTS.md §0.2 (First-Principles Elegance), §1.5 (Canonical DRY), §2.1 #3a (Annals Write-Back).

---

## Batch 1 — 2026-06-03: Unused Part-File Duplicates (29 files)

**Commit**: `delete(src/cli): remove 29 dead-code part-file duplicates`
**Authority**: AGENTS.md §1.5 (Canonical DRY), §0.2 (First-Principles Elegance)
**Reason**: These part files were created during an incomplete module-splitting refactoring. They define exact AST duplicates of functions that already exist in their respective main modules (`wf_state.nim`, `topology_cli.nim`, `observability.nim`, `recertify_lean.nim`, `asi_cli.nim`, `verify_workflow_cli.nim`). Zero imports or includes reference these files anywhere in the project (verified by `grep -rn` across `src/`, `tests/`, `experimental/`, and build configs). Per Context7 Nim documentation (tut1.md), `include` is for splitting large modules, but these files were never integrated into any `include` chain reaching a live module.

### Deletion Impact
- **DRY violations resolved**: 20+ exact AST fingerprint duplicates eliminated from `src/gate/nimtry/nimtry_cli.nim --full-tree` output.
- **Compile effect**: No change — files were already dead code with zero compilation impact.
- **Restoration risk**: LOW — functions are already defined in live main modules.

### Deleted Files

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `src/cli/wf_state_parts/wf_state_part1.nim` | Exact duplicate of `wf_state.nim::resetForceHealQuarantine` | LOW — live definition in `wf_state.nim` |
| `src/cli/wf_state_parts/wf_state_part2.nim` | Dead include parent (included `part2_part1` and `part2_part2`, but never imported) | LOW — no live references |
| `src/cli/wf_state_parts/wf_state_part2_parts/wf_state_part2_part1.nim` | Exact duplicates of `wf_state.nim::sortAxProofEntries`, `jsonFromAxProofEntries`, `trimProofStatePathPrefix`, `axStateEntryEngine` | LOW — live definitions in `wf_state.nim` |
| `src/cli/wf_state_parts/wf_state_part2_parts/wf_state_part2_part2.nim` | Exact duplicates of `wf_state.nim::mergeTransitionLogIntoProofState`, `autoDetectAndDemoteStale`, `syncVaultToProofState` | LOW — live definitions in `wf_state.nim` |
| `src/cli/wf_state_parts/wf_state_part3.nim` | Exact duplicate of `wf_state.nim::mergeTransitionLogIntoProofState` | LOW — live definition in `wf_state.nim` |
| `src/cli/wf_state_parts/wf_state_part4.nim` | Exact duplicate of `wf_state.nim::syncVaultToProofState` | LOW — live definition in `wf_state.nim` |
| `src/cli/commands/observability_parts/observability_part1.nim` | Exact duplicate of `observability.nim::defaultAxObservabilityStatePath` | LOW — live definition in `observability.nim` |
| `src/cli/commands/observability_parts/observability_part2.nim` | Exact duplicate of `observability.nim::loadObservabilityState` | LOW — live definition in `observability.nim` |
| `src/cli/commands/observability_parts/observability_part3.nim` | Exact duplicate of `observability.nim::runAxTraceCli` | LOW — live definition in `observability.nim` |
| `src/cli/commands/observability_parts/observability_part4.nim` | Exact duplicate of `observability.nim::runAxTraceCli` | LOW — live definition in `observability.nim` |
| `src/cli/commands/observability_parts/observability_part5.nim` | Exact duplicate of `observability.nim::runAxTraceCli` | LOW — live definition in `observability.nim` |
| `src/cli/topology_cli_parts/topology_cli_part1.nim` | Exact duplicate of `topology_cli.nim::computeTopologyNodeDepths` | LOW — live definition in `topology_cli.nim` |
| `src/cli/topology_cli_parts/topology_cli_part2.nim` | Exact duplicates of `topology_cli.nim::collectTopologySourceFiles`, `normalizeTopologyModulePath`, `loadSourceSlice`, `buildStructuralDiagnoses`, `analyzeTopologySourceRoot`, `runVerifyTopologyCli`, `cmdVerifyTopology` | LOW — live definitions in `topology_cli.nim` |
| `src/cli/topology_cli_parts/topology_cli_part4.nim` | Exact duplicate of `topology_cli.nim::buildStructuralDiagnoses` | LOW — live definition in `topology_cli.nim` |
| `src/cli/topology_cli_parts/topology_cli_part5.nim` | Exact duplicate of `topology_cli.nim::buildStructuralDiagnoses` | LOW — live definition in `topology_cli.nim` |
| `src/cli/commands/recertify_lean_parts/recertify_lean_part1.nim` | Exact duplicates of `recertify_lean.nim::bundleCachePath`, `loadBundleCache`, `saveBundleCache`, `computeStringHash`, `buildBundleContent`, `defaultRecertifyLeanConfig`, `updateCertificateLeanHash`, `loadVaultTable`, `runLeanCompiler`, `processEvidenceFile` | LOW — live definitions in `recertify_lean.nim` |
| `src/cli/commands/recertify_lean_parts/recertify_lean_part2.nim` | Exact duplicate of `recertify_lean.nim::autoRecertifyLeanIfNeeded` | LOW — live definition in `recertify_lean.nim` |
| `src/cli/commands/recertify_lean_parts/recertify_lean_part3.nim` | Exact duplicate of `recertify_lean.nim::autoRecertifyLeanIfNeeded` | LOW — live definition in `recertify_lean.nim` |
| `src/cli/commands/recertify_lean_parts/recertify_lean_part4.nim` | Exact duplicate of `recertify_lean.nim::autoRecertifyLeanIfNeeded` | LOW — live definition in `recertify_lean.nim` |
| `src/cli/asi_cli_parts/asi_cli_part1.nim` | Exact duplicate of `asi_cli.nim::purityFileReportFromContent` | LOW — live definition in `asi_cli.nim` |
| `src/cli/asi_cli_parts/asi_cli_part2.nim` | Exact duplicate of `asi_cli.nim::getEngineAsiFixed4` | LOW — live definition in `asi_cli.nim` |
| `src/cli/asi_cli_parts/asi_cli_part3.nim` | Exact duplicate of `asi_cli.nim::getEngineAsiFixed4` | LOW — live definition in `asi_cli.nim` |
| `src/cli/asi_cli_parts/asi_cli_part4.nim` | Exact duplicate of `asi_cli.nim::getEngineAsiFixed4` | LOW — live definition in `asi_cli.nim` |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part1.nim` | Dead include parent (included `part1_part1` and `part1_part2`, but never imported) | LOW — no live references |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part1_parts/verify_workflow_cli_part1_part1.nim` | Exact duplicate of `verify_workflow_cli.nim::jsonFromOrchestrationReport` | LOW — live definition in `verify_workflow_cli.nim` |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part1_parts/verify_workflow_cli_part1_part2.nim` | Exact duplicates of `verify_workflow_cli.nim::renderVerifyWorkflowDiagnosticLines`, `renderVerifyWorkflowSummaryLines` | LOW — live definitions in `verify_workflow_cli.nim` |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part2.nim` | Exact duplicate of `verify_workflow_cli.nim::runVerifyWorkflow` | LOW — live definition in `verify_workflow_cli.nim` |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part3.nim` | Exact duplicate of `verify_workflow_cli.nim::runVerifyWorkflow` | LOW — live definition in `verify_workflow_cli.nim` |
| `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part4.nim` | Exact duplicate of `verify_workflow_cli.nim::runVerifyWorkflow` | LOW — live definition in `verify_workflow_cli.nim` |

### Empty Directories Removed
- `src/cli/wf_state_parts/wf_state_part2_parts/`
- `src/cli/wf_state_parts/`
- `src/cli/commands/observability_parts/`
- `src/cli/commands/recertify_lean_parts/`
- `src/cli/asi_cli_parts/`
- `src/cli/verify_workflow_cli_parts/verify_workflow_cli_part1_parts/`
- `src/cli/verify_workflow_cli_parts/`

### Remaining Part Files (Not Duplicates, Not Deleted)
| File | Status |
|------|--------|
| `src/cli/topology_cli_parts/topology_cli_part3.nim` | Dead code but no DRY duplicate; functions (`buildAxFrontierEntries`, `buildAxProofSubsetState`, `buildTopologyImpactIndexTable`) do not exist in live modules. Left in place pending architectural review. |
