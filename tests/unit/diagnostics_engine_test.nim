import std/unittest
import std/strutils
import core/diagnostics/diagnostics_engine
import core/sorter/sorter_core

suite "analyzeLogicalComplexity contract":
  test "analyzes empty SMT-LIB2":
    let profile = analyzeLogicalComplexity("")
    check profile.nonLinearArithmeticCount == 0

  test "detects non-linear arithmetic":
    let profile = analyzeLogicalComplexity("(* x y)")
    check profile.nonLinearArithmeticCount > 0

suite "emptyTimeoutDiagnosis contract":
  test "returns empty diagnosis":
    let diag = emptyTimeoutDiagnosis()
    check not hasTimeoutDiagnosis(diag)

suite "hasTimeoutDiagnosis contract":
  test "returns true for diagnosis with complexity":
    let diag = buildTimeoutDiagnosis(
      sorterNodeId("test"),
      "proc foo = echo 1",
      "",
      0, 1, 1000
    )
    check hasTimeoutDiagnosis(diag)

  test "returns false for empty diagnosis":
    let diag = emptyTimeoutDiagnosis()
    check not hasTimeoutDiagnosis(diag)

suite "generateSelfHealingDirective contract":
  test "generates directive from diagnosis":
    let diag = buildTimeoutDiagnosis(
      sorterNodeId("test"),
      "while true: echo 1",
      "(* x y)",
      1, 2, 5000
    )
    let directive = generateSelfHealingDirective(diag)
    check directive.refactoringGuidance.len > 0
