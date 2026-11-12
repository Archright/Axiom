# 6 Supreme Techniques Audit — Raw Evidence

> Audit date: 2026-06-03  
> Method: targeted `grep` + `sed` excerpts on `src/` tree. ReadFile NOT used on `.nim` per project policy.

---

## Task 1: CEGAR

### 1.1 `runCegarLoop` call sites

```
$ grep -rn "runCegarLoop\|bridgeCegarToBmc" src/
src/core/orchestrator_topology_worker.nim:82:## Calls runCegarLoop from cegar_engine for real fixed-point convergence.
src/core/orchestrator_topology_worker.nim:92:  let cegarResult = runCegarLoop(cfg, headerId, z3Check, budgetMs = remainingMs)
src/verification/cegar_bmc_bridge.nim:54:proc bridgeCegarToBmc*(
src/verification/cegar_engine.nim:148:proc runCegarLoop*(
```

**Determination:** `runCegarLoop` is called exactly once in production code, from `orchestrator_topology_worker.nim:92` inside `applyCegarAbstraction`.

### 1.2 `bridgeCegarToBmc` call sites

```
$ grep -rn "bridgeCegarToBmc\|cegar_bmc_bridge" src/ | grep -v "src/verification/cegar_bmc_bridge.nim"
<no output>
```

**Determination:** `bridgeCegarToBmc` is defined in `cegar_bmc_bridge.nim:54` but has **zero callers** in `src/`.

### 1.3 `applyCegarAbstraction` caller

```
$ grep -rn "applyCegarAbstraction" src/
src/core/orchestrator_parts/orchestrator_part1.nim:84:          let abstraction = applyCegarAbstraction(...)
```

---

## Task 2: BMC

### 2.1 `bmc_generic.nim` call graph

```
$ grep -rn "bmc_generic\|verifyGenericProperty\|verifyIntegerOverflow\|verifyIndexBounds\|verifyNullDereference" src/
src/core/bmc_generic.nim:209:func verifyGenericProperty*(
src/core/bmc_generic.nim:219:func verifyIntegerOverflow*(
src/core/bmc_generic.nim:225:  verifyGenericProperty(config, @[initialValue], delta)
src/core/bmc_generic.nim:228:func verifyIndexBounds*(
src/core/bmc_generic.nim:233:  verifyGenericProperty(config, @[indexValue], 0)
src/core/bmc_generic.nim:236:func verifyNullDereference*(
src/core/bmc_generic.nim:240:  verifyGenericProperty(config, @[pointerValue], 0)
src/verification/cegar_bmc_bridge.nim:12:import core/bmc_generic
src/verification/cegar_bmc_bridge.nim:13:export bmc_generic
src/verification/cegar_bmc_bridge.nim:70:  result.bmcVerdict = verifyGenericProperty(config, effectiveValues, delta)
```

**Determination:** `verifyGenericProperty` is called only from:
- within `bmc_generic.nim` itself (lines 225, 233, 240)
- `cegar_bmc_bridge.nim:70` (dead code — `bridgeCegarToBmc` has no callers)

### 2.2 `bmc_race.nim` call graph

```
$ grep -rn "bmc_race\." src/core/axiom_api_parts/axiom_api_part2.nim
src/core/axiom_api_parts/axiom_api_part2.nim:37:  let verdict = bmc_race.verifyRaceConditionWithDelta(gated[0], gated[1])
src/core/axiom_api_parts/axiom_api_part2.nim:53:  let verdict = bmc_race.verifyRaceCondition(stateValue, rule)
```

`bmc_race.nim` is also imported by:
- `src/core/solver_bridge.nim`
- `src/core/axiom_api_session.nim`
- `src/core/axiom_api.nim`
- `src/core/expression_parser.nim`
- `src/core/session_parser.nim`

---

## Task 3: SMT-based inductive proof

### 3.1 `solver_bridge.nim` importers

