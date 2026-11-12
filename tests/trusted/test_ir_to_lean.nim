## Tests for Axiom Core IR → Lean 4 conversion (Phase 2E).
##
## All tests run at compile time via macro.
## If any assertion fails, it produces a compile-time error.

import std/macros
import std/strutils
import core/trusted/ir_to_lean
import core/trusted/lean_goal
import core/trusted/axiom_ir_helpers
macro runTests() =
  # -- Test 1: boAdd → "+" in Lean -----------------------------------------
  block:
    let expr = irBinOp(boAdd, irLit(3), irLit(5))
    let lean = irExprToLean(expr)
    doAssert lean == "(3 + 5)",
      "Test 1: boAdd mapping failed, got: " & lean

  # -- Test 2: irBitVec64 → "BitVec 64" ------------------------------------
  block:
    let t = irTypeBitVec64()
    let lean = irTypeToLean(t)
    doAssert lean == "BitVec 64",
      "Test 2: irBitVec64 mapping failed, got: " & lean

  # -- Test 2b: irBool → "Bool" --------------------------------------------
  block:
    let t = irTypeBool()
    let lean = irTypeToLean(t)
    doAssert lean == "Bool",
      "Test 2b: irBool mapping failed, got: " & lean

  # -- Test 2c: irList → "List (BitVec 64)" --------------------------------
  block:
    let t = irTypeList(irTypeBitVec64())
    let lean = irTypeToLean(t)
    doAssert lean == "List (BitVec 64)",
      "Test 2c: irList mapping failed, got: " & lean

  # -- Test 3: ekIf → "if ... then ... else ..." ---------------------------
  block:
    let cond = irBinOp(boLt, irVar("n", irTypeBitVec64()), irLit(0))
    let thenBr = irBvNeg(irVar("n", irTypeBitVec64()))
    let elseBr = irVar("n", irTypeBitVec64())
    let expr = irIf(cond, thenBr, elseBr)
    let lean = irExprToLean(expr)
    doAssert "if " in lean and "then" in lean and "else" in lean,
      "Test 3: irIf mapping failed, got: " & lean

  # -- Test 4: Non-recursive func → plain "def" ----------------------------
  block:
    let body = irAdd(irVar("a", irTypeBitVec64()),
                     irVar("b", irTypeBitVec64()))
    let f = irFuncDef("add",
                      @[("a", irTypeBitVec64()),
                        ("b", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = false)
    let lean = irFuncDefToLean(f)
    doAssert lean.startsWith("def add "),
      "Test 4: expected 'def add', got: " & lean
    doAssert "partial" notin lean,
      "Test 4: non-recursive def must not be partial, got: " & lean
    ## Multi-parameter golden: each parameter is its own binder group
    ## `(a : T) (b : U)` — a single `(a : T b : U)` group does not parse.
    doAssert lean == "def add (a : BitVec 64) (b : BitVec 64) : BitVec 64 :=\n  (a + b)",
      "Test 4: expected per-parameter binders, got: " & lean

  # -- Test 5: Recursive func → termination analysis -----------------------
  block:
    ## Recursive function with numeric decrement (n - 1)
    let body = irIf(
      irBinOp(boEq, irVar("n", irTypeBitVec64()), irLit(0)),
      irLit(0),
      irBinOp(boAdd,
        irVar("n", irTypeBitVec64()),
        irRecCall(@[irBinOp(boSub, irVar("n", irTypeBitVec64()), irLit(1))]))
    )
    let f = irFuncDef("sum",
                      @[("n", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let lean = emitRecDef(f)
    doAssert lean.startsWith("def sum "),
      "Test 5: expected 'def sum', got: " & lean
    doAssert "termination_by n" in lean,
      "Test 5: expected 'termination_by n', got: " & lean
    doAssert "decreasing_by omega" in lean,
      "Test 5: expected 'decreasing_by omega', got: " & lean

  # -- Test 5b: Recursive func with list param → structural ----------------
  block:
    let body = irLit(0)
    let f = irFuncDef("len",
                      @[("xs", irTypeList(irTypeBitVec64()))],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let lean = emitRecDef(f)
    doAssert lean.startsWith("def len "),
      "Test 5b: expected 'def len', got: " & lean
    doAssert "partial" notin lean,
      "Test 5b: structural recursion must not be partial, got: " & lean

  # -- Test 5c: Recursive func with identity rec-call → fallback partial def -----
  block:
    ## Recursive function passing param unchanged (identity pattern).
    ## No numeric decrement and no structural recursion → tsFallback → partial def.
    let body = irIf(
      irBinOp(boEq, irVar("x", irTypeBitVec64()), irLit(0)),
      irLit(0),
      irRecCall(@[irVar("x", irTypeBitVec64())])
    )
    let f = irFuncDef("mystery",
                      @[("x", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let lean = emitRecDef(f)
    doAssert lean.startsWith("partial def mystery "),
      "Test 5c: expected 'partial def mystery', got: " & lean
    doAssert "partial" in lean,
      "Test 5c: fallback rec-call must be partial, got: " & lean
    doAssert "termination_by" in lean,
      "Test 5c: expected termination_by, got: " & lean

# -- Test 6: Full module output with imports -----------------------------
  block:
    let body = irAdd(irVar("a", irTypeBitVec64()),
                       irVar("b", irTypeBitVec64()))
    let f = irFuncDef("add",
                      @[("a", irTypeBitVec64()),
                        ("b", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = false)
    let lean = irToLeanModule(f, @["Axiom.IR.Basic"])
    doAssert lean.startsWith("import Init\n"),
      "Test 6: expected import Init, got: " & lean
    doAssert "import Axiom.IR.Basic\n" in lean,
      "Test 6: expected import for IR.Basic, got: " & lean
    doAssert "def add " in lean,
      "Test 6: expected 'def add', got: " & lean
    # Import hygiene: imports appear ONLY before the first def/theorem.
    let defPos = lean.find("def add ")
    doAssert defPos >= 0,
      "Test 6: expected def, got: " & lean
    doAssert lean.find("import ", defPos) < 0,
      "Test 6: duplicate import after first def: " & lean
    # Axioms query must be TARGETED at the def — never bare `#print axioms`.
    doAssert "#print axioms add\n" in lean,
      "Test 6: expected targeted print, got: " & lean

  # -- Test 6b: Module for recursive function ------------------------------
  block:
    let body = irIf(
      irBinOp(boEq, irVar("n", irTypeBitVec64()), irLit(0)),
      irLit(0),
      irRecCall(@[irBinOp(boSub, irVar("n", irTypeBitVec64()), irLit(1))])
    )
    let f = irFuncDef("countdown",
                      @[("n", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let lean = irToLeanModule(f)
    doAssert "import Init\n" in lean,
      "Test 6b: expected Init import, got: " & lean
    doAssert "def countdown " in lean,
      "Test 6b: expected 'def countdown', got: " & lean
    doAssert "termination_by n" in lean,
      "Test 6b: expected termination_by, got: " & lean
    # Import hygiene applies to recursive modules too.
    let defPos = lean.find("def countdown ")
    doAssert defPos >= 0,
      "Test 6b: expected def, got: " & lean
    doAssert lean.find("import ", defPos) < 0,
      "Test 6b: duplicate import after first def: " & lean
    doAssert "#print axioms countdown\n" in lean,
      "Test 6b: expected targeted print, got: " & lean

  # -- Test 7: Output metadata for fallback (identity rec-call) ---------
  block:
    let body = irIf(
      irBinOp(boEq, irVar("x", irTypeBitVec64()), irLit(0)),
      irLit(0),
      irRecCall(@[irVar("x", irTypeBitVec64())])
    )
    let f = irFuncDef("mystery",
                      @[("x", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let meta = leanOutputMetadata(f)
    doAssert "\"terminationStrategy\": \"tsFallback\"" in meta,
      "Test 7: expected tsFallback, got: " & meta
    doAssert "\"terminationUnchecked\": true" in meta,
      "Test 7: expected terminationUnchecked true, got: " & meta

  # -- Test 8: Output metadata for numeric descent -------------------------
  block:
    let body = irIf(
      irBinOp(boEq, irVar("n", irTypeBitVec64()), irLit(0)),
      irLit(0),
      irRecCall(@[irBinOp(boSub, irVar("n", irTypeBitVec64()), irLit(1))])
    )
    let f = irFuncDef("sum",
                      @[("n", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = true)
    let meta = leanOutputMetadata(f)
    doAssert "\"terminationStrategy\": \"tsNumeric\"" in meta,
      "Test 8: expected tsNumeric, got: " & meta
    doAssert "\"terminationUnchecked\": false" in meta,
      "Test 8: expected terminationUnchecked false, got: " & meta

  # -- Test 9: Non-recursive metadata -------------------------------------
  block:
    let body = irAdd(irVar("a", irTypeBitVec64()),
                     irVar("b", irTypeBitVec64()))
    let f = irFuncDef("add",
                      @[("a", irTypeBitVec64()),
                        ("b", irTypeBitVec64())],
                      irTypeBitVec64(),
                      body,
                      isRec = false)
    let meta = leanOutputMetadata(f)
    doAssert "\"terminationStrategy\": \"tsNone\"" in meta,
      "Test 9: expected tsNone, got: " & meta

  # -- Test 10: Sectioned LeanGoal renderer — obligation naming + import hygiene --
  block:
    let goal = makeLeanGoal(
      theoremName = "clamp",
      proposition = "result ≥ lo ∧ result ≤ hi",
      proofScript = "by\n  bv_decide",
      assumptions = @["lo : BitVec 64", "hi : BitVec 64", "result : BitVec 64"],
      requiredImports = @["Vec.Bar", "Aesop", "Foo.Bar", "Foo.Bar",
                          "Aesop", "Std.Tactic.BVDecide"],
      obligationId = "c4a0b1c2")
    let moduleCode = renderLeanModule(goal)
    doAssert moduleCode.startsWith("import Init\n"),
      "Test 10: expected import Init first, got: " & moduleCode
    doAssert moduleCode.count("import Std.Tactic.BVDecide\n") == 1,
      "Test 10: BVDecide must appear exactly once: " & moduleCode
    doAssert moduleCode.count("import Foo.Bar\n") == 1,
      "Test 10: duplicate import must be deduplicated: " & moduleCode
    let aPos = moduleCode.find("import Aesop\n")
    let fPos = moduleCode.find("import Foo.Bar\n")
    let vPos = moduleCode.find("import Vec.Bar\n")
    doAssert aPos >= 0 and fPos >= 0 and vPos >= 0,
      "Test 10: expected extras, got: " & moduleCode
    doAssert aPos < fPos and fPos < vPos,
      "Test 10: extras must be sorted, got: " & moduleCode
    doAssert "theorem obligation_c4a0b1c2" in moduleCode,
      "Test 10: expected obligation theorem name, got: " & moduleCode
    doAssert "#print axioms obligation_c4a0b1c2\n" in moduleCode,
      "Test 10: expected targeted print, got: " & moduleCode
    doAssert "namespace Axiom\n" in moduleCode and "end Axiom\n" in moduleCode,
      "Test 10: expected namespace open/close, got: " & moduleCode
    let theoremPos = moduleCode.find("theorem obligation_c4a0b1c2")
    doAssert theoremPos >= 0,
      "Test 10: expected theorem, got: " & moduleCode
    doAssert moduleCode.find("import ", theoremPos) < 0,
      "Test 10: import after first theorem in module: " & moduleCode

  # -- Test 11: Legacy goal naming when obligationId is empty --------------
  block:
    let legacy = makeLeanGoal(theoremName = "add_spec",
                              proposition = "r = r",
                              proofScript = "by\n  sorry")
    doAssert goalTheoremName(legacy) == "add_spec",
      "Test 11: legacy naming expected, got: " & goalTheoremName(legacy)
    doAssert renderTheorem(legacy) == "theorem add_spec : r = r :=\n",
      "Test 11: legacy theorem decl, got: " & renderTheorem(legacy)
    doAssert renderEnd(legacy) == "#print axioms add_spec\n",
      "Test 11: legacy targeted print, got: " & renderEnd(legacy)
    doAssert goalTheoremName(makeLeanGoal("g2", "True", obligationId = "id7")) ==
      "obligation_id7",
      "Test 11: obligation naming expected"

  result = newStmtList()
  result.add quote do:
    echo "  All assertions passed (compile-time)."

runTests()
echo "=== Phase 2E: IR → Lean 4 Conversion Tests ==="
echo "=== Done ==="
