import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/strutils

import core/solver/types
import core/solver/expr_serialize
import ../../core/trusted/axiom_pragmas

## Emit Smt2.
func emitSmt2*(req: SolverRequest): string {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  var lines: seq[string] = @[]
  lines.add("(set-logic " & logicKindString(req.logic) & ")")
  for decl in req.declarations:
    lines.add("(declare-const " & decl & " Int)")
  for precondition in req.preconditions:
    lines.add("(assert " & toSmt(precondition) & ")")
  for (label, precondition) in req.labeledPreconditions:
    lines.add("(assert (! " & toSmt(precondition) & " :named " & label & "))")
  if req.checkSat:
    lines.add("(check-sat)")
  for assertion in req.assertions:
    lines.add("(assert " & toSmt(assertion) & ")")
  for (label, assertion) in req.labeledAssertions:
    lines.add("(assert (! " & toSmt(assertion) & " :named " & label & "))")
  if req.checkSat:
    lines.add("(check-sat)")
  if req.getModel:
    lines.add("(get-model)")
  if req.getUnsatCore:
    lines.add("(get-unsat-core)")
  lines.join("\n")

{.pop.}

{.pop.}
