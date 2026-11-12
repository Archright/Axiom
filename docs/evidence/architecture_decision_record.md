# Architecture Decision Record
> **Note (2026-05-25):** CONTEXT.md was merged into AGENTS.md §0-§1. References to "CONTEXT.md" below refer to the pre-merge structure. See AGENTS.md for current SSOT.

- [MCP Server Integration](mcp_server_integration.md): Building a lightweight MCP server that provides memory-based verification and refinement tools (axiom_validate_integrity, etc.)
- [Throttled Self-Healing Pipeline](throttled_self_healing_pipeline.md): SMT unsat-core analysis and deterministic invariant refinement hint suggestions (Smart Search, The Judge)
- [Prevention of Vacuous Truth](vacuous_truth_prevention.md): Blocking false positives through SMT-LIB dual-pass pipeline construction
- [Removal of Magic String](magic_string_removal.md): Removing implicit dependencies and controlling side effects through explicit flag-based control
- [3-Tier Proof System](three_tier_proof_system.md): Enforcing triangular integrity across docs/evidence/, CONTEXT.md, and tests/features/

- GUARDIAN.md § 0: Integrity downgrade prohibition (No-Downgrade Policy). Prohibiting `func→proc` changes and `{.noSideEffect.}` removal, enforcing dependency injection pattern.
- GUARDIAN.md § 12: NoNonAlignedOutput. All CLI table outputs must use fixed-width alignment and Unicode box-drawing characters.
- src/cli/report.nim: Separated pure computation function module. All functions like `createLayoutConfig`, `renderUnicodeBoxTop`, `formatTimeField` use `func` and `{.noSideEffect.}`. Uses `computeDynamicColumnWidths` for content-based dynamic column width calculation.
- src/ui/display.nim: Added `termWidth: int` parameter to `renderProgressLine` to change to dependency injection structure.
- src/ui/ax_tui_reporter.nim: Applied Unicode box-drawing (┌, ─, │), displaying counts in section headers, distinguishing auxiliary information with Dim color. Implemented `termWidth` injection pattern via `renderTuiReportWithWidth`. Dynamic column width maintains alignment even for long content like "Unattempted: 9580". Entry alignment: ID(4 chars) + label(dynamic) + `[` immediately followed by left-aligned status/reason + trailing padding based on longest badge visible on current screen + common `]` column format.
- src/core/orchestrator.nim: Added `processorCount: int` parameter to `computeParallelWorkerLimit`.
- src/cli/main.nim: Added `processorCount: int` parameter to `computeSmartQueueLimit` and `computeSmartDiagnosisDepth`.
- src/core/trusted_base.nim: Applied macOS Mach-O section format `__DATA,__axiom_proof`.