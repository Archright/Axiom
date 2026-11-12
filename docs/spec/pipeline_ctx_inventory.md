# Pipeline Context Inventory — State Dependency Matrix

**Purpose:** Exhaustive mapping of all `ctx` (PipelineContext) field accesses in
`src/verification/universal_pipeline.nim` (640 lines) to guide defunctionalization.

**Method:** `grep -on "ctx\.[a-zA-Z_][a-zA-Z0-9_]*"` sorted by frequency.

**Date:** 2026-06-10
**Commit:** 53a94729

---

## Field Frequency Summary

| Field | Access Count | Read/Write | Classification |
|-------|-------------|------------|----------------|
| `ctx.judgeArt` | 32 | R | Persona artifact (Judge dispatch) |
| `ctx.loopReq` | 24 | R/W | Mutable per-iteration request |
| `ctx.req` | 15 | R | Original input request |
| `ctx.detected` | 14 | R/W | Stage output (DetectedState) |
| `ctx.caseArt` | 14 | R | Persona artifact (Detective dispatch) |
| `ctx.error` | 13 | R/W | Terminal error state |
| `ctx.swatArt` | 9 | R | Persona artifact (SWAT dispatch) |
| `ctx.result` | 9 | R/W | Terminal success result |
| `ctx.guardExitMessage` | 7 | W | Guard/logging only |
| `ctx.currentSource` | 7 | R/W | Iteration-scoped source code |
| `ctx.guardTerminalStatus` | 6 | W | Guard/logging only |
| `ctx.guardStageHistory` | 6 | W | Guard/logging only |
| `ctx.guardCurrentStage` | 6 | W | Guard/logging only |
| `ctx.stagnation` | 5 | R/W | Loop control (stagnation detection) |
| `ctx.kInductionLeanVerified` | 5 | R/W | K-induction state |
| `ctx.iteration` | 5 | R/W | Loop counter |
| `ctx.draftArt` | 5 | R | Persona artifact (Legislator dispatch) |
| `ctx.leanstralLeanSource` | 4 | R/W | Scribe/Judge shared Lean source |
| `ctx.currentInvariant` | 4 | R/W | Iteration-scoped invariant |
| `ctx.scribeArt` | 3 | R | Persona artifact (Scribe dispatch) |
| `ctx.kInductionLeanScript` | 3 | R/W | K-induction state |
| `ctx.guardNodeId` | 3 | R | Guard/logging only |
| `ctx.globalRegistry` | 3 | R/W | Invariant registry |
| `ctx.bmcProven` | 3 | R/W | Scout stage internal flag |
| `ctx.visitedStates` | 2 | R/W | Loop control (fingerprinting) |
| `ctx.kInductionProved` | 2 | R/W | K-induction state |
| `ctx.guardStartTime` | 2 | R | Guard/logging only |
| `ctx.goalDeltas` | 2 | R | Legislator/Judge shared state |
| `ctx.useFeedback` | 1 | W | Legislator stage flag |
| `ctx.translation` | 1 | W | Translation result (set once) |
| `ctx.priorPromotion` | 1 | W | Prior promotion (set once) |
| `ctx.maxIterations` | 1 | R | Loop bound |
| `ctx.detArt` | 1 | R | Likely typo for `detected` |

---

## State Dependency Matrix

### Matrix Legend
- **Source:** Where the field is populated
- **Consumer:** Which stage/function reads it
- **New Target:** Where it moves in the defunctionalized design
- **Type:** `Config` (read-only), `State` (stage input/output), `Artifact` (dispatch result), `Guard` (logging only)

