# 4-Layer Pipeline Forensic Audit — Verification Artifacts

**Date**: 2026-06-03
**Auditor**: subagent forensic code audit
**Scope**: `runUniversalAcceptancePipeline`, `runUniversalAcceptancePipelineCore`, `runBatchUapOrchestration`

---

## §1. Shell Commands & Grep Outputs

### 1.1 Persona pipeline cross-module grep

```bash
$ grep -n "bmc_generic\|bmc_race" src/personas/swat.nim
# (no output)

$ grep -n "cegar_engine" src/personas/detective.nim
# (no output)

$ grep -n "runLeanReplay" src/personas/judge.nim
41:      let leanReplayResult = runLeanReplay(req.functionName, preSynthesizedLeanSource)

$ grep -rn "callLeanstral" src/
verification/leanstral_gateway.nim:198:proc callLeanstral*(prompt: string; timeoutMs: int = leanstralTimeoutMs; backend: LLMBackend = nil): LeanstralResult {.raises: [].} =
verification/proof_synthesis_engine_parts/proof_synthesis_engine_part2.nim:13:  let leanstralRes = callLeanstral(prompt, timeoutMs = timeoutMs)
verification/proof_synthesis_engine_parts/proof_synthesis_engine_part1.nim:120:    let leanstralRes = callLeanstral(prompt, timeoutMs = config.timeoutMs)
verification/universal_pipeline.nim:62:      let lsResult = callLeanstral(leanPrompt)
```

### 1.2 `runUniversalAcceptancePipelineCore` caller search

```bash
$ grep -rn "runUniversalAcceptancePipelineCore" src/
verification/pipeline_core_runner_parts/pipeline_core_runner_part2.nim:32:proc runUniversalAcceptancePipelineCore*(
verification/proof_vault/src_verification_universal_pipeline_core_runUniversalAcceptancePipelineCore_logic_integrity_n9091683660248304457.json:2:  "theorem": "src_verification_universal_pipeline_core_runUniversalAcceptancePipelineCore_logic_integrity",
```

**Result**: ZERO `.nim` call-sites outside its own definition. Only a proof-vault JSON artifact references it.

### 1.3 Git history for `pipeline_core_runner_parts/`

```bash
$ git log --oneline -- src/verification/pipeline_core_runner_parts/
f7c968c7 fix(DEBT#105): fix moveFileOpt bugs and unused imports
515bd513 refactor(io): mass migrate ALL I/O calls to safe wrappers (120 changes)
46e58715 fix: resolve spec-binding gate errors and raises pragma violations
1ccc1348 refactor: 100% raises compliance including _parts/ sub-modules
0127f757 refactor: 100% {.push raises: [Exception].} compliance
```

---

## §2. Symbol Body Excerpts

### 2.1 `runUniversalAcceptancePipeline` (src/verification/universal_pipeline.nim:25)

```nim
proc runUniversalAcceptancePipeline*(
  req: UniversalPipelineRequest
): Result[UniversalPipelineResult, AxiomError] {.raises: [].} =
  if req.astJson.strip().len == 0 or req.sourceCode.strip().len == 0:
    return err(axiomErrEmptyString)

  let translation = ??mapAstJsonToUniversalTranslation(req.language, req.astJson)

  let caseResult = ??detective.openCase(req, translation)
  ...
  let draftResult = ??legislator.legislate(req, translation, initialScan, priorPromotion, req.sourceCode)
  ...
  let raidResult = ??swat.executeRaid(req, translation, initialScan, priorPromotion.invariant, evolutionHit, caseResult.traceReport)
  ...
  block leanstralAttempt:
    try:
      let leanPrompt = "Prove the following Lean 4 theorem for function " & req.functionName & ...
      let lsResult = callLeanstral(leanPrompt)
      if lsResult.success and lsResult.theoremSource.len > 0:
        let replayResult = runLeanReplay(req.functionName, lsResult.theoremSource)
        ...
  let judgeResult = ??judge.certify(req, translation, raidResult.healedSource, seededInvariant, "proven_by_induction", req.maxRounds, preSynthesizedLeanSource = leanstralLeanSource)
  ...
  let detectiveResult = ??detective.investigate(req, translation, priorPromotion, initialScan, judgeResult.finalSource, activeInvariant, judgeResult.nearestDiagnostic, judgeResult.failedReplayAttempts)
```

