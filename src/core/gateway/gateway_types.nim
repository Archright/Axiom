import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/types/domain_types
import core/types/results
import std/options
type
  NumericInvariantProc* = proc(value: int): bool {.raises: [], noSideEffect, gcsafe.}
  RelationalInvariantProc* = proc(stateValue: int; inputDelta: int): bool {.raises: [], noSideEffect, gcsafe.}
  ConstraintDefinition* = object
    minValue*: Option[int]
    maxValue*: Option[int]
    invariant*: Option[NumericInvariantProc]
  InputConstraintDefinition* = object
    stateConstraint*: ConstraintDefinition
    inputConstraint*: ConstraintDefinition
    relationalInvariant*: Option[proc(stateValue: int; inputDelta: int): bool {.closure, raises: [], noSideEffect, gcsafe.}]
  makeInputConstraintDefinition* = object
    stateConstraint*: ConstraintDefinition
    inputConstraint*: ConstraintDefinition
    relationalInvariant*: Option[proc(stateValue: int; inputDelta: int): bool {.closure, raises: [], noSideEffect, gcsafe.}]

  TypeConstraintKind* = enum
    tcRange
    tcNonEmpty
    tcLength
    tcRefinement
    tcEnum

  TypeConstraint* = object
    kind*: TypeConstraintKind
    varName*: string
    nimType*: string
    smtSort*: string
    lowerBound*: Option[int]
    upperBound*: Option[int]
    allowedValues*: seq[string]
    refinementExpr*: string
const
  maxStateValue* = 1_000_000_000

## Some.
func some*(
  invariant: proc(stateValue: int; inputDelta: int): bool {.raises: [], noSideEffect, gcsafe.}
): Option[proc(stateValue: int; inputDelta: int): bool {.closure, raises: [], noSideEffect, gcsafe.}] {.raises: [], inline, axiom: ["(assert true)", "true"].} =
  options.some(proc(stateValue: int; inputDelta: int): bool {.closure, raises: [], noSideEffect, gcsafe.} =
    invariant(stateValue, inputDelta)
  )

## Make Constraint Definition (non-noSideEffect overload removed —
## callers always pass noSideEffect procs, resolved by func overload above).
converter toInputConstraintDefinition*(
  c: makeInputConstraintDefinition
): InputConstraintDefinition {.raises: [], inline.} =
  InputConstraintDefinition(
    stateConstraint: c.stateConstraint,
    inputConstraint: c.inputConstraint,
    relationalInvariant: c.relationalInvariant
  )

## Require Length.
func requireLen*(raw: string; expected: int; errValue: AxiomError): Result[string, AxiomError] {.
  raises: [],
  requires: expected > 0,
  ensures: (not result.isOk()) or (result.get() == raw and result.get().len == expected)
.} =
  if raw.len != expected:
    return err(errValue)
  ok(raw)

## Make Constraint Definition.
func makeConstraintDefinition*(
  minValue: Option[int];
  maxValue: Option[int];
  invariant: Option[NumericInvariantProc] = none(NumericInvariantProc)
): Result[ConstraintDefinition, AxiomError] {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  if minValue.isSome() and maxValue.isSome() and minValue.get() > maxValue.get():
    return err(axiomErrInvalidValue)
  ok(ConstraintDefinition(minValue: minValue, maxValue: maxValue, invariant: invariant))

## Gatekeep Numeric Input.
func gatekeepNumericInput*(value: int; constraint: ConstraintDefinition): Result[int, AxiomError] {.raises: [], inline, axiom: ["(assert (and (and (>= value -9223372036854775808) (<= value 9223372036854775807))))", "value >= -9223372036854775808 ∧ value <= 9223372036854775807"].} =
  if constraint.minValue.isSome() and value < constraint.minValue.get():
    return err(axiomErrInvalidValue)
  if constraint.maxValue.isSome() and value > constraint.maxValue.get():
    return err(axiomErrInvalidValue)
  if constraint.invariant.isSome() and not constraint.invariant.get()(value):
    return err(axiomErrInvalidValue)
  ok(value)

## Gatekeep Refinement Range.
func gatekeepRefinementRange*(
  value: int;
  minValue: int;
  maxValue: int
): Result[int, AxiomError] {.
  axiom: ["(assert (and (>= value -9223372036854775808) (<= value 9223372036854775807)))", "value >= -9223372036854775808 ∧ value <= 9223372036854775807"],
  raises: [],
  requires: minValue <= maxValue,
  ensures:
    (not result.isOk()) or
    (result.get() >= minValue and result.get() <= maxValue)
.} =
  let constraintRes = ??makeConstraintDefinition(some(minValue), some(maxValue))
  gatekeepNumericInput(value, constraintRes)
proc requireLen*(raw: string; expected: int; errValue: AxiomError): Result[string, AxiomError] {.
  raises: [],
  requires: expected > 0,
  ensures: (not result.isOk()) or (result.get() == raw and result.get().len == expected)
.} =
  if raw.len != expected:
    return err(errValue)
  ok(raw)

{.pop.}
