import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils
import std/tables
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import verification/solver/z3_pool
import core/results

type
  ImplicationResult* = enum
    irImplied
    irNotImplied
    irUnknown

func collectVarTypes(e: IRExpr, vars: var Table[string, IRType]) =
  if e == nil: return
  case e.kind
  of irVar:
    if e.varName.len > 0 and e.varName notin vars:
      vars[e.varName] = e.varType
  of irLet:
    collectVarTypes(e.letVal, vars)
    collectVarTypes(e.letBody, vars)
  of irIf:
    collectVarTypes(e.ifCond, vars)
    collectVarTypes(e.ifThen, vars)
    collectVarTypes(e.ifElse, vars)
  of irCase:
    collectVarTypes(e.caseScrutinee, vars)
    for br in e.caseBranches:
      collectVarTypes(br.body, vars)
    collectVarTypes(e.caseDefault, vars)
  of irCall:
    for a in e.callArgs:
      collectVarTypes(a, vars)
  of irBinOp:
    collectVarTypes(e.binLhs, vars)
    collectVarTypes(e.binRhs, vars)
  of irUnaryOp:
    collectVarTypes(e.unaryArg, vars)
  of irRecCall:
    for a in e.recArgs:
      collectVarTypes(a, vars)
  of irLoop:
    for a in e.loopInits:
      collectVarTypes(a, vars)
    collectVarTypes(e.loopCond, vars)
    collectVarTypes(e.loopStep, vars)
    collectVarTypes(e.loopBody, vars)
    for inv in e.loopInvariants:
      collectVarTypes(inv, vars)
    collectVarTypes(e.loopVariant, vars)
  of irCast:
    collectVarTypes(e.castExpr, vars)
  else: discard

proc buildImplicationSmt*(invariant: IRExpr, postCondition: IRExpr): string {.raises: [].} =
  if invariant == nil or postCondition == nil:
    return ""
  let negPost = irUnaryOp(uoNot, postCondition)
  let conjunction = irBinOp(boAnd, invariant, negPost)
  let smtBody = irExprToSmt(conjunction, 0)
  if smtBody.len == 0:
    return ""
  var freeVars: Table[string, IRType]
  collectVarTypes(invariant, freeVars)
  collectVarTypes(postCondition, freeVars)
  var decls = ""
  for name, typ in freeVars:
    decls.add("(declare-fun " & name & " () " & irTypeToSmt(typ) & ")\n")
  "(set-logic QF_BV)\n" & decls & "(assert " & smtBody & ")\n(check-sat)\n"

proc checkImplication*(invariant: IRExpr, postCondition: IRExpr): ImplicationResult {.raises: [].} =
  let smtQuery = buildImplicationSmt(invariant, postCondition)
  if smtQuery.len == 0:
    return irUnknown
  try:
    var implCanonicalDigest, implTransportDigest: string
    let z3Res = z3ExecPersistent(smtQuery, timeoutMs = 500,
      canonicalEnvelopeDigest = implCanonicalDigest, transportPayloadDigest = implTransportDigest)
    if z3Res.isOk:
      let output = z3Res.get().strip().toLowerAscii()
      if output == "unsat":
        return irImplied
      elif output == "sat":
        return irNotImplied
    return irUnknown
  except CatchableError:
    return irUnknown

proc checkAllImplications*(invariants: seq[IRExpr], postConditions: seq[IRExpr]): ImplicationResult {.raises: [].} =
  if postConditions.len == 0:
    return irImplied
  if invariants.len == 0:
    return irUnknown
  var combinedInvariant = invariants[0]
  for i in 1 ..< invariants.len:
    combinedInvariant = irBinOp(boAnd, combinedInvariant, invariants[i])
  for pc in postConditions:
    let implResult = checkImplication(combinedInvariant, pc)
    if implResult != irImplied:
      return implResult
  irImplied
