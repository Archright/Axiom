import std/unittest
import std/strutils
import core/translator/universal_assembler
import core/judge/smart_search

suite "ULA Tautology Bridge":
  test "sanitizeLeanSource strips Nim type annotations":
    let input = "let x : int = 42\nlet y : string = \"hello\""
    let output = sanitizeLeanSource(input)
    check " : int " notin output
    check "x :=" in output
    check "y :=" in output

  test "sanitizeLeanSource strips NimInt annotation":
    let input = "let z : NimInt = 0"
    let output = sanitizeLeanSource(input)
    check " : NimInt " notin output
    check "z :=" in output

  test "sanitizeLeanSource preserves := assignment":
    let input = "let valid := 42"
    let output = sanitizeLeanSource(input)
    check "valid :=" in output

  test "sanitizeLeanSource strips Nim semicolons":
    let input = "let a := 1; let b := 2"
    let output = sanitizeLeanSource(input)
    check ";" notin output

  test "buildLeanProofBody returns simpa for tautology hint":
    var hint = SemanticHint(
      strategy: isTautologyProof,
      leanProposition: "depth >= 0",
      smtConstraint: "(assert (>= depth 0))"
    )
    let body = buildLeanProofBody("", hint)
    check "simpa" in body
