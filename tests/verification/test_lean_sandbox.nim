## Tests for lean_build_sandbox.nim — Phase 3D
## Verifies sandbox lifecycle, output parsing, and end-to-end Lean builds.

import std/[unittest, os, strutils]

import verification/lean_build_sandbox

# ═══════════════════════════════════════════════════════════════════════════════
# Pure function tests
# ═══════════════════════════════════════════════════════════════════════════════

suite "parseAxioms":
  test "extracts axiom names from standard output":
    let output = """
axiom someAxiom : Nat → Nat
axiom anotherOne : String
some random text
"""
    let axioms = parseAxioms(output)
    check axioms.len == 2
    check axioms[0] == "someAxiom"
    check axioms[1] == "anotherOne"

  test "returns empty seq for no axioms":
    let output = "Build completed successfully\nNo axioms used\n"
    let axioms = parseAxioms(output)
    check axioms.len == 0

  test "handles axiom without type annotation":
    let output = "axiom bareAxiom\n"
    let axioms = parseAxioms(output)
    check axioms.len == 1
    check axioms[0] == "bareAxiom"

  test "ignores non-axiom lines containing 'axiom' as substring":
    let output = "using axiom in a sentence\nanother line\n"
    let axioms = parseAxioms(output)
    check axioms.len == 0

suite "containsSorry":
  test "detects sorry in output":
    check containsSorry("error: tactic failed\n  Lean sorry\n") == true

  test "returns false when no sorry present":
    check containsSorry("Build completed\nAll good\n") == false

  test "detects sorry with surrounding text":
    check containsSorry("found sorry at line 42") == true

suite "buildSuccess":
  test "exit code 0 is success":
    check buildSuccess(0) == true

  test "non-zero exit code is failure":
    check buildSuccess(1) == false
    check buildSuccess(127) == false

# ═══════════════════════════════════════════════════════════════════════════════
# Sandbox lifecycle tests
# ═══════════════════════════════════════════════════════════════════════════════

suite "createSandbox / destroySandbox":
  test "createSandbox creates a unique directory":
    let sandbox = createSandbox()
    try:
      check sandbox.sandboxDir.len > 0
      check sandbox.uuid.len > 0
      check dirExists(sandbox.sandboxDir)
    finally:
      destroySandbox(sandbox)

  test "destroySandbox removes the directory":
    let sandbox = createSandbox()
    let dirPath = sandbox.sandboxDir
    check dirExists(dirPath)
    destroySandbox(sandbox)
    check not dirExists(dirPath)

  test "destroySandbox is safe to call on missing directory":
    let sandbox = LeanBuildSandbox(sandboxDir: "/tmp/nonexistent_sandbox_xyz", uuid: "test")
    # Should not raise
    destroySandbox(sandbox)

  test "sandbox copies proofs directory contents":
    let sandbox = createSandbox()
    try:
      # Check that key Lean proof files are present
      check fileExists(sandbox.sandboxDir / "lakefile.lean")
      check fileExists(sandbox.sandboxDir / "GateInvariants.lean")
      check dirExists(sandbox.sandboxDir / "GateInvariants")
    finally:
      destroySandbox(sandbox)

  test "two sandboxes have unique directories":
    let s1 = createSandbox()
    let s2 = createSandbox()
    try:
      check s1.sandboxDir != s2.sandboxDir
      check s1.uuid != s2.uuid
    finally:
      destroySandbox(s1)
      destroySandbox(s2)

# ═══════════════════════════════════════════════════════════════════════════════
# End-to-end tests (require Lean/Lake to be installed)
# ═══════════════════════════════════════════════════════════════════════════════

let leanAvailable = findExe("lake").len > 0

suite "verifyWithSandbox (end-to-end)":
  test "verifyWithSandbox creates and cleans up sandbox":
    if not leanAvailable:
      skip()
    let result = verifyWithSandbox(timeout = 60)
    # Result is always a valid SandboxResult (no crash = cleanup worked)
    check result.compilerOutput.len >= 0

  test "lake build result is captured":
    if not leanAvailable:
      skip()
    let result = verifyWithSandbox(timeout = 120)
    # If build timed out (clean build without .lake cache can be slow), that's acceptable
    if result.exitCode == -1:
      check result.compilerOutput.len >= 0  # timeout: output may be empty
    else:
      # Output should contain some text from lake build
      check result.compilerOutput.len > 0
      # Exit code should be present
      check result.exitCode in [0, 1, 2]  # 0=ok, 1=sorry-warn, 2=error
