# Quarantine Registry: layer2_pdr.nim

**Date:** 2026-06-03

## File Paths

- **Original:** `src/verification/engine_variants/layer2_pdr.nim`
- **Quarantine Destination:** `experimental/pending_deprecation/2026_06_03/layer2_pdr.nim`

## Deletion Reason

Hardcoded HORN query template stub. The real engine (`fixedpoint_engine.nim`) is now bound and superseded this placeholder. The stub contained only skeletal PDR (Property Directed Reachability) logic with hardcoded query fragments that do not integrate with the current 4-layer verification pipeline (Scout → Detective → Scribe → Judge).

## Restoration Risk

**Low.** The stub has zero production callers after the pipeline refactoring. All call sites previously referencing `layer2_pdr` have been redirected to `fixedpoint_engine.nim` as part of the `ax prove` v0.3.7 compliance work.

## SSOT Authority

- AGENTS.md §1.2 Quarantine Policy
- AGENTS.md §2.1 #3a Annals Write-Back

## Related Commit Context

Part of `ax prove` Notion spec v0.3.7 compliance remediation.

## Deletion — 2026-06-05: Expired Quarantine

**Deletion date**: 2026-06-05
**Rationale**: File quarantined 2026-06-03, exceeded waiting period with zero importers confirmed in `src/` and `tests/`. Safe to permanently delete.
**Authority**: AGENTS.md §1.2 Quarantine Policy, `experimental/README.md` Quarantine Protocol.
**Importers verified**: 0 in `src/`, 0 in `tests/`.