### 2.2 `detective.openCase` (src/personas/detective.nim:30)

```nim
proc openCase*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation
): Result[DetectiveArtifact, AxiomError] {.raises: [].} =
  try:
    let priorPromotion = loadPromotionFromProofVault(req)
    let initialScan = runNegativeInvariantSearch(translation, req.sourceCode, priorPromotion.invariant)
    let evolutionHit = selectEvolutionHit(initialScan)
    let traceReport = buildTraceReport(evolutionHit)
    ok(DetectiveArtifact(...))
```

### 2.3 `detective.investigate` (src/personas/detective.nim:54)

```nim
proc investigate*(...): Result[DetectiveArtifact, AxiomError] {.raises: [].} =
  try:
    let finalScan = runNegativeInvariantSearch(translation, finalSource, activeInvariant)
    let evolutionHit = selectEvolutionHit(initialScan)
    let verificationVerdict = inferVerificationVerdict(finalScan)
    let traceReport = buildTraceReport(evolutionHit)
    let verdictReport = buildVerificationVerdictReport(...)
```

### 2.4 `legislator.legislate` (src/personas/legislator.nim:34)

```nim
proc legislate*(...): Result[LegislatorArtifact, AxiomError] {.raises: [].} =
  try:
    let evolutionHit = selectEvolutionHit(initialScan)
    let baselineInvariant = if evolutionHit.isSome(): buildRefinedInvariant(...) else: ""
    ...
    let asiFixed4 = computeAsiFixed4(runNegativeInvariantSearch(translation, healedSource, activeInvariant))
```

### 2.5 `swat.executeRaid` (src/personas/swat.nim:30)

```nim
proc executeRaid*(...): Result[SwatArtifact, AxiomError] {.raises: [].} =
  try:
    # Source integrity gate — SWAT only scans, never modifies source
    let finalScan = runNegativeInvariantSearch(translation, req.sourceCode, activeInvariant)
    let sourceChecksumRes = ??syncRecoveredSourceToModule(req, req.sourceCode)
    let pocSnippet = if evolutionHit.isSome(): buildPocSnippet(...) else: ""
    let reproductionPathRes = ??writeReproductionArtifact(req, evolutionHit, pocSnippet)
    let bddPathRes = ??writeBddFeature(req, initialScan)
```

### 2.6 `judge.certify` (src/personas/judge.nim:29)

```nim
proc certify*(...): Result[JudgeArtifact, AxiomError] {.raises: [].} =
  try:
    # Phase 1 wiring: if Leanstral produced a verified Lean source, try it first
    if preSynthesizedLeanSource.len > 0:
      let leanReplayResult = runLeanReplay(req.functionName, preSynthesizedLeanSource)
      if leanReplayResult.isOk and leanReplayResult.get().isValid:
        ...
    let refined = runLeanProofRefinementLoop(req, translation, sourceCode, activeInvariant, maxRounds)
    let inferred = inferLeanSpec(...)
```

### 2.7 `runUniversalAcceptancePipelineCore` (src/verification/pipeline_core_runner_parts/pipeline_core_runner_part2.nim:32)

```nim
proc runUniversalAcceptancePipelineCore*(
  req: UniversalPipelineRequest
): Result[UniversalPipelineResult, AxiomError] =
  if req.astJson.strip().len == 0 or req.sourceCode.strip().len == 0:
    return err(axiomErrEmptyString)
  let mapped = ??mapAstJsonToUniversalTranslation(req.language, req.astJson)
  let translation = mapped
  let priorPromotion = loadPromotionFromProofVault(req)
  let initial = runNegativeInvariantSearch(translation, req.sourceCode, priorPromotion.invariant)
  let healed = runSelfHealingLoop(req.sourceCode, translation, initial, req.maxRounds, priorPromotion.invariant)
  ...
  let leanRefined = runLeanProofRefinementLoop(req, translation, healed.finalSource, seededInvariant, req.maxRounds)
  ...
  let finalScan = runNegativeInvariantSearch(translation, leanRefined.finalSource, activeInvariant)
  let verificationVerdict = inferVerificationVerdict(finalScan)
  ...
  ok(resultObj)
```

