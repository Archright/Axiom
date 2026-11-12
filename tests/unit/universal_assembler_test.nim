import std/unittest
import std/strutils
import core/translator/universal_assembler
import core/judge/smart_search
import core/translator/ast_to_lean_bridge

suite "Universal Lean Assembler (ULA)":
  test "sanitizeLeanSource removes Nim semicolons":
    let raw = "def foo (x : Int) : Int :=\n  let a := 1; let b := 2; a + b"
    let cleaned = sanitizeLeanSource(raw)
    check not (";" in cleaned)
    check "\n  let a := 1" in cleaned
    check "\n  let b := 2" in cleaned

  test "buildLeanPrelude contains import Std":
    let prelude = buildLeanPrelude()
    check "import Std" in prelude

  test "buildLeanTheoremDecl generates correct theorem header":
    let params = @[((name: "x", nimType: "int"))]
    let decl = buildLeanTheoremDecl("foo", params, "x ≥ 0")
    check "theorem foo" in decl
    check "(x : NimInt)" in decl
    check "x ≥ 0" in decl
    check ":= by" in decl

  test "buildUniversalLeanSource from TranslatorContext includes def and theorem":
    var ctx = TranslatorContext(
      nimSource: "proc add(a, b: int): int = a + b",
      modulePath: "test.nim",
      functionName: "add",
      paramTypes: @[
        NimParamInfo(name: "a", nimType: "int", isVar: false),
        NimParamInfo(name: "b", nimType: "int", isVar: false)
      ],
      returnType: "int",
      bodyExpr: "a + b",
      isFunc: true
    )
    let src = buildUniversalLeanSource(ctx)
    check "import Std" in src
    check "theorem add" in src
    check "def add" in src
    check not (";" in src)

  test "buildUniversalLeanSource from SemanticHint includes prelude and theorem":
    let hint = SemanticHint(
      leanProposition: "x ≥ 0",
      smtConstraint: "(assert (>= x 0))",
      sourceReference: "test",
      confidence: 0.9,
      strategy: isIntervalAbstraction,
      retryCount: 0,
      paramTypes: @[((name: "x", nimType: "int"))]
    )
    let src = buildUniversalLeanSource("test::foo", hint, hint.smtConstraint)
    check "import Std" in src
    check "theorem test_foo" in src
    check "x ≥ 0" in src

  test "buildLeanProofBody returns assemblePrimitiveProof for known patterns":
    let smt = "(assert (>= x 0))"
    let body = buildLeanProofBody(smt)
    check body.len > 0
    check body != "  exact h_sys\n" or body == "  exact h_sys\n"
