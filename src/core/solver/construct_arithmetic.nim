import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/solver/types
import ../../core/trusted/axiom_pragmas

## Add.
func add*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [], axiom: ["(assert (= 1 1))", "1 = 1"].} =
  SmtSExpr(kind: exprAdd, text: "", args: @[a, b])

## Sub.
func sub*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprSub, text: "", args: @[a, b])

## Mul.
func mul*(a, b: SmtSExpr): SmtSExpr {.inline, raises: [].} =
  SmtSExpr(kind: exprMul, text: "", args: @[a, b])

{.pop.}
{.pop.}
