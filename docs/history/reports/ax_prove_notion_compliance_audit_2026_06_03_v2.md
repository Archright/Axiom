# `ax prove` ↔ Notion Specification v0.3.7 Compliance Re-Audit Report

**Date**: 2026-06-03 (post-remediation)  
**Auditor**: Kimi Code CLI (Axiom Project Agent) + Parallel Subagent Fleet  
**Scope**: `ax prove` command and its 6 Notion pillars after commits `b4262de3` and `5fa45958`  
**Notion Spec**: https://app.notion.com/p/344c1d573f3f802299b5fecd0086e0a7  
**Previous Audit**: `docs/reports/ax_prove_notion_compliance_audit_2026_06_03.md` (baseline `d0040e47`)

---

## 1. Executive Summary

| Pillar | Prior Score | Current Score | Delta | Status |
|---|---|---|---|---|
| **4-Layer Verification Engine** | 2.5 / 4 | **3.0 / 4** | +0.5 | PARTIAL → IMPROVED |
| **Core Quartet Personas** | 1.0 / 4 | **2.5 / 4** | +1.5 | PARTIAL → IMPROVED |
| **3 Final Gates** | 1.0 / 3 | **1.5 / 3** | +0.5 | PARTIAL → IMPROVED |
| **6 Supreme Techniques** | 3.5 / 6 | **4.0 / 6** | +0.5 | PARTIAL → IMPROVED |
| **Self-Evolution Loop** | 1.0 / 5 | **1.5 / 5** | +0.5 | PARTIAL → IMPROVED |
| **CLI Output & Localization** | 1.0 / 3 | **2.0 / 3** | +1.0 | PARTIAL → IMPROVED |
| **Overall** | **10.0 / 25** | **14.5 / 25** | **+4.5** | **+18 pp** |

### Single Most Critical Remaining Gap

**Legislator-Scribe Semantic Mismatch & Missing Outer Convergence Loop.**
The compile-time `LayerMapping` in `persona_interface.nim` now claims `pkLegislator → plkScribe` (Layer 3), but `legislator.nim` still performs only invariant drafting and self-healing — zero LLM theorem synthesis. Meanwhile, the Self-Evolution Loop remains a single-pass sequential pipeline instead of an iterative convergence cycle. These two gaps are structurally interdependent: without a true Scribe persona generating Lean drafts, and without an outer loop feeding Judge diagnostics back to Detective, the "autonomous evolution" contract of the Notion spec cannot be satisfied.

### Second Most Critical Remaining Gap

**Empty Diagnosis Location Data.**
Despite wiring real CEGAR and BMC engines, both the main diagnosis path (`judge.nim:parseDiagnosticToDiscontinuities`) and the new CEGAR→BMC fallback path (`universal_pipeline.nim:84-94`) populate `MathematicalDiscontinuity` with `filePath: ""`, `lineNumber: 0`, and `smtUnsatCoreVars: @[]`. The spec requires *정밀 명세* (precise specification) of discontinuity points; this remains unimplemented.

---

## 2. Pillar-by-Pillar Delta Analysis

### 2.1 4-Layer Verification Engine (2.5 → 3.0 / 4)

| Layer | Prior | Current | Verdict |
|---|---|---|---|
| **L1 Scout / BMC** | Shallow wrapper, SWAT didn't call it | SWAT now calls `runLayer1Bmc`; wrapper still naive | **IMPROVED** |
| **L2 Detective / CEGAR** | Real CEGAR orphaned, PDR stub wired | `detective.openCase` calls `proveWithFixedpoint` + `runCegarLoop` fallback; `cegar_bmc_bridge` active in UAP | **FIXED** |
| **L3 Scribe / LLM** | Inline `callLeanstral` in pipeline, no persona | Still inline; Legislator does not perform Scribe work | **UNCHANGED** |
| **L4 Judge / Lean 4** | Real Lean 4 replay + single retry | Unchanged; compliant | **COMPLIANT** |

**Key evidence**:
- `detective.nim:47-59` — real fixed-point + CEGAR fallback wired.
- `universal_pipeline.nim:77-95` — CEGAR counterexample → BMC witness fallback path.
- `layer1_bmc.nim` — still uses `sourceCode.contains("while")` and hardcoded property kinds (downstream issue, not persona-layer gap).

---

### 2.2 Core Quartet Personas (1.0 → 2.5 / 4)

| Persona | Prior | Current | Verdict |
|---|---|---|---|
| **SWAT** | Layer 2 (CEGAR), no BMC | Layer 1 (Scout) via `LayerMapping`; calls `runLayer1Bmc` | **FIXED** |
| **Detective** | Layer 1 (topology), no CEGAR | Layer 2 via `LayerMapping`; CFG + fixed-point + CEGAR | **FIXED** |
| **Legislator** | Layer 2.5 (invariant drafting) | Layer 3 via `LayerMapping`, but behavior unchanged | **TYPE-ONLY FIX** |
| **Judge** | Layer 3-4, real Lean replay | Unchanged; compliant | **COMPLIANT** |

