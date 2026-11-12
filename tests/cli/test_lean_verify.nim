{.push raises: [].}

## Unit tests for Lean build sandbox verification — Phase 3B.
## Tests pure helper functions and SandboxResult structure validation.
## No I/O required — all tests use mock/constructed data.

import std/json
import std/unittest
import std/strutils

import verification/lean_build_sandbox
import cli/lean_verify_cmd

# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: SandboxResult structure has expected fields
# ═══════════════════════════════════════════════════════════════════════════════

suite "SandboxResult — structure validation":
  test "default SandboxResult has all expected fields":
    let sr = SandboxResult()
    check sr.success == false
    check sr.compilerOutput.len == 0
    check sr.axiomsUsed.len == 0
    check sr.sorryFound == false
    check sr.exitCode == 0

  test "SandboxResult success=true with axioms":
    let sr = SandboxResult(
      success: true,
      compilerOutput: "Build succeeded",
      axiomsUsed: @["prop1", "prop2"],
      sorryFound: false,
      exitCode: 0
    )
    check sr.success == true
    check sr.compilerOutput == "Build succeeded"
    check sr.axiomsUsed.len == 2
    check sr.axiomsUsed[0] == "prop1"
    check sr.axiomsUsed[1] == "prop2"
    check sr.sorryFound == false
    check sr.exitCode == 0

  test "SandboxResult with sorry detected":
    let sr = SandboxResult(
      success: true,
      compilerOutput: "warning: declaration uses 'sorry'",
      axiomsUsed: @[],
      sorryFound: true,
      exitCode: 0
    )
    check sr.sorryFound == true
    check sr.success == true  # lake build succeeded but sorry found

  test "SandboxResult build failure":
    let sr = SandboxResult(
      success: false,
      compilerOutput: "error: type mismatch",
      axiomsUsed: @[],
      sorryFound: false,
      exitCode: 1
    )
    check sr.success == false
    check sr.exitCode == 1

# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: Pure helper functions
# ═══════════════════════════════════════════════════════════════════════════════

suite "parseAxioms — axiom extraction":
  test "empty output returns empty seq":
    check parseAxioms("").len == 0

  test "parses single axiom with type":
    let output = "axiom prop1 : Nat → Prop"
    let axioms = parseAxioms(output)
    check axioms.len == 1
    check axioms[0] == "prop1"

  test "parses multiple axioms":
    let output = "axiom p1 : Bool\naxiom p2 : Nat\naxiom p3 : Prop"
    let axioms = parseAxioms(output)
    check axioms.len == 3
    check axioms[0] == "p1"
    check axioms[1] == "p2"
    check axioms[2] == "p3"

  test "ignores non-axiom lines":
    let output = "import Init\naxiom foo : Bool\n#check bar\naxiom baz : Nat"
    let axioms = parseAxioms(output)
    check axioms.len == 2
    check axioms[0] == "foo"
    check axioms[1] == "baz"

  test "handles axiom without type annotation":
    let output = "axiom myAxiom :"
    let axioms = parseAxioms(output)
    check axioms.len == 1

suite "containsSorry — sorry detection":
  test "empty output has no sorry":
    check containsSorry("") == false

  test "detects sorry in output":
    check containsSorry("warning: uses 'sorry'") == true

  test "no sorry in clean output":
    check containsSorry("Build succeeded\nNo warnings") == false

  test "detects sorry across multiple lines":
    let output = "line 1 ok\nline 2 uses sorry\nline 3 ok"
    check containsSorry(output) == true

suite "buildSuccess — exit code check":
  test "exit code 0 is success":
    check buildSuccess(0) == true

  test "exit code 1 is failure":
    check buildSuccess(1) == false

  test "negative exit code is failure":
    check buildSuccess(-1) == false

# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: LeanVerifyResult and classifyOutcome
# ═══════════════════════════════════════════════════════════════════════════════