```
$ grep -rn "import.*solver_bridge\|from.*solver_bridge" src/verification/ src/core/ src/cli/ src/personas/
src/verification/pipeline_negative_scan.nim:11:import core/solver_bridge
src/core/axiom_api_session.nim:12:import core/solver_bridge
src/core/axiom_api.nim:10:import core/solver_bridge
src/cli/commands/heal_node_executor.nim:10:import core/solver_bridge
```

### 3.2 Actual SMT solver invocation in pipeline

```
$ grep -rn "solver_bridge\.\|z3ExecPersistent\|z3Spawn\|buildTransitionPayload\|buildKInductionPayload\|parseZ3StdoutAsResult\|dumpEvidence" src/verification/pipeline_negative_scan.nim src/verification/pipeline_negative_scan_parts/
src/verification/pipeline_negative_scan_parts/pipeline_negative_scan_part2.nim:282:    let parsed = parseZ3StdoutAsResult(solverStdout, translation.smt2, violatedProperty)
```

**Determination:** SMT solver is invoked inside `pipeline_negative_scan` (part of Detective's `runNegativeInvariantSearch`). `parseZ3StdoutAsResult` is the concrete bridge call at line 282.

### 3.3 Pipeline entry points

```
$ grep -rn "runUniversalAcceptancePipeline\|runBatchUapOrchestrator" src/
src/cli/integrity_cli.nim:212:proc runUniversalAcceptancePipelineCliJson*
src/verification/universal_pipeline.nim:25:proc runUniversalAcceptancePipeline*
src/verification/batch_uap_orchestrator.nim:145:      let uapResult = runUniversalAcceptancePipeline(uapReqRes.get())
```

---

## Task 4: Fixed-point static analysis

### 4.1 "fixed-point" / "fixpoint" occurrences

```
$ grep -rin "fixed.point\|fixpoint\|fix.point" src/verification/ src/core/
src/verification/cegar_engine.nim:4:## with a real fixed-point convergence loop.
src/verification/cegar_engine.nim:16:    cegarProven          ## Fixed-point reached, all invariants verified
src/verification/cegar_engine.nim:93:  parts.add("; AXIOM CEGAR: Proved loop invariants (fixed-point)")
src/verification/cegar_engine.nim:155:  ## Fixed-point convergence loop for loop invariant synthesis.
src/verification/cegar_engine.nim:163:  ##   6. If fingerprint unchanged from previous iteration → fixed-point (cegarProven)
src/verification/cegar_engine.nim:166:  ## Terminates on: fixed-point, max iterations, or time budget exceeded.
src/verification/cegar_engine.nim:212:    # Compute fingerprint for fixed-point detection
src/verification/cegar_engine.nim:225:    # Fixed-point reached — all discoverable invariants have been proved
src/core/orchestrator_topology_worker.nim:82:## Calls runCegarLoop from cegar_engine for real fixed-point convergence.
src/core/integrity_refinement_loop.nim:454:        "prove/fixed-point"
src/core/orchestrator_parts/orchestrator_part1.nim:67:      # CEGAR: build CFG from source and attempt fixed-point convergence
```

### 4.2 `fixedpoint_engine.nim` usage

```
$ grep -rn "fixedpoint_engine\|FixedpointEngine\|runFixedpoint\|solveChc" src/
<no output in src/ source files>
```

`src/core/solver/fixedpoint_engine.nim` exists (contains CHC → Z3 fixedpoint engine code) but has **zero callers** in `src/`.

### 4.3 `runCegarLoop` fixed-point excerpt

```nim
# src/verification/cegar_engine.nim:148-230 (excerpt)
proc runCegarLoop*(...): CegarResult =
  ## Fixed-point convergence loop for loop invariant synthesis.
  ##   6. If fingerprint unchanged from previous iteration → fixed-point (cegarProven)
  var prevFingerprint: uint64 = 0
  ...
  while iteration < maxIterations:
    ...
    let newFingerprint = computeInvariantFingerprint(provedInvariants)
    let fixedPoint = (newFingerprint == prevFingerprint) and iteration > 0
    ...
    if fixedPoint:
      return CegarResult(verdict: cegarProven, ...)
    prevFingerprint = newFingerprint
    ...
```

---

## Task 5: Summary-based modular analysis

### 5.1 "summary" / "modular" in expected modules

```
$ grep -rn "summary\|modular" src/personas/detective.nim src/verification/universal_pipeline.nim
src/verification/universal_pipeline.nim:206:    discard writeStderrLine("Failed to write proof summary to " & resultObj.proofSummaryPath)
```

The only "summary" match is the **output file path** `proofSummaryPath` in `universal_pipeline.nim:206` — not a technique.

### 5.2 `detective.nim` functions

```
$ sed -n '1,120p' src/personas/detective.nim
# Key exports:
func detectiveLogLine(...)
proc openCase*(...)
proc investigate*(...)
```

`openCase` calls `loadPromotionFromProofVault`, `runNegativeInvariantSearch`, `selectEvolutionHit`, `buildTraceReport`. No modular decomposition or function summarization.

---

## Task 6: Deductive program verification (Lean 4)

### 6.1 `runLeanReplay` call sites

```
$ grep -rn "runLeanReplay\|leanstral_gateway\|leanReplayResult" src/
src/personas/judge.nim:41:      let leanReplayResult = runLeanReplay(req.functionName, preSynthesizedLeanSource)
src/personas/judge.nim:42:      if leanReplayResult.isOk and leanReplayResult.get().isValid:
src/verification/universal_pipeline.nim:20:import leanstral_gateway
src/verification/universal_pipeline.nim:64:        let replayResult = runLeanReplay(req.functionName, lsResult.theoremSource)
src/core/provider_interface.nim:124:  let res = runLeanReplay("provider_node", source)
src/core/solver/wrappers.nim:33:  let res = runLeanReplay("node_auto", query)
src/core/the_judge_eval.nim:36:proc runLeanReplay*(nodeId: string; leanQuery: string): Result[...]
src/core/the_judge_eval.nim:105:  let leanResult = runLeanReplay(nodeId, leanQuery)
src/core/lean_replay.nim:49:proc runLeanReplay*(nodeId: string; leanSource: string): Result[LeanReplayResult, string]
src/verification/cli_bridge.nim:50:import leanstral_gateway
src/verification/cli_bridge.nim:51:export leanstral_gateway
src/verification/proof_synthesis_engine.nim:18:import verification/leanstral_gateway
```

### 6.2 `judge.certify` Lean excerpt

```nim
# src/personas/judge.nim:29-55 (excerpt)
proc certify*(...):
  if preSynthesizedLeanSource.len > 0:
    let leanReplayResult = runLeanReplay(req.functionName, preSynthesizedLeanSource)
    if leanReplayResult.isOk and leanReplayResult.get().isValid:
      let inferred = inferLeanSpec(...)
      return ok(JudgeArtifact(..., proofReplayMethod: "leanstral", ...))
```

### 6.3 `universal_pipeline.nim` Leanstral wiring

```nim
# src/verification/universal_pipeline.nim:20-72 (excerpt)
import leanstral_gateway
import ../core/lean_replay

proc runUniversalAcceptancePipeline*(...):
  ...
  # Phase 1 wiring: Leanstral -> Judge (Scribe -> Layer 4)
  block leanstralAttempt:
    let lsResult = callLeanstral(leanPrompt)
    if lsResult.success and lsResult.theoremSource.len > 0:
      let replayResult = runLeanReplay(req.functionName, lsResult.theoremSource)
      if replayResult.isOk and replayResult.get().isValid:
        leanstralLeanSource = lsResult.theoremSource
  ...
  let judgeResult = ??judge.certify(..., preSynthesizedLeanSource = leanstralLeanSource)
```

---

## End of Evidence File
