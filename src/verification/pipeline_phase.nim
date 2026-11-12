import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/crypto/hash_kernel
import std/strutils
import verification/pipeline_state_types
# axiomIoBoundary

type
  PipelinePhaseKind* = enum
    pkInit
    pkSwatReady        ## Ready to run SWAT (input: SwatArtifact)
    pkDetectiveReady   ## Ready to run Detective (input: DetectiveContext)
    pkLegislatorReady  ## Ready to run Legislator (input: DetectedState)
    pkScribeReady      ## Ready to run Scribe (input: LegislatedState)
    pkJudgeReady       ## Ready to run Judge (input: ScribedState)
    pkPostProcessReady ## Ready to run PostProcess (input: JudgedState)

  PipelinePhase* = object
    ## Current phase of the pipeline, carrying the input artifact for the
    ## stage that is about to execute. Object variant ensures compile-time
    ## exhaustiveness in case handling.
    case kind*: PipelinePhaseKind
    of pkInit:
      discard
    of pkSwatReady:
      swatArt*: SwatArtifact
    of pkDetectiveReady:
      detCtx*: DetectiveContext
    of pkLegislatorReady:
      detected*: DetectedState
    of pkScribeReady:
      legislated*: LegislatedState
    of pkJudgeReady:
      scribed*: ScribedState
    of pkPostProcessReady:
      judged*: JudgedState
func kind*(p: PipelinePhase): PipelinePhaseKind {.raises: [].} =
  p.kind
func swatArt*(p: PipelinePhase): SwatArtifact {.raises: [].} =
  p.swatArt
func detCtx*(p: PipelinePhase): DetectiveContext {.raises: [].} =
  p.detCtx
func detected*(p: PipelinePhase): DetectedState {.raises: [].} =
  p.detected
func legislated*(p: PipelinePhase): LegislatedState {.raises: [].} =
  p.legislated
func scribed*(p: PipelinePhase): ScribedState {.raises: [].} =
  p.scribed
func judged*(p: PipelinePhase): JudgedState {.raises: [].} =
  p.judged

## ─── Constructors ───────────────────────────────────────────────────────────
func toSwatReadyPhase*(swatArt: SwatArtifact): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkSwatReady, swatArt: swatArt)
func toDetectiveReadyPhase*(detCtx: DetectiveContext): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkDetectiveReady, detCtx: detCtx)
func toLegislatorReadyPhase*(detected: DetectedState): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkLegislatorReady, detected: detected)
func toScribeReadyPhase*(legislated: LegislatedState): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkScribeReady, legislated: legislated)
func toJudgeReadyPhase*(scribed: ScribedState): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkJudgeReady, scribed: scribed)
func toPostProcessReadyPhase*(judged: JudgedState): PipelinePhase {.raises: [].} =
  PipelinePhase(kind: pkPostProcessReady, judged: judged)

## ─── Deterministic Fingerprint (Cycle Detection) ────────────────────────────
func fingerprint*(phase: PipelinePhase): string {.raises: [].} =
  ## Deterministic state fingerprint for FSM cycle detection.
  ## Uses SHA-256 for cross-platform determinism.
  var parts: seq[string] = @[$phase.kind]
  case phase.kind
  of pkInit: discard
  of pkSwatReady:
    parts.add($phase.swatArt.logLines.len)
  of pkDetectiveReady:
    parts.add($phase.detCtx.detectiveInput.cegarCounterexample)
  of pkLegislatorReady:
    parts.add($phase.detected.goalDeltas.len)
  of pkScribeReady:
    parts.add($phase.legislated.activeInvariant.len)
  of pkJudgeReady:
    parts.add($phase.scribed.verified)
  of pkPostProcessReady:
    parts.add($phase.judged.finalInvariant.len)
  sha256Hex(parts.join("|"))

## ─── Default Phase Constructor ────────────────────────────────────────────────
func defaultPhase*(kind: PipelinePhaseKind): PipelinePhase {.raises: [].} =
  ## Construct a PipelinePhase with zero-initialized field values.
  ## Used by the FSM loop to advance phases after dispatch.
  case kind
  of pkInit: PipelinePhase(kind: pkInit)
  of pkSwatReady: toSwatReadyPhase(default(SwatArtifact))
  of pkDetectiveReady: toDetectiveReadyPhase(default(DetectiveContext))
  of pkLegislatorReady: toLegislatorReadyPhase(default(DetectedState))
  of pkScribeReady: toScribeReadyPhase(default(LegislatedState))
  of pkJudgeReady: toJudgeReadyPhase(default(ScribedState))
  of pkPostProcessReady: toPostProcessReadyPhase(default(JudgedState))
{.pop.}
