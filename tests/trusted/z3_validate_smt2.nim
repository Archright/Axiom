## Quick Z3 validation: generate SMT-LIB2 and pipe to z3.
import core/trusted/ir_to_smt
import core/trusted/axiom_ir_helpers
import std/os
proc main() =
  let body = irBinOp(boAdd, irVar("a", irTypeBitVec64()),
                     irVar("b", irTypeBitVec64()))
  let f = irFuncDef("f_add",
                     @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
                     irTypeBitVec64(), body)
  let script = irToSmtScript(f, includeOverflowDefines = true)
  echo script

  let annotated = AnnotatedExpr(expr: body, overflow: oNoOverflow)
  let assertions = generateOverflowAssertions(annotated)
  echo ""
  for a in assertions:
    echo a

main()
