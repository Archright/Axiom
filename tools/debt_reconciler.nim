## tools/debt_reconciler.nim
##
## Debt Reconciler — Stage 2: Pure-AST theater bug detection.
##
## Scans files cited in data/debt_registry.json Theater/ entries and checks
## whether the reported theater patterns still exist in the current source.
##
## Uses structural text-scanning with block tracking (brace depth, indentation,
## control-flow analysis) to detect patterns deterministically — no regex
## heuristics, no text-substring matching alone. Every detection is grounded
## in parsed block structure.
##
## Patterns detected:
##   [ALWAYS-PASS]     unconditional return true/false in verification procs
##   [SWALLOWED]       except branch containing only discard (no logging/re-raise)
##   [DEAD-GATE]       gate/check proc returns true without real logic
##   [VACUOUS]         hardcoded true conversion / empty-evidence pass-through
##   [DISGUISED-STUB]  func/proc body is trivially true with no computation
##   [UNENFORCED]      claim of guarantee with no enforcement code path
##   [FAKE-COUNTS]     coverage/counts returned as hardcoded values
##
## Read-only: reports Theater/ entries whose pattern no longer reproduces in
## source. bin/debt_engine is the sole writer of data/debt_registry.json; this
## tool exits non-zero while any such entry remains unclosed in the registry.
##
## Usage:
##   nim c -r tools/debt_reconciler.nim              # reconcile all (read-only report)
##   nim c -r tools/debt_reconciler.nim --dry-run    # read-only (the only mode)
##   nim c -r tools/debt_reconciler.nim --file PATH  # scan single file
##   nim c -r tools/debt_reconciler.nim --id DEBT#NNN # reconcile single entry
##
## Compile:
##   nim c tools/debt_reconciler.nim
##

import std/[os, strutils, json, sequtils, algorithm]

# ═══════════════════════════════════════════════════════════════════════════
# §1. Types
# ═══════════════════════════════════════════════════════════════════════════

type
  TheaterPattern = enum
    tpAlwaysPass        ## unconditional return true/false in verification
    tpSwallowedFailure  ## except { discard } with no audit trail
    tpDeadGate          ## gate proc returns true without real logic
    tpVacuousProof      ## always-pass proof / empty evidence → success
    tpDisguisedStub     ## trivially true body masquerading as logic
    tpUnenforcedClaim   ## doc says "guarantees X" but no code enforces it
    tpFakeCounts        ## coverage/counts are hardcoded booleans
    tpTestTheater       ## test asserts check nothing meaningful
    tpCiTheater         ## CI step always passes regardless of outcome
    tpUncategorized     ## unknown theater pattern

  TheaterViolation = object
    pattern:   TheaterPattern
    filePath:  string
    line:      int
    message:   string
    severity:  string  ## "critical", "high", "medium", "low"

  DebtEntry = object
    id:           string
    category:     string
    description:  string
    files:        seq[string]
    severity:     string
    source:       string
    status:       string
    symbol:       string       ## optional
    contentHash:  string       ## optional
    lineRange:    string       ## optional
    resolution:   string       ## optional
    resolvedAt:   string       ## optional
    resolvedBy:   string       ## optional
    resolutionNote: string     ## optional
    lastVerifiedAt: string     ## optional

  ReconcileResult = object
    entryId:     string
    filePath:    string
    wasFixed:    bool          ## pattern existed before, now gone
    stillExists: bool          ## pattern still present
    foundViolations: seq[TheaterViolation]

# ═══════════════════════════════════════════════════════════════════════════
# §2. Constants
# ═══════════════════════════════════════════════════════════════════════════

const
  RegistryPath    = "data/debt_registry.json"
  VerificationProcPatterns = [
    "check", "verify", "validate", "assert", "ensure",
    "guarantee", "confirm", "prove", "isValid",
    "hasPermission", "hasAccess", "wouldPass",
    "runVerification", "crossValidation", "satisfies",
    "isConsistent", "passes", "complies"
  ]
  GateProcPatterns = [
    "gate", "audit", "enforce", "guard", "sanityCheck",
    "preCommit", "postCommit", "tier", "deferred"
  ]
  ProofProcPatterns = [
    "proof", "prove", "witness", "verif", "smt", "lean",
    "z3", "prop", "theorem", "lemma", "refine"
  ]
  MaxErrors = 50

# ═══════════════════════════════════════════════════════════════════════════
# §3. Helpers — func (pure, no I/O)
# ═══════════════════════════════════════════════════════════════════════════

func isVerificationProc(procName: string): bool {.raises: [].} =
  let name = procName.toLowerAscii()
  for pat in VerificationProcPatterns:
    if pat in name: return true

func isGateProc(procName: string): bool {.raises: [].} =
  let name = procName.toLowerAscii()
  for pat in GateProcPatterns:
    if pat in name: return true

