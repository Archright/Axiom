import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Transition Adapter — TransitionRule → BmcTransition Conversion
##
## Converts the domain-layer TransitionRule type into the SMT-LIB2
## BmcTransition format required by spacer_chc_router.nim.
##
## This is the bridge between the simple op/delta model and the
## full SMT-LIB2 transition encoding.
##
## Plan v3 Phase D: "transition_adapter.nim (new file): TransitionRule → BmcTransition"

import core/bmc/bmc_types

func encodeTransitionAsBmc*(
    rule: TransitionRule;
    varName: string = "x"
): BmcTransition {.noSideEffect.} =
  ## Convert a TransitionRule to a BmcTransition suitable for CHC/Spacer.
  ##
  ## TransitionRule is a compact representation:
  ##   - op: transitionSub | transitionAdd
  ##   - delta: integer
  ##   - invariant: minValue/maxValue constraints
  ##
  ## BmcTransition is the SMT-LIB2 representation:
  ##   - preState: variable declarations with sorts
  ##   - guard: boolean condition
  ##   - postState: variable assignments
  let preStateVars = @[(varName, "Int")]
  let guardExpr = case rule.op
    of transitionSub:
      # x >= delta (prevents underflow)
      "(>= " & varName & " " & $rule.delta & ")"
    of transitionAdd:
      # true (no guard needed for addition)
      "true"

  let postExpr = case rule.op
    of transitionSub:
      varName & " (- " & varName & " " & $rule.delta & ")"
    of transitionAdd:
      varName & " (+ " & varName & " " & $rule.delta & ")"

  BmcTransition(
    preState: preStateVars,
    guard: guardExpr,
    postState: @[(varName, postExpr)]
  )

func encodeTransitionsAsBmc*(
    rules: seq[TransitionRule];
    varName: string = "x"
): seq[BmcTransition] {.noSideEffect.} =
  ## Convert multiple TransitionRules to BmcTransitions.
  result = @[]
  for rule in rules:
    result.add(encodeTransitionAsBmc(rule, varName))

{.pop.}
