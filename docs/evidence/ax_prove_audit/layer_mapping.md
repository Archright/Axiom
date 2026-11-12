# 4-Layer Pipeline Audit

**Audit Date**: 2026-06-03  
**Auditor**: forensic subagent  
**Scope**: `src/verification/universal_pipeline.nim`, `src/verification/pipeline_core_runner_parts/`, `src/verification/batch_uap_orchestrator.nim`

---

## Layer Mapping Table

| Notion Layer | Persona | Code Function | Calls Expected Technique? | Evidence |
|---|---|---|---|---|
| Layer 1 (Scout/BMC) | SWAT | `swat.executeRaid` | **NO** — does NOT call `bmc_generic.nim` or `bmc_race.nim`. Instead calls `runNegativeInvariantSearch` which performs static AST-based scans (`checkBufferOverflow`, `checkNullPointer`, `checkIntegerOverflow`, `checkGhostUpdate`, `checkDeadlockRace`). No true BMC or race-condition model checking is invoked. | `src/personas/swat.nim:30-60`; grep `bmc_generic\|bmc_race` in `src/personas/swat.nim` → no matches. |
| Layer 2 (Detective/CEGAR) | Detective | `detective.openCase` | **NO** — does NOT call `cegar_engine.nim`. Calls `runNegativeInvariantSearch` + `selectEvolutionHit` + `buildTraceReport`. | `src/personas/detective.nim:30-50`; grep `cegar_engine` in `src/personas/detective.nim` → no matches. |
| Layer 2 (Detective/CEGAR) | Detective | `detective.investigate` | **NO** — does NOT call `cegar_engine.nim`. Calls `runNegativeInvariantSearch` + `inferVerificationVerdict` + `buildVerificationVerdictReport`. | `src/personas/detective.nim:54-84`; grep `cegar_engine` in `src/personas/detective.nim` → no matches. |
| Layer 3 (Scribe/LLM) | Legislator | `legislator.legislate` | **N/A** — Notion spec places LLM synthesis in Scribe layer, but Legislator builds invariants via `buildRefinedInvariant` and `mergeInvariantClauses`. No LLM call here. | `src/personas/legislator.nim:34-68`. |
| Layer 3 (Scribe/LLM) | *(inline in pipeline)* | `callLeanstral` | **YES** — `callLeanstral` exists at `src/verification/leanstral_gateway.nim:198` and is invoked from `universal_pipeline.nim:62` with a Lean 4 theorem prompt. | `src/verification/leanstral_gateway.nim:198`; grep shows 3 call sites. |
| Layer 4 (Judge/Lean 4) | Judge | `judge.certify` | **PARTIAL** — DOES call `runLeanReplay` (line 41) for Leanstral pre-synthesis. Falls back to `runLeanProofRefinementLoop` which invokes `verifyGeneratedLeanSourceWithCompiler` with the Lean compiler. No direct Lean kernel invocation; it shells out to `lean` executable. | `src/personas/judge.nim:29-90`; grep `runLeanReplay` → line 41 match. |

### Key Finding: Technique Mismatch

The Notion spec expects:
- **Scout/BMC** → `bmc_generic.nim` / `bmc_race.nim`
- **Detective/CEGAR** → `cegar_engine.nim`

The actual implementation uses `runNegativeInvariantSearch` (AST pattern matching + heuristics) for **both** SWAT and Detective personas. Neither `bmc_generic` nor `cegar_engine` are referenced by any persona module. The `runNegativeInvariantSearch` procedure (`src/verification/pipeline_negative_scan_parts/pipeline_negative_scan_part3.nim:184`) performs:
1. `checkBufferOverflow` — AST assert-condition scanning
2. `checkNullPointer` — AST `ptr` identifier scanning
3. `checkIntegerOverflow` — IL token scanning for `add`/`sub`
4. `checkGhostUpdate` — version-transition heuristic
5. `checkDeadlockRace` — concurrency signal + `lock`/`atomic`/`gcsafe` pragma scanning

This is **static heuristic analysis**, not BMC or CEGAR abstraction refinement.

---

## Orphaned Code Analysis

### `runUniversalAcceptancePipelineCore`

**Location**: `src/verification/pipeline_core_runner_parts/pipeline_core_runner_part2.nim:32`

#### Caller Graph
```
runUniversalAcceptancePipelineCore
  ├─ called by: (NONE in src/ *.nim)
  └─ referenced by: 1 proof-vault JSON artifact
      └─ verification/proof_vault/..._runUniversalAcceptancePipelineCore_logic_integrity_...
```

#### Git History
```
f7c968c7 fix(DEBT#105): fix moveFileOpt bugs and unused imports
515bd513 refactor(io): mass migrate ALL I/O calls to safe wrappers (120 changes)
46e58715 fix: resolve spec-binding gate errors and raises pragma violations
1ccc1348 refactor: 100% raises compliance including _parts/ sub-modules
0127f757 refactor: 100% {.push raises: [Exception].} compliance
```

