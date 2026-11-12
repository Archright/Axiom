# `ax prove` ↔ Notion Specification v0.3.7 Compliance Audit Report

**Date**: 2026-06-03  
**Auditor**: Kimi Code CLI (Axiom Project Agent) + Parallel Subagent Fleet  
**Scope**: `ax prove` command and its underlying 4-Layer Verification Engine, 3 Final Gates, 6 Supreme Techniques, Core Quartet Personas, and Self-Evolution Loop  
**Notion Spec**: https://app.notion.com/p/344c1d573f3f802299b5fecd0086e0a7  
**Commit**: `d0040e47`

---

## 1. Executive Summary

| Pillar | Status | Severity | Score |
|---|---|---|---|
| **4-Layer Verification Engine** | PARTIAL | Major | 2.5 / 4 |
| **6 Supreme Techniques** | PARTIAL | Major | 3.5 / 6 |
| **Core Quartet Personas** | PARTIAL | Critical | 1 / 4 |
| **Self-Evolution Loop** | PARTIAL | Major | 1 / 5 |
| **3 Final Gates of ax prove** | PARTIAL | Critical | 1 / 3 |
| **CLI Output Structure** | PARTIAL | Medium | ASI reported; gates not surfaced in Korean |

### Single Most Critical Finding

**Persona-Layer Inversion & Dead Code.** The 4-Layer pipeline exists in type signatures and comments, but the actual execution order inverts persona roles (SWAT runs CEGAR instead of BMC; Detective runs topology scan instead of abstract interpretation). The real CEGAR engine (`cegar_engine.nim`) and real fixed-point engine (`fixedpoint_engine.nim`) are **orphaned** — present in the codebase but never invoked by `runUniversalAcceptancePipeline`.

### Second Most Critical Finding

**Operational No-Ops.** The 3 Final Gates and the Self-Evolution Loop have complete type frameworks (`MathematicalDiscontinuity`, `StructuredRemediationPayload`, `RefactoringStagnation`) but their operational bodies are no-ops: healing sets `changed = false`, diagnosis returns empty `filePath`/`lineNumber`, and the evolution loop performs at most a single retry instead of iterative convergence.

---

## 2. 4-Layer Verification Engine Compliance

### Notion Spec

```
Layer 1: Scout  → BMC          (shallow bug filtering)
Layer 2: Detective → CEGAR/PDR (abstract interpretation, invariant synthesis)
Layer 3: Scribe   → LLM Auto-formalization (Lean 4 proof draft)
Layer 4: Judge    → Lean 4 Kernel (100% deterministic truth)
```

### Implementation Analysis

| Layer | Code Artifact | Wired into UAP? | Real Implementation? | Verdict |
|---|---|---|---|---|
| **L1 Scout / BMC** | `layer1_bmc.nim` + `bmc_generic.nim` | ✅ Early-exit | ⚠️ Shallow stub wrapper + real generic engine | **PARTIAL** |
| **L2 Detective / CEGAR** | `cegar_engine.nim` + `layer2_pdr.nim` | ⚠️ Stub PDR wired; real CEGAR orphaned | ✅ Real CEGAR / ❌ Stub PDR | **PARTIAL** |
| **L3 Scribe / LLM** | `callLeanstral` (inline in `universal_pipeline.nim`) | ✅ Called | ✅ Real Leanstral gateway | **PARTIAL** (no persona) |
| **L4 Judge / Lean 4** | `judge.nim` | ✅ Called | ✅ Real Lean 4 replay + closed-loop retry | **COMPLIANT** |

#### Layer 1 — Scout / BMC (PARTIAL)

- `bmc_generic.nim` implements a genuine bounded model checker with recursive state-space exploration (`genericExplore`), witness traces (`GenericBmcTrace`), and violation detection for race conditions, integer overflow, index bounds, and null dereference.
- **However**, `layer1_bmc.nim` wraps it naively: loop detection is `sourceCode.contains("while") or contains("for")`; for loop-free code it calls `verifyGenericProperty(config, @[0], 0)` with **hardcoded** property kind (`bpkIndexOutOfBounds`) and initial values. It does not parse the actual function's parameters or AST.
- The SWAT persona (`swat.nim`) does **not** call BMC. Instead, `executeRaid` calls `runNegativeInvariantSearch` (static heuristics).

