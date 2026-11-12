import std/[strutils, sequtils]
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import core/trusted/ir_to_lean
import core/trusted/axiom_ir
import verification/cross_validation
import core/deterministic_cas_key

let bv64 = irTypeBitVec64()
let boolType = irTypeBool()

# ═══════════════════════════════════════════════════════════════════════
# Test IR fixtures
# ═══════════════════════════════════════════════════════════════════════

## Simple addition: add(x, y) = x + y
let irAdd = irFuncDef(
  name = "add",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irAdd(irVar("x", bv64), irVar("y", bv64))
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

## Postcondition for add (honest spec contract)
func withPost(f: IRFuncDef; post: IRExpr): IRFuncDef =
  result = f
  result.postConditions = @[post]

let irAddPost = withPost(irAdd,
  irEq(irVar("result", bv64), irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))))

let irMaxPost = withPost(irMax,
  irEq(irVar("result", bv64),
    irIf(irGe(irVar("x", bv64), irVar("y", bv64)),
      irVar("x", bv64), irVar("y", bv64))))

# ═══════════════════════════════════════════════════════════════════════
# Commutative-op variants (reordered operands)
# ═══════════════════════════════════════════════════════════════════════

## add(y, x) — operands swapped vs irAdd
let irAddReversed = irFuncDef(
  name = "add",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irAdd(irVar("y", bv64), irVar("x", bv64))
)

let irAddReversedPost = withPost(irAddReversed,
  irEq(irVar("result", bv64), irBinOp(boAdd, irVar("y", bv64), irVar("x", bv64))))

## mul(x, y) vs mul(y, x)
let irMul = irFuncDef(
  name = "mul",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irMul(irVar("x", bv64), irVar("y", bv64))
)

let irMulReversed = irFuncDef(
  name = "mul",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irMul(irVar("y", bv64), irVar("x", bv64))
)

## Phase 2e: unsigned remainder (%%) — boRemU → bvurem / BitVec.umod
let irRemU = irFuncDef(
  name = "urem",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irBinOp(boRemU, irVar("x", bv64), irVar("y", bv64))
)
let irRemUPost = withPost(irRemU,
  irEq(irVar("result", bv64), irBinOp(boRemU, irVar("x", bv64), irVar("y", bv64))))

## Phase 2e: signed remainder (mod / %) — boRem → bvsrem / BitVec.srem
let irRemS = irFuncDef(
  name = "srem",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irBinOp(boRem, irVar("x", bv64), irVar("y", bv64))
)
let irRemSPost = withPost(irRemS,
  irEq(irVar("result", bv64), irBinOp(boRem, irVar("x", bv64), irVar("y", bv64))))

## Phase 2a/2b: signed division — boDiv → bvsdiv / BitVec.sdiv
let irDivS = irFuncDef(
  name = "sdiv",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irBinOp(boDiv, irVar("x", bv64), irVar("y", bv64))
)
let irDivSPost = withPost(irDivS,
  irEq(irVar("result", bv64), irBinOp(boDiv, irVar("x", bv64), irVar("y", bv64))))

# ═══════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════

