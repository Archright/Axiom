## tools/cyclomatic_complexity.nim
## Cyclomatic complexity measurement tool for Nim source files.
## Parses source files line-by-line, tracks function boundaries via
## indentation, and counts decision points per function.
##
## Cyclomatic complexity = 1 + number of decision points
## Decision points: if/elif/for/while/case/of/try/except/and/or
##
## Usage:
##   nim c -o:bin/cyclomatic_complexity tools/cyclomatic_complexity.nim
##   bin/cyclomatic_complexity <file.nim>              # single file
##   bin/cyclomatic_complexity src/core/               # directory scan
##   bin/cyclomatic_complexity --top=20 src/           # top 20 most complex
##   bin/cyclomatic_complexity --json src/             # JSON output
##   bin/cyclomatic_complexity --threshold=10 src/     # only complexity > 10

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, strformat, json, algorithm]

type
  FuncComplexity = object
    name: string
    kind: string       ## "func" or "proc"
    line: int
    complexity: int
    isHighRisk: bool   ## complexity > 10

  FileComplexity = object
    path: string
    totalComplexity: int
    functions: seq[FuncComplexity]
    highRiskCount: int

# =============================================================================
# Core Analysis
# =============================================================================

func stripComment(line: string): string =
  ## Remove everything after the first `#` that is not inside a string.
  var inString = false
  var stringChar = ' '
  var i = 0
  while i < line.len:
    let c = line[i]
    if inString:
      if c == '\\' and i + 1 < line.len:
        inc i  # skip escaped char
      elif c == stringChar:
        inString = false
    else:
      if c == '#' and (i == 0 or line[i - 1] != '\\'):
        return line[0 ..< i]
      elif c == '"' or c == '\'':
        inString = true
        stringChar = c
    inc i
  result = line

func countDecisionPoints(line: string): int =
  ## Count decision-point keywords in a single line.
  let stripped = line.strip()
  # Skip comment-only lines, doc comments, pragmas, string literals
  if stripped.startsWith("##") or stripped.startsWith("#") or
     stripped.startsWith("{.") or stripped.startsWith("\""):
    return 0

  var count = 0
  let words = stripped.splitWhitespace()

  for word in words:
    case word
    of "if", "elif", "for", "while", "case", "try", "except", "finally":
      inc count
    of "and", "or":
      inc count
    else: discard

  result = count

func getIndentLevel(line: string): int =
  ## Return the number of leading spaces in a line.
  result = 0
  for c in line:
    case c
    of ' ': inc result
    of '\t': inc result, 2
    else: break

func isFunctionStart(line: string): tuple[isFunc: bool, kind: string, name: string] =
  ## Check if a line starts a function/proc declaration at the top level.
  result = (false, "", "")
  let stripped = line.strip()

  if stripped.startsWith("proc ") or stripped.startsWith("func "):
    let kind = if stripped.startsWith("proc "): "proc" else: "func"
    let prefix = kind & " "
    var rest = stripped[prefix.len ..^ 1]
    # Skip export marker
    if rest.startsWith("*"):
      rest = rest[1 ..^ 1]
    # Get name up to first non-identifier char
    var name = ""
    for c in rest:
      if c.isAlphaNumeric() or c == '_':
        name.add c
      else:
        break
    if name.len > 0:
      result = (true, kind, name)

func isTopLevelDecl(line: string): bool =
  ## Check if a line is a top-level declaration (not indented).
  let stripped = line.strip()
  if stripped.len == 0 or stripped.startsWith("#"):
    return false
  if getIndentLevel(line) > 0:
    return false
  result = stripped.startsWith("proc ") or stripped.startsWith("func ") or
           stripped.startsWith("type") or stripped.startsWith("const ") or
           stripped.startsWith("var ") or stripped.startsWith("let ") or
           stripped.startsWith("template ") or stripped.startsWith("macro ") or
           stripped.startsWith("converter ") or stripped.startsWith("method ") or
           stripped.startsWith("iterator ") or stripped.startsWith("{.") or
           stripped.startsWith("import ") or stripped.startsWith("from ")

