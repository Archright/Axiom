## Unit tests for smt_sort.nim — compile-time SMT sort tracking via phantom types.

{.push raises: [CatchableError].}

import std/unittest
import std/strutils
import core/trusted/smt_sort

suite "SMT Sort — Constructors":
  test "bvLit produces hex literal":
    let e = bvLit(255)
    check e.raw == "#x00000000000000FF"

  test "bvLit zero":
    let e = bvLit(0)
    check e.raw == "#x0000000000000000"

  test "bvLit large value":
    let e = bvLit(0xDEADBEEF'i64)
    check e.raw == "#x00000000DEADBEEF"

  test "bvVar creates named variable":
    let e = bvVar("x")
    check e.raw == "x"

  test "bvVar with complex name":
    let e = bvVar("_tmp`gensym12")
    check e.raw == "_tmp`gensym12"

  test "boolLit true":
    let e = boolLit(true)
    check e.raw == "true"

  test "boolLit false":
    let e = boolLit(false)
    check e.raw == "false"

  test "boolVar creates named variable":
    let e = boolVar("p")
    check e.raw == "p"

  test "fromRaw wraps string into typed expr":
    let e = fromRaw[Bv64Sort]("(bvadd x y)")
    check e.raw == "(bvadd x y)"

  test "toRaw extracts raw string":
    let e = bvLit(42)
    check toRaw(e) == "#x000000000000002A"

  test "toRaw on bool expr":
    let e = boolLit(true)
    check toRaw(e) == "true"

suite "SMT Sort — Boolean Connectives":
  test "smtAnd combines two bool vars":
    let a = boolVar("p")
    let b = boolVar("q")
    let e = smtAnd(a, b)
    check e.raw == "(and p q)"

  test "smtOr combines two bool vars":
    let a = boolVar("p")
    let b = boolVar("q")
    let e = smtOr(a, b)
    check e.raw == "(or p q)"

  test "smtNot negates bool var":
    let e = smtNot(boolVar("p"))
    check e.raw == "(not p)"

  test "smtImplies two bool vars":
    let a = boolVar("p")
    let b = boolVar("q")
    let e = smtImplies(a, b)
    check e.raw == "(=> p q)"

  test "smtConjunction empty returns true":
    let e = smtConjunction @[]
    check e.raw == "true"

  test "smtConjunction single element returns that element":
    let p = boolVar("p")
    let e = smtConjunction @[p]
    check e.raw == "p"

  test "smtConjunction multiple elements":
    let e = smtConjunction @[boolVar("p"), boolVar("q"), boolVar("r")]
    check e.raw == "(and p q r)"

  test "smtDisjunction empty returns false":
    let e = smtDisjunction @[]
    check e.raw == "false"

  test "smtDisjunction single element returns that element":
    let p = boolVar("p")
    let e = smtDisjunction @[p]
    check e.raw == "p"

  test "smtDisjunction multiple elements":
    let e = smtDisjunction @[boolVar("p"), boolVar("q"), boolVar("r")]
    check e.raw == "(or p q r)"

  test "nested boolean connectives":
    let p = boolVar("p")
    let q = boolVar("q")
    let r = boolVar("r")
    let inner = smtAnd(p, q)
    let outer = smtOr(inner, r)
    check outer.raw == "(or (and p q) r)"

  test "implies chain":
    let a = boolVar("a")
    let b = boolVar("b")
    let c = boolVar("c")
    let e = smtImplies(smtImplies(a, b), c)
    check e.raw == "(=> (=> a b) c)"

suite "SMT Sort — Bitvector Arithmetic":
  test "smtBvAdd":
    let a = bvVar("x")
    let b = bvVar("y")
    let e = smtBvAdd(a, b)
    check e.raw == "(bvadd x y)"

  test "smtBvSub":
    let e = smtBvSub(bvVar("x"), bvVar("y"))
    check e.raw == "(bvsub x y)"

  test "smtBvMul":
    let e = smtBvMul(bvVar("x"), bvVar("y"))
    check e.raw == "(bvmul x y)"

  test "smtBvAnd bitwise":
    let e = smtBvAnd(bvVar("x"), bvVar("y"))
    check e.raw == "(bvand x y)"

  test "smtBvOr bitwise":
    let e = smtBvOr(bvVar("x"), bvVar("y"))
    check e.raw == "(bvor x y)"

  test "smtBvXor":
    let e = smtBvXor(bvVar("x"), bvVar("y"))
    check e.raw == "(bvxor x y)"

  test "smtBvNot":
    let e = smtBvNot(bvVar("x"))
    check e.raw == "(bvnot x)"

  test "smtBvShl":
    let e = smtBvShl(bvVar("x"), bvVar("y"))
    check e.raw == "(bvshl x y)"

  test "smtBvLshr":
    let e = smtBvLshr(bvVar("x"), bvVar("y"))
    check e.raw == "(bvlshr x y)"

  test "smtBvAshr":
    let e = smtBvAshr(bvVar("x"), bvVar("y"))
    check e.raw == "(bvashr x y)"

suite "SMT Sort — Comparisons":
  test "smtBvEq":
    let e = smtBvEq(bvVar("x"), bvVar("y"))
    check e.raw == "(= x y)"

  test "smtBvDistinct":
    let e = smtBvDistinct(bvVar("x"), bvVar("y"))
    check e.raw == "(distinct x y)"

  test "smtBvLt signed less-than":
    let e = smtBvLt(bvVar("x"), bvVar("y"))
    check e.raw == "(bvslt x y)"

  test "smtBvLe signed less-or-equal":
    let e = smtBvLe(bvVar("x"), bvVar("y"))
    check e.raw == "(bvsle x y)"

  test "smtBvGt signed greater-than":
    let e = smtBvGt(bvVar("x"), bvVar("y"))
    check e.raw == "(bvsgt x y)"

  test "smtBvGe signed greater-or-equal":
    let e = smtBvGe(bvVar("x"), bvVar("y"))
    check e.raw == "(bvsge x y)"

suite "SMT Sort — Coercion Round-trips":
  test "coerceToBool: BV64 → Bool":
    let bv = bvVar("x")
    let e = coerceToBool(bv)
    check e.raw == "(not (= x #x0000000000000000))"

  test "coerceToBool of literal non-zero":
    let bv = bvLit(42)
    let e = coerceToBool(bv)
    check e.raw == "(not (= #x000000000000002A #x0000000000000000))"

  test "coerceToBv64: true → BV64":
    let b = boolLit(true)
    let e = coerceToBv64(b)
    check e.raw == "(ite true #x0000000000000001 #x0000000000000000)"

  test "coerceToBv64: false → BV64":
    let b = boolLit(false)
    let e = coerceToBv64(b)
    check e.raw == "(ite false #x0000000000000001 #x0000000000000000)"

  test "coerce round-trip: bv→bool→bv":
    let original = bvVar("x")
    let asBool = coerceToBool(original)
    # Type-level check: asBool is SmtExpr[BoolSort], not Bv64Sort
    # Verify by checking the generated SMT pattern
    check "(not (= x" in asBool.raw
    # The back-converted BV should contain the coercion pattern
    let backToBv = coerceToBv64(asBool)
    check "ite" in backToBv.raw

  test "coerceThenCompare: bv→bool→eq":
    let x = bvVar("x")
    let y = bvVar("y")
    let xNonzero = coerceToBool(x)
    let yNonzero = coerceToBool(y)
    let bothNonzero = smtAnd(xNonzero, yNonzero)
    check "(and" in bothNonzero.raw
    check "(not (= x" in bothNonzero.raw
    check "(not (= y" in bothNonzero.raw

suite "SMT Sort — Raw Bridge":
  test "smtAndRaw empty returns true":
    check smtAndRaw(@[]) == "true"

  test "smtAndRaw single returns that string":
    let result = smtAndRaw(@["p"])
    check result == "p"

  test "smtAndRaw multiple":
    let result = smtAndRaw(@["p", "q", "r"])
    check result == "(and p q r)"

  test "smtOrRaw empty returns false":
    let result = smtOrRaw(@[])
    check result == "false"

  test "smtOrRaw single returns that string":
    let result = smtOrRaw(@["p"])
    check result == "p"

  test "smtOrRaw multiple":
    let result = smtOrRaw(@["p", "q", "r"])
    check result == "(or p q r)"

  test "fromRaw + toRaw identity":
    let orig = "(bvadd (_ BitVec 64) 42)"
    let e = fromRaw[Bv64Sort](orig)
    check toRaw(e) == orig

  test "smtConjunction composed with smtImplies":
    let a = boolVar("a")
    let b = boolVar("b")
    let c = boolVar("c")
    let conj = smtConjunction @[smtImplies(a, b), c]
    check conj.raw == "(and (=> a b) c)"

  test "complex expression: (bvadd (bvsub x y) z)":
    let x = bvVar("x")
    let y = bvVar("y")
    let z = bvVar("z")
    let sub = smtBvSub(x, y)
    let add = smtBvAdd(sub, z)
    check add.raw == "(bvadd (bvsub x y) z)"

  test "chained comparisons with coercion":
    let x = bvVar("x")
    let zero = bvLit(0)
    let gtZero = smtBvGt(x, zero)
    let ltTen = smtBvLt(x, bvLit(10))
    let both = smtAnd(gtZero, ltTen)
    check both.raw == "(and (bvsgt x #x0000000000000000) (bvslt x #x000000000000000A))"

  test "bvLit negative value wraps correctly":
    let e = bvLit(-1'i64)
    check e.raw.len > 0
    check "ff" in e.raw.toLowerAscii
