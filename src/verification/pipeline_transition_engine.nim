import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/domain_types
import core/integrity/integrity_refinement_types
import core/orchestration/pipeline_config
import core/orchestration/pipeline_types
import core/pipeline_core_types
import std/options
import std/strutils
import verification/pipeline_effect
import verification/pipeline_phase
import verification/pipeline_stage_detective
import verification/pipeline_stage_judge
import verification/pipeline_stage_legislator
import verification/pipeline_stage_postprocess
import verification/pipeline_stage_scribe
import verification/pipeline_state_types
import verification/pipeline_transition
## Compile-time Command→Phase mapping. Missing entry = compile error.
## Context7-verified: array[EnumType, T] enforces exhaustiveness at compile time.
const PhaseMapping*: array[PipelineCommand, PipelinePhaseKind] = [
  cmdRequireSwat:        pkSwatReady,
  cmdRequireDetective:   pkDetectiveReady,
  cmdRequireLegislator:  pkLegislatorReady,
  cmdRequireScribe:      pkScribeReady,
  cmdRequireJudge:       pkJudgeReady,
  cmdRequirePostProcess: pkPostProcessReady,
  cmdPipelineComplete:   pkPostProcessReady,
]

static:
  doAssert PhaseMapping.len == ord(high(PipelineCommand)) + 1,
    "PhaseMapping: every PipelineCommand must have a corresponding PipelinePhaseKind"
func registryContains(registry: InvariantRegistry; id: string): bool {.raises: [].} =
  ## Check whether an invariant with the given id is present in the registry.
  for i in 0 ..< registry.count:
    if registry.entries[i].id == id:
      return true
  return false

# ---------------------------------------------------------------------------
# Phase 4 Helpers — CEGAR Skip
# ---------------------------------------------------------------------------
func extractInvariantFromSmtlib2(smtlib2: string): string {.raises: [].} =
  ## Extract proved invariant assertions from SMT-LIB2 encoding.
  ## Returns a human-readable invariant string joined by ∧.
  ## Used when CEGAR proves and Legislator is skipped.
  var parts: seq[string] = @[]
  for line in smtlib2.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("(assert ") and trimmed.endsWith(")"):
      parts.add(trimmed.substr(8, trimmed.len - 2))
  if parts.len == 0:
    return smtlib2  ## Fallback: return raw SMT-LIB2 if no assertions found
  parts.join(" ∧ ")

# ---------------------------------------------------------------------------
# FSM Transition
# ---------------------------------------------------------------------------
func transition*(
  phase: PipelinePhase;
  input: PipelineInput;
  config: PipelineConfig;
  accum: LoopAccumulators;
  dispatchRes: Option[DispatchResult]
): (Transition2, LoopAccumulators) {.raises: [].} =
  ## FSM state transition. Returns (Transition, updated accumulators).
  ## Context7-verified: tuple return is move-optimized by ARC/ORC (=sink rewrite).

  case phase.kind
  of pkInit:
    return (suspendTrans(cmdRequireSwat), accum)

  of pkSwatReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let swatOutcome = dispatchRes.get().swatOutcome
    if swatOutcome.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let outcome = swatOutcome.get()
    case outcome.kind
    of ssrBmcSuccess:
      return (terminalOkTrans(outcome.pipelineResult), accum)
    of ssrFallbackRequired:
      var nextAccum = accum
      nextAccum.kInductionPayload = outcome.kInductionResult
      return (suspendTrans(cmdRequireDetective), nextAccum)

  of pkDetectiveReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let caseArt = dispatchRes.get().caseArt
    let detected = runDetectiveStage(input, caseArt, @[], accum.goalDeltas)
    var nextAccum = accum
    nextAccum.detected = detected
    # Phase 4: Skip Legislator when CEGAR proves with invariants.
    # When CEGAR reaches a fixed-point (cegarProven) and has proved invariants,
    # the invariant is already mathematically verified by Z3. The Legislator's
    # LLM-based invariant drafting is redundant in this case.
    if not caseArt.cegarCounterexample and caseArt.cegarSmtlib2.len > 0:
      let cegarInvariant = extractInvariantFromSmtlib2(caseArt.cegarSmtlib2)
      nextAccum.legislated = toLegislatedState(
        detected,
        baselineInvariant = cegarInvariant,
        refinedInvariant = cegarInvariant,
        activeInvariant = cegarInvariant,
        healedSource = input.req.sourceCode,
        evolutionReasoning = "CEGAR proved — Legislator skipped",
        logLines = @["[CEGAR-Skip] Invariant proved by CEGAR, bypassing Legislator"]
      )
      return (suspendTrans(cmdRequireScribe), nextAccum)
    # Normal flow: delegate to Legislator for LLM-based invariant drafting
    return (suspendTrans(cmdRequireLegislator), nextAccum)

  of pkLegislatorReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let draftArt = dispatchRes.get().draftArt
    let healedSource = input.req.sourceCode
    let legislated = runLegislatorStage(accum.detected, draftArt, healedSource)
    var nextAccum = accum
    if draftArt.activeInvariant.len > 0:
      # Phase 2a: active invariant must be registered before Detective→Legislator transition
      if not registryContains(nextAccum.globalRegistry, draftArt.activeInvariant):
        return (terminalErrTrans(axiomErrInconsistentState), nextAccum)
    nextAccum.legislated = legislated
    return (suspendTrans(cmdRequireScribe), nextAccum)

  of pkScribeReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let scribeArt = dispatchRes.get().scribeArt
    let scribed = runScribeStage(accum.legislated, scribeArt, accum.kInductionPayload)
    var nextAccum = accum
    nextAccum.scribed = scribed
    return (suspendTrans(cmdRequireJudge), nextAccum)

  of pkJudgeReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let judgeArt = dispatchRes.get().judgeArt
    let judged = runJudgeStage(accum.scribed, judgeArt)
    var nextAccum = accum
    if judgeArt.leanKernelVerified:
      # Phase 2b invariant: verified judgment must produce a non-empty certificate
      if judgeArt.proofArtifact.nodeId.len == 0:
        return (terminalErrTrans(axiomErrInconsistentState), nextAccum)
    nextAccum.judged = judged
    return (suspendTrans(cmdRequirePostProcess), nextAccum)

  of pkPostProcessReady:
    if dispatchRes.isNone:
      return (terminalErrTrans(axiomErrInconsistentState), accum)
    let postArt = dispatchRes.get().postArt
    let postProcessed = runPostProcessStage(accum.judged, postArt)
    return (terminalOkTrans(postProcessed), accum)
{.pop.}
