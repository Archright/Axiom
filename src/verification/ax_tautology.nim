import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import verification/solver/z3_pool

type
  TautologyCheckResult* = enum
    tcNonTautology
    tcTautology
    tcUnknown

proc conditionToSmt(negated: IRExpr): string =
  let negSmt = irExprToSmt(negated)
  if negSmt.len == 0:
    return ""
  result = "(set-logic QF_BV)\n(assert " & negSmt & ")\n(check-sat)\n"

proc checkTautology*(condition: IRExpr): TautologyCheckResult =
  if condition == nil:
    return tcTautology
  let negated = irUnaryOp(uoNot, condition)
  let smtScript = conditionToSmt(negated)
  if smtScript.len == 0:
    return tcUnknown
  try:
    var tautCanonicalDigest, tautTransportDigest: string
    let res = z3ExecPersistent(smtScript, timeoutMs = 500,
      canonicalEnvelopeDigest = tautCanonicalDigest, transportPayloadDigest = tautTransportDigest)
    if res.isOk:
      let output = res.get().strip().toLowerAscii()
      if output == "unsat":
        return tcTautology
      elif output == "sat":
        return tcNonTautology
    return tcUnknown
  except CatchableError:
    return tcUnknown

proc checkInvariantVacuity*(preConditions: seq[IRExpr]): TautologyCheckResult =
  for pc in preConditions:
    let r = checkTautology(pc)
    if r == tcTautology:
      return tcTautology
    if r == tcUnknown:
      return tcUnknown
  tcNonTautology

{.pop.}
