import std/options

type
  IRExprKind* = enum
    ieVar
    ieConst
    ieBinaryOp
    ieApp
    ieRefinement

  IRExpr* = ref object
    case kind*: IRExprKind
    of ieVar:
      varName*: string
    of ieConst:
      val*: string
    of ieBinaryOp:
      left*, right*: IRExpr
      op*: string
    of ieApp:
      fnName*: string
      args*: seq[IRExpr]
    of ieRefinement:
      refBaseType*: string
      refVarName*: string
      predicate*: IRExpr

  AxiomIRParam* = object
    name*: string
    typeName*: string
    isInductive*: bool

  AxiomParam* = object
    name*: string
    typeStr*: string
    refinement*: Option[IRExpr]
    isInductive*: bool

  IROpKind* = enum irAdd, irSub, irAssign, irReturn, irCall

  AxiomIRNode* = ref object
    kind*: IROpKind
    name*: string
    children*: seq[AxiomIRNode]
    params*: seq[AxiomParam]
    returnType*: string
    preConditions*: seq[IRExpr]
    postCondition*: Option[IRExpr]
    body*: IRExpr

proc isInductive*(param: AxiomParam): bool {.raises: [].} =
  param.isInductive
