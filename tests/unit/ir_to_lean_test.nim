## Unit tests for ir_to_lean.nim — IR to Lean 4 source code converter.

import std/unittest
import std/strutils
import core/trusted/ir_to_lean
import core/trusted/lean_goal
import core/trusted/axiom_ir_helpers
import core/results

suite "IR to Lean — Type Mapping":
  test "irtBitVec64 → BitVec 64":
    check irTypeToLean(irTypeBitVec64()) == "BitVec 64"

  test "irtBool → Bool":
    check irTypeToLean(irTypeBool()) == "Bool"

  test "irtList(BitVec64) → List (BitVec 64)":
    check irTypeToLean(irTypeList(irTypeBitVec64())) == "List (BitVec 64)"

  test "irtString → String":
    check irTypeToLean(irTypeString()) == "String"

  test "irtEnum → Nat":
    check irTypeToLean(irTypeEnum("Color", @["Red", "Blue"], @[0'i64, 1'i64])) == "Nat"

  test "irtVariant → Nat":
    check irTypeToLean(irTypeVariant("Status", @["Ok", "Err"], @[0'i64, 1'i64], @[])) == "Nat"

  test "nested list type":
    check irTypeToLean(irTypeList(irTypeList(irTypeBool()))) == "List (List (Bool))"

suite "IR to Lean — Binary Operator Mapping":
  test "boAdd → +":
    check irBinOpToLean(boAdd) == "+"

  test "boSub → -":
    check irBinOpToLean(boSub) == "-"

  test "boMul → *":
    check irBinOpToLean(boMul) == "*"

  test "boDiv → BitVec.sdiv":
    check irBinOpToLean(boDiv) == "BitVec.sdiv"

  test "boRem → BitVec.srem":
    check irBinOpToLean(boRem) == "BitVec.srem"

  test "boLt → <":
    check irBinOpToLean(boLt) == "<"

  test "boLe → ≤":
    check irBinOpToLean(boLe) == "≤"

  test "boGt → >":
    check irBinOpToLean(boGt) == ">"

  test "boGe → ≥":
    check irBinOpToLean(boGe) == "≥"

  test "boAnd → &&":
    check irBinOpToLean(boAnd) == "&&"

  test "boOr → ||":
    check irBinOpToLean(boOr) == "||"

  test "boEq → ==":
    check irBinOpToLean(boEq) == "=="

suite "IR to Lean — Unary Operator Mapping":
  test "uoNot → !":
    check irUnaryOpToLean(uoNot) == "!"

  test "uoBvNot → ~~~":
    check irUnaryOpToLean(uoBvNot) == "~~~"

  test "uoBvNeg → -'":
    check irUnaryOpToLean(uoBvNeg) == "-'"

