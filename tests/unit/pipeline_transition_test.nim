## pipeline_transition_test.nim
## Semantic assertion tests for pipeline_transition.nim — the FSM transition layer.
##
## Coverage:
##   - Generic Transition[T]: next(), terminalOk(), terminalErr()
##   - Non-generic Transition2: continueTrans(), suspendTrans(), terminalOkTrans(), terminalErrTrans()
##   - Query/accessor round-trips for both types
##   - All TransitionKind2 variants verified

import std/[unittest, options]
import verification/pipeline_transition
import verification/pipeline_phase
import verification/pipeline_effect
import verification/pipeline_state_types
import core/types/domain_types
import core/types/pipeline_core_types
import core/contracts/universal_pipeline_contract
import core/boundary/persona_interface

# ─── Helpers ──────────────────────────────────────────────────────────────────

func dummySwatPhase(): PipelinePhase =
  toSwatReadyPhase(default(SwatArtifact))

func dummyDetectivePhase(): PipelinePhase =
  toDetectiveReadyPhase(default(DetectiveContext))

# ─── Generic Transition[T] ────────────────────────────────────────────────────

suite "Transition[T] — generic pipeline transition":

  test "next() produces tkNext with correct state":
    let t = next(42)
    check t.transitionKind() == tkNext
    check t.nextState() == 42

  test "next() with string state":
    let t = next("hello")
    check t.transitionKind() == tkNext
    check t.nextState() == "hello"

  test "terminalOk() produces tkTerminal with result and no error":
    let res = default(UniversalPipelineResult)
    let t = terminalOk(res)
    check t.transitionKind() == tkTerminal
    check t.finalResult().isSome
    check t.terminalError().isNone

  test "terminalErr() produces tkTerminal with error and no result":
    let t = terminalErr(axiomErrInconsistentState)
    check t.transitionKind() == tkTerminal
    check t.finalResult().isNone
    check t.terminalError().isSome
    check t.terminalError().get() == axiomErrInconsistentState

  test "terminalOk round-trip — result matches input":
    let res = default(UniversalPipelineResult)
    let t = terminalOk(res)
    check t.finalResult().get().healedSource == res.healedSource

  test "terminalErr round-trip — error enum preserved":
    for err in [axiomErrSchemaVersionUnsupported, axiomErrFileSystemError,
                axiomErrNetworkFailure]:
      let t = terminalErr(err)
      check t.terminalError().get() == err

# ─── Non-generic Transition2 ──────────────────────────────────────────────────

suite "Transition2 — FSM engine transition":

  test "continueTrans produces tk2Continue":
    let phase = dummySwatPhase()
    let t = continueTrans(phase)
    check t.transition2Kind() == tk2Continue

  test "continueTrans carries the next phase":
    let phase = dummySwatPhase()
    let t = continueTrans(phase)
    check t.nextPhase().kind == pkSwatReady

  test "continueTrans with each phase kind":
    let phases = [
      PipelinePhase(kind: pkInit),
      dummySwatPhase(),
      dummyDetectivePhase(),
      toLegislatorReadyPhase(default(DetectedState)),
      toScribeReadyPhase(default(LegislatedState)),
      toJudgeReadyPhase(default(ScribedState)),
      toPostProcessReadyPhase(default(JudgedState)),
    ]
    let expectedKinds = [
      pkInit, pkSwatReady, pkDetectiveReady, pkLegislatorReady,
      pkScribeReady, pkJudgeReady, pkPostProcessReady,
    ]
    for i in 0..<phases.len:
      let t = continueTrans(phases[i])
      check t.transition2Kind() == tk2Continue
      check t.nextPhase().kind == expectedKinds[i]

  test "suspendTrans produces tk2Suspend":
    let t = suspendTrans(cmdRequireDetective)
    check t.transition2Kind() == tk2Suspend

  test "suspendTrans carries the command":
    let t = suspendTrans(cmdRequireLegislator)
    check t.suspendCmd() == cmdRequireLegislator

  test "suspendTrans with all command variants":
    let commands = [
      cmdRequireSwat, cmdRequireDetective, cmdRequireLegislator,
      cmdRequireScribe, cmdRequireJudge, cmdRequirePostProcess,
      cmdPipelineComplete,
    ]
    for cmd in commands:
      let t = suspendTrans(cmd)
      check t.transition2Kind() == tk2Suspend
      check t.suspendCmd() == cmd

  test "suspendTrans with explicit DispatchContext":
    let ctx = DispatchContext(target: dtDetective, detCtx: default(DetectiveContext))
    let t = suspendTrans(cmdRequireDetective, ctx)
    check t.transition2Kind() == tk2Suspend
    check t.suspendCmd() == cmdRequireDetective

  test "terminalOkTrans produces tk2Terminal with result":
    let res = default(UniversalPipelineResult)
    let t = terminalOkTrans(res)
    check t.transition2Kind() == tk2Terminal
    check t.terminalResult().isSome
    check t.terminalError().isNone

  test "terminalErrTrans produces tk2Terminal with error":
    let t = terminalErrTrans(axiomErrNotFound)
    check t.transition2Kind() == tk2Terminal
    check t.terminalResult().isNone
    check t.terminalError().isSome
    check t.terminalError().get() == axiomErrNotFound

  test "terminalErrTrans preserves distinct error values":
    let t1 = terminalErrTrans(axiomErrEmptyString)
    let t2 = terminalErrTrans(axiomErrJsonInvalid)
    check t1.terminalError().get() == axiomErrEmptyString
    check t2.terminalError().get() == axiomErrJsonInvalid
    check t1.terminalError().get() != t2.terminalError().get()

  test "Transition2 kind accessor returns correct enum for all variants":
    let tCont = continueTrans(dummySwatPhase())
    let tSusp = suspendTrans(cmdRequireJudge)
    let tTerm = terminalErrTrans(axiomErrFileSystemError)

    check tCont.transition2Kind() == tk2Continue
    check tSusp.transition2Kind() == tk2Suspend
    check tTerm.transition2Kind() == tk2Terminal

  test "each Transition2 kind is mutually exclusive":
    let tCont = continueTrans(dummySwatPhase())
    check tCont.transition2Kind() != tk2Suspend
    check tCont.transition2Kind() != tk2Terminal

    let tSusp = suspendTrans(cmdRequireSwat)
    check tSusp.transition2Kind() != tk2Continue
    check tSusp.transition2Kind() != tk2Terminal

    let tTerm = terminalErrTrans(axiomErrNotFound)
    check tTerm.transition2Kind() != tk2Continue
    check tTerm.transition2Kind() != tk2Suspend
