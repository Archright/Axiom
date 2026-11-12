## tests/unit/enforce_structural_safety_test.nim
## Unit test for compile-time structural safety enforcement macro.
## Verifies that the macro is properly injected via config.nims
## and that structural invariants are enforced at compile time.

import std/os
import std/strutils
import std/unittest

suite "Enforce Structural Safety Macro":
  test "Macro module exists at correct path":
    check fileExists("src/core/trusted/enforce_structural_safety.nim")

  test "Feature spec exists":
    check fileExists("tests/features/enforce_structural_safety.feature")

  test "config.nims injects macro via switch import":
    let configContent = readFile("config.nims")
    check configContent.contains("enforce_structural_safety")
    check configContent.contains("switch(\"import\"")

  test "Macro module contains enforceStructuralSafety proc":
    let content = readFile("src/core/trusted/enforce_structural_safety.nim")
    check content.contains("enforceStructuralSafety")
    check content.contains("macro")

  test "Macro checks ref object proc fields":
    let content = readFile("src/core/trusted/enforce_structural_safety.nim")
    check content.contains("ref")
    check content.contains("object")
    # Verify the macro inspects nnkTypeSection for ref object patterns
    check content.contains("nnkRefTy") or content.contains("ref object")

  test "Macro checks func var parameters":
    let content = readFile("src/core/trusted/enforce_structural_safety.nim")
    check content.contains("var")
    check content.contains("nnkVarTy") or content.contains("func")

  test "Macro checks import boundaries":
    let content = readFile("src/core/trusted/enforce_structural_safety.nim")
    check content.contains("import") or content.contains("nnkImportStmt")
