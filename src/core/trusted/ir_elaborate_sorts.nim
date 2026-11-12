import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Type Elaboration Pass — single recursive pass that inserts irCast nodes
## wherever boolean operators receive BitVec64 arguments.
##
## Purpose: Makes the IR well-sorted BEFORE any SMT emission, eliminating
## all downstream ad-hoc coercion in ir_to_smt_chunk2, expr_serialize.
##
## Properties:
##   - In-place mutation (ref object fields)
##   - Idempotent: safe to call multiple times
##   - O(n) single traversal
##   - Pure: no side effects beyond IR mutation

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers

func isBv64*(t: IRType): bool {.inline.} =
  t != nil and t.kind == irtBitVec64

func elaborateSorts*(e: IRExpr) =
  if e == nil: return
  case e.kind
  of irLit, irFloatLit, irStringLit:
    discard
  of irVar:
    discard
  of irCast:
    elaborateSorts(e.castExpr)
  of irUnaryOp:
    elaborateSorts(e.unaryArg)
    if e.unaryOp == uoNot and isBv64(e.unaryArg.typ):
      e.unaryArg = irCast(e.unaryArg, irTypeBool())
  of irBinOp:
    elaborateSorts(e.binLhs)
    elaborateSorts(e.binRhs)
    if e.binOp in {boAnd, boOr}:
      if isBv64(e.binLhs.typ):
        e.binLhs = irCast(e.binLhs, irTypeBool())
      if isBv64(e.binRhs.typ):
        e.binRhs = irCast(e.binRhs, irTypeBool())
  of irIf:
    elaborateSorts(e.ifCond)
    elaborateSorts(e.ifThen)
    elaborateSorts(e.ifElse)
    if isBv64(e.ifCond.typ):
      e.ifCond = irCast(e.ifCond, irTypeBool())
  of irCall:
    for arg in e.callArgs: elaborateSorts(arg)
    if e.callName in ["and", "or"] and e.callArgs.len == 2:
      if isBv64(e.callArgs[0].typ):
        e.callArgs[0] = irCast(e.callArgs[0], irTypeBool())
      if isBv64(e.callArgs[1].typ):
        e.callArgs[1] = irCast(e.callArgs[1], irTypeBool())
    elif e.callName == "not" and e.callArgs.len == 1:
      if isBv64(e.callArgs[0].typ):
        e.callArgs[0] = irCast(e.callArgs[0], irTypeBool())
  of irLet:
    elaborateSorts(e.letVal)
    elaborateSorts(e.letBody)
  of irCase:
    elaborateSorts(e.caseScrutinee)
    for br in e.caseBranches: elaborateSorts(br.body)
    elaborateSorts(e.caseDefault)
  of irRecCall:
    for arg in e.recArgs: elaborateSorts(arg)
  of irLoop:
    for init in e.loopInits: elaborateSorts(init)
    elaborateSorts(e.loopCond)
    elaborateSorts(e.loopStep)
    elaborateSorts(e.loopBody)
    for inv in e.loopInvariants: elaborateSorts(inv)
    elaborateSorts(e.loopVariant)

{.pop.}
