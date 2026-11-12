import core/trusted/layer_declaration
axiomLayer "domain"
import std/[strutils, sequtils]
import core/axiom_pragmas
import core/ir/ir_types
import core/results
import verification/solver/z3_pool

const NonVacuityTimeoutMs* = 30_000

proc smtSymbol*(name: string): string {.raises: [].} =
  if name.len == 0:
    return "true"
  var ok = true
  for ch in name:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      discard
    else:
      ok = false
      break
  if ok:
    result = name
  else:
    result = "|" & name.replace("|", "||") & "|"

proc smtConst*(value: string): string {.raises: [].} =
  let v = value.strip()
  if v.len == 0:
    return "true"
  let lower = v.toLowerAscii()
  if lower == "true":
    return "true"
  if lower == "false":
    return "false"
  result = v

proc smtBinaryOp*(op: string): string {.raises: [].} =
  case op.strip().toLowerAscii()
  of "==", "=":
    "="
  of "!=", "not=":
    "not="
  of ">=", "<=", ">", "<":
    op.strip()
  of "and", "&&", "andalso":
    "and"
  of "or", "||", "oro":
    "or"
  else:
    op.strip()

proc convertToSmt*(expr: IRExpr): string {.raises: [].} =
  if expr.isNil:
    return "true"
  case expr.kind
  of ieVar:
    result = smtSymbol(expr.varName)
  of ieConst:
    result = smtConst(expr.val)
  of ieBinaryOp:
    let left = convertToSmt(expr.left)
    let right = convertToSmt(expr.right)
    result = "(" & smtBinaryOp(expr.op) & " " & left & " " & right & ")"
  of ieApp:
    let fnName = expr.fnName.strip().toLowerAscii()
    case fnName
    of "and":
      if expr.args.len == 0:
        result = "true"
      else:
        result = "(and " & expr.args.mapIt(convertToSmt(it)).join(" ") & ")"
    of "or":
      if expr.args.len == 0:
        result = "false"
      else:
        result = "(or " & expr.args.mapIt(convertToSmt(it)).join(" ") & ")"
    of "not", "!", "not=":
      if expr.args.len == 0:
        result = "false"
      else:
        result = "(not " & convertToSmt(expr.args[0]) & ")"
    else:
      result = "true"
  of ieRefinement:
    if expr.predicate.isNil:
      result = "true"
    else:
      result = convertToSmt(expr.predicate)

proc gateToSmtLib2*(ir: AxiomIRNode): string {.raises: [].} =
  result = "(set-logic QF_LIA)\n"
  if ir.isNil:
    result.add("(declare-const |result| Int)\n")
  else:
    for param in ir.params:
      let paramName = smtSymbol(param.name)
      result.add("(declare-const |" & paramName & "| Int)\n")
  result.add("(declare-const |result| Int)\n")

  for preCond in ir.preConditions:
    let smtExpr = convertToSmt(preCond)
    if smtExpr != "true":
      result.add("(assert " & smtExpr & ")\n")

  if ir != nil and ir.body != nil:
    let bodySmt = convertToSmt(ir.body)
    if bodySmt != "":
      result.add("(assert " & bodySmt & ")\n")

  result.add("(assert (not (= |result| 0)))\n")
  result.add("(check-sat)\n")

proc runZ3WithQuery*(query: string; timeoutMs: int = NonVacuityTimeoutMs):
    Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect], raises: [].} =
  var gateCanonicalDigest, gateTransportDigest: string
  z3ExecPersistent(query, timeoutMs,
    canonicalEnvelopeDigest = gateCanonicalDigest, transportPayloadDigest = gateTransportDigest)

proc verifyNonVacuity*(ir: AxiomIRNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  let smtQuery = gateToSmtLib2(ir)
  let z3Result = runZ3WithQuery(smtQuery)
  if z3Result.isOk:
    let output = z3Result.get().strip().toLowerAscii()
    return output == "sat" or output.startsWith("sat ") or output.startsWith("sat\n")
  else:
    return false