func analyzeFunctionBody(bodyLines: seq[string]): int =
  ## Compute cyclomatic complexity for a function body. Base = 1.
  result = 1
  for line in bodyLines:
    let cleaned = stripComment(line)
    inc result, countDecisionPoints(cleaned)

proc parseFile(path: string): FileComplexity =
  ## Parse a single Nim file and compute per-function complexity.
  result = FileComplexity(path: path, totalComplexity: 0,
                          functions: @[], highRiskCount: 0)

  var lines: seq[string]
  try:
    lines = path.readFile().splitLines()
  except IOError:
    return result

  var i = 0
  while i < lines.len:
    let line = lines[i]
    let (isFunc, funcKind, funcName) = isFunctionStart(line)

    if isFunc and getIndentLevel(line) == 0:
      let startLine = i + 1  # 1-based
      var bodyLines: seq[string]
      inc i

      # Collect body: indented or empty lines until next top-level decl
      while i < lines.len:
        let bodyLine = lines[i]
        let stripped = bodyLine.strip()
        if stripped.len == 0:
          # Empty line — peek ahead to check if next line ends the function
          if i + 1 < lines.len:
            let nextLine = lines[i + 1]
            let nextStripped = nextLine.strip()
            if nextStripped.len > 0 and getIndentLevel(nextLine) == 0 and
               isTopLevelDecl(nextLine):
              break
          bodyLines.add bodyLine
          inc i
          continue
        if getIndentLevel(bodyLine) == 0 and isTopLevelDecl(bodyLine):
          break
        bodyLines.add bodyLine
        inc i

      let complexity = analyzeFunctionBody(bodyLines)
      let isHighRisk = complexity > 10
      result.functions.add FuncComplexity(
        name: funcName, kind: funcKind, line: startLine,
        complexity: complexity, isHighRisk: isHighRisk
      )
      inc result.totalComplexity, complexity
      if isHighRisk:
        inc result.highRiskCount
    else:
      inc i

proc collectNimFiles(dir: string): seq[string] =
  ## Recursively collect all .nim files in a directory.
  result = @[]
  try:
    for entry in walkDirRec(dir):
      if entry.endsWith(".nim"):
        result.add entry
  except OSError:
    discard

# =============================================================================
# Output Formatting
# =============================================================================

func formatTextReport(files: seq[FileComplexity], topN, threshold: int): string =
  ## Format results as human-readable text.
  var output: seq[string]
  output.add "=== Cyclomatic Complexity Report ==="
  output.add ""

  # Flatten all functions and sort by complexity
  var allFuncs: seq[tuple[filePath: string, fc: FuncComplexity]]
  for f in files:
    for fc in f.functions:
      if fc.complexity > threshold:
        allFuncs.add (f.path, fc)

  allFuncs.sort(proc (a, b: tuple[filePath: string, fc: FuncComplexity]): int =
    cmp(b.fc.complexity, a.fc.complexity)
  )

  let showCount = min(topN, allFuncs.len)
  output.add fmt"Top {showCount} most complex functions (threshold > {threshold}):"
  output.add ""

  for idx in 0 ..< showCount:
    let (filePath, fc) = allFuncs[idx]
    let risk = if fc.isHighRisk: " [HIGH RISK]" else: ""
    output.add fmt"  {idx + 1:3d}. {filePath}:{fc.name} ({fc.kind}, line {fc.line}) complexity={fc.complexity}{risk}"

  output.add ""
  output.add "=== Per-File Summary ==="
  output.add ""
  for f in files:
    if f.functions.len > 0:
      output.add fmt"  {f.path}: {f.functions.len} functions, total={f.totalComplexity}, highRisk={f.highRiskCount}"

  output.add ""
  output.add fmt"Total files analyzed: {files.len}"
  var totalFuncs = 0
  var totalCx = 0
  var totalHR = 0
  for f in files:
    inc totalFuncs, f.functions.len
    inc totalCx, f.totalComplexity
    inc totalHR, f.highRiskCount
  output.add fmt"Total functions: {totalFuncs}"
  output.add fmt"Total complexity: {totalCx}"
  output.add fmt"High-risk functions (complexity > 10): {totalHR}"

  result = output.join("\n")

