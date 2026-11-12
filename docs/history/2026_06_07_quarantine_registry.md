# Quarantine Registry: 2026-06-07 Batch

**Date:** 2026-06-07

> Append-only registry of quarantined modules.
> Purpose: Track files moved to `experimental/pending_deprecation/` and prevent undocumented quarantine drift.
> Authority: AGENTS.md §1.2 (Experimental Zone Sub-structure), §2.1 #3a (Annals Write-Back).

---

## File 1 — cac_test.nim

| Field | Value |
|-------|-------|
| **Original Path** | `tests/gateway/cac_test.nim` (or equivalent test location) |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_07/cac_test.nim` |
| **Quarantine Reason** | Content-Addressable Cache (CAC) gateway test for `isAsiCacheValid`. The CAC mechanism and `asi_cli` integration were deprecated or refactored; the test no longer matches the current ASI validation pipeline. |
| **Restoration Risk** | LOW — test verifies deprecated CAC behavior; current ASI pipeline does not use this cache strategy. |
| **Recommended Action** | DELETE — no production code path exercises this test's coverage area. |
| **SSOT Authority** | AGENTS.md §0.7 (Business-Only Test Scope), §1.2 (Quarantine Policy), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: Only if CAC mechanism is reintroduced into the ASI pipeline. In that case, a new test must be written against the new API surface, not restored from this file.

---

## Deletion Checklist

If a future agent proposes restoring a quarantined file from this batch, require ALL of the following:

1. [ ] The file is listed in this registry with a documented quarantine reason.
2. [ ] The agent provides evidence that the quarantine reason no longer applies.
3. [ ] The agent runs the appropriate gate (`src/gate/nimtry/nimtry_cli.nim`, `bin/procedure_gate`) and shows PASS.
4. [ ] The agent updates this registry with a "Restored" entry (date, agent, justification).
5. [ ] `nimble test` passes after restoration.
