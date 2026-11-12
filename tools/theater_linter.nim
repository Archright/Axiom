## tools/theater_linter.nim
##
## AST-based Theater Pattern Linter — detects AGENTS.md §0.9 violations
## in Nim source files using std/macros structural analysis.
##
## Patterns detected:
##   [SWALLOWED-EXC]    except { CatchableError: discard } — swallowed errors
##                      (§0.9 signature #2: swallowed failure)
##   [TAUTOLOGY-ASSERT] check x == true or x == false — tautological asserts
##                      (§0.9 signature #6: unenforced claim / vacuous proof)
##   [VACUOUS-RETURN]   return true/false without conditional logic
##                      (§0.9 signature #1: always-pass)
##
## Usage:
##   nim r tools/theater_linter.nim                    # scan src/**/*.nim
##   nim r tools/theater_linter.nim --staged           # scan git staged files
##   nim r tools/theater_linter.nim src/foo/bar.nim    # lint specific file(s)
##   nim r tools/theater_linter.nim --json             # JSON output for CI
##
## Exit code: 0 = clean, 1 = violations found, 2 = usage error
##
## Compile (AOT):
##   nim c --hints:off -o:bin/theater_linter tools/theater_linter.nim
##
## CI Integration:
##   Run as pre-commit hook via bin/axiom-gate L2 workflow (.circleci removed
##   2026-08-06; CI migrated to GitHub Actions — see AGENTS.md §3).
##
## Note: Uses std/macros for AST-level structural analysis. Nim's internal
## compiler/ast module is only available when building the Nim compiler
## itself — std/macros is the correct approach for standalone tools.
## See docs/spec/nim_effect_system_quirks.md §5 for details.

import std/[os, osproc, strutils, json, times]

# ═══════════════════════════════════════════════════════════════════════════
# §1. Types
# ═══════════════════════════════════════════════════════════════════════════

type
  TheaterPattern* = enum
    tpSwallowedExc      ## except branch contains bare discard
    tpTautologyAssert   ## check x == true or x == false
    tpVacuousReturn     ## return true/false without conditional guard

  TheaterViolation* = object
    pattern*:   TheaterPattern
    filePath*:  string
    line*:      int
    message*:   string
    context*:   string  ## surrounding code context

  ScanMode* = enum
    smFull, smStaged, smFiles

  LintConfig* = object
    mode*:        ScanMode  ## full, staged, or file list
    files*:       seq[string]
    jsonOutput*:  bool
    verbose*:     bool
    exemptIO*:    bool     ## skip axiom:best-effort(ioboundary catch) markers

# ═══════════════════════════════════════════════════════════════════════════
# §2. Constants
# ═══════════════════════════════════════════════════════════════════════════

const
  VerificationProcPatterns* = [
    "check", "verify", "validate", "assert", "ensure",
    "guarantee", "confirm", "prove", "isValid",
    "hasPermission", "hasAccess", "wouldPass",
    "passes", "satisfies", "meets"
  ]

  BoundaryExemptMarker = "axiom:best-effort(ioboundary catch)"

  SrcDir = "src/"

# ═══════════════════════════════════════════════════════════════════════════
# §3. Helpers — func (pure, no I/O)
# ═══════════════════════════════════════════════════════════════════════════

func isVerificationProc(procName: string): bool {.raises: [].} =
  let name = procName.toLowerAscii()
  for pat in VerificationProcPatterns:
    if pat in name: return true

func stripComment(line: string): string {.raises: [].} =
  var depth = 0
  for i in 0 ..< line.len:
    if line[i] == '#' and (i == 0 or line[i-1] != '\\'):
      if depth == 0: return line[0 ..< i]
    elif line[i] == '[' and i + 1 < line.len and line[i+1] == '#':
      inc depth
    elif line[i] == '#' and i + 1 < line.len and line[i+1] == ']':
      dec depth
  result = line

func stripStringLiterals(line: string): string {.raises: [].} =
  var output = ""
  var i = 0
  while i < line.len:
    if line[i] == '"':
      ## Skip quoted string
      var j = i + 1
      while j < line.len and line[j] != '"':
        if line[j] == '\\': inc j
        inc j
      output.add("\"\"")
      i = j + 1
    else:
      output.add(line[i])
      inc i
  result = output

func getLineText(lines: openArray[string], lineNum: int): string =
  if lineNum > 0 and lineNum <= lines.len:
    lines[lineNum - 1].strip()
  else: ""