func toJson(files: seq[FileComplexity]): JsonNode =
  ## Convert results to JSON.
  var root = newJObject()
  var filesArray = newJArray()

  for f in files:
    var fileObj = newJObject()
    fileObj["path"] = newJString(f.path)
    fileObj["totalComplexity"] = newJInt(f.totalComplexity)
    fileObj["highRiskCount"] = newJInt(f.highRiskCount)

    var funcsArray = newJArray()
    for fc in f.functions:
      var funcObj = newJObject()
      funcObj["name"] = newJString(fc.name)
      funcObj["kind"] = newJString(fc.kind)
      funcObj["line"] = newJInt(fc.line)
      funcObj["complexity"] = newJInt(fc.complexity)
      funcObj["isHighRisk"] = newJBool(fc.isHighRisk)
      funcsArray.add funcObj

    fileObj["functions"] = funcsArray
    filesArray.add fileObj

  root["files"] = filesArray

  var totalFuncs = 0
  var totalCx = 0
  var totalHR = 0
  for f in files:
    inc totalFuncs, f.functions.len
    inc totalCx, f.totalComplexity
    inc totalHR, f.highRiskCount

  var summary = newJObject()
  summary["totalFiles"] = newJInt(files.len)
  summary["totalFunctions"] = newJInt(totalFuncs)
  summary["totalComplexity"] = newJInt(totalCx)
  summary["highRiskCount"] = newJInt(totalHR)
  root["summary"] = summary

  result = root

# =============================================================================
# CLI
# =============================================================================

proc parseArgs(): tuple[target: string, topN: int, threshold: int, jsonOut: bool] =
  result = ("", 50, 0, false)
  var targetFound = false
  for i in 1..paramCount():
    let p = paramStr(i)
    if p.startsWith("--top="):
      result.topN = parseInt(p[6..^1])
    elif p.startsWith("--threshold="):
      result.threshold = parseInt(p[12..^1])
    elif p == "--json":
      result.jsonOut = true
    elif p == "--help" or p == "-h":
      echo "Usage: cyclomatic_complexity [options] <path>"
      echo ""
      echo "Options:"
      echo "  --top=N           Show top N most complex functions (default: 50)"
      echo "  --threshold=N     Only show functions with complexity > N (default: 0)"
      echo "  --json            Output as JSON"
      echo "  --help, -h        Show this help"
      echo ""
      echo "Arguments:"
      echo "  <path>            Single .nim file or directory to scan"
      quit(0)
    else:
      result.target = p
      targetFound = true

  if not targetFound:
    echo "Error: no target path specified. Use --help for usage."
    quit(1)

proc main() =
  let args = parseArgs()
  let target = args.target

  var files: seq[FileComplexity]

  if target.endsWith(".nim"):
    if not fileExists(target):
      echo fmt"Error: file not found: {target}"
      quit(1)
    files.add parseFile(target)
  elif dirExists(target):
    var nimFiles = collectNimFiles(target)
    nimFiles.sort()
    for f in nimFiles:
      files.add parseFile(f)
  else:
    echo fmt"Error: path not found: {target}"
    quit(1)

  # Sort files by total complexity descending
  files.sort(proc (a, b: FileComplexity): int =
    cmp(b.totalComplexity, a.totalComplexity)
  )

  if args.jsonOut:
    echo toJson(files).pretty()
  else:
    echo formatTextReport(files, args.topN, args.threshold)

main()
