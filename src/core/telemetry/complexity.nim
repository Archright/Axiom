import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/trusted/axiom_ir

func countDecisionPoints(e: IRExpr): int {.raises: [].} =
  result = 0
  case e.kind
  of irIf:
    result += 1
    result += countDecisionPoints(e.ifCond)
    result += countDecisionPoints(e.ifThen)
    result += countDecisionPoints(e.ifElse)
  of irCase:
    result += e.caseBranches.len
    result += countDecisionPoints(e.caseScrutinee)
    for br in e.caseBranches:
      result += countDecisionPoints(br.body)
    if not e.caseDefault.isNil:
      result += countDecisionPoints(e.caseDefault)
  of irBinOp:
    if e.binOp in {boAnd, boOr}:
      result += 1
    result += countDecisionPoints(e.binLhs)
    result += countDecisionPoints(e.binRhs)
  of irLet:
    result += countDecisionPoints(e.letVal)
    result += countDecisionPoints(e.letBody)
  of irCall:
    for arg in e.callArgs:
      result += countDecisionPoints(arg)
  of irUnaryOp:
    result += countDecisionPoints(e.unaryArg)
  of irRecCall:
    for arg in e.recArgs:
      result += countDecisionPoints(arg)
  of irLoop:
    result += countDecisionPoints(e.loopCond)
    result += countDecisionPoints(e.loopBody)
    for inv in e.loopInvariants:
      if not inv.isNil:
        result += countDecisionPoints(inv)
    if not e.loopVariant.isNil:
      result += countDecisionPoints(e.loopVariant)
    for init in e.loopInits:
      result += countDecisionPoints(init)
    if not e.loopStep.isNil:
      result += countDecisionPoints(e.loopStep)
  of irCast:
    result += countDecisionPoints(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

func computeCyclomaticComplexity*(f: IRFuncDef): float {.raises: [].} =
  1.0 + countDecisionPoints(f.body).float

{.pop.}