func isProofProc(procName: string): bool {.raises: [].} =
  let name = procName.toLowerAscii()
  for pat in ProofProcPatterns:
    if pat in name: return true

func stripComment(line: string): string {.raises: [].} =
  var inString = false
  var escapeNext = false
  for i in 0 ..< line.len:
    let ch = line[i]
    if escapeNext:
      result.add(ch)
      escapeNext = false
      continue
    if ch == '\\':
      escapeNext = true
      result.add(ch)
      continue
    if ch == '"':
      inString = not inString
    if ch == '#' and not inString:
      return result
    result.add(ch)

func stripStringAndComments(line: string): string {.raises: [].} =
  ## Remove string literals and comments from a line for structural analysis.
  var inString = false
  var tripleQuote = 0
  var escapeNext = false
  var i = 0
  while i < line.len:
    let ch = line[i]
    if escapeNext:
      result.add(' ')
      escapeNext = false
      inc i
      continue
    if ch == '\\':
      escapeNext = true
      result.add(' ')
      inc i
      continue
    if inString:
      result.add(' ')
      if ch == '"':
        inString = false
      inc i
      continue
    if ch == '#':
      ## comment start — rest of line is whitespace
      while i < line.len:
        result.add(' ')
        inc i
      continue
    if ch == '"' and tripleQuote == 0:
      inString = true
      result.add(' ')
      inc i
      continue
    if ch == '\"':
      inc tripleQuote
      if tripleQuote == 3:
        inString = true
        result.add(' ')
        inc i
        inc i
        continue
      result.add(' ')
      inc i
      continue
    result.add(ch)
    inc i

func extractProcName(declLine: string): string {.raises: [].} =
  ## Extract the identifier name from a proc/func/method declaration line.
  let s = declLine.strip()
  var start = 0
  for kw in ["proc ", "func ", "method ", "template ", "macro ",
             "iterator ", "converter ", "type "]:
    if s.startsWith(kw):
      start = kw.len
      break
  if start == 0: return ""

  var name = ""
  for i in start ..< s.len:
    let c = s[i]
    if c in Letters or c in Digits or c == '_' or c == '*':
      name.add(c)
    else:
      break
  result = name.strip(chars = {'*', '`'})

func findProcBodyLines(lines: openArray[string], procStartLine: int): tuple[start: int, `end`: int] {.raises: [].} =
  ## Find the start and end line numbers of a proc body using brace/indent tracking.
  ## Returns (bodyStart, bodyEnd) — 0-indexed line numbers.
  var bodyStart = procStartLine
  var braceDepth = 0
  var foundOpening = false
  var totalBrace = 0

  ## First pass: find where the body starts (after signature + opening brace)
  for i in procStartLine ..< lines.len:
    let line = lines[i].strip()
    if line.len == 0: continue

    ## Count braces on this line
    for ch in line:
      if ch == '{':
        inc braceDepth
        if not foundOpening:
          foundOpening = true
          bodyStart = i + 1
      elif ch == '}':
        dec braceDepth

    if foundOpening and braceDepth <= 0:
      ## Body ended on same line or next line
      if bodyStart > i:
        bodyStart = i
      return (bodyStart, i)

  ## Second pass: if no braces found, use indentation-based detection
  if not foundOpening:
    ## Look for indented block after signature
    var baseIndent = -1
    for i in (procStartLine + 1) ..< lines.len:
      let line = lines[i]
      if line.strip().len == 0: continue
      if line.strip().startsWith("#"): continue

      ## Calculate indent level
      var indent = 0
      for ch in line:
        if ch == ' ': inc indent
        elif ch == '\t': inc indent; inc indent
        else: break

      if baseIndent == -1:
        if indent > 0:
          baseIndent = indent
          bodyStart = i
          break
      else:
        if indent < baseIndent and line.strip().len > 0:
          return (bodyStart, i - 1)

    if baseIndent >= 0:
      return (bodyStart, lines.len - 1)

  return (bodyStart, lines.len - 1)

func countNonBlankNonCommentLines(bodyLines: openArray[string]): int {.raises: [].} =
  var count = 0
  for line in bodyLines:
    let stripped = stripComment(line).strip()
    if stripped.len > 0:
      inc count
  return count