proc main() =
  echo "=== Canonical Determinism Golden Tests (Phase 2f) ==="

  # -- (a) Digest determinism: same IR → same canonical digest ----------
  block:
    let d1 = computeIrDigest(irAdd)
    let d2 = computeIrDigest(irAdd)
    doAssert d1.len == 64, "digest must be 64 hex chars (SHA-256)"
    doAssert d1 == d2, "same IR must produce same canonical digest"
    echo "  [PASS] same IR → same canonical digest"

  # -- (a) Digest determinism: stable across multiple calls -------------
  block:
    let hashes = [computeIrDigest(irAdd), computeIrDigest(irAdd), computeIrDigest(irAdd)]
    doAssert hashes[0] == hashes[1] and hashes[1] == hashes[2],
      "digest must be stable across repeated calls"
    echo "  [PASS] digest stable across multiple calls"

  # -- (a) Different IR → different digest ------------------------------
  block:
    let dAdd = computeIrDigest(irAdd)
    let dMul = computeIrDigest(irMul)
    let dMax = computeIrDigest(irMax)
    doAssert dAdd != dMul, "different IR (add vs mul) must yield different digest"
    doAssert dAdd != dMax, "different IR (add vs max) must yield different digest"
    doAssert dMul != dMax, "different IR (mul vs max) must yield different digest"
    echo "  [PASS] different IR → different digest"

  # -- (a) Commutative op canonicalization: reordered operands → same digest
  block:
    let dForward = computeIrDigest(irAdd)
    let dReversed = computeIrDigest(irAddReversed)
    doAssert dForward == dReversed,
      "commutative boAdd with reordered operands must yield same canonical digest"
    echo "  [PASS] commutative op reordered operands → same canonical digest"

  # -- (a) Commutative op canonicalization: mul reordered → same digest -
  block:
    let dMulFwd = computeIrDigest(irMul)
    let dMulRev = computeIrDigest(irMulReversed)
    doAssert dMulFwd == dMulRev,
      "commutative boMul with reordered operands must yield same canonical digest"
    echo "  [PASS] commutative mul reordered → same canonical digest"

  # -- (b) SMT text identity: irToSmtScript vs crossValidate().z3Result --
  block:
    let smtDirect = irToSmtScript(irAddPost)
    let cv = crossValidate(irAddPost)
    doAssert smtDirect == cv.z3Result,
      "irToSmtScript(f) must be byte-identical to crossValidate(f).z3Result"
    doAssert smtDirect.len > 0, "SMT output must be non-empty"
    echo "  [PASS] irToSmtScript == crossValidate().z3Result (byte-identical)"

  # -- (b) SMT text identity for commutative-op IR (reordered) -----------
  block:
    let smtForward = irToSmtScript(irAddPost)
    let smtReversed = irToSmtScript(irAddReversedPost)
    doAssert smtForward != smtReversed,
      "irToSmtScript must reflect operand order (raw IR, no canonicalization for SMT)"
    echo "  [PASS] irToSmtScript preserves operand order (non-canonicalized SMT path)"

  # -- (b) SMT text determinism: same IR → same SMT across multiple calls
  block:
    let smt1 = irToSmtScript(irAddPost)
    let smt2 = irToSmtScript(irAddPost)
    let smt3 = irToSmtScript(irAddPost)
    doAssert smt1 == smt2, "irToSmtScript must be deterministic (call 1 == call 2)"
    doAssert smt2 == smt3, "irToSmtScript must be deterministic (call 2 == call 3)"
    echo "  [PASS] irToSmtScript deterministic across repeated calls"

  # -- (b) SMT text identity for max (conditional IR) --------------------
  block:
    let smtDirect = irToSmtScript(irMaxPost)
    let cv = crossValidate(irMaxPost)
    doAssert smtDirect == cv.z3Result,
      "irToSmtScript(max) must be byte-identical to crossValidate(max).z3Result"
    doAssert smtDirect.contains("(set-logic QF_BV)"), "SMT must have set-logic"
    doAssert smtDirect.contains("(define-fun max_impl"), "SMT must define max_impl"
    doAssert smtDirect.contains("(check-sat)"), "SMT must have check-sat"
    echo "  [PASS] irToSmtScript == crossValidate().z3Result for conditional IR"

  # -- (b) crossValidate digest matches computeIrDigest ------------------
  block:
    let cv = crossValidate(irAddPost)
    let directDigest = computeIrDigest(irAddPost)
    doAssert cv.irDigest == computeDeterministicCasKey(directDigest),
      "crossValidate irDigest must match computeDeterministicCasKey(computeIrDigest(f))"
    echo "  [PASS] crossValidate irDigest matches direct computation"

  # -- (b) SMT text non-empty for well-formed IR -------------------------
  block:
    let cv = crossValidate(irAddPost)
    doAssert cv.z3Result.len > 0, "crossValidate SMT output must be non-empty"
    doAssert cv.leanResult.len > 0, "crossValidate Lean output must be non-empty"
    doAssert cv.consistent == true, "crossValidate must report consistent for well-formed IR"
    echo "  [PASS] crossValidate produces non-empty SMT and Lean output"

  # -- (b) Vacuous IR (no postconditions) produces empty SMT ------------
  block:
    let irNoPost = irFuncDef(
      name = "nocheck",
      params = @[("x", bv64)],
      ret = bv64,
      body = irVar("x", bv64)
    )
    let smt = irToSmtScript(irNoPost)
    doAssert smt.len == 0, "irToSmtScript must return empty string for IR without postconditions"
    echo "  [PASS] vacuous IR (no postconditions) → empty SMT"

  # ══════════════════════════════════════════════════════════════════
  # Phase 2e: %% → BitVec.umod (Lean) and boRemU → bvurem (SMT) golden tests
  # ══════════════════════════════════════════════════════════════════

  # -- (c) Phase 2e: %% (boRemU) → BitVec.umod in Lean -----------------
  block:
    let leanDirect = irToLeanModule(irRemUPost)
    let cv = crossValidate(irRemUPost)
    doAssert leanDirect == cv.leanResult,
      "irToLeanModule(f) must be byte-identical to crossValidate(f).leanResult for %% (boRemU)"
    doAssert leanDirect.contains("BitVec.umod"),
      "Phase 2e: %% (boRemU) must map to BitVec.umod in Lean, got: " & leanDirect
    echo "  [PASS] Phase 2e: %% (boRemU) → BitVec.umod in Lean (byte-identical crossValidate)"

  # -- (c) Phase 2e: mod (boRem) → BitVec.srem in Lean ----------------
  block:
    let leanDirect = irToLeanModule(irRemSPost)
    let cv = crossValidate(irRemSPost)
    doAssert leanDirect == cv.leanResult,
      "irToLeanModule(f) must be byte-identical to crossValidate(f).leanResult for mod (boRem)"
    doAssert leanDirect.contains("BitVec.srem"),
      "Phase 2e: mod (boRem) must map to BitVec.srem in Lean, got: " & leanDirect
    echo "  [PASS] Phase 2e: mod (boRem) → BitVec.srem in Lean (byte-identical crossValidate)"

  # -- (c) Phase 2e: %% (boRemU) → bvurem in SMT (no regression to bvsrem)
  block:
    let smtDirect = irToSmtScript(irRemUPost)
    doAssert smtDirect.contains("(bvurem"),
      "Phase 2e: %% (boRemU) must lower to bvurem in SMT, got: " & smtDirect
    doAssert smtDirect.contains("(bvsrem") == false,
      "Phase 2e regression: %% (boRemU) must NOT lower to bvsrem in SMT"
    let cv = crossValidate(irRemUPost)
    doAssert smtDirect == cv.z3Result,
      "irToSmtScript(%%) must be byte-identical to crossValidate(%%).z3Result"
    echo "  [PASS] Phase 2e: %% (boRemU) → bvurem in SMT, no bvsrem regression"

  # -- (c) Phase 2e: mod (boRem) → bvsrem in SMT ---------------------
  block:
    let smtDirect = irToSmtScript(irRemSPost)
    doAssert smtDirect.contains("(bvsrem"),
      "Phase 2e: mod (boRem) must lower to bvsrem in SMT, got: " & smtDirect
    doAssert smtDirect.contains("(bvurem") == false,
      "Phase 2e regression: mod (boRem) must NOT lower to bvurem in SMT"
    let cv = crossValidate(irRemSPost)
    doAssert smtDirect == cv.z3Result,
      "irToSmtScript(mod) must be byte-identical to crossValidate(mod).z3Result"
    echo "  [PASS] Phase 2e: mod (boRem) → bvsrem in SMT, no bvurem regression"

  # -- (c) Phase 2a/2b: boDiv → bvsdiv in SMT ------------------------
  block:
    let smtDirect = irToSmtScript(irDivSPost)
    doAssert smtDirect.contains("(bvsdiv"),
      "Phase 2a/2b: boDiv must lower to bvsdiv in SMT, got: " & smtDirect
    let cv = crossValidate(irDivSPost)
    doAssert smtDirect == cv.z3Result,
      "irToSmtScript(boDiv) must be byte-identical to crossValidate(boDiv).z3Result"
    echo "  [PASS] Phase 2a/2b: boDiv → bvsdiv in SMT"

  # -- (c) Phase 2e: boDiv → BitVec.sdiv in Lean ----------------------
  block:
    let leanDirect = irToLeanModule(irDivSPost)
    let cv = crossValidate(irDivSPost)
    doAssert leanDirect == cv.leanResult,
      "irToLeanModule(f) must be byte-identical to crossValidate(f).leanResult for boDiv"
    doAssert leanDirect.contains("BitVec.sdiv"),
      "Phase 2e: boDiv must map to BitVec.sdiv in Lean, got: " & leanDirect
    echo "  [PASS] Phase 2e: boDiv → BitVec.sdiv in Lean (byte-identical crossValidate)"

  # -- (c) crossValidate vs direct irToSmtScript byte-identical Lean --
  block:
    let leanDirect = irToLeanModule(irAddPost)
    let cv = crossValidate(irAddPost)
    doAssert leanDirect == cv.leanResult,
      "irToLeanModule(f) must be byte-identical to crossValidate(f).leanResult"
    echo "  [PASS] crossValidate vs direct irToLeanModule byte-identical"

  echo "=== All canonical determinism golden tests passed ==="

main()