### 2.8 `runBatchUapOrchestration` budget lines (src/verification/batch_uap_orchestrator.nim)

```nim
const
  nodeTimeoutMs* = 120_000  ## 2 min per-node wall-clock timeout

proc runBatchUapOrchestration*(...): BatchUapReport {.raises: [Exception].} =
  var budget = initProofBudget()
  ...
  let budgetVerdict = checkBudget(budget)
  if budgetVerdict != pbvContinue:
    report.nodeReports.add(...)
    depthFailed = true
    break
  ...
  discard consumeGas(budget)
  ...
  let nodeStartMono = getMonoTime().ticks
  let uapResult = runUniversalAcceptancePipeline(uapReqRes.get())
  let nodeElapsedMs = (getMonoTime().ticks - nodeStartMono) div 1_000_000
  if nodeElapsedMs > nodeTimeoutMs:
    report.nodeReports.add(...)
```

### 2.9 `runNegativeInvariantSearch` (src/verification/pipeline_negative_scan_parts/pipeline_negative_scan_part3.nim:184)

```nim
proc runNegativeInvariantSearch*(
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string = ""
): NegativeInvariantScan =
  var sourceAst = none(XmlNode)
  if translation.language.toLowerAscii() == "nim" and sourceCode.len > 0:
    try:
      sourceAst = some(parseNim(sourceCode))
    except CatchableError:
      discard
  if translation.memoryAccessCount > 0:
    checkBufferOverflow(result, translation, sourceAst, activeInvariant)
    checkNullPointer(result, translation, sourceAst, activeInvariant)
  checkIntegerOverflow(result, translation, sourceCode, sourceAst, activeInvariant)
  checkGhostUpdate(result, translation, sourceCode, sourceAst, activeInvariant)
  checkDeadlockRace(result, translation, sourceCode, sourceAst, activeInvariant)
```

### 2.10 `runLeanProofRefinementLoop` (src/verification/healing_orchestrator.nim:70)

```nim
proc runLeanProofRefinementLoop*(...):
  tuple[finalSource: string; finalInvariant: string; rounds: seq[HealingRound]; nearestDiagnostic: string; failedReplayAttempts: int] =
  let leanExe = getEnv("AXIOM_LEAN_CMD", "lean")
  let roundsCap = if maxRounds <= 0: 1 else: maxRounds
  var currentSource = sourceCode
  var currentInvariant = activeInvariant
  var visitedStates = @[healingStateFingerprint(currentSource, currentInvariant)]
  for round in 1 .. roundsCap:
    let inferred = inferLeanSpec(...)
    let artifactPath = joinPath(...)
    let compilerResult = verifyGeneratedLeanSourceWithCompiler(inferred.theoremSource, artifactPath, leanExe)
    ...
    if compilerResult.verified:
      result.rounds.add(HealingRound(...))
```

---

## §3. Deterministic Evidence Checklist

| Claim | Evidence | Status |
|---|---|---|
| `swat.executeRaid` does NOT import `bmc_generic` or `bmc_race` | grep of `src/personas/swat.nim` → no matches | ✅ CONFIRMED |
| `detective.openCase`/`investigate` does NOT import `cegar_engine` | grep of `src/personas/detective.nim` → no matches | ✅ CONFIRMED |
| `judge.certify` calls `runLeanReplay` | grep of `src/personas/judge.nim` line 41 | ✅ CONFIRMED |
| `callLeanstral` exists | grep found definition at `leanstral_gateway.nim:198` + 3 call sites | ✅ CONFIRMED |
| `runUniversalAcceptancePipelineCore` has ZERO callers in `src/` | grep returned only definition + 1 proof-vault JSON | ✅ CONFIRMED |
| `runBatchUapOrchestration` calls `initProofBudget` | line 69 of `batch_uap_orchestrator.nim` | ✅ CONFIRMED |
| `runBatchUapOrchestration` calls `checkBudget` | line 103 of `batch_uap_orchestrator.nim` | ✅ CONFIRMED |
| `runBatchUapOrchestration` calls `consumeGas` | line 135 of `batch_uap_orchestrator.nim` | ✅ CONFIRMED |
| `nodeTimeoutMs = 120_000` | line 20 of `batch_uap_orchestrator.nim` | ✅ CONFIRMED |
