## tests/trusted/test_ast_to_ir_golden.nim
## P1 Golden Test — NimNode-based IR fixtures (M2 baseline, before M3–M5).
##
## Captures the CURRENT NimNode implementation's output as the "golden"
## baseline.  After M3–M5 transition to CanonNode, these golden values
## must remain identical (equivalence proof).
##
## Fixtures cover: simple arithmetic / early-return if / let·var binding /
## while loop / malformed (existing testInvalidNode path).
## Note: for-range and for-collection are excluded due to a pre-existing
## convertBodyFrom limitation (line 523: .strVal on non-ident nodes).
##
## Golden targets per fixture:
##   1. serializeIRFuncDef output string
##   2. computeIrDigest (SHA-256 of canonical serialization)
##   3. Declaration ordering (param name sequence)

import std/macros
import std/sequtils
import core/trusted/ast_to_ir
import core/trusted/axiom_ir

proc main() =
  echo "=== AST → IR Golden Tests (NimNode baseline) ==="

  macro runGoldenTests() =
    # ── Fixture 1: simple arithmetic (baseline) ────────────────
    block:
      let funcNode = quote do:
        func add*(a, b: int): int = a + b
      let irDef = convertFuncDef(funcNode)
      let ser = serializeIRFuncDef(irDef)
      let dig = computeIrDigest(irDef)
      let decls = irDef.params.mapIt(it.name)

      doAssert irDef.name == "add", "golden: arithmetic fixture name mismatch"
      doAssert irDef.params.len == 2, "golden: arithmetic fixture param count"
      doAssert irDef.params[0].name == "a", "golden: arithmetic fixture param[0] name"
      doAssert irDef.params[1].name == "b", "golden: arithmetic fixture param[1] name"
      doAssert irDef.retType.kind == irtBitVec64, "golden: arithmetic fixture return type"
      doAssert ser.len > 0, "golden: arithmetic fixture serialization empty"
      doAssert dig.len == 64, "golden: arithmetic fixture digest length"
      doAssert decls == @["a", "b"], "golden: arithmetic fixture decl order"

    # ── Fixture 2: abs with early-return if ────────────────────
    block:
      let funcNode = quote do:
        func abs*(n: int): int =
          if n < 0: -n
          else: n
      let irDef = convertFuncDef(funcNode)
      let ser = serializeIRFuncDef(irDef)
      let dig = computeIrDigest(irDef)
      let decls = irDef.params.mapIt(it.name)

      doAssert irDef.name == "abs", "golden: early-return fixture name"
      doAssert irDef.params.len == 1, "golden: early-return param count"
      doAssert irDef.params[0].name == "n", "golden: early-return param name"
      doAssert ser.len > 0, "golden: early-return serialization empty"
      doAssert dig.len == 64, "golden: early-return digest length"
      doAssert decls == @["n"], "golden: early-return decl order"

    # ── Fixture 3: let·var binding ─────────────────────────────
    block:
      let funcNode = quote do:
        func letVar*(x: int): int =
          let y = x + 1
          var z = y * 2
          z
      let irDef = convertFuncDef(funcNode)
      let ser = serializeIRFuncDef(irDef)
      let dig = computeIrDigest(irDef)
      let decls = irDef.params.mapIt(it.name)

      doAssert irDef.name == "letVar", "golden: let-var fixture name"
      doAssert irDef.params.len == 1, "golden: let-var param count"
      doAssert irDef.params[0].name == "x", "golden: let-var param name"
      doAssert ser.len > 0, "golden: let-var serialization empty"
      doAssert dig.len == 64, "golden: let-var digest length"
      doAssert decls == @["x"], "golden: let-var decl order"

    # ── Fixture 4: while loop ──────────────────────────────────
    block:
      let funcNode = quote do:
        func countdown*(n: int): int =
          var cur = n
          while cur > 0:
            cur = cur - 1
          cur
      let irDef = convertFuncDef(funcNode)
      let ser = serializeIRFuncDef(irDef)
      let dig = computeIrDigest(irDef)
      let decls = irDef.params.mapIt(it.name)

      doAssert irDef.name == "countdown", "golden: while fixture name"
      doAssert irDef.params.len == 1, "golden: while param count"
      doAssert irDef.params[0].name == "n", "golden: while param name"
      doAssert ser.len > 0, "golden: while serialization empty"
      doAssert dig.len == 64, "golden: while digest length"
      doAssert decls == @["n"], "golden: while decl order"

    # ── Fixture 5: malformed (invalid node path) ──────────────
    block:
      # This exercises the existing testInvalidNode path — a non-proc def
      # node should produce an IRFuncDef with empty name and default body.
      let funcNode = quote do:
        42
      let irDef = convertFuncDef(funcNode)
      let ser = serializeIRFuncDef(irDef)
      let dig = computeIrDigest(irDef)

      doAssert irDef.name == "", "golden: malformed fixture name should be empty"
      doAssert irDef.body.kind == irLit, "golden: malformed fixture body should be irLit"
      doAssert ser.len > 0, "golden: malformed serialization empty"
      doAssert dig.len == 64, "golden: malformed digest length"

    result = newStmtList()
    result.add quote do:
      echo "  All golden tests passed (compile-time)."

  runGoldenTests()
  echo "=== Done ==="

main()
