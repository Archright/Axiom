# Report Output & Stale State Guardrails

> Extracted from AGENTS.md §7. Refer back to AGENTS.md §3 for the condensed version.

## Report TUI Policy

- `ax report` (without flags) MUST output a human-readable TUI (ASCII table) to stdout.
- `ax report --json` is the ONLY path that emits raw JSON to stdout.
- `renderReportStdoutLines` must never silently fall back to JSON when TUI lines are present; `cmdReport` dispatches based on `logLines` vs `outputJson` explicitly.
- Any change to `runReportCli` that bypasses `renderAsiReportTui` is a regression and must be caught by the BDD scenario `ax report shows TUI by default`.

## Stale Proof State Auto-Purge (Physical Guardrail)

- `logs/ax_proof_state.json` is a transient execution artifact, not a SSOT.
- If the file is older than 24 hours, the archive helper `archiveStaleProofState` (`src/cli/report_cli.nim`) moves it to `logs/ax_proof_state.json.stale.<timestamp>`. It is currently not wired into the report read path (no production caller; covered by `tests/cli/test_report_cli.nim`).
- ASI calculation MUST rely on the certificate vault (`src/verification/certificates/`) as the sole SSOT; stale `ax_proof_state.json` entries must never zero-out the ASI score.
- The read-side guarantee is enforced in `verification/proof_state_builder.nim` (`getUnifiedAsiFixed4`/`getUnifiedAsiGraded4` always hydrate from the certificate vault; the cached-state fast path was removed) and is not configurable without a `GUARDIAN.md` amendment.

## Evidence Receipt Guardrail (EDC Protocol)

- Sub-agent post-condition verification produces `docs/evidence/verifications/*.evidence` receipts.
- Parent agents MUST verify receipt existence and HEAD hash binding before trusting sub-agent results.
- Full protocol: see AGENTS.md §2.5; subagent-delegation enforcement (superseding the `subagent-mandate` skill) lives in `src/gate/runners/delegation_enforcer.nim` — see `docs/agents/plugin-migration.md`.

## data/universe_merkle.lock Sovereignty Rule

1. `data/universe_merkle.lock` is a deterministic snapshot of the integrity universe and MUST remain Git-tracked.
2. The pre-push hook MUST reference this file in a read-only manner only. Under no circumstances may the hook directly modify (write to) the physical lock file, thereby leaving unstaged residue in the working tree.
3. The sole authority to update the lock in response to asset changes is the `ax prove` command-line interface, which serves as the single source of truth (SSOT) for lock regeneration.
