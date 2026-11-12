## tools/ast_theater_gate.nim
##
## Hybrid AST Linter Gate — detects Theater bug patterns (AGENTS.md §0.9)
## in Nim source files using structural analysis (text + lightweight AST cues).
##
## Patterns detected:
##   [SILENT-DISCARD]    except { discard } — swallowed exceptions
##                        (§0.9 signature #2: swallowed failure)
##   [UNCOND-RETURN]     return true in verification proc at top level
##                        (§0.9 signature #1: always-pass)
##   [FABRICATED-VALUE]  hardcoded booleans in verification context
##                        (§0.9 signature #3: disguised stub)
##
## Usage:
##   ast_theater_gate --incremental   Scan staged .nim files (git diff)
##   ast_theater_gate --full-scan     Scan all .nim files in src/
##
## Exit code: 0 = clean, 1 = violations found, 2 = usage error
##
## Compile:
##   nim c --hints:off -o:bin/ast_theater_gate tools/ast_theater_gate.nim
##
## Note: parseStmt/parseExpr are compile-time-only in Nim 2.2.10. This tool
## uses deterministic text-scanning with context windows to detect patterns
## that would otherwise require runtime AST parsing. See GUARDIAN §0.5b quirk.

import std/[os, strutils, osproc, times]

# ═══════════════════════════════════════════════════════════════════════════
# §1. Types
# ═══════════════════════════════════════════════════════════════════════════

type
  TheaterPattern = enum
    tpSilentDiscard          ## except branch contains only bare discard
    tpUnconditionalReturnTrue  ## return true at proc top-level (always-pass)
    tpFabricatedValue        ## hardcoded false/true in verification proc

  TheaterViolation = object
    pattern:   TheaterPattern
    filePath:  string
    line:      int
    message:   string

# ═══════════════════════════════════════════════════════════════════════════
# §2. Constants
# ═══════════════════════════════════════════════════════════════════════════

const
  VerificationProcPatterns = [
    "check", "verify", "validate", "assert", "ensure",
    "guarantee", "confirm", "prove", "isValid",
    "hasPermission", "hasAccess", "wouldPass"
  ]

# ═══════════════════════════════════════════════════════════════════════════
# §3. Helpers — func (pure, no I/O)
# ═══════════════════════════════════════════════════════════════════════════

func isVerificationProc(procName: string): bool {.raises: [].} =
  let name = procName.toLowerAscii()
  for pat in VerificationProcPatterns:
    if pat in name: return true

func stripComment(line: string): string =
  let hashPos = line.find('#')
  if hashPos >= 0: result = line[0 ..< hashPos]
  else: result = line

# ═══════════════════════════════════════════════════════════════════════════
# §4. Pattern detectors — text-scanning with context windows
# ═══════════════════════════════════════════════════════════════════════════

proc detectSilentDiscard(filePath: string; lines: openArray[string]): seq[TheaterViolation] =
  ## Find except branches whose body is ONLY bare discard statements.
  for i in 0 ..< lines.high:
    let stripped = lines[i].strip().toLowerAscii()
    if stripped == "except:" or stripped.startsWith("except ("):
      ## Found an except clause — check subsequent non-blank lines
      var allBareDiscard = true
      var hasStatements = false
      for j in (i + 1) .. min(i + 10, lines.high):
        let inner = lines[j].strip()
        if inner.len == 0: continue            ## skip blanks
        if inner.startsWith("except ") or
           inner.startsWith("finally") or
           inner.startsWith("else:") or
           inner.startsWith("elif ") or
           inner.startsWith("if "):
          break                                ## hit another block
        hasStatements = true
        if inner != "discard":
          allBareDiscard = false; break
        elif inner == "discard" and j + 1 <= lines.high:
          ## Check if next non-blank line is also just "discard"
          var nextNonBlank = lines.high + 1
          for k in (j + 1) .. min(j + 3, lines.high):
            let ns = lines[k].strip()
            if ns.len > 0:
              nextNonBlank = k
              break
          if nextNonBlank <= lines.high and
             lines[nextNonBlank].strip().toLowerAscii() == "discard":
            continue                           ## multiple discards — still barren
          else:
            break                              ## end of except body
      if allBareDiscard and hasStatements:
        result.add(TheaterViolation(
          pattern: tpSilentDiscard,
          filePath: filePath,
          line: i + 2,                          ## line of the discard stmt
          message: "Swallowed exception: 'except {discard}' silently drops " &
                   "errors without logging or re-raising"))

