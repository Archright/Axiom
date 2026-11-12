import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/options
import std/sequtils
import std/strutils

import core/boundary/persona_boundary
import core/proof/proof_vacuity_gate
import core/judge/lean_replay
import core/encoding/smt_to_lean/private/parser
import personas/legislator_feedback
export persona_boundary

import ../core/trusted/env_access
import ../core/trusted/effect_bridge  # For AxiomIOEffect

import personas/judge_automation

# axiomIoBoundary — persona module performing I/O (LLM calls, Lean compiler subprocess)

let ctx = defaultPersonaCtx

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
# @axiom-hint: lean="functionName.length ≥ 0 ∧ proofReplayMethod.length ≥ 0 ∧ verified = true ∨ verified = false ∧ failedAttempts ≥ -9223372036854775808 ∧ failedAttempts ≤ 9223372036854775807" smt="(assert (and (>= (str.len functionName) 0) (>= (str.len proofReplayMethod) 0) (or (= verified true) (= verified false)) (and (>= failedAttempts -9223372036854775808) (<= failedAttempts 9223372036854775807))))"
proc judgeLogLine(
  functionName: string;
  proofReplayMethod: string;
  verified: bool;
  failedAttempts: int
): string {.raises: [], noSideEffect.} =
  let named = if functionName.len > 0: functionName else: "unknown"
  let status = if verified: "Approved" else: "Pending"
  let replayMethod = if proofReplayMethod.len > 0: proofReplayMethod else: "unknown"
  "[Judge] " & status & " complete: " & named & " replay=" & replayMethod & " failedAttempts=" & $failedAttempts

proc safeParsePositiveInt(s: string): int {.raises: [].} =
  ## Parse a positive integer without raising; returns 0 on failure.
  result = 0
  var started = false
  for ch in s:
    if ch == ' ':
      if started: break
      continue
    if ch >= '0' and ch <= '9':
      started = true
      result = result * 10 + (ord(ch) - ord('0'))
    else:
      result = 0
      return

proc parseLeanLineLocation(line: string; defaultPath: string): tuple[filePath: string, lineNumber: int] {.raises: [].} =
  ## Parse Lean compiler output of the form: file.lean:line:col: error: message
  ## Also supports warning: and info: severity markers.
  result = (filePath: defaultPath, lineNumber: 0)
  let errorIdx = line.find(" error:")
  let warningIdx = line.find(" warning:")
  let infoIdx = line.find(" info:")
  let severityIdx = if errorIdx >= 0: errorIdx
                    elif warningIdx >= 0: warningIdx
                    elif infoIdx >= 0: infoIdx
                    else: -1
  if severityIdx < 0:
    return
  let prefix = line.substr(0, severityIdx - 1)
  let parts = prefix.split(':')
  if parts.len >= 3:
    let lineNum = safeParsePositiveInt(parts[^2])
    if lineNum > 0:
      result.lineNumber = lineNum
      var pathParts: seq[string] = @[]
      for i in 0 .. parts.len - 3:
        pathParts.add(parts[i])
      result.filePath = pathParts.join(":")
  elif parts.len == 2:
    let lineNum = safeParsePositiveInt(parts[^1])
    if lineNum > 0:
      result.lineNumber = lineNum
      result.filePath = parts[0]

proc parseDiagnosticToDiscontinuities*(
    diagnostic: string;
    sourcePath: string = "";
    unsatCoreVars: seq[string] = @[];
    sourceCode: string = ""
): seq[MathematicalDiscontinuity] {.raises: [].} =
  if diagnostic.len == 0:
    return @[]
  for line in diagnostic.splitLines:
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    let loc = parseLeanLineLocation(trimmed, sourcePath)
    var kind = dkMissingInvariant
    let lower = trimmed.toLowerAscii()
    if "non-linear" in lower or "nonlinear" in lower:
      kind = dkNonLinearArithmetic
    elif "recursion" in lower or "recursive" in lower:
      kind = dkUnboundedRecursion
    elif "side effect" in lower or "side-effect" in lower:
      kind = dkExternalSideEffect
    elif "alias" in lower or "aliasing" in lower:
      kind = dkPointerAliasing
    elif "race" in lower or "concurrency" in lower:
      kind = dkConcurrencyRace
    result.add(MathematicalDiscontinuity(
      filePath: loc.filePath,
      lineNumber: loc.lineNumber,
      smtUnsatCoreVars: @[],
      discontinuityKind: kind,
      description: trimmed
    ))
  # Unsat core correlation: enrich each discontinuity with matching Z3 variables
  if unsatCoreVars.len > 0 and sourceCode.len > 0:
    for i in 0 ..< result.len:
      for varName in unsatCoreVars:
        if varName.len > 0 and varName in sourceCode:
          result[i].smtUnsatCoreVars.add(varName)

