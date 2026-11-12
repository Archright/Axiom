import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/boundary/gateway/gateway_generator
import core/boundary/gateway/gateway_spec
import core/gateway/gateway_constraint
import core/gateway/gateway_json
import core/gateway/gateway_main
import core/gateway/gateway_types
import core/types/domain_types
import core/types/results
import std/options
import std/strutils
export gateway_json
export gateway_main
export gateway_generator
export gateway_spec
export domain_types

## Gatekeep State Input.
func gatekeepStateInput*(
  stateValue: int;
  inputDelta: int;
  constraints: InputConstraintDefinition = InputConstraintDefinition(
    stateConstraint: makeStateConstraint(),
    inputConstraint: makeInputConstraint(),
    relationalInvariant: none(proc(stateValue: int; inputDelta: int): bool {.closure, raises: [], noSideEffect, gcsafe.})
  )
): Result[(int, int), AxiomError] {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807"].} =
  let stateConstraint =
    if constraints.stateConstraint.minValue.isNone() and
      constraints.stateConstraint.maxValue.isNone() and
      constraints.stateConstraint.invariant.isNone():
      makeStateConstraint()
    else:
      constraints.stateConstraint
  let inputConstraint =
    if constraints.inputConstraint.minValue.isNone() and
      constraints.inputConstraint.maxValue.isNone() and
      constraints.inputConstraint.invariant.isNone():
      makeInputConstraint()
    else:
      constraints.inputConstraint
  let safeState = ??gatekeepNumericInput(stateValue, stateConstraint)
  let safeInput = ??gatekeepNumericInput(inputDelta, inputConstraint)
  if constraints.relationalInvariant.isSome() and not constraints.relationalInvariant.get()(safeState, safeInput):
    return err(axiomErrInvalidValue)
  ok((safeState, safeInput))

## Emit Type Constraint As Smt.
func emitTypeConstraintAsSmt*(c: TypeConstraint): string {.raises: [], axiom: ["(assert (and (= (str.len parts) 0) (= (str.len parts) 1) (= (str.len eqs) 1)))", "parts.length = 0 ∧ parts.length = 1 ∧ eqs.length = 1"].} =
  ## Emit a single type constraint as an SMT-LIB2 assertion.
  case c.kind
  of tcRange:
    var parts: seq[string] = @[]
    if c.lowerBound.isSome:
      parts.add("(>= " & c.varName & " " & $c.lowerBound.get() & ")")
    if c.upperBound.isSome:
      parts.add("(<= " & c.varName & " " & $c.upperBound.get() & ")")
    if parts.len == 0:
      return ""
    if parts.len == 1:
      return "(assert " & parts[0] & ")"
    return "(assert (and " & parts.join(" ") & "))"
  of tcNonEmpty:
    if c.smtSort == "String":
      return "(assert (> (str.len " & c.varName & ") 0))"
    return "(assert (> (seq.len " & c.varName & ") 0))"
  of tcLength:
    if c.lowerBound.isSome and c.upperBound.isSome:
      return "(assert (and (>= (seq.len " & c.varName & ") " & $c.lowerBound.get() & ") (<= (seq.len " & c.varName & ") " & $c.upperBound.get() & ")))"
    if c.lowerBound.isSome:
      return "(assert (>= (seq.len " & c.varName & ") " & $c.lowerBound.get() & "))"
    if c.upperBound.isSome:
      return "(assert (<= (seq.len " & c.varName & ") " & $c.upperBound.get() & "))"
    return ""
  of tcRefinement:
    if c.refinementExpr.len > 0:
      return "(assert " & c.refinementExpr.replace("$var", c.varName) & ")"
    return ""
  of tcEnum:
    if c.allowedValues.len > 0:
      var eqs: seq[string] = @[]
      for v in c.allowedValues:
        eqs.add("(= " & c.varName & " " & v & ")")
      if eqs.len == 1:
        return "(assert " & eqs[0] & ")"
      return "(assert (or " & eqs.join(" ") & "))"
    return ""

## Emit Type Constraints As Smt.
func emitTypeConstraintsAsSmt*(constraints: seq[TypeConstraint]): string {.raises: [], axiom: ["(assert (and (> (str.len line) 0) (>= result 0) (>= constraints 0)))", "line.length > 0 ∧ (result >= 0) ∧ (constraints >= 0)"].} =
  var lines: seq[string] = @[]
  for c in constraints:
    let line = emitTypeConstraintAsSmt(c)
    if line.len > 0:
      lines.add(line)
  result = lines.join("\n")

## Gatekeep State Input.
# @axiom-hint: lean="stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807" smt="(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))"