#### Layer 2 — Detective / CEGAR / PDR (PARTIAL)

- `cegar_engine.nim` contains a **real** CEGAR implementation: `runCegarLoop` with interval abstraction (`refineIntervals`), Z3-backed invariant synthesis (`synthesizeLoopInvariant`), FNV-1a fingerprinting for fixed-point detection, and termination on convergence / max iterations (20) / budget (30s).
- **However**, `runUniversalAcceptancePipeline` **never calls** `runCegarLoop`. It calls the stub `runPdrSpacer` in `layer2_pdr.nim`, which builds a **hardcoded template HORN query** that discards the actual function name and variable count.
- The real fixed-point engine (`src/core/solver/fixedpoint_engine.nim`) with genuine CHC emission and Z3 Spacer solving is also **not wired** into the UAP pipeline.
- The Detective persona (`detective.nim`) does **not** perform CEGAR or abstract interpretation. `openCase` calls `runNegativeInvariantSearch` (static heuristic scanning).

#### Layer 3 — Scribe / LLM Auto-formalization (PARTIAL)

- `callLeanstral` (from `leanstral_gateway.nim`) is invoked inline in `universal_pipeline.nim` with a prompt that seeds the function name, invariant, and source code. It generates Lean 4 theorem source.
- **However**, there is no dedicated **Scribe** persona module (`src/personas/scribe.nim`). The Legislator persona is incorrectly mapped to "Layer 2.5" and performs invariant drafting, not Lean theorem synthesis.

#### Layer 4 — Judge / Lean 4 Kernel (COMPLIANT)

- `judge.nim` `certify` correctly:
  1. Accepts pre-synthesized Lean source from Leanstral (Scribe shortcut).
  2. Runs `runLeanReplay` to spawn the Lean 4 kernel subprocess with 60s timeout.
  3. Enforces anti-vacuity via `#print axioms <theoremName>`.
  4. Implements a **single** closed-loop retry: if Lean rejects, injects counterexample into Legislator via `legislateWithFeedback` and retries once.
  5. Returns `leanKernelVerified` flag.
- This is the only layer that fully satisfies the Notion spec.

---

## 3. Core Quartet Personas ↔ Notion Spec Mapping

| Notion Persona | Notion Role | Code Persona | Code Mapped Layer | Actual Implementation | Verdict |
|---|---|---|---|---|---|
| **특공대 (SWAT)** | Layer 1: BMC / Scout | `swat.nim` | Layer 2 (CEGAR) ❌ | `runNegativeInvariantSearch` (static heuristics) | **PARTIAL** |
| **탐정 (Detective)** | Layer 2: CEGAR / PDR / Z3 | `detective.nim` | Layer 1 (topology/BMC) ❌ | `runNegativeInvariantSearch` (static heuristics) | **PARTIAL** |
| **입법자 (Legislator)** | Layer 3: Scribe / LLM | `legislator.nim` | Layer 2.5 (invariant drafting) ❌ | Self-healing + invariant drafting; NO Lean synthesis | **PARTIAL** |
| **대법관 (Judge)** | Layer 4: Lean 4 Kernel | `judge.nim` | Layer 3-4 ✅ | `runLeanReplay` + closed-loop feedback | **COMPLIANT** |

### Critical Finding: Persona-Layer Inversion

The code comments inside `runUniversalAcceptancePipeline` invert the Notion spec mapping:

```nim
# Stage 1: Detective (Layer 1 — topology + BMC prefilter)      ← WRONG: Detective should be Layer 2
# Stage 2: Legislator (Layer 2.5 — invariant drafting)         ← WRONG: Legislator should be Layer 3 (Scribe)
# Stage 3: Swat (Layer 2 — CEGAR abstraction + raid execution) ← WRONG: SWAT should be Layer 1 (Scout/BMC)
# Stage 4: Judge (Layer 3-4 — LLM formalization + Lean verification) ← OK: Judge is Layer 4
```