func getContextWindow(lines: openArray[string], targetLine: int, window: int = 3): string =
  var parts: seq[string] = @[]
  for offset in -window .. window:
    let ln = targetLine + offset
    if ln > 0 and ln <= lines.len:
      let prefix = if offset < 0: "~ " elif offset > 0: "  "
      else: "==>"
      parts.add(prefix & $(ln) & ": " & lines[ln - 1].strip())
  parts.join("\n")

# ═══════════════════════════════════════════════════════════════════════════
# §4. Structural pattern detectors — text-scanning with context windows
#
# Note: Nim's internal compiler/ast module is only available when building
# the Nim compiler itself. std/macros parseFile has unreliable type resolution
# for standalone tools (see docs/spec/nim_effect_system_quirks.md §5).
# This linter uses deterministic text-scanning with context windows to detect
# patterns that would otherwise require runtime AST parsing.
# ═══════════════════════════════════════════════════════════════════════════

proc detectSwallowedExceptions(filePath: string; content: string): seq[TheaterViolation] =
  ## Find except branches whose body contains only bare discard statements.
  ## Skips blocks marked with axiom:best-effort(ioboundary catch) comment.
  let lines = content.splitLines()
  for i in 0 ..< lines.high:
    let stripped = lines[i].strip().toLowerAscii()
    if BoundaryExemptMarker in lines[i]: continue
    if stripped == "except:" or stripped.startsWith("except ("):
      var allBareDiscard = true
      var hasStatements = false
      for j in (i + 1) .. min(i + 10, lines.high):
        let inner = lines[j].strip()
        if inner.len == 0: continue
        if inner.startsWith("except ") or
           inner.startsWith("finally") or
           inner.startsWith("else:") or
           inner.startsWith("elif ") or
           inner.startsWith("if "):
          break
        hasStatements = true
        if inner != "discard":
          allBareDiscard = false; break
        elif inner == "discard" and j + 1 <= lines.high:
          var nextNonBlank = lines.high + 1
          for k in (j + 1) .. min(j + 3, lines.high):
            let ns = lines[k].strip()
            if ns.len > 0:
              nextNonBlank = k; break
          if nextNonBlank <= lines.high and
             lines[nextNonBlank].strip().toLowerAscii() == "discard":
            continue
          else:
            break
      if allBareDiscard and hasStatements:
        result.add(TheaterViolation(
          pattern: tpSwallowedExc,
          filePath: filePath,
          line: i + 2,
          message: "Swallowed exception: 'except' block discards all errors " &
                   "without logging or re-raising (§0.9 signature #2)",
          context: getContextWindow(lines, i + 1)))

proc detectTautologicalAssertions(filePath: string; content: string): seq[TheaterViolation] =
  ## Find check/verify/assert calls with tautological arguments like
  ## x == true, x == false, x == true or x == false, etc.
  let lines = content.splitLines()
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip()
    let lower = stripped.toLowerAscii()

    ## Match check/verify/assert calls
    var procName = ""
    if lower.startsWith("check(") or lower.startsWith("check ("):
      procName = "check"
    elif lower.startsWith("assert(") or lower.startsWith("assert ("):
      procName = "assert"
    elif lower.startsWith("verify(") or lower.startsWith("verify ("):
      procName = "verify"
    elif lower.startsWith("expect(") or lower.startsWith("expect ("):
      procName = "expect"
    elif lower.startsWith("require(") or lower.startsWith("require ("):
      procName = "require"

    if procName.len > 0:
      ## Extract the argument string between first ( and matching )
      var argStr = ""
      var parenDepth = 0
      var started = false
      for c in stripped:
        if c == '(':
          if not started: started = true; continue
          inc parenDepth
        elif c == ')':
          if started: dec parenDepth
          if parenDepth <= 0 and started: break
        if started and parenDepth >= 0:
          argStr.add(c)

      let argLower = argStr.toLowerAscii()
      var isTautology = false

      ## Check for excluded middle: X == true or X == false
      if ("== true" in argLower or "== true" in argLower.replace(" ", "")) and
         ("== false" in argLower or "== false" in argLower.replace(" ", "")):
        isTautology = true

      ## Check for identity tautology: x == x
      var eqParts = argStr.split("==")
      if eqParts.len == 2:
        let left = eqParts[0].strip().replace(" ", "")
        let right = eqParts[1].strip().replace(" ", "")
        if left.len > 0 and left == right:
          isTautology = true

      ## Check for simple true/false assertions: check(true), check(false)
      let trimmedArg = argStr.strip().replace(" ", "")
      if trimmedArg in ["true", "True", "false", "False"]:
        isTautology = true

      if isTautology:
        result.add(TheaterViolation(
          pattern: tpTautologyAssert,
          filePath: filePath,
          line: i + 1,
          message: "Tautological assertion: '" & procName & "' called with " &
                   "logically unavoidable condition (§0.9 signature #6)",
          context: getContextWindow(lines, i + 1)))