**Key evidence**:
- `persona_interface.nim:24-35` — compile-time bijective `LayerMapping` with `static` assertions.
- `legislator.nim:49-78` — still no `callLeanstral` or Lean theorem generation.
- `detective.nim:93-116` — `investigate` still static; does not consume CEGAR artifacts from `openCase`.

---

### 2.3 3 Final Gates (1.0 → 1.5 / 3)

| Gate | Prior | Current | Verdict |
|---|---|---|---|
| **판별 (The Sieve)** | Post-UAP classification only | Still post-UAP only; no AST pre-classifier | **UNCHANGED** |
| **진단 (The Diagnosis)** | Keyword-only, empty location | Keyword-only, empty location; new CEGAR fallback also empty | **PARTIALLY IMPROVED** |
| **교정 (The Guidance)** | Templates never applied, healing no-op | `applyRefactoringTemplate` active (2/6 patterns); stagnation still unconnected | **IMPROVED** |

**Key evidence**:
- `refactoring_engine.nim:145-184` — `applyRefactoringTemplate` now implements 2 patterns.
- `healing_orchestrator.nim:37` — calls `applyRefactoringTemplate` instead of no-op.
- `judge.nim:49-52` — `filePath: ""`, `lineNumber: 0` persist.
- `batch_uap_orchestrator.nim` — no structured pre-UAP sieve taxonomy.

---

### 2.4 6 Supreme Techniques (3.5 → 4.0 / 6)

| Technique | Prior | Current | Verdict |
|---|---|---|---|
| **CEGAR** | Real but orphaned | Wired into Detective + UAP fallback | **FIXED** |
| **고정점 기반 정적 분석** | Real in CEGAR; stub PDR | `proveWithFixedpoint` wired in Detective | **IMPROVED** |
| **요약 기반 분석 (Modular)** | Cache table only | Still cache-only; `preConditions`/`postConditions` never populated | **UNCHANGED** |
| **SMT 기반 유도 증명** | Real CHC engine; stub PDR entry | CHC engine exists; PDR quarantined; no new SMT unsat-core logic | **UNCHANGED** |
| **BMC** | Real generic engine | Unchanged; compliant | **COMPLIANT** |
| **연역적 프로그램 검증 (Lean 4)** | Real kernel replay | Unchanged; compliant | **COMPLIANT** |

**Key evidence**:
- `cegar_engine.nim:150-259` — `runCegarLoop` now called from `detective.nim`.
- `fixedpoint_engine.nim` — CHC emission + Z3 Spacer solving exists but only reached via Detective fallback.
- `function_verification_summary.nim` — still a pure cache table.

---

### 2.5 Self-Evolution Loop (1.0 → 1.5 / 5)

| Gap | Prior | Current | Verdict |
|---|---|---|---|
| **Persona-layer inversion** | Inverted | Fixed by `LayerMapping` | **CLOSED** |
| **Healing no-op** | `changed = false` | Calls `applyRefactoringTemplate` | **PARTIALLY CLOSED** |
| **Single retry, not a loop** | At most 1 retry | Still hard cap = 1; `maxRounds` ignored | **UNCHANGED** |
| **No outer pipeline loop** | Sequential 1-pass | Still sequential 1-pass | **UNCHANGED** |
| **No convergence criterion** | None | Still none | **UNCHANGED** |

**Key evidence**:
- `healing_orchestrator.nim:32, 88` — `let roundsCap = 1` hardcoded.
- `universal_pipeline.nim:31-262` — no `while` loop; stages run once.
- `integrity_refinement_loop.nim:185-259` — real `while` loop exists but Bitcoin-Script-specific and not imported by UAP.

---

### 2.6 CLI Output & Localization (1.0 → 2.0 / 3)

| Gap | Prior | Current | Verdict |
|---|---|---|---|
| **3-gate structure in TUI** | Missing | `renderTuiReport` renders Sieve/Diagnosis/Guidance | **CLOSED** |
| **3-gate structure in plain-text** | Missing | `wf_render.nim` still gate-less | **UNCHANGED** |
| **Korean gate names** | Missing | English only (`Sieve-Gate`, etc.); AGENTS.md §1.1 conflict | **UNCHANGED** |
| **Render-path consistency** | N/A | `renderTuiReportWithWidth` omits gate summary (divergence) | **NEW GAP** |

**Key evidence**:
- `ax_tui_reporter_part2.nim:337-342` — gate headers appended in `renderTuiReport`.
- `ax_tui_reporter_part2.nim:352-430` — `renderTuiReportWithWidth` omits gate block.
- `wf_render.nim` — zero `notion_semantic_mapper` imports.
- `notion_semantic_mapper.nim:17-28` — `GateLocalizedNames` are English.

---

## 3. Cross-Pillar Issues

### Issue X1: Compile-Time Claim vs. Runtime Behavior Divergence
The `static` assertion in `persona_interface.nim` creates a compile-time bijection (`pkLegislator → plkScribe`), but `legislator.nim` contains zero LLM formalization logic. This misleads future maintainers and breaks the Notion spec's Layer 3 contract. **Affected pillars**: Personas, 4-Layer Engine, Self-Evolution Loop.

