## pipeline_effect_test.nim
## Semantic assertion tests for pipeline_effect.nim — the effect descriptor layer.
##
## Coverage:
##   - noEffect(): produces peNone
##   - dispatchEffect(): produces peDispatch with correct target + input
##   - effectKind(), effectTarget(), effectInput() accessors
##   - DispatchResult: all 6 target variants with field accessors
##   - DispatchContext: all 6 target variants
##   - Round-trip: construct → query → accessor → field verification

import std/[unittest, strutils]
import verification/pipeline_effect
import verification/pipeline_state_types
import core/boundary/persona_interface
import core/types/lean_lsp_types
import core/solver/solver_bridge

# ─── PipelineEffect — noEffect ───────────────────────────────────────────────

suite "PipelineEffect — noEffect":

  test "noEffect() produces peNone":
    let pe = noEffect()
    check pe.effectKind() == peNone

  test "noEffect is not dispatch":
    let pe = noEffect()
    check pe.effectKind() != peDispatch

# ─── PipelineEffect — dispatchEffect ─────────────────────────────────────────

suite "PipelineEffect — dispatchEffect":

  test "dispatchEffect produces peDispatch":
    let pe = dispatchEffect(dtSwat)
    check pe.effectKind() == peDispatch

  test "dispatchEffect carries target":
    let pe = dispatchEffect(dtDetective)
    check pe.effectTarget() == dtDetective

  test "dispatchEffect carries input string":
    let pe = dispatchEffect(dtJudge, "some-payload")
    check pe.effectInput() == "some-payload"

  test "dispatchEffect default input is empty":
    let pe = dispatchEffect(dtLegislator)
    check pe.effectInput() == ""

  test "dispatchEffect with all targets":
    let targets = [dtSwat, dtDetective, dtLegislator, dtScribe, dtJudge, dtPostProcess]
    for tgt in targets:
      let pe = dispatchEffect(tgt, $tgt)
      check pe.effectKind() == peDispatch
      check pe.effectTarget() == tgt
      check pe.effectInput() == $tgt

# ─── PipelineEffect — round-trip ─────────────────────────────────────────────

suite "PipelineEffect — round-trip construction → query → accessor":

  test "noEffect round-trip — kind peNone, no further fields":
    let pe = noEffect()
    check pe.effectKind() == peNone
    # effectTarget and effectInput are only valid for peDispatch,
    # but the object stores zero-init values for the dispatch branch.
    # We verify the kind is correct — that's the contract.

  test "dispatchEffect round-trip — kind + target + input preserved":
    let pe = dispatchEffect(dtScribe, "lean-theorem-source")
    check pe.effectKind() == peDispatch
    check pe.effectTarget() == dtScribe
    check pe.effectInput() == "lean-theorem-source"

  test "dispatchEffect with unicode input":
    let pe = dispatchEffect(dtLegislator, "불변량: ∀ x, x ≥ 0")
    check pe.effectInput() == "불변량: ∀ x, x ≥ 0"

  test "dispatchEffect with long input":
    let longInput = "A".repeat(10_000)
    let pe = dispatchEffect(dtSwat, longInput)
    check pe.effectInput().len == 10_000

# ─── DispatchContext — construction and field access ─────────────────────────

suite "DispatchContext — all target variants":

  test "dtSwat context carries SwatArtifact":
    var art = default(SwatArtifact)
    art.healedSource = "safe-code"
    let ctx = DispatchContext(target: dtSwat, swatArt: art)
    check ctx.target == dtSwat
    check ctx.swatArt.healedSource == "safe-code"

  test "dtDetective context carries DetectiveContext":
    let detCtx = default(DetectiveContext)
    let ctx = DispatchContext(target: dtDetective, detCtx: detCtx)
    check ctx.target == dtDetective

  test "dtLegislator context carries DetectedState + goalDeltas":
    var det = default(DetectedState)
    det.cegarCounterexample = true
    var delta = default(GoalDelta)
    delta.resolvedGoals = @["goal_1"]
    let ctx = DispatchContext(target: dtLegislator, detected: det,
                              currentDeltas: @[delta])
    check ctx.target == dtLegislator
    check ctx.detected.cegarCounterexample == true
    check ctx.currentDeltas.len == 1
    check ctx.currentDeltas[0].resolvedGoals == @["goal_1"]

  test "dtScribe context carries LegislatedState + KInductionResult":
    var leg = default(LegislatedState)
    leg.activeInvariant = "invariant_ok"
    let kindRes = KInductionResult(verdict: kivProved, k: 3,
                                    baseCaseUnsat: true, stepCaseUnsat: true)
    let ctx = DispatchContext(target: dtScribe, legislated: leg,
                              kInductionPayload: kindRes)
    check ctx.target == dtScribe
    check ctx.legislated.activeInvariant == "invariant_ok"
    check ctx.kInductionPayload.verdict == kivProved
    check ctx.kInductionPayload.k == 3

  test "dtJudge context carries ScribedState":
    var scr = default(ScribedState)
    scr.verified = true
    let ctx = DispatchContext(target: dtJudge, scribed: scr)
    check ctx.target == dtJudge
    check ctx.scribed.verified == true

  test "dtPostProcess context carries JudgedState":
    var judged = default(JudgedState)
    judged.leanKernelVerified = true
    judged.proofDepth = 7
    let ctx = DispatchContext(target: dtPostProcess, judged: judged)
    check ctx.target == dtPostProcess
    check ctx.judged.leanKernelVerified == true
    check ctx.judged.proofDepth == 7

  test "stagnationEscalated flag is accessible":
    let ctx = DispatchContext(target: dtSwat, swatArt: default(SwatArtifact),
                              stagnationEscalated: true)
    check ctx.stagnationEscalated == true

  test "goalDeltas field is accessible":
    var delta = default(GoalDelta)
    delta.newGoals = @["g1", "g2"]
    let ctx = DispatchContext(target: dtSwat, swatArt: default(SwatArtifact),
                              goalDeltas: @[delta])
    check ctx.goalDeltas.len == 1
    check ctx.goalDeltas[0].newGoals == @["g1", "g2"]