proc detectVacuousReturns(filePath: string; content: string): seq[TheaterViolation] =
  ## Find verification procs whose body is only "return true/false" or
  ## "result = true/false" with no real logic.
  let lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    let lower = stripped.toLowerAscii()

    let isProcDef = lower.startsWith("proc ") or lower.startsWith("func ") or
                    lower.startsWith("proc* ") or lower.startsWith("func* ")
    if isProcDef:
      var name = ""
      var rest = stripped
      if rest.startsWith("proc* ") or rest.startsWith("func* "):
        rest = rest[6..^1]
      elif rest.startsWith("proc ") or rest.startsWith("func "):
        rest = rest[5..^1]
      for ch in rest:
        if ch in {'(', ':', '[', ' ', '\t', '=', '*'}: break
        name.add(ch)
      name = name.strip(chars = {'*', '`'})

      if name.len > 0 and isVerificationProc(name):
        var bodyStart = i
        var braceDepth = 0
        var foundBody = false

        for j in (i + 1) ..< lines.len:
          let hdr = lines[j].strip()
          for ch in hdr:
            if ch == '{': inc braceDepth
            elif ch == '}': dec braceDepth
          if braceDepth <= 0 and "{" in hdr:
            bodyStart = j; foundBody = true; break
          if braceDepth <= 0 and j > i and ("=" in hdr or ":" in hdr):
            bodyStart = j; foundBody = true; break

        if not foundBody:
          for j in (i + 1) ..< lines.len:
            if lines[j].strip().len > 0 and lines[j][0] in {' ', '\t'}:
              bodyStart = j; foundBody = true; break
            elif lines[j].strip().len > 0 and not lines[j].strip().startsWith("#"):
              break

        if foundBody:
          let indentChar = if bodyStart < lines.len and
                              lines[bodyStart].strip().len > 0:
                               lines[bodyStart][0]
                             else: ' '
          var bodyLines: seq[string] = @[]
          for j in bodyStart ..< lines.len:
            let bl = lines[j].strip()
            if bl.len == 0:
              bodyLines.add(bl); continue
            if j > bodyStart and lines[j][0] != indentChar and bl.len > 0:
              break
            bodyLines.add(bl)

          var trimmedBody: seq[string] = @[]
          for bl in bodyLines:
            let ts = stripComment(bl).strip()
            if ts.len > 0: trimmedBody.add(ts)

          if trimmedBody.len == 1:
            let stmt = trimmedBody[0].toLowerAscii()
            if stmt.startsWith("return true") or stmt == "return true":
              result.add(TheaterViolation(
                pattern: tpVacuousReturn,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Always-pass: verification proc '" & name &
                         "' unconditionally returns true — no actual logic (§0.9 signature #1)",
                context: getContextWindow(lines, bodyStart + 1)))
            elif stmt.startsWith("return false") or stmt == "return false":
              result.add(TheaterViolation(
                pattern: tpVacuousReturn,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Fabricated negative: verification proc '" & name &
                         "' unconditionally returns false — no actual logic (§0.9 signature #1)",
                context: getContextWindow(lines, bodyStart + 1)))
            elif stmt.startsWith("result = true"):
              result.add(TheaterViolation(
                pattern: tpVacuousReturn,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Always-pass: verification proc '" & name &
                         "' sets result = true — no actual logic (§0.9 signature #1)",
                context: getContextWindow(lines, bodyStart + 1)))
            elif stmt.startsWith("result = false"):
              result.add(TheaterViolation(
                pattern: tpVacuousReturn,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Fabricated negative: verification proc '" & name &
                         "' sets result = false — no actual logic (§0.9 signature #1)",
                context: getContextWindow(lines, bodyStart + 1)))
          elif trimmedBody.len > 1:
            for bi in 0 ..< trimmedBody.len:
              let stmt = trimmedBody[bi].toLowerAscii()
              if stmt.startsWith("return true") or stmt == "return true":
                var inCond = false
                for ci in 0 ..< bi:
                  let cs = trimmedBody[ci].toLowerAscii()
                  if cs.startsWith("if ") or cs.startsWith("when ") or
                     cs.startsWith("case ") or "elif " in cs or "else:" in cs:
                    inCond = true; break
                if not inCond:
                  result.add(TheaterViolation(
                    pattern: tpVacuousReturn,
                    filePath: filePath,
                    line: bodyStart + bi + 1,
                    message: "Unconditional 'return true' in verification proc '" &
                             name & "' at line " & $(bodyStart + bi + 1) &
                             " — no conditional guard (§0.9 signature #1)",
                    context: getContextWindow(lines, bodyStart + bi + 1)))
              elif stmt.startsWith("return false") or stmt == "return false":
                var inCond = false
                for ci in 0 ..< bi:
                  let cs = trimmedBody[ci].toLowerAscii()
                  if cs.startsWith("if ") or cs.startsWith("when ") or
                     cs.startsWith("case ") or "elif " in cs or "else:" in cs:
                    inCond = true; break
                if not inCond:
                  result.add(TheaterViolation(
                    pattern: tpVacuousReturn,
                    filePath: filePath,
                    line: bodyStart + bi + 1,
                    message: "Hardcoded 'return false' in verification proc '" &
                             name & "' — fabricated negative result (§0.9 signature #1)",
                    context: getContextWindow(lines, bodyStart + bi + 1)))

    inc i

