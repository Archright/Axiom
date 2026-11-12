## Tests for vacuityProven derivation in lean_lsp_compiler.nim
##
## Per §0.7: only business scenarios, NOT compiler-guaranteed behaviors.

import std/unittest
import core/types/lean_lsp_types
import verification/lean_lsp_compiler

suite "negativeMutationPassed — vacuityProven evidence chain":

  test "verified + negative test FAILED → vacuityProven = true":
    let result = LeanCompilerResult(
      verified: true,
      negativeTestVerified: false,  # negative test failed (DESIRED: proof is non-vacuous)
      exitCode: 0,
      diagnostics: @[],
      output: "",
      artifactPath: "",
      vacuityProven: false
    )
    check negativeMutationPassed(result) == true

  test "verified + no negative test run → vacuityProven = false":
    let result = LeanCompilerResult(
      verified: true,
      negativeTestVerified: true,  # no mutation test or test passed (vacuous)
      exitCode: 0,
      diagnostics: @[],
      output: "",
      artifactPath: "",
      vacuityProven: false
    )
    check negativeMutationPassed(result) == false

  test "not verified → vacuityProven = false (regardless of mutation)":
    let result = LeanCompilerResult(
      verified: false,
      negativeTestVerified: true,
      exitCode: -1,
      diagnostics: @[],
      output: "",
      artifactPath: "",
      vacuityProven: false
    )
    check negativeMutationPassed(result) == false

  test "substring-only presence does NOT set vacuityProven":
    # Source contains "ax_vacuity_check" but negative mutation test passed (vacuous)
    let result = LeanCompilerResult(
      verified: true,
      negativeTestVerified: true,  # mutation test passed → vacuous
      exitCode: 0,
      diagnostics: @[],
      output: "",
      artifactPath: "",
      vacuityProven: false
    )
    check negativeMutationPassed(result) == false

suite "buildNegativeTestSource — conclusion anchor (`:= by` / `:=\\nby`)":
  ## The renderer (irFuncDefToTheorem) emits `:=\nby`; the mutation anchor
  ## must accept both emission shapes or the non-vacuity check reports a
  ## false VACUOUS (unbuildable mutation).

  test "single-line anchor mutates conclusion to False":
    check buildNegativeTestSource("theorem t : 42 = 42 := by\n  rfl\n") ==
      "theorem t : False := by\n  rfl\n"

  test "newline anchor (irFuncDefToTheorem emission shape) mutates conclusion to False":
    check buildNegativeTestSource(
      "theorem t :\n  (let result := f x;\n    42 = 42) :=\nby\n  unfold f\n  bv_decide\n"
    ) == "theorem t : False :=\nby\n  unfold f\n  bv_decide\n"

  test "indented by after a newline is also anchored":
    check buildNegativeTestSource("theorem t : 42 = 42 :=\n  by\n  rfl\n") ==
      "theorem t : False :=\n  by\n  rfl\n"

  test "`by` as identifier prefix does not anchor":
    check buildNegativeTestSource("theorem t : 42 = 42 := bytes\n") == ""

  test "no tactic conclusion returns empty":
    check buildNegativeTestSource("theorem t : 42 = 42\n") == ""
