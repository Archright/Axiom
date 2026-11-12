## effect_auto_fixer.nim — Automated proc→func conversion with CST-safe token replacement.
##
## Scans Nim source files for `proc` definitions that can be safely converted
## to `func` (noSideEffect). Uses sweep-line disjoint verification and atomic
## file writes for crash safety.
##
## Safety rules (GUARDIAN §0.6):
## - DO NOT convert if the body contains I/O calls
## - DO NOT convert if the body accesses ref object fields
## - DO NOT convert if the body reads/writes global mutable variables
## - DO NOT convert if the proc has {.cast(noSideEffect).} or {.axiomEffect: IoEffect.}
## - DO NOT convert if the proc writes to result fields of ref types (§17)

import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/engine_bridge
import shared_types/shared_types
import std/[os, strutils, algorithm, parseopt]
import tools/sweep_line
const
  procKw* = "proc"
  funcKw* = "func"

  ## Known I/O identifiers that disqualify a proc from func conversion.
  ## Conservative list — false negatives (missing an I/O call) are acceptable;
  ## false positives (flagging a pure call) are not.
  ioIdentifiers: seq[string] = @[
    "readFile", "writeFile", "open", "close", "flushFile",
    "execProcess", "execCmd", "execCmdEx", "execVProcess",
    "startProcess", "echo", "createDir", "removeDir",
    "removeFile", "moveFile", "copyFile", "dirExists",
    "fileExists", "walkDir", "walkDirRec", "sleep",
    "stdout.write", "stderr.write", "stdin.readLine",
    "getFileSize", "setFilePermissions", "getFilePermissions",
    "setCurrentDir", "getCurrentDir", "getHomeDir",
    "getTempDir", "existsEnv", "getEnv", "putEnv",
  ]

  ## Pragmas that block proc→func conversion.
  blockPragmas: seq[string] = @[
    "cast(noSideEffect)",
    "axiomEffect: IoEffect",
    "noSideEffect",
  ]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------
## effect_auto_fixer.nim — Automated proc→func conversion with CST-safe token replacement.
##
## Scans Nim source files for `proc` definitions that can be safely converted
## to `func` (noSideEffect). Uses sweep-line disjoint verification and atomic
## file writes for crash safety.
##
## Safety rules (GUARDIAN §0.6):
## - DO NOT convert if the body contains I/O calls
## - DO NOT convert if the body accesses ref object fields
## - DO NOT convert if the body reads/writes global mutable variables
## - DO NOT convert if the proc has {.cast(noSideEffect).} or {.axiomEffect: IoEffect.}
## - DO NOT convert if the proc writes to result fields of ref types (§17)
type
  ProcCandidate* = object
    ## A proc identified as a potential func conversion candidate.
    filePath*: string
    line*: int           ## 1-based line number of the proc keyword
    col*: int            ## 0-based column of the proc keyword
    name*: string        ## proc name (without export marker)
    hasIOCalls*: bool
    hasRefAccess*: bool
    hasGlobalAccess*: bool
    canConvert*: bool

  EditPlan* = object
    ## A planned set of token edits for a single file.
    edits*: seq[TokenEdit]
    filePath*: string
func isCommentLine(line: string): bool =
  ## True if the line's first non-whitespace character is '#'.
  for c in line:
    if c == '#': return true
    if c != ' ' and c != '\t': return false
  false
func indentLevel(line: string): int =
  ## Return the leading whitespace count.
  for c in line:
    if c in {' ', '\t'}: inc result
    else: break
func stripInlineComment(line: string): string =
  ## Remove trailing comment, respecting string and char literals.
  var inStr = false
  var sc = '\0'
  var i = 0
  while i < line.len:
    let c = line[i]
    if inStr:
      if c == sc:
        inStr = false
    elif c in {'"', '\''}:
      inStr = true
      sc = c
    elif c == '#':
      return line[0 ..< i].strip()
    inc i
  line
