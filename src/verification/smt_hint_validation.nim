import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils
import core/judge/smart_search
import core/sync/sync_utils_process
import core/domain_types
import core/axiom_pragmas
import core/encoding/type_logic_registry
import core/types/z3_solver_config
# axiomIoBoundary

proc nimTypeToSmtType*(nimType: string): string {.raises: [].} =
  ## Forwarding stub — delegates to TypeLogicRegistry.
  ## Kept for backward compatibility. New code should use lookupTypeLogic() directly.
  lookupTypeLogic(nimType).smtSort

proc buildNegativeSmtQuery*(hint: SemanticHint): string {.raises: [].} =
  var query = "(set-logic ALL)\n"
  for pt in hint.paramTypes:
    query.add("(declare-const " & pt.name & " " & nimTypeToSmtType(pt.nimType) & ")\n")
  let assertBody = hint.smtConstraint.strip()
  var prop = ""
  if assertBody.startsWith("(assert "):
    prop = assertBody[7 .. ^1].strip()
    if prop.endsWith(")"):
      prop = prop[0 .. ^2].strip()
  else:
    prop = assertBody
  query.add("(assert (not " & prop & "))\n")
  query.add("(check-sat)\n")
  query

## Extract Z3 Proof Trace.
## Phase 4: Runs Z3 with (set-option :produce-proofs true) and captures
## the proof trace on unsat results. Returns empty string on sat or failure.
proc extractZ3ProofTrace*(hint: SemanticHint): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var query = "(set-option :produce-proofs true)\n"
  query.add("(set-logic ALL)\n")
  for pt in hint.paramTypes:
    query.add("(declare-const " & pt.name & " " & nimTypeToSmtType(pt.nimType) & ")\n")
  let assertBody = hint.smtConstraint.strip()
  var prop = ""
  if assertBody.startsWith("(assert "):
    prop = assertBody[7 .. ^1].strip()
    if prop.endsWith(")"):
      prop = prop[0 .. ^2].strip()
  else:
    prop = assertBody
  query.add("(assert " & prop & ")\n")
  query.add("(check-sat)\n")
  query.add("(get-proof)\n")
  let z3Res = runProcessWithTimeout(resolveZ3Path(), @["-smt2", "-in"], 10000, query)
  if not z3Res.timedOut and z3Res.exitCode == 0:
    let lines = z3Res.output.splitLines()
    var foundUnsat = false
    for line in lines:
      let trimmed = line.strip().toLowerAscii()
      if trimmed == "unsat":
        foundUnsat = true
        continue
      if foundUnsat and trimmed.len > 0:
        return line.strip()
  ""

proc checkSemanticContrast*(hint: SemanticHint): bool =
  ## Returns true if negated proposition is SAT (non-trivial).
  ## Returns false if UNSAT (trivial/vacuous).
  ## Fail-closed: Z3 failure/timoet → treated as vacuous (blocked).
  let query = buildNegativeSmtQuery(hint)
  let z3Res = runProcessWithTimeout(resolveZ3Path(), @["-smt2", "-in"], 10000, query)
  if not z3Res.timedOut and z3Res.exitCode == 0:
    let output = z3Res.output.strip().toLowerAscii()
    return output == "sat"
  return false  # fail-closed: Z3 failure → assume vacuous to block certification
{.pop.}
