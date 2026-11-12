## tests/integration/test_vc_complete_integration.nim
## VC Pipeline E2E Integration Test — spawns Lean kernel.
## Guarded by axiomIntegration / leanIntegration defines.

when defined(axiomIntegration) or defined(leanIntegration):

  import std/[unittest, os]
  import src/verification/lean_repl_bridge

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