proc buildStructuredRemediation(
    discontinuities: seq[MathematicalDiscontinuity];
    templates: seq[RefactoringTemplate] = @[]
): StructuredRemediationPayload {.raises: [].} =
  StructuredRemediationPayload(
    discontinuities: discontinuities,
    suggestedPatterns: @[],
    refactoringTemplates: templates
  )

proc buildProofArtifact(
    nodeId: string;
    leanKernelVerified: bool;
    provenLayer: string;
    asiScore: float;
    discontinuities: seq[MathematicalDiscontinuity];
    unsatCoreVars: seq[string];
    leanDiagnostic: string;
    elapsedMs: int;
    iterations: int;
    stagnationEscalated: bool;
    templates: seq[RefactoringTemplate] = @[]
): proof_artifact.ProofArtifact {.raises: [].} =
  ## Construct a ProofArtifact from judge-internal types.
  ## Converts MathematicalDiscontinuity → proof_artifact.Discontinuity via ordinal mapping.
  var converted: seq[proof_artifact.Discontinuity] = @[]
  for d in discontinuities:
    converted.add(proof_artifact.Discontinuity(
      filePath: d.filePath,
      lineNumber: d.lineNumber,
      smtUnsatCoreVars: d.smtUnsatCoreVars,
      kind: proof_artifact.DiscontinuityKind(ord(d.discontinuityKind)),
      description: d.description
    ))
  proof_artifact.ProofArtifact(
    nodeId: nodeId,
    kind: if leanKernelVerified: proof_artifact.pakProven else: proof_artifact.pakUnverifiable,
    discontinuities: converted,
    suggestedPatterns: @[],
    refactoringTemplates: templates,
    synergyMetrics: proof_artifact.emptySynergyMetrics(),
    provenLayer: provenLayer,
    asiScore: asiScore,
    smtUnsatCoreVars: unsatCoreVars,
    leanDiagnostic: leanDiagnostic,
    elapsedMs: elapsedMs,
    iterations: iterations,
    stagnationEscalated: stagnationEscalated
  )


proc extractGoalDeltas(diagnostic: string): seq[string] {.raises: [], noSideEffect.} =
  ## Extract goal-related diagnostic lines for Legislator feedback.
  var deltas: seq[string] = @[]
  for line in diagnostic.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("unsolved goal") or stripped.startsWith("⊢ ") or stripped.contains("unable to unify"):
      deltas.add(stripped)
  deltas

