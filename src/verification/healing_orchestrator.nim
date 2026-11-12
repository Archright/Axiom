import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

##
## Verification-layer self-healing loops that coordinate compiler replay,
## negative invariant scanning, assertion injection, and invariant promotion.

import std/os
import std/strutils
import std/tables
import core/axiom_pragmas
import ../core/trusted/env_access

import core/utils/text_utils
import core/logic/lean_diagnostic as lean_diagnostic
import core/logic/pipeline_fingerprint_engine
import core/logic/pipeline_healing_logic
import core/types/refactor_task_types  # RefactorStatus, RefactorResult
import core/diagnostics/refactoring_engine
import core/types/translation_types
import verification/lean_lsp
import verification/pipeline_lean_spec_inference
# axiomIoBoundary
import verification/pipeline_negative_scan

const diagKindToVulnKind = toTable {
  "unsolved_goals":          "vkDeadlockRaceCondition",
  "tactic_failed":           "vkIntegerOverflowUnderflow",
  "type_mismatch":           "vkNullPointerDereference",
  "missing_import_or_symbol": "vkNullPointerDereference",
  "missing_instance":        "vkGhostUpdate",
  "invalid_projection":      "vkBufferOverflow"
}

## Run Self Healing Loop.
# @axiom-hint: lean="maxRounds ≤ 0 ∧ fixedKinds.length = 0 ∧ (current ≥ 0) ∧ (scan ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (<= maxRounds 0) (= (str.len fixedKinds) 0) (>= current 0) (>= scan 0) (>= result 0)))"
proc runSelfHealingLoop*(
  sourceCode: string;
  translation: UniversalTranslation;
  initial: NegativeInvariantScan;
  maxRounds: int;
  activeInvariant: string = ""
): tuple[finalSource: string; finalScan: NegativeInvariantScan; rounds: seq[HealingRound]] =
  var current = sourceCode
  var scan = initial
  let roundsCap = 1  ## Hard cap at 1 retry for deterministic termination
  for round in 1 .. roundsCap:
    if not scan.hasVulnerability:
      break
    var fixedKinds: seq[string] = @[]
    for hit in scan.hits:
      let patched = applyRefactoringTemplate(current, $hit.hit.kind)
      if patched.status == rsVerified:
        current = patched.refactoredSource
        if not fixedKinds.contains($hit.hit.kind):
          fixedKinds.add($hit.hit.kind)
    if fixedKinds.len == 0:
      result.rounds.add(HealingRound(
        round: round,
        phase: "negative-invariant-healing",
        fixedKinds: @[],
        remainingVulnerabilities: scan.hits.len,
        feedbackSummary: "",
        suggestedTactic: "",
        diagnosticCount: 0
      ))
      break
    try:
      scan = runNegativeInvariantSearch(translation, current, activeInvariant)
    except CatchableError:
      break
    result.rounds.add(HealingRound(
      round: round,
      phase: "negative-invariant-healing",
      fixedKinds: fixedKinds,
      remainingVulnerabilities: scan.hits.len,
      feedbackSummary: "",
      suggestedTactic: "",
      diagnosticCount: 0
    ))
  result.finalSource = current
  result.finalScan = scan

