{.push raises: [CatchableError].}
## BDD feature test for axiom_ir_helpers.feature
## Verifies IR helper constructors and pretty-printers.

import std/unittest
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_ir

suite "Axiom Core IR Helpers":

  test "irLit constructs literal expression":
    let e = irLit(42)
    check e.kind == irLit
    check e.litVal == 42

  test "irVar constructs variable reference":
    let e = irVar("x", IRType(kind: irtBitVec64))
    check e.kind == irVar
    check e.varName == "x"
    check e.varType.kind == irtBitVec64

  test "irPretty produces non-empty string for literals":
    let e = irLit(7)
    let s = irPretty(e)
    check s.len > 0
