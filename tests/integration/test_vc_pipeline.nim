## tests/integration/test_vc_pipeline.nim
## VC Pipeline Integration Tests
## Tests the complete verification condition pipeline with Lean 4 kernel,
## tactic injection, and goal extraction using std/tempfiles sandboxing.
##
## All tests that require Lean 4 are guarded by findExe("lean") and skip
## gracefully when Lean is unavailable.

when defined(axiomIntegration) or defined(leanIntegration):

  import std/[unittest, tempfiles, os, strutils, options]
  import ../../src/verification/lean_repl_bridge
  import ../../src/personas/legislator

  proc setupTest(): bool =
    findExe("lean") != ""

  proc createTempLeanFile(content: string): string =
    let (tmpFile, tmpPath) = createTempFile("vc_test_", ".lean")
    tmpFile.write(content)
    tmpFile.close()
    tmpPath

  proc cleanupTempFile(path: string) =
    removeFile(path)

  suite "Phase 4 VC Pipeline Integration Tests":
    test "Setup: Lean 4 availability":
      check setupTest() == true

    test "Scenario 4: buildTacticPrompt includes theorem and goal":
      let prompt = buildTacticPrompt(
        "theorem add_comm_int (a b : Int) : a + b = b + a := by",
        "a + b = b + a")
      check "add_comm_int" in prompt
      check "a + b = b + a" in prompt
      check "by" in prompt

    test "Scenario 5: buildTacticPrompt with last error":
      let prompt = buildTacticPrompt(
        "theorem foo : True := by",
        "True",
        some("simp didn't close the goal"))
      check "Previous attempt failed" in prompt
      check "simp didn't close the goal" in prompt

    test "Scenario 6: extractGoal finds unsolved goals in Lean output":
      let sampleOutput = "unsolved goals\n⊢ a + b = b + a"
      let goal = extractGoal(sampleOutput)
      check goal.isSome()
      check goal.get() == "⊢ a + b = b + a"

    test "Scenario 7: extractGoal with tactic failed message":
      let sampleOutput = "tactic failed, there are unsolved goals\n⊢ a + b = b + a"
      let goal = extractGoal(sampleOutput)
      check goal.isSome()
      check goal.get() == "⊢ a + b = b + a"

    test "Scenario 8: extractGoal returns none for verified output":
      let verifiedOutput = "No goals"
      let goal = extractGoal(verifiedOutput)
      check goal.isNone()

    test "Scenario 9: extractGoal returns none for empty output":
      let goal = extractGoal("")
      check goal.isNone()

    test "Scenario 10g: runLeanKernel returns psUnsolvedGoals for sorry theorem":
      if not setupTest(): skip()

      let leanCode = "theorem oops : True := by sorry\n"
      let tmpPath = createTempLeanFile(leanCode)
      defer: cleanupTempFile(tmpPath)

      let res = runLeanKernel(tmpPath)
      check res.status == psUnsolvedGoals
      check res.rawOutput.len > 0

    test "Scenario 10: Syntax error with runLeanKernel":
      if not setupTest(): skip()

      let leanCode = "theorem bad_syntax :="
      let tmpPath = createTempLeanFile(leanCode)
      defer: cleanupTempFile(tmpPath)

      let res = runLeanKernel(tmpPath)
      check res.status == psSyntaxError
      check res.rawOutput.len > 0

    test "Scenario 11: runLeanKernel with verified theorem":
      if not setupTest(): skip()

      let leanCode = "def main : IO Unit := pure ()\n"
      let tmpPath = createTempLeanFile(leanCode)
      defer: cleanupTempFile(tmpPath)

      let res = runLeanKernel(tmpPath)
      check res.status == psVerified

    test "Scenario 12: runLeanKernel returns status for valid file":
      if not setupTest(): skip()

      let leanCode = "def main : IO Unit := pure ()\n"
      let tmpPath = createTempLeanFile(leanCode)
      defer: cleanupTempFile(tmpPath)

      let res = runLeanKernel(tmpPath, timeoutMs = 5000)
      check res.status == psVerified

    test "Scenario 13: Temp file sandboxing — create, verify, cleanup":
      if not setupTest(): skip()

      let leanCode = "def main : IO Unit := pure ()\n"
      let tmpPath = createTempLeanFile(leanCode)
      check fileExists(tmpPath)

      let res = runLeanKernel(tmpPath)
      check res.status == psVerified

      cleanupTempFile(tmpPath)
      check not fileExists(tmpPath)
