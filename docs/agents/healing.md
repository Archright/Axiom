# Axiom Healing Protocol

> Extracted from AGENTS.md §6. Refer back to AGENTS.md §4 for the condensed version.

## Core Protocol

The No Bypass Principle, Mathematical Proposition Derivation, Autonomous Retry with Refinement, and Hint Quality Gates are defined in this protocol and enforced by the verification-layer healing orchestrator (`src/verification/healing_orchestrator.nim`). The `axiom-healing` skill was migrated to gate infrastructure; see `docs/agents/plugin-migration.md`. (The former `auto_heal` gate runner — `src/gate/runners/auto_heal.nim` and its `tools/auto_heal.nim` engine — was removed 2026-08-08; see `docs/history/debt/auto-heal-removed-2026-08-08.md`.)

## Leanstral Prover Agent

The **leanstral model** (`mistral/labs-leanstral-2603`) is the designated agent for synthesizing mathematical propositions submitted to the Lean 4 kernel.

- **Invocation**: `opencode run --model mistral/labs-leanstral-2603 "<reasoning material and proposition submission request>"`
- **Pipeline**: leanstral receives source context + SMT unsat-core + diagnostic hints → synthesizes Lean 4 theorem → Lean kernel replay (`verifyGeneratedLeanSourceWithCompiler`) → Judge evaluation → Global consistency check → promotion to `verified` or retry.
- **Implementation Reference**: The leanstral gateway and prompt/evidence contract are implemented in `src/verification/leanstral_gateway.nim`, `src/verification/leanstral_prompt.nim`, and `src/verification/leanstral_repl.nim`. The `leanstral-prover` skill doc was removed; see `docs/agents/plugin-migration.md`.
