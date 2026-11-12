import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Verify
## Verification operations: BMC race detection, symbolic encoding,
## k-induction, and semantic payload verification.

import std/options

import core/gateway/gateway
import core/gateway/gateway_types
import core/types/results
import core/bmc/bmc_race
import core/bmc/bmc_types
import core/utils/axiom_clock
import core/solver/solver_bridge
import core/solver/types
import core/solver/type_serialize
import core/parsers/expression_parser

import core/contracts/universal_pipeline_contract
import core/api/axiom_api_helpers
import ../../core/trusted/axiom_pragmas
export axiom_api_helpers

## Verify Semantic Equality Payload By Solver Output.
func verifySemanticEqualityPayloadBySolverOutput*(
  payload: SemanticEqualityPayload;
  solverStdout: string
): Result[SemanticPayloadVerificationResponse, SymbolicFailure] {.raises: [], axiom: ["(assert (and (>= (seq.len payload_enumValues) 0) (>= (seq.len payload_unsatCore) 0) (>= (str.len solverStdout) 0)))", "payload_enumValues.size >= 0 ∧ payload_unsatCore.size >= 0 ∧ solverStdout.length >= 0"].} =
  let smt2Res = buildSemanticEqualityPayloadSmt(payload)
  if smt2Res.isErr():
    return err(toSymbolicFailure(smt2Res.error))
  let smt2 = smt2Res.get()
  let parsed = parseZ3StdoutAsResult(solverStdout, smt2, semanticProofGoalString(payload.proofGoal))
  if parsed.isOk():
    return ok(semanticPayloadResponse(payload, smt2, parsed.get().evidence.status, none(SolverCounterExample)))
  let failure = parsed.error
  if failure.solverStatus.isSome():
    if failure.code == axiomErrSolverSatCounterExample:
      return ok(semanticPayloadResponse(payload, smt2, failure.solverStatus.get(), failure.counterExample))
    if failure.code == axiomErrSolverUnknown:
      return ok(semanticPayloadResponse(payload, smt2, failure.solverStatus.get(), none(SolverCounterExample)))
    if failure.code == axiomErrVacuousContradiction:
      return ok(semanticPayloadResponse(payload, smt2, failure.solverStatus.get(), none(SolverCounterExample)))
  err(failure)

## Verify Race Condition.
func verifyRaceCondition*(stateValue: int; inputDelta: int): Result[BmcVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807"].} =
  let gatedRes = ??gatekeepStateInput(
    stateValue,
    inputDelta,
    InputConstraintDefinition(
      relationalInvariant: gateway_types.some(stateDeltaWithinBalance)
    )
  )
  let gated = gatedRes
  var clk = deterministicClock(0, 0)
  let verdict = bmc_race.verifyRaceConditionWithDelta(clk, gated[0], gated[1])
  ok(BmcVerificationResponse(
    raceDetected: verdict.raceDetected,
    raceFinalState: verdict.raceFinalState,
    bothWritePathExists: verdict.bothWritePathExists,
    sequentialResultA: verdict.sequentialResults[0],
    sequentialResultB: verdict.sequentialResults[1],
    sequentialUniqueCount: verdict.sequentialUniqueCount,
    stepBound: bmcStepBound
  ))

## Verify User Code Race.
func verifyUserCodeRace*(code: string; stateValue: int): Result[BmcVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len code) 0) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807))))", "code.length >= 0 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807"].} =
  let ruleRes = ??parseUserCodeToRule(code)
  let rule = ruleRes
  var clk = deterministicClock(0, 0)
  let verdict = bmc_race.verifyRaceCondition(clk, stateValue, rule)
  ok(BmcVerificationResponse(
    raceDetected: verdict.raceDetected,
    raceFinalState: verdict.raceFinalState,
    bothWritePathExists: verdict.bothWritePathExists,
    sequentialResultA: verdict.sequentialResults[0],
    sequentialResultB: verdict.sequentialResults[1],
    sequentialUniqueCount: verdict.sequentialUniqueCount,
    stepBound: bmcStepBound
  ))

