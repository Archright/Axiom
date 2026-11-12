## Sorry Audit Gate Test — Validates sorry detection in Lean files.
##
## Creates temp .lean files with and without sorry, then verifies
## the gate correctly reports PASS/FAIL.

{.push raises: [CatchableError].}

import std/[os, unittest]
import src/gate/runners/sorry_audit_gate

{.push warning[BareExcept]:off.}

suite "Sorry Audit Gate — word-boundary detection":
  test "isSorryWord detects standalone sorry":
    check isSorryWord("  sorry")
    check isSorryWord("exact foo by sorry")
    check isSorryWord("sorry -- after comment")
    check isSorryWord("by sorry")

  test "isSorryWord rejects substrings":
    check not isSorryWord("sorry_not_sorry")
    check not isSorryWord("mySorryVariable")
    check not isSorryWord("apologize")  # no match at all

  test "scanContent finds sorry in non-comment lines":
    let content = "-- this is a comment\ntheorem foo : sorry\n  sorry here\n"
    let findings = scanContent(content, "test.lean")
    check findings.len == 2
    check findings[0].line == 2
    check findings[1].line == 3

  test "scanContent ignores comment lines":
    let content = "-- sorry this is a comment\ntheorem foo : sorry\n"
    let findings = scanContent(content, "test.lean")
    check findings.len == 1
    check findings[0].line == 2

  test "scanContent returns empty for sorry-free content":
    let content = "theorem foo : True := by\n  trivial\n"
    let findings = scanContent(content, "test.lean")
    check findings.len == 0

suite "Sorry Audit Gate — file scanning":
  test "Gate FAIL on file with sorry":
    let testDir = getTempDir() / "axiom_sorry_test_" & $getCurrentProcessId()
    let proofsDir = testDir / "proofs"
    createDir(proofsDir)
    defer: removeDir(testDir)

    writeFile(proofsDir / "test.lean", "theorem foo : sorry\n  sorry\n")
    let res = runSorryAudit(testDir)
    check not res.ok
    check res.findings.len == 2

  test "Gate PASS on file without sorry":
    let testDir = getTempDir() / "axiom_sorry_test_" & $getCurrentProcessId()
    let proofsDir = testDir / "proofs"
    createDir(proofsDir)
    defer: removeDir(testDir)

    writeFile(proofsDir / "test.lean", "theorem foo : True := by\n  trivial\n")
    let res = runSorryAudit(testDir)
    check res.ok
    check res.findings.len == 0

  test "Gate PASS when no proofs directory exists":
    let testDir = getTempDir() / "axiom_sorry_test_" & $getCurrentProcessId()
    createDir(testDir)
    defer: removeDir(testDir)

    let res = runSorryAudit(testDir)
    check res.ok

  test "Gate detects sorry in nested directories":
    let testDir = getTempDir() / "axiom_sorry_test_" & $getCurrentProcessId()
    let proofsDir = testDir / "proofs" / "GateInvariants"
    createDir(proofsDir)
    defer: removeDir(testDir)

    writeFile(proofsDir / "nested.lean", "theorem bar : sorry\n")
    let res = runSorryAudit(testDir)
    check not res.ok
    check res.findings.len == 1

  test "Gate ignores sorry in comments in nested files":
    let testDir = getTempDir() / "axiom_sorry_test_" & $getCurrentProcessId()
    let proofsDir = testDir / "proofs"
    createDir(proofsDir)
    defer: removeDir(testDir)

    writeFile(proofsDir / "commented.lean", "-- sorry is not detected here\ntheorem ok : True\n")
    let res = runSorryAudit(testDir)
    check res.ok
    check res.findings.len == 0

{.pop.}