proc tryLeanstralShortcut(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode, activeInvariant, verificationVerdict: string;
  preSynthesizedLeanSource: string;
  smtUnsatCoreVars: seq[string];
  elapsedMs, iterations: int
): Option[JudgeArtifact] =
  ## Phase 1: Leanstral shortcut -- return early if pre-synthesized proof is valid.
  if preSynthesizedLeanSource.len == 0:
    return none(JudgeArtifact)
  let leanReplayResult = runLeanReplay(req.functionName, preSynthesizedLeanSource)
  if not leanReplayResult.isOk or not leanReplayResult.get().isValid:
    return none(JudgeArtifact)
  ## leanKernelVerified is derived from runLeanReplay's verdict, which is now
  ## sorry-aware (fail-closed on sorryAx / non-allowlisted axioms). No hardcoded
  ## true — docs/spec/lean_sorry_gate.md (DEBT#296).
  let leanKernelVerified = leanReplayResult.get().isValid
  let inferred = ctx.inferLeanSpec(
    req.modulePath, req.functionName, translation,
    sourceCode, activeInvariant, verificationVerdict
  )
  let discontinuities = parseDiagnosticToDiscontinuities("", req.modulePath)
  ctx.logStage(skJudge, req.functionName, "verified=true", 0, ssSucceeded, nil)
  some(JudgeArtifact(
    finalSource: sourceCode,
    finalInvariant: activeInvariant,
    inferredSpec: inferred,
    nearestDiagnostic: "",
    nearestDiscontinuities: discontinuities,
    failedReplayAttempts: 0,
    rounds: @[],
    proofReplayMethod: "leanstral",
    proofReplayTactics: @["leanstral_llm"],
    leanKernelVerified: leanKernelVerified,
    vacuityProven: false,
    negativeMutationPass: false,
    proofDepth: inferred.proofReplay.tactics.len,
    logLines: @["[Judge] Leanstral proof accepted by Lean 4 kernel"],
    structuredRemediation: buildStructuredRemediation(discontinuities),
    proofArtifact: buildProofArtifact(
      nodeId = $req.functionName,
      leanKernelVerified = leanKernelVerified,
      provenLayer = "leanstral",
      asiScore = 0.0,
      discontinuities = discontinuities,
      unsatCoreVars = smtUnsatCoreVars,
      leanDiagnostic = "",
      elapsedMs = elapsedMs,
      iterations = iterations,
      stagnationEscalated = false
    )
  ))

proc tryDeterministicCertification(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode, activeInvariant, verificationVerdict: string;
  preSynthesizedLeanSource: string;
  smtUnsatCoreVars: seq[string];
  elapsedMs, iterations: int
): Option[JudgeArtifact] =
  ## Phase 5: Deterministic strategy attempt before LLM fallback.
  let detGoalSource = if preSynthesizedLeanSource.len > 0: preSynthesizedLeanSource
                      else: sourceCode
  let goalShape = classifyGoalViaWhnf(detGoalSource)
  let detResult = tryDeterministicProof(detGoalSource, goalShape)
  if detResult.isNone:
    return none(JudgeArtifact)
  let proof = detResult.get()
  let inferred = ctx.inferLeanSpec(
    req.modulePath, req.functionName, translation,
    sourceCode, activeInvariant, verificationVerdict
  )
  let discontinuities = parseDiagnosticToDiscontinuities(proof.output, req.modulePath)
  ctx.logStage(skJudge, req.functionName, "verified=true", 0, ssSucceeded, nil)
  some(JudgeArtifact(
    finalSource: sourceCode,
    finalInvariant: activeInvariant,
    inferredSpec: inferred,
    nearestDiagnostic: proof.output,
    nearestDiscontinuities: discontinuities,
    failedReplayAttempts: 0,
    rounds: @[],
    proofReplayMethod: "deterministic_" & $proof.strategy,
    proofReplayTactics: @[strategyToTactic(proof.strategy)],
    leanKernelVerified: true,
    vacuityProven: false,
    negativeMutationPass: false,
    proofDepth: 1,
    logLines: @["[Judge] Deterministic strategy " & $proof.strategy &
                " (" & $goalShape & ") solved proof goal"],
    structuredRemediation: buildStructuredRemediation(discontinuities),
    proofArtifact: buildProofArtifact(
      nodeId = $req.functionName,
      leanKernelVerified = true,
      provenLayer = "deterministic",
      asiScore = 0.0,
      discontinuities = discontinuities,
      unsatCoreVars = smtUnsatCoreVars,
      leanDiagnostic = proof.output,
      elapsedMs = elapsedMs,
      iterations = iterations,
      stagnationEscalated = false
    )
  ))