## Encode Transition Smt.
func encodeTransitionSmt*(stateValue: int; inputDelta: int): Result[SymbolicVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807"].} =
  let gatedRes = ??gatekeepStateInput(
    stateValue,
    inputDelta,
    InputConstraintDefinition(
      relationalInvariant: gateway_types.some(stateDeltaWithinBalance)
    )
  )
  let gated = gatedRes
  let payload = buildTransitionPayload(gated[0], makeSubtractRule(gated[1]))
  ok(SymbolicVerificationResponse(
    status: "encoded",
    smt2: payload.smt2,
    hasCounterExample: false,
    counterExampleProperty: "",
    inductionProved: false,
    k: 0,
    baseSmt2: "",
    stepSmt2: ""
  ))

## Verify Runtime Error Zero By Solver Output.
func verifyRuntimeErrorZeroBySolverOutput*(
  stateValue: int;
  inputDelta: int;
  solverStdout: string
): Result[SymbolicVerificationResponse, SymbolicFailure] {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807)) (>= (str.len solverStdout) 0)))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807 ∧ solverStdout.length >= 0"].} =
  let gated = gatekeepStateInputAsSymbolicFailure(stateValue, inputDelta)
  if gated.isErr():
    return err(gated.error)
  let payload = buildRuntimeErrorZeroPayload(gated.get()[0], makeSubtractRule(gated.get()[1]))
  let parsed = parseZ3StdoutAsResult(solverStdout, payload.smt2)
  if parsed.isOk():
    let ev = parsed.get().evidence
    return ok(SymbolicVerificationResponse(
      status: solverStatusString(ev.status),
      smt2: payload.smt2,
      hasCounterExample: ev.counterExample.isSome(),
      counterExampleProperty: if ev.counterExample.isSome(): ev.counterExample.get().violatedProperty else: "",
      inductionProved: false,
      k: 0,
      baseSmt2: "",
      stepSmt2: ""
    ))
  let failure = parsed.error
  if failure.solverStatus.isSome():
    if failure.code == axiomErrSolverSatCounterExample or failure.code == axiomErrSolverUnknown or failure.code == axiomErrVacuousContradiction:
      return ok(SymbolicVerificationResponse(
        status: solverStatusString(failure.solverStatus.get()),
        smt2: payload.smt2,
        hasCounterExample: failure.counterExample.isSome(),
        counterExampleProperty: if failure.counterExample.isSome(): failure.counterExample.get().violatedProperty else: "",
        inductionProved: false,
        k: 0,
        baseSmt2: "",
        stepSmt2: ""
      ))
  return err(failure)

## Build KInduction Smt.
func buildKInductionSmt*(
  k: int;
  stateValue: int;
  inputDelta: int
): Result[SymbolicVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "k >= -9223372036854775808 ∧ k <= 9223372036854775807 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807"].} =
  let gatedRes = ??gatekeepStateInput(
    stateValue,
    inputDelta,
    InputConstraintDefinition(
      relationalInvariant: gateway_types.some(stateDeltaWithinBalance)
    )
  )
  let gated = gatedRes
  let payload = buildKInductionPayload(k, gated[0], makeSubtractRule(gated[1]))
  ok(SymbolicVerificationResponse(
    status: "encoded",
    smt2: "",
    hasCounterExample: false,
    counterExampleProperty: "",
    inductionProved: false,
    k: payload.request.k,
    baseSmt2: payload.baseSmt2,
    stepSmt2: payload.stepSmt2
  ))

## Build KInduction Smt By Injected Rule.
func buildKInductionSmtByInjectedRule*(
  k: int;
  stateValue: int;
  ruleText: string;
  invariantText: string
): Result[SymbolicVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (>= (str.len ruleText) 0) (>= (str.len invariantText) 0)))", "k >= -9223372036854775808 ∧ k <= 9223372036854775807 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ ruleText.length >= 0 ∧ invariantText.length >= 0"].} =
  let payload = buildKInductionPayload(k, stateValue, ??parseUserCodeAndInvariantToRule(ruleText, invariantText))
  ok(SymbolicVerificationResponse(
    status: "encoded",
    smt2: "",
    hasCounterExample: false,
    counterExampleProperty: "",
    inductionProved: false,
    k: payload.request.k,
    baseSmt2: payload.baseSmt2,
    stepSmt2: payload.stepSmt2
  ))