All commits are **refactoring/maintenance** — no functional consumer was ever added after the split.

#### Structural Comparison

| Aspect | `runUniversalAcceptancePipeline` (active) | `runUniversalAcceptancePipelineCore` (orphaned) |
|---|---|---|
| Persona wrappers | Yes (detective, legislator, swat, judge) | No — monolithic inline logic |
| Leanstral Phase-1 wiring | Yes (`callLeanstral` + `runLeanReplay`) | No — only `runLeanProofRefinementLoop` |
| Source checksum sync | Yes (`syncRecoveredSourceToModule`) | Yes |
| BDD feature writing | Yes (`writeBddFeature` via swat) | Yes |
| Proof artifact writing | Yes | Yes |
| Promotion snapshot | Yes | Yes |
| Import in `universal_pipeline.nim` | Yes | **No** — not imported anywhere |

#### Verdict

**ORPHANED LEGACY IMPLEMENTATION**.

`runUniversalAcceptancePipelineCore` is a **pre-persona monolithic pipeline** that was likely split out during the `_parts/` modularization (commit `0127f757`) but never deleted. It duplicates the active pipeline's logic without the persona abstraction layer and without the Leanstral→Judge Phase 1 wiring. It has **zero compile-time consumers** and is only referenced by a proof-vault integrity theorem JSON, suggesting it was once part of the verification target set but has since been abandoned.

**Recommendation**: Mark for deletion under DEBT registry or re-integrate if a non-persona fast-path is desired. Currently it is dead code.

---

## Budget/Gas Behavior

### `runBatchUapOrchestration` (`src/verification/batch_uap_orchestrator.nim`)

#### Budget Lifecycle

1. **Initialization** (line 69)
   ```nim
   var budget = initProofBudget()
   ```
   Creates a fresh `ProofBudget` at the start of every orchestration run.

2. **Pre-flight Check** (line 103)
   ```nim
   let budgetVerdict = checkBudget(budget)
   if budgetVerdict != pbvContinue:
     report.nodeReports.add(OrchestrationNodeReport(
       nodeId: item.nodeId,
       status: orchestrationTimedOut,
       evidenceLogJson: "budget exhausted: " & $budgetVerdict
     ))
     depthFailed = true
     break
   ```
   Before each node, the budget is checked. If exhausted, the node is marked `orchestrationTimedOut` and depth processing stops.

3. **Gas Consumption** (line 135)
   ```nim
   discard consumeGas(budget)
   ```
   One gas unit is consumed **per node** immediately before UAP execution.

#### Wall-Clock Timeout

```nim
const
  nodeTimeoutMs* = 120_000  ## 2 min per-node wall-clock timeout
```

Used at line 147:
```nim
let nodeElapsedMs = (getMonoTime().ticks - nodeStartMono) div 1_000_000
if nodeElapsedMs > nodeTimeoutMs:
  report.nodeReports.add(OrchestrationNodeReport(
    nodeId: item.nodeId,
    status: orchestrationTimedOut,
    evidenceLogJson: "node timeout: " & $nodeElapsedMs & "ms > " & $nodeTimeoutMs & "ms"
  ))
  continue
```

**Behavior**: The timeout is measured **after** `runUniversalAcceptancePipeline` returns, not as a hard interrupt. If the pipeline hangs internally, the timeout will not trigger until control returns to the orchestrator. This is a **post-hoc deadline check**, not a preemptive kill.

#### Budget/Gas Verification Checklist

| Check | Line | Status |
|---|---|---|
| `initProofBudget` called | 69 | ✅ |
| `checkBudget` called before node execution | 103 | ✅ |
| `consumeGas` called per node | 135 | ✅ |
| `nodeTimeoutMs = 120_000` declared | 20 | ✅ |
| Timeout enforced post-return | 147 | ✅ (with caveat above) |

---

## Summary

| Finding | Severity | Description |
|---|---|---|
| BMC/CEGAR technique gap | **Architectural drift** | Notion spec expects `bmc_generic`/`cegar_engine`; actual code uses static heuristic `runNegativeInvariantSearch`. |
| Orphaned `runUniversalAcceptancePipelineCore` | **Dead code** | Zero callers, pre-persona monolithic duplicate. Should be quarantined or deleted. |
| Leanstral wiring | **Present** | `callLeanstral` + `runLeanReplay` correctly wired in both `universal_pipeline.nim` and `judge.certify`. |
| Budget/gas system | **Operational** | `initProofBudget` → `checkBudget` → `consumeGas` chain is intact. Timeout is post-hoc, not preemptive. |
