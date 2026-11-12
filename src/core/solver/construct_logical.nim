import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/solver/types
import ../../core/trusted/axiom_pragmas

## Eq.
func eq*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprEq, text: "", args: @[a, b])

## Lt.
func lt*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprLt, text: "", args: @[a, b])

## Le.
func le*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprLe, text: "", args: @[a, b])

## Gt.
func gt*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  SmtSExpr(kind: exprGt, text: "", args: @[a, b])

## Ge.
func ge*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  SmtSExpr(kind: exprGe, text: "", args: @[a, b])

## And E.
func andE*(xs: seq[SmtSExpr]): SmtSExpr {.inline, raises: [], axiom: ["(assert (and (>= (seq.len xs) 0)))", "xs.size ≥ 0"].} =
  SmtSExpr(kind: exprAnd, text: "", args: xs)

## Or E.
func orE*(xs: seq[SmtSExpr]): SmtSExpr {.inline, raises: [], axiom: ["(assert (and (>= (seq.len xs) 0)))", "xs.size ≥ 0"].} =
  SmtSExpr(kind: exprOr, text: "", args: xs)

## Not E.
func notE*(x: SmtSExpr): SmtSExpr {.inline, raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  SmtSExpr(kind: exprNot, text: "", args: @[x])

## Impli.
func implies*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  SmtSExpr(kind: exprImplies, text: "", args: @[a, b])

{.pop.}
{.pop.}