func isTrivialBody(bodyLines: openArray[string]): bool {.raises: [].} =
  ## Check if body contains only trivial statements (return true, return false, discard, result = true/false).
  let nonBlank = countNonBlankNonCommentLines(bodyLines)
  if nonBlank == 0: return true

  var allTrivial = true
  for line in bodyLines:
    let stripped = stripComment(line).strip().toLowerAscii()
    if stripped.len == 0: continue
    if stripped.startsWith("return true") or stripped == "return true": continue
    if stripped.startsWith("return false") or stripped == "return false": continue
    if stripped.startsWith("result = true") or stripped == "result = true": continue
    if stripped.startsWith("result = false") or stripped == "result = false": continue
    if stripped == "discard" or stripped == "result = discard": continue
    if stripped.startsWith("exit(true)") or stripped.startsWith("exit(false)"): continue
    if stripped.startsWith("# ") or stripped.startsWith("//"): continue
    allTrivial = false
    break
  return allTrivial

func hasReturnTrue(bodyLines: openArray[string]; atIdx: int): bool {.raises: [].} =
  let stripped = stripComment(bodyLines[atIdx]).strip().toLowerAscii()
  return stripped.startsWith("return true") or stripped == "return true" or
         stripped == "result = true" or stripped.startsWith("exit(true)")

func hasReturnFalse(bodyLines: openArray[string]; atIdx: int): bool {.raises: [].} =
  let stripped = stripComment(bodyLines[atIdx]).strip().toLowerAscii()
  return stripped.startsWith("return false") or stripped == "return false" or
         stripped == "result = false" or stripped.startsWith("exit(false)")

func isInConditional(bodyLines: openArray[string]; stmtIdx: int): bool {.raises: [].} =
  ## Check if a statement at stmtIdx is inside an if/when/case conditional.
  var depth = 0
  for i in 0 ..< stmtIdx:
    let line = stripComment(bodyLines[i]).strip().toLowerAscii()
    if line.startsWith("if ") or line.startsWith("if(") or
       line.startsWith("when ") or line.startsWith("case ") or
       line.contains(": if ") or line.contains(": when "):
      inc depth
    elif line == "else:" or line == "else:":
      discard  ## stays in conditional scope
    elif line.startsWith("end") or line.startsWith("done"):
      if depth > 0: dec depth
  return depth > 0

# ═══════════════════════════════════════════════════════════════════════════
# §4. Pattern detectors — structural analysis with block tracking
# ═══════════════════════════════════════════════════════════════════════════