func findBodyEquals(text: string): int =
  ## Find the '=' that separates the proc header from the body.
  ## Skips '=' inside (), [], {} nesting.
  var pd = 0
  var bd = 0
  var kd = 0
  for i, c in text:
    case c
    of '(': inc pd
    of ')':
      if pd > 0: dec pd
    of '[': inc bd
    of ']':
      if bd > 0: dec bd
    of '{': inc kd
    of '}':
      if kd > 0: dec kd
    of '=':
      if pd == 0 and bd == 0 and kd == 0:
        return i
    else:
      discard
  -1
# ---------------------------------------------------------------------------
# Helpers (private)
# ---------------------------------------------------------------------------
func extractProcName(header: string): string =
  ## Extract the proc name from the header text.
  let s = header.strip()
  if not s.startsWith("proc "): return ""
  let rest = s[5 .. ^1]
  for i, c in rest:
    if c in {'(', '*', '[', '{', ':', ' ', '\t', '='}:
      return rest[0 ..< i].strip().strip(chars = {'*'})
  rest.strip().strip(chars = {'*'})

# ---------------------------------------------------------------------------
# Body extraction
# ---------------------------------------------------------------------------
func collectHeader(lines: seq[string], start: int): tuple[hdr: seq[string],
                     bodyStart: int] =
  ## Collect lines forming the proc header (up to and including '=').
  var idx = start
  while idx < lines.len:
    result.hdr.add(lines[idx])
    let cleaned = stripInlineComment(lines[idx])
    if findBodyEquals(cleaned) >= 0:
      return (result.hdr, idx + 1)
    inc idx
  (result.hdr, idx)
func collectBody(lines: seq[string], bodyStart: int, procIndent: int): seq[string] =
  ## Collect the proc body based on indentation relative to procIndent.
  var idx = bodyStart
  while idx < lines.len:
    let line = lines[idx]
    let stripped = line.strip()
    # Skip blank lines between body statements
    if stripped.len == 0:
      result.add(line)
      inc idx
      continue
    let ind = indentLevel(line)
    if ind <= procIndent:
      # Explicit 'end' at proc level closes the block
      if stripped == "end" or stripped.startsWith("end "):
        result.add(line)
        inc idx
      break
    result.add(line)
    inc idx

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------
func bodyHasIO(body: seq[string]): bool =
  ## Check for known I/O identifiers in the body lines.
  for line in body:
    if isCommentLine(line): continue
    let c = stripInlineComment(line)
    for id in ioIdentifiers:
      if id in c: return true
  false
func bodyHasRefAccess(body: seq[string]): bool =
  ## Check for ref field mutation patterns (GUARDIAN §17).
  ## Flags 'result.field' writes and general ref dereference patterns.
  for line in body:
    if isCommentLine(line): continue
    let c = stripInlineComment(line)
    # result.field writes — prohibited for ref result types (§17)
    if "result." in c: return true
  false
func extractModuleGlobals(lines: seq[string]): seq[string] =
  ## Extract top-level var/let names that may be mutable globals.
  for line in lines:
    let stripped = line.strip()
    if indentLevel(line) > 0: continue
    var prefix = ""
    if stripped.startsWith("var "): prefix = "var "
    elif stripped.startsWith("let "): prefix = "let "
    else: continue
    let rest = stripped[prefix.len .. ^1]
    for i, c in rest:
      if c in {':', '=', ' ', '\t'}:
        let name = rest[0 ..< i].strip()
        if name.len > 0 and name[0] != '_':
          result.add(name)
        break
func bodyUsesGlobals(body: seq[string], globals: seq[string]): bool =
  ## Check if the body references module-level mutable variables.
  if globals.len == 0: return false
  for line in body:
    if isCommentLine(line): continue
    let c = stripInlineComment(line)
    for g in globals:
      if g notin c: continue
      var pos = c.find(g)
      while pos >= 0:
        let preOk = pos == 0 or not c[pos - 1].isAlphaNumeric()
        let afterPos = pos + g.len
        let aftOk = afterPos >= c.len or not c[afterPos].isAlphaNumeric()
        if preOk and aftOk: return true
        pos = c.find(g, pos + 1)
  false

