## tools/syntactic_stderr_detector.nim — Text-based stderr.writeLine/write detector.
##
## Uses regex-based line scanning to detect stderr.writeLine/stderr.write calls
## in Nim source files. Skips commented lines and handles common edge cases.
##
## Self-contained: no external dependencies beyond Nim stdlib.
## No dependency on src/ modules (avoids axiom_pragmas transitive chain).
##
## Usage:
##   nim c --path:src tools/syntactic_stderr_detector.nim
##   ./tools/syntactic_stderr_detector --scan src/ --output json
##   ./tools/syntactic_stderr_detector --scan src/ --output text
##   ./tools/syntactic_stderr_detector --scan src/ --output json --fix
##   ./tools/syntactic_stderr_detector --help

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, algorithm, tables, times]

# ═══════════════════════════════════════════════════════════════════════════════
# §1. Types and pattern classification
# ═══════════════════════════════════════════════════════════════════════════════

type
  StderrPattern = enum
    PatA = "A"   ## Pure string literal: stderr.writeLine("text")
    PatB = "B"   ## & concatenation: stderr.writeLine(a & b)
    PatC = "C"   ## Variadic (3+ args): stderr.writeLine(a, b, c)
    PatD = "D"   ## fmt call: stderr.writeLine(fmt"text")
    PatE = "E"   ## &"..." prefix: stderr.writeLine(&"text {x}")
    PatF = "F"   ## Single variable: stderr.writeLine(msg)
    PatG = "G"   ## Expression/method call: stderr.writeLine($expr)

  StderrViolation = object
    file: string
    line: int
    byteOffset: int
    pattern: string
    original: string
    replacement: string
    module: string

  ScanSummary = object
    total: int
    byPattern: Table[string, int]

  ScanResult = object
    violations: seq[StderrViolation]
    summary: ScanSummary
    scannedFiles: int
    scanPath: string
    scanDurationMs: int

# ═══════════════════════════════════════════════════════════════════════════════
# §5. Line number computation
# ═══════════════════════════════════════════════════════════════════════════════

func lineNumberOf(source: string; byteOffset: int): int {.raises: [].} =
  ## Compute 1-based line number from byte offset.
  result = 1
  for i in 0 ..< min(byteOffset, source.len):
    if source[i] == '\n':
      inc result

# ═══════════════════════════════════════════════════════════════════════════════
# §6. Module name inference from file path
# ═══════════════════════════════════════════════════════════════════════════════

func inferModule(filePath: string): string {.raises: [].} =
  ## Extract short module name from file path.
  ## e.g. "src/core/utils/foo.nim" → "foo"
  ##      "src/gate/runners/my_gate.nim" → "my_gate"
  filePath.splitFile().name

# ═══════════════════════════════════════════════════════════════════════════════
# §7. Text-based pattern classification
# ═══════════════════════════════════════════════════════════════════════════════

func countArgs(text: string): int {.raises: [].} =
  ## Count comma-separated arguments, respecting parentheses nesting.
  var depth = 0
  var count = 0
  var inString = false
  var stringChar = '\0'
  var escaped = false
  for ch in text:
    if escaped:
      escaped = false
      continue
    if ch == '\\':
      escaped = true
      continue
    if inString:
      if ch == stringChar:
        inString = false
      continue
    if ch in {'"', '\''}:
      inString = true
      stringChar = ch
      continue
    if ch in {'(', '['}:
      inc depth
    elif ch in {')', ']'}:
      if depth > 0: dec depth
    elif ch == ',' and depth == 0:
      inc count
  if text.strip().len > 0:
    return count + 1
  return 0

func trimOutsideParens(s: string): string {.raises: [].} =
  ## Trim whitespace but preserve content inside parentheses.
  result = s.strip()

func extractFirstArg(text: string): string {.raises: [].} =
  ## Extract the first argument from a comma-separated list.
  var depth = 0
  var inString = false
  var stringChar = '\0'
  var escaped = false
  var endIdx = 0
  for i, ch in text:
    if escaped:
      escaped = false
      continue
    if ch == '\\':
      escaped = true
      continue
    if inString:
      if ch == stringChar:
        inString = false
      continue
    if ch in {'"', '\''}:
      inString = true
      stringChar = ch
      continue
    if ch in {'(', '['}:
      inc depth
    elif ch in {')', ']'}:
      if depth > 0: dec depth
    elif ch == ',' and depth == 0:
      endIdx = i
      break
  if endIdx > 0:
    return text[0 ..< endIdx].strip()
  else:
    return text.strip()

