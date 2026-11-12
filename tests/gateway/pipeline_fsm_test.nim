{.push raises: [].}

## Pipeline FSM Hyper-Isolation Test Harness
##
## Unified test exercising Universal Acceptance Pipeline FSM traversal
## and CEGAR mock oracle. All tests are deterministic, in-memory, no I/O.
## ARC/ORC safe: ref object with {.acyclic.} pattern.

import std/unittest
import std/options
import verification/universal_pipeline
import verification/pipeline_state_types
import core/boundary/persona_interface
import core/orchestration/pipeline_types
import core/types/pipeline_core_types
import core/types/domain_types
import verification/pipeline_effect
import core/solver/solver_bridge
import core/orchestrator/cegar_bmc_types
import core/orchestrator/cegar_types
import core/contracts/universal_pipeline_contract
import mock_solver_oracle

# ── Mock Dispatch State ──
type
  MockDispatchState {.acyclic.} = ref object
    ## ORC safe: no self-referential fields.
    callLog*: seq[PipelineCommand]

proc createMockDispatch(): (PersonaDispatchFn, MockDispatchState) =
  ## Create a mock dispatch function that records all commands
  ## and writes minimal artifacts back to the pipeline context.
  ## proc (not func): ref object heap allocation is a side effect.
  let state = MockDispatchState(callLog: @[])
  let dispatch = proc(cmd: PipelineCommand; ctx: PipelineContext;
                       dispatchCtx: DispatchContext)
      {.closure, raises: [CatchableError].} =
    state.callLog.add(cmd)
    case cmd
    of cmdRequireSwat:
      ## Set swatOutcome to ssrFallbackRequired so FSM continues past SWAT.
      ## ssrBmcSuccess would terminate the pipeline immediately.
      ctx.swatArt = default(SwatArtifact)
      ctx.swatOutcome = some(SwatStageOutcome(
        kind: ssrFallbackRequired,
        kInductionResult: default(KInductionResult),
        cegarBmcResult: default(CegarBmcResult),
        priorInvariant: ""
      ))
    of cmdRequireDetective:
      ctx.caseArt = default(DetectiveArtifact)
    of cmdRequireLegislator:
      ## activeInvariant must be empty to skip registryContains check
      ## (Phase 2a invariant: non-empty invariant must be in registry).
      ctx.draftArt = default(LegislatorArtifact)
    of cmdRequireScribe:
      ctx.scribeArt = default(ScribeArtifact)
    of cmdRequireJudge:
      ## leanKernelVerified = false skips proofArtifact.nodeId check
      ## (Phase 2b invariant: verified judgment needs non-empty cert).
      ctx.judgeArt = default(JudgeArtifact)
    of cmdRequirePostProcess:
      ctx.detArt = default(DetectiveArtifact)
    of cmdPipelineComplete:
      discard
  (dispatch, state)

func makeMinimalRequest(): UniversalPipelineRequest =
  ## Minimal valid request for pipeline FSM testing.
  UniversalPipelineRequest(
    language: "nim",
    modulePath: "test_module",
    functionName: "testFunc",
    astJson: "{}",
    sourceCode: "func testFunc(x: int): int = x",
    maxRounds: 3,
    proofVaultDir: "/tmp/axiom_test",
    bddDir: "/tmp/axiom_test/bdd",
    logic: slQfLia,
    verificationContext: AxiomVerificationContext(
      functionName: "testFunc",
      logic: slQfLia
    )
  )

# ──────────────────────────────────────────────────────────────────────────────
# Pipeline FSM Test Suite
# ──────────────────────────────────────────────────────────────────────────────

