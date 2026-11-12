{.push raises: [CatchableError].}
## BDD feature test for ast_to_ir.feature
## Verifies Nim AST → Axiom Core IR conversion.

import std/unittest
import std/macros
import core/trusted/ast_to_ir
import core/trusted/axiom_ir

suite "AST to IR Conversion":

  test "convertFuncDef produces IRFuncDef for simple proc":
    macro toIrFuncDef(): untyped =
      let ast = quote do:
        proc add(a, b: int): int = a + b
      let ir = convertFuncDef(ast)
      result = newLit((ir.name, $ir.retType.kind, ir.params.len))
    let (name, retKind, paramCount) = toIrFuncDef()
    check name == "add"
    check retKind == "irtBitVec64"
    check paramCount == 2

  test "convertExpr produces irBinOp for infix addition":
    macro toIrExpr(): untyped =
      var ctx = initIrContext("test", @[])
      let ir = convertExpr(infix(ident"a", "+", ident"b"), ctx)
      result = newLit(($ir.kind, $ir.binOp))
    let (kind, binOp) = toIrExpr()
    check kind == "irBinOp"
    check binOp == "boAdd"