Neither SWAT nor Detective performs their Notion-spec role (BMC for SWAT, CEGAR for Detective).

---

## 4. 3대 최종 관문 (The 3 Final Gates) Compliance

### 1. 판별 (The Sieve) — Proven vs Unverifiable Classification

**Status: PARTIAL**

- `batch_uap_orchestrator.nim` classifies nodes **post-execution** into `orchestrationVerified` (`asiFixed4 == "1.0000"` or `smtTrack.solverStatus == "unsat"`), `orchestrationProofFailed`, and `orchestrationTimedOut`.
- **Gaps**:
  - No dedicated Sieve stage **before** UAP that analyzes AST properties (loops, recursion, non-linear arithmetic, side effects) to classify nodes into `Proven` / `Unverifiable` / `NeedsRefactoring` with structured predicates.
  - Layer 1 BMC and Layer 2 PDR fast paths are present in the type system but their implementations are stubs/templates that do not perform actual analysis on the input code.
  - No "Unverifiable" taxonomy: failed nodes are labeled with generic strings, not structured predicates explaining *why* (e.g., "contains non-linear arithmetic", "has unbounded recursion").

### 2. 진단 (The Diagnosis) — Mathematical Discontinuity Specification

**Status: PARTIAL**

- `judge.nim` implements `parseDiagnosticToDiscontinuities` which performs substring matching on Lean compiler output (`"non-linear" in lower`, `"recursion" in lower`).
- **Gaps**:
  - **Keyword-only diagnosis**: It does not analyze SMT models, extract unsat cores, or compute mathematical discontinuities from the proof obligation.
  - **Empty location data**: Every `MathematicalDiscontinuity` returned has `filePath: ""`, `lineNumber: 0`, and `smtUnsatCoreVars: @[]`. The spec requires *정밀 명세* (precise specification) of discontinuity points.
  - **No SMT unsat core analysis**: The `smtUnsatCoreVars` field is always empty. There is no logic to map Z3 unsat core variables back to source-level discontinuity locations.
  - **Detective doesn't diagnose**: `detective.investigate` produces a verdict and trace report but does not output `MathematicalDiscontinuity` objects.

### 3. 교정 (The Guidance) — f×g×h Rule Engine & Deterministic Patterns

**Status: PARTIAL**

- `refactoring_engine.nim` implements the f×g×h framework with `computeSynergyMetrics`, `classifySignals`, `generateTemplates`, and `RefactoringStagnation` (3 consecutive failures → human handoff).
- **Gaps**:
  - **Templates are never applied**: `generateTemplates` produces `RefactoringTemplate` objects with string descriptions and hints only. There is no code that applies these templates to the AST or source text.
  - **Healing orchestrator is a no-op**: `runSelfHealingLoop` and `runLeanProofRefinementLoop` explicitly set `changed = false` with the comment "Source integrity gate — do not patch source."
  - **No Z3 verification of refactorings**: The `RefactoringVerdict` enum exists, but there is no logic that applies a refactoring and then re-runs Z3 to verify equivalence.
  - **Stagnation logic unconnected**: `recordFailure` / `recordSuccess` exist, but no caller increments the stagnation counter or checks `escalated`.

---

## 5. 6대 천왕 기법 (6 Supreme Techniques) Compliance

| # | Technique | Status | Real or Stub? | Evidence |
|---|-----------|--------|---------------|----------|
| 1 | **CEGAR** (시행착오형 추상화) | **COMPLIANT** | Real (simplified) | `cegar_engine.nim:runCegarLoop` with interval abstraction, Z3 checks, fingerprint fixed-point |
| 2 | **고정점 기반 정적 분석** | **PARTIAL** | Real in CEGAR; Stub in PDR layer | `cegar_engine.nim` has real fixed-point; `layer2_pdr.nim` is hardcoded template; `fixedpoint_engine.nim` orphaned |
| 3 | **요약 기반 분석** (Modular) | **MISSING** | Stub/Cache only | `function_verification_summary.nim` is a pure cache table; `preConditions`/`postConditions` never populated |
| 4 | **SMT 기반 유도 증명** | **PARTIAL** | Real CHC engine; Stub PDR entry point | `fixedpoint_engine.nim` emits genuine CHC; `layer2_pdr.nim` discards input; not wired into UAP |
| 5 | **BMC** (유한 경로 탐색) | **COMPLIANT** | Real (simplified) | `bmc_generic.nim` has real `genericExplore`; wrapper is naive |
| 6 | **연역적 프로그램 검증** (Lean 4) | **COMPLIANT** | Real | `lean_replay.nim` spawns Lean 4 kernel with `#print axioms` anti-vacuity |