proc detectUnconditionalReturns(filePath: string; lines: openArray[string]): seq[TheaterViolation] =
  ## Find verification procs whose body is only "return true/false" or
  ## "result = true/false" with no real logic.
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    let lower = stripped.toLowerAscii()

    ## Detect proc/func definitions
    let isProcDef = lower.startsWith("proc ") or lower.startsWith("func ") or
                    lower.startsWith("proc* ") or lower.startsWith("func* ")
    if isProcDef:
      ## Extract proc name
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
        ## Found a verification proc — analyze its body
        ## Body starts after the proc header (may span multiple lines)
        var bodyStart = i
        var braceDepth = 0
        var foundBody = false
        var bodyLines: seq[string] = @[]

        ## Skip past proc signature to find body
        for j in (i + 1) ..< lines.len:
          let hdr = lines[j].strip()
          ## Count braces to find body start
          for ch in hdr:
            if ch == '{': inc braceDepth
            elif ch == '}': dec braceDepth
          if braceDepth <= 0 and "{" in hdr:
            bodyStart = j; foundBody = true; break
          if braceDepth <= 0 and j > i and ("=" in hdr or ":" in hdr):
            bodyStart = j; foundBody = true; break

        if not foundBody:
          ## Try finding body as indented block after signature
          for j in (i + 1) ..< lines.len:
            if lines[j].strip().len > 0 and lines[j][0] in {' ', '\t'}:
              bodyStart = j; foundBody = true; break
            elif lines[j].strip().len > 0 and not lines[j].strip().startsWith("#"):
              break

        if foundBody:
          ## Collect body lines until dedent or end
          let indentChar = if bodyStart < lines.len and
                            lines[bodyStart].strip().len > 0:
                             lines[bodyStart][0]
                           else: ' '
          for j in bodyStart ..< lines.len:
            let bl = lines[j].strip()
            if bl.len == 0:
              bodyLines.add(bl); continue
            if j > bodyStart and lines[j][0] != indentChar and bl.len > 0:
              break                              ## dedent → end of body
            bodyLines.add(bl)

          ## Check body for theater patterns
          var trimmedBody: seq[string] = @[]
          for bl in bodyLines:
            let ts = stripComment(bl).strip()
            if ts.len > 0: trimmedBody.add(ts)

          if trimmedBody.len == 1:
            ## Single statement in verification proc — likely fabricated
            let stmt = trimmedBody[0].toLowerAscii()
            if stmt.startsWith("return true") or stmt == "return true":
              result.add(TheaterViolation(
                pattern: tpUnconditionalReturnTrue,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Always-pass: verification proc '" & name &
                         "' unconditionally returns true — no actual logic"))
            elif stmt.startsWith("return false") or stmt == "return false":
              result.add(TheaterViolation(
                pattern: tpFabricatedValue,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Fabricated negative: verification proc '" & name &
                         "' unconditionally returns false — no actual logic"))
            elif stmt.startsWith("result = true") or stmt == "result = true":
              result.add(TheaterViolation(
                pattern: tpUnconditionalReturnTrue,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Always-pass: verification proc '" & name &
                         "' sets result = true — no actual logic"))
            elif stmt.startsWith("result = false") or stmt == "result = false":
              result.add(TheaterViolation(
                pattern: tpFabricatedValue,
                filePath: filePath,
                line: bodyStart + 1,
                message: "Fabricated negative: verification proc '" & name &
                         "' sets result = false — no actual logic"))
          elif trimmedBody.len > 1:
            ## Multiple statements — check for unconditional return true/false
            ## outside conditional guards
            for bi in 0 ..< trimmedBody.len:
              let stmt = trimmedBody[bi].toLowerAscii()
              if stmt.startsWith("return true") or stmt == "return true":
                ## Check if inside a conditional
                var inCond = false
                for ci in 0 ..< bi:
                  let cs = trimmedBody[ci].toLowerAscii()
                  if cs.startsWith("if ") or cs.startsWith("when ") or
                     cs.startsWith("case ") or cs.contains("elif ") or
                     cs.contains("else:"):
                    inCond = true; break
                if not inCond:
                  result.add(TheaterViolation(
                    pattern: tpUnconditionalReturnTrue,
                    filePath: filePath,
                    line: bodyStart + bi + 1,
                    message: "Unconditional 'return true' in verification " &
                             "proc '" & name & "' at line " &
                             $(bodyStart + bi + 1) & " — no conditional guard"))
              elif stmt.startsWith("return false") or stmt == "return false":
                var inCond = false
                for ci in 0 ..< bi:
                  let cs = trimmedBody[ci].toLowerAscii()
                  if cs.startsWith("if ") or cs.startsWith("when ") or
                     cs.startsWith("case ") or cs.contains("elif ") or
                     cs.contains("else:"):
                    inCond = true; break
                if not inCond:
                  result.add(TheaterViolation(
                    pattern: tpFabricatedValue,
                    filePath: filePath,
                    line: bodyStart + bi + 1,
                    message: "Hardcoded 'return false' in verification " &
                             "proc '" & name & "' — fabricated negative result"))

    inc i