suite "IR to Lean — Expression Conversion":
  test "irLit converts to number string":
    let e = irLit(42)
    check irExprToLean(e) == "42"

  test "irFloatLit converts to float string":
    let e = IRExpr(typ: irTypeBitVec64(), kind: irFloatLit, floatVal: 3.14)
    check irExprToLean(e).len > 0

  test "irVar converts to name":
    let e = irVar("x", irTypeBitVec64())
    check irExprToLean(e) == "x"

  test "irStringLit converts to quoted string":
    let e = IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: "hello")
    check irExprToLean(e) == "\"hello\""

  test "irBinOp converts with infix notation":
    let e = irBinOp(boAdd, irLit(1), irLit(2))
    check irExprToLean(e) == "(1 + 2)"

  test "irIf converts to if-then-else":
    let cond = irEq(irVar("x", irTypeBitVec64()), irLit(0))
    let e = irIf(cond, irLit(1), irLit(2))
    check "if " in irExprToLean(e)
    check "then" in irExprToLean(e)
    check "else" in irExprToLean(e)

  test "irLet converts to let binding":
    let e = irLet("x", irLit(42), irVar("x", irTypeBitVec64()))
    check "let x := " in irExprToLean(e)

  test "irCall with builtin len":
    let e = irCall("len", @[irVar("s", irTypeString())])
    check irExprToLean(e) == "String.length s"

  test "irCall with builtin substr":
    let e = irCall("substr", @[irVar("s", irTypeString()), irLit(0), irLit(5)])
    check irExprToLean(e).startsWith("String.take")

  test "irCall with builtin charAt":
    let e = irCall("charAt", @[irVar("s", irTypeString()), irLit(0)])
    check irExprToLean(e).startsWith("String.get")

  test "irCall with builtin concat":
    let e = irCall("concat", @[irVar("a", irTypeString()), irVar("b", irTypeString())])
    check irExprToLean(e).startsWith("String.append")

  test "irCall with builtin contains":
    let e = irCall("contains", @[irVar("s", irTypeString()), irVar("sub", irTypeString())])
    check irExprToLean(e).startsWith("String.contains")

  test "irCall with builtin indexOf":
    let e = irCall("indexOf", @[irVar("s", irTypeString()), irVar("sub", irTypeString())])
    check irExprToLean(e).startsWith("String.indexOf")

  test "irCall with custom function":
    let e = irCall("foo", @[irLit(1), irLit(2)])
    check irExprToLean(e) == "foo 1 2"

  test "opCastToBool converts BV64 to Bool":
    let e = irCall("opCastToBool", @[irVar("x", irTypeBitVec64())])
    check "(x != 0)" in irExprToLean(e)

  test "opCastToBv64 converts Bool to Nat":
    let e = irCall("opCastToBv64", @[irVar("b", irTypeBool())])
    check "if " in irExprToLean(e)
    check "then 1 else 0" in irExprToLean(e)

  test "irRecCall uses __self__ placeholder":
    let e = irRecCall(@[irLit(42)])
    check irExprToLean(e).startsWith("__self__")

  test "irUnaryOp uoNot":
    let e = irUnaryOp(uoNot, irVar("p", irTypeBool()))
    check irExprToLean(e) == "(! p)"

  test "irUnaryOp uoBvNot":
    let e = irUnaryOp(uoBvNot, irVar("x", irTypeBitVec64()))
    check irExprToLean(e).contains("~~~")

  test "irCase match expression":
    let scrutinee = irVar("n", irTypeBitVec64())
    let branches = @[CaseBranch(pattern: 0, body: irLit(0)), CaseBranch(pattern: 1, body: irLit(1))]
    let e = irCase(scrutinee, branches, nil)
    check "match " in irExprToLean(e)
    check "| 0 => 0" in irExprToLean(e)

  test "irCast":
    let e = IRExpr(typ: irTypeBool(), kind: irCast, castExpr: irVar("x", irTypeBitVec64()), castFrom: irTypeBitVec64(), castTo: irTypeBool())
    check "(cast " in irExprToLean(e)

  test "nested binary ops":
    let e = irBinOp(boAdd, irBinOp(boMul, irLit(2), irLit(3)), irLit(4))
    let lean = irExprToLean(e)
    check "(2 * 3)" in lean
    check " + 4)" in lean

suite "IR to Lean — Termination Strategy":
  test "non-recursive function returns tsNone":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    check detectTerminationStrategy(f) == tsNone

  test "list parameter returns tsStructural":
    var f = irFuncDef(
      name = "process_list",
      params = @[("lst", irTypeList(irTypeBitVec64()))],
      ret = irTypeBitVec64(),
      body = irLit(0),
      isRec = true
    )
    check detectTerminationStrategy(f) == tsStructural

  test "numeric decrement detected":
    let f = irFuncDef(
      name = "decrement",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irSub(irVar("n", irTypeBitVec64()), irLit(1))
    )
    check detectNumericDecrement(f.body, "n") == true

  test "no numeric decrement":
    let f = irFuncDef(
      name = "double",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irMul(irVar("n", irTypeBitVec64()), irLit(2))
    )
    check detectNumericDecrement(f.body, "n") == false

  test "structural recursion detection via case":
    let body = irCase(
      irVar("lst", irTypeList(irTypeBitVec64())),
      @[CaseBranch(pattern: 0, body: irLit(0))],
      nil
    )
    check detectStructuralRecursion(body) == true

  test "fallback strategy for unknown recursion":
    var funcDef = irFuncDef(
      name = "unknown_rec",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irRecCall(@[irVar("n", irTypeBitVec64())]),
      isRec = true
    )
    check detectTerminationStrategy(funcDef) == tsFallback