---

## 6. 자가 진화 루프 (Self-Evolution Loop) Compliance

### Notion Spec

```
[의도 입법] → [헌법 심판] → [취약점 추리] → [특공대 급습] → [반례 학습 및 법 개정]
```

### Implementation Analysis

**Status: PARTIAL**

- The pipeline stages corresponding to the 5 self-evolution phases exist and are wired in the correct order in `universal_pipeline.nim`:
  1. `detective.openCase` (취약점 추리)
  2. `legislator.legislate` (의도 입법)
  3. `swat.executeRaid` (특공대 급습)
  4. `judge.certify` (헌법 심판)
  5. `detective.investigate` (post-verdict analysis)

- `judge.certify` contains a **single closed-loop retry**:
  ```nim
  if not refined.leanKernelVerified:
    let cx = CounterExamplePayload(...)
    let feedbackRes = legislateWithFeedback(req, translation, initialScan, priorPromotion, sourceCode, cx)
    if feedbackRes.isOk:
      let retryRefined = unit.runLeanProofRefinement(...)
  ```

- `legislator_feedback.nim` implements `legislateWithFeedback`: builds a prompt with Lean diagnostic and SMT counterexample, calls `callLeanstral(prompt)` for LLM-based revision.

### Gaps

| Gap | Severity | Description |
|-----|----------|-------------|
| **Single retry, not a loop** | Critical | The "loop" performs **at most one** Legislator→Judge retry. If the retry fails, the function returns the original failed result. No `while` or `for` loop cycling until `leanKernelVerified == true`. |
| **No outer pipeline loop** | Critical | The 5-phase cycle runs **exactly once** per node. There is no mechanism to feed the Judge's final diagnostic back into Detective's `openCase` for a new iteration. |
| **No convergence criterion** | High | No termination condition based on proof success, invariant stability, or maximum iterations. |
| **Orphaned true loop** | High | `src/core/integrity_refinement_loop.nim` contains a genuine `while` loop with Z3 feedback and counterexample learning, but it is **hardcoded for Bitcoin Script** and not imported by `universal_pipeline.nim`. |
| **No automatic cycling** | High | The spec requires the loop to cycle *without human intervention until convergence*. The current implementation requires the entire `ax prove` command to be re-run externally. |

---

## 7. CLI Output Structure Compliance

**Status: PARTIAL**

- ASI 1.0000 is correctly reported in JSON output (`asiFixed4` field).
- The 3 gates (판별/진단/교정) exist in the type system and JSON payloads (`nearestDiscontinuities`, `structuredRemediation`), but the **human-readable CLI output** (`wf_render.nim`) does **not** surface the Korean gate names or present the report in the 3-gate format.
- `semantic_alias_mapper.nim` defines the canonical 3-gate schema, but it is not rendered in the CLI stdout path.

---

## 8. Critical Action Items