| # | Current ctx Field | Source | Consumer(s) | New Target (Defunctionalized) | Type |
|---|-------------------|--------|-------------|------------------------------|------|
| 1 | `ctx.req` | External input | Scout, Detective, Legislator, Scribe, Judge, PostProcess | `PipelineConfig.req` | Config |
| 2 | `ctx.translation` | Translation setup (line 101) | Detective, Legislator, Scribe, Judge | `PipelineConfig.translation` | Config |
| 3 | `ctx.maxIterations` | External input | Loop condition (line 116) | `PipelineConfig.maxIterations` | Config |
| 4 | `ctx.priorPromotion` | Proof vault load (line 108) | Detective (line 259) | `PipelineConfig.priorPromotion` | Config |
| 5 | `ctx.guardNodeId` | External input | Logging (lines 160, 584, 606) | `PipelineConfig.guardNodeId` | Config |
| 6 | `ctx.guardStartTime` | External input | Logging (lines 585, 603) | `PipelineConfig.guardStartTime` | Config |
| 7 | `ctx.loopReq` | Derived from `req` + `currentSource` (line 117) | SWAT, Detective, K-induction, CEGAR bridge | Stage input parameter | State |
| 8 | `ctx.currentSource` | `req.sourceCode` initially, then `swatArt.healedSource` (line 117) | SWAT, Detective, K-induction, Legislator, Scribe | `DetectedState.currentSource` → `LegislatedState.currentSource` | State |
| 9 | `ctx.currentInvariant` | `priorPromotion.invariant` initially (line 111) | Legislator, Scribe, Judge | `LegislatedState.currentInvariant` | State |
| 10 | `ctx.iteration` | Incremented each loop (line 380, 398) | Loop condition, Legislator, Judge, logging | Orchestrator `var iteration` | State |
| 11 | `ctx.bmcProven` | Set by Scout (line 126-129) | Loop fast-path (line 131) | `ScoutStageResult.bmcProven` | State |
| 12 | `ctx.swatArt` | SWAT dispatch (line 127) | Scout (logLines, healedSource), Detective, Judge | `DispatchResult(dtSwat).swatArt` | Artifact |
| 13 | `ctx.caseArt` | Detective dispatch (line 371) | Detective (cegarCounterexample, unsatCoreVars, initialScan, traceReport, evolutionHit, priorPromotion), Legislator (goalDeltas), Judge | `DispatchResult(dtDetective).caseArt` | Artifact |
| 14 | `ctx.detected` | Built from `caseArt` (line 259-268) | Legislator, Scribe, Judge, PostProcess | `DetectedState` (explicit type) | State |
| 15 | `ctx.useFeedback` | Derived from `detected.cxHistory` (line 275) | Legislator dispatch routing | `LegislatedState.useFeedback` | State |
| 16 | `ctx.draftArt` | Legislator dispatch (line 281) | Legislator (activeInvariant, baselineInvariant), Scribe, Judge, PostProcess | `DispatchResult(dtLegislator).draftArt` | Artifact |
| 17 | `ctx.globalRegistry` | Initialized empty, mutated by Legislator (line 283) | Legislator (upsertInvariant) | `LegislatedState.globalRegistry` | State |
| 18 | `ctx.goalDeltas` | Derived from `detected` (line 268) | Legislator (line 331), Judge (line 615) | `DetectedState.goalDeltas` | State |
| 19 | `ctx.scribeArt` | Scribe dispatch (line 293) | Scribe (verified, theoremSource) | `DispatchResult(dtScribe).scribeArt` | Artifact |
| 20 | `ctx.leanstralLeanSource` | Set from `scribeArt` (line 294) or K-induction (line 299) | Judge (line 550) | `ScribedState.leanstralLeanSource` | State |
| 21 | `ctx.kInductionProved` | Set by K-induction path (line 190) | Loop path selection (line 297) | `DetectedState.kInductionProved` | State |
| 22 | `ctx.kInductionLeanVerified` | Set by K-induction verification (line 204) | Loop path selection (line 297) | `DetectedState.kInductionLeanVerified` | State |
| 23 | `ctx.kInductionLeanScript` | Set by K-induction (line 206) | Scribe fallback (line 298) | `DetectedState.kInductionLeanScript` | State |
| 24 | `ctx.judgeArt` | Judge dispatch (line 542) | Judge (finalInvariant, finalSource, nearestDiagnostic, failedReplayAttempts), PostProcess, loop termination | `DispatchResult(dtJudge).judgeArt` | Artifact |
| 25 | `ctx.stagnation` | Mutated throughout loop (lines 311, 338, 347, 379, 383) | Loop termination, Judge (escalation) | `PipelineOrchestratorState.stagnation` | State |
| 26 | `ctx.visitedStates` | Mutated in loop (lines 352, 354) | Fingerprint deduplication | `PipelineOrchestratorState.visitedStates` | State |
| 27 | `ctx.result` | Set on success (lines 132, 218, 486) | Orchestrator return (line 563) | `Transition.tkTerminal.finalResult` | Terminal |
| 28 | `ctx.error` | Set on failure (lines 76, 85, 121, 154, etc.) | Orchestrator return (line 613) | `Transition.tkTerminal.error` | Terminal |
| 29 | `ctx.guardCurrentStage` | Written at each stage boundary | Logging only | `GuardState.currentStage` | Guard |
| 30 | `ctx.guardStageHistory` | Written at each stage boundary | Logging only | `GuardState.stageHistory` | Guard |
| 31 | `ctx.guardTerminalStatus` | Written on terminal (lines 78, 87, 145, 252) | Logging only | `GuardState.terminalStatus` | Guard |
| 32 | `ctx.guardExitMessage` | Written on terminal (lines 77, 86, 146, 253) | Logging only | `GuardState.exitMessage` | Guard |

