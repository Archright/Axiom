import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/trusted/axiom_pragmas
import core/trusted/candidate_evidence
import core/trusted/verification_model_types
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt

func synthesizeCandidateEvidence*(model: VerificationModel): CandidateEvidence {.axiomDecision(
  id = "DECISION-0310",
  reason = "Interval invariant synthesizer for single-counter accumulator loops (C20: second candidate-evidence source alongside solver-derived certs)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  if model.semantic.states.len != 1:
    return CandidateEvidence()
  let sv = model.semantic.states[0]

  if model.semantic.initExprs.len != 1:
    return CandidateEvidence()
  let initExpr = model.semantic.initExprs[0]
  if initExpr == nil or initExpr.kind != irLit:
    return CandidateEvidence()
  let c0 = initExpr.litVal

  if model.semantic.transitions.len != 1:
    return CandidateEvidence()
  let tr = model.semantic.transitions[0]

  if tr.guard == nil or tr.guard.kind != irBinOp or tr.guard.binOp != boLt:
    return CandidateEvidence()
  let gLhs = tr.guard.binLhs
  let gRhs = tr.guard.binRhs
  if gLhs == nil or gRhs == nil:
    return CandidateEvidence()
  if gLhs.kind != irVar or gLhs.varName != sv.name:
    return CandidateEvidence()
  if gRhs.kind != irLit:
    return CandidateEvidence()
  let b = gRhs.litVal

  if tr.update.assignments.len != 1:
    return CandidateEvidence()
  let assign = tr.update.assignments[0]
  if assign.symbol != sv.name:
    return CandidateEvidence()
  let updExpr = assign.expr
  if updExpr == nil or updExpr.kind != irBinOp or updExpr.binOp != boAdd:
    return CandidateEvidence()
  let addLhs = updExpr.binLhs
  let addRhs = updExpr.binRhs
  if addLhs == nil or addRhs == nil:
    return CandidateEvidence()
  var k: int64 = -1
  if addLhs.kind == irVar and addLhs.varName == sv.name and addRhs.kind == irLit:
    k = addRhs.litVal
  elif addRhs.kind == irVar and addRhs.varName == sv.name and addLhs.kind == irLit:
    k = addLhs.litVal
  else:
    return CandidateEvidence()
  if k <= 0:
    return CandidateEvidence()

  let c0Smt = irExprToSmt(irLit(c0))
  let bSmt = irExprToSmt(irLit(b))
  let invFormula = "(and (bvuge " & sv.name & " " & c0Smt & ") (bvule " & sv.name & " " & bSmt & "))"

  result = candidateEvidence(cesSynthesizer, @[("state", invFormula)], provenance="axiom:interval", fingerprint="")

{.pop.}