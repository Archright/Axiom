## Tests for cross_validation.nim — Phase 4B
## Verifies IR-based cross-validation between SMT-LIB2 and Lean 4 backends.

import std/[unittest, strutils]
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import verification/cross_validation

# ═══════════════════════════════════════════════════════════════════════════════
# Test IR fixtures
# ═══════════════════════════════════════════════════════════════════════════════

let bv64 = irTypeBitVec64()

## Simple addition: add(x, y) = x + y
let irAdd = irFuncDef(
  name = "add",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irAdd(irVar("x", bv64), irVar("y", bv64))
)

## Simple multiply: mul(x, y) = x * y  (different IR → different digest)
let irMul = irFuncDef(
  name = "mul",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irMul(irVar("x", bv64), irVar("y", bv64))
)

## Conditional: max(x, y) = if x >= y then x else y
let irMax = irFuncDef(
  name = "max",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irIf(
    irGe(irVar("x", bv64), irVar("y", bv64)),
    irVar("x", bv64),
    irVar("y", bv64)
  )
)

## Postcondition variants — honest spec contracts so irToSmtScript emits a
## real BMC negation (the vacuous guard returns "" without postconditions):
##   add(x,y)=x+y, mul(x,y)=x*y, max(x,y)=ite(x>=y,x,y)
func withPost(f: IRFuncDef; post: IRExpr): IRFuncDef =
  result = f
  result.postConditions = @[post]

let irAddPost = withPost(irAdd, irEq(irVar("result", bv64), irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))))
let irMulPost = withPost(irMul, irEq(irVar("result", bv64), irBinOp(boMul, irVar("x", bv64), irVar("y", bv64))))
let irMaxPost = withPost(irMax, irEq(irVar("result", bv64),
  irIf(irGe(irVar("x", bv64), irVar("y", bv64)), irVar("x", bv64), irVar("y", bv64))))

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: computeIrDigest() is deterministic
# ═══════════════════════════════════════════════════════════════════════════════

suite "computeIrDigest — determinism":
  test "same IR produces same hash":
    let h1 = computeIrDigest(irAdd)
    let h2 = computeIrDigest(irAdd)
    check h1.len == 64
    check h1 == h2

  test "hash is stable across multiple calls":
    let hashes = [
      computeIrDigest(irAdd),
      computeIrDigest(irAdd),
      computeIrDigest(irAdd)
    ]
    check hashes[0] == hashes[1]
    check hashes[1] == hashes[2]

# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: Different IR → different digest
# ═══════════════════════════════════════════════════════════════════════════════

suite "computeIrDigest — different IR":
  test "different function name yields different digest":
    let hAdd = computeIrDigest(irAdd)
    let hMul = computeIrDigest(irMul)
    check hAdd != hMul

  test "different body structure yields different digest":
    let hAdd = computeIrDigest(irAdd)
    let hMax = computeIrDigest(irMax)
    check hAdd != hMax

  test "different function names all produce unique digests":
    let hAdd = computeIrDigest(irAdd)
    let hMul = computeIrDigest(irMul)
    let hMax = computeIrDigest(irMax)
    # All three should be distinct
    check hAdd != hMul
    check hAdd != hMax
    check hMul != hMax

# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: irToSmtScript and irToLeanModule produce non-empty output
# ═══════════════════════════════════════════════════════════════════════════════

suite "crossValidate — both backends produce output":
  test "SMT output is non-empty for simple IR":
    let r = crossValidate(irAddPost)
    check r.z3Result.len > 0

  test "Lean output is non-empty for simple IR":
    let r = crossValidate(irAddPost)
    check r.leanResult.len > 0

  test "SMT output contains set-logic":
    let r = crossValidate(irAddPost)
    check contains(r.z3Result, "(set-logic QF_BV)")

  test "SMT output contains define-fun":
    let r = crossValidate(irAddPost)
    check contains(r.z3Result, "(define-fun add")

  test "Lean output contains def keyword":
    let r = crossValidate(irAddPost)
    check contains(r.leanResult, "def add")

  test "SMT output contains check-sat":
    let r = crossValidate(irAddPost)
    check contains(r.z3Result, "(check-sat)")

  test "crossValidate returns consistent for well-formed IR":
    let r = crossValidate(irAddPost)
    check r.consistent == true

  test "crossValidate works with conditional IR (max)":
    let r = crossValidate(irMaxPost)
    check r.consistent == true
    check r.z3Result.len > 0
    check r.leanResult.len > 0

  test "crossValidate works with multiplication IR":
    let r = crossValidate(irMulPost)
    check r.consistent == true
    check contains(r.z3Result, "(define-fun mul")
    check contains(r.leanResult, "def mul")

# ═══════════════════════════════════════════════════════════════════════════════
# Conformance: shift operations must be explicitly UNSUPPORTED, never boAdd
# ═══════════════════════════════════════════════════════════════════════════════

suite "Shift operations — explicit UNSUPPORTED (SemanticProfileV1 spShiftUnsupported)":
  let bv64 = irTypeBitVec64()

  let irShlBase = irFuncDef(
    name = "shl_op",
    params = @[("x", bv64), ("y", bv64)],
    ret = bv64,
    body = irBinOp(boShl, irVar("x", bv64), irVar("y", bv64))
  )
  let irShl = withPost(irShlBase,
    irEq(irVar("result", bv64), irBinOp(boShl, irVar("x", bv64), irVar("y", bv64))))

  let irShrBase = irFuncDef(
    name = "shr_op",
    params = @[("x", bv64), ("y", bv64)],
    ret = bv64,
    body = irBinOp(boShr, irVar("x", bv64), irVar("y", bv64))
  )
  let irShr = withPost(irShrBase,
    irEq(irVar("result", bv64), irBinOp(boShr, irVar("x", bv64), irVar("y", bv64))))

  test "shl SMT output contains explicit UNSUPPORTED marker":
    let smt = irToSmtScript(irShl)
    check contains(smt, "UNSUPPORTED")

  test "shl SMT output does NOT contain bvadd (no silent boAdd corruption)":
    let smt = irToSmtScript(irShl)
    check not contains(smt, "(bvadd")

  test "shr SMT output contains explicit UNSUPPORTED marker":
    let smt = irToSmtScript(irShr)
    check contains(smt, "UNSUPPORTED")

  test "shr SMT output does NOT contain bvadd (no silent boAdd corruption)":
    let smt = irToSmtScript(irShr)
    check not contains(smt, "(bvadd")

  test "shl and shr produce distinct SMT output (not identical to boAdd)":
    let irAddRef = withPost(irFuncDef(
      name = "add_ref",
      params = @[("x", bv64), ("y", bv64)],
      ret = bv64,
      body = irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))
    ), irEq(irVar("result", bv64),
      irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))))
    let smtAdd = irToSmtScript(irAddRef)
    let smtShl = irToSmtScript(irShl)
    check smtAdd != smtShl