## Verify KInduction By Solver Output.
func verifyKInductionBySolverOutput*(
  k: int;
  stateValue: int;
  inputDelta: int;
  baseStdout: string;
  stepStdout: string
): Result[SymbolicVerificationResponse, SymbolicFailure] {.raises: [], axiom: ["(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807)) (>= (str.len baseStdout) 0) (>= (str.len stepStdout) 0) (>= finalStatus 0)))", "k >= -9223372036854775808 ∧ k <= 9223372036854775807 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807 ∧ baseStdout.length >= 0 ∧ stepStdout.length >= 0 ∧ (finalStatus >= 0)"].} =
  let gated = gatekeepStateInputAsSymbolicFailure(stateValue, inputDelta)
  if gated.isErr():
    return err(gated.error)
  let payload = buildKInductionPayload(k, gated.get()[0], makeSubtractRule(gated.get()[1]))
  let baseRes = parseZ3StdoutAsResult(baseStdout, payload.baseSmt2, "k_induction_base")
  if baseRes.isErr():
    return err(baseRes.error)
  let stepRes = parseZ3StdoutAsResult(stepStdout, payload.stepSmt2, "k_induction_step")
  # A k-induction argument discharges only when the base AND the step
  # obligation both came back unsat. The default is the weakest state the
  # solver vocabulary allows: a status that was never observed stays unknown,
  # so no unhandled path inherits a proof. The status string is never an input
  # to the proof flag — a bare `unsat` is solver evidence, not a proof-checked
  # result (docs/spec/evidence_calculus.md I6).
  let baseUnsat = baseRes.isOk() and baseRes.get().evidence.status == solverUnsat
  let stepUnsat = stepRes.isOk() and stepRes.get().evidence.status == solverUnsat
  var finalStatus = "unknown"
  var inductionProved = false
  if baseUnsat and stepUnsat:
    finalStatus = "proved"
    inductionProved = true
  elif stepRes.isErr() and stepRes.error.solverStatus.isSome() and (stepRes.error.code == axiomErrSolverSatCounterExample or stepRes.error.code == axiomErrSolverUnknown or stepRes.error.code == axiomErrVacuousContradiction):
    finalStatus = solverStatusString(stepRes.error.solverStatus.get())
  elif stepRes.isErr():
    return err(stepRes.error)

  ok(SymbolicVerificationResponse(
    status: finalStatus,
    smt2: "",
    hasCounterExample: finalStatus == "sat",
    counterExampleProperty: if finalStatus == "sat": "k_induction_base_or_step" else: "",
    inductionProved: inductionProved,
    k: k,
    baseSmt2: payload.baseSmt2,
    stepSmt2: payload.stepSmt2
  ))

## Verify KInduction By Injected Rule Output.
func verifyKInductionByInjectedRuleOutput*(
  k: int;
  stateValue: int;
  ruleText: string;
  invariantText: string;
  baseStdout: string;
  stepStdout: string
): Result[SymbolicVerificationResponse, SymbolicFailure] {.raises: [], axiom: ["(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (>= (str.len ruleText) 0) (>= (str.len invariantText) 0) (>= (str.len baseStdout) 0) (>= (str.len stepStdout) 0) (>= finalStatus 0)))", "k >= -9223372036854775808 ∧ k <= 9223372036854775807 ∧ stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ ruleText.length >= 0 ∧ invariantText.length >= 0 ∧ baseStdout.length >= 0 ∧ stepStdout.length >= 0 ∧ (finalStatus >= 0)"].} =
  let ruleRes = parseUserCodeAndInvariantToRule(ruleText, invariantText)
  if ruleRes.isErr():
    return err(toSymbolicFailure(ruleRes.error))
  let payload = buildKInductionPayload(k, stateValue, ruleRes.get())
  let baseRes = parseZ3StdoutAsResult(baseStdout, payload.baseSmt2, "k_induction_base")
  if baseRes.isErr():
    return err(baseRes.error)
  let stepRes = parseZ3StdoutAsResult(stepStdout, payload.stepSmt2, "k_induction_step")
  # Same derivation as verifyKInductionBySolverOutput: discharged only on the
  # base∧step unsat conjunction, weakest status otherwise.
  let baseUnsat = baseRes.isOk() and baseRes.get().evidence.status == solverUnsat
  let stepUnsat = stepRes.isOk() and stepRes.get().evidence.status == solverUnsat
  var finalStatus = "unknown"
  var inductionProved = false
  if baseUnsat and stepUnsat:
    finalStatus = "proved"
    inductionProved = true
  elif stepRes.isErr() and stepRes.error.solverStatus.isSome() and (stepRes.error.code == axiomErrSolverSatCounterExample or stepRes.error.code == axiomErrSolverUnknown or stepRes.error.code == axiomErrVacuousContradiction):
    finalStatus = solverStatusString(stepRes.error.solverStatus.get())
  elif stepRes.isErr():
    return err(stepRes.error)

  ok(SymbolicVerificationResponse(
    status: finalStatus,
    smt2: "",
    hasCounterExample: finalStatus == "sat",
    counterExampleProperty: if finalStatus == "sat": "k_induction_base_or_step" else: "",
    inductionProved: inductionProved,
    k: k,
    baseSmt2: payload.baseSmt2,
    stepSmt2: payload.stepSmt2
  ))

{.pop.}
