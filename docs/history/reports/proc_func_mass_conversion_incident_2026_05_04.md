# Incident Report: proc→func Mass Conversion False Positives

**Date:** 2026-05-04
**Severity:** High ( broke `nim check` gate for multiple core modules )
**Status:** Resolved

## Summary

During a batch technical-debt remediation session, an agent executed a mass `proc → func` conversion across `src/core/` without per-function side-effect verification. This caused `nim check` failures in 20+ modules where functions perform physical IO (file system, network, time acquisition, mutable global state, or process execution).

## Root Cause

`func` in Nim implicitly carries `{.noSideEffect.}`. The compiler rejects any `func` that calls file-IO primitives (`readFile`, `writeFile`, `fileExists`, `dirExists`, `walkDir`), network operations, time acquisition (`now`, `utc`, `getTime`), or mutable global state mutation.

The mass-conversion script treated `proc` and `func` as interchangeable keywords, ignoring the semantic contract difference.

## Affected Modules

The following `src/core/` modules were incorrectly targeted and had to be reverted to `proc` (or had `{.push noSideEffect.}` removed):

| Module | Side-Effect Category |
|--------|---------------------|
| `json_utils` | File IO, JSON parsing |
| `cli_utils` | Terminal IO, encoding |
| `state_manager` | Atomic file writes, JSON state persistence |
| `solver_bridge` | External process execution |
| `vault_manager` | File-based vault IO |
| `semantic_graph` | Mutable graph mutation, IO |
| `vault_factory` | File system operations |
| `tree_sitter_bridge` | FFI / external library calls |
| `global_symbol_graph` | Mutable global state |
| `orchestrator` | Event emission, mutable state |
| `orchestrator_topology` | Progress event sinking |
| `orchestrator_types` | Mutable state containers |
| `orchestrator_vault` | Vault IO |
| `spec_generator` | File generation |
| `lean_diagnostic` | External process communication |
| `smart_search` | Mutable search index |
| `axiom_api` | Network / external API calls |
| `z3_pool` | External solver process management |
| `pipeline_verdict_engine` | Mutable pipeline state |
| `ecosystem_linkage` | Manifest scanning, chain-of-trust certificate building (`fileExists`, `readFile`, `walkDir`, `now`, `utc`) |

## Resolution

1. **Immediate:** Reverted physically impure functions back to `proc`.
2. **Module-level:** Removed `{.push noSideEffect.}` from 20 modules that perform IO.
3. **Policy:** Added `Mandatory (Mass Conversion Audit)` clause to `GUARDIAN.md §11`.

## Prevention (Physical Enforcement)

Three physical guardrails were implemented to prevent recurrence:

### 1. SSOT Deny-List (`src/core/.physically_impure_modules`)

A machine-readable deny-list at `src/core/.physically_impure_modules` enumerates all core modules that perform physical side effects. This file is the single source of truth for both the injection scanner and the compliance auditor.

### 2. Pragma Injector Respects Deny-List (`scripts/gates/inject_core_pragmas.nim`)

The pragma injector now loads the deny-list before walking `src/core/`. For any module on the list:
- `{.push raises: [].}` is still injected (all modules must be exception-safe).
- `{.push noSideEffect.}` is **skipped**.

This prevents the root cause: a future agent can never accidentally inject `noSideEffect` into an impure module, even if the agent has no knowledge of Nim semantics.

### 3. Compliance Scanner Respects Deny-List (`scripts/gates/guardian_compliance_scanner.nim`)

The compliance scanner now loads the same deny-list. Modules on the list are considered compliant even if they lack `{.push noSideEffect.}`, eliminating the false-negative reports that previously encouraged agents to "fix" them by adding the pragma.

## Agent Takeaway

> `func` is not a cosmetic upgrade over `proc`. It is a **compiler-enforced purity contract**. Mass conversion without side-effect audit is equivalent to lying to the type system. The compiler will catch the lie, but only after the damage is staged.