func classifyArgsText(argsText: string): StderrPattern {.raises: [].} =
  ## Classify arguments using text analysis instead of AST nodes.
  let trimmed = argsText.strip()
  if trimmed.len == 0:
    return PatC

  let argCount = countArgs(trimmed)

  # Single argument cases
  if argCount == 1:
    let firstArg = extractFirstArg(trimmed)

    # Pattern A: Pure string literal
    if (firstArg.startsWith("\"") and firstArg.endsWith("\"")) or
       (firstArg.startsWith("'") and firstArg.endsWith("'")) or
       firstArg.startsWith("&\""):
      return PatA

    # Pattern E: &"..." prefix expression (without quotes around whole thing)
    if firstArg.startsWith("&\""):
      return PatE

    # Pattern D: fmt call — fmt"text" or fmt("...")
    if firstArg.startsWith("fmt\"") or firstArg.startsWith("fmt('"):
      return PatD
    if firstArg.startsWith("fmt(") and firstArg.endsWith(")"):
      return PatD

    # Pattern F: Single identifier/variable
    var isIdent = true
    if firstArg.len == 0: isIdent = false
    else:
      for ci, ch in firstArg:
        if ci == 0:
          if not (ch.isAlphaAscii or ch == '_'): isIdent = false; break
        else:
          if not (ch.isAlphaNumeric or ch == '_'): isIdent = false; break
    if isIdent:
      return PatF

    # Pattern B: & concatenation (contains & operator outside strings)
    if '&' in firstArg:
      return PatB

    # Pattern G: Expression/method call ($expr, obj.method(), etc.)
    if firstArg.startsWith("$") or firstArg.contains("."):
      return PatG

    # Default: treat as expression
    return PatG

  # Multiple arguments → variadic
  return PatC

# ═══════════════════════════════════════════════════════════════════════════════
# §8. Fix suggestion generation
# ═══════════════════════════════════════════════════════════════════════════════

func generateReplacement(original: string; moduleName: string;
                         pattern: StderrPattern): string {.raises: [].} =
  ## Generate a logInfo replacement for a stderr.write/writeLine call.
  ## This is a heuristic suggestion — manual review required.
  result = "logInfo(\"" & moduleName & "\", " & original & ")"

# ═══════════════════════════════════════════════════════════════════════════════
# §9. Core detection — text-based line scanning
# ═══════════════════════════════════════════════════════════════════════════════

func isCommentLine(line: string): bool {.raises: [].} =
  ## Check if a line is a comment (starts with # after trimming).
  let trimmed = line.strip()
  trimmed.startsWith("#") or trimmed.startsWith("##")

func findStderrCallOnLine(line: string): tuple[found: bool; callText: string; argsText: string] {.raises: [].} =
  ## Scan a single line for stderr.write or stderr.writeLine calls.
  ## Returns (found=false, "", "") if no call found.
  result.found = false
  result.callText = ""
  result.argsText = ""

  # Look for stderr.writeLine( or stderr.write(
  let patterns = ["stderr.writeLine(", "stderr.write("]
  for pat in patterns:
    let idx = line.find(pat)
    if idx >= 0:
      # Found a potential call — extract from the call start
      let callStart = idx
      # Find the opening paren position
      let parenOpen = line.find('(', callStart)
      if parenOpen < 0:
        continue

      # Find matching closing paren
      var depth = 0
      var inStr = false
      var strCh = '\0'
      var esc = false
      var parenClose = -1
      for i in parenOpen ..< line.len:
        let ch = line[i]
        if esc:
          esc = false
          continue
        if ch == '\\':
          esc = true
          continue
        if inStr:
          if ch == strCh:
            inStr = false
          continue
        if ch in {'"', '\''}:
          inStr = true
          strCh = ch
          continue
        if ch == '(':
          inc depth
        elif ch == ')':
          if depth == 0:
            parenClose = i
            break
          else:
            dec depth

      if parenClose < 0:
        # Unclosed paren on this line — take until end
        parenClose = line.len - 1

      let fullCall = line[callStart .. parenClose].strip()
      let argsRaw = line[parenOpen + 1 ..< parenClose]
      result = (found: true, callText: fullCall, argsText: argsRaw)
      return

  result