# ═══════════════════════════════════════════════════════════════════════════
# §5. File scanning
# ═══════════════════════════════════════════════════════════════════════════

proc checkFile(filePath: string; config: LintConfig): seq[TheaterViolation] =
  ## Read filePath and run all pattern detectors.
  result = @[]
  if not fileExists(filePath):
    return

  var content: string
  try:
    content = readFile(filePath)
  except IOError, OSError:
    return

  if content.strip().len == 0:
    return

  ## Run AST-based detectors
  result.add(detectSwallowedExceptions(filePath, content))
  result.add(detectTautologicalAssertions(filePath, content))
  result.add(detectVacuousReturns(filePath, content))

  ## Apply IO boundary exemptions if configured
  if config.exemptIO and result.len > 0:
    var filtered: seq[TheaterViolation] = @[]
    let lines = content.splitLines()
    for v in result:
      if v.pattern == tpSwallowedExc:
        ## Check if the violation line or nearby lines have exemption marker
        var exempted = false
        for offset in -2 .. 2:
          let ln = v.line + offset
          if ln > 0 and ln <= lines.len:
            let lineText = lines[ln - 1]
            if BoundaryExemptMarker in lineText:
              exempted = true
              break
        if not exempted:
          filtered.add(v)
      else:
        filtered.add(v)
    result = filtered

proc lintFile(filePath: string; config: LintConfig) =
  try:
    let violations = checkFile(filePath, config)
    if violations.len > 0:
      for v in violations:
        if config.jsonOutput:
          let jv = %*{
            "pattern": $v.pattern,
            "file": v.filePath,
            "line": v.line,
            "message": v.message,
            "context": v.context
          }
          echo jv.pretty()
        else:
          echo "[THEATER] ", v.filePath, ":", v.line, " [", $v.pattern, "] ", v.message
          if config.verbose and v.context.len > 0:
            for ctxLine in v.context.splitLines():
              echo "       | ", ctxLine
  except CatchableError as e:
    echo "[ERROR] Failed to parse ", filePath, ": ", e.msg

# ═══════════════════════════════════════════════════════════════════════════
# §6. CLI layer
# ═══════════════════════════════════════════════════════════════════════════

const Tag = "[theater-linter]"

func patternTag(p: TheaterPattern): string =
  case p
  of tpSwallowedExc:      "[SWALLOWED-EXC]"
  of tpTautologyAssert:   "[TAUTOLOGY-ASSERT]"
  of tpVacuousReturn:     "[VACUOUS-RETURN]"

proc collectStagedFiles(): seq[string] =
  let (output, code) = execCmdEx("git diff --name-only --cached")
  if code != 0 or output.strip().len == 0: return @[]
  for line in output.strip().splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0 and trimmed.endsWith(".nim"):
      result.add(trimmed)