suite "classifyOutcome — exhaustive outcome classification":
  test "sandbox failure (exitCode=-1) maps to SandboxFailed":
    let sr = SandboxResult(success: false, exitCode: -1)
    check classifyOutcome(sr) == leanVerifySandboxFailed

  test "sorry found maps to SorryFound":
    let sr = SandboxResult(success: true, sorryFound: true, exitCode: 0)
    check classifyOutcome(sr) == leanVerifySorryFound

  test "build failure (exitCode=1) maps to BuildFailed":
    let sr = SandboxResult(success: false, sorryFound: false, exitCode: 1)
    check classifyOutcome(sr) == leanVerifyBuildFailed

  test "clean success maps to Success":
    let sr = SandboxResult(success: true, sorryFound: false, exitCode: 0)
    check classifyOutcome(sr) == leanVerifySuccess

suite "LeanVerifyResult — structure validation":
  test "default LeanVerifyResult fields":
    let lr = LeanVerifyResult()
    check lr.success == false
    check lr.sorryFound == false
    check lr.axiomsUsed.len == 0
    check lr.exitCode == 0
    check lr.outputJson.len == 0
    check lr.logLines.len == 0

suite "buildVerificationJson — JSON serialization":
  test "successful result serializes correctly":
    let lr = LeanVerifyResult(
      success: true,
      sorryFound: false,
      axiomsUsed: @["p1", "p2"],
      exitCode: 0
    )
    let jsonStr = buildVerificationJson(lr)
    let node = parseJson(jsonStr)
    check node["gate"].getStr() == "lean-verify"
    check node["success"].getBool() == true
    check node["sorryFound"].getBool() == false
    check node["exitCode"].getInt() == 0
    check node["axiomsUsed"].len == 2

  test "sorry-found result serializes correctly":
    let lr = LeanVerifyResult(
      success: false,
      sorryFound: true,
      axiomsUsed: @[],
      exitCode: 0
    )
    let jsonStr = buildVerificationJson(lr)
    let node = parseJson(jsonStr)
    check node["sorryFound"].getBool() == true
    check node["axiomsUsed"].len == 0

suite "buildLogLines — human-readable output":
  test "success produces pass message":
    let sr = SandboxResult(success: true, sorryFound: false, exitCode: 0)
    let lines = buildLogLines(sr)
    check lines.len >= 1
    check lines[0].contains("PASS")

  test "sorry found produces fail message with diagnostics":
    let sr = SandboxResult(
      success: true,
      compilerOutput: "line 1: error: uses sorry",
      sorryFound: true,
      exitCode: 0
    )
    let lines = buildLogLines(sr)
    check lines.len >= 1
    check lines[0].contains("FAIL")
    check lines[0].contains("sorry")

  test "build failure produces exit code message":
    let sr = SandboxResult(
      success: false,
      compilerOutput: "error: type mismatch",
      exitCode: 1
    )
    let lines = buildLogLines(sr)
    check lines.len >= 1
    check lines[0].contains("FAIL")
    check lines[0].contains("1")

  test "sandbox failure produces error message":
    let sr = SandboxResult(
      success: false,
      compilerOutput: "sandbox creation error",
      exitCode: -1
    )
    let lines = buildLogLines(sr)
    check lines.len >= 1
    check lines[0].contains("FAIL")
    check lines[0].contains("sandbox")

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: LeanBuildSandbox handle structure
# ═══════════════════════════════════════════════════════════════════════════════

suite "LeanBuildSandbox — handle structure":
  test "default sandbox has empty fields":
    let sb = LeanBuildSandbox()
    check sb.sandboxDir.len == 0
    check sb.uuid.len == 0

  test "sandbox with populated fields":
    let sb = LeanBuildSandbox(
      sandboxDir: "/tmp/lean_sandbox_test",
      uuid: "test-uuid-123"
    )
    check sb.sandboxDir == "/tmp/lean_sandbox_test"
    check sb.uuid == "test-uuid-123"

{.pop.}