proc initJudgeCallbacks(
  req: UniversalPipelineRequest;
  maxRounds: int
): VerificationUnit =
  ## Initialize the VerificationUnit with callback-based DIP.
  ## ctx is module-level let (immutable), cast(gcsafe) is safe.
  proc healCb(src: string, tr: UniversalTranslation, scan: NegativeInvariantScan, maxR: int, prior: string): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.raises: [CatchableError], gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    {.cast(gcsafe).}:
      {.axiomGcsafe.}:
        ctx.runSelfHealingLoop(src, tr, scan, maxR, prior)
  proc refineCb(req: UniversalPipelineRequest, tr: UniversalTranslation, src: string, inv: string, maxR: int): tuple[finalSource: string, finalInvariant: string, rounds: seq[HealingRound], nearestDiagnostic: string, failedReplayAttempts: int, leanKernelVerified: bool, vacuityProven: bool] {.raises: [CatchableError], gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    {.cast(gcsafe).}:
      {.axiomGcsafe.}:
        ctx.runLeanProofRefinementLoop(req, tr, src, inv, maxR)
  proc scanCb(tr: UniversalTranslation, src: string, prior: string): NegativeInvariantScan {.raises: [CatchableError], gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    {.cast(gcsafe).}:
      {.axiomGcsafe.}:
        ctx.runNegativeInvariantSearch(tr, src, prior)
  func mergeCb(prior: string, refined: string): string {.raises: [], gcsafe.} =
    mergeInvariantClauses(prior, refined)
  initVerificationUnit(healCb, refineCb, scanCb, mergeCb, leanExe=getAxiomEnv(evLeanCmd, "lean"), maxRounds=maxRounds)

proc tryClosedLoopRetry(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode, activeInvariant, verificationVerdict: string;
  refined: tuple[finalSource: string; finalInvariant: string; rounds: seq[HealingRound]; nearestDiagnostic: string; failedReplayAttempts: int; leanKernelVerified: bool; vacuityProven: bool];
  inferred: LeanSpecInference;
  cxHistory: seq[CounterExamplePayload];
  smtUnsatCoreVars: seq[string];
  elapsedMs, iterations: int;
  stagnationEscalated: bool;
  unit: VerificationUnit
): Option[JudgeArtifact] =
  ## Closed-loop feedback: Lean kernel rejected -> inject counterexample into Legislator.
  let smtCxStr = if smtUnsatCoreVars.len > 0:
    "Z3 unsat core: {" & smtUnsatCoreVars.join(", ") & "}"
  else:
    ""
  let cx = CounterExamplePayload(
    nodeId: req.functionName,
    failedInvariant: activeInvariant,
    leanDiagnostic: refined.nearestDiagnostic,
    smtCounterExample: smtCxStr,
    traceReport: buildTraceReport(none(AnnotatedHit))
  )
  let updatedHistory = cxHistory & @[cx]
  let priorPromotion = (invariant: activeInvariant, snapshotPath: "")
  let initialScan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
  let goalDeltas = extractGoalDeltas(refined.nearestDiagnostic)
  let feedbackRes = legislateWithFeedback(req, translation, initialScan, priorPromotion, sourceCode, updatedHistory, unsatCoreVars = @[], goalDelta = goalDeltas, failingLeanSource = inferred.theoremSource)
  if not feedbackRes.isOk:
    return none(JudgeArtifact)
  let revised = feedbackRes.get()
  if revised.activeInvariant.len == 0 or revised.activeInvariant == activeInvariant:
    return none(JudgeArtifact)
  let retryRefined = unit.runLeanProofRefinement(req, translation, sourceCode, revised.activeInvariant)
  let retryInferred = ctx.inferLeanSpec(
    req.modulePath, req.functionName, translation,
    retryRefined.finalSource, retryRefined.finalInvariant, verificationVerdict
  )
  let retryDiscontinuities = parseDiagnosticToDiscontinuities(retryRefined.nearestDiagnostic, req.modulePath)
  ctx.logStage(skJudge, req.functionName, "verified=" & $retryRefined.leanKernelVerified, 0, ssSucceeded, nil)
  some(JudgeArtifact(
    finalSource: retryRefined.finalSource,
    finalInvariant: retryRefined.finalInvariant,
    inferredSpec: retryInferred,
    nearestDiagnostic: retryRefined.nearestDiagnostic,
    nearestDiscontinuities: retryDiscontinuities,
    failedReplayAttempts: retryRefined.failedReplayAttempts,
    rounds: refined.rounds & retryRefined.rounds,
    proofReplayMethod: retryInferred.proofReplay.replayMethod,
    proofReplayTactics: retryInferred.proofReplay.tactics.mapIt(it.name),
    leanKernelVerified: retryRefined.leanKernelVerified,
    vacuityProven: retryRefined.vacuityProven,
    negativeMutationPass: retryRefined.vacuityProven,
    proofDepth: retryInferred.proofReplay.tactics.len,
    logLines: @[
      judgeLogLine(req.functionName, retryInferred.proofReplay.replayMethod, retryRefined.leanKernelVerified, retryRefined.failedReplayAttempts)
    ],
    structuredRemediation: buildStructuredRemediation(retryDiscontinuities),
    proofArtifact: buildProofArtifact(
      nodeId = $req.functionName,
      leanKernelVerified = retryRefined.leanKernelVerified,
      provenLayer = "judge",
      asiScore = 0.0,
      discontinuities = retryDiscontinuities,
      unsatCoreVars = smtUnsatCoreVars,
      leanDiagnostic = retryRefined.nearestDiagnostic,
      elapsedMs = elapsedMs,
      iterations = iterations,
      stagnationEscalated = stagnationEscalated
    )
  ))

## Vacuity gate check for any proof path
proc checkVacuityGate(
  artifact: var JudgeArtifact;
  sourceCode, functionName: string;
  req: UniversalPipelineRequest = default(UniversalPipelineRequest)
) =
  let hasStrictSpecWarning = artifact.finalSource.find("strictSpecWarningRaised : Bool := true") >= 0
  if not hasStrictSpecWarning: return
  let hasSafetyGoal = artifact.finalSource.find("_inferred_safety_goal") >= 0
  if not hasSafetyGoal: return

  # Lean replay to detect actual vacuity from #reduce
  let replayResult = runLeanReplay(functionName, artifact.finalSource)
  let reduceResultIsVacuous = replayResult.isOk and replayResult.get().vacuityDetected

  # Layer 2: Context-Aware Vacuity Gate
  let vacuityGateResult = validateVacuityParts(
    leanSource = artifact.finalSource,
    smtConstraint = "",
    nodeId = functionName,
    sourceContext = sourceCode,
    reduceResultIsVacuous = reduceResultIsVacuous
  )

  # Extract typed variables from request context
  var stateVars: seq[tuple[name: string, smtType: string]] = @[]
  for pre in req.preConditions:
    let decls = parseSmtlib2Decls(pre)
    for d in decls:
      stateVars.add((d.name, d.smtType))
  if stateVars.len == 0:
    let decls = parseSmtlib2Decls(artifact.finalInvariant)
    for d in decls:
      stateVars.add((d.name, d.smtType))

  # Layer 3: Z3 Non-Triviality Check (with fallback detection)
  let z3Result = verifyNonTrivialityWithFallback(
    invariantClauses = @[artifact.finalInvariant],
    stateVars = stateVars,
    sourceContext = sourceCode,
    timeoutMs = 5000
  )

  # Layer 4: Negative Mutation Test
  let mutationPass = runNegativeMutationTest(functionName, artifact.finalSource)

  # Composite gate
  var status = VacuityProofStatus(
    leanReplayPass: not vacuityGateResult.isVacuousReject,
    z3NonTrivialityPass: z3Result.nonTrivial,
    negativeMutationPass: mutationPass,
    nonVerifiedFallback: z3Result.fallback,
    fallbackReason: z3Result.reason
  )

  if not isGenuinelyProven(status):
    var reasons: seq[string] = @[]
    if not status.leanReplayPass: reasons.add("LeanReplay: vacuous goal")
    if not status.z3NonTrivialityPass: reasons.add("Z3: invariant trivially true")
    if not status.negativeMutationPass: reasons.add("Mutation: negative test passed or syntax error")
    artifact.vacuityProven = false
    artifact.negativeMutationPass = false
    artifact.leanKernelVerified = false
    ctx.logStage(skJudge, functionName,
      "REJECT: vacuity defense [" & reasons.join("; ") & "]", 0, ssFailed, nil)

## Certify.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc certify*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string;
  verificationVerdict: string;
  maxRounds: int;
  preSynthesizedLeanSource: string = "";
  cxHistory: seq[CounterExamplePayload] = @[];
  smtUnsatCoreVars: seq[string] = @[];
  elapsedMs: int = 0;
  iterations: int = 0;
  stagnationEscalated: bool = false;
  goalDeltas: seq[GoalDelta] = @[]
): Result[JudgeArtifact, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls ctx.logStage, runLeanReplay, ctx.inferLeanSpec — I/O side effects]
  ## Phase 2: Judge migrated to VerificationUnit with closed-loop feedback.
  ## If Lean kernel rejects the invariant, counterexample is injected back
  ## into Legislator for a single retry.
  try:
    # Phase 1: Leanstral shortcut
    let leanstralArtifact = tryLeanstralShortcut(req, translation, sourceCode,
      activeInvariant, verificationVerdict, preSynthesizedLeanSource,
      smtUnsatCoreVars, elapsedMs, iterations)
    if leanstralArtifact.isSome:
      var art = leanstralArtifact.get()
      checkVacuityGate(art, sourceCode, $req.functionName, req=req)
      return ok(art)

    # Phase 5: Deterministic strategy
    let detArtifact = tryDeterministicCertification(req, translation, sourceCode,
      activeInvariant, verificationVerdict, preSynthesizedLeanSource,
      smtUnsatCoreVars, elapsedMs, iterations)
    if detArtifact.isSome:
      var art = detArtifact.get()
      checkVacuityGate(art, sourceCode, $req.functionName, req=req)
      return ok(art)

    # DIP refinement via callbacks
    let unit = initJudgeCallbacks(req, maxRounds)
    let refined = unit.runLeanProofRefinement(req, translation, sourceCode, activeInvariant)
    let inferred = ctx.inferLeanSpec(
      req.modulePath, req.functionName, translation,
      refined.finalSource, refined.finalInvariant, verificationVerdict
    )

    # Closed-loop retry on Lean kernel rejection
    if not refined.leanKernelVerified:
      let retryArtifact = tryClosedLoopRetry(req, translation, sourceCode,
        activeInvariant, verificationVerdict, refined, inferred, cxHistory,
        smtUnsatCoreVars, elapsedMs, iterations, stagnationEscalated, unit)
      if retryArtifact.isSome:
        return ok(retryArtifact.get())

    # Final success
    let discontinuities = parseDiagnosticToDiscontinuities(refined.nearestDiagnostic, req.modulePath)
    ctx.logStage(skJudge, req.functionName, "verified=" & $refined.leanKernelVerified, 0, ssSucceeded, nil)
    ok(JudgeArtifact(
      finalSource: refined.finalSource,
      finalInvariant: refined.finalInvariant,
      inferredSpec: inferred,
      nearestDiagnostic: refined.nearestDiagnostic,
      nearestDiscontinuities: discontinuities,
      failedReplayAttempts: refined.failedReplayAttempts,
      rounds: refined.rounds,
      proofReplayMethod: inferred.proofReplay.replayMethod,
      proofReplayTactics: inferred.proofReplay.tactics.mapIt(it.name),
      leanKernelVerified: refined.leanKernelVerified,
    vacuityProven: refined.vacuityProven,
    negativeMutationPass: refined.vacuityProven,
    proofDepth: inferred.proofReplay.tactics.len,
    logLines: @[
      judgeLogLine(req.functionName, inferred.proofReplay.replayMethod, refined.leanKernelVerified, refined.failedReplayAttempts)
    ],
    structuredRemediation: buildStructuredRemediation(discontinuities),
    proofArtifact: buildProofArtifact(
      nodeId = $req.functionName,
      leanKernelVerified = refined.leanKernelVerified,
      provenLayer = "judge",
      asiScore = 0.0,
      discontinuities = discontinuities,
      unsatCoreVars = smtUnsatCoreVars,
      leanDiagnostic = refined.nearestDiagnostic,
        elapsedMs = elapsedMs,
        iterations = iterations,
        stagnationEscalated = stagnationEscalated
      )
    ))
  except CatchableError:
    err(axiomErrInconsistentState)

{.pop.}

