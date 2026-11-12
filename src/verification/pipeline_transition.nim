import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## PipelineTransition — Pure control-flow result for defunctionalized stages.
##
## Closed-world: a stage either produces the next state or terminates.
## This type never grows with new effects (retry, user input, etc.).
## Effect handling is the responsibility of PipelineEffect (open-world).

import std/options
import core/domain_types
import core/pipeline_core_types
import verification/pipeline_phase
import verification/pipeline_effect
import core/contracts/universal_pipeline_contract
# axiomIoBoundary

type
  TransitionKind* = enum
    tkNext     ## Stage produced a valid next state; pipeline continues
    tkTerminal ## Pipeline complete (success or failure)

  Transition*[T] = object
    ## Pure result of a pipeline stage. Carries either the next typed state
    ## or terminal information. Zero side effects.
    case kind: TransitionKind
    of tkNext:
      nextState: T
    of tkTerminal:
      finalResult: Option[UniversalPipelineResult]
      error: Option[AxiomError]

func transitionKind*[T](t: Transition[T]): TransitionKind {.raises: [].} =
  t.kind

func nextState*[T](t: Transition[T]): T {.raises: [].} =
  t.nextState

func finalResult*[T](trans: Transition[T]): Option[UniversalPipelineResult] {.raises: [].} =
  trans.finalResult

func terminalError*[T](trans: Transition[T]): Option[AxiomError] {.raises: [].} =
  trans.error

func next*[T](state: T): Transition[T] {.raises: [].} =
  ## Convenience constructor for tkNext.
  Transition[T](kind: tkNext, nextState: state)

func terminalOk*(res: UniversalPipelineResult): Transition[int] {.raises: [].} =
  ## Convenience constructor for successful termination.
  ## Uses int as dummy type parameter (void not allowed in object variants).
  Transition[int](kind: tkTerminal, finalResult: some(res), error: none(AxiomError))

func terminalErr*(err: AxiomError): Transition[int] {.raises: [].} =
  ## Convenience constructor for failed termination.
  ## Uses int as dummy type parameter (void not allowed in object variants).
  Transition[int](kind: tkTerminal, finalResult: none(UniversalPipelineResult), error: some(err))

# ─── Non-generic Transition for FSM Engine ──────────────────────────────────

type
  TransitionKind2* = enum
    tk2Continue  ## Move to next phase immediately
    tk2Suspend   ## Requires external persona dispatch
    tk2Terminal  ## Pipeline finished

  Transition2* = object
    ## Non-generic transition for the FSM engine.
    case kind*: TransitionKind2
    of tk2Continue:
      nextPhase*: PipelinePhase
    of tk2Suspend:
      cmd*: PipelineCommand
      dispatchCtx*: DispatchContext
    of tk2Terminal:
      finalResult*: Option[UniversalPipelineResult]
      finalError*: Option[AxiomError]

func transition2Kind*(t: Transition2): TransitionKind2 {.raises: [].} =
  t.kind

func nextPhase*(t: Transition2): PipelinePhase {.raises: [].} =
  t.nextPhase

func suspendCmd*(t: Transition2): PipelineCommand {.raises: [].} =
  t.cmd

func terminalResult*(t: Transition2): Option[UniversalPipelineResult] {.raises: [].} =
  t.finalResult

func terminalError*(t: Transition2): Option[AxiomError] {.raises: [].} =
  t.finalError

func continueTrans*(nextPhase: PipelinePhase): Transition2 {.raises: [].} =
  Transition2(kind: tk2Continue, nextPhase: nextPhase)

func suspendTrans*(cmd: PipelineCommand; dispatchCtx: DispatchContext = DispatchContext()): Transition2 {.raises: [].} =
  Transition2(kind: tk2Suspend, cmd: cmd, dispatchCtx: dispatchCtx)

func terminalOkTrans*(res: UniversalPipelineResult): Transition2 {.raises: [].} =
  Transition2(kind: tk2Terminal, finalResult: some(res), finalError: none(AxiomError))

func terminalErrTrans*(err: AxiomError): Transition2 {.raises: [].} =
  Transition2(kind: tk2Terminal, finalResult: none(UniversalPipelineResult), finalError: some(err))

{.pop.}
