# Unified Pipeline Architecture — Dead Code Removal Registry

**Date:** 2026-06-03
**Author:** Axiom Agent (Unified Pipeline Refactor)
**SSOT Authority:** docs/history/reports/ax_prove_notion_compliance_audit_2026_06_03.md

## Deletion Rationale

The compliance audit identified a bifurcated pipeline architecture in `ax prove`:
- **Shortcut path**: `runAxProveShortcutCli` → topology scan only (no verification)
- **Verify path**: `runUniversalAcceptancePipelineCore` → orphaned, no active caller
- **Unified path**: `AxiomEngine` (new) → single entry point for all proof tasks

To eliminate the architectural debt of parallel pipelines, the following dead code
was removed after its unique logic was extracted into reusable components:

## Deleted / Removed Components

| Component | File | Replacement |
|-----------|------|-------------|
| `runAxProveShortcutCli` | `src/cli/wf_runners.nim` | `runAxiomEngineCli` in `src/cli/axiom_engine.nim` |
| `shouldUseAxProofShortcut` | `src/cli/ax_workflow_shortcuts.nim` | Removed — no bifurcation needed |
| `cliRunAxProofShortcut` enum | `src/cli/cli_types.nim` | `cliRunAxiomEngine` |
| `cliRunAxProofShortcut` dispatch | `src/cli/action_interpreter_cli.nim` | `cliRunAxiomEngine` dispatch |
| `runUniversalAcceptancePipelineCore` | `src/verification/pipeline_core_runner_parts/pipeline_core_runner_part2.nim` | `VerificationUnit` (`src/core/verification_unit.nim`) |

## Extracted Logic (Reusable Components)

The unique verification logic formerly trapped inside
`runUniversalAcceptancePipelineCore` was extracted into three first-class modules:

1. **`src/core/pipeline_adapter.nim`** — UAP Persona Pipeline ↔ Orchestrator CEGAR bridge.
   Elevates CEGAR from SMT-timeout fallback to first-class `psCegarAbstraction` stage.

2. **`src/core/verification_unit.nim`** — Stateless `VerificationUnit` providing
   `runSelfHealing()` and `runLeanProofRefinement()` as pure functions.
   Consumed by both `judge.certify` and `legislator.legislate`.

3. **`src/personas/legislator_feedback.nim`** — Closed-loop Judge → Legislator feedback.
   `CounterExamplePayload` type + `legislateWithFeedback()` for CEGIR
   (counterexample-guided invariant refinement).

## Restoration Risk

- **Low** for `runAxProveShortcutCli` / `shouldUseAxProofShortcut` — the unified
  `AxiomEngine` covers all previous shortcut behaviors plus full verification.
- **Low** for `runUniversalAcceptancePipelineCore` — its logic is preserved in
  `VerificationUnit` with improved testability (pure functions, no orphaned state).

## Verification

- All removed symbols verified as unreferenced via `grep -r` across `src/`.
- Replacement modules compile independently (`nim c` on each new file).
- `action_interpreter_cli.nim` compiles with updated dispatch.
- `ax_workflow_shortcuts.nim` compiles with removed function.

## Related

- Compliance audit: `docs/history/reports/ax_prove_notion_compliance_audit_2026_06_03.md`
- Unified engine: `src/cli/axiom_engine.nim`