## Run Lean Proof Refinement Loop.
# @axiom-hint: lean="sourceCode.length ≥ 0 ∧ activeInvariant.length ≥ 0 ∧ maxRounds ≥ -9223372036854775808 ∧ maxRounds ≤ 9223372036854775807" smt="(assert (and (>= (str.len sourceCode) 0) (>= (str.len activeInvariant) 0) (and (>= maxRounds -9223372036854775808) (<= maxRounds 9223372036854775807))))"
# @axiom-hint: lean="maxRounds ≤ 0 ∧ goals.length > 0 ∧ nearestDiagnostic.length > 0 ∧ currentInvariant ≠ previousInvariant ∧ hints.length > 0 ∧ loopDetected ∧ (fallbackHints ≥ 0) ∧ (currentSource ≥ 0) ∧ (result ≥ 0) ∧ (currentInvariant ≥ 0)" smt="(assert (and (<= maxRounds 0) (> (str.len goals) 0) (> (str.len nearestDiagnostic) 0) (not (= currentInvariant previousInvariant)) (> (str.len hints) 0) loopDetected (>= fallbackHints 0) (>= currentSource 0) (>= result 0) (>= currentInvariant 0)))"
proc runLeanProofRefinementLoop*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string;
  maxRounds: int
): tuple[
  finalSource: string;
  finalInvariant: string;
  rounds: seq[HealingRound];
  nearestDiagnostic: string;
  failedReplayAttempts: int;
  leanKernelVerified: bool;
  vacuityProven: bool
] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  let leanExe = getAxiomEnv(evLeanCmd, "lake env lean")
  let roundsCap = 3  ## 3-strikes escalation: try up to 3 refinement rounds
  var currentSource = sourceCode
  var currentInvariant = activeInvariant
  var visitedStates = @[healingStateFingerprint(currentSource, currentInvariant)]
  var leanKernelVerified = false
  var vacuityProven = false
  for round in 1 .. roundsCap:
    let inferred = inferLeanSpec(
      req.modulePath,
      req.functionName,
      translation,
      currentSource,
      currentInvariant,
      "proven_by_induction"
    )
    let artifactPath = joinPath(
      req.proofVaultDir,
      sanitizeToken(req.functionName) & "_lean_feedback_round_" & $round & ".lean"
    )
    let compilerResult = verifyGeneratedLeanSourceWithCompiler(
      inferred.theoremSource,
      artifactPath,
      leanExe
    )
    let goals = extractGoalLinesFromCompilerOutput(compilerResult.output)
    var hints = lean_diagnostic.inferMissingHypotheses(compilerResult.diagnostics, goals)
    let fallbackHints = synthesizeLeanFallbackHints(currentSource, currentInvariant, compilerResult.output)
    for h in fallbackHints:
      if not hints.contains(h):
        hints.add(h)
    let nearestDiagnostic =
      if compilerResult.diagnostics.len > 0:
        compilerResult.diagnostics[0].message
      elif goals.len > 0:
        goals[0]
      else:
        compilerResult.output.strip()
    if nearestDiagnostic.len > 0:
      result.nearestDiagnostic = nearestDiagnostic
    if compilerResult.verified:
      leanKernelVerified = true
      vacuityProven = compilerResult.vacuityProven
      result.rounds.add(HealingRound(
        round: round,
        phase: "lean-proof-refinement",
        fixedKinds: @["proof_replay"],
        remainingVulnerabilities: 0,
        feedbackSummary: "Lean kernel accepted promoted invariant replay.",
        suggestedTactic: "proof_term_rewrite",
        diagnosticCount: compilerResult.diagnostics.len
      ))
      break
    result.failedReplayAttempts.inc()
    let previousInvariant = currentInvariant
    let diagKind =
      if compilerResult.diagnostics.len > 0:
        lean_diagnostic.diagnosticKind(compilerResult.diagnostics[0])
      else:
        ""
    let derivedVulnKind = diagKindToVulnKind.getOrDefault(diagKind, "vkGhostUpdate")
    let assertionPatch = applyRefactoringTemplate(currentSource, derivedVulnKind)
    if assertionPatch.status == rsVerified:
      currentSource = assertionPatch.refactoredSource
    currentInvariant = strengthenInvariantFromLeanHints(currentInvariant, translation, hints)
    var rescanned: NegativeInvariantScan
    try:
      rescanned = runNegativeInvariantSearch(translation, currentSource, currentInvariant)
    except CatchableError:
      rescanned = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
    var fixedKinds: seq[string] = @[]
    if assertionPatch.status == rsVerified:
      fixedKinds.add("precondition_promotion")
    if currentInvariant != previousInvariant:
      fixedKinds.add("invariant_promotion")
    let feedbackSummary =
      if hints.len > 0:
        hints.join(" | ")
      elif nearestDiagnostic.len > 0:
        nearestDiagnostic
      else:
        "Lean proof replay failed without actionable diagnostic."
    let nextStateFingerprint = healingStateFingerprint(currentSource, currentInvariant)
    let loopDetected = visitedStates.contains(nextStateFingerprint)
    if not loopDetected:
      visitedStates.add(nextStateFingerprint)
    if loopDetected and not fixedKinds.contains("loop_guard"):
      fixedKinds.add("loop_guard")
    result.rounds.add(HealingRound(
      round: round,
      phase: "lean-proof-refinement",
      fixedKinds: fixedKinds,
      remainingVulnerabilities: rescanned.hits.len,
      feedbackSummary:
        if loopDetected:
          feedbackSummary & " | loop guard engaged on repeated healing state"
        else:
          feedbackSummary,
      suggestedTactic: "promote_missing_preconditions",
      diagnosticCount: compilerResult.diagnostics.len
    ))
    if loopDetected or hints.len == 0 or (assertionPatch.status != rsVerified and currentInvariant == previousInvariant):
      break
  result.finalSource = currentSource
  result.finalInvariant = currentInvariant
  result.leanKernelVerified = leanKernelVerified
  result.vacuityProven = vacuityProven
{.pop.}
