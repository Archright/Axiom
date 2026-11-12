import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/asyncdispatch
import std/asyncfutures
import std/json
import std/os
import std/sequtils
import std/strformat
import std/strutils
import core/lean_lsp_types
import verification/lean_lsp_client
import verification/lean_lsp_feedback
import verification/lean_lsp_tactic
import verification/tactic_backtrack
import verification/unified_trajectory
import core/utils/file_utils
import core/utils/text_utils
import core/runtime_context
import core/logic/lean_diagnostic
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

proc runDynamicProofSearch*(
 specPath: string = "";
  workPath: string = "";
  corePath: string = "";
  theoremName: string = "ai_generated_balance_never_negative";
  leanExe: string = "";
  maxAttempts: int = 6
): Future[LeanSearchResult] {.async, warning[BareExcept]: off, raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  var result = LeanSearchResult(
    succeeded: false,
    attempts: 0,
    finalTactic: "",
    reason: "",
    diagnostics: @[],
    goals: @[],
    tacticTrace: @[],
    hypothesisSuggestions: @[],
    proofVaultArtifact: ""
  )
  ## Tactic Backtrack Engine: snapshot store for goal-aware proof search
  var snapshotStore = initSnapshotStore("logs/tactic_snapshots")
  var snapshots: seq[TacticSnapshot] = @[]
  var previousGoals: seq[string] = @[]
  
  let resolvedSpecPath =
    if specPath.len > 0: specPath
    else: joinPath("src", "verification", "spec.lean")
  let resolvedWorkPath =
    if workPath.len > 0: workPath
    else: joinPath("src", "verification", "proof_search_attempt.lean")
  let resolvedCorePath =
    if corePath.len > 0: corePath
    else: joinPath("src", "core")
  if not fileExists(resolvedSpecPath):
    result.diagnostics = @[LeanDiagnostic(line: 0, character: 0, severity: 1, message: "missing spec file")]
    return result
  if not dirExists(resolvedCorePath):
    result.diagnostics = @[LeanDiagnostic(line: 0, character: 0, severity: 1, message: "missing core directory")]
    return result
  let baseSpec = readFileSafe(resolvedSpecPath)
  let generatedSpec = appendGeneratedCoreSpec(baseSpec, resolvedCorePath)
  let complexity = analyzeSpecComplexity(generatedSpec.source)
  if generatedSpec.structureCount == 0 and generatedSpec.enumCount == 0 and generatedSpec.functionCount == 0:
    result.diagnostics = @[LeanDiagnostic(line: 0, character: 0, severity: 1, message: "core parse produced empty specification")]
    return result
  let generatedSpecArtifact = writeGeneratedSpecArtifact(generatedSpec.source)
  logStage(skScribe, "spec-generator",
    "structures=" & $generatedSpec.structureCount & " enums=" & $generatedSpec.enumCount &
    " functions=" & $generatedSpec.functionCount,
    extra = %*{
      "corePath": resolvedCorePath,
      "untrustedFunctionCount": generatedSpec.untrustedFunctionCount,
      "warnings": generatedSpec.warnings,
      "complexitySummary": complexity.summary,
      "complexityFingerprint": complexity.fingerprint,
      "generatedSpecArtifact": generatedSpecArtifact,
      "generatedSpecLength": generatedSpec.source.len
    })
  for warning in generatedSpec.warnings:
    logWarn("lean_lsp_proof_search", "[spec][warning] " & warning)
  var ctx = newVerificationRuntimeContext()
  var client = ctx.startLeanLsp(leanExe)
  if not (await client.initialize(getCurrentDir())):
    client.shutdown(ctx)
    result.diagnostics = @[LeanDiagnostic(line: 0, character: 0, severity: 1, message: "lean lsp initialize failed")]
    return result
  
  var tacticPlan = buildInitialTacticStrategy(complexity)
  let warmStartTactics = loadWarmStartTactics(theoremName, complexity)
  for idx in countdown(warmStartTactics.high, 0):
    if not tacticPlan.contains(warmStartTactics[idx]):
      tacticPlan.insert(warmStartTactics[idx], 0)
  if tacticPlan.len == 0:
    tacticPlan = @["omega"]
  var tacticCursor = 0
  var tactic = tacticPlan[tacticCursor]
  var tacticHistory: seq[string] = @[]
  for i in 1 .. maxAttempts:
    let source = theoremSource(generatedSpec.source, theoremName, tactic)
    discard writeFileSafe(resolvedWorkPath, source)
    
    # 2. JSON-RPC sequence integrity: initialize context with didOpen on new attempt
    client.openDocument(resolvedWorkPath, source)
    
    try:
      let feedback = await collectFeedbackWithHardTimeout(
        client,
        lineOfTactic(source, tactic),
        computeProofAttemptTimeoutMs(complexity, i)
      )
      result.attempts = i
      result.finalTactic = tactic
      result.reason = ""
      result.diagnostics = feedback.diagnostics
      result.goals = feedback.goals
      tacticHistory.add(tactic)
      result.tacticTrace = tacticHistory
      
      ## Tactic Backtrack: compute Goal Delta and create snapshot
      let goalDelta = computeGoalDelta(previousGoals, feedback.goals)
      let succeeded = not hasErrors(feedback.diagnostics)
      var hypothesesBefore: seq[string] = @[]
      for hyp in feedback.goals:
        if not hyp.startsWith("⊢"):
          hypothesesBefore.add hyp
      let snapshot = TacticSnapshot(
        index: i - 1,
        goalBefore: previousGoals,
        hypothesesBefore: hypothesesBefore,
        tacticApplied: tactic,
        goalAfter: feedback.goals,
        diagnostic: if feedback.diagnostics.len > 0: feedback.diagnostics[0]
                    else: LeanDiagnostic(),
        sourceHash: "",
        succeeded: succeeded,
        goalDelta: goalDelta
      )
      snapshots.add(snapshot)
      snapshotStore.store(snapshot)
      previousGoals = feedback.goals
      
      logInfo("lean_lsp_proof_search", fmt"[backtrack][attempt {i}] delta: resolved={goalDelta.resolvedGoals.len} new={goalDelta.newGoals.len} unchanged={goalDelta.unchangedGoals.len}")
      
      ## Global Reset check: detect labyrinth and jump back
      let (resetTrigger, resetIdx) = shouldReset(snapshots, i, maxAttempts - i, maxAttempts)
      if resetTrigger != grtNone:
        logInfo("lean_lsp_proof_search", fmt"[backtrack][RESET] trigger={resetTrigger} jumping to snapshot {resetIdx}")
        if resetIdx >= 0 and resetIdx < snapshots.len:
          let resetSnap = snapshots[resetIdx]
          previousGoals = resetSnap.goalBefore
          # Clear tactic history from the reset point onward to allow re-exploration
          while tacticHistory.len > resetIdx + 1:
            discard tacticHistory.pop()
      let hypothesisSuggestions = inferMissingHypotheses(feedback.diagnostics, feedback.goals)
      result.hypothesisSuggestions = hypothesisSuggestions
      logInfo("lean_lsp_proof_search", fmt"[lsp][attempt {i}] tactic={tactic}")
      for event in feedback.events:
        logInfo("lean_lsp_proof_search", "[lsp] " & event)
      for goal in feedback.goals:
        logInfo("lean_lsp_proof_search", "[lsp][goal] " & goal)
      for suggestion in hypothesisSuggestions:
        logInfo("lean_lsp_proof_search", "[lsp][suggestion] " & suggestion)
      logStage(skScribe, theoremName,
        "attempt=" & $i & " tactic=" & tactic,
        extra = %*{
          "attempt": i,
          "tactic": tactic,
          "complexityFingerprint": complexity.fingerprint,
          "diagnostics": feedback.diagnostics.mapIt(%*{
            "line": it.line,
            "character": it.character,
            "severity": it.severity,
            "message": it.message
          }),
          "goals": feedback.goals,
          "hypothesisSuggestions": hypothesisSuggestions,
          "goalDelta": {
            "resolved": goalDelta.resolvedGoals,
            "newGoals": goalDelta.newGoals,
            "unchanged": goalDelta.unchangedGoals,
            "isProgressive": isProgressive(goalDelta),
            "isDestructive": isDestructive(goalDelta)
          },
          "resetTrigger": $resetTrigger
        })
      if not hasErrors(feedback.diagnostics):
        result.succeeded = true
        result.proofVaultArtifact = saveProofVaultArtifact(
          theoremName = theoremName,
          complexity = complexity,
          attempts = i,
          tactics = tacticHistory,
          goals = feedback.goals
        )
        logStage(skScribe, theoremName, "succeeded on attempt " & $i,
          status = ssSucceeded,
          extra = %*{"attempt": i, "tactic": tactic, "proofVaultArtifact": result.proofVaultArtifact})
        break
      let adaptiveTactic = generateContextAwareTactic(
        feedback.diagnostics,
        feedback.goals,
        complexity,
        tacticHistory
      )
      if adaptiveTactic.len > 0 and not tacticPlan.contains(adaptiveTactic):
        tacticPlan.add(adaptiveTactic)
      while tacticCursor < tacticPlan.len and tacticHistory.contains(tacticPlan[tacticCursor]):
        inc tacticCursor
      if tacticCursor < tacticPlan.len:
        tactic = tacticPlan[tacticCursor]
      else:
        tactic = adaptiveTactic
    except IOError as e:
      # 1. Async session timeout feedback transmission
      logError("lean_lsp_proof_search", "[lsp][error] " & e.msg)
      let msgTokens = tokenizeLowered(e.msg)
      result.reason =
        if "timeout_exceeded" in msgTokens or "lsp_timeout_error" in msgTokens: "timeout_exceeded"
        else: "io_error"
      result.diagnostics.add(LeanDiagnostic(line: 0, character: 0, severity: 1, message: e.msg))
      logStage(skScribe, theoremName, "attempt=" & $i & " " & result.reason & ": " & e.msg,
        status = if result.reason == "timeout_exceeded": ssTimeout else: ssFailed,
        extra = %*{"attempt": i, "error": e.msg})
      if result.reason == "timeout_exceeded":
        try: killProcessTree(client.p) except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      # On timeout, terminate to request simpler tactic from AI
      break
    except CatchableError as e:
      logInfo("lean_lsp_proof_search", "[lsp][fatal] " & e.msg)
      result.reason = "fatal_error"
      logStage(skScribe, theoremName, "attempt=" & $i & " fatal: " & e.msg,
        status = ssFailed,
        extra = %*{"attempt": i, "error": e.msg})
      break
    
    await sleepAsync(500)
    
  client.shutdown(ctx)
  result




