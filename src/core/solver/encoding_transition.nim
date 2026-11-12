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
  core / solver / construct_arithmetic

import
  core / solver / construct_logical

## Transition Encoding — pure T(x, x') without I(x).
##
## Three-Layer Separation (I/T/P):
##   I(x)   = initialValue binding  ← caller injects (solver_bridge)
##   T(x,x') = pure transition      ← this module generates
##   P(x)    = safety property       ← encoding_properties handles
type TransitionEncoding* = object
  declarations*: seq[string]
  transitionExpr*: SmtSExpr
  finalStateSymbol*: string

## Encode Rule Transition — pure T(x, x') only.
##
## Returns TransitionEncoding with:
##   - declarations: ["x_0", "x_1"]  (state variables)
##   - transitionExpr: SmtSExpr for T(x_0, x_1)
##   - finalStateSymbol: "x_1"
##
## Does NOT bind x_0 to any concrete value.
## Caller is responsible for injecting I(x) = (x_0 = initialValue).
func encodeRuleTransition*(rule: TransitionRule): TransitionEncoding {.raises: [].} =
  let x0 = symInt("x_0")
  let x1 = symInt("x_1")
  let delta = intLit(rule.delta)
  case rule.op
  of transitionAdd:
    TransitionEncoding(
      declarations: @["x_0", "x_1"],
      transitionExpr: eq(x1, add(x0, delta)),
      finalStateSymbol: "x_1"
    )
  of transitionSub:
    TransitionEncoding(
      declarations: @["x_0", "x_1"],
      transitionExpr: eq(x1, ite(ge(x0, delta), sub(x0, delta), x0)),
      finalStateSymbol: "x_1"
    )

{.pop.}

{.pop.}

{.pop}