# ─── DispatchResult — construction and field access ──────────────────────────

suite "DispatchResult — all target variants":

  test "dtSwat result carries SwatArtifact":
    var art = default(SwatArtifact)
    art.sourceChecksum = "checksum123"
    let dr = DispatchResult(target: dtSwat, swatArt: art)
    check dr.dispatchTarget() == dtSwat
    check dr.swatArt().sourceChecksum == "checksum123"

  test "dtDetective result carries DetectiveArtifact":
    var da = default(DetectiveArtifact)
    da.cegarCounterexample = true
    let dr = DispatchResult(target: dtDetective, caseArt: da)
    check dr.dispatchTarget() == dtDetective
    check dr.caseArt().cegarCounterexample == true

  test "dtLegislator result carries LegislatorArtifact":
    var la = default(LegislatorArtifact)
    la.activeInvariant = "legislated_inv"
    la.baselineInvariant = "base"
    la.refinedInvariant = "refined"
    let dr = DispatchResult(target: dtLegislator, draftArt: la)
    check dr.dispatchTarget() == dtLegislator
    check dr.draftArt().activeInvariant == "legislated_inv"
    check dr.draftArt().baselineInvariant == "base"
    check dr.draftArt().refinedInvariant == "refined"

  test "dtScribe result carries ScribeArtifact":
    var sa = default(ScribeArtifact)
    sa.verified = true
    sa.theoremSource = "theorem foo : True := trivial"
    sa.tacticTrace = @["intro", "trivial"]
    let dr = DispatchResult(target: dtScribe, scribeArt: sa)
    check dr.dispatchTarget() == dtScribe
    check dr.scribeArt().verified == true
    check dr.scribeArt().theoremSource == "theorem foo : True := trivial"
    check dr.scribeArt().tacticTrace == @["intro", "trivial"]

  test "dtJudge result carries JudgeArtifact":
    var ja = default(JudgeArtifact)
    ja.leanKernelVerified = true
    ja.proofDepth = 4
    ja.failedReplayAttempts = 0
    let dr = DispatchResult(target: dtJudge, judgeArt: ja)
    check dr.dispatchTarget() == dtJudge
    check dr.judgeArt().leanKernelVerified == true
    check dr.judgeArt().proofDepth == 4
    check dr.judgeArt().failedReplayAttempts == 0

  test "dtPostProcess result carries DetectiveArtifact":
    var da = default(DetectiveArtifact)
    da.cegarCounterexample = false
    da.unsatCoreVars = @["a", "b"]
    let dr = DispatchResult(target: dtPostProcess, postArt: da)
    check dr.dispatchTarget() == dtPostProcess
    check dr.postArt().cegarCounterexample == false
    check dr.postArt().unsatCoreVars == @["a", "b"]

  test "DispatchResult targets are mutually exclusive":
    let targets = [dtSwat, dtDetective, dtLegislator, dtScribe, dtJudge, dtPostProcess]
    for tgt in targets:
      case tgt
      of dtSwat:
        let dr = DispatchResult(target: dtSwat, swatArt: default(SwatArtifact))
        check dr.dispatchTarget() == dtSwat
      of dtDetective:
        let dr = DispatchResult(target: dtDetective, caseArt: default(DetectiveArtifact))
        check dr.dispatchTarget() == dtDetective
      of dtLegislator:
        let dr = DispatchResult(target: dtLegislator, draftArt: default(LegislatorArtifact))
        check dr.dispatchTarget() == dtLegislator
      of dtScribe:
        let dr = DispatchResult(target: dtScribe, scribeArt: default(ScribeArtifact))
        check dr.dispatchTarget() == dtScribe
      of dtJudge:
        let dr = DispatchResult(target: dtJudge, judgeArt: default(JudgeArtifact))
        check dr.dispatchTarget() == dtJudge
      of dtPostProcess:
        let dr = DispatchResult(target: dtPostProcess, postArt: default(DetectiveArtifact))
        check dr.dispatchTarget() == dtPostProcess
