# Quarantine Registry: 2026-06-08 Batch

**Date:** 2026-06-08

> Append-only registry of quarantined modules.
> Purpose: Track files moved to `experimental/pending_deprecation/` and prevent undocumented quarantine drift.
> Authority: AGENTS.md §1.2 (Experimental Zone Sub-structure), §2.1 #3a (Annals Write-Back).

---

## File 1 — axiom_catalog_validator.nim

| Field | Value |
|-------|-------|
| **Original Path** | `src/core/axiom_catalog_validator.nim` (or equivalent core location) |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_08/axiom_catalog_validator.nim` |
| **Quarantine Reason** | Compile-time macro (`loadAndValidateAxiomCatalog`) that loads and validates the externalized axiom catalog JSON against `AxiomMapping` schema. Replaced by runtime validation or consolidated into the verified axioms pipeline. No active importers remain in `src/`. |
| **Restoration Risk** | LOW — compile-time validation macro with zero production callers after axiom catalog refactoring. |
| **Recommended Action** | DELETE — functionality superseded by current verified axioms infrastructure. |
| **SSOT Authority** | AGENTS.md §1.2 (Quarantine Policy), §1.3 (SSOT), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: Only if a standalone compile-time catalog validator is needed again. Prefer integrating validation into the existing `verified_axioms` module rather than restoring this standalone file.

---

## File 2 — axiom_contract.nim

| Field | Value |
|-------|-------|
| **Original Path** | `src/core/axiom_contract.nim` (or equivalent core location) |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_08/axiom_contract.nim` |
| **Quarantine Reason** | Doc-Code Sync Enforcement via `@axiom-constraint` annotations. Compile-time macro (`axiomContractEnforce`) that parses source files for constraint annotations and validates documentation references. Large module (~200 lines) with parsing, validation, and compile-time macro API. The annotation-based doc-code sync approach was replaced by the gate-based enforcement pipeline (`nimtry`, `procedure-gate`). |
| **Restoration Risk** | MEDIUM — contains well-structured parsing logic that could be reused, but annotation format is project-specific with no external consumers. |
| **Recommended Action** | DELETE — annotation-based enforcement is incompatible with the current gate-driven architecture. If doc-code sync is needed, implement as a nimtry plugin. |
| **SSOT Authority** | AGENTS.md §1.2 (Quarantine Policy), §1.5 (nimtry Engine), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: If lightweight inline doc-code sync annotations are reintroduced. Must be implemented as a nimtry rule, not a standalone macro.

---

## File 3 — intrinsic_filter.nim

| Field | Value |
|-------|-------|
| **Original Path** | `src/core/intrinsic_filter.nim` |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_08/intrinsic_filter.nim` |
| **Quarantine Reason** | Legacy intrinsic property filter behind compile-time switch (`-d:axiomLegacyFallback`). Default build already produced a compile error (`{.error: "Legacy module ... Migrate to new API."}`). All intrinsic property logic was migrated to `verified_axioms.nim`. The file contained wrapper functions (`isTrivialViaZ3`, `isIntrinsicProperty`, `normalizeLeanUnicode`) that delegate to the verified axiom registry. |
| **Restoration Risk** | LOW — module was already gated behind a compile-time flag with an explicit error message directing migration. Zero active callers. |
| **Recommended Action** | DELETE — migration to `verified_axioms.nim` is complete. Legacy compile-time switch serves no purpose. |
| **SSOT Authority** | AGENTS.md §0.6 (Static First Enforcement), §1.2 (Quarantine Policy), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: None. The `verified_axioms.nim` module is the canonical replacement. Any new intrinsic property detection should be added there.

---

## File 4 — safe_json_accessors.nim

| Field | Value |
|-------|-------|
| **Original Path** | `src/core/safe_json_accessors.nim` (or equivalent core location) |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_08/safe_json_accessors.nim` |
| **Quarantine Reason** | Safe JSON field accessor wrappers (`safeGetString`, `safeGetInt`, `safeGetFloat`, `safeGetBool`, `safeGetArray`). Provides null-safe JSON extraction with defaults. Functionality consolidated into `core/safe_parsers` or replaced by direct `std/json` usage with appropriate nil-checks at call sites. No active importers remain. |
| **Restoration Risk** | LOW — thin wrapper functions with no complex logic. If safe JSON access is needed, `std/json` with `getOrDefault` or inline guards are sufficient. |
| **Recommended Action** | DELETE — utility wrappers with zero callers. Avoids DRY violation with `safe_parsers`. |
| **SSOT Authority** | AGENTS.md §1.2 (Quarantine Policy), §1.3 (SSOT), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: Only if a centralized safe JSON accessor module is explicitly needed again. Prefer inline nil-checks at call sites to maintain the "no unnecessary abstraction layers" principle.

---

## File 5 — type_registry.nim

| Field | Value |
|-------|-------|
| **Original Path** | `src/core/step_registry.nim` (or equivalent core location) |
| **Quarantine Destination** | `experimental/pending_deprecation/2026_06_08/type_registry.nim` |
| **Quarantine Reason** | Schema-Aware Complexity (SAC) type registry. Large module (~220 lines) that builds a global type-name→field-count mapping from the source tree, with heuristic fallback weights for known stdlib types, data-derived weights, and name-suffix heuristics. Part of the D-Factor complexity analysis. Over-engineered for current needs; the complexity gate was simplified or removed from the verification pipeline. |
| **Restoration Risk** | MEDIUM — contains well-researched heuristic data (Phase 0 analysis weights, suffix heuristics) that may be useful for future complexity analysis. However, the file I/O scanning approach (`walkDirRec`) is expensive and the registry was not cached. |
| **Recommended Action** | DELETE — complexity analysis should be reimplemented as a nimtry rule or gate plugin if needed, not as a standalone file I/O scanner. |
| **SSOT Authority** | AGENTS.md §1.2 (Quarantine Policy), §1.5 (nimtry Engine), §2.1 #3a (Annals Write-Back) |

**Resurrection Conditions**: If complexity-aware verification is reintroduced. Must be implemented as a nimtry plugin with incremental caching (SHA256), not a raw `walkDirRec` scanner. The heuristic weight tables (KnownStdlibTypes, DataDerivedWeights, SuffixHeuristics) should be extracted into a separate data file if reused.

---

## Deletion Checklist

If a future agent proposes restoring a quarantined file from this batch, require ALL of the following:

1. [ ] The file is listed in this registry with a documented quarantine reason.
2. [ ] The agent provides evidence that the quarantine reason no longer applies.
3. [ ] The agent runs the appropriate gate (`src/gate/nimtry/nimtry_cli.nim`, `bin/procedure_gate`) and shows PASS.
4. [ ] The agent updates this registry with a "Restored" entry (date, agent, justification).
5. [ ] `nimble test` passes after restoration.
