import std/[unittest, os]
import src/verification/lean_repl_bridge

suite "VC Pipeline Unit Tests":
  test "checkLeanOutput returns false for sorry output":
    check checkLeanOutput("warning: declaration uses 'sorry'") == false

  test "checkLeanOutput returns false for error output":
    check checkLeanOutput("error: type mismatch") == false

  test "checkLeanOutput returns true for clean output":
    check checkLeanOutput("No goals") == true

  test "checkLeanOutput is case-insensitive":
    check checkLeanOutput("SORRY found") == false
    check checkLeanOutput("ERROR: type mismatch") == false

  test "checkLeanOutput returns true for empty output":
    check checkLeanOutput("") == true

  test "checkLeanOutput returns false when sorry is embedded":
    check checkLeanOutput("tactic failed, uses sorry") == false

suite "VC Pipeline E2E Integration Test":
  test "my_concat_assoc 2-round deterministic convergence":
    let fixturePath = "tests/fixtures/test_custom_reverse_sorry.lean"
    let tempPath = "tests/fixtures/temp_vc_test.lean"

    copyFile(fixturePath, tempPath)
    defer: removeFile(tempPath)

    let r1 = runLeanKernel(tempPath)
    check r1.status == psUnsolvedGoals

    let inductionTactic = """
by
  induction xs with
  | nil => rfl
  | cons h t ih => simp [my_concat, ih]
"""
    let r1Code = readFile(tempPath)
    let r2Code = injectTactic(r1Code, inductionTactic)
    writeFile(tempPath, r2Code)

    let r2 = runLeanKernel(tempPath)
    check r2.status == psVerified
