## A/B Test Comparator — Bit-level test result comparison
## Compares two test result files and reports differences.
## Used for regression detection: any behavioral change between
## two runs with identical input is a potential regression.
## Exit 1 if differences found.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, algorithm, tables]

type
  DiffEntry = object
    testName: string
    oldResult: string
    newResult: string

proc parseResults(content: string): seq[(string, string)] =
  ## Parse test results as (test_name, result) pairs.
  ## Format: one per line, "test_name: PASS|FAIL|SKIP"
  result = @[]
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    let colonPos = stripped.find(':')
    if colonPos > 0:
      let name = stripped[0 .. colonPos - 1].strip()
      let val = stripped[colonPos + 1 .. ^1].strip()
      result.add((name, val))

proc compareResults(oldFile, newFile: string): seq[DiffEntry] =
  ## Compare two result files and return differences.
  result = @[]
  let oldContent = readFile(oldFile)
  let newContent = readFile(newFile)
  let oldResults = parseResults(oldContent)
  let newResults = parseResults(newContent)

  var oldMap = initTable[string, string]()
  for (name, val) in oldResults:
    oldMap[name] = val

  for (name, val) in newResults:
    if name in oldMap:
      if oldMap[name] != val:
        result.add(DiffEntry(testName: name, oldResult: oldMap[name], newResult: val))
    else:
      result.add(DiffEntry(testName: name, oldResult: "(missing)", newResult: val))

  # Check for tests that disappeared
  var newMap = initTable[string, string]()
  for (name, val) in newResults:
    newMap[name] = val
  for (name, val) in oldResults:
    if name notin newMap:
      result.add(DiffEntry(testName: name, oldResult: val, newResult: "(missing)"))

proc main() =
  let params = commandLineParams()
  if params.len < 2:
    echo "Usage: ab_test_comparator <old_results> <new_results>"
    echo "  Compares two test result files and reports differences."
    echo "  Format: one result per line, 'test_name: PASS|FAIL|SKIP'"
    quit(2)

  let oldFile = params[0]
  let newFile = params[1]

  if not fileExists(oldFile):
    echo "ERROR: Old results file not found: ", oldFile
    quit(2)
  if not fileExists(newFile):
    echo "ERROR: New results file not found: ", newFile
    quit(2)

  let diffs = compareResults(oldFile, newFile)

  if diffs.len == 0:
    echo "OK: Results are identical (bit-level match)"
    quit(0)

  echo "FAIL: ", diffs.len, " difference(s) found:"
  echo ""
  for d in diffs:
    echo "  ", d.testName
    echo "    old: ", d.oldResult
    echo "    new: ", d.newResult
  quit(1)

when isMainModule:
  main()
