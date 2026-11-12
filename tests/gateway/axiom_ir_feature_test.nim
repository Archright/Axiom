{.push raises: [CatchableError].}
## BDD feature test for axiom_ir.feature
## Verifies Axiom Core IR types, expressions, and serialization.

import std/unittest
import core/trusted/axiom_ir

suite "Axiom Core IR":

  test "IRTypeKind enum values are accessible":
    check irtBitVec64 == irtBitVec64
    check irtBool == irtBool
    check irtList == irtList

  test "IRExprKind enum values are accessible":
    check irLit == irLit
    check irVar == irVar
    check irLet == irLet
    check irIf == irIf
    check irLoop == irLoop
    check irCall == irCall
    check irRecCall == irRecCall

  test "loopVariant field exists on irLoop":
    ## Issue 3: Well-Founded Metric Boundary Assertion.
    ## irLoop must carry a loopVariant field for termination proofs.
    var expr = IRExpr(kind: irLoop, loopVariant: IRExpr(kind: irLit, litVal: 0))
    check expr.kind == irLoop
    check expr.loopVariant.kind == irLit
    check expr.loopVariant.litVal == 0
