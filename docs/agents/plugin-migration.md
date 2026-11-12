# Plugin Migration Guide

## Overview

Five Axiom skills have been migrated to Kimi CLI plugins for deterministic tool invocation. In addition, `subagent-mandate` has been superseded by the `delegation-enforcer` agent-runtime plugin. The source SKILL.md files for these migrated skills have been removed; the infrastructure listed below is now the SSOT.

## Deleted Source Skills

| Skill | Replaced By | Deletion Date |
|-------|-------------|---------------|
| `git-branch-rebase-sync` | `git-sync` plugin + `bin/sync-branch` | 2026-06-17 |
| `axiom-quality-gate` | `axiom-quality-gate` plugin + `bin/run-quality-audit` | 2026-06-17 |
| `prek-quality-gate` | `prek-quality-gate` plugin + `bin/run-gate` | 2026-06-17 |
| `git-atomic-commit` | `git-atomic-commit` plugin + `bin/git-commit-atomic` | 2026-06-17 |
| `subagent-mandate` | `delegation-enforcer` agent-runtime plugin | 2026-06-17 |

> Historical context only: reference material formerly under `.agents/skills/<name>/references/` (for `axiom-quality-gate`, `subagent-mandate`, and `subagent-driven-development`) is retained for historical context. The `.agents/` directory was removed (commit 4847be498) and is **not shipped** — the infrastructure in the tables above is the SSOT. Reintroduction is a feature decision: opencode recognizes `.agents/skills/<name>/SKILL.md` as a valid skill location, so real files would be consumed, but dummy/template files remain prohibited.

## Infrastructure-Migrated Skills (Non-Plugin)

| Skill | Replaced By | Category | Deletion Date |
|-------|-------------|----------|---------------|
| `architecture-principles` | `src/gate/configs/architecture_rules.json` + `bin/architecture-config-gate` | Config-as-Code | 2026-06-17 |
| `documentation-first` | `src/gate/configs/documentation_first.json` + `bin/documentation_first_gate` | Config-as-Code | 2026-06-17 |
| `axiom-healing` | `bin/healing-orchestrator` | Orchestrator | 2026-06-17 |
| `precision-inference` | `bin/healing-orchestrator` (entropy/binding/counter-ex gates) | Orchestrator | 2026-06-17 |
| `leanstral-prover` | `bin/leanstral-prover` | Orchestrator | 2026-06-17 |
| `subagent-driven-development` | `bin/subagent-orchestrator` (plan template formerly `.agents/templates/subagent_plan_template.md`, removed with `.agents/`) | Orchestrator | 2026-06-17 |
| `integrity-workflow` | `bin/integrity-workflow` | MCP Interface / Workflow | 2026-06-17 |
> These new gates are **not yet registered in `src/gate/manifest.d/`** because they report many pre-existing violations. They can be run manually and will be enabled in pre-commit after the codebase is cleaned up.

## Common Safety Infrastructure

| Tool | Purpose |
|------|---------|
| `bin/debug-mode` | Break-glass switch — puts all gates into warning mode (exit 0) for infrastructure repairs |
| `bin/gate_admin` | Gate lifecycle CLI: list, status, enable, disable |
| `src/gate/policy_schema.json` | Shared policy SSOT for all gates |
| `~/.axiom/gate_history.jsonl` | Failure dataset for continuous optimization |

## Migrated Plugins

| Plugin | Skill Source | Tool | Description |
|--------|-------------|------|-------------|
| git-sync | git-branch-rebase-sync | `sync_branch` | Two-Phase Rebase-Forward Sync |
| axiom-quality-gate | axiom-quality-gate | `run_quality_audit` | 4-dimension quality audit (stdout) |
| prek-quality-gate | prek-quality-gate | `run_gate` | nim check + nimtry on files |
| git-atomic-commit | git-atomic-commit | `atomic_commit` | Atomic commit with Conventional Commits |
| delegation-enforcer | subagent-mandate | `enforce_delegation` | Scans wire logs for agent Bash loops; blocks subagent delegation violations |

## Plugin Structure

The Kimi CLI plugin convention is a plugin directory `<name>/` containing a `plugin.json` spec. Historically this structure lived under `.agents/plugins/<name>/`; the `.agents/` directory was removed (commit 4847be498) and is **not shipped** — plugins are installed from the global cache `~/.kimi/plugins/` (see `docs/agents/rules_workflow.md` §2.8). The structure below is the historical convention, not a currently shipped path:

```
.agents/plugins/<name>/
  plugin.json   # Kimi CLI plugin spec (historical — not currently present)
```

Wrapper scripts live in `bin/`:
- `bin/sync-branch`
- `bin/run-quality-audit`
- `bin/run-gate`
- `bin/git-commit-atomic`
- `bin/delegation-enforcer-plugin`

## Installation

> **Note:** These install commands are historical — they target `.agents/plugins/`, which was removed (commit 4847be498) and is **not shipped**. Plugins are resolved from the global cache `~/.kimi/plugins/` per `docs/agents/rules_workflow.md` §2.8.

```bash
kimi plugin install .agents/plugins/git-sync
kimi plugin install .agents/plugins/axiom-quality-gate
kimi plugin install .agents/plugins/prek-quality-gate
kimi plugin install .agents/plugins/git-atomic-commit
kimi plugin install .agents/plugins/delegation-enforcer
```

## Fallback

If Kimi CLI plugin system is unavailable, invoke the wrapper scripts in `bin/` directly. The original SKILL.md files have been removed; the wrapper scripts and this document are the SSOT.

## Technical Debt

- `prek-quality-gate`: `nimtry` binary not compiled; script falls back to `nim c -r`
- `axiom-quality-gate`: `four_dimension_audit.sh` writes to file; wrapper reads it back to stdout
- `gate_replay.nim` JSON output: not yet implemented
