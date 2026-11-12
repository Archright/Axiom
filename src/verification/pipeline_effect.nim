import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/lean_lsp_types
import core/solver/solver_bridge
import std/options
import verification/pipeline_state_types
# axiomIoBoundary

type
  DispatchTarget* = enum
    ## Which persona dispatch is required.
    dtSwat         ## Dispatch to swat.executeRaid
    dtDetective    ## Dispatch to detective.openCase
    dtLegislator   ## Dispatch to legislator.legislate or legislator_feedback
    dtScribe       ## Dispatch to scribe.synthesizeLeanTheorem
    dtJudge        ## Dispatch to judge.certify
    dtPostProcess  ## Dispatch to detective.investigate

  DispatchResult* = object
    ## Typed artifacts produced by external persona dispatch.
    ## Object variant ensures compile-time exhaustiveness.
    case target*: DispatchTarget
    of dtSwat:
      swatArt*: SwatArtifact
      swatOutcome*: Option[SwatStageOutcome]
    of dtDetective:
      caseArt*: DetectiveArtifact
    of dtLegislator:
      draftArt*: LegislatorArtifact
    of dtScribe:
      scribeArt*: ScribeArtifact
    of dtJudge:
      judgeArt*: JudgeArtifact
    of dtPostProcess:
      postArt*: DetectiveArtifact  ## detective.investigate returns DetectiveArtifact

  PipelineEffectKind* = enum
    peNone     ## No external effect; pure computation only
    peDispatch ## Requires persona dispatch before continuing

  DispatchContext* = object
    ## Sealed ADT carrying exactly the data a dispatch target needs.
    ## Loop accumulator snapshots (stagnationEscalated, goalDeltas) are stored
    ## as common fields so multiple targets (Legislator, Judge) can read them
    ## without duplicating field names across variant branches.
    case target*: DispatchTarget
    of dtSwat:
      swatArt*: SwatArtifact
    of dtDetective:
      detCtx*: DetectiveContext
    of dtLegislator:
      detected*: DetectedState
      currentDeltas*: seq[GoalDelta]
    of dtScribe:
      legislated*: LegislatedState
      kInductionPayload*: KInductionResult
    of dtJudge:
      scribed*: ScribedState
    of dtPostProcess:
      judged*: JudgedState
    stagnationEscalated*: bool
    goalDeltas*: seq[GoalDelta]

  PipelineEffect* = object
    ## Description of an external interaction required by a stage.
    case kind: PipelineEffectKind
    of peNone:
      discard
    of peDispatch:
      target: DispatchTarget
      ## Serialized input for the dispatch target.
      ## The orchestrator is responsible for deserialization and routing.
      requiredInput: string
func dispatchTarget*(dr: DispatchResult): DispatchTarget {.raises: [].} =
  dr.target
func swatArt*(dr: DispatchResult): SwatArtifact {.raises: [].} =
  dr.swatArt
func caseArt*(dr: DispatchResult): DetectiveArtifact {.raises: [].} =
  dr.caseArt
func draftArt*(dr: DispatchResult): LegislatorArtifact {.raises: [].} =
  dr.draftArt
func scribeArt*(dr: DispatchResult): ScribeArtifact {.raises: [].} =
  dr.scribeArt
func judgeArt*(dr: DispatchResult): JudgeArtifact {.raises: [].} =
  dr.judgeArt
func postArt*(dr: DispatchResult): DetectiveArtifact {.raises: [].} =
  dr.postArt
func effectKind*(pe: PipelineEffect): PipelineEffectKind {.raises: [].} =
  pe.kind
func effectTarget*(pe: PipelineEffect): DispatchTarget {.raises: [].} =
  pe.target
func effectInput*(pe: PipelineEffect): string {.raises: [].} =
  pe.requiredInput
func noEffect*(): PipelineEffect {.raises: [].} =
  ## Convenience constructor for peNone.
  PipelineEffect(kind: peNone)
func dispatchEffect*(target: DispatchTarget; input: string = ""): PipelineEffect {.raises: [].} =
  ## Convenience constructor for peDispatch.
  PipelineEffect(kind: peDispatch, target: target, requiredInput: input)
{.pop.}