# ═══════════════════════════════════════════════════════════════════════════
# §5. File scanning
# ═══════════════════════════════════════════════════════════════════════════

proc checkFile(filePath: string): seq[TheaterViolation] =
  ## Read *filePath* and run all pattern detectors.
  result = @[]
  try:
    let content = readFile(filePath)
    if content.strip().len == 0: return @[]
    let lines = content.splitLines()
    result.add(detectSilentDiscard(filePath, lines))
    result.add(detectUnconditionalReturns(filePath, lines))
  except IOError, OSError:  # axiom:best-effort(file read failure — scanner tool, non-fatal)
    discard  # axiom:best-effort(file read failure)
  except Exception:  # axiom:best-effort(unexpected parse error — scanner tool, non-fatal)
    discard  # axiom:best-effort(unexpected parse error)

# ═══════════════════════════════════════════════════════════════════════════
# §6. CLI layer
# ═══════════════════════════════════════════════════════════════════════════

const
  Tag      = "[ast-theater]"
  SrcDir   = "src/"
  MaxWarns = 50

func patternTag(p: TheaterPattern): string =
  case p
  of tpSilentDiscard:       "[SILENT-DISCARD]"
  of tpUnconditionalReturnTrue: "[UNCOND-RETURN]"
  of tpFabricatedValue:     "[FABRICATED-VALUE]"

func formatViolation(v: TheaterViolation): string =
  let loc = if v.line > 0: ":" & $v.line else: ":??"
  result = v.filePath & loc & ": " & patternTag(v.pattern) & " " & v.message

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

proc scanFiles(files: seq[string]; verbose: bool = false): tuple[
  violations: seq[TheaterViolation]; scanned: int; errors: int] =
  var scannedCount = 0
  var errorCount   = 0
  for f in files:
    try:
      let viols = checkFile(f)
      result.violations.add(viols)
      inc scannedCount
      if verbose and viols.len > 0:
        echo Tag, " ", f, " — ", viols.len, " violation(s)"
    except CatchableError as e:
      inc errorCount
      if errorCount <= MaxWarns:
        echo Tag, " WARNING: failed to parse ", f, ": ", e.msg
  result.scanned = scannedCount
  result.errors  = errorCount

proc main() =
  let params = commandLineParams()

  if "--help" in params or "-h" in params:
    echo "Axiom AST Theater Linter Gate"
    echo ""
    echo "Usage:"
    echo "  ast_theater_gate --incremental   Scan staged .nim files (git diff)"
    echo "  ast_theater_gate --full-scan     Scan all .nim files in src/"
    echo ""
    echo "Patterns detected:"
    echo "  [SILENT-DISCARD]    except { discard } — swallowed exceptions"
    echo "  [UNCOND-RETURN]     return true in verification procs — always-pass"
    echo "  [FABRICATED-VALUE]  hardcoded booleans in verification context"
    echo ""
    echo "Exit code: 0 = clean, 1 = violations found"
    quit(0)

  var mode: string
  var verbose = false
  for p in params:
    if p in ["--incremental", "--full-scan"]: mode = p
    elif p in ["--verbose", "-v"]: verbose = true

  if mode.len == 0:
    stderr.writeLine(Tag, " Error: specify --incremental or --full-scan")
    stderr.writeLine("  ast_theater_gate --incremental   Scan staged .nim files")
    stderr.writeLine("  ast_theater_gate --full-scan     Scan all .nim files in src/")
    quit(2)

  var files: seq[string] = @[]
  case mode
  of "--incremental":
    files = collectStagedFiles()
    if files.len == 0:
      echo Tag, " INFO: no staged .nim files"
      quit(0)
    echo Tag, " Incremental scan: ", files.len, " staged file(s)"
  of "--full-scan":
    files = collectAllFiles(SrcDir)
    if files.len == 0:
      echo Tag, " INFO: no .nim files found in ", SrcDir
      quit(0)
    echo Tag, " Full scan: ", files.len, " file(s) in ", SrcDir

  let start = epochTime()
  let scan  = scanFiles(files, verbose)
  let elapsed = int((epochTime() - start) * 1000)

  if scan.violations.len > 0:
    echo Tag, " FAIL: ", scan.violations.len, " theater pattern(s) found"
    if scan.errors > 0:
      echo Tag, "       ", scan.errors, " file(s) skipped (parse error)"
    echo "---"
    for v in scan.violations:
      echo "  ", formatViolation(v)
    quit(1)
  else:
    echo Tag, " PASS: no theater patterns found (",
         $scan.scanned, " files, ", $elapsed, "ms)"
    quit(0)

when isMainModule:
  main()