---

## Classification Summary

| Category | Fields | Count |
|----------|--------|-------|
| **Config** (read-only, set at start) | req, translation, maxIterations, priorPromotion, guardNodeId, guardStartTime | 6 |
| **State** (stage input/output, flows through type chain) | loopReq, currentSource, currentInvariant, iteration, detected, useFeedback, globalRegistry, goalDeltas, leanstralLeanSource, kInductionProved, kInductionLeanVerified, kInductionLeanScript, stagnation, visitedStates, bmcProven | 15 |
| **Artifact** (dispatch results, tagged union variants) | swatArt, caseArt, draftArt, scribeArt, judgeArt | 5 |
| **Terminal** (success/failure, Transition variant) | result, error | 2 |
| **Guard** (logging only, no business logic) | guardCurrentStage, guardStageHistory, guardTerminalStatus, guardExitMessage | 4 |
| **Unknown/Typo** | detArt | 1 |

**Total distinct fields:** 33

---

## Key Findings

### 1. `ctx.judgeArt` is the heaviest dependency (32 reads)
Judge artifacts are read by: PostProcess, loop termination logic, stagnation handling, and final result assembly. This confirms `DispatchResult(dtJudge)` needs rich sub-fields.

### 2. `ctx.loopReq` (24 R/W) is iteration-scoped request state
Not truly read-only because `sourceCode` is mutated each iteration (`ctx.loopReq.sourceCode = ctx.currentSource`). This is a **derived input** that should be computed by the orchestrator and passed as a parameter, not stored in mutable context.

### 3. Guard fields (4 fields, 25 writes) are pure logging
`guardCurrentStage`, `guardStageHistory`, `guardTerminalStatus`, `guardExitMessage` have zero impact on business logic. They should be extracted to a `GuardState` object and handled by a logging wrapper, not the core pipeline logic.

### 4. K-induction state (3 fields) is a side-channel
`kInductionProved`, `kInductionLeanVerified`, `kInductionLeanScript` are set in a K-induction fast-path and read later by Scribe/Judge. This is effectively an **alternative source** for `leanstralLeanSource`. The type model should make this explicit: `LeanSourceOrigin = loScribe | loKInduction`.

### 5. `ctx.stagnation` + `ctx.visitedStates` are loop-control state
These belong in the orchestrator's `var` state, not in any stage function.

### 6. `ctx.detArt` (line 426) is likely a typo
Appears once at line 426. Should be `ctx.detected` or `ctx.caseArt`. Needs verification.

---

## Defunctionalization Migration Order

Based on dependency graph analysis, the safest extraction order is:

1. **Guard fields** (zero business logic dependency) → `GuardState`
2. **Terminal fields** (result, error) → `Transition[T]`
3. **Config fields** (read-only inputs) → `PipelineConfig`
4. **Artifact fields** (dispatch outputs) → `DispatchResult`
5. **State fields** (type-chain flow) → `DetectedState`, `LegislatedState`, etc.
6. **Loop-control fields** (stagnation, visitedStates) → Orchestrator `var`

This order ensures each extraction has minimal downstream impact.
