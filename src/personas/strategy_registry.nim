## Strategy Registry — Compile-time macro registry for OCP-compliant dispatch.
##
## Custom pragma macros register GoalShape → strategy and JudgeStrategy → tactic
## handlers at compile time. Dispatch macros generate exhaustive case statements
## from the registry, eliminating manual case branch maintenance.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import macros

{.push raises: [CatchableError].}

# ──────────────────────────────────────────────────────────────────────────────
# Types (canonical definitions — re-exported by judge_automation)
# ──────────────────────────────────────────────────────────────────────────────

type
  GoalShape* = enum
    ## Classification of Lean proof goal structure.
    gsLinearArithmetic   ## Goals involving linear integer arithmetic (Nat/Int, +, -, *, ≤, ≥)
    gsEquality           ## Structural or definitional equality goals (a = b)
    gsInductiveStructure ## Goals requiring induction on inductive types (List, Nat, Tree, …)
    gsFiniteEquality     ## Decidable equality on finite/enum types
    gsGeneral            ## Unrecognized but well-formed goals
    gsUnknown            ## Classification failed or goal source was empty

  JudgeStrategy* = enum
    ## Ordered deterministic proof strategies.
    jsRfl            ## Reflexivity (definitional equality)
    jsOmega          ## Omega (linear arithmetic over Int/Nat)
    jsDecide         ## Decide (typeclass-based decidability)
    jsNativeDecide   ## Native decide (Lean built-in, no Mathlib)
    jsSimp           ## Simplifier
    jsSimpOmega      ## Combined simp + omega pass
    jsGrind          ## Grind (congruence + arithmetic)
    jsAesop          ## Aesop (structured auto)
    jsLlmFallback    ## LLM fallback (Leanstral)

# ──────────────────────────────────────────────────────────────────────────────
# Compile-time registries
# ──────────────────────────────────────────────────────────────────────────────

var shapeHandlerRegistry {.compileTime.}: seq[(GoalShape, string)]
var strategyHandlerRegistry {.compileTime.}: seq[(JudgeStrategy, string)]

# ──────────────────────────────────────────────────────────────────────────────
# Custom pragma macros — handler registration
# ──────────────────────────────────────────────────────────────────────────────

macro registerShapeHandler*(shape: static GoalShape, def: untyped): untyped =
  ## Custom pragma: {.registerShapeHandler(gsXxx).}
  ## Registers the decorated proc as the handler for the given GoalShape.
  var procName = $def[0]
  if procName.len > 0 and procName[^1] == '*':
    procName = procName[0..^2]
  shapeHandlerRegistry.add((shape, procName))
  result = def

macro registerStrategyHandler*(strategy: static JudgeStrategy, def: untyped): untyped =
  ## Custom pragma: {.registerStrategyHandler(jsXxx).}
  ## Registers the decorated proc as the handler for the given JudgeStrategy.
  var procName = $def[0]
  if procName.len > 0 and procName[^1] == '*':
    procName = procName[0..^2]
  strategyHandlerRegistry.add((strategy, procName))
  result = def

# ──────────────────────────────────────────────────────────────────────────────
# Dispatch macros — generate case statements from registry
# ──────────────────────────────────────────────────────────────────────────────

macro dispatchShape*(shape: GoalShape): seq[JudgeStrategy] =
  ## Generate an exhaustive case statement from registered shape handlers.
  result = nnkCaseStmt.newTree(shape)
  for (gs, procName) in shapeHandlerRegistry:
    result.add nnkOfBranch.newTree(ident($gs), newCall(ident(procName)))
  result.add(nnkElse.newTree(
    nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
  ))

macro dispatchStrategy*(strategy: JudgeStrategy): string =
  ## Generate an exhaustive case statement from registered strategy handlers.
  result = nnkCaseStmt.newTree(strategy)
  for (js, procName) in strategyHandlerRegistry:
    result.add nnkOfBranch.newTree(ident($js), newCall(ident(procName)))
  result.add(nnkElse.newTree(newLit("")))

{.pop}