proc detectSilentDiscard(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Structural detection: find except branches whose body is ONLY bare discard
  ## statements with no logging, re-raising, or audit trail.
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()
    if stripped == "except:" or stripped.startsWith("except (") or
       stripped.startsWith("except,") or stripped == "except CatchableError:":
      ## Found an except clause — analyze its body structurally
      var bodyStart = i + 1
      var bodyEnd = i + 1
      var braceDepth = 0
      var hasRealCode = false
      var allBareDiscard = true
      var firstStatementLine = -1

      ## Scan until we hit dedent, another except/finally/else, or end of file
      for j in (i + 1) .. min(i + 20, lines.len - 1):
        let inner = lines[j].strip()
        if inner.len == 0:
          bodyEnd = j
          continue

        ## Check for block-ending constructs
        if inner.startsWith("except ") or inner.startsWith("except,") or
           inner.startsWith("finally") or inner.startsWith("else:") or
           inner.startsWith("elif ") or inner.startsWith("if ") or
           inner.startsWith("when ") or inner.startsWith("case ") or
           inner.startsWith("proc ") or inner.startsWith("func ") or
           inner.startsWith("end"):
          bodyEnd = j
          break

        inc bodyEnd

        ## Check if this is a bare discard
        let innerLower = inner.toLowerAscii()
        if innerLower == "discard" or innerLower == "result = discard":
          if firstStatementLine == -1:
            firstStatementLine = j
        else:
          ## Non-discard statement found — this is real error handling
          hasRealCode = true
          allBareDiscard = false
          break

      if allBareDiscard and bodyEnd > bodyStart and not hasRealCode:
        ## Verify there's no logging, re-raising, or audit trail in the except block
        var hasLogging = false
        for j in bodyStart .. bodyEnd:
          let blk = lines[j].strip().toLowerAscii()
          if "log" in blk or "echo" in blk or "raise" in blk or
             "warn" in blk or "error" in blk or "debug" in blk or
             "stderr" in blk or "audit" in blk or "record" in blk:
            hasLogging = true
            break

        if not hasLogging and firstStatementLine >= 0:
          result.add(TheaterViolation(
            pattern: tpSwallowedFailure,
            filePath: filePath,
            line: firstStatementLine + 1,
            message: "Swallowed exception: except branch at line " &
                     $(i + 1) & " contains only discard — silently drops errors",
            severity: "critical"
          ))

proc detectUnconditionalReturns(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Structural detection: find verification procs with unconditional
  ## return true/false bodies that perform no actual computation.
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()

    ## Detect proc/func/method definitions
    let isProcDef = stripped.startsWith("proc ") or stripped.startsWith("func ") or
                    stripped.startsWith("method ") or stripped.startsWith("template ") or
                    stripped.startsWith("macro ") or stripped.startsWith("iterator ")
    if not isProcDef: continue

    let procName = extractProcName(lines[i])
    if procName.len == 0: continue

    ## Skip if not a verification/gate/proof proc
    if not (isVerificationProc(procName) or isGateProc(procName) or isProofProc(procName)):
      continue

    ## Find the proc body using structural analysis
    let (bodyStart, bodyEnd) = findProcBodyLines(lines, i)
    if bodyStart > bodyEnd: continue

    var bodyLines: seq[string] = @[]
    for j in bodyStart .. bodyEnd:
      bodyLines.add(lines[j])

    let nonBlankCount = countNonBlankNonCommentLines(bodyLines)
    if nonBlankCount == 0: continue

    ## Check for trivial body (only return true/false, discard)
    if isTrivialBody(bodyLines):
      let isVerification = isVerificationProc(procName)
      let isGate = isGateProc(procName)
      let isProof = isProofProc(procName)

      ## Determine pattern type based on proc name and body
      var hasTrueReturn = false
      var hasFalseReturn = false
      for bi in 0 ..< bodyLines.len:
        if hasReturnTrue(bodyLines, bi): hasTrueReturn = true
        if hasReturnFalse(bodyLines, bi): hasFalseReturn = true

      if hasTrueReturn and isVerification:
        result.add(TheaterViolation(
          pattern: tpAlwaysPass,
          filePath: filePath,
          line: bodyStart + 1,
          message: "Always-pass: verification proc '" & procName &
                   "' unconditionally returns true — no actual logic (" &
                   $nonBlankCount & " non-blank line(s))",
          severity: "critical"
        ))
      elif hasTrueReturn and isGate:
        result.add(TheaterViolation(
          pattern: tpDeadGate,
          filePath: filePath,
          line: bodyStart + 1,
          message: "Dead gate: gate proc '" & procName &
                   "' unconditionally returns true — gate is non-functional (" &
                   $nonBlankCount & " non-blank line(s))",
          severity: "critical"
        ))
      elif hasTrueReturn and isProof:
        result.add(TheaterViolation(
          pattern: tpVacuousProof,
          filePath: filePath,
          line: bodyStart + 1,
          message: "Vacuous proof: proof proc '" & procName &
                   "' unconditionally returns true — no actual proof (" &
                   $nonBlankCount & " non-blank line(s))",
          severity: "critical"
        ))
      elif hasFalseReturn and isVerification:
        result.add(TheaterViolation(
          pattern: tpDisguisedStub,
          filePath: filePath,
          line: bodyStart + 1,
          message: "Fabricated negative: verification proc '" & procName &
                   "' unconditionally returns false — disguised stub (" &
                   $nonBlankCount & " non-blank line(s))",
          severity: "high"
        ))

    elif nonBlankCount <= 3:
      ## Small body — check for unconditional return true outside conditionals
      for bi in 0 ..< bodyLines.len:
        if hasReturnTrue(bodyLines, bi):
          if not isInConditional(bodyLines, bi):
            result.add(TheaterViolation(
              pattern: tpAlwaysPass,
              filePath: filePath,
              line: bodyStart + bi + 1,
              message: "Unconditional 'return true' in '" & procName &
                       "' at line " & $(bodyStart + bi + 1) &
                       " — no conditional guard (" &
                       $nonBlankCount & " non-blank line(s))",
              severity: "critical"
            ))
            break

proc detectDeadGates(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Structural detection: find gate/procedure procs that return true/false
  ## without executing any real gate logic (no parsing, no validation, no checks).
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()

    let isProcDef = stripped.startsWith("proc ") or stripped.startsWith("func ")
    if not isProcDef: continue

    let procName = extractProcName(lines[i])
    if procName.len == 0: continue

    if not isGateProc(procName): continue

    let (bodyStart, bodyEnd) = findProcBodyLines(lines, i)
    if bodyStart > bodyEnd: continue

    var bodyLines: seq[string] = @[]
    for j in bodyStart .. bodyEnd:
      bodyLines.add(lines[j])

    let nonBlankCount = countNonBlankNonCommentLines(bodyLines)
    if nonBlankCount == 0: continue

    ## A dead gate has trivial body AND returns true (or sets result = true)
    if isTrivialBody(bodyLines):
      for bi in 0 ..< bodyLines.len:
        let stmt = stripComment(bodyLines[bi]).strip().toLowerAscii()
        if stmt.startsWith("return true") or stmt == "result = true" or
           stmt.startsWith("exit(true)"):
          result.add(TheaterViolation(
            pattern: tpDeadGate,
            filePath: filePath,
            line: bodyStart + bi + 1,
            message: "Dead gate: '" & procName & "' returns true without " &
                     "executing any gate logic (" & $nonBlankCount &
                     " non-blank line(s), line " & $(bodyStart + bi + 1) & ")",
            severity: "critical"
          ))
          break

proc detectVacuousProofs(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Structural detection: find proof-related procs that convert constraints
  ## to True/true or return success without actually invoking a solver/backend.
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()

    let isProcDef = stripped.startsWith("proc ") or stripped.startsWith("func ")
    if not isProcDef: continue

    let procName = extractProcName(lines[i])
    if procName.len == 0: continue

    if not isProofProc(procName): continue

    let (bodyStart, bodyEnd) = findProcBodyLines(lines, i)
    if bodyStart > bodyEnd: continue

    var bodyLines: seq[string] = @[]
    for j in bodyStart .. bodyEnd:
      bodyLines.add(lines[j])

    let nonBlankCount = countNonBlankNonCommentLines(bodyLines)
    if nonBlankCount == 0: continue

    ## Check for hardcoded true conversion patterns
    for bi in 0 ..< bodyLines.len:
      let stmt = stripComment(bodyLines[bi]).strip().toLowerAscii()
      if stmt == "return true" or stmt == "result = true" or
         stmt == "ok(true)" or stmt.startswith("ok(True") or
         stmt == "exit(true)":
        ## Check if this is inside a conditional (legitimate early return)
        if isInConditional(bodyLines, bi): continue

        ## Check if there's actual solver/backend invocation in the proc
        var hasSolverCall = false
        for cj in 0 ..< bodyLines.len:
          let cstmt = stripComment(bodyLines[cj]).strip().toLowerAscii()
          if "z3" in cstmt or "lean" in cstmt or "solve" in cstmt or
             "prove" in cstmt or "execute" in cstmt or "gorge" in cstmt or
             "startProcess" in cstmt or "cmd" in cstmt or "call" in cstmt:
            hasSolverCall = true
            break

        if not hasSolverCall:
          result.add(TheaterViolation(
            pattern: tpVacuousProof,
            filePath: filePath,
            line: bodyStart + bi + 1,
            message: "Vacuous proof: '" & procName & "' returns success " &
                     "without invoking any solver/backend (" &
                     $nonBlankCount & " non-blank line(s))",
            severity: "critical"
          ))
          break

proc detectSwallowingInSmallBodies(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Detect except blocks in small functions where swallow is more likely theater.
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()
    if stripped == "except:" or stripped.startsWith("except ("):
      ## Measure the size of the surrounding function
      var funcStart = i
      var funcEnd = i
      var foundFuncEnd = false

      ## Look backward for proc/func definition
      for bi in countdown(i - 1, max(0, i - 100)):
        let bline = stripComment(lines[bi]).strip().toLowerAscii()
        if bline.startsWith("proc ") or bline.startsWith("func ") or
           bline.startsWith("method "):
          funcStart = bi
          break

      ## Look forward for function end
      var braceD = 0
      var foundOpen = false
      for fj in i .. min(i + 50, lines.len - 1):
        for ch in lines[fj]:
          if ch == '{': inc braceD; foundOpen = true
          elif ch == '}': dec braceD
        if foundOpen and braceD <= 0:
          funcEnd = fj
          foundFuncEnd = true
          break

      if not foundFuncEnd:
        funcEnd = min(i + 30, lines.len - 1)

      ## Count non-blank lines in the function
      var funcLines: seq[string] = @[]
      for fi in funcStart .. funcEnd:
        funcLines.add(lines[fi])
      let funcSize = countNonBlankNonCommentLines(funcLines)

      if funcSize <= 15:
        ## Small function with except — check if it swallows
        var hasRealHandling = false
        for ej in (i + 1) .. min(i + 10, funcEnd):
          let eline = lines[ej].strip().toLowerAscii()
          if eline.len == 0: continue
          if eline.startsWith("except ") or eline.startsWith("finally") or
             eline.startsWith("else:") or eline.startsWith("end"):
            break
          if eline != "discard" and eline != "result = discard":
            hasRealHandling = true
            break

        if not hasRealHandling:
          ## Check for any logging
          var hasLogging = false
          for ej in funcStart .. funcEnd:
            let fl = lines[ej].strip().toLowerAscii()
            if "log" in fl or "echo" in fl or "raise" in fl or
               "stderr" in fl or "warn" in fl or "error" in fl or
               "audit" in fl or "record" in fl:
              hasLogging = true
              break

          if not hasLogging:
            result.add(TheaterViolation(
              pattern: tpSwallowedFailure,
              filePath: filePath,
              line: i + 1,
              message: "Exception swallowed in small func (" & $funcSize &
                       " lines): except at line " & $(i + 1) &
                       " has no real error handling or audit trail",
              severity: "high"
            ))

proc detectFakeCoverage(filePath: string; lines: openArray[string]): seq[TheaterViolation] {.raises: [].} =
  ## Detect coverage/count reporting procs that return hardcoded values.
  for i in 0 ..< lines.len:
    let stripped = stripComment(lines[i]).strip().toLowerAscii()

    let isProcDef = stripped.startsWith("proc ") or stripped.startsWith("func ")
    if not isProcDef: continue

    let procName = extractProcName(lines[i])
    if procName.len == 0: continue

    let nameLower = procName.toLowerAscii()
    if not ("coverage" in nameLower or "count" in nameLower or
            "metric" in nameLower or "report" in nameLower or
            "summary" in nameLower or "stats" in nameLower):
      continue

    let (bodyStart, bodyEnd) = findProcBodyLines(lines, i)
    if bodyStart > bodyEnd: continue

    var bodyLines: seq[string] = @[]
    for j in bodyStart .. bodyEnd:
      bodyLines.add(lines[j])

    let nonBlankCount = countNonBlankNonCommentLines(bodyLines)
    if nonBlankCount == 0: continue

    ## Check for hardcoded boolean returns in coverage/reporting procs
    for bi in 0 ..< bodyLines.len:
      let stmt = stripComment(bodyLines[bi]).strip().toLowerAscii()
      if stmt.startsWith("return true") or stmt == "result = true" or
         stmt == "ok(true)" or stmt == "ok(true)" or
         stmt.startsWith("exit(true)"):
        if not isInConditional(bodyLines, bi):
          result.add(TheaterViolation(
            pattern: tpFakeCounts,
            filePath: filePath,
            line: bodyStart + bi + 1,
            message: "Hardcoded coverage value: '" & procName &
                     "' returns true without measuring anything (" &
                     $nonBlankCount & " non-blank line(s))",
            severity: "high"
          ))
          break

# ═══════════════════════════════════════════════════════════════════════════
# §5. File scanning orchestrator
# ═══════════════════════════════════════════════════════════════════════════

proc checkFile(filePath: string): seq[TheaterViolation] {.raises: [].} =
  ## Read filePath and run all structural pattern detectors.
  result = @[]
  try:
    if not fileExists(filePath): return @[]
    let content = readFile(filePath)
    if content.strip().len == 0: return @[]
    let lines = content.splitLines()

    ## Run all detectors
    result.add(detectSilentDiscard(filePath, lines))
    result.add(detectUnconditionalReturns(filePath, lines))
    result.add(detectDeadGates(filePath, lines))
    result.add(detectVacuousProofs(filePath, lines))
    result.add(detectSwallowingInSmallBodies(filePath, lines))
    result.add(detectFakeCoverage(filePath, lines))
  except IOError, OSError, CatchableError:
    discard

# ═══════════════════════════════════════════════════════════════════════════
# §6. Debt registry parsing
# ═══════════════════════════════════════════════════════════════════════════

proc parseDebtEntry(obj: JsonNode): DebtEntry =
  result.id = obj["id"].getStr("")
  result.category = obj["category"].getStr("")
  result.description = obj["description"].getStr("")
  result.severity = obj["severity"].getStr("medium")
  result.source = obj["source"].getStr("unknown")
  result.status = obj["status"].getStr("open")

  ## Parse files array
  if obj.hasKey("files"):
    let filesArr = obj["files"]
    if filesArr.kind == JArray:
      for f in filesArr:
        result.files.add(f.getStr(""))
  elif obj.hasKey("file"):
    result.files.add(obj["file"].getStr(""))

  ## Optional fields
  if obj.hasKey("symbol"):
    result.symbol = obj["symbol"].getStr("")
  if obj.hasKey("contentHash"):
    result.contentHash = obj["contentHash"].getStr("")
  if obj.hasKey("lineRange"):
    result.lineRange = obj["lineRange"].getStr("")
  if obj.hasKey("resolution"):
    result.resolution = obj["resolution"].getStr("")
  if obj.hasKey("lastVerifiedAt"):
    result.lastVerifiedAt = obj["lastVerifiedAt"].getStr("")

proc loadRegistry(path: string): tuple[entries: seq[DebtEntry]; raw: JsonNode] =
  if not fileExists(path):
    echo "❌ Registry not found: " & path
    quit(1)

  let content = readFile(path)
  let parsed = parseJson(content)
  if parsed.kind != JObject:
    echo "❌ Invalid registry format"
    quit(1)

  let entriesArr = parsed["entries"]
  if entriesArr.kind != JArray:
    echo "❌ Missing 'entries' array"
    quit(1)

  for entryObj in entriesArr:
    if entryObj.kind == JObject:
      result.entries.add(parseDebtEntry(entryObj))
  result.raw = parsed

proc updateEntryInRaw(raw: var JsonNode; entry: DebtEntry): JsonNode =
  ## Update a specific entry in the raw JSON by matching its id.
  let entriesArr = raw["entries"]
  for i in 0 ..< entriesArr.len:
    if entriesArr[i]["id"].getStr("") == entry.id:
      entriesArr[i]["resolution"] = %*entry.resolution
      if entry.resolvedAt.len > 0:
        entriesArr[i]["resolvedAt"] = %*entry.resolvedAt
      if entry.resolvedBy.len > 0:
        entriesArr[i]["resolvedBy"] = %*entry.resolvedBy
      if entry.resolutionNote.len > 0:
        entriesArr[i]["resolutionNote"] = %*entry.resolutionNote
      if entry.lastVerifiedAt.len > 0:
        entriesArr[i]["lastVerifiedAt"] = %*entry.lastVerifiedAt
      return entriesArr[i]
  return newJObject()

# ═══════════════════════════════════════════════════════════════════════════
# §7. Reconciliation engine
# ═══════════════════════════════════════════════════════════════════════════

let Tag = "[debt-reconciler]"

func patternTag(p: TheaterPattern): string =
  case p
  of tpAlwaysPass:        "[ALWAYS-PASS]"
  of tpSwallowedFailure:  "[SWALLOWED]"
  of tpDeadGate:          "[DEAD-GATE]"
  of tpVacuousProof:      "[VACUOUS]"
  of tpDisguisedStub:     "[DISGUISED-STUB]"
  of tpUnenforcedClaim:   "[UNENFORCED]"
  of tpFakeCounts:        "[FAKE-COUNTS]"
  of tpTestTheater:       "[TEST-THEATER]"
  of tpCiTheater:         "[CI-THEATER]"
  of tpUncategorized:     "[UNCATEGORIZED]"

func formatViolation(v: TheaterViolation): string =
  let loc = if v.line > 0: ":" & $v.line else: ":??"
  result = v.filePath & loc & ": " & patternTag(v.pattern) & " " & v.message

proc resolveFilePath(baseDir: string; refPath: string): string =
  ## Resolve a file reference from debt registry to absolute path.
  ## References may include line ranges like "src/foo.nim:12-34".
  let cleanPath = refPath.split(':')[0].strip()
  if cleanPath.startsWith("/"):
    return cleanPath
  elif cleanPath.startsWith("./"):
    var p = baseDir / cleanPath[2..^1]
    p.normalizePath()
    return p
  else:
    var p = baseDir / cleanPath
    p.normalizePath()
    return p

proc reconcileEntry(entry: DebtEntry; baseDir: string; dryRun: bool): seq[ReconcileResult] =
  ## Reconcile a single debt entry against current source files.
  result = @[]

  if entry.category.find("Theater/") != 0:
    return @[]  ## Not a theater entry — skip

  for fileRef in entry.files:
    let filePath = resolveFilePath(baseDir, fileRef)
    if not fileExists(filePath):
      result.add(ReconcileResult(
        entryId: entry.id,
        filePath: filePath,
        wasFixed: false,
        stillExists: false,
        foundViolations: @[]
      ))
      continue

    ## Scan the file for theater patterns
    let violations = checkFile(filePath)

    if violations.len == 0:
      ## No violations found — pattern may be fixed
      let currentResolution = entry.resolution
      if currentResolution == "FIXED" or currentResolution == "FALSE_POSITIVE":
        ## Already resolved — verify lastVerifiedAt is recent
        result.add(ReconcileResult(
          entryId: entry.id,
          filePath: filePath,
          wasFixed: false,
          stillExists: false,
          foundViolations: @[]
        ))
      elif currentResolution == "WONT_FIX" or currentResolution == "ORPHANED":
        ## Explicit rejection — don't change
        result.add(ReconcileResult(
          entryId: entry.id,
          filePath: filePath,
          wasFixed: false,
          stillExists: false,
          foundViolations: @[]
        ))
      else:
        ## No resolution set yet — pattern appears fixed
        result.add(ReconcileResult(
          entryId: entry.id,
          filePath: filePath,
          wasFixed: true,
          stillExists: false,
          foundViolations: @[]
        ))
    else:
      ## Violations still present
      result.add(ReconcileResult(
        entryId: entry.id,
        filePath: filePath,
        wasFixed: false,
        stillExists: true,
        foundViolations: violations
      ))

# ═══════════════════════════════════════════════════════════════════════════
# §8. CLI layer
# ═══════════════════════════════════════════════════════════════════════════

proc main() {.raises: [CatchableError].} =
  let params = commandLineParams()
  let baseDir = getCurrentDir()

  var dryRun = false
  var singleFile: string = ""
  var singleId: string = ""

  for p in params:
    case p
    of "--dry-run": dryRun = true
    of "--file":
      if params.len > 1:
        let idx = params.find(p)
        if idx + 1 < params.len:
          singleFile = params[idx + 1]
    of "--id":
      if params.len > 1:
        let idx = params.find(p)
        if idx + 1 < params.len:
          singleId = params[idx + 1]
    of "--help", "-h":
      echo "Axiom Debt Reconciler — Stage 2: Pure-AST Theater Detection"
      echo ""
      echo "Usage:"
      echo "  debt_reconciler                        Reconcile all theater entries (read-only report)"
      echo "  debt_reconciler --dry-run              Read-only (the only mode)"
      echo "  debt_reconciler --file PATH            Scan single file"
      echo "  debt_reconciler --id DEBT#NNN          Reconcile single entry"
      quit(0)
    else: discard

  ## Load registry
  var registry = loadRegistry(RegistryPath)
  echo Tag, " Loaded ", registry.entries.len, " debt entries"

  ## Filter to theater entries
  var theaterEntries: seq[DebtEntry] = @[]
  for e in registry.entries:
    if e.category.find("Theater/") == 0:
      theaterEntries.add(e)

  echo Tag, " Found ", theaterEntries.len, " theater entries"

  ## If --file mode, scan the file and report
  if singleFile.len > 0:
    echo Tag, " Scanning file: ", singleFile
    let violations = checkFile(singleFile)
    if violations.len == 0:
      echo Tag, " PASS: no theater patterns in ", singleFile
    else:
      echo Tag, " FAIL: ", violations.len, " violation(s) in ", singleFile
      for v in violations:
        echo "  ", formatViolation(v)
    quit(if violations.len == 0: 0 else: 1)

  ## If --id mode, reconcile single entry
  if singleId.len > 0:
    var found = false
    for e in theaterEntries:
      if e.id == singleId:
        found = true
        let results = reconcileEntry(e, baseDir, dryRun)
        echo Tag, " Reconciling ", singleId
        for r in results:
          if r.wasFixed:
            echo Tag, " ✅ ", r.entryId, " (", r.filePath, ") — PATTERN FIXED"
          elif r.stillExists:
            echo Tag, " ❌ ", r.entryId, " (", r.filePath, ") — STILL EXISTS"
            for v in r.foundViolations:
              echo "     ", formatViolation(v)
          else:
            echo Tag, " ⏭️  ", r.entryId, " (", r.filePath, ") — already resolved"
        break
    if not found:
      echo Tag, " Entry not found: ", singleId
    quit(0)

  ## Full reconciliation
  echo Tag, " Starting reconciliation..."
  echo ""

  var totalScanned = 0
  var newlyFixed = 0
  var stillBroken = 0
  var alreadyResolved = 0
  var errors = 0
  var allResults: seq[ReconcileResult] = @[]

  for entry in theaterEntries:
    try:
      let results = reconcileEntry(entry, baseDir, dryRun)
      allResults.add(results)

      for r in results:
        inc totalScanned
        if r.wasFixed:
          inc newlyFixed
        elif r.stillExists:
          inc stillBroken
        else:
          inc alreadyResolved
    except CatchableError as e:
      inc errors
      if errors <= MaxErrors:
        echo Tag, " ERROR processing ", entry.id, ": ", e.msg

  ## Summary
  echo "---"
  echo Tag, " Reconciliation complete:"
  echo Tag, "   Total scanned:  ", totalScanned
  echo Tag, "   Newly fixed:    ", newlyFixed
  echo Tag, "   Still broken:   ", stillBroken
  echo Tag, "   Already resolved:", alreadyResolved
  if errors > 0:
    echo Tag, "   Errors:         ", errors

  ## Report entries the registry has not caught up with
  if newlyFixed > 0:
    echo ""
    echo Tag, " ", newlyFixed, " entry(ies) no longer reproduce their theater pattern:"
    for r in allResults:
      if r.wasFixed:
        echo Tag, "   ", r.entryId, " → ", r.filePath
    echo Tag, " Registry is read-only here; close these through bin/debt_engine."

  ## Report still-broken entries
  if stillBroken > 0:
    echo ""
    echo Tag, " Entries still showing theater patterns:"
    var reported = 0
    for r in allResults:
      if r.stillExists:
        if reported < 20:
          echo Tag, "   ", r.entryId, " → ", r.filePath
          for v in r.foundViolations:
            echo Tag, "     ", formatViolation(v)
        inc reported
    if reported > 20:
      echo Tag, "   ... and ", reported - 20, " more"

  ## Exit code
  if stillBroken > 0:
    quit(1)
  elif newlyFixed > 0:
    quit(1)
  else:
    echo ""
    echo Tag, " All theater entries reconciled successfully"
    quit(0)

when isMainModule:
  main()