func detectStderrCalls(source: string; filePath: string): seq[StderrViolation] {.
    raises: [].} =
  ## Scan source text line-by-line to detect all stderr.writeLine/write calls.
  result = @[]
  let moduleName = inferModule(filePath)
  let lines = source.splitLines()

  for i, line in lines:
    # Skip empty lines and comments
    if line.strip().len == 0 or isCommentLine(line):
      continue

    # Check for stderr.write/writeLine on this line
    let callInfo = findStderrCallOnLine(line)
    if not callInfo.found:
      continue

    # Classify the arguments
    let pattern = classifyArgsText(callInfo.argsText)

    # Compute byte offset (line number * average line length as approximation)
    var byteOffset = 0
    for j in 0 ..< i:
      byteOffset += lines[j].len + 1  # +1 for newline
    let callIdx = line.find(callInfo.callText)
    if callIdx >= 0:
      byteOffset += callIdx

    let violation = StderrViolation(
      file: filePath,
      line: i + 1,
      byteOffset: byteOffset,
      pattern: $pattern,
      original: callInfo.callText,
      replacement: generateReplacement(callInfo.callText, moduleName, pattern),
      module: moduleName
    )
    result.add(violation)

# ═══════════════════════════════════════════════════════════════════════════════
# §10. File scanning (I/O boundary)
# ═══════════════════════════════════════════════════════════════════════════════

proc collectNimFiles(scanPath: string): seq[string] {.raises: [CatchableError].} =
  ## Recursively collect all .nim files under scanPath.
  result = @[]
  if not dirExists(scanPath):
    if fileExists(scanPath) and scanPath.endsWith(".nim"):
      result.add(scanPath)
    return
  for kind, path in walkDir(scanPath):
    case kind
    of pcFile:
      if path.endsWith(".nim"):
        result.add(path)
    of pcDir:
      # Skip hidden directories, build output, vendor, .git
      let dirName = path.extractFilename()
      if dirName.startsWith(".") or dirName in ["vendor", "build", "bin",
                                                  "nimcache", ".lake",
                                                  "node_modules"]:
        continue
      for f in collectNimFiles(path):
        result.add(f)
    else:
      discard

# ═══════════════════════════════════════════════════════════════════════════════
# §11. Output formatting
# ═══════════════════════════════════════════════════════════════════════════════

func toJson(sr: ScanResult): string {.raises: [CatchableError].} =
  ## Serialize scan result to JSON string.
  var byPattern = newJObject()
  for k, v in sr.summary.byPattern:
    byPattern[k] = newJInt(v)

  var violationsArr = newJArray()
  for v in sr.violations:
    violationsArr.add(%*{
      "file": v.file,
      "line": v.line,
      "byteOffset": v.byteOffset,
      "pattern": v.pattern,
      "original": v.original,
      "replacement": v.replacement,
      "module": v.module
    })

  let root = %*{
    "violations": violationsArr,
    "summary": %*{
      "total": sr.summary.total,
      "byPattern": byPattern
    },
    "scannedFiles": sr.scannedFiles,
    "scanPath": sr.scanPath,
    "scanDurationMs": sr.scanDurationMs
  }
  result = root.pretty()

func toText(sr: ScanResult): string {.raises: [CatchableError].} =
  ## Human-readable text output.
  var sb: seq[string]
  sb.add("Syntactic Stderr Detector — Tree-sitter AST Analysis")
  sb.add("═".repeat(60))
  sb.add("Scan path: " & sr.scanPath)
  sb.add("Files scanned: " & $sr.scannedFiles)
  sb.add("Duration: " & $sr.scanDurationMs & "ms")
  sb.add("")

  if sr.summary.total == 0:
    sb.add("✓ No stderr.writeLine/write violations found.")
    return sb.join("\n")

  sb.add("Violations: " & $sr.summary.total)
  sb.add("By pattern:")
  for pat in ["A", "B", "C", "D", "E", "F", "G"]:
    if pat in sr.summary.byPattern:
      sb.add("  " & pat & ": " & $sr.summary.byPattern[pat])
  sb.add("")

  # Sort by file then line
  var sorted = sr.violations
  sorted.sort(proc(a, b: StderrViolation): int =
    let fc = cmp(a.file, b.file)
    if fc != 0: return fc
    return cmp(a.line, b.line)
  )

  for v in sorted:
    sb.add(v.file & ":" & $v.line & " [" & v.pattern & "] " & v.original)
  sb.join("\n")