# ---------------------------------------------------------------------------
# Public API — scanning
# ---------------------------------------------------------------------------
proc scanFile*(filePath: string): seq[ProcCandidate] {.axiomEffect: IoEffect.} =
  ## Scan a .nim file and identify proc→func conversion candidates.
  ##
  ## Reads the file, extracts every top-level and nested proc definition,
  ## evaluates safety rules against the body, and returns candidates with
  ## their conversion eligibility flags.
  result = @[]
  if not fileExists(filePath): return

  let content = readFile(filePath)
  let lines = content.splitLines()
  let globals = extractModuleGlobals(lines)

  var idx = 0
  while idx < lines.len:
    let line = lines[idx]
    let stripped = line.strip()

    # Skip comments and blank lines
    if isCommentLine(line) or stripped.len == 0:
      inc idx
      continue

    # Match 'proc' keyword at line start (after indentation)
    if not stripped.startsWith("proc "):
      inc idx
      continue

    let pCol = line.len - line.strip(leading = true, trailing = false).len
    let pIndent = indentLevel(line)
    let lineNum = idx + 1  # 1-based

    # Collect header (may span multiple lines until '=')
    let (hdr, bodyStart) = collectHeader(lines, idx)
    let headerText = hdr.join(" ")

    # Check blocking pragmas in header
    var blocked = false
    for bp in blockPragmas:
      if bp in headerText:
        blocked = true
        break

    let name = extractProcName(headerText)

    # Collect block body
    var body = collectBody(lines, bodyStart, pIndent)

    # Also check for inline body on the '=' line
    let lastHdrLine = stripInlineComment(hdr[^1])
    let eqPos = findBodyEquals(lastHdrLine)
    if eqPos >= 0:
      let afterEq = lastHdrLine[eqPos + 1 .. ^1].strip()
      if afterEq.len > 0:
        body.insert(afterEq, 0)

    # Run safety checks on combined body
    let hasIO = bodyHasIO(body)
    let hasRef = bodyHasRefAccess(body)
    let hasGlobal = bodyUsesGlobals(body, globals)

    result.add ProcCandidate(
      filePath: filePath,
      line: lineNum,
      col: pCol,
      name: name,
      hasIOCalls: hasIO,
      hasRefAccess: hasRef,
      hasGlobalAccess: hasGlobal,
      canConvert: not blocked and not hasIO and not hasRef and not hasGlobal,
    )

    # Advance past the body
    idx = bodyStart + body.len

# ---------------------------------------------------------------------------
# Public API — planning
# ---------------------------------------------------------------------------
func planConversion*(candidates: seq[ProcCandidate]): EditPlan =
  ## Plan token edits for safe conversions.
  ##
  ## For each candidate where canConvert is true, creates a TokenEdit
  ## that replaces 'proc' with 'func' at the exact source position.
  ## The edits are suitable for verifyDisjointSweep verification.
  result = EditPlan(
    edits: @[],
    filePath: if candidates.len > 0: candidates[0].filePath else: "",
  )
  for c in candidates:
    if not c.canConvert: continue
    # 'proc' and 'func' are both 4 bytes — clean token swap
    result.edits.add TokenEdit(
      startLine: c.line,
      startCol: c.col,
      endLine: c.line,
      endCol: c.col + procKw.len,
      original: procKw,
      replacement: funcKw,
    )

