## Tests for canonical_hub_lint_runner — test against known inputs

import std/[os, strutils, tables]
import gate/runners/canonical_hub_lint_runner

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

var testCount = 0
var passCount = 0

template check(condition: bool, msg: string) =
  inc testCount
  if condition:
    inc passCount
  else:
    echo "FAIL: " & msg

# ---------------------------------------------------------------------------
# Helper: create temp files with specific content for testing
# ---------------------------------------------------------------------------

proc createTempTestFile(name, content: string): string =
  let dir = getTempDir() / "axiom_lint_test"
  createDir(dir)
  let path = dir / name
  writeFile(path, content)
  path

proc cleanupTestDir() =
  let dir = getTempDir() / "axiom_lint_test"
  if dirExists(dir):
    removeDir(dir)

# ---------------------------------------------------------------------------
# Test: isBlankLine
# ---------------------------------------------------------------------------

block:
  check(isBlankLine(""), "empty line is blank")
  check(isBlankLine("   "), "whitespace-only line is blank")
  check(isBlankLine("  \t  "), "tab+space line is blank")
  check(not isBlankLine("hello"), "non-empty line is not blank")
  check(not isBlankLine("# comment"), "comment is not blank")

# ---------------------------------------------------------------------------
# Test: isCommentLine
# ---------------------------------------------------------------------------

block:
  check(isCommentLine("# comment"), "standard comment")
  check(isCommentLine("  # indented comment"), "indented comment")
  check(isCommentLine("## doc comment"), "doc comment")
  check(not isCommentLine("import foo"), "import is not comment")
  check(not isCommentLine("func bar()"), "func is not comment")
  check(not isCommentLine(""), "empty is not comment")

# ---------------------------------------------------------------------------
# Test: isPragmaPush / isPragmaPop / isDeprecatedPragma
# ---------------------------------------------------------------------------

block:
  check(isPragmaPush("{.push raises: [].}"), "push pragma")
  check(isPragmaPush("  {.push.}"), "indented push")
  check(not isPragmaPush("{.pop.}"), "pop is not push")
  check(not isPragmaPush("import std/os"), "import is not push")

  check(isPragmaPop("{.pop.}"), "pop pragma")
  check(isPragmaPop("  {.pop.}"), "indented pop")
  check(not isPragmaPop("{.push.}"), "push is not pop")

  check(isDeprecatedPragma("{.deprecated: \"old\".}"), "deprecated pragma")
  check(not isDeprecatedPragma("{.push.}"), "push is not deprecated")

# ---------------------------------------------------------------------------
# Test: isImportLine / isExportLine / isFromImportLine
# ---------------------------------------------------------------------------

block:
  check(isImportLine("import std/os"), "standard import")
  check(isImportLine("  import core/types/results"), "indented import")
  check(not isImportLine("export foo"), "export is not import")
  check(not isImportLine("# import foo"), "comment is not import")

  check(isExportLine("export foo"), "standard export")
  check(isExportLine("  export bar"), "indented export")
  check(not isExportLine("import foo"), "import is not export")

  check(isFromImportLine("from std/os import parentDir"), "from import")
  check(isFromImportLine("  from core/types import Result"), "indented from import")
  check(not isFromImportLine("import std/os"), "regular import is not from-import")

# ---------------------------------------------------------------------------
# Test: isAllowedLine
# ---------------------------------------------------------------------------

block:
  check(isAllowedLine(""), "blank line is allowed")
  check(isAllowedLine("# comment"), "comment is allowed")
  check(isAllowedLine("{.push raises: [].}"), "pragma push is allowed")
  check(isAllowedLine("{.pop.}"), "pragma pop is allowed")
  check(isAllowedLine("{.deprecated: \"x\".}"), "deprecated is allowed")
  check(isAllowedLine("import std/os"), "import is allowed")
  check(isAllowedLine("export foo"), "export is allowed")
  check(isAllowedLine("from foo import bar"), "from import is allowed")
  check(not isAllowedLine("func foo()"), "func is NOT allowed")
  check(not isAllowedLine("let x = 1"), "let is NOT allowed")

# ---------------------------------------------------------------------------
# Test: findForbiddenKeyword
# ---------------------------------------------------------------------------

block:
  check(findForbiddenKeyword("func foo()") == "func", "should find func")
  check(findForbiddenKeyword("proc bar()") == "proc", "should find proc")
  check(findForbiddenKeyword("let x = 1") == "let", "should find let")
  check(findForbiddenKeyword("var y = 2") == "var", "should find var")
  check(findForbiddenKeyword("if cond:") == "if", "should find if")
  check(findForbiddenKeyword("  for i in 0..10:") == "for", "should find indented for")
  check(findForbiddenKeyword("import std/os") == "", "import is not forbidden")
  check(findForbiddenKeyword("export foo") == "", "export is not forbidden")

