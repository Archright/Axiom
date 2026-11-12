## Tests for AST-Based Axiom Signature matching (Phase 5A).

import core/trusted/axiom_ir_helpers
import core/verified_axioms/ast_signature
import std/strutils
proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      body
      inc passed
      echo "  PASS: " & name

  echo "=== AST Signature Tests ==="
  echo ""

  # -- Test 1: computeIrTypeSignature deterministic output --------------------
  echo "1. computeIrTypeSignature deterministic output"
  check "same params → same signature (call 1)":
    let params = @[IRFuncParam(name: "a", ty: irTypeBitVec64()),
                   IRFuncParam(name: "b", ty: irTypeBitVec64())]
    let sig = computeIrTypeSignature(params)
    assert sig == "(bv64,bv64)"

  check "same params → same signature (call 2)":
    let params = @[IRFuncParam(name: "x", ty: irTypeBitVec64()),
                   IRFuncParam(name: "y", ty: irTypeBitVec64())]
    let sig = computeIrTypeSignature(params)
    assert sig == "(bv64,bv64)"

  check "empty params → ()":
    let sig = computeIrTypeSignature(@[])
    assert sig == "()"

  echo ""

  # -- Test 2: Different param types → different signatures -------------------
  echo "2. Different param types → different signatures"
  check "bv64 vs bool":
    let paramsA = @[IRFuncParam(name: "a", ty: irTypeBitVec64())]
    let paramsB = @[IRFuncParam(name: "a", ty: irTypeBool())]
    let sigA = computeIrTypeSignature(paramsA)
    let sigB = computeIrTypeSignature(paramsB)
    assert sigA != sigB
    assert sigA == "(bv64)"
    assert sigB == "(bool)"

  check "list(bv64) vs bv64":
    let paramsA = @[IRFuncParam(name: "a", ty: irTypeList(irTypeBitVec64()))]
    let paramsB = @[IRFuncParam(name: "a", ty: irTypeBitVec64())]
    let sigA = computeIrTypeSignature(paramsA)
    let sigB = computeIrTypeSignature(paramsB)
    assert sigA != sigB
    assert sigA == "(list(bv64))"
    assert sigB == "(bv64)"

  echo ""

  # -- Test 3: Same param types → same signature (name-independent) -----------
  echo "3. Same param types → same signature (name-independent)"
  check "param names don't affect signature":
    let paramsA = @[IRFuncParam(name: "foo", ty: irTypeBitVec64()),
                    IRFuncParam(name: "bar", ty: irTypeBool())]
    let paramsB = @[IRFuncParam(name: "x", ty: irTypeBitVec64()),
                    IRFuncParam(name: "y", ty: irTypeBool())]
    assert computeIrTypeSignature(paramsA) == computeIrTypeSignature(paramsB)

  echo ""

  # -- Test 4: computeIrSignatureHash returns valid hex SHA-256 ---------------
  echo "4. computeIrSignatureHash returns valid hex SHA-256"
  check "hash is 64 hex chars":
    let params = @[IRFuncParam(name: "a", ty: irTypeBitVec64()),
                   IRFuncParam(name: "b", ty: irTypeBitVec64())]
    let h = computeIrSignatureHash(params, irTypeBitVec64())
    assert h.len == 64
    for ch in h:
      assert ch in "0123456789abcdef"

  check "same inputs → same hash":
    let params = @[IRFuncParam(name: "a", ty: irTypeBitVec64())]
    let h1 = computeIrSignatureHash(params, irTypeBitVec64())
    let h2 = computeIrSignatureHash(params, irTypeBitVec64())
    assert h1 == h2

  check "different inputs → different hash":
    let paramsA = @[IRFuncParam(name: "a", ty: irTypeBitVec64())]
    let paramsB = @[IRFuncParam(name: "a", ty: irTypeBool())]
    let h1 = computeIrSignatureHash(paramsA, irTypeBitVec64())
    let h2 = computeIrSignatureHash(paramsB, irTypeBool())
    assert h1 != h2

  echo ""

  # -- Test 5: computeNimAstHash is deterministic -----------------------------
  echo "5. computeNimAstHash is deterministic"
  check "same IR func → same hash":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let h1 = computeNimAstHash(f)
    let h2 = computeNimAstHash(f)
    assert h1 == h2
    assert h1.len == 64

  check "different bodies → different hash":
    let f1 = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irLit(1))
    )
    let f2 = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irMul(irVar("a", irTypeBitVec64()), irLit(1))
    )
    assert computeNimAstHash(f1) != computeNimAstHash(f2)

  check "different names → different hash":
    let f1 = irFuncDef(
      name = "foo",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irVar("a", irTypeBitVec64())
    )
    let f2 = irFuncDef(
      name = "bar",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irVar("a", irTypeBitVec64())
    )
    assert computeNimAstHash(f1) != computeNimAstHash(f2)

  echo ""

  # -- Test 6: Different IR funcs → different hashes --------------------------
  echo "6. Different IR funcs → different hashes"
  check "different return types → different hash":
    let f1 = irFuncDef(
      name = "f",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irVar("a", irTypeBitVec64())
    )
    let f2 = irFuncDef(
      name = "f",
      params = @[("a", irTypeBitVec64())],
      ret = irTypeBool(),
      body = irVar("a", irTypeBitVec64())
    )
    assert computeNimAstHash(f1) != computeNimAstHash(f2)

  check "recursive vs non-recursive → different hash":
    let f1 = irFuncDef(
      name = "fac",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irLit(1),
      isRec = false
    )
    let f2 = irFuncDef(
      name = "fac",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irLit(1),
      isRec = true
    )
    assert computeNimAstHash(f1) != computeNimAstHash(f2)

  echo ""

  # -- Test 7: axiomSignature returns populated AxiomSignature ---------------
  echo "7. axiomSignature returns populated AxiomSignature"
  check "all fields populated with leanOutput":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let leanOut = "def add (a b : UInt64) : UInt64 := a + b"
    let sig = axiomSignature(f, leanOut)
    assert sig.nimHash.len == 64
    assert sig.leanHash.len == 64
    assert sig.paramSignature == "(bv64,bv64)->bv64"

  check "empty leanOutput → empty leanHash":
    let f = irFuncDef(
      name = "id",
      params = @[("x", irTypeBool())],
      ret = irTypeBool(),
      body = irVar("x", irTypeBool())
    )
    let sig = axiomSignature(f)
    assert sig.nimHash.len == 64
    assert sig.leanHash == ""
    assert sig.paramSignature == "(bool)->bool"

  check "same func + same lean → same signature":
    let f = irFuncDef(
      name = "max",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irIf(
        irGe(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64())),
        irVar("a", irTypeBitVec64()),
        irVar("b", irTypeBitVec64())
      )
    )
    let lean = "theorem max_eq (a b : Nat) : max a b = if a ≥ b then a else b"
    let s1 = axiomSignature(f, lean)
    let s2 = axiomSignature(f, lean)
    assert s1.nimHash == s2.nimHash
    assert s1.leanHash == s2.leanHash
    assert s1.paramSignature == s2.paramSignature

  echo ""

  # -- Test 8: irExprStructure captures structure, ignores names ---------------
  echo "8. irExprStructure ignores variable names"
  check "different var names → same structure":
    let e1 = irAdd(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let e2 = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    assert irExprStructure(e1) == irExprStructure(e2)

  check "different literal values → different structure":
    let e1 = irLit(1)
    let e2 = irLit(2)
    assert irExprStructure(e1) != irExprStructure(e2)

  echo ""

  # -- Summary --------------------------------------------------------------
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
