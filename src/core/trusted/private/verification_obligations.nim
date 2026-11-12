import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import std/sequtils
import std/strutils
import core/trusted/axiom_ir
import core/trusted/axiom_pragmas
import core/trusted/ir_to_smt
import core/trusted/verification_model_types
import core/trusted/private/identity_core
import core/trusted/private/identity_mapping
import core/trusted/private/transition_formula_builder

## P2/P4 — Verification Obligation Model (backend-agnostic, VM semantic layer).
##
## Obligations are a VerificationModel semantic concept, NOT a CHC concept. CHC
## and Evidence are two ENCODING strategies of the SAME obligation model.
##
## P4 disjunction: the transition relation is the union over edges. Consecution
## is PER-EDGE — `Inv_A(x) /\ Trans_AB(x,x') /\ ¬Inv_B(x')` — so a certificate's
## per-relation invariants must be tied to the edge's TARGET relation via C14
## identity, never to a single monolithic "state" invariant.

type
  InitiationObligation* = object
    relationId*: string
    sourceNode*: NodeId
    initConjuncts*: seq[string]       ## SMT conjuncts at the entry state

  ConsecutionObligation* = object
    ## Per-edge consecution (P4): Inv(source) /\ Trans(target) [on this edge]
    ## is checked against the TARGET relation's invariant.
    relationId*: string
    sourceNode*: NodeId
    targetNode*: NodeId
    transitionIndex*: int             ## index into model.semantic.transitions
    guardSmt*: string                 ## from the semantic kernel (C5.1)
    postArgsSmt*: seq[string]         ## per-state post expressions (kernel)

  SafetyObligation* = object
    relationId*: string
    exitNode*: NodeId
    propertySmt*: string              ## safety property at the exit

  VerificationObligations* = object
    initiations*: seq[InitiationObligation]
    consecutions*: seq[ConsecutionObligation]
    safeties*: seq[SafetyObligation]
    relationMap*: SemanticToCanonicalMap

func buildInitiations*(model: VerificationModel): seq[InitiationObligation] {.axiomDecision(
  id = "DECISION-0401",
  reason = "Init is not a transition (kernel is Transition-only per §0.2 God-Object prevention); irExprToSmt is architecturally correct for init conjuncts. State variable names match the kernel's stateNames ordering (consistency with buildConsecutions).",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v33").} =
  ## Initiation family: the entry-state conjuncts (= stateVar initExpr).
  let sem = model.semantic
  if sem.states.len != sem.initExprs.len or sem.states.len == 0:
    return @[]
  var conjuncts: seq[string] = @[]
  for i, st in sem.states:
    conjuncts.add("(= " & st.name & " " & irExprToSmt(sem.initExprs[i]) & ")")
  @[InitiationObligation(
    relationId: "rel_state",
    sourceNode: NodeId(0),
    initConjuncts: conjuncts
  )]

func buildConsecutions*(model: VerificationModel): seq[ConsecutionObligation] {.axiomDecision(
  id = "DECISION-0402",
  reason = "Consecution IS a transition obligation; kernel (buildTransitionFormula) is the single source of truth for post-state per C5.1 Golden semantics.",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v33").} =
  ## Consecution family — ONE obligation PER EDGE (P4 disjunction).
  let sem = model.semantic
  var builder = newTransitionFormulaBuilder(sem.states.mapIt(it.name))
  result = @[]
  for i, tr in sem.transitions:
    var fresh = 0
    let formula = buildTransitionFormula(builder, tr, fresh)
    result.add(ConsecutionObligation(
      relationId: "rel_state",
      sourceNode: tr.source,
      targetNode: tr.target,
      transitionIndex: i,
      guardSmt: formula.guardSmt,
      postArgsSmt: formula.postArgs.mapIt(it.nextSmt)
    ))

func buildSafeties*(model: VerificationModel): seq[SafetyObligation] {.axiomDecision(
  id = "DECISION-0403",
  reason = "Safety property is not a transition (kernel is Transition-only); irExprToSmt is architecturally correct for property extraction.",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v33").} =
  ## Safety family: the property that must hold at the exit.
  let sem = model.semantic
  result = @[]
  var propSmt: string
  if sem.property.isSome and sem.property.get != nil:
    # P2: substitute the function-return state var for `result` before SMT
    # emission. sem.resultStateName is set by loop lowering (mirrors the
    # legacy buildChcProperty ("result", loopVars[^1]) substitution) so the
    # CHC error rule is well-formed over declared state vars.
    var propIr = sem.property.get
    if sem.resultStateName.isSome:
      ## Rename the `result` var to the loop's last state var name (mirrors the
      ## legacy buildChcProperty ("result", loopVars[^1]) substitution) so the
      ## emitted CHC property references a declared state variable.
      let resultStateName = sem.resultStateName.get
      propIr = substVarsInExpr(propIr, @[("result", resultStateName)])
    elif sem.states.len > 0:
      ## when a loop var is produced by the old indirect path,
      ## the last state var is the result accumulator (mirrors loopVars[^1]).
      propIr = substVarsInExpr(propIr, @[("result", sem.states[^1].name)])
    propSmt = irExprToSmt(propIr)
  elif sem.obligations.len > 0:
    var preds: seq[string] = @[]
    for ob in sem.obligations:
      if ob.predicate != nil:
        var predIr = ob.predicate
        if sem.resultStateName.isSome:
          let resultStateName = sem.resultStateName.get
          predIr = substVarsInExpr(predIr, @[("result", resultStateName)])
        elif sem.states.len > 0:
          ## when a loop var is produced by the old indirect path,
          ## the last state var is the result accumulator (mirrors loopVars[^1]).
          predIr = substVarsInExpr(predIr, @[("result", sem.states[^1].name)])
        preds.add(irExprToSmt(predIr))
    propSmt = if preds.len == 1: preds[0] else: "(and " & preds.join(" ") & ")"
  else:
    return @[]
  result.add(SafetyObligation(
    relationId: "rel_state",
    exitNode: model.metadata.functionExit,
    propertySmt: propSmt
  ))

func buildObligations*(model: VerificationModel): VerificationObligations {.axiomDecision(
  id = "DECISION-0404",
  reason = "Aggregates all three obligation families; consecution is kernel-derived, init/safety are property-level (not transition-level) per §0.2 God-Object prevention.",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v33").} =
  ## Derive the three obligation families (C10) from the semantic model.
  var relationMap: SemanticToCanonicalMap
  for tr in model.semantic.transitions:
    relationMap.setNodeMapping(tr.source, RelationId("rel_state"))
    relationMap.setNodeMapping(tr.target, RelationId("rel_state"))
  VerificationObligations(
    initiations: buildInitiations(model),
    consecutions: buildConsecutions(model),
    safeties: buildSafeties(model),
    relationMap: relationMap
  )

{.pop.}