suite "IR to Lean — Function Definition":
  test "irFuncDefToLean simple function":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let lean = irFuncDefToLean(f)
    check "def add" in lean
    check "BitVec 64" in lean
    ## Multi-parameter golden: Lean 4 requires per-parameter binders
    ## `(a : T) (b : U)` — a single `(a : T b : U)` group does not parse.
    check lean == "def add (a : BitVec 64) (b : BitVec 64) : BitVec 64 :=\n" &
                  "  (a + b)"

  test "emitRecDef for recursive function":
    var f = irFuncDef(
      name = "factorial",
      params = @[("n", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irIf(
        irLe(irVar("n", irTypeBitVec64()), irLit(1)),
        irLit(1),
        irMul(irVar("n", irTypeBitVec64()), irRecCall(@[irSub(irVar("n", irTypeBitVec64()), irLit(1))]))
      ),
      isRec = true
    )
    let lean = emitRecDef(f)
    check "def factorial" in lean or "partial def" in lean

  test "resolveRecCalls replaces __self__":
    let body = irRecCall(@[irLit(1)])
    check resolveRecCalls(body, "factorial") == "factorial 1"

  test "leanOutputMetadata format":
    let f = irFuncDef(
      name = "test_fn",
      params = @[],
      ret = irTypeBitVec64(),
      body = irLit(0)
    )
    let meta = leanOutputMetadata(f)
    check "test_fn" in meta
    check "isRecursive" in meta
    check "terminationStrategy" in meta

  test "irToLeanModule generates complete module":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let moduleCode = irToLeanModule(f)
    check "import Init" in moduleCode
    check "import Std.Tactic.BVDecide" in moduleCode
    check "def add" in moduleCode
    check "#print axioms" in moduleCode

suite "IR to Lean — Refined Module":
  test "refinedExprToProp on bin op lt":
    let e = irBinOp(boLt, irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    let result = refinedExprToProp(e)
    check result.isOk()
    # Signed-order BitVec predicate (no bare `<` infix — Lean core has no
    # signed BitVec order; see leanBvSlt).
    check result.get == "(BitVec.slt x y)"

  test "refinedExprToProp comparison emits signed BitVec predicate (bv_decide fragment)":
    # The comparison proposition must stay inside the dischargeable fragment:
    # the former `(1 : BitVec 64).toInt ≥ (1 : BitVec 64).toInt` Int-projection
    # emission is undischargeable (measured 2026-10-09, lean 4.33.0: omega
    # cannot fold BitVec.toInt literals, bv_decide rejects Int goals) and left
    # certificates stalled at certZ3Candidate. The signed-order predicate
    # `BitVec.sle` (operands mirrored for ≥) is by definition the same Int
    # order and kernel-checks clean under `bv_decide` (exit 0, no axioms).
    let e = irBinOp(boGe, irVar("result", irTypeBitVec64()), irLit(1))
    let result = refinedExprToProp(e)
    check result.isOk()
    check "1.toInt" notin result.get
    check "(BitVec.sle 1 result)" == result.get

  test "irExprToLean comparison emits signed BitVec predicate (bv_decide fragment)":
    let e = irBinOp(boGt, irVar("maxWorkers", irTypeBitVec64()), irLit(0))
    let rendered = irExprToLean(e)
    check "0.toInt" notin rendered
    check "(BitVec.slt 0 maxWorkers)" == rendered

  test "refinedExprToProp on bin op eq":
    let e = irBinOp(boEq, irVar("x", irTypeBitVec64()), irLit(0))
    let result = refinedExprToProp(e)
    check result.isOk()
    check "=" in result.get

  test "refinedExprToProp on unary not":
    let e = irUnaryOp(uoNot, irBinOp(boEq, irVar("x", irTypeBitVec64()), irLit(0)))
    let result = refinedExprToProp(e)
    check result.isOk()
    check "\u{00AC}" in result.get or "¬" in result.get

  test "refinedExprToProp on nil returns err":
    let result = refinedExprToProp(nil)
    check result.isErr()

  test "refinedExprToProp on lit":
    let e = irLit(42)
    let result = refinedExprToProp(e)
    check result.isOk()
    check "42" in result.get

  test "refinedExprToProp on var":
    let e = irVar("x", irTypeBitVec64())
    let result = refinedExprToProp(e)
    check result.isOk()
    check "x" in result.get

  test "irToLeanRefinedModule basic":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let result = irToLeanRefinedModule(f)
    check result.isOk()
    check "def add" in result.get
    check "import Init" in result.get

suite "IR to Lean — No Prefix Operator Assertion":
  test "binary operators never emitted in prefix SMT-LIB2 form":
    ## Regression test for N3 audit finding: irBinExprToLean must emit
    ## Lean 4 infix notation, never SMT-LIB2 prefix like "(< a b)".
    ## Comparisons are exempt from the infix form: Lean core has no signed
    ## BitVec infix order, so they lower to the named core functions
    ## `BitVec.slt`/`BitVec.sle` (like boDiv/boRem → `BitVec.sdiv`/`srem`)
    ## — still never a bare SMT operator in prefix position.
    let ops: seq[(BinOpKind, string)] = @[
      (boAdd, "+"), (boSub, "-"), (boMul, "*"),
      (boAnd, "&&"), (boOr, "||"), (boEq, "==")
    ]
    for (op, _) in ops:
      let e = irBinOp(op, irLit(1), irLit(2))
      let lean = irExprToLean(e)
      let opStr = irBinOpToLean(op)
      ## Prefix form "(<op> <lhs> <rhs>)" must NOT appear.
      ## Infix form "(<lhs> <op> <rhs>)" must appear.
      check not lean.startsWith("(" & opStr & " ")
      check lean.contains(" " & opStr & " ")

  test "comparisons emit signed-order BitVec.slt/sle (never bare SMT prefix)":
    ## Signed-order emission (mirrored operands for >/≥); the banned form is
    ## a bare SMT-LIB2 operator in prefix position ("(< a b)"), not a named
    ## core function application.
    check irExprToLean(irBinOp(boLt, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))) ==
      "(BitVec.slt a b)"
    check irExprToLean(irBinOp(boLe, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))) ==
      "(BitVec.sle a b)"
    check irExprToLean(irBinOp(boGt, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))) ==
      "(BitVec.slt b a)"
    check irExprToLean(irBinOp(boGe, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))) ==
      "(BitVec.sle b a)"

