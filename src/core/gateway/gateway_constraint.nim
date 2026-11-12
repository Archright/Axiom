import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Constraint factory helpers extracted from gateway.nim.

import std/options
import core/gateway/gateway_types
import ../../core/trusted/axiom_pragmas

## Make State Constraint.
func makeStateConstraint*(): ConstraintDefinition {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ConstraintDefinition(minValue: some(0), maxValue: some(maxStateValue), invariant: none(NumericInvariantProc))

## Make Input Constraint.
func makeInputConstraint*(): ConstraintDefinition {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ConstraintDefinition(minValue: some(0), maxValue: some(maxStateValue), invariant: none(NumericInvariantProc))

{.pop.}

{.pop.}
