import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

{.push, raises: [].}
# axiomIoBoundary
{.push, noSideEffect.}
import
  core / bmc / bmc_race

import
  core / solver / types

import
  core / solver / construct_base

import
  core / solver / construct_logical

## Encode Invariant Predicate.
func encodeInvariantPredicate*(symbol: string;
    rule: TransitionRule): SmtSExpr {.
    inline, raises: [].} =
  case rule.invariant.kind
  of invariantMinValue:
    ge(symInt(symbol), intLit(rule.invariant.minValue))
  of invariantMaxValue:
    le(symInt(symbol), intLit(rule.invariant.maxValue))

## Encode Invariant Violation.
func encodeInvariantViolation*(symbol: string;
    rule: TransitionRule): SmtSExpr {.
    inline, raises: [].} =
  notE(encodeInvariantPredicate(symbol, rule))

## Encode Reachable And Violation.
func encodeReachableAndViolation*(transitionAssertions: seq[SmtSExpr];
                                  violation: SmtSExpr): seq[SmtSExpr] {.
    raises: [].} =
  result = @[]
  for a in transitionAssertions:
    result.add(a)
  result.add(violation)

## Make Zero Runtime Error Query.
func makeZeroRuntimeErrorQuery*(declarations: seq[string];
                                transitionAssertions: seq[SmtSExpr];
                                finalSymbol: string;
                                    rule: TransitionRule): SolverRequest {.
    raises: [].} =
  SolverRequest(logic: logicQfLia, declarations: declarations,
                preconditions: transitionAssertions,
                assertions: @[encodeInvariantViolation(finalSymbol, rule)],
                finalStateSymbol: finalSymbol, checkSat: true, getModel: true,
                getUnsatCore: true)

{.pop.}

{.pop.}

{.pop}