suite "IR to Lean — Sectioned LeanGoal renderer":
  test "renderHeaderImports: Init, then BVDecide, then deduped sorted extras":
    let header = renderHeaderImports(
      @["Zeta", "Alpha", "Std.Tactic.BVDecide", "Aesop", "Alpha", ""])
    check header == "import Init\n" &
                    "import Std.Tactic.BVDecide\n" &
                    "import Aesop\n" &
                    "import Alpha\n" &
                    "import Zeta\n\n"

  test "renderHeaderImports omits BVDecide when not required":
    check renderHeaderImports(@["Axiom.IR.Basic"]) ==
      "import Init\nimport Axiom.IR.Basic\n\n"

  test "renderHeaderImports deduplicates Init":
    check renderHeaderImports(@["Init", "Init"]) == "import Init\n\n"

  test "goalTheoremName maps obligationId to obligation_<id>":
    let goal = makeLeanGoal(theoremName = "add", proposition = "r = a + b",
                            proofScript = "by\n  rfl",
                            assumptions = @["a : BitVec 64", "b : BitVec 64"],
                            requiredImports = @["Aesop"],
                            obligationId = "c4id42")
    check goalTheoremName(goal) == "obligation_c4id42"
    check renderTheorem(goal) ==
      "theorem obligation_c4id42 (a : BitVec 64) (b : BitVec 64) : r = a + b :=\n"
    check renderEnd(goal) == "#print axioms obligation_c4id42\n"

  test "goalTheorem legacy naming when obligationId empty":
    let goal = makeLeanGoal(theoremName = "add_spec", proposition = "True",
                            proofScript = "by rfl")
    check goalTheoremName(goal) == "add_spec"
    check renderTheorem(goal) == "theorem add_spec : True :=\n"
    check renderEnd(goal) == "#print axioms add_spec\n"

  test "renderLeanModule: imports only in header, obligation naming, targeted print":
    let goal = makeLeanGoal(theoremName = "clamp_spec",
                            proposition = "r = r",
                            proofScript = "by\n  bv_decide",
                            requiredImports = @["Std.Tactic.BVDecide", "Aesop"],
                            obligationId = "x1a2b3c")
    let moduleCode = renderLeanModule(goal)
    check moduleCode.startsWith("import Init\n")
    check "import Aesop\n" in moduleCode
    check "theorem obligation_x1a2b3c" in moduleCode
    check "#print axioms obligation_x1a2b3c\n" in moduleCode
    check "namespace Axiom\n" in moduleCode
    check "end Axiom\n" in moduleCode
    let theoremPos = moduleCode.find("theorem obligation_x1a2b3c")
    check theoremPos >= 0
    check moduleCode.find("import ", theoremPos) < 0

  test "irToLeanModule imports all before first def, targeted print":
    let f = irFuncDef(
      name = "add",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    let moduleCode = irToLeanModule(f, @["Axiom.IR.Basic"])
    let defPos = moduleCode.find("def add ")
    check defPos >= 0
    check moduleCode.find("import ", defPos) < 0
    check "#print axioms add\n" in moduleCode

  test "irToLeanModule with postconditions: no import after theorem":
    var f = irFuncDef(
      name = "band",
      params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
      ret = irTypeBitVec64(),
      body = irAdd(irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64()))
    )
    f.postConditions = @[irBvNot(irVar("a", irTypeBitVec64()))]
    let moduleCode = irToLeanModule(f)
    ## postcondition with bitwise op routes to bv_decide; the module header
    ## must still be the ONLY place imports appear — never after the theorem.
    check "theorem band_post0" in moduleCode
    let defPos = moduleCode.find("def band ")
    check defPos >= 0
    check moduleCode.find("import ", defPos) < 0
    check moduleCode.count("import Std.Tactic.BVDecide\n") == 1
    check "#print axioms band\n" in moduleCode