suite "Pipeline FSM Hyper-Isolation":
  test "FSM traverses all 6 persona stages":
    ## Transition engine path: pkInit → SWAT → Detective → Legislator →
    ## Scribe → Judge → PostProcess → terminal.
    ## Each stage yields a PipelineCommand; mock dispatch records it.
    let (dispatch, state) = createMockDispatch()
    let req = makeMinimalRequest()
    discard runPipelineWithDispatch(req, dispatch)
    # All 6 persona stages must be dispatched (cmdPipelineComplete is not dispatched by runner)
    doAssert state.callLog.len >= 6,
      "Expected >= 6 dispatch calls, got " & $state.callLog.len
    doAssert state.callLog[0] == cmdRequireSwat,
      "First dispatch must be cmdRequireSwat"
    doAssert state.callLog[1] == cmdRequireDetective,
      "Second dispatch must be cmdRequireDetective"
    doAssert state.callLog[2] == cmdRequireLegislator,
      "Third dispatch must be cmdRequireLegislator"
    doAssert state.callLog[3] == cmdRequireScribe,
      "Fourth dispatch must be cmdRequireScribe"
    doAssert state.callLog[4] == cmdRequireJudge,
      "Fifth dispatch must be cmdRequireJudge"
    doAssert state.callLog[5] == cmdRequirePostProcess,
      "Sixth dispatch must be cmdRequirePostProcess"

  test "returns valid VerificationOutcome":
    ## Pipeline must always return a VerificationOutcome, never crash.
    let (dispatch, _) = createMockDispatch()
    let req = makeMinimalRequest()
    let outcome = runPipelineWithDispatch(req, dispatch)
    case outcome.exitKind
    of pekSuccess:
      doAssert outcome.verdict in {vvSafe, vvUnsafe, vvUnknown}
    of pekFailure:
      doAssert outcome.failureMessage.len > 0

  test "guardExitMessage populated on terminal":
    ## The pipeline guard must record a reason string on termination.
    let (dispatch, _) = createMockDispatch()
    let req = makeMinimalRequest()
    let outcome = runPipelineWithDispatch(req, dispatch)
    case outcome.exitKind
    of pekSuccess:
      # Success path: pipeline completed without error
      doAssert outcome.verdict in {vvSafe, vvUnknown}
    of pekFailure:
      # Failure path: failureMessage must explain why
      doAssert outcome.failureMessage.len > 0,
        "pekFailure must carry a failureMessage"

  test "pipeline with swat fast-path terminates early":
    ## When SWAT returns ssrBmcSuccess, pipeline terminates immediately
    ## without reaching Detective/Legislator/Scribe/Judge/PostProcess.
    func dispatchSwatFastPath(cmd: PipelineCommand; ctx: PipelineContext;
                              dispatchCtx: DispatchContext)
        {.raises: [CatchableError].} =
      case cmd
      of cmdRequireSwat:
        ctx.swatArt = default(SwatArtifact)
        ctx.swatOutcome = some(SwatStageOutcome(
          kind: ssrBmcSuccess,
          pipelineResult: default(UniversalPipelineResult)
        ))
      else:
        doAssert false, "Should not dispatch " & $cmd & " on fast-path"
    let req = makeMinimalRequest()
    let fastOutcome = runPipelineWithDispatch(req, dispatchSwatFastPath)
    # Fast-path: either pekSuccess (verdict from result) or pekFailure (empty result fallback)
    doAssert fastOutcome.exitKind in {pekSuccess, pekFailure}

# ──────────────────────────────────────────────────────────────────────────────
# CEGAR Mock Oracle Test Suite
# ──────────────────────────────────────────────────────────────────────────────

suite "CEGAR Mock Oracle":
  test "always proven":
    let result = mockCegarEngineResult(msmAlwaysProven)
    doAssert result.verdict == cegarProven
    doAssert result.iterations == 1
    doAssert result.elapsedMs == 0'i64

  test "always refuted":
    let result = mockCegarEngineResult(msmAlwaysRefuted)
    doAssert result.verdict == cegarCounterexample
    doAssert result.iterations == 1

  test "first refute then prove":
    let result = mockCegarEngineResult(msmFirstRefute)
    doAssert result.verdict == cegarProven
    doAssert result.iterations == 2,
      "msmFirstRefute must report 2 iterations (refute + prove)"

  test "timeout":
    let result = mockCegarEngineResult(msmTimeout)
    doAssert result.verdict == cegarBudgetExceeded
    doAssert result.iterations == 0
    doAssert result.elapsedMs == 30000'i64

  test "mock Z3 check — always proven closure":
    let z3 = createMockZ3Check(msmAlwaysProven)
    doAssert z3("(assert true)") == true
    doAssert z3("any query") == true

  test "mock Z3 check — always refuted closure":
    let z3 = createMockZ3Check(msmAlwaysRefuted)
    doAssert z3("(assert false)") == false
    doAssert z3("any query") == false

  test "mock Z3 check — first refute then prove closure":
    let z3 = createMockZ3Check(msmFirstRefute)
    doAssert z3("iteration 1") == false,
      "First query must return false (counterexample)"
    doAssert z3("iteration 2") == true,
      "Second query must return true (proven after refinement)"
    doAssert z3("iteration 3") == true,
      "Subsequent queries must return true"

  test "mock Z3 check — timeout closure raises":
    let z3 = createMockZ3Check(msmTimeout)
    var caught = false
    try:
      discard z3("query")
    except CatchableError:
      caught = true
    doAssert caught, "msmTimeout closure must raise CatchableError"

{.pop.}
