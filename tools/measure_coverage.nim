## Coverage Measurement Tool — DEBT#169
## Scans src/**/*.nim and checks for corresponding test files in tests/.
## Outputs a JSON report to data/coverage_report.json.
## Standalone binary — no project imports required.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, json, math]

func extractModuleName(filePath: string): string =
  ## Extract the base module name (without .nim extension) from a file path.
  let name = extractFilename(filePath)
  if name.endsWith(".nim"):
    result = name[0 .. ^5]
  else:
    result = name

func hasTestFile(moduleName: string; testFiles: seq[string]): bool =
  ## Check if any test file matches this module name.
  ## Matches: <module>_test.nim (exact/prefix), test_<module>*.nim (prefix).
  let suffix = "_test.nim"
  let prefix = "test_"
  for tf in testFiles:
    let tfName = extractFilename(tf)
    if tfName.endsWith(suffix):
      let base = tfName[0 .. ^(suffix.len + 1)]
      # Allow moduleName to be a prefix of base (e.g., anti_theater_gate matches anti_theater_gate_feature)
      if base == moduleName or base.startsWith(moduleName & "_"):
        return true
    elif tfName.startsWith(prefix):
      # Match test_<moduleName>.nim or test_<moduleName>_<anything>.nim
      let afterPrefix = tfName[prefix.len .. ^1]
      if afterPrefix.endsWith(".nim"):
        let withoutExt = afterPrefix[0 .. ^5]
        if withoutExt == moduleName or withoutExt.startsWith(moduleName & "_"):
          return true
      elif afterPrefix == moduleName or afterPrefix.startsWith(moduleName & "_"):
        return true
  result = false

proc collectNimFiles(root: string; excludeDirs: seq[string]): seq[string] =
  ## Recursively collect all .nim files, excluding specified directories.
  result = @[]
  for kind, path in walkDir(root, relative = false):
    if kind == pcDir:
      let dirName = extractFilename(path)
      var skip = false
      for ex in excludeDirs:
        if dirName == ex:
          skip = true
          break
      if skip:
        continue
      result.add(collectNimFiles(path, excludeDirs))
    elif kind == pcFile and path.endsWith(".nim"):
      result.add(path)

proc collectTestFiles(root: string): seq[string] =
  ## Recursively collect all test .nim files under tests/.
  result = @[]
  for kind, path in walkDir(root, relative = false):
    if kind == pcDir:
      result.add(collectTestFiles(path))
    elif kind == pcFile and path.endsWith(".nim"):
      result.add(path)

proc generateReport(srcDir, testsDir, outputFile: string) =
  ## Generate the coverage report JSON.
  let excludeDirs = @["vendor", "generated"]

  # Collect all source modules
  let srcFiles = collectNimFiles(srcDir, excludeDirs)
  let testFiles = collectTestFiles(testsDir)

  var testedCount = 0
  var untested: seq[string] = @[]

  for srcFile in srcFiles:
    let moduleName = extractModuleName(srcFile)
    if hasTestFile(moduleName, testFiles):
      inc testedCount
    else:
      untested.add(srcFile)

  let total = srcFiles.len
  let pct = if total > 0: (testedCount.float / total.float) * 100.0 else: 0.0

  let now = now().utc()
  let ts = now.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  var report = %*{
    "total_modules": total,
    "tested_modules": testedCount,
    "untested_modules_count": untested.len,
    "coverage_pct": round(pct * 10) / 10,
    "timestamp": ts
  }

  # Write report idempotently: timestamp is audit metadata — exclude from comparison
  # to avoid unnecessary rewrites on every run.
  let outputDir = parentDir(outputFile)
  if not dirExists(outputDir):
    createDir(outputDir)

  var changed = true
  if fileExists(outputFile):
    try:
      let existing = readFile(outputFile)
      let existingJson = parseJson(existing)
      var stableExisting = existingJson
      stableExisting["timestamp"] = %""
      var stableReport = report
      stableReport["timestamp"] = %""
      if stableExisting.pretty(indent = 2) == stableReport.pretty(indent = 2):
        changed = false
    except CatchableError: # axiom:best-effort(unreadable-prior-coverage: treated as changed, idempotent write still proceeds)
      discard

  if changed:
    writeFile(outputFile, pretty(report, indent = 2))

  # Also write the untested module list alongside (always fresh — no idempotent needed)

  # Also write the untested module list alongside
  let untestedFile = outputFile.replace(".json", "_untested.json")
  var untestedArr = newJArray()
  for m in untested:
    untestedArr.add(newJString(m))
  writeFile(untestedFile, pretty(%*{
    "count": untested.len,
    "modules": untestedArr
  }, indent = 2))

  # Summary to stdout
  echo "=== Coverage Report ==="
  echo "Total modules:  ", total
  echo "Tested modules: ", testedCount
  echo "Untested:       ", untested.len
  echo "Coverage:       ", round(pct * 10) / 10, "%"
  echo "Report:         ", outputFile
  echo "Untested list:  ", untestedFile

proc main() =
  let params = commandLineParams()

  # Defaults
  var srcDir = "src"
  var testsDir = "tests"
  var outputFile = "data/coverage_report.json"

  # Parse simple args
  var i = 0
  while i < params.len:
    case params[i]
    of "--src":
      if i + 1 < params.len:
        srcDir = params[i + 1]
        inc i
    of "--tests":
      if i + 1 < params.len:
        testsDir = params[i + 1]
        inc i
    of "--output":
      if i + 1 < params.len:
        outputFile = params[i + 1]
        inc i
    of "--help", "-h":
      echo "Usage: measure_coverage [options]"
      echo "  --src <dir>     Source directory (default: src)"
      echo "  --tests <dir>   Tests directory (default: tests)"
      echo "  --output <file> Output JSON file (default: data/coverage_report.json)"
      quit(0)
    else:
      echo "Unknown option: ", params[i]
      quit(2)
    inc i

  if not dirExists(srcDir):
    echo "ERROR: Source directory not found: ", srcDir
    quit(2)
  if not dirExists(testsDir):
    echo "WARNING: Tests directory not found: ", testsDir

  generateReport(srcDir, testsDir, outputFile)

when isMainModule:
  main()
