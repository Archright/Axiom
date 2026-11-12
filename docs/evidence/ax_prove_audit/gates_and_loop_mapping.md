# 3 Gates & Self-Evolution Loop Audit

**Audit Date**: 2026-06-03  
**Auditor**: Kimi Code CLI (direct investigation + subagent artifacts)  
**Scope**: `ax prove` 3 gates, self-evolution loop, persona order discrepancy  

---

## 1. Gate Mapping

### 1.1 The Sieve (판별) — Proven vs Unverifiable Classification

**Notion Spec Expectation**:
> "혼돈의 소프트웨어 바다에서 '검증 가능(Proven)'과 '검증 불가능(Unverifiable)'을 냉정하게 가려냅니다."

**Code Reality**:
- `axProofShortcutExitCode` (`src/cli/wf_runners.nim:24`) classifies **topology scan** results, not UAP proof results.
- It reads `verifiedCount`, `unverifiableCount`, `vacuousCount`, `timeoutCount` from a pre-computed JSON node.
- These counts come from `analyzeTopologySourceRoot`, which does NOT run `runUniversalAcceptancePipeline`.
- There is **no first-class Sieve stage** that filters nodes before UAP entry.

**Verdict**: ❌ **NOT IMPLEMENTED** as a pipeline gate.

---

### 1.2 Diagnosis (진단) — Precise Threat Specification

**Notion Spec Expectation**:
> "'검증 불가능' 판정을 받은 로직에 대해 엔진은 단순히 에러 로그만 뱉지 않습니다. '왜(Why)' 안 되는지, 어느 지점에서 수학적 불연속성이나 비결정적 위협이 발생하는지 그 근원적 파괴 경로를 정밀하게 짚어줍니다."

**Code Reality**:
- `src/core/diagnostics_engine.nim` implements:
  - `buildTimeoutDiagnosis` — analyzes SMTLIB2 complexity, quantifiers, non-linear arithmetic, loops, recursion
  - `buildStructuralDiagnosis` — analyzes coupling, logical depth, interface distance, child node count
- **Callers**:
  - `buildTimeoutDiagnosis` is called from `src/core/orchestrator_topology_worker.nim:34,70` (timeout fallback in orchestrator)
  - `buildStructuralDiagnosis` has **ZERO callers** in `src/`
- Neither is invoked by `runAxProveShortcutCli` or `runUniversalAcceptancePipeline`.

**Verdict**: ⚠️ **IMPLEMENTED BUT NOT WIRED TO CLI** — exists as a library but not surfaced to `ax prove` users.

---

### 1.3 Guidance (교정) — f×g×h Refactoring Patterns

**Notion Spec Expectation**:
> "검증 불가능한 혼돈의 로직을 검증 가능한 질서의 로직으로 리팩토링하는 경로를 완벽히 제시합니다. 비결정성을 숙청하고, 불변량을 명시하며, f × g × h 파이프라인 구조로 재배치하는 '무결성 설계 패턴'을 코드에 주입합니다."

**Code Reality**:
- `src/core/refactoring_engine.nim` implements:
  - 6 signal types (`RefactoringSignalKind`): quantifier excess, non-linear arithmetic, deep dependency, high coupling, missing loop invariant, missing decrease measure
  - 6 pattern templates (`RefactoringPatternKind`): extract pure function, linearize variables, insert composition node, isolate interface, add loop invariant, add decrease measure
  - `RefactoringStagnation` with `maxFailures = 3` and escalation to human handoff
- **Callers**:
  - `generateRefactoringTemplates` has **ZERO callers** in `src/`
  - `classifySignals` and `generateTemplates` are pure functions with no production consumers
- `src/cli/commands/heal.nim` implements `runAxHealCli` with full scheduling, Leanstral integration, and state applier.
- **Callers**: `runAxHealCli` is NOT invoked from `ax prove` dispatch chain.

**Verdict**: ⚠️ **IMPLEMENTED BUT NOT WIRED TO CLI** — the refactoring engine and heal subsystem exist but are unreachable from `ax prove`.

---

## 2. Self-Evolution Loop (자가 진화 루프)

### 2.1 Notion Spec

> 의도 입법 → 헌법 심판 → 취약점 추리 → 특공대 급습 → 반례 학습 및 법 개정

### 2.2 Code Reality

The only loop-like structure is inside `runUniversalAcceptancePipeline`:
1. `detective.openCase` — initial scan (Detective)
2. `legislator.legislate` — invariant drafting (Legislator)
3. `swat.executeRaid` — negative invariant confirmation (SWAT)
4. `callLeanstral` + `judge.certify` — LLM synthesis + Lean verification (Scribe + Judge)
5. `detective.investigate` — final verification (Detective)

**However**:
- There is **no feedback edge** from Judge or Detective back to Legislator.
- `runBatchUapOrchestrator` iterates over dependency depths with `maxRounds = 6`, but this is batch scheduling, not per-function evolutionary refinement.
- `refactoring_engine.nim` has stagnation detection (`maxFailures = 3`) that escalates to human handoff — an escape valve, not a learning loop.
- No evidence of "counterexample learning" or "law revision" automation exists outside the single-pass UAP flow.

**Verdict**: ⚠️ **PARTIAL** — the pipeline runs once per node. No closed-loop auto-refinement.

---

## 3. Persona Loop Order Discrepancy

### 3.1 Notion Order

Legislator → Judge → Detective → SWAT → Legislator

### 3.2 Actual Order

Detective → Legislator → SWAT → Scribe → Judge → Detective

### 3.3 Investigation

#### Git History
```bash
$ git log --oneline --all -- src/verification/universal_pipeline.nim | head -n 5
```
```
f27307a0 feat(prove): implement 4-layer proof pipeline architecture (Phase 0-8)
1c2e9aed fix: eliminate try/except — direct JSON construction and proper {.raises: [].}
46e58715 fix: resolve spec-binding gate errors and raises pragma violations
...
01cd261e Refactor universal pipeline into persona orchestrator
```

Commit `01cd261e` (2026-04-02) introduced the persona orchestrator refactor. Commit `f27307a0` (2026-06-01) added Leanstral→Judge wiring and claimed 4-layer architecture completion. **Neither commit mentions an intentional loop order change.**

#### Inline Comments
The only architectural comment in `universal_pipeline.nim` is:
```nim
# Phase 1 wiring: Leanstral -> Judge (Scribe -> Layer 4)
```

No rationale for placing Detective at both ends or SWAT before Judge.

#### Hypothesis: Performance Optimization?
A plausible but **unverified** hypothesis: SWAT's lightweight `runNegativeInvariantSearch` acts as a pre-filter before the expensive Lean 4 kernel verification in Judge. However, since SWAT does not invoke BMC (it only performs static AST scanning), this pre-filtering effect is minimal.

**Verdict**: ❌ **NO DOCUMENTED RATIONALE** — the order discrepancy appears to be organic, not intentional.

---

## 4. Summary

| Component | Status | Severity |
|---|---|---|
| The Sieve (판별) | ❌ Missing | Critical |
| Diagnosis (진단) | ⚠️ Unwired | Major |
| Guidance (교정) | ⚠️ Unwired | Major |
| Self-Evolution Loop | ⚠️ Single-pass only | Minor |
| Persona Loop Order | ❌ Undocumented deviation | Minor |