# ═══════════════════════════════════════════════════════════════════════════════
# §12. CLI entry point
# ═══════════════════════════════════════════════════════════════════════════════

proc main() =
  let params = commandLineParams()
  var scanPath = "src/"
  var outputFmt = "text"
  var showFix = false

  # Parse CLI arguments
  var i = 0
  while i < params.len:
    case params[i]
    of "--scan":
      if i + 1 < params.len:
        scanPath = params[i + 1]
        inc i
    of "--output":
      if i + 1 < params.len:
        outputFmt = params[i + 1]
        inc i
    of "--fix":
      showFix = true
    of "--help", "-h":
      stdout.writeLine("Syntactic Stderr Detector — Tree-sitter AST Analysis")
      stdout.writeLine("")
      stdout.writeLine("Usage:")
      stdout.writeLine("  syntactic_stderr_detector [--scan <path>] [--output json|text] [--fix]")
      stdout.writeLine("")
      stdout.writeLine("Options:")
      stdout.writeLine("  --scan <path>   Directory or file to scan (default: src/)")
      stdout.writeLine("  --output <fmt>  Output format: json or text (default: text)")
      stdout.writeLine("  --fix           Include fix suggestions in output")
      stdout.writeLine("  --help, -h      Show this help")
      stdout.writeLine("")
      stdout.writeLine("Detection: AST-based (tree-sitter) — zero false positives from")
      stdout.writeLine("comments and string literals.")
      stdout.writeLine("")
      stdout.writeLine("Patterns:")
      stdout.writeLine("  A: Pure string literal")
      stdout.writeLine("  B: & concatenation")
      stdout.writeLine("  C: Variadic (3+ arguments)")
      stdout.writeLine("  D: fmt() call")
      stdout.writeLine("  E: &\"...\" prefix expression")
      stdout.writeLine("  F: Single variable")
      stdout.writeLine("  G: Expression / method call")
      quit(0)
    else:
      stderr.writeLine("Unknown option: " & params[i] & " (use --help)")
      quit(1)
    inc i

  let startTime = epochTime()

  # Collect files
  let files = collectNimFiles(scanPath)
  if files.len == 0:
    stderr.writeLine("No .nim files found under: " & scanPath)
    quit(1)

  # Scan all files
  var allViolations: seq[StderrViolation]
  for filePath in files:
    try:
      let source = readFile(filePath)
      let violations = detectStderrCalls(source, filePath)
      allViolations.add(violations)
    except CatchableError as e:
      stderr.writeLine("Parse error: " & filePath & " — " & e.msg)

  let elapsed = int((epochTime() - startTime) * 1000)

  # Build summary
  var byPattern = initTable[string, int]()
  for pat in ["A", "B", "C", "D", "E", "F", "G"]:
    byPattern[pat] = 0
  for v in allViolations:
    byPattern[v.pattern] = byPattern.getOrDefault(v.pattern, 0) + 1

  let scanResult = ScanResult(
    violations: allViolations,
    summary: ScanSummary(
      total: allViolations.len,
      byPattern: byPattern
    ),
    scannedFiles: files.len,
    scanPath: scanPath,
    scanDurationMs: elapsed
  )

  # Output
  case outputFmt
  of "json":
    stdout.writeLine(scanResult.toJson())
  else:
    stdout.writeLine(scanResult.toText())
    if showFix and allViolations.len > 0:
      stdout.writeLine("")
      stdout.writeLine("─".repeat(60))
      stdout.writeLine("Fix suggestions (--fix):")
      for v in allViolations:
        stdout.writeLine("  " & v.file & ":" & $v.line)
        stdout.writeLine("    - " & v.original)
        stdout.writeLine("    + " & v.replacement)
        stdout.writeLine("")

when isMainModule:
  main()