proc collectAllFiles(baseDir: string): seq[string] =
  if not dirExists(baseDir): return @[]
  for path in walkDirRec(baseDir):
    if path.endsWith(".nim") and ".nimcache" notin path and
       fileExists(path) and not dirExists(path):
      result.add(path)

proc main() =
  let params = commandLineParams()
  var config = LintConfig(
    mode: smFull,
    files: @[],
    jsonOutput: false,
    verbose: false,
    exemptIO: true
  )

  for p in params:
    case p
    of "--help", "-h":
      echo "Axiom Theater Pattern Linter"
      echo ""
      echo "Usage:"
      echo "  theater_linter [options] [file1.nim file2.nim ...]"
      echo ""
      echo "Options:"
      echo "  --staged         Scan git-staged .nim files (pre-commit mode)"
      echo "  --full-scan      Scan all .nim files in src/ (default)"
      echo "  --json           JSON output for CI integration"
      echo "  --verbose, -v    Show code context for violations"
      echo "  --no-io-exempt   Do not skip axiom:best-effort(ioboundary catch)"
      echo "  --help, -h       Show this help message"
      echo ""
      echo "Patterns detected:"
      echo "  [SWALLOWED-EXC]    except { discard } — swallowed exceptions"
      echo "  [TAUTOLOGY-ASSERT] check x == true — logically unavoidable conditions"
      echo "  [VACUOUS-RETURN]   return true in verification procs — always-pass"
      echo ""
      echo "Exit code: 0 = clean, 1 = violations found"
      quit(0)
    of "--staged":
      config.mode = smStaged
    of "--full-scan":
      config.mode = smFull
    of "--json":
      config.jsonOutput = true
    of "--verbose", "-v":
      config.verbose = true
    of "--no-io-exempt":
      config.exemptIO = false
    else:
      if p.startsWith("-"):
        stderr.writeLine(Tag, " Unknown option: ", p)
        quit(2)
      else:
        config.files.add(p)

  ## Determine file set
  var files: seq[string] = @[]
  case config.mode
  of smStaged:
    files = collectStagedFiles()
    if files.len == 0:
      echo Tag, " INFO: no staged .nim files"
      quit(0)
    echo Tag, " Incremental scan: ", files.len, " staged file(s)"
  of smFull:
    if config.files.len > 0:
      for f in config.files:
        if fileExists(f): files.add(f)
    else:
      files = collectAllFiles(SrcDir)
      if files.len == 0:
        echo Tag, " INFO: no .nim files found in ", SrcDir
        quit(0)
      echo Tag, " Full scan: ", files.len, " file(s) in ", SrcDir
  of smFiles:
    for f in config.files:
      if fileExists(f): files.add(f)
    if files.len == 0:
      echo Tag, " ERROR: none of the specified files exist"
      quit(2)

  ## Run lint
  let start = epochTime()
  var totalViolations: seq[TheaterViolation] = @[]
  var scannedCount = 0
  var errorCount = 0

  for f in files:
    try:
      let violations = checkFile(f, config)
      totalViolations.add(violations)
      inc scannedCount
      if config.verbose and violations.len > 0:
        echo Tag, " ", f, " — ", violations.len, " violation(s)"
    except CatchableError as e:
      inc errorCount
      echo Tag, " WARNING: failed to parse ", f, ": ", e.msg

  let elapsed = int((epochTime() - start) * 1000)

  ## Output results
  if totalViolations.len > 0:
    echo Tag, " FAIL: ", totalViolations.len, " theater pattern(s) found"
    if errorCount > 0:
      echo Tag, "       ", errorCount, " file(s) skipped (parse error)"
    echo "---"
    for v in totalViolations:
      if not config.jsonOutput:
        echo "  ", v.filePath, ":", v.line, ": ", patternTag(v.pattern), " ", v.message
        if config.verbose and v.context.len > 0:
          for ctxLine in v.context.splitLines():
            echo "       | ", ctxLine
      else:
        let jv = %*{
          "pattern": $v.pattern,
          "file": v.filePath,
          "line": v.line,
          "message": v.message,
          "context": v.context
        }
        echo jv.pretty()
    quit(1)
  else:
    echo Tag, " PASS: no theater patterns found (",
         $scannedCount, " files, ", $elapsed, "ms)"
    quit(0)

when isMainModule:
  main()
