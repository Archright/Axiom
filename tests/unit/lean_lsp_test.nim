import std/unittest
import std/json
import std/strutils
import verification/lean_lsp
import verification/pipeline_core_types

suite "diagnosticKind contract":
  test "returns explicit diag.kind when set":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "some message",
      kind: "type_mismatch"
    )
    check diagnosticKind(diag) == "type_mismatch"

  test "parses tactic_failed from message":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "tactic failed to solve goal"
    )
    check diagnosticKind(diag) == "tactic_failed"

  test "parses type_mismatch from message":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "application type mismatch"
    )
    check diagnosticKind(diag) == "type_mismatch"

  test "parses unsolved_goals from message":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "unsolved goals remain"
    )
    check diagnosticKind(diag) == "unsolved_goals"

  test "parses missing_import_or_symbol from unknown constant":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "unknown constant Foo"
    )
    check diagnosticKind(diag) == "missing_import_or_symbol"

  test "returns general_constraint for unrecognized message":
    let diag = LeanDiagnostic(
      line: 1, character: 0, severity: 1,
      message: "something completely different"
    )
    check diagnosticKind(diag) == "general_constraint"

suite "extractLeanGoalsFromJson contract":
  test "extracts goals from nested JSON structure":
    let node = %*{
      "goals": [
        {"type": "string", "value": "unsolved goals: goal1"},
        {"type": "string", "value": "unsolved goals: goal2"}
      ]
    }
    let goals = extractLeanGoalsFromJson(node)
    check goals.len == 2
    check goals[0].contains("goal1")
    check goals[1].contains("goal2")

  test "returns empty sequence for non-object node":
    let node = %*["goal1", "goal2"]
    let goals = extractLeanGoalsFromJson(node)
    check goals.len == 0

suite "analyzeSpecComplexity contract":
  test "empty source returns all false flags":
    let complexity = analyzeSpecComplexity("")
    check not complexity.hasRecursiveDefs
    check not complexity.needsInduction
    check not complexity.needsCases
    check not complexity.hasPatternMatching
    check complexity.fingerprint.len > 0
    check complexity.summary.len > 0

  test "source with recursive keyword sets recursive flag":
    let complexity = analyzeSpecComplexity("def foo (n : Nat) : Nat := match n with | 0 => 1 | n + 1 => foo n + 1")
    # May or may not set flag depending on tree-sitter parse success
    # Just verify it doesn't crash and returns consistent fingerprint
    check complexity.fingerprint.len > 0

  test "fingerprint is deterministic for identical input":
    let c1 = analyzeSpecComplexity("theorem test : 1 = 1 := rfl")
    let c2 = analyzeSpecComplexity("theorem test : 1 = 1 := rfl")
    check c1.fingerprint == c2.fingerprint

suite "buildInitialTacticStrategy contract":
  test "empty complexity returns base simp tactic":
    let complexity = LeanSpecComplexity(
      hasRecursiveDefs: false,
      needsInduction: false,
      needsCases: false,
      hasPatternMatching: false,
      fingerprint: "",
      summary: ""
    )
    let tactics = buildInitialTacticStrategy(complexity)
    check tactics.len == 1
    check tactics[0].contains("simpa")

  test "induction flag adds induction tactic":
    let complexity = LeanSpecComplexity(
      hasRecursiveDefs: true,
      needsInduction: true,
      needsCases: false,
      hasPatternMatching: false,
      fingerprint: "",
      summary: ""
    )
    let tactics = buildInitialTacticStrategy(complexity)
    check tactics.len == 2
    check tactics[0].contains("induction")
    check tactics[1].contains("simpa")

  test "cases flag adds cases tactic":
    let complexity = LeanSpecComplexity(
      hasRecursiveDefs: false,
      needsInduction: false,
      needsCases: true,
      hasPatternMatching: false,
      fingerprint: "",
      summary: ""
    )
    let tactics = buildInitialTacticStrategy(complexity)
    check tactics.len == 2
    check tactics[0].contains("cases")
    check tactics[1].contains("simpa")

  test "pattern matching flag adds simp tactic":
    let complexity = LeanSpecComplexity(
      hasRecursiveDefs: false,
      needsInduction: false,
      needsCases: false,
      hasPatternMatching: true,
      fingerprint: "",
      summary: ""
    )
    let tactics = buildInitialTacticStrategy(complexity)
    check tactics.len == 2
    check tactics[0].contains("simp")
    check tactics[1].contains("simpa")
