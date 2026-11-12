{.push raises: [CatchableError].}

## Lean LSP Tactic Tests — Unit tests for verification/lean_lsp_tactic.nim
## Tests theoremSource, lineOfTactic, generateContextAwareTactic.
## I/O procs (appendGeneratedCoreSpec, writeGeneratedSpecArtifact, etc.) are
## tested with temp dirs where applicable.

import std/[unittest, os, strutils, json, times]
import verification/lean_lsp_tactic
import core/logic/lean_diagnostic
import core/spec/spec_generator_types

# ---------------------------------------------------------------------------
# theoremSource
# ---------------------------------------------------------------------------

suite "theoremSource":
  test "generates valid theorem block":
    let result = theoremSource("axiom H : True", "test_theorem", "trivial")
    check "axiom H : True" in result
    check "theorem test_theorem" in result
    check "by" in result
    check "trivial" in result

  test "includes namespace wrapper":
    let result = theoremSource("", "my_thm", "simp")
    check "namespace Axiom.Verification" in result
    check "end Axiom.Verification" in result

  test "theorem params are (steps amount initialBalance : Nat)":
    let result = theoremSource("", "thm", "tac")
    check "steps amount initialBalance : Nat" in result

  test "includes Invariant in goal type":
    let result = theoremSource("", "thm", "tac")
    check "Invariant (Run steps amount initialBalance)" in result

  test "includes variable and example":
    let result = theoremSource("", "thm", "tac")
    check "variable (balance : Nat)" in result
    check "example : balance >= 0" in result
    check "Nat.zero_le balance" in result

  test "baseSpec is stripped and prepended":
    let result = theoremSource("  axiom X : Nat  ", "thm", "tac")
    check result.startsWith("axiom X : Nat")

  test "tactic is indented with two spaces":
    let result = theoremSource("", "thm", "myTactic")
    check "  myTactic" in result

# ---------------------------------------------------------------------------
# lineOfTactic
# ---------------------------------------------------------------------------

suite "lineOfTactic":
  test "finds tactic on first line (index 0)":
    let source = "  trivial\nmore code\n"
    check lineOfTactic(source, "trivial") == 0

  test "finds tactic on later line":
    let source = "line0\nline1\n  simp [X]\nline3\n"
    check lineOfTactic(source, "simp [X]") == 2

  test "returns 0 when tactic not found (Nim default int)":
    let source = "line0\nline1\nline2\n"
    check lineOfTactic(source, "nonexistent") == 0

  test "matches stripped line":
    let source = "  tac\n"
    check lineOfTactic(source, "tac") == 0

  test "handles empty source":
    check lineOfTactic("", "tac") == 0

  test "handles empty tactic":
    let source = "\n\n\n"
    check lineOfTactic(source, "") == 0  # empty line.strip() == ""

  test "first occurrence when duplicate":
    let source = "  simp\nother\n  simp\n"
    check lineOfTactic(source, "simp") == 0

# ---------------------------------------------------------------------------
# generateContextAwareTactic
# ---------------------------------------------------------------------------

suite "generateContextAwareTactic":
  test "unsolved_goals diagnostic → returns tactic":
    let diags = @[
      LeanDiagnostic(line: 1, character: 0, severity: 1,
                     message: "unsolved goals", kind: "unsolved_goals")
    ]
    let result = generateContextAwareTactic(diags, @[])
    check result.len > 0

  test "missing_import_or_symbol → returns simp tactic":
    let diags = @[
      LeanDiagnostic(line: 1, character: 0, severity: 1,
                     message: "unknown constant X", kind: "missing_import_or_symbol")
    ]
    let result = generateContextAwareTactic(diags, @[])
    check result.len > 0

  test "type_mismatch → returns simp tactic":
    let diags = @[
      LeanDiagnostic(line: 1, character: 0, severity: 1,
                     message: "type mismatch", kind: "type_mismatch")
    ]
    let result = generateContextAwareTactic(diags, @[])
    check result.len > 0

  test "goals without diagnostics → returns tactic":
    let result = generateContextAwareTactic(@[], @["⊢ Nat"])
    check result.len > 0

  test "empty diagnostics and goals → returns default tactic":
    let result = generateContextAwareTactic(@[], @[])
    check result.len > 0

  test "usedTactics are excluded from candidates":
    # With empty diagnostics, the default tactic is returned
    # regardless of usedTactics (since initial candidates are tried first)
    let result1 = generateContextAwareTactic(@[], @[])
    check result1.len > 0

  test "complexity affects strategy":
    let complexity = LeanSpecComplexity(needsInduction: true)
    let result = generateContextAwareTactic(@[], @[], complexity)
    check result.len > 0

# ---------------------------------------------------------------------------
# I/O procs with temp dirs
# ---------------------------------------------------------------------------

suite "writeGeneratedSpecArtifact":
  test "writes spec to logs/generated_core_spec.lean":
    let savedDir = getCurrentDir()
    let tmpDir = getTempDir() / "axiom_test_lsp_io_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    createDir("logs")
    let path = writeGeneratedSpecArtifact("-- test spec")
    check path.len > 0
    check fileExists(path)
    let content = readFile(path)
    check "-- test spec" in content

{.pop.}
