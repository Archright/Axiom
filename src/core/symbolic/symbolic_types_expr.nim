import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/solver/expr_serialize  # canonical coerceToBool, needsBvCoercion
import std/tables
import core/trusted/axiom_pragmas_lite

type
  SymSymSExprKind* = enum
    seVar, seConst, seAdd, seSub, seMul, seDiv, seMod,
    seEq, seNe, seLt, seLe, seGt, seGe,
    seAnd, seOr, seNot,
    seTrue, seFalse,
    ## Tier 1 ADT: Option and Result
    seNone, seSome, seIsSome, seVal,
    seOk, seErr, seIsOk, seErrMsg,
    ## Tier 2 abstract: uninterpreted functions and axiom references
    seUninterpretedApp, seAxiomRef,
    ## Tier 1 collections: List operations
    seNil, seCons, seHead, seTail, seLength

  SymSymSExprObj* = object
    kind*: SymSymSExprKind
    name*: string
    intValue*: int
    lhs*: ref SymSymSExprObj
    rhs*: ref SymSymSExprObj

  SymSExpr* = ref SymSymSExprObj

  SymbolicState* = object
    pathCondition*: SymSExpr
    assignments*: Table[string, SymSExpr]
    loopInvariants*: Table[int, SymSExpr]

  SymbolicTrace* = seq[SymbolicState]

  CfgAnalysisResult* = object
    hasLoops*: bool
    hasUnsupported*: bool
    loopInvariants*: Table[int, SymSExpr]
    unsupportedReason*: string

## S Var.
func sVar*(name: string): SymSExpr {.inline, axiom: ["(assert (and ast_parse_failed_isolated (>= result 0) (>= result 0) (>= (str.len name) 0)))", "ast_parse_failed_isolated ∧ (result ≥ 0) ∧ (result ≥ 0) ∧ name.length ≥ 0"].} =
  new(result)
  result.kind = seVar
  result.name = name

## S Const.
func sConst*(value: int): SymSExpr {.inline, axiom: ["(assert (and (>= result 0) (>= result 0) (and (>= value -9223372036854775808) (<= value 9223372036854775807))))", "(result ≥ 0) ∧ (result ≥ 0) ∧ value ≥ -9223372036854775808 ∧ value ≤ 9223372036854775807"].} =
  new(result)
  result.kind = seConst
  result.intValue = value

## S True.
func sTrue*(): SymSExpr {.inline, axiom: ["(assert (and ast_parse_failed_isolated (>= depth 0)))", "ast_parse_failed_isolated ∧ depth >= 0"].} =
  new(result)
  result.kind = seTrue

## S False.
func sFalse*(): SymSExpr {.inline, axiom: ["(assert (and ast_parse_failed_isolated (>= depth 0)))", "ast_parse_failed_isolated ∧ depth >= 0"].} =
  new(result)
  result.kind = seFalse

