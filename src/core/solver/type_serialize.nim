import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Solver Status & Logic Kind Serialization
##
## Pure case-dispatch functions for converting solver domain enums
## to their string representations. Imports bare_types (not types)
## to avoid circular dependency.
##
## Import graph: bare_types.nim → type_serialize.nim (one-directional)

import core/types/domain_types
import core/types/solver_types
import core/solver/bare_types
import ../trusted/axiom_pragmas_lite

export solver_types.SolverStatus

## Solver Status String.
func solverStatusString*(status: SolverStatus): string {.inline, raises: [], axiom: ["(assert (and solverSat solverUnsat solverUnknown solverTimeout solverVacuousContradiction))", "solverSat ∧ solverUnsat ∧ solverUnknown ∧ solverTimeout ∧ solverVacuousContradiction"].} =
  case status
  of solverSat:
    "sat"
  of solverUnsat:
    "unsat"
  of solverUnknown:
    "unknown"
  of solverTimeout:
    "timeout"
  of solverVacuousContradiction:
    "vacuous_contradiction"

## Logic Kind String.
func logicKindString*(logic: LogicKind): string {.inline, raises: [], axiom: ["(assert (and logicQfLia))", "logicQfLia"].} =
  case logic
  of logicQfLia:
    "QF_LIA"

{.pop.}
{.pop.}
