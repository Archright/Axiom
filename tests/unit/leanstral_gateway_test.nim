import std/unittest
import std/strutils
import verification/leanstral_gateway

suite "stripAnsiCodes contract":
  test "removes ANSI color codes":
    let raw = "\x1B[31mred\x1B[0m"
    check stripAnsiCodes(raw) == "red"

  test "preserves plain text":
    check stripAnsiCodes("hello") == "hello"

  test "handles empty string":
    check stripAnsiCodes("") == ""

suite "isAgentBehaviorDetected contract":
  test "detects bash command marker":
    check isAgentBehaviorDetected("$ ls -la")

  test "detects tool use marker":
    check isAgentBehaviorDetected("tool_use")

  test "returns false for clean code":
    check not isAgentBehaviorDetected("exact rfl")

suite "extractLeanBlock contract":
  test "extracts theorem block":
    let raw = "Some text\ntheorem test : 1 = 1 := rfl\nend test\nMore text"
    let codeBlock = extractLeanBlock(raw)
    check codeBlock.contains("theorem")

  test "returns empty when no Lean block":
    check extractLeanBlock("no code here") == ""

suite "validateLeanstralSourcePolicy contract":
  test "allows Std import":
    check validateLeanstralSourcePolicy("import Std") == ""

  test "flags non-Std import":
    let result = validateLeanstralSourcePolicy("import Mathlib")
    check result.len > 0
    check result.contains("forbidden")

suite "isLeanstralSourcePolicyDiagnostic contract":
  test "detects policy diagnostic":
    check isLeanstralSourcePolicyDiagnostic("forbidden Lean import: Mathlib")

  test "returns false for normal text":
    check not isLeanstralSourcePolicyDiagnostic("theorem test")