# ---------------------------------------------------------------------------
# Test: isStub (with real content)
# ---------------------------------------------------------------------------

block:
  let stubContent = """
import core/types/results
export results
"""
  check(isStub(stubContent), "import+export without func/proc = stub")

  let nonStubContent = """
import core/types/results

func doSomething(): string =
  result = "hello"
"""
  check(not isStub(nonStubContent), "import+func is NOT a stub")

  let importOnlyContent = """
import std/os
import std/strutils
"""
  # Has import but no export, so not a stub
  check(not isStub(importOnlyContent), "import only (no export) is NOT a stub")

# ---------------------------------------------------------------------------
# Test: checkStubContent — clean stub
# ---------------------------------------------------------------------------

block:
  let cleanContent = """
## Results module
{.push raises: [].}

import core/types/results
export results

{.pop.}
"""
  let violations = checkStubContent("clean.nim", cleanContent)
  check(violations.len == 0, "clean stub should have 0 violations, got " & $violations.len)

# ---------------------------------------------------------------------------
# Test: checkStubContent — stub with forbidden keywords
# ---------------------------------------------------------------------------

block:
  let dirtyContent = """
import core/types/results
export results

func processIt(): string =
  result = "done"
"""
  let violations = checkStubContent("dirty.nim", dirtyContent)
  check(violations.len > 0, "dirty stub should have violations, got " & $violations.len)
  check(violations[0].severity == seError, "should be error severity")
  check("func" in violations[0].message, "should mention 'func' keyword")

# ---------------------------------------------------------------------------
# Test: checkStubContent — stub with unexpected content
# ---------------------------------------------------------------------------

block:
  let weirdContent = """
import core/types/results
export results

something_weird_here
"""
  let violations = checkStubContent("weird.nim", weirdContent)
  check(violations.len > 0, "weird stub should have violations")
  check(violations[0].severity == seWarning, "should be warning severity")

# ---------------------------------------------------------------------------
# Test: formatViolation
# ---------------------------------------------------------------------------

block:
  let v = LintViolation(
    file: "test.nim",
    line: 42,
    column: 1,
    message: "stub contains 'func'",
    severity: seError
  )
  let formatted = v.formatViolation()
  check("test.nim:42:" in formatted, "should contain file:line")
  check("func" in formatted, "should contain message")

# ---------------------------------------------------------------------------
# Test: LintResult counters
# ---------------------------------------------------------------------------

block:
  var lr = LintResult(
    filesScanned: 10,
    stubsDetected: 3,
    violations: @[
      LintViolation(file: "a.nim", line: 1, column: 1, message: "err1", severity: seError),
      LintViolation(file: "a.nim", line: 2, column: 1, message: "err2", severity: seError),
      LintViolation(file: "b.nim", line: 1, column: 1, message: "warn1", severity: seWarning),
    ]
  )
  check(lr.hasViolations(), "should have violations")
  check(lr.errorCount() == 2, "should have 2 errors")
  check(lr.warningCount() == 1, "should have 1 warning")

  var cleanLr = LintResult(filesScanned: 5, stubsDetected: 2, violations: @[])
  check(not cleanLr.hasViolations(), "clean result should have no violations")

# ---------------------------------------------------------------------------
# Test: runCanonicalHubLint with empty paths (scans src/core/)
# ---------------------------------------------------------------------------

block:
  # This tests against the actual project — src/core/ should exist
  let coreDir = getCurrentDir() / "src" / "core"
  if dirExists(coreDir):
    let result = runCanonicalHubLint(@[coreDir])
    check(result.filesScanned > 0, "should scan files in src/core/, got " & $result.filesScanned)
    # We don't check violation count — the project may or may not have violations
    # but the scan should complete without crashing
    echo "  Lint scan: " & $result.filesScanned & " files, " &
         $result.stubsDetected & " stubs, " &
         $result.violations.len & " violations"
  else:
    echo "  Skipping src/core/ scan test (dir not found)"

# ---------------------------------------------------------------------------
# Cleanup and Summary
# ---------------------------------------------------------------------------

cleanupTestDir()

echo ""
echo "Canonical hub lint tests: " & $passCount & "/" & $testCount & " passed"
if passCount < testCount:
  quit(1)