## S Add.
func sAdd*(a, b: SymSExpr): SymSExpr {.inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  new(result)
  result.kind = seAdd
  result.lhs = a
  result.rhs = b

## S Sub.
func sSub*(a, b: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seSub
  result.lhs = a
  result.rhs = b

## S Mul.
func sMul*(a, b: SymSExpr): SymSExpr {.inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  new(result)
  result.kind = seMul
  result.lhs = a
  result.rhs = b

## S Eq.
func sEq*(a, b: SymSExpr): SymSExpr {.inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  new(result)
  result.kind = seEq
  result.lhs = a
  result.rhs = b

## S Lt.
func sLt*(a, b: SymSExpr): SymSExpr {.inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  new(result)
  result.kind = seLt
  result.lhs = a
  result.rhs = b

## S Le.
func sLe*(a, b: SymSExpr): SymSExpr {.inline, axiom: ["(assert (and ast_parse_failed_isolated (>= result 0)))", "ast_parse_failed_isolated ∧ (result ≥ 0)"].} =
  new(result)
  result.kind = seLe
  result.lhs = a
  result.rhs = b

## S Ge.
func sGe*(a, b: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seGe
  result.lhs = a
  result.rhs = b

## S Gt.
func sGt*(a, b: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seGt
  result.lhs = a
  result.rhs = b

## S And.
func sAnd*(a, b: SymSExpr): SymSExpr {.axiomDecision, inline, axiom: ["(assert (and ast_parse_failed_isolated b a))", "ast_parse_failed_isolated ∧ b ∧ a"].} =
  if a.kind == seTrue:
    return b
  if b.kind == seTrue:
    return a
  if a.kind == seFalse or b.kind == seFalse:
    return sFalse()
  new(result)
  result.kind = seAnd
  result.lhs = a
  result.rhs = b

## S Not.
func sNot*(a: SymSExpr): SymSExpr {.axiomDecision, inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  if a.kind == seTrue:
    return sFalse()
  if a.kind == seFalse:
    return sTrue()
  new(result)
  result.kind = seNot
  result.lhs = a

## S None (Option.t.none).
func sNone*(): SymSExpr {.inline.} =
  new(result)
  result.kind = seNone

## S Some (Option.t some wrapper).
func sSome*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seSome
  result.lhs = a

## S Is Some (Option.t.isSome predicate).
func sIsSome*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seIsSome
  result.lhs = a

## S Val (Option.t.get! unwrap).
func sVal*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seVal
  result.lhs = a

## S Ok (Result.ok wrapper).
func sOk*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seOk
  result.lhs = a

## S Err (Result.error wrapper).
func sErr*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seErr
  result.lhs = a

## S Is Ok (Result.isOk predicate).
func sIsOk*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seIsOk
  result.lhs = a

## S Err Msg (Result.errorMsg unwrap).
func sErrMsg*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seErrMsg
  result.lhs = a

## S Uninterpreted App (uninterpreted function application: name arg).
func sUninterpretedApp*(fn: string; arg: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seUninterpretedApp
  result.name = fn
  result.lhs = arg

## S Axiom Ref (reference to a named axiom).
func sAxiomRef*(axiomName: string): SymSExpr {.inline.} =
  new(result)
  result.kind = seAxiomRef
  result.name = axiomName

## S Nil (empty list).
func sNil*(): SymSExpr {.inline.} =
  new(result)
  result.kind = seNil

## S Cons (list cons: head :: tail).
func sCons*(head, tail: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seCons
  result.lhs = head
  result.rhs = tail

## S Head (list head accessor).
func sHead*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seHead
  result.lhs = a

## S Tail (list tail accessor).
func sTail*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seTail
  result.lhs = a

## S Length (list length accessor).
func sLength*(a: SymSExpr): SymSExpr {.inline.} =
  new(result)
  result.kind = seLength
  result.lhs = a

## S Expr To String.
func sExprToString*(e: SymSExpr): string {.raises: [], axiom: ["(assert (and seVar seConst seTrue seFalse seAdd seSub seMul seDiv seMod seEq seNe seLt seLe seGt seGe seAnd seOr seNot))", "seVar ∧ seConst ∧ seTrue ∧ seFalse ∧ seAdd ∧ seSub ∧ seMul ∧ seDiv ∧ seMod ∧ seEq ∧ seNe ∧ seLt ∧ seLe ∧ seGt ∧ seGe ∧ seAnd ∧ seOr ∧ seNot"].} =
  if e.isNil:
    return "nil"
  case e.kind
  of seVar:
    e.name
  of seConst:
    $e.intValue
  of seTrue:
    "true"
  of seFalse:
    "false"
  of seAdd:
    "(+ " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seSub:
    "(- " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seMul:
    "(* " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seDiv:
    "(div " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seMod:
    "(mod " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seEq:
    "(= " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seNe:
    "(not (= " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & "))"
  of seLt:
    "(< " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seLe:
    "(<= " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seGt:
    "(> " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seGe:
    "(>= " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seAnd:
    "(and " & coerceToBool(sExprToString(e.lhs)) & " " & coerceToBool(sExprToString(e.rhs)) & ")"
  of seOr:
    "(or " & coerceToBool(sExprToString(e.lhs)) & " " & coerceToBool(sExprToString(e.rhs)) & ")"
  of seNot:
    "(not " & sExprToString(e.lhs) & ")"
  of seNone:
    "None"
  of seSome:
    "(some " & sExprToString(e.lhs) & ")"
  of seIsSome:
    "(isSome " & sExprToString(e.lhs) & ")"
  of seVal:
    "(val " & sExprToString(e.lhs) & ")"
  of seOk:
    "(ok " & sExprToString(e.lhs) & ")"
  of seErr:
    "(err " & sExprToString(e.lhs) & ")"
  of seIsOk:
    "(isOk " & sExprToString(e.lhs) & ")"
  of seErrMsg:
    "(errMsg " & sExprToString(e.lhs) & ")"
  of seUninterpretedApp:
    "(app " & e.name & " " & sExprToString(e.lhs) & ")"
  of seAxiomRef:
    "(axiom " & e.name & ")"
  of seNil:
    "nil"
  of seCons:
    "(cons " & sExprToString(e.lhs) & " " & sExprToString(e.rhs) & ")"
  of seHead:
    "(head " & sExprToString(e.lhs) & ")"
  of seTail:
    "(tail " & sExprToString(e.lhs) & ")"
  of seLength:
    "(length " & sExprToString(e.lhs) & ")"


{.pop.}

{.pop.}
