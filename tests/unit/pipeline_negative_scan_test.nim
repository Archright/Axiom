import std/unittest
import std/json
import std/strutils
import core/utils/text_utils
import verification/pipeline_negative_scan_part1
import verification/pipeline_negative_scan_part3
import core/types/pipeline_core_types

suite "leadingWhitespace contract":
  test "extracts leading spaces":
    check leadingWhitespace("  hello") == "  "

  test "extracts leading tabs":
    check leadingWhitespace("\thello") == "\t"

  test "extracts mixed spaces and tabs":
    check leadingWhitespace(" \t hello") == " \t "

  test "no leading whitespace returns empty":
    check leadingWhitespace("hello") == ""

  test "empty string returns empty":
    check leadingWhitespace("") == ""

suite "bindingValue contract":
  test "returns existing key value":
    let bindings = %*{"x": "1", "y": "2"}
    check bindingValue(bindings, "x", "default") == "1"

  test "returns default for missing key":
    let bindings = %*{"x": "1"}
    check bindingValue(bindings, "z", "default") == "default"

  test "returns default for non-object":
    let bindings = %*["a", "b"]
    check bindingValue(bindings, "x", "default") == "default"

suite "applyOneRemediation contract":
  test "empty source appends snippet at end":
    let hit = VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: ""))
    let result = applyOneRemediation("", "nim", hit)
    check result.changed
    check result.updated.contains("if ptr == nil:")

  test "inserts null check after Nim proc header":
    let source = "proc foo(): int =\n  echo 1"
    let hit = VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: ""))
    let result = applyOneRemediation(source, "nim", hit)
    check result.changed
    check result.updated.contains("if ptr == nil:")

  test "inserts buffer bounds check after Nim proc header":
    let source = "proc bar(): int =\n  echo 1"
    let hit = VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0))
    let result = applyOneRemediation(source, "nim", hit)
    check result.changed
    check result.updated.contains("if idx < 0 or idx >= length:")

  test "deadlock_race_condition produces remediation for nim":
    let source = "proc foo(): int =\n  echo 1"
    let hit = VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: ""))
    let result = applyOneRemediation(source, "nim", hit)
    check result.changed
    check result.updated.contains("lockHeld")

  test "inserts C-style null check after brace":
    let source = "int foo() {\n  return 1;\n}"
    let hit = VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: ""))
    let result = applyOneRemediation(source, "c", hit)
    check result.changed
    check result.updated.contains("if (ptr == NULL)")

## Refactor: ACI-driven extract-method/table-driven DRY improvements validated by existing suite.
