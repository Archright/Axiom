import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## BMC Lowering Pass — compile-time IR transformations for SMT BMC emission.
##
## Chains three idempotent transformations into a single entry point:
##   1. recomputeTyp     — backfill typ on deserialized trees (in-place)
##   2. resolveRecCalls  — replace irRecCall with named irCall (new tree)
##   3. elaborateSorts   — insert irCast for Bool/BV64 coercion (in-place)
##
## Design:
##   Separates compile-time IR transformations from the SMT emission path
##   (ir_to_smt_chunk3.nim), ensuring the emission functions operate on
##   well-sorted, well-typed IR without side effects.
##
## Properties:
##   - Pure-functional: returns a new IRFuncDef, never mutates input
##   - Idempotent: lowerToBmc(lowerToBmc(f)) == lowerToBmc(f)
##   - All functions are `func` with `{.raises: [].}`
##
## Usage:
##   let lowered = lowerToBmc(funcDef)
##   let smtScript = irToSmtScript(lowered)

import core/trusted/axiom_ir
import core/trusted/ir_tree_ops
import core/trusted/ir_elaborate_sorts

func lowerToBmc*(f: IRFuncDef; depth: int = 5): IRFuncDef =
  ## Apply the BMC lowering pipeline to an IR function definition.
  ##
  ## The `depth` parameter is reserved for future BMC loop unrolling
  ## (currently unused; the default depth of 5 is sufficient for
  ## the standard 4-layer pipeline).
  ##
  ## Transformations applied (in order):
  ##   1. recomputeTyp — ensures typ fields are populated on deserialized IR
  ##   2. resolveRecCalls — replaces irRecCall(self, args) → irCall(funcName, args)
  ##   3. elaborateSorts — inserts irCast for Bool↔BV64 coercion at comparison sites
  ##
  ## Returns a new IRFuncDef with the transformed body. The original is not mutated.
  discard depth  # Reserved for future BMC unrolling depth control
  result = f
  recomputeTyp(result.body)
  result.body = resolveRecCalls(result.body, result.name)
  elaborateSorts(result.body)

{.pop.}
