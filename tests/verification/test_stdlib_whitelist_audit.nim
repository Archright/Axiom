{.push raises: [CatchableError].}

## Stdlib Whitelist Audit Tests — Unit tests for gate/stdlib_whitelist_audit_runner.nim
## Tests pure analysis functions: findStdlibImports, buildUsageTable,
## buildAuditResult, readFileContent, findNimFilesRecursive.

import std/[unittest, os, tables, algorithm, times, strutils]
import gate/runners/stdlib_whitelist_audit_runner

# ---------------------------------------------------------------------------
# findStdlibImports
# ---------------------------------------------------------------------------

suite "findStdlibImports":
  test "detects std/json import":
    let content = "import std/json\nimport core/types\n"
    let imports = findStdlibImports(content)
    check imports.len == 1
    check "std/json" in imports

  test "detects multiple stdlib imports":
    let content = "import std/[json, os, strutils]\nimport core/results\n"
    let imports = findStdlibImports(content)
    check imports.len == 3
    check "std/json" in imports
    check "std/os" in imports
    check "std/strutils" in imports

  test "detects 'from' import syntax":
    let content = "from std/json import parseJson, pretty\n"
    let imports = findStdlibImports(content)
    check imports.len == 1
    check "std/json" in imports

  test "non-stdlib imports are ignored":
    let content = "import core/types\nimport gate/orchestrator\n"
    let imports = findStdlibImports(content)
    check imports.len == 0

  test "empty content returns empty list":
    let imports = findStdlibImports("")
    check imports.len == 0

  test "deduplicates imports":
    let content = "import std/json\nimport std/json\nfrom std/json import parseJson\n"
    let imports = findStdlibImports(content)
    check imports.len == 1

  test "returns sorted list":
    let content = "import std/strutils\nimport std/json\nimport std/os\n"
    let imports = findStdlibImports(content)
    check imports == @["std/json", "std/os", "std/strutils"]

  test "mixed import and from-import":
    let content = "import std/os\nfrom std/strutils import splitLines\n"
    let imports = findStdlibImports(content)
    check imports.len == 2

  test "ignores comments and non-import lines":
    let content = "# This is a comment\nimport std/json\nlet x = 1\n"
    let imports = findStdlibImports(content)
    check imports.len == 1
    check "std/json" in imports

  test "handles Windows-style std paths":
    let content = "import std\\json\n"
    let imports = findStdlibImports(content)
    check imports.len == 1

# ---------------------------------------------------------------------------
# buildUsageTable
# ---------------------------------------------------------------------------

suite "buildUsageTable":
  test "builds module→files mapping":
    var fileContents = initTable[string, string]()
    fileContents["a.nim"] = "import std/json\n"
    fileContents["b.nim"] = "import std/json\nimport std/os\n"
    let table = buildUsageTable(fileContents)
    check table.len == 2
    check table["std/json"].len == 2
    check table["std/os"].len == 1

  test "empty input → empty table":
    var fileContents = initTable[string, string]()
    let table = buildUsageTable(fileContents)
    check table.len == 0

  test "files with no stdlib imports not in table":
    var fileContents = initTable[string, string]()
    fileContents["core.nim"] = "import core/types\n"
    let table = buildUsageTable(fileContents)
    check table.len == 0

# ---------------------------------------------------------------------------
# buildAuditResult
# ---------------------------------------------------------------------------

suite "buildAuditResult":
  test "builds correct AuditResult":
    var usageTable = initTable[string, seq[string]]()
    usageTable["std/json"] = @["a.nim", "b.nim"]
    usageTable["std/os"] = @["b.nim"]
    let result = buildAuditResult(5, usageTable)
    check result.filesScanned == 5
    check result.uniqueModules == 2
    check result.usage.len == 2
    # sorted by module name
    check result.usage[0].module == "std/json"
    check result.usage[0].count == 2
    check result.usage[1].module == "std/os"
    check result.usage[1].count == 1

  test "empty usage → zero modules":
    var emptyTable = initTable[string, seq[string]]()
    let result = buildAuditResult(10, emptyTable)
    check result.filesScanned == 10
    check result.uniqueModules == 0
    check result.usage.len == 0

# ---------------------------------------------------------------------------
# readFileContent
# ---------------------------------------------------------------------------

suite "readFileContent":
  test "reads existing file":
    let tmpFile = getTempDir() / "axiom_test_readme_" & $epochTime().int & ".nim"
    defer: removeFile(tmpFile)
    writeFile(tmpFile, "hello world")
    let content = readFileContent(tmpFile)
    check content == "hello world"

  test "non-existent file returns empty string":
    let content = readFileContent("/nonexistent/path/file.nim")
    check content.len == 0

# ---------------------------------------------------------------------------
# findNimFilesRecursive
# ---------------------------------------------------------------------------

suite "findNimFilesRecursive":
  test "finds .nim files recursively":
    let tmpDir = getTempDir() / "axiom_test_nimfind_" & $epochTime().int
    let subDir = tmpDir / "sub"
    createDir(subDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "a.nim", "")
    writeFile(subDir / "b.nim", "")
    writeFile(tmpDir / "c.txt", "")
    let files = findNimFilesRecursive(tmpDir)
    check files.len == 2
    var foundA, foundB = false
    for f in files:
      if f.endsWith("a.nim"): foundA = true
      if f.endsWith("b.nim"): foundB = true
    check foundA
    check foundB

  test "non-existent directory returns empty":
    let files = findNimFilesRecursive("/nonexistent/path/xyz")
    check files.len == 0

  test "empty directory returns empty":
    let tmpDir = getTempDir() / "axiom_test_nimfind_empty_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let files = findNimFilesRecursive(tmpDir)
    check files.len == 0

# ---------------------------------------------------------------------------
# AuditResult type
# ---------------------------------------------------------------------------

suite "AuditResult type":
  test "StdlibUsage fields":
    let usage = StdlibUsage(module: "std/json", files: @["a.nim"], count: 1)
    check usage.module == "std/json"
    check usage.files.len == 1
    check usage.count == 1

  test "AuditResult fields":
    let result = AuditResult(filesScanned: 3, uniqueModules: 1, usage: @[])
    check result.filesScanned == 3
    check result.uniqueModules == 1
    check result.usage.len == 0

{.pop.}