### Issue X2: Empty Location Data Replicated Across Paths
Both the main diagnosis path (`judge.nim`) and the new CEGAR→BMC fallback path (`universal_pipeline.nim`) return `MathematicalDiscontinuity` with empty `filePath`/`lineNumber`/`smtUnsatCoreVars`. Fixing this requires wiring the CFG builder / AST offset mapper into both paths. **Affected pillars**: 3 Gates, 4-Layer Engine.

### Issue X3: `maxRounds` Parameter Regression
Commit `b4262de3` changed `healing_orchestrator.nim` from `roundsCap = maxRounds` to `roundsCap = 1`, silently discarding the caller's iteration budget. This breaks the Self-Evolution Loop's configurability. **Affected pillars**: Self-Evolution Loop, 3 Gates.

---

## 4. Prioritized Action Items

| Priority | Action | Owner Pillar | Target File(s) |
|---|---|---|---|
| **P0** | Move Leanstral synthesis into Legislator or create `scribe.nim` | Personas / 4-Layer | `src/personas/legislator.nim` or new `src/personas/scribe.nim` |
| **P0** | Close the outer evolution loop — wrap UAP stages in `while` with termination on `leanKernelVerified` / max iterations / stagnation | Self-Evolution | `src/verification/universal_pipeline.nim` |
| **P0** | Populate diagnosis location data — wire CFG offsets into `MathematicalDiscontinuity` | 3 Gates / 4-Layer | `src/personas/judge.nim`, `src/verification/universal_pipeline.nim` |
| **P1** | Restore `maxRounds` respect in healing loops | Self-Evolution | `src/verification/healing_orchestrator.nim` |
| **P1** | Implement remaining 4 refactoring patterns + Z3 equivalence check | 3 Gates | `src/core/refactoring_engine.nim`, `src/verification/healing_orchestrator.nim` |
| **P1** | Connect stagnation logic (`recordFailure` / `recordSuccess`) | 3 Gates / Self-Evolution | `src/verification/universal_pipeline.nim`, `src/core/refactoring_engine.nim` |
| **P1** | Add 3-gate summary to `renderTuiReportWithWidth` | CLI Output | `src/ui/ax_tui_reporter_parts/ax_tui_reporter_part2.nim` |
| **P1** | Integrate gate mapping into `wf_render.nim` plain-text path | CLI Output | `src/cli/wf_render.nim` |
| **P2** | Implement AST-based Sieve pre-classifier (loops, recursion, non-linear arithmetic) | 3 Gates | `src/verification/batch_uap_orchestrator.nim` or new `src/personas/simp.nim` |
| **P2** | Generalize `integrity_refinement_loop.nim` for domain-agnostic use | Self-Evolution | `src/core/integrity_refinement_loop.nim` |
| **P2** | Implement external i18n resource for Korean gate names | CLI Output | New `resources/i18n/ko.json` |
| **P3** | Populate `function_verification_summary` pre/post-conditions | 6 Techniques | `src/core/function_verification_summary.nim` |

---

## 5. Evidence Index

| ID | File | Line(s) | Description |
|----|------|---------|-------------|
| E201 | `src/personas/detective.nim` | 47-59 | Fixed-point + CEGAR fallback wired in `openCase` |
| E202 | `src/verification/universal_pipeline.nim` | 77-95 | CEGAR counterexample → BMC witness fallback path |
| E203 | `src/personas/persona_interface.nim` | 24-35 | Compile-time `LayerMapping` with bijective assertions |
| E204 | `src/personas/legislator.nim` | 49-78 | No LLM theorem synthesis despite `plkScribe` mapping |
| E205 | `src/core/refactoring_engine.nim` | 145-184 | `applyRefactoringTemplate` with 2 real pattern implementations |
| E206 | `src/verification/healing_orchestrator.nim` | 32, 88 | `roundsCap = 1` hardcoded; `maxRounds` ignored |
| E207 | `src/ui/ax_tui_reporter_parts/ax_tui_reporter_part2.nim` | 337-342 | TUI renders 3 gate headers |
| E208 | `src/ui/ax_tui_reporter_parts/ax_tui_reporter_part2.nim` | 352-430 | `renderTuiReportWithWidth` omits gate block |
| E209 | `src/personas/judge.nim` | 49-52 | Empty `filePath`/`lineNumber`/`smtUnsatCoreVars` persist |
| E210 | `src/verification/universal_pipeline.nim` | 84-94 | New CEGAR fallback also emits empty location data |
| E211 | `src/cli/wf_render.nim` | — | Zero gate-related rendering; no `notion_semantic_mapper` import |
| E212 | `src/core/integrity_refinement_loop.nim` | 185-259 | Real `while` loop; Bitcoin-Script-specific; not imported by UAP |
| E213 | `src/ui/notion_semantic_mapper.nim` | 17-28 | `GateLocalizedNames` are English only |

---

*Report generated by parallel subagent fleet (4 of 6 completed; 2 timed out and synthesized from cross-agent evidence + manual inspection).*
*Methodology: Read-only codebase exploration; no source modifications.*
*Delta baseline: `d0040e47` → `5fa45958`.*
