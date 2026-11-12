# CLI Amputation + Config-Engine Separation (2026-06-04)

## Summary

Purge all non-essential `ax` commands and separate CLI flag parsing from engine execution logic via the `ExecutionPolicy` domain object.

## Deleted Commands

| Command | Rationale | Restoration Risk |
|---------|-----------|------------------|
| `ax gate` | CI infrastructure belongs in pre-commit hook scripts, not product binary | Low — `bin/gate_hook` already wraps gate binaries |
| `ax check` | Diagnostic subset superseded by `ax prove` | Low — topology scan covers same surface |
| `ax monitor` | Observability plumbing, not core UX | Low — metrics exported via `core/metrics.nim` directly |
| `ax submit` | External registry integration, not core proof flow | Low — standalone script viable |
| `ax dashboard` | TUI/reporting merged into `ax report` | Low — `report_cli.nim` covers summaries |
| `ax mcp` | MCP is an extension point, not a CLI command | Low — separate stdio handler planned |
| `ax uap` | Internal pipeline orchestrator, not user-facing | Low — invoked by `ax prove` internally |
| `ax integrity-loop` | Workflow automation, not core proof | Low — scriptable externally |
| `ax verify` | Broken registry bug, superseded by `ax prove` | Low — `prove` covers verification queue |
| `ax heal` | Merged into `ax prove --heal` | Low — same code path via policy |
| `ax init` | Onboarding belongs in documentation | Low — README quick-start replaces it |

## Deleted Files

### CLI Modules (27 files)
- `src/cli/action_command_registry.nim`
- `src/cli/action_dispatch_cli.nim`
- `src/cli/git_cli.nim`
- `src/cli/basic_commands_cli.nim`
- `src/cli/certificate_cli.nim`
- `src/cli/commands/check.nim`
- `src/cli/commands/gate.nim`
- `src/cli/commands/heal.nim`
- `src/cli/commands/heal_analysis.nim`
- `src/cli/commands/heal_injection.nim`
- `src/cli/commands/heal_leanstral.nim`
- `src/cli/commands/heal_node_executor.nim`
- `src/cli/commands/heal_parsing.nim`
- `src/cli/commands/monitor.nim`
- `src/cli/commands/observability.nim`
- `src/cli/commands/recertify_lean.nim`
- `src/cli/commands/status_graph.nim`
- `src/cli/commands/submit.nim`
- `src/cli/commands/submit_proof.nim`
- `src/cli/commands/vault_sync.nim`
- `src/cli/evidence_cli.nim`
- `src/cli/integrity_cli.nim`
- `src/cli/mcp_command_cli.nim`
- `src/cli/procedure_gate.nim`
- `src/cli/symbolic_cli.nim`
- `src/cli/verify_workflow_cli.nim`

### Tests & Features (13 files)
- `tests/features/ax_axiom_help_separation.feature`
- `tests/features/ax_heal_removal.feature`
- `tests/features/freeze_graph_cache.feature`
- `tests/features/orchestrator.feature`
- `tests/features/prove_heal_unification.feature`
- `tests/features/remove_ax_heal_and_legacy.feature`
- `tests/features/topology_cache.feature`
- `tests/gateway/parallel_first_test.nim`
- `tests/unit/ax_workflow_cli_test.nim`
- `tests/unit/heal_batch_scheduler_test.nim`
- `tests/unit/heal_parsing_test.nim`
- `tests/unit/heal_scheduler_test.nim`
- `tests/unit/proof_preservation_test.nim`
- `tests/unit/vault_sync_test.nim`
- `tests/unit/verify_workflow_cli_test.nim`

## New Files

- `src/core/execution_policy.nim` — Domain-layer policy SSOT
- `src/verification/report_engine.nim` — Decoupled report business logic

## Architecture Changes

- `ExecutionVariant` enum (Presentation layer) replaced by `ExecutionPolicy` object (Domain layer)
- `ProofTask.mode` → `ProofTask.policy`
- `buildPolicy()` enforces zero-fallback validation (mutually exclusive flags, non-negative limits)
- `report_cli.nim` reduced to thin wrapper; logic moved to `verification/report_engine.nim`

## SSOT Authority

- AGENTS.md §1.6 "`ax` is the SOLE CLI entry point"
- AGENTS.md §1.2 Layered Gate Architecture (Domain / Infrastructure / Presentation separation)
- AGENTS.md §2.2 #3a Annals Write-Back (this file)
