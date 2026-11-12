## Canonical Hub Lint Runner Feature Test.
## See tests/features/canonical_hub_lint.feature for the specification.
##
## Verifies the pure lint logic that enforces forwarding stub purity:
## stubs may only contain imports, exports, comments, and pragmas.
## Business-logic keywords (func, proc, let, var, etc.) are forbidden.

import std/[unittest, strutils]
import gate/runners/canonical_hub_lint_runner

suite "Canonical Hub Lint Runner — pure helpers":
  test "firstNonWhitespace finds first non-space index":
    check "  foo".firstNonWhitespace() == 2
    check "bar".firstNonWhitespace() == 0
    check "   ".firstNonWhitespace() == -1
    check "".firstNonWhitespace() == -1

  test "isCommentLine detects comment markers":
    check isCommentLine("# a comment") == true
    check "  # indented comment".isCommentLine() == true
    check isCommentLine("not a comment") == false
    check "".isCommentLine() == false

  test "isBlankLine detects blank and whitespace-only lines":
    check isBlankLine("") == true
    check isBlankLine("   ") == true
    check isBlankLine("\t") == true
    check isBlankLine("x") == false

  test "isPragmaPush detects {.push ...} directives":
    check isPragmaPush("{.push raises: [].}") == true
    check isPragmaPush("  {.push.}") == true
    check isPragmaPush("{.pop.}") == false

  test "isPragmaPop detects {.pop.} directives":
    check isPragmaPop("{.pop.}") == true
    check isPragmaPop("  {.pop.}") == true
    check isPragmaPop("{.push raises: [].}") == false

  test "isDeprecatedPragma detects {.deprecated ...}":
    check isDeprecatedPragma("{.deprecated.}") == true
    check isDeprecatedPragma("  {.deprecated: use foo instead.}") == true
    check isDeprecatedPragma("{.push.}") == false

  test "isImportLine detects import statements":
    check isImportLine("import std/[os, strutils]") == true
    check isImportLine("import\tstd/os") == true
    check isImportLine("from foo import bar") == false

  test "isExportLine detects export statements":
    check isExportLine("export gate_types") == true
    check isExportLine("export\tgate_types") == true

  test "isFromImportLine detects from-import statements":
    check isFromImportLine("from std/os import `/`)") == true
    check isFromImportLine("from gate/types import GateConfig") == true
    check isFromImportLine("import std/os") == false

  test "isAllowedLine accepts all permitted line types":
    check isAllowedLine("") == true                          # blank
    check isAllowedLine("# comment") == true                 # comment
    check isAllowedLine("{.push raises: [].}") == true      # pragma push
    check isAllowedLine("{.pop.}") == true                   # pragma pop
    check isAllowedLine("{.deprecated.}") == true            # deprecated pragma
    check isAllowedLine("import std/os") == true             # import
    check isAllowedLine("export gate_types") == true         # export
    check isAllowedLine("from foo import bar") == true       # from-import
    check isAllowedLine("func add(a, b: int): int = a + b") == false  # forbidden

  test "findForbiddenKeyword detects business-logic keywords":
    check findForbiddenKeyword("func add(a, b: int) = a + b") == "func"
    check findForbiddenKeyword("proc main() = discard") == "proc"
    check findForbiddenKeyword("let x = 5") == "let"
    check findForbiddenKeyword("var count = 0") == "var"
    check findForbiddenKeyword("const MAX = 10") == "const"
    check findForbiddenKeyword("if x > 0:") == "if"
    check findForbiddenKeyword("for i in 0..10:") == "for"
    check findForbiddenKeyword("case n:") == "case"
    check findForbiddenKeyword("try: discard") == "try"

  test "findForbiddenKeyword returns empty for allowed content":
    check findForbiddenKeyword("# just a comment") == ""
    check findForbiddenKeyword("import std/os") == ""
    check findForbiddenKeyword("") == ""
    check findForbiddenKeyword("{.push raises: [].}") == ""

  test "isStub detects forwarding stubs (import+export, no func/proc)":
    const stubContent = """import std/[os, strutils]
import gate/types
export gate_types
"""
    check isStub(stubContent) == true

  test "isStub returns false for files with func definitions":
    const nonStub = """import std/os
export gate_types

func add(a, b: int): int = a + b
"""
    check isStub(nonStub) == false

  test "isStub returns false for files without exports":
    const noExport = """import std/os
import std/strutils
"""
    check isStub(noExport) == false

suite "Canonical Hub Lint Runner — violation detection":
  test "checkStubContent finds forbidden 'func' keyword":
    const stub = """import std/os
export gate_types

func add(a, b: int): int = a + b
"""
    let violations = checkStubContent("test_file.nim", stub)
    check violations.len > 0
    check violations[0].severity == seError
    check "func" in violations[0].message
    check violations[0].line == 4  # 1-indexed line number

  test "checkStubContent finds forbidden 'proc' keyword":
    const stub = """import std/os
export gate_types

proc doStuff() = discard
"""
    let violations = checkStubContent("test_file.nim", stub)
    check violations.len > 0
    check violations[0].severity == seError
    check "proc" in violations[0].message

  test "checkStubContent returns empty for clean stub":
    const cleanStub = """import std/[os, strutils]
import gate/types
export gate_types
"""
    let violations = checkStubContent("test_file.nim", cleanStub)
    check violations.len == 0

  test "checkStubContent finds multiple violations in one file":
    const dirtyStub = """import std/os
export gate_types

func add(a, b: int) = discard
let x = 5
if x > 0: discard
"""
    let violations = checkStubContent("test_file.nim", dirtyStub)
    check violations.len >= 3

  test "formatViolation produces file:line: message format":
    let v = LintViolation(file: "foo.nim", line: 10, column: 1,
                          message: "bad stuff", severity: seError)
    let formatted = formatViolation(v)
    check "foo.nim:10: bad stuff" == formatted

suite "Canonical Hub Lint Runner — LintResult helpers":
  test "hasViolations returns true when errors exist":
    var lr = LintResult(filesScanned: 1, stubsDetected: 1)
    lr.violations.add LintViolation(severity: seError, file: "x.nim",
                                     line: 1, column: 1, message: "err")
    check hasViolations(lr) == true

  test "hasViolations returns false when only warnings exist":
    var lr = LintResult(filesScanned: 1, stubsDetected: 1)
    lr.violations.add LintViolation(severity: seWarning, file: "x.nim",
                                     line: 1, column: 1, message: "warn")
    check hasViolations(lr) == false

  test "hasViolations returns false for empty violations":
    let lr = LintResult(filesScanned: 1, stubsDetected: 1)
    check hasViolations(lr) == false

  test "errorCount and warningCount are correct":
    var lr = LintResult(filesScanned: 1, stubsDetected: 2)
    lr.violations.add LintViolation(severity: seError, file: "a.nim",
                                     line: 1, column: 1, message: "e1")
    lr.violations.add LintViolation(severity: seError, file: "a.nim",
                                     line: 2, column: 1, message: "e2")
    lr.violations.add LintViolation(severity: seWarning, file: "b.nim",
                                     line: 1, column: 1, message: "w1")
    check errorCount(lr) == 2
    check warningCount(lr) == 1
