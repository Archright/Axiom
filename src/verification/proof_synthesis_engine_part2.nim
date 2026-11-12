import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import std/options
import std/os
import std/sequtils
import std/strutils
import std/times
import core/axiom_pragmas
import ../core/trusted/env_access

import verification/lean_lsp
import core/trusted/lean_util
import core/contracts/universal_pipeline_contract
import core/json/json_utils
import core/proof/proof_vacuity_gate
import core/utils/text_utils
import core/logic/semantic_theorem_builder
import verification/leanstral_gateway
import verification/llm_backend
# axiomIoBoundary
import core/translator/universal_assembler as ula

import verification/proof_synthesis_engine_part1
export proof_synthesis_engine_part1
import verification/leanstral_repl  # REPL-based synthesis

const
  axiomVaultDir = "src/verification/axiom_vault"
  evidenceDir = "logs/evidence"

## Run a single Leanstral round: network invocation, compiler replay, and evidence persistence.
# @axiom-hint: lean="prompt.length ≥ 0 ∧ artifactPath.length ≥ 0 ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807 ∧ leanExe.length ≥ 0 ∧ theoremSkeleton.length ≥ 0" smt="(assert (and (>= (str.len prompt) 0) (>= (str.len artifactPath) 0) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807)) (>= (str.len leanExe) 0) (>= (str.len theoremSkeleton) 0)))"
# @axiom-hint: lean="theoremSkeleton.length > 0 ∧ vacuityErr.length > 0 ∧ (result ≥ 0) ∧ (compileResult ≥ 0)" smt="(assert (and (> (str.len theoremSkeleton) 0) (> (str.len vacuityErr) 0) (>= result 0) (>= compileResult 0)))"
proc runLeanstralRound*(
  prompt: string;
  artifactPath: string;
  timeoutMs: int;
 leanExe: string = "";
  theoremSkeleton: string = ""
): LeanstralRoundResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let leanstralRes = callLeanstral(prompt, timeoutMs = timeoutMs)
  result.leanstralSuccess = leanstralRes.success
  result.leanstralDiagnostics = leanstralRes.diagnostics
  result.tacticTrace = leanstralRes.tacticTrace
  result.rawOutput = leanstralRes.rawOutput
  if not leanstralRes.success or leanstralRes.theoremSource.len == 0:
    return
  let sourceBody = if theoremSkeleton.len > 0:
      theoremSkeleton & leanstralRes.theoremSource & "\n"
    else:
      leanstralRes.theoremSource
  ## Zero-Trust Sanitization: strip colon artifacts, reserved words,
  ## and Nim type annotations from Leanstral output before Lean compilation.
  ## NOTE: sanitizeLeanSource preserves colons in theorem/def headers.
  ## Leanstral output contains theorem header + body; we must also strip
  ## colons from non-header portions. Apply total nuclear colon removal
  ## after sanitize to catch any remaining colon artifacts in the body.
  let (sanitizedBody, _) = ula.sanitizeLeanSource(sourceBody)
  # Additional nuclear pass: protect := then strip all colons from sanitized
  var finalBody = sanitizedBody
  const sentinel = "__COLEQ__"
  finalBody = finalBody.replace(":=", sentinel)
  var idx = 0
  var buf = ""
  while idx < finalBody.len:
    if finalBody[idx] == ':':
      inc idx
      while idx < finalBody.len and finalBody[idx] == ' ':
        inc idx
      continue
    buf.add(finalBody[idx])
    inc idx
  finalBody = buf
  finalBody = finalBody.replace(sentinel, ":=")
  let sourceToCompile = withExtendedAxiomPrelude(finalBody)
  ## Final total nuclear pass: re-apply full sanitizeLeanSource to the
  ## fully assembled source (prelude + body) before Lean compilation.
  ## This catches any artifacts that survived individual sanitization steps.
  let (finalSanitized, _) = ula.sanitizeLeanSource(sourceToCompile)
  result.theoremSource = finalSanitized
  result.success = true
  let vacuityErr = leanSourceVacuityReason(sourceToCompile, "", "", prompt)
  if vacuityErr.len > 0:
    result.verified = false
    result.compilerExitCode = -1
    result.diagnostics = @["Semantic integrity checkpoint rejected Leanstral output: " &
      vacuityErr]
    return
  var compileResult: LeanCompilerResult
  try:
    compileResult = verifyGeneratedLeanSourceWithCompiler(sourceToCompile, artifactPath, leanExe)
  except CatchableError as e:
    compileResult = LeanCompilerResult(
      verified: false,
      exitCode: -1,
      diagnostics: @[lean_diagnostic.LeanDiagnostic(
        line: 0,
        character: 0,
        severity: 1,
        message: e.msg
      )],
      output: e.msg,
      artifactPath: artifactPath
    )
  result.verified = compileResult.verified
  result.compilerExitCode = compileResult.exitCode
  result.diagnostics = compileResult.diagnostics.mapIt(it.message)
  result.leanDiagnostics = compileResult.diagnostics
  result.artifactPath = artifactPath
  try:
    let safeName = extractFilename(artifactPath).replace(".lean", "")
    let evidencePath = joinPath(evidenceDir, safeName & ".json")
    discard existsOrCreateDir(parentDir(evidencePath))
    discard writePrettyJsonFile(evidencePath, %*{
      "timestamp": now().utc.format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
      "theoremSource": sourceToCompile,
      "leanCompilerExitCode": compileResult.exitCode,
      "diagnostics": result.diagnostics,
      "tacticTrace": leanstralRes.tacticTrace
    })
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc runLeanstralRoundRepl*(
  prompt: string;
  artifactPath: string;
  timeoutMs: int;
 maxRounds: int = 10;
  leanExe: string = "";
  theoremSkeleton: string = ""
): LeanstralRoundResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## REPL-based version of runLeanstralRound.
  ## Uses tryLeanstralReplSynthesis for interactive feedback loop.
  ## Falls back to one-shot if REPL is unavailable.
  let replResult = tryLeanstralReplSynthesis(prompt, "", timeoutMs, maxRounds)
  if replResult.success:
    result.success = true
    result.verified = true
    result.theoremSource = replResult.theoremSource
    result.tacticTrace = replResult.tacticTrace
    result.diagnostics = @[replResult.diagnostics]
  else:
    # Graceful degradation: fall back to one-shot
    result = runLeanstralRound(prompt, artifactPath, timeoutMs, leanExe, theoremSkeleton)