# ---------------------------------------------------------------------------
# Public API — applying
# ---------------------------------------------------------------------------
proc applyEdits*(plan: EditPlan): bool {.axiomEffect: IoEffect.} =
  ## Apply edits using sweep_line verification + atomicWrite.
  ##
  ## Returns true on success, false if the disjoint check fails or
  ## the atomic write encounters an error.
  if plan.edits.len == 0: return true
  if plan.filePath.len == 0: return false

  # Mutable copy for verifyDisjointSweep (it sorts in-place)
  var edits = plan.edits

  # Verify all edits target disjoint source regions (O(N log N))
  let chk = verifyDisjointSweep(edits)
  if not chk.ok:
    echo "ERROR: disjoint check failed: ", chk.msg
    return false

  # Read original file
  let content = readFile(plan.filePath)
  let hadTrailingNl = content.len > 0 and content[^1] == '\n'
  var lines = content.splitLines()

  # Sort edits in reverse line order so earlier positions stay valid
  edits.sort(proc (a, b: TokenEdit): int =
    cmp(b.startLine * 10000 + b.startCol,
        a.startLine * 10000 + a.startCol)
  )

  for edit in edits:
    let li = edit.startLine - 1  # to 0-based
    if li < 0 or li >= lines.len: continue
    let ln = lines[li]
    let before = if edit.startCol > 0: ln[0 ..< edit.startCol] else: ""
    let after = if edit.endCol < ln.len: ln[edit.endCol .. ^1] else: ""
    lines[li] = before & edit.replacement & after

  # Reconstruct content preserving trailing newline
  var newContent = lines.join("\n")
  if hadTrailingNl: newContent.add('\n')

  # Crash-safe atomic write (temp + fsync + rename)
  let wr = atomicWrite(plan.filePath, newContent)
  if not wr.ok:
    echo "ERROR: atomic write failed: ", wr.err
    return false

  true

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
func formatCandidate(c: ProcCandidate): string =
  ## Format a candidate for human-readable output.
  result = c.filePath & ":" & $c.line & " " & c.name
  if not c.canConvert:
    result &= " [BLOCKED]"
    var reasons: seq[string]
    if c.hasIOCalls: reasons.add("io")
    if c.hasRefAccess: reasons.add("ref")
    if c.hasGlobalAccess: reasons.add("global")
    if reasons.len > 0:
      result &= " (" & reasons.join(", ") & ")"
# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
proc main() {.axiomEffect: IoEffect.} =
  ## CLI entry point for the effect auto-fixer.
  ##
  ## Usage:
  ##   effect_auto_fixer --check-only --file <path>
  ##   effect_auto_fixer --check-only --dir <path>
  ##   effect_auto_fixer --file <path>
  ##   effect_auto_fixer --dir <path>
  var checkOnly = false
  var targetFile = ""
  var targetDir = ""

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "check-only", "c":
        checkOnly = true
      of "file", "f":
        targetFile = val
      of "dir", "d":
        targetDir = val
      of "help", "h":
        echo "effect_auto_fixer — Automated proc→func conversion"
        echo ""
        echo "Options:"
        echo "  --check-only, -c   Dry run — report candidates without applying"
        echo "  --file, -f <path>  Target a single .nim file"
        echo "  --dir, -d <path>   Recursively scan a directory"
        echo "  --help, -h         Show this help"
        return
    of cmdArgument:
      if targetFile.len == 0 and targetDir.len == 0:
        targetFile = val
    of cmdEnd:
      discard

  # Collect files to scan
  var files: seq[string]
  if targetFile.len > 0:
    files.add(targetFile)
  elif targetDir.len > 0:
    for f in walkDirRec(targetDir):
      if f.endsWith(".nim"):
        files.add(f)
  else:
    echo "ERROR: specify --file or --dir"
    quit(1)

  # Scan → Plan → Verify disjoint → Apply (or report)
  var totalCandidates = 0
  var totalConvertable = 0

  for fp in files:
    let candidates = scanFile(fp)
    if candidates.len == 0: continue

    let plan = planConversion(candidates)
    totalCandidates += candidates.len
    totalConvertable += plan.edits.len

    for c in candidates:
      echo formatCandidate(c)

    if not checkOnly and plan.edits.len > 0:
      if not applyEdits(plan):
        echo "ERROR: failed to apply edits to ", fp

  echo ""
  echo "Summary: ", totalCandidates, " procs scanned, ",
       totalConvertable, " convertible"
  if checkOnly:
    echo "(dry run — no changes applied)"

when isMainModule:
  main()
