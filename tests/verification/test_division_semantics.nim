import std/strutils
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import core/trusted/ir_to_lean
import core/types/results

proc main() =
  echo "=== Division Semantics Conformance Tests ==="

  let bv64 = irTypeBitVec64()
  let a = irVar("a", bv64)
  let b = irVar("b", bv64)

  # -- SMT Encoder: boDiv -> bvsdiv (signed trunc-toward-zero) --------
  block:
    let divExpr = irBinOp(boDiv, a, b)
    let smt = irExprToSmt(divExpr)
    doAssert smt == "(bvsdiv a b)",
      "boDiv -> bvsdiv failed, got: " & smt
    echo "  PASS: boDiv -> bvsdiv"

  # -- SMT Encoder: boRem -> bvsrem (signed, sign-of-dividend) --------
  block:
    let remExpr = irBinOp(boRem, a, b)
    let smt = irExprToSmt(remExpr)
    doAssert smt == "(bvsrem a b)",
      "boRem -> bvsrem failed, got: " & smt
    echo "  PASS: boRem -> bvsrem"

  # -- SMT Encoder: boRemU -> bvurem (unsigned) -----------------------
  block:
    let remUExpr = irBinOp(boRemU, a, b)
    let smt = irExprToSmt(remUExpr)
    doAssert smt == "(bvurem a b)",
      "boRemU -> bvurem failed, got: " & smt
    echo "  PASS: boRemU -> bvurem"

  # -- Phase2a regression: %% (boRemU) must NOT lower to bvsrem --------
  block:
    let remUExpr = irBinOp(boRemU, a, b)
    let smt = irExprToSmt(remUExpr)
    doAssert smt != "(bvsrem a b)",
      "Phase2a regression: boRemU must NOT map to bvsrem"
    doAssert smt == "(bvurem a b)",
      "Phase2a regression: boRemU must map to bvurem, got: " & smt
    echo "  PASS: boRemU (%%) does NOT lower to bvsrem"

  # -- SMT Encoder: binOpSymbol for all three division ops -------------
  block:
    doAssert binOpSymbol(boDiv) == "bvsdiv",
      "binOpSymbol(boDiv) failed, got: " & binOpSymbol(boDiv)
    doAssert binOpSymbol(boRem) == "bvsrem",
      "binOpSymbol(boRem) failed, got: " & binOpSymbol(boRem)
    doAssert binOpSymbol(boRemU) == "bvurem",
      "binOpSymbol(boRemU) failed, got: " & binOpSymbol(boRemU)
    echo "  PASS: binOpSymbol mappings"

  # -- SMT Encoder: binOpSmt for all three division ops ----------------
  block:
    doAssert binOpSmt(boDiv, bv64, bv64) == "bvsdiv",
      "binOpSmt(boDiv) failed, got: " & binOpSmt(boDiv, bv64, bv64)
    doAssert binOpSmt(boRem, bv64, bv64) == "bvsrem",
      "binOpSmt(boRem) failed, got: " & binOpSmt(boRem, bv64, bv64)
    doAssert binOpSmt(boRemU, bv64, bv64) == "bvurem",
      "binOpSmt(boRemU) failed, got: " & binOpSmt(boRemU, bv64, bv64)
    echo "  PASS: binOpSmt mappings"

  # -- IR->Lean: boDiv -> BitVec.sdiv (signed trunc-toward-zero) --------
  block:
    let divExpr = irBinOp(boDiv, a, b)
    let lean = irExprToLean(divExpr)
    doAssert lean == "(BitVec.sdiv a b)",
      "boDiv -> BitVec.sdiv failed, got: " & lean
    echo "  PASS: boDiv -> BitVec.sdiv"

  # -- IR->Lean: boRem -> BitVec.srem (signed, sign-of-dividend) --------
  block:
    let remExpr = irBinOp(boRem, a, b)
    let lean = irExprToLean(remExpr)
    doAssert lean == "(BitVec.srem a b)",
      "boRem -> BitVec.srem failed, got: " & lean
    echo "  PASS: boRem -> BitVec.srem"

  # -- IR->Lean: boRemU -> BitVec.umod (unsigned) ------------------------
  block:
    let remUExpr = irBinOp(boRemU, a, b)
    let lean = irExprToLean(remUExpr)
    doAssert lean == "(BitVec.umod a b)",
      "boRemU -> BitVec.umod failed, got: " & lean
    echo "  PASS: boRemU -> BitVec.umod"

  # -- IR->Lean: irBinOpToLean for all three division ops --------------
  block:
    doAssert irBinOpToLean(boDiv) == "BitVec.sdiv",
      "irBinOpToLean(boDiv) failed, got: " & irBinOpToLean(boDiv)
    doAssert irBinOpToLean(boRem) == "BitVec.srem",
      "irBinOpToLean(boRem) failed, got: " & irBinOpToLean(boRem)
    doAssert irBinOpToLean(boRemU) == "BitVec.umod",
      "irBinOpToLean(boRemU) failed, got: " & irBinOpToLean(boRemU)
    echo "  PASS: irBinOpToLean mappings"

  # -- Full IR function: signed division via / --------------------------
  block:
    let body = irBinOp(boDiv, irVar("x", bv64), irVar("y", bv64))
    var f = irFuncDef("sdiv",
                       @[("x", bv64), ("y", bv64)],
                       bv64, body)
    f.postConditions = @[irEq(irVar("result", bv64), irBinOp(boDiv, irVar("x", bv64), irVar("y", bv64)))]
    let script = irToSmtScript(f)
    doAssert "(bvsdiv x y)" in script,
      "Full IR: signed division missing bvsdiv in script, got: " & script
    doAssert "(bvurem" notin script,
      "Full IR: signed division must NOT contain bvurem"
    echo "  PASS: Full IR signed division -> bvsdiv"

  # -- Full IR function: unsigned remainder via %% ----------------------
  block:
    let body = irBinOp(boRemU, irVar("x", bv64), irVar("y", bv64))
    var f = irFuncDef("urem",
                       @[("x", bv64), ("y", bv64)],
                       bv64, body)
    f.postConditions = @[irEq(irVar("result", bv64), irBinOp(boRemU, irVar("x", bv64), irVar("y", bv64)))]
    let script = irToSmtScript(f)
    doAssert "(bvurem x y)" in script,
      "Full IR: unsigned remainder missing bvurem in script, got: " & script
    doAssert "(bvsrem" notin script,
      "Full IR: unsigned remainder must NOT contain bvsrem"
    echo "  PASS: Full IR unsigned remainder -> bvurem"

  # -- Full IR function: signed mod via % -------------------------------
  block:
    let body = irBinOp(boRem, irVar("x", bv64), irVar("y", bv64))
    var f = irFuncDef("smod",
                       @[("x", bv64), ("y", bv64)],
                       bv64, body)
    f.postConditions = @[irEq(irVar("result", bv64), irBinOp(boRem, irVar("x", bv64), irVar("y", bv64)))]
    let script = irToSmtScript(f)
    doAssert "(bvsrem x y)" in script,
      "Full IR: signed mod missing bvsrem in script, got: " & script
    doAssert "(bvurem" notin script,
      "Full IR: signed mod must NOT contain bvurem"
    echo "  PASS: Full IR signed mod -> bvsrem"

  # -- Verify all BinOpKind cases in parseBinOpKind handle boRemU -----
  block:
    var pos = 0
    let op = parseBinOpKind("boRemU", pos)
    doAssert op == boRemU,
      "parseBinOpKind(\"boRemU\") failed, got: " & $op
    echo "  PASS: parseBinOpKind handles boRemU"

  # -- Verify all BinOpKind cases in irBinOpToLean handle boRemU ------
  block:
    let lean = irBinOpToLean(boRemU)
    doAssert lean == "BitVec.umod",
      "irBinOpToLean(boRemU) failed, got: " & lean
    echo "  PASS: irBinOpToLean handles boRemU"

  # -- Verify all BinOpKind cases in binOpSmt handle boRemU -----------
  block:
    let smt = binOpSmt(boRemU, bv64, bv64)
    doAssert smt == "bvurem",
      "binOpSmt(boRemU) failed, got: " & smt
    echo "  PASS: binOpSmt handles boRemU"

  # -- Verify all BinOpKind cases in binOpSymbol handle boRemU ---------
  block:
    let sym = binOpSymbol(boRemU)
    doAssert sym == "bvurem",
      "binOpSymbol(boRemU) failed, got: " & sym
    echo "  PASS: binOpSymbol handles boRemU"

  # -- Verify irBinExprToLean handles boDiv/boRem/boRemU --------------
  block:
    let divLean = irBinExprToLean(irBinOp(boDiv, a, b), 0)
    doAssert divLean == "(BitVec.sdiv a b)",
      "irBinExprToLean(boDiv) failed, got: " & divLean
    let remLean = irBinExprToLean(irBinOp(boRem, a, b), 0)
    doAssert remLean == "(BitVec.srem a b)",
      "irBinExprToLean(boRem) failed, got: " & remLean
    let remULean = irBinExprToLean(irBinOp(boRemU, a, b), 0)
    doAssert remULean == "(BitVec.umod a b)",
      "irBinExprToLean(boRemU) failed, got: " & remULean
    echo "  PASS: irBinExprToLean handles all three division ops"

  # -- Verify refinedExprToProp handles boDiv/boRem/boRemU (else branch)
  block:
    let divProp = refinedExprToProp(irBinOp(boDiv, a, b))
    doAssert isOk(divProp),
      "refinedExprToProp(boDiv) failed"
    doAssert "BitVec.sdiv" in divProp.get,
      "refinedExprToProp(boDiv) missing BitVec.sdiv, got: " & divProp.get
    let remProp = refinedExprToProp(irBinOp(boRem, a, b))
    doAssert isOk(remProp),
      "refinedExprToProp(boRem) failed"
    doAssert "BitVec.srem" in remProp.get,
      "refinedExprToProp(boRem) missing BitVec.srem, got: " & remProp.get
    let remUProp = refinedExprToProp(irBinOp(boRemU, a, b))
    doAssert isOk(remUProp),
      "refinedExprToProp(boRemU) failed"
    doAssert "BitVec.umod" in remUProp.get,
      "refinedExprToProp(boRemU) missing BitVec.umod, got: " & remUProp.get
    echo "  PASS: refinedExprToProp handles all three division ops"

  echo "=== All Division Semantics Tests Passed ==="

main()