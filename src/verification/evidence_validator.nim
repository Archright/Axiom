import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/[options, sequtils, strutils, tables]
import core/trusted/axiom_pragmas
import core/trusted/private/verification_obligations
import core/trusted/private/transition_formula_builder
import core/trusted/ir_to_smt
import core/trusted/verification_model_types
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import verification/obligation_discharger
import core/types/solver_types

type
  ValidatedEvidence* = object
    initiations*: seq[ObligationResult]
    consecutions*: seq[ObligationResult]
    safety*: seq[ObligationResult]
    overall*: VerificationResult

  EvidenceValidator* = object
    discharger*: ObligationDischarger

proc newEvidenceValidator*(z3Path: string = "z3"; timeoutMs: int = 5000): EvidenceValidator {.axiomDecision(
  id = "DECISION-0308",
  reason = "Constructs EvidenceValidator with a Z3-backed ObligationDischarger (C17)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  EvidenceValidator(discharger: newObligationDischarger(z3Path, timeoutMs))

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

func aggregateSolverStatus(results: seq[ObligationResult]): SolverStatus {.raises: [].} =
  for r in results:
    let s = parseSolverStatus(r.solverStatus)
    if s == solverSat:
      return solverSat
  for r in results:
    let s = parseSolverStatus(r.solverStatus)
    if s == solverTimeout:
      return solverTimeout
  for r in results:
    let s = parseSolverStatus(r.solverStatus)
    if s == solverUnknown:
      return solverUnknown
  solverUnsat

# ── Obligation query construction ─────────────────────────────────────────────
func stateArgs(model: VerificationModel): seq[string] {.raises: [].} =
  model.semantic.states.mapIt(it.name)

func preStateExpr(model: VerificationModel): string {.raises: [].} =
  "(state " & stateArgs(model).join(" ") & ")"

func isIdentChar(c: char): bool {.raises: [].} =
  c.isAlphaNumeric or c == '_'

func replaceVarToken(s, name, repl: string): string {.raises: [].} =
  ## Word-boundary replacement: substitute the state-var token `name` with the
  ## successor SMT term `repl` inside an invariant formula.
  result = ""
  var i = 0
  while i < s.len:
    if i + name.len <= s.len and s[i ..< i + name.len] == name and
       (i == 0 or not isIdentChar(s[i - 1])) and
       (i + name.len == s.len or not isIdentChar(s[i + name.len])):
      result.add(repl)
      i += name.len
    else:
      result.add(s[i])
      inc i

func postInvariantConjunct(model: VerificationModel; inv: string): string {.axiomDecision(
  id = "DECISION-0319",
  reason = "Constructs the post-state invariant conjunct Inv(θ(x)) by substitution over the semantic-kernel successor expressions, forming the genuinely-inductive consecution consequent (P4)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32"), raises: [].} =
  ## Apply the invariant to the POST-state by substituting each state-var name
  ## with its semantic-kernel successor expression, so the consecution PO is
  ## the genuinely inductive check `Inv(x) ∧ Guard(x) ⇒ Inv(θ(x))` (P4), never
  ## the vacuous transition-closure `Inv(x) ∧ Guard ⇒ (state θ(x))`.
  if model.semantic.transitions.len == 0 or inv.len == 0:
    return ""
  var builder = newTransitionFormulaBuilder(model.semantic.states.mapIt(it.name))
  var fresh = 0
  let formula = buildTransitionFormula(builder, model.semantic.transitions[0], fresh)
  if formula.postArgs.len != model.semantic.states.len:
    return ""
  result = inv
  for i, st in model.semantic.states:
    result = replaceVarToken(result, st.name, formula.postArgs[i].nextSmt)

func exitGuardConjunct(model: VerificationModel): string {.raises: [].} =
  ## SMT for "loop is exited" (¬ loop condition). Safety obligations must be
  ## discharged at the exit, not over every loop state (P4 obligation shape).
  if model.semantic.exitGuard.isSome and model.semantic.exitGuard.get != nil:
    let g = irExprToSmt(model.semantic.exitGuard.get)
    if g != "true" and g.len > 0:
      return "(not " & g & ")"
  "true"

func smtDeclarations(model: VerificationModel): string {.raises: [].} =
  var lines: seq[string] = @[]
  let stateSorts = model.semantic.states.mapIt(irTypeToSmt(it.irType)).join(" ")
  lines.add("(declare-fun state (" & stateSorts & ") Bool)")
  for st in model.semantic.states:
    lines.add("(declare-const " & st.name & " " & irTypeToSmt(st.irType) & ")")
  lines.join("\n")

proc proveImplication(validator: EvidenceValidator; name: string; model: VerificationModel; antecedent, consequent: string): ObligationResult {.raises: [].} =
  ## PO: assert not (antecedent => consequent), expect UNSAT (never holds that
  ## antecedent ∧ ¬consequent).
  let decls = smtDeclarations(model)
  # No `set-logic` (default logic): HORN rejects the non-HORN `(not (=> ...))`
  # validity check (returns `unknown`), and QF_* logics forbid the `state`
  # uninterpreted predicate. The default logic admits BV + UF.
  let script =
    (if decls.len > 0: decls & "\n" else: "") &
    "(assert (not (=> " & antecedent & " " & consequent & ")))\n" &
    "(check-sat)\n"
  result = validator.discharger.discharge(script)
  result.obligationName = name
  if result.passed:
    result.errorMessage = ""
  else:
    result.errorMessage = result.solverStatus

proc validate*(validator: EvidenceValidator; model: VerificationModel; ce: CandidateEvidence): ValidatedEvidence {.axiomDecision(
  id = "DECISION-0309",
  reason = "C18+C20: validate consumes neutral CandidateEvidence via the Obligation Model (buildObligations); gates missing evidence (C20) to prevent proving without invariants; consecution/safety use per-edge obligation data from the kernel",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  ## Validate a CandidateEvidence against a VerificationModel via the three
  ## obligation families derived from the Obligation Model. Produces ValidatedEvidence;
  ## Safe requires all three families to pass and non-empty evidence (C18, C20).
  var evidence = ValidatedEvidence()

  if model.semantic.states.len == 0:
    evidence.overall = makeInconclusive(rkNotEncodable)
    return evidence

  # C20 gate: missing evidence → Inconclusive; obligation families still computed
  # but overall must never be Proved without evidence.
  let hasEvidence = not ce.isEmpty()

  let inv = ce.invariants.getOrDefault("state", "")
  let obligations = buildObligations(model)

  # Family 1 — Initiation (PO1): Init(state) ⇒ Inv(state)
  for init in obligations.initiations:
    if init.initConjuncts.len > 0:
      let initExpr = if init.initConjuncts.len == 1: init.initConjuncts[0] else: "(and " & init.initConjuncts.join(" ") & ")"
      evidence.initiations.add(proveImplication(validator, "initiation", model, initExpr, if inv.len > 0: inv else: initExpr))

  # Family 2 — Consecution (PO2): Inv(state) ∧ Trans(state,state') ⇒ Inv(state')
  for conc in obligations.consecutions:
    if inv.len > 0:
      let consolid = postInvariantConjunct(model, inv)
      let consequent = if consolid.len > 0: consolid else: "(state " & conc.postArgsSmt.join(" ") & ")"
      evidence.consecutions.add(proveImplication(
        validator, "consecution", model,
        "(and " & inv & " " & conc.guardSmt & ")", consequent
      ))
    else:
      let pre = preStateExpr(model)
      let consequent = "(state " & conc.postArgsSmt.join(" ") & ")"
      evidence.consecutions.add(proveImplication(
        validator, "transition-closure", model,
        "(and " & pre & " " & conc.guardSmt & ")", consequent
      ))

  # Family 3 — Safety (PO3): Inv(state) ∧ ¬exitGuard ⇒ Property(state)
  for safety in obligations.safeties:
    let exitG = exitGuardConjunct(model)
    if inv.len > 0:
      let ante = if exitG == "true": inv else: "(and " & inv & " " & exitG & ")"
      evidence.safety.add(proveImplication(validator, "safety", model, ante, safety.propertySmt))
    else:
      let pre = preStateExpr(model)
      let ante = if exitG == "true": pre else: "(and " & pre & " " & exitG & ")"
      evidence.safety.add(proveImplication(validator, "safety", model, ante, safety.propertySmt))

  # ── Aggregate (C10) ──────────────────────────────────────────────────
  var allPassed = true
  for oc in evidence.initiations:
    if not oc.passed: allPassed = false
  for oc in evidence.consecutions:
    if not oc.passed: allPassed = false
  for oc in evidence.safety:
    if not oc.passed: allPassed = false

  if evidence.initiations.len == 0 and evidence.consecutions.len == 0 and evidence.safety.len == 0:
    evidence.overall = makeInconclusive(rkNotEncodable)
  elif allPassed and hasEvidence:
    let aggSolver = aggregateSolverStatus(evidence.initiations & evidence.consecutions & evidence.safety)
    if aggSolver == solverSat:
      evidence.overall = makeCandidateCounterexample("", smCHC, pkSpacer)
      evidence.overall.solverStatus = solverSat
    else:
      evidence.overall = makeProved(smCHC, pkSpacer, psUnbounded)
      evidence.overall.solverStatus = aggSolver
  else:
    let aggSolver = aggregateSolverStatus(evidence.initiations & evidence.consecutions & evidence.safety)
    case aggSolver
    of solverSat:
      evidence.overall = makeCandidateCounterexample("", smCHC, pkSpacer)
      evidence.overall.solverStatus = solverSat
    of solverTimeout:
      evidence.overall = makeTimeout()
      evidence.overall.solverStatus = solverTimeout
    of solverUnknown:
      evidence.overall = makeSolverUnknown()
      evidence.overall.solverStatus = solverUnknown
    else:
      evidence.overall = makeInconclusive(rkEvidenceRejected)
      evidence.overall.solverStatus = aggSolver

  evidence

{.pop.}