## Leanstral Synthesis Strategy.
# @axiom-hint: lean="artifactPath.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ config_maxRounds ≥ -9223372036854775808 ∧ config_maxRounds ≤ 9223372036854775807 ∧ config_timeoutMs ≥ -9223372036854775808 ∧ config_timeoutMs ≤ 9223372036854775807" smt="(assert (and (>= (str.len artifactPath) 0) (>= (str.len leanExe) 0) (>= (str.len vaultDir) 0) (and (>= config_maxRounds -9223372036854775808) (<= config_maxRounds 9223372036854775807)) (and (>= config_timeoutMs -9223372036854775808) (<= config_timeoutMs 9223372036854775807))))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
proc leanstralSynthesisStrategy*(
  payload: SemanticEqualityPayload;
  artifactPath: string;
  leanExe: string;
  vaultDir: string;
  config: SynthesisConfig
): SynthesisResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let backend = resolveDefaultBackend()
  if backend.isNone:
    result.verified = false
    result.feedbackSummary = "FATAL: No LLM backend available. Set AXIOM_LLM_API_URL + AXIOM_LLM_API_KEY. Leanstral synthesis cannot proceed without an LLM backend."
    return
  let outcome = tryLeanstralSynthesis(payload, artifactPath, leanExe, vaultDir, config)
  if outcome.success:
    result.verified = true
    result.theoremSource = outcome.theoremSource
    result.tacticTrace = outcome.tacticTrace
    result.minimalProofPath = minimizeProofPath(outcome.tacticTrace.join("\n"))
    result.rounds = outcome.rounds
    result.feedbackSummary = outcome.feedbackSummary
  else:
    result.verified = false
    result.rounds = outcome.rounds
    result.feedbackSummary = outcome.feedbackSummary

## Run Semantic Proof Replay.
# @axiom-hint: lean="leanArtifactPath.length ≥ 0" smt="(assert (and (>= (str.len leanArtifactPath) 0)))"
# @axiom-hint: lean="tacticPlan.length = 0 ∧ tacticCursor < tacticPlan.length ∧ nextTactic.length > 0 ∧ allMsgTokensInSummary = false ∧ activeTactic = nextTactic ∧ (allMsgTokensInSummary ≥ 0) ∧ (finalSummary ≥ 0) ∧ (liveFeedback ≥ 0) ∧ (tacticPlan ≥ 0) ∧ (nextTactic ≥ 0) ∧ (minimalProofPath ≥ 0) ∧ (result ≥ 0) ∧ (finalSource ≥ 0) ∧ (msgTokens ≥ 0) ∧ (compileResult ≥ 0) ∧ (activeTactic ≥ 0)" smt="(assert (and (= (str.len tacticPlan) 0) (< tacticCursor (str.len tacticPlan)) (> (str.len nextTactic) 0) (= allMsgTokensInSummary false) (= activeTactic nextTactic) (>= allMsgTokensInSummary 0) (>= finalSummary 0) (>= liveFeedback 0) (>= tacticPlan 0) (>= nextTactic 0) (>= minimalProofPath 0) (>= result 0) (>= finalSource 0) (>= msgTokens 0) (>= compileResult 0) (>= activeTactic 0)))"
proc runSemanticProofReplay*(
  payload: SemanticEqualityPayload;
  leanArtifactPath: string;
 strategy: SynthesisStrategy = leanstralSynthesisStrategy
): tuple[
  theoremSource: string;
  tacticTrace: seq[string];
  minimalProofPath: seq[string];
  verified: bool;
  rounds: seq[HealingRound];
  feedbackSummary: string;
  failedAttempts: int
] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  let candidateInvariants = buildSemanticCandidateInvariantHints(payload)
  let leanExe = getAxiomEnv(evLeanCmd, "lean")
  let artifactPath =
    try:
      if leanArtifactPath.isAbsolute:
        leanArtifactPath
      else:
        absolutePath(leanArtifactPath)
    except CatchableError:
      leanArtifactPath

  let vaultDir = getAxiomEnv(evVaultDir, axiomVaultDir)
  let synthResult = strategy(payload, artifactPath, leanExe, vaultDir, defaultSynthesisConfig)
  if synthResult.verified:
    return (
      theoremSource: synthResult.theoremSource,
      tacticTrace: synthResult.tacticTrace,
      minimalProofPath: synthResult.minimalProofPath,
      verified: true,
      rounds: synthResult.rounds,
      feedbackSummary: synthResult.feedbackSummary,
      failedAttempts: 0
    )
  result.rounds.add(synthResult.rounds)

  var tacticPlan = buildSemanticProofTacticCandidates(payload, candidateInvariants)
  if tacticPlan.len == 0:
    tacticPlan = @["simp"]
  var attemptedTactics: seq[string] = @[]
  var tacticCursor = 0
  var activeTactic = tacticPlan[0]
  var finalSource = buildSemanticLeanTheoremSource(payload, activeTactic, candidateInvariants)
  var finalSummary = "semantic proof replay not executed"
  var minimalProofPath: seq[string] = minimizeProofPath(activeTactic)
  var failedAttempts = 0
  let maxAttempts = max(3, tacticPlan.len + 2)
  for attempt in 1 .. maxAttempts:
    let minimalTactic = minimizeProofTactic(activeTactic)
    finalSource = buildSemanticLeanTheoremSource(payload, minimalTactic, candidateInvariants)
    var compileResult: LeanCompilerResult
    try:
      compileResult = verifyGeneratedLeanSourceWithCompiler(finalSource, artifactPath, leanExe)
    except CatchableError as e:
      compileResult = LeanCompilerResult(
        verified: false,
        exitCode: -1,
        diagnostics: @[lean_diagnostic.LeanDiagnostic(
          line: 0,
          character: 0,
          severity: 1,
          message: e.msg
        )],
        output: e.msg,
        artifactPath: artifactPath
      )
    let tacticLine = semanticProofTacticLine(finalSource, minimalTactic)
    var liveFeedback: lean_diagnostic.LeanLiveDiagnosticFeedback
    try:
      liveFeedback = getLiveDiagnosticFeedback(
        artifactPath,
        finalSource,
        tacticLine,
        leanExe = leanExe
      )
    except AxiomLspError as e:
      liveFeedback = lean_diagnostic.LeanLiveDiagnosticFeedback(
        line: tacticLine,
        hasErrors: true,
        hasWarnings: false,
        dominantKind: "lsp_unavailable",
        summary: "Lean LSP feedback collection failed. " & e.msg,
        diagnostics: compileResult.diagnostics,
        goals: @[],
        actionableHints: @["Reduce to simpler tactics based on compiler diagnostics."]
      )
    let combinedDiagnostics = mergeLeanDiagnostics(liveFeedback.diagnostics, compileResult.diagnostics)
    liveFeedback.diagnostics = combinedDiagnostics
    liveFeedback.hasErrors = liveFeedback.hasErrors or lean_diagnostic.hasErrors(combinedDiagnostics)
    liveFeedback.hasWarnings = liveFeedback.hasWarnings or combinedDiagnostics.anyIt(it.severity == 2)
    if compileResult.verified:
      liveFeedback.summary = "Lean kernel accepted the replay tactic without contradiction."
      finalSummary = liveFeedback.summary
      attemptedTactics.add(activeTactic)
      minimalProofPath = minimizeProofPath(minimalTactic)
      finalSource = buildSemanticLeanTheoremSource(payload, minimalTactic, candidateInvariants)
      result.rounds.add(HealingRound(
        round: attempt,
        phase: "semantic-proof-replay",
        fixedKinds: @["proof_replay"],
        remainingVulnerabilities: 0,
        feedbackSummary: liveFeedback.summary,
        suggestedTactic: activeTactic,
        diagnosticCount: combinedDiagnostics.len
      ))
      result.verified = true
      break
    failedAttempts.inc()
    if compileResult.diagnostics.len > 0:
      let summaryTokens = tokenizeLowered(liveFeedback.summary)
      let msgTokens = tokenizeLowered(compileResult.diagnostics[0].message)
      var allMsgTokensInSummary = true
      for tok in msgTokens:
        if tok.len > 0 and tok notin summaryTokens:
          allMsgTokensInSummary = false
          break
      if not allMsgTokensInSummary:
        liveFeedback.summary.add(" Compiler: " & compileResult.diagnostics[0].message)
    finalSummary = liveFeedback.summary
    attemptedTactics.add(activeTactic)
    var nextTactic = ""
    try:
      nextTactic = generateContextAwareTactic(
        combinedDiagnostics,
        liveFeedback.goals,
        lean_diagnostic.LeanSpecComplexity(),
        attemptedTactics
      )
    except CatchableError:
      nextTactic = ""
    if not isSemanticReplayTacticCompatible(nextTactic):
      nextTactic = ""
    result.rounds.add(HealingRound(
      round: attempt,
      phase: "semantic-proof-replay",
      fixedKinds: @[],
      remainingVulnerabilities: 1,
      feedbackSummary: liveFeedback.summary,
      suggestedTactic: nextTactic,
      diagnosticCount: combinedDiagnostics.len
    ))
    if nextTactic.len > 0 and not tacticPlan.contains(nextTactic):
      tacticPlan.add(nextTactic)
    while tacticCursor < tacticPlan.len and attemptedTactics.contains(tacticPlan[tacticCursor]):
      tacticCursor.inc()
    if tacticCursor < tacticPlan.len:
      activeTactic = tacticPlan[tacticCursor]
    elif nextTactic.len > 0:
      activeTactic = nextTactic
    else:
      break
  result.theoremSource = finalSource
  result.tacticTrace = attemptedTactics
  result.minimalProofPath = minimalProofPath
  result.feedbackSummary = finalSummary
  result.failedAttempts = failedAttempts

{.pop.}
