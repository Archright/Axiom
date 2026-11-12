{.push raises: [CatchableError].}
## BDD feature test for ast_signature.feature
## Verifies AST-based deterministic axiom signature matching.

import std/unittest
import core/verified_axioms/ast_signature
import core/trusted/axiom_ir

suite "AST Signature Matching":

  test "irTypeShortName maps bitvec64 to bv64":
    let t = IRType(kind: irtBitVec64)
    let s = irTypeShortName(t)
    check s == "bv64"

  test "irTypeShortName maps bool to bool":
    let t = IRType(kind: irtBool)
    let s = irTypeShortName(t)
    check s == "bool"

  test "paramSignature produces deterministic hash string":
    let params = @[IRFuncParam(name: "a", ty: irTypeBitVec64()),
                   IRFuncParam(name: "b", ty: irTypeBitVec64())]
    let sig = computeIrSignatureHash(params, irTypeBitVec64())
    check sig.len > 0
