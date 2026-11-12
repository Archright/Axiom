import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/solver/types
import ../../core/trusted/axiom_pragmas

## Sym Int.
func symInt*(name: string): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprSymbol, text: name, args: @[])

## Int Lit.
func intLit*(n: int): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprIntLit, text: $n, args: @[])

## Bool Lit.
func boolLit*(b: bool): SmtSExpr {.inline, raises: [], axiom: ["(assert (and b (or (= b true) (= b false))))", "b ∧ b = true ∨ b = false"].} =
  if b:
    SmtSExpr(kind: exprBoolLit, text: "true", args: @[])
  else:
    SmtSExpr(kind: exprBoolLit, text: "false", args: @[])

## Ite.
func ite*(condExpr, thenExpr, elseExpr: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprIte, text: "", args: @[condExpr, thenExpr, elseExpr])

{.pop.}
{.pop.}
