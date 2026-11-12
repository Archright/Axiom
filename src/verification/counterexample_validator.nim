import core/trusted/layer_declaration
axiomLayer "infrastructure"
# axiomIoBoundary — P4 semantic witness validation performs real Z3 solver I/O
# via ObligationDischarger; §0.6 permits proc at the I/O boundary.
{.push raises: [].}

import std/[options, sequtils, strutils, tables]
import core/trusted/axiom_pragmas
import core/trusted/axiom_ir_types
import core/trusted/verification_model_types
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import core/types/solver_types
import verification/obligation_discharger
import core/trusted/ir_to_smt
import verification/counterexample_replay
## Re-export the S4-S5 replay adapter: consumers of this module (notably
## ir_pipeline_runner) drive `replayConfirmedDisproof` after a P4 promotion
## without adding a direct dependency edge on the adapter module.
export counterexample_replay

type
  CounterexampleVerdict* = enum
    cvConfirmed
    cvSpurious
    cvUnresolved

  CounterexampleValidator* = object
    discharger*: ObligationDischarger

func newCounterexampleValidator*(z3Path: string = "z3"; timeoutMs: int = 5000): CounterexampleValidator {.axiomDecision(
  id = "DECISION-0310",
  reason = "Constructs CounterexampleValidator with a Z3-backed ObligationDischarger for semantic witness validation (P4)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  CounterexampleValidator(discharger: newObligationDischarger(z3Path, timeoutMs))

func parseSolverStatus(s: string): SolverStatus {.raises: [].} =
  case s
  of "sosUnsat": solverUnsat
  of "sosSat": solverSat
  of "sosUnknown": solverUnknown
  of "sosTimeout": solverTimeout
  of "sosResourceLimit": solverTimeout
  of "sosProcessError": solverUnknown
  of "sosParseError": solverUnknown
  else: solverUnknown

func smtDeclarationsForModel(model: VerificationModel): string {.raises: [].} =
  var lines: seq[string] = @[]
  let stateSorts = model.semantic.states.mapIt(irTypeToSmt(it.irType)).join(" ")
  lines.add("(declare-fun state (" & stateSorts & ") Bool)")
  for st in model.semantic.states:
    lines.add("(declare-const " & st.name & " " & irTypeToSmt(st.irType) & ")")
  lines.join("\n")

func isC20OneStateEntryBindingModel(model: VerificationModel): bool {.raises: [].} =
  ## C20 one-state contract-model discriminator (lowerPostconditionModel,
  ## ir_pipeline_runner): exactly ONE transition whose guard is nil and whose
  ## parallel update frames nothing — the identity entry→exit edge. Loop
  ## lowering NEVER creates a nil-guard transition (an unguarded loop edge
  ## would make the loop body unconditional), so this shape is exclusive to
  ## the one-state BMC contract model; `resultStateName == some("result")` is
  ## its result-binding marker. The discrimination is by MODEL SHAPE, never
  ## by expression type alone — that is what keeps the CHC condition reading
  ## and the C20 binding reading sound both ways.
  let sem = model.semantic
  if sem.transitions.len != 1:
    return false
  let t = sem.transitions[0]
  if t.guard != nil:
    return false
  if t.update.assignments.len != 0 or t.update.havocs.len != 0:
    return false
  sem.resultStateName.isSome and sem.resultStateName.get == "result"

func preconditionSmt(model: VerificationModel): string {.raises: [].} =
  ## Entry constraints of the model. `semantic.initExprs` carries TWO ROLES,
  ## discriminated by MODEL SHAPE (isC20OneStateEntryBindingModel), never by
  ## expression type alone:
  ##
  ## 1. CHC entry CONDITIONS — loop-lowered models (lowerLoopToTransition)
  ##    and hand-built CHC fixtures (`typ == nil` initExprs) read bool-typed
  ##    initExprs as bare conditions; the CHC encoders consume initExprs as
  ##    state-rule args. Non-C20 models keep that reading unchanged.
  ## 2. C20 one-state ENTRY BINDINGS — the straight-line BMC contract model
  ##    (lowerPostconditionModel) binds each parameter to itself and `result`
  ##    to the actual body (the computation already happened at entry), so a
  ##    typed bool initExpr there is the EQUALITY
  ##    `(= states[i].name expr)`, index-aligned — same shape as the
  ##    value-typed branch below. This is the pipeline's uniform value
  ##    reading: buildInitiations (verification_obligations.nim) renders ALL
  ##    initExprs as equalities; preconditionSmt's bare-bool branch was the
  ##    lone condition reading, and for a bool-returning function it forced
  ##    the body true — excluding every defect witness → UNSAT → cvSpurious
  ##    → no P4 promotion (DECISION-0311 validate / DECISION-0312 finalize).
  ##
  ## Value-typed initExprs are always the ENTRY BINDING of their
  ## index-aligned state var — asserted as an EQUALITY: asserting the bare
  ## term would feed a BitVec where a Bool is expected, z3 would reject the
  ## script with a type error, and every BMC SAT would fail closed as
  ## cvUnresolved (the P4 promotion would be unreachable). A value-typed or
  ## C20-bool initExpr with no index-aligned state var is unprojectable →
  ## "" fails the caller closed.
  let n = model.semantic.initExprs.len
  if n == 0:
    return "true"
  let c20EntryBindings = isC20OneStateEntryBindingModel(model)
  var parts: seq[string] = @[]
  for i, expr in model.semantic.initExprs:
    if expr == nil:
      continue
    if expr.typ != nil and expr.typ.kind != irtBool:
      if i >= model.semantic.states.len:
        return ""
      parts.add("(= " & model.semantic.states[i].name & " " & irExprToSmt(expr) & ")")
    elif c20EntryBindings and expr.typ != nil:
      # C20 one-state model: a typed bool initExpr is the ENTRY BINDING of
      # its index-aligned state var (`result` → the actual body), not a
      # condition. Well-sorted: smtDeclarationsForModel declares Bool states.
      if i >= model.semantic.states.len:
        return ""
      parts.add("(= " & model.semantic.states[i].name & " " & irExprToSmt(expr) & ")")
    else:
      parts.add(irExprToSmt(expr))
  if parts.len == 0:
    return "true"
  if parts.len == 1:
    parts[0]
  else:
    "(and " & parts.join(" ") & ")"

func negatedPostconditionSmt(model: VerificationModel): string {.raises: [].} =
  if model.semantic.property.isNone or model.semantic.property.get == nil:
    return "false"
  let prop = irExprToSmt(model.semantic.property.get)
  if prop == "true":
    "false"
  elif prop == "false":
    "true"
  else:
    "(not " & prop & ")"

proc validateCounterexample*(validator: CounterexampleValidator; model: VerificationModel;
                              candidate: CandidateEvidence; z3Path: string;
                              timeoutMs: int): CounterexampleVerdict {.axiomDecision(
  id = "DECISION-0311",
  reason = "P4 semantic witness validation: determines whether a SAT candidate counterexample genuinely violates the postcondition under the precondition, or is a spurious lowering/encoding artifact",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if candidate.isEmpty():
    return cvUnresolved
  if candidate.model.len == 0:
    return cvUnresolved
  if model.semantic.states.len == 0:
    return cvUnresolved
  let decls = smtDeclarationsForModel(model)
  let pre = preconditionSmt(model)
  if pre.len == 0:
    return cvUnresolved
  let negPost = negatedPostconditionSmt(model)
  let script =
    (if decls.len > 0: decls & "\n" else: "") &
    "(assert " & pre & ")\n" &
    "(assert " & negPost & ")\n" &
    "(check-sat)\n"
  let outcome = validator.discharger.discharge(script)
  if outcome.passed:
    cvSpurious
  else:
    let status = parseSolverStatus(outcome.solverStatus)
    case status
    of solverSat:
      cvConfirmed
    of solverTimeout, solverUnknown:
      cvUnresolved
    of solverUnsat:
      cvSpurious
    of solverVacuousContradiction:
      cvSpurious

func finalizeVerdict*(candidate: VerificationResult; verdict: CounterexampleVerdict): VerificationResult {.axiomDecision(
  id = "DECISION-0312",
  reason = "P4 finalization: maps CounterexampleVerdict to VerificationResult; cvConfirmed promotes to vsDisproved (I3 invariant: DISPROVED iff solver SAT and validation passed), cvSpurious/cvUnresolved preserves rkCandidateCounterexample",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  case verdict
  of cvConfirmed:
    result = makeDisproved(smBMC, candidate.provenance, psBounded)
    result.model = candidate.model
    result.solverStatus = solverSat
  of cvSpurious, cvUnresolved:
    result = candidate

{.pop.}