| Priority | Action | Owner Suggestion | Files |
|---|---|---|---|
| P0 | **Fix Persona-Layer Mapping** | Reorder stages in `universal_pipeline.nim` to match Notion spec: SWAT→Layer1(BMC), Detective→Layer2(CEGAR), Legislator→Layer3(Scribe/LLM), Judge→Layer4 | `src/verification/universal_pipeline.nim` |
| P0 | **Wire Real CEGAR into UAP** | Replace `runPdrSpacer` stub call with `runCegarLoop` or `runCegarAbstraction` from `cegar_engine.nim` | `src/verification/universal_pipeline.nim` |
| P0 | **Wire Real Fixed-Point Engine** | Replace stub PDR with `fixedpoint_engine.nim` CHC emission + Z3 Spacer solving | `src/verification/engine_variants/layer2_pdr.nim` |
| P0 | **Implement Real Sieve Stage** | Add AST-based pre-classification before UAP: analyze loops, recursion, non-linear arithmetic, side effects | `src/verification/batch_uap_orchestrator.nim` or new `src/personas/simp.nim` |
| P1 | **Enrich Diagnosis with SMT Unsat Cores** | Wire Z3 `:produce-unsat-cores` into `smtUnsatCoreVars`; map variables to source locations | `src/personas/judge.nim`, `src/core/remediation_types.nim` |
| P1 | **Make Healing Orchestrator Operational** | Remove `changed = false` no-ops; implement assertion injection and source patching guarded by Z3 equivalence checks | `src/verification/healing_orchestrator.nim` |
| P1 | **Close the Outer Evolution Loop** | Wrap `Detective → Legislator → Swat → Judge` in a `while` convergence loop with termination condition (`leanKernelVerified`, max iterations, stagnation detection) | `src/verification/universal_pipeline.nim` |
| P1 | **Generalize `integrity_refinement_loop.nim`** | Replace Bitcoin-Script-specific logic with domain-agnostic counterpart wired into UAP | `src/core/integrity_refinement_loop.nim` |
| P2 | **Implement Summary-Based Modular Analysis** | Populate `preConditions`/`postConditions` in `FunctionVerificationSummary`; use summaries at call sites for compositional verification | `src/core/function_verification_summary.nim` |
| P2 | **Surface 3 Gates in CLI Output** | Update `wf_render.nim` to present 판별/진단/교정 sections in human-readable stdout | `src/cli/wf_render.nim` |

---

## 9. Evidence Index

| Evidence ID | File | Line | Description |
|---|---|---|---|
| E001 | `src/verification/universal_pipeline.nim` | 31-262 | `runUniversalAcceptancePipeline` — inverted persona-layer mapping |
| E002 | `src/verification/engine_variants/layer1_bmc.nim` | 19-50 | `runLayer1Bmc` — string-based loop detection, hardcoded params |
| E003 | `src/core/bmc_generic.nim` | 176-218 | `genericExplore` — real BMC engine |
| E004 | `src/verification/cegar_engine.nim` | 150-259 | `runCegarLoop` — real CEGAR with fixed-point, Z3, intervals |
| E005 | `src/verification/engine_variants/layer2_pdr.nim` | 67-109 | `buildHornQuery` / `runPdrSpacer` — hardcoded template stub |
| E006 | `src/verification/cegar_bmc_bridge.nim` | 54-75 | `bridgeCegarToBmc` — orphaned, zero callers in `src/` |
| E007 | `src/personas/judge.nim` | 66-169 | `certify` — real Lean 4 replay + single closed-loop retry |
| E008 | `src/personas/detective.nim` | 30-55 | `openCase` — calls `runNegativeInvariantSearch`, not CEGAR |
| E009 | `src/personas/swat.nim` | 30-63 | `executeRaid` — calls `runNegativeInvariantSearch`, not BMC |
| E010 | `src/core/refactoring_engine.nim` | 49-162 | f×g×h framework — types complete, no source transformation |
| E011 | `src/verification/healing_orchestrator.nim` | 22-186 | `runSelfHealingLoop` — `changed = false` no-op |
| E012 | `src/core/function_verification_summary.nim` | — | Cache table only; `preConditions`/`postConditions` never populated |
| E013 | `src/cli/wf_render.nim` | 31-79 | `renderAxWorkflowReportLines` — no Korean 3-gate presentation |
| E014 | `src/core/integrity_refinement_loop.nim` | — | Real `while` loop with Z3 feedback, but Bitcoin-Script-specific and orphaned |

---

*Report generated by parallel subagent fleet (3 agents) + manual synthesis.*
*Methodology: Read-only codebase exploration via code-index MCP; no source modifications.*
