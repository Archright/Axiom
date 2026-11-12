import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/sequtils
import std/strutils
import core/trusted/axiom_ir
import core/trusted/ir_to_smt
import core/trusted/verification_model_types

## Semantic Kernel — the single operational definition of a Transition's
## post-state semantics, shared by EVERY encoder (CHC, Evidence; later BMC).
##
## Contract: C5.1 (Golden Transition-Formula Semantics) and C5/C6. This module
## is the semantic SSOT for ParallelUpdate lowering — consumers MUST NOT
## re-implement update lowering (divergence → CHC/Evidence/BMC disagree).
##
## Golden semantics (C5.1):
##   assigned(v) → v' = irExprToSmt(expr)     (RHS evaluated in pre-state S)
##   havoc(v)    → v' unconstrained (fresh free variable)
##   otherwise   → v' = v                     (frame condition)
##   ParallelUpdate is applied simultaneously; update ordering is NOT observable.

type
  PostStateArg* = object
    stateVar*: string   ## the state variable name (pre-state identity)
    nextSmt*: string    ## expression for v'; frame => stateVar itself, havoc => fresh var

  TransitionFormula* = object
    guardSmt*: string
    postArgs*: seq[PostStateArg]

  TransitionFormulaBuilder* = object
    stateNames*: seq[string]   ## ordered state signature (deterministic)

func newTransitionFormulaBuilder*(stateNames: openArray[string]): TransitionFormulaBuilder {.raises: [].} =
  TransitionFormulaBuilder(stateNames: @stateNames)

func guardSmt*(tr: Transition): string {.raises: [].} =
  if tr.guard != nil:
    irExprToSmt(tr.guard)
  else:
    "true"

func buildTransitionFormula*(b: TransitionFormulaBuilder; tr: Transition;
                             freshBase: var int): TransitionFormula {.raises: [].} =
  ## Golden per-transition formula. See C5.1.
  result.guardSmt = guardSmt(tr)
  for v in b.stateNames:
    var assigned = false
    for a in tr.update.assignments:
      if a.symbol == v:
        result.postArgs.add(PostStateArg(stateVar: v, nextSmt: irExprToSmt(a.expr)))
        assigned = true
        break
    if assigned:
      continue
    if v in tr.update.havocs:
      # fresh unconstrained post-state variable
      inc freshBase
      result.postArgs.add(PostStateArg(stateVar: v, nextSmt: "__havoc" & $freshBase))
    else:
      # frame condition: v' = v
      result.postArgs.add(PostStateArg(stateVar: v, nextSmt: v))

func postStateRel*(b: TransitionFormulaBuilder; tr: Transition;
                   freshBase: var int): string {.raises: [].} =
  ## `(state next0 next1 ...)` from the semantic kernel (post-state relation).
  let f = buildTransitionFormula(b, tr, freshBase)
  "(state " & f.postArgs.mapIt(it.nextSmt).join(" ") & ")"

func transitionRel*(b: TransitionFormulaBuilder; tr: Transition;
                    freshBase: var int): string {.raises: [].} =
  ## `(state v0 v1 ...)` pre-state relation args.
  "(state " & b.stateNames.join(" ") & ")"

{.pop.}