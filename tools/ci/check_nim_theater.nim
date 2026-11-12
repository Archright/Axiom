## check_nim_theater.nim — Static scanner for theater patterns in Nim source code.
##
## Part of the Fail-Closed paradigm shift (Phase 9). Replaces the missing
## `{.nodiscard.}` / `DiscardedResult` compiler warning from Nim 2.2.10.
## # axiom:best-effort(ioboundary catch) — this tool is a scanner, not production code
##
## Rules:
##   S1 — Swallowed Failure: `except CatchableError:` + `discard` without annotation
##   S2 — Always-Pass: `check true` without compile-check annotation; `return true`/`return ok(...)` heuristics
##   S3 — Dead Catch: empty `except:` blocks (no body or only `discard`)
##   S4 — Critical Write Discard: `discard <call>` to verification-critical functions
##        (writeFileSafe, writeFileOpt, writeCertificate, store, commit, persist,
##         save, appendLog, AtomicWrite) without # axiom:best-effort( tag
##   S5 — Unreachable Stub: `doAssert false` / `assert false` with "NOT IMPLEMENTED"
##        message in test files (generator-emitted stubs), NOT intentional guards
##   C  — CI Fail-Open Swallow: `|| true` / `|| :` / `|| rm ...` / `|| echo ...`
##        in CI files (Makefile, *.mk, .circleci/*.yml, .github/workflows/**,
##        .github/actions/**) without # axiom:best-effort(reason). Signature and
##        file-set parity with src/gate/runners/anti_theater_gate.nim rule C.
##        CI files are scanned only when passed as arguments (e.g.
##        `bin/check_nim_theater Makefile ci/ .github/`); the push-time
##        Makefile scan-set extension is pending triage of the pre-existing
##        untagged findings it surfaces.
##   S6 — Raw proof-status comparison: comparing `status` directly with
##        `vsProved` in src|tools .nim (anti_theater_gate.nim rule S3; the
##        scanner-local ID is S6 because this scanner's S3 already means
##        dead-catch — reusing S3 here would corrupt the file+symbol+rule
##        allowlist anchors). Excludes the semantic-helper SSOT
##        (verification_result_types.nim), the reference gate's own source,
##        and this scanner's own source (self-reference carve-outs, matching
##        the reference whitelist). No tag exemption. The needle is assembled
##        from fragments (const vsProvedRawNeedle) so the exact literal never
##        appears on a source line — the commit-time gate scans this file's
##        added lines with the same rule and would otherwise block its own
##        detector.
##
## Line-based scanner (NOT an AST scanner): each rule matches raw source lines.
## Lines that lie entirely inside a multi-line string literal (`""" ... """`)
## are masked out before pattern matching — a pattern inside a string literal
## is a false positive, not theater. Single-line `"..."` strings are not
## tracked (minimal-change principle); see docs/spec/theater_detection_policy.md.
##
## Allowlist anchor identity: `file + symbol + rule`. The `line` field in the
## allowlist JSON is DERIVED EVIDENCE ONLY — it is never part of the canonical
## anchor. Symbol resolution scans preceding source lines for the nearest
## enclosing top-level declaration (`proc`, `func`, `template`, `macro`,
## `iterator`, `converter`, `type`). If no declaration encloses the line,
## the symbol falls back to the file basename. This makes allowlist entries
## resilient to line-number drift from edits.
##
## Usage:
##   nim c -o:bin/check_nim_theater tools/ci/check_nim_theater.nim
##   bin/check_nim_theater <path1> [path2] ...
##   bin/check_nim_theater --allowlist allowlist.json <path1> ...
##   bin/check_nim_theater --allowlist allowlist.json src/ tests/ tools/ \
##       Makefile ci/ .circleci/ .github/   # + CI files (rule C)
##
## Exit code: 0 = PASS, 1 = FAIL (theater patterns found)

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[algorithm, os, json, strutils]

type
  Finding = object
    path: string
    line: int
    rule: string
    message: string

  AllowlistEntry = object
    file: string
    line: int  # 0 means entire file is allowlisted for this rule; kept as derived evidence only
    rule: string
    reason: string
    rationale: string  # optional justification for directory-wide (line 0) entries
    symbol: string  # canonical anchor: enclosing top-level declaration name; "" = legacy line/prefix matching

var
  findings: seq[Finding] = @[]
  allowlist: seq[AllowlistEntry] = @[]
  allowlistLoaded = false

# ---------------------------------------------------------------------------
# Allowlist loader
# ---------------------------------------------------------------------------

proc loadAllowlist(path: string) =
  if not fileExists(path):
    echo "WARN: allowlist file not found: ", path
    return
  let content = readFile(path)
  if content.strip.len == 0:
    return
  let jsonNode = parseJson(content)
  if jsonNode.kind != JArray:
    echo "WARN: allowlist is not a JSON array, ignoring"
    return
  for entry in jsonNode:
    allowlist.add(AllowlistEntry(
      file: entry["file"].getStr(""),
      line: entry["line"].getInt(0),
      rule: entry["rule"].getStr(""),
      reason: entry["reason"].getStr(""),
      rationale: entry.getOrDefault("rationale").getStr(""),
      symbol: entry.getOrDefault("symbol").getStr("")
    ))
  allowlistLoaded = true

# ---------------------------------------------------------------------------
# Symbol resolver — finds the enclosing top-level declaration name
# at a given (path, line). Used as the canonical anchor for allowlist
# identity (file + symbol + rule). Line numbers are derived evidence only.
# ---------------------------------------------------------------------------

proc extractDeclName(line: string; keyword: string): string =
  ## Extract the symbol name immediately following `keyword` on a
  ## declaration line. Handles backtick-quoted names and generic params.
  let kwLen = keyword.len
  if line.len < kwLen + 1:
    return ""
  # Verify the keyword is at the start (after optional whitespace)
  let afterKw = line[kwLen .. ^1]
  if afterKw.len == 0 or afterKw[0] notin {' ', '\t'}:
    return ""
  var i = 0
  while i < afterKw.len and afterKw[i] in {' ', '\t'}:
    i.inc
  if i >= afterKw.len:
    return ""
  let rest = afterKw[i .. ^1]
  # Backtick-quoted name
  if rest[0] == '`':
    let endIdx = rest.find('`', 1)
    if endIdx > 0:
      return rest[1 ..< endIdx]
    return rest[1 .. ^1]
  # Regular identifier: collect alphanumeric + underscore
  var j = 0
  while j < rest.len and (rest[j].isAlphaAscii or rest[j] == '_' or rest[j].isDigit):
    j.inc
  if j > 0:
    result = rest[0 ..< j]

proc resolveSymbol(path: string; lineNum: int): string =
  ## Given a source file path and 1-based line number, return the
  ## enclosing top-level declaration's symbol name.  Scans preceding
  ## lines for the nearest declaration start.  If no enclosing
  ## declaration is found, returns the file basename (no extension).
  let absPath = absolutePath(path)
  if not fileExists(absPath):
    return splitFile(absPath).name
  let content = readFile(absPath)
  let lines = content.splitLines()
  let target = lineNum - 1  # convert to 0-based
  if target < 0 or target >= lines.len:
    return splitFile(absPath).name

  # Keywords that introduce a top-level declaration whose name we care about.
  # `concept` and `resource` are included but rarely appear in allowlist entries.
  let declKeywords = ["proc", "func", "template", "macro", "iterator",
                      "converter", "type", "concept"]

  for i in countdown(target, 0):
    let trimmed = lines[i].strip()
    if trimmed.len == 0:
      continue
    # Skip pure comment lines — they don't start declarations
    if trimmed.startsWith("#"):
      continue

    # Check for `resource` keyword (separate pattern per spec)
    if trimmed.startsWith("resource"):
      let name = extractDeclName(trimmed, "resource")
      if name.len > 0:
        return name
      # resource with no name found — keep scanning backwards
      continue

    # Check each declaration keyword
    for kw in declKeywords:
      if trimmed.startsWith(kw & " "):
        let name = extractDeclName(trimmed, kw)
        if name.len > 0:
          return name
        # Keyword found but no name extracted (e.g. `type` on its own line
        # before the type definition).  Keep scanning backwards for the
        # actual `type Foo = ...` line.
        break  # don't check other keywords on this line

  # No enclosing declaration found — fall back to file-level symbol
  result = splitFile(absPath).name

# ---------------------------------------------------------------------------
# Allowlist matching
# ---------------------------------------------------------------------------

proc isAllowlisted(path: string; lineNum: int; rule: string): bool =
  if not allowlistLoaded:
    return false
  let absPath = absolutePath(path)
  for e in allowlist:
    let eAbs = absolutePath(e.file)
    # Check if eAbs is a directory prefix of absPath or exact match
    if not (absPath.startsWith(eAbs) or eAbs == absPath):
      continue
    # Symbol-based matching (canonical anchor: file + symbol + rule)
    if e.symbol.len > 0:
      let sym = resolveSymbol(path, lineNum)
      if sym == e.symbol and e.rule == rule:
        return true
      continue
    # Legacy fallback: line 0 = whole file; otherwise exact line match
    if e.line == 0 and e.rule == rule:
      return true
    if e.line == lineNum and e.rule == rule:
      return true
  false

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

proc addFinding(path: string; line: int; rule, msg: string) =
  if isAllowlisted(path, line, rule):
    return
  findings.add(Finding(path: path, line: line, rule: rule, message: msg))

proc printFinding(f: Finding) =
  echo f.path, ":", f.line, ": [", f.rule, "] ", f.message

# ---------------------------------------------------------------------------
# File scanning helpers
# ---------------------------------------------------------------------------

proc isTestDir(path: string): bool =
  path.startsWith("tests/") or "/tests/" in path

# ---------------------------------------------------------------------------
# Multi-line string literal masking
# ---------------------------------------------------------------------------

proc stripLineComment(line: string): string =
  ## Returns the portion of `line` before the first `#` comment marker.
  ## A `"""` inside a comment is not a real multi-line string delimiter.
  let idx = line.find('#')
  if idx >= 0:
    line[0 ..< idx]
  else:
    line

proc countTripleQuotes(line: string): int =
  ## Counts non-overlapping `"""` groups in `line`.
  ## A single-line `"""..."""` literal counts as 2 groups (even, no toggle);
  ## a multi-line opening or closing delimiter counts as 1 (odd, toggles).
  var i = 0
  while i < line.len:
    if line[i] == '"' and i + 2 < line.len and
       line[i+1] == '"' and line[i+2] == '"':
      inc result
      inc i, 3
    else:
      inc i

proc buildStringMask(lines: seq[string]): seq[bool] =
  ## Returns a mask where mask[i] == true means line i lies fully inside a
  ## multi-line string literal (`""" ... """`) and must be skipped by the
  ## pattern rules. Delimiter lines themselves are always scanned —
  ## conservative: over-detection is preferred over missed theater.
  result = newSeq[bool](lines.len)
  var inString = false
  for i, line in lines:
    let n = countTripleQuotes(stripLineComment(line))
    if n == 0:
      result[i] = inString
    else:
      if (n mod 2) == 1:
        inString = not inString
      result[i] = false

proc hasAnnotation(line: string; annotation: string): bool =
  let stripped = line.strip()
  annotation in stripped

proc hasBestEffort(line: string): bool =
  hasAnnotation(line, "axiom:best-effort(")

proc hasFailClosedSilent(line: string): bool =
  hasAnnotation(line, "fail-closed: silent-by-design(")

proc hasCompileCheck(line: string): bool =
  hasAnnotation(line, "axiom:compile-check")

# Check if a line has meaningful conditional logic (heuristic for S2)
proc hasConditionalLogic(line: string): bool =
  let trimmed = line.strip()
  # Count operators, comparisons, function calls as indicators of real logic
  if trimmed.contains("==") or trimmed.contains("!="): return true
  if trimmed.contains(">") or trimmed.contains("<"): return true
  if trimmed.contains("and") or trimmed.contains("or"): return true
  if trimmed.contains("not "): return true
  if trimmed.contains("(") and trimmed.contains(")"): return true
  if trimmed.contains("in "): return true
  if trimmed.contains("is "): return true
  false

# ---------------------------------------------------------------------------
# Rule S1 — Swallowed Failure
# ---------------------------------------------------------------------------

proc checkRuleS1(lines: seq[string]; mask: seq[bool]; path: string) =
  var i = 0
  while i < lines.len:
    if mask[i]:
      i += 1
      continue
    let line = lines[i]
    let trimmed = line.strip()

    # Multi-line: `except CatchableError:` line followed by `discard` on next line
    if trimmed.startsWith("except CatchableError:") and trimmed.endsWith(":"):
      if hasBestEffort(line) or hasFailClosedSilent(line):
        i += 1
        continue
      # Check if there's code after : on same line
      let afterColon = trimmed[trimmed.find(":")+1 .. ^1].strip
      if afterColon.len > 0 and afterColon != "discard":
        i += 1
        continue
      # Same-line discard
      if afterColon == "discard":
        if allowlistLoaded or hasBestEffort(line) or hasFailClosedSilent(line):
          i += 1
          continue
        addFinding(path, i + 1, "S1", "Swallowed failure: except CatchableError: discard (add # axiom:best-effort(reason) annotation)")
        i += 1
        continue
      # Next-line discard
      if i + 1 < lines.len:
        let nextTrimmed = lines[i+1].strip()
        if nextTrimmed == "discard" and not mask[i+1]:
          let prevLine = if i > 0: lines[i-1] else: ""
          if hasBestEffort(prevLine) or hasFailClosedSilent(prevLine) or
             hasBestEffort(line) or hasFailClosedSilent(line) or
             hasBestEffort(lines[i+1]) or hasFailClosedSilent(lines[i+1]):
            i += 1
            continue
          addFinding(path, i + 1, "S1", "Swallowed failure: except CatchableError: discard (add # axiom:best-effort(reason) annotation)")

    # Single-line: `try: ... except CatchableError: discard`
    if trimmed.startsWith("try:"):
      # Scan forward for matching except within the same line or next few lines
      var j = i + 1
      var depth = 1
      while j < lines.len and j < i + 5:
        if mask[j]:
          j += 1
          continue
        let l = lines[j]
        let lt = l.strip()
        if lt.startsWith("except ") or lt.startsWith("except:"):
          if "CatchableError" in lt and "discard" in lt:
            if not hasBestEffort(l) and not hasFailClosedSilent(l):
              addFinding(path, j + 1, "S1", "Swallowed failure: except CatchableError: discard in try block")
          break
        j += 1

    # Inline pattern: `except CatchableError: discard`
    if "except CatchableError" in trimmed and "discard" in trimmed and ":" in trimmed:
      # Make sure it's not the multi-line case we already handled
      if not trimmed.startsWith("except CatchableError:") or trimmed.len > 80:
        i += 1
        continue
      if not hasBestEffort(line) and not hasFailClosedSilent(line):
        addFinding(path, i + 1, "S1", "Swallowed failure: except CatchableError: discard inline")

    i += 1

# ---------------------------------------------------------------------------
# Rule S2 — Always-Pass
# ---------------------------------------------------------------------------

proc checkRuleS2(lines: seq[string]; mask: seq[bool]; path: string) =
  for i, line in lines:
    if mask[i]:
      continue
    let trimmed = line.strip()

    # `check true` without compile-check annotation
    if trimmed == "check true":
      if not hasCompileCheck(line):
        if i > 0 and not hasCompileCheck(lines[i-1]):
          addFinding(path, i + 1, "S2", "Always-pass pattern: check true without # axiom:compile-check")

    # `doAssert true` or `assert true`
    if trimmed == "doAssert true" or trimmed == "assert true":
      if not hasCompileCheck(line):
        if i > 0 and not hasCompileCheck(lines[i-1]):
          addFinding(path, i + 1, "S2", "Always-pass pattern: " & trimmed & " without # axiom:compile-check")

    # `return true` — only flag when it's trivially a stub
    # (function has no real logic, just return true with a comment or nothing)
    if trimmed == "return true":
      # Check if this is a bare func body: prev line is just func header ending in = or :
      let prev = if i > 0: lines[i-1].strip() else: ""
      let prev2 = if i > 1: lines[i-2].strip() else: ""
      if (prev.len == 0 or prev.startsWith("{") or prev.startsWith("#")) and
         prev2.endsWith("{.raises: [].}="):
        addFinding(path, i + 1, "S2", "Always-pass pattern: stub return true in raises function")

# ---------------------------------------------------------------------------
# Rule S3 — Dead Catch: detect `except:` blocks with no real body
# ---------------------------------------------------------------------------

proc isBlockBoundary(line: string): bool =
  ## Returns true if the line marks the end of an except block body.
  let t = line.strip()
  t.startsWith("except ") or t.startsWith("except:") or
  t.startsWith("finally") or t.startsWith("finally:") or
  t == "end" or t == "else:" or t.startsWith("else:")

proc checkRuleS3(lines: seq[string]; mask: seq[bool]; path: string) =
  var i = 0
  while i < lines.len:
    if mask[i]:
      i += 1
      continue
    let line = lines[i]
    let trimmed = line.strip()
    i += 1

    # Must be an except line ending with :
    if not (trimmed.startsWith("except") and trimmed.endsWith(":")):
      continue
    if hasBestEffort(line) or hasFailClosedSilent(line):
      continue

    # Determine the colon position (the one at the end, not the one after "except")
    let lastColon = trimmed.rfind(":")
    if lastColon < 0:
      continue
    let afterColon = trimmed[lastColon+1 .. ^1].strip

    # If there's code after the colon (e.g., `except: discard`), it has a body.
    if afterColon.len > 0:
      continue

    # Multi-line: scan forward until we hit a block boundary.
    # The body is "empty" if all lines are blank, comments, or discards.
    var j = i
    var bodyEmpty = true
    while j < lines.len:
      if mask[j]:
        j += 1
        continue
      let bt = lines[j].strip()
      if bt.len == 0:
        j += 1
        continue
      if isBlockBoundary(lines[j]):
        break
      # Count as non-empty only if it's real code (non-comment, non-discard)
      if not bt.startsWith("#") and bt != "discard":
        bodyEmpty = false
        break
      j += 1
    if bodyEmpty:
      addFinding(path, i, "S3", "Empty/trivial except block (body is only comments, discards, or empty)")

# ---------------------------------------------------------------------------
# Rule S4 — Critical Write Discard
# Flag `discard <call>` to verification-critical functions without best-effort tag
# ---------------------------------------------------------------------------

proc isCriticalWriteName(name: string): bool =
  ## Returns true if the function name suggests a verification-critical
  ## write/persist operation whose return value should not be silently dropped.
  let n = name.toLowerAscii()
  # Exact or substring matches for critical-write semantics
  "writefile" in n or
  "writecertificate" in n or
  "atomicwrite" in n or
  "store" in n or
  "commit" in n or
  "persist" in n or
  "appendlog" in n or
  # "save" is common but we only flag it when combined with context clues
  # (handled separately below)
  false

proc hasSaveContext(line: string): bool =
  ## For the generic "save" keyword, require additional context to avoid
  ## false positives (e.g., `saveToFile` in non-critical paths).
  let t = line.toLowerAscii()
  "savesettings" in t or "saveconfig" in t or "savestate" in t or
  "savecertif" in t or "saveproof" in t or "savedata" in t or
  "savecache" in t

proc checkRuleS4(lines: seq[string]; mask: seq[bool]; path: string) =
  for i, line in lines:
    if mask[i]:
      continue
    let trimmed = line.strip()

    # Skip if no discard keyword at all
    if "discard" notin trimmed:
      continue

    # Must NOT carry the best-effort exemption tag
    if hasBestEffort(line) or hasFailClosedSilent(line):
      continue

    # Extract the call target name from `discard <name>(...)` or `discard mod.name(...)`
    # Pattern: discard followed by optional whitespace then an identifier or dot expression
    let afterDiscard = trimmed[trimmed.find("discard") + 7 .. ^1].strip()
    if afterDiscard.len == 0:
      continue

    # Get the first token (the call target name)
    var callTarget = ""
    if afterDiscard[0] in {'a'..'z', 'A'..'Z', '_'}:
      var j = 0
      while j < afterDiscard.len and afterDiscard[j] in {'a'..'z', 'A'..'Z', '_', '0'..'9'}:
        callTarget.add(afterDiscard[j])
        j.inc
    elif afterDiscard[0] == '.':
      # Shouldn't happen at start of discard arg, skip
      continue
    else:
      continue

    if callTarget.len == 0:
      continue

    # Check if this is a critical write function
    if isCriticalWriteName(callTarget) or hasSaveContext(trimmed):
      addFinding(path, i + 1, "S4",
        "Critical write discard: `discard " & callTarget & "(...)` drops verification result " &
        "(add # axiom:best-effort(reason) annotation if intentional)")

# ---------------------------------------------------------------------------
# Rule S5 — Unreachable Stub Detection
# Flag `doAssert false` / `assert false` with "NOT IMPLEMENTED" message
# in test files. Exempt intentional guards (should-not-reach, exhaustive, etc.)
# ---------------------------------------------------------------------------

proc isIntentionalGuard(message: string): bool =
  ## Returns true if the assert message indicates an intentional invariant
  # guard rather than a generator-emitted stub.
  let m = message.toLowerAscii()
  "should not" in m or
  "exhaustive" in m or
  "invariant" in m or
  "release mode" in m or
  "timeout" in m or
  "unreachable" in m or
  "failed" in m or
  "not found from" in m  # repo_root.nim guard pattern

proc extractAssertMessage(line: string): string =
  ## Extract the message string from `doAssert false, "message"` or
  ## `assert false, "message"` patterns.
  let commaIdx = line.find(",")
  if commaIdx < 0:
    return ""
  let rest = line[commaIdx + 1 .. ^1].strip()
  # Remove surrounding quotes
  if rest.startsWith("\"") and rest.endsWith("\"") and rest.len > 2:
    return rest[1 .. rest.len - 2]
  if rest.startsWith("'") and rest.endsWith("'") and rest.len > 2:
    return rest[1 .. rest.len - 2]
  ""

proc checkRuleS5(lines: seq[string]; mask: seq[bool]; path: string) =
  # Only scan test files
  if not isTestDir(path):
    return

  for i, line in lines:
    if mask[i]:
      continue
    let trimmed = line.strip()

    # Match doAssert false or assert false (both standalone and inline-with-message forms)
    let isDoAssertFalse = trimmed.startsWith("doAssert false") or trimmed == "doAssert false"
    let isAssertFalse = trimmed.startsWith("assert false") or trimmed == "assert false"
    if not (isDoAssertFalse or isAssertFalse):
      continue

    # Extract message from inline form: `doAssert false, "msg"` or multi-line form
    var msg = extractAssertMessage(trimmed)

    # If no inline message, check next line for comma-separated message
    if msg.len == 0 and i + 1 < lines.len and not mask[i+1]:
      let nextLine = lines[i+1].strip()
      if nextLine.startsWith(","):
        msg = extractAssertMessage(nextLine)

    # Only flag if message contains "NOT IMPLEMENTED" pattern
    if "not implemented" notin msg.toLowerAscii():
      continue

    # Exempt intentional guards
    if isIntentionalGuard(msg):
      continue

    # Skip if carries best-effort exemption
    if hasBestEffort(line) or (i + 1 < lines.len and not mask[i+1] and hasBestEffort(lines[i+1])):
      continue

    addFinding(path, i + 1, "S5",
      "Unreachable stub: `doAssert false` with \"NOT IMPLEMENTED\" message — " &
      "generator-emitted placeholder, not a real assertion")

# ---------------------------------------------------------------------------
# Rule C — CI Fail-Open Swallow (parity: anti_theater_gate.nim rule C)
# Flag `|| true` / `|| :` / `|| rm ...` / `|| echo ...` in CI files.
# ---------------------------------------------------------------------------

proc matchesCIFile(path: string): bool =
  ## CI config file set, mirroring anti_theater_gate.nim matchesCIFile:
  ## root Makefile, any *.mk, .circleci/*.yml, .github/workflows/**.yml|yaml,
  ## .github/actions/**.yml|yaml. Path-form tolerant (relative or absolute).
  ## `endsWith("/Makefile")` deliberately also matches Makefiles found under
  ## scanned subdirectories — a full-tree scan should treat them as CI files.
  let p = path.replace('\\', '/')
  p == "Makefile" or p.endsWith("/Makefile") or
  p.endsWith(".mk") or
  ((p.startsWith(".circleci/") or "/.circleci/" in p) and p.endsWith(".yml")) or
  ((p.startsWith(".github/workflows/") or "/.github/workflows/" in p) and
     (p.endsWith(".yml") or p.endsWith(".yaml"))) or
  ((p.startsWith(".github/actions/") or "/.github/actions/" in p) and
     (p.endsWith(".yml") or p.endsWith(".yaml")))

proc stripCiComment(line: string): string =
  ## Returns the portion of `line` before the first `#` that is not inside a
  ## quoted scalar. `#` is the comment introducer in Make (GNU Make manual,
  ## "What Makefiles Contain") and in YAML 1.2.2 (c-comment; excluded inside
  ## quoted scalars); Make recipe lines are handed to the shell, where `#`
  ## also comments. Tag exemptions are checked on RAW lines, so a tag written
  ## in the trailing comment still exempts its line.
  var inSingle = false
  var inDouble = false
  for i, c in line:
    case c
    of '\'':
      if not inDouble:
        inSingle = not inSingle
    of '"':
      if not inSingle:
        inDouble = not inDouble
    of '#':
      if not inSingle and not inDouble:
        return line[0 ..< i]
    else:
      discard
  result = line

proc hasFailOpenSwallow(line: string): bool =
  ## Signature parity with anti_theater_gate.nim hasFailOpenSwallow:
  ## known-dangerous swallow patterns whose RHS makes a failing LHS succeed:
  ## `|| true`, `|| :`, `|| rm ...`, `|| echo ...`.
  ## NOT a general fail-open verifier: `|| exit ...` is fail-closed, never
  ## flagged. Line-local: a `cmd || \` continuation hiding `true` on the next
  ## line is not seen (same limitation as the reference gate).
  let parts = line.split("||")
  if parts.len < 2:
    return false
  let rhs = parts[^1].strip()
  rhs == "true" or rhs.startsWith("true ") or rhs.startsWith("true#") or
  rhs == ":" or
  rhs.startsWith("rm ") or
  rhs.startsWith("echo ")

proc checkRuleC(lines: seq[string]; path: string) =
  ## Detection runs on the comment-stripped line (a `|| true` inside a comment
  ## is not executable); the exemption tags (`# axiom:best-effort(reason)`,
  ## `# fail-closed: silent-by-design(reason)`) are honored on the pattern line
  ## or the line immediately above, checked against the RAW lines. No Nim
  ## string mask — CI files are not Nim sources.
  for i, line in lines:
    if hasBestEffort(line) or hasFailClosedSilent(line):
      continue
    if i > 0 and (hasBestEffort(lines[i-1]) or hasFailClosedSilent(lines[i-1])):
      continue
    if hasFailOpenSwallow(stripCiComment(line)):
      addFinding(path, i + 1, "C",
        "CI fail-open swallow: `|| <true|:|rm|echo>` silences command failure " &
        "(add # axiom:best-effort(reason) on/above the line, or handle the failure)")

proc scanCIFile(path: string) =
  let content = readFile(path)
  let lines = content.splitLines()
  if lines.len == 0:
    return
  checkRuleC(lines, path)

# ---------------------------------------------------------------------------
# Rule S6 — Raw proof-status comparison (parity: anti_theater_gate.nim rule S3)
# Flag raw `status`/`vsProved` equality in proof-authoritative src|tools .nim.
# ---------------------------------------------------------------------------

# The needle is assembled from fragments — the same self-flag-avoidance
# technique anti_theater_gate.nim uses for its own audit needle
# (`const needle = "# " & "axiom:best-effort"`): the commit-time gate scans
# this file's added lines with rule S3, so the exact literal must not appear
# contiguously on any source line of this file.
const vsProvedRawNeedle = "status == " & "vsProved"

proc matchesSrcOrToolsNim(path: string): bool =
  (path.startsWith("src/") or "/src/" in path or
   path.startsWith("tools/") or "/tools/" in path) and
  path.endsWith(".nim")

proc isProofAuthoritativeNim(path: string): bool =
  ## Mirrors anti_theater_gate.nim matchesProofAuthoritativeFile: src|tools
  ## .nim, excluding the semantic-helper SSOT (verification_result_types.nim —
  ## the sanctioned place that raw-compares) and this scanner's own source
  ## (same self-reference carve-out the reference grants anti_theater_gate.nim:
  ## the detector literal and its docs would otherwise self-flag). Test trees
  ## are out of scope.
  matchesSrcOrToolsNim(path) and
  not isTestDir(path) and
  not path.endsWith("verification_result_types.nim") and
  not path.endsWith("anti_theater_gate.nim") and
  not path.endsWith("check_nim_theater.nim")

proc checkRuleS6(lines: seq[string]; mask: seq[bool]; path: string) =
  ## Substring parity with anti_theater_gate.nim hasVsProvedRaw — the needle
  ## subsumes the dotted `.status`-prefixed form. Raw comparison bypasses the
  ## isProved()/isUnboundedProved()/isBoundedProved() helper layer, enabling
  ## proof-authoritative decisions without scope awareness. No tag exemption
  ## (reference parity); patterns inside multi-line string literals are masked.
  for i, line in lines:
    if mask[i]:
      continue
    if vsProvedRawNeedle in line:
      addFinding(path, i + 1, "S6",
        "Raw proof-status comparison: `" & vsProvedRawNeedle & "` bypasses the " &
        "isProved()/isUnboundedProved()/isBoundedProved() helper layer")

# ---------------------------------------------------------------------------
# Main scanner
# ---------------------------------------------------------------------------

proc scanFile(filePath: string) =
  if not fileExists(filePath):
    echo "WARN: file not found: ", filePath
    return
  if not filePath.endsWith(".nim"):
    return

  let content = readFile(filePath)
  let lines = content.splitLines()

  if lines.len == 0:
    return

  let mask = buildStringMask(lines)

  checkRuleS1(lines, mask, filePath)
  checkRuleS2(lines, mask, filePath)
  checkRuleS3(lines, mask, filePath)
  checkRuleS4(lines, mask, filePath)
  checkRuleS5(lines, mask, filePath)
  if isProofAuthoritativeNim(filePath):
    checkRuleS6(lines, mask, filePath)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  var args = commandLineParams()
  if args.len == 0:
    echo "Usage: check_nim_theater [--allowlist <file>] <path1> [path2 ...]"
    quit(1)

  var paths: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--allowlist" or args[i] == "--allow-list":
      i += 1
      if i < args.len:
        loadAllowlist(args[i])
      else:
        echo "ERROR: --allowlist requires a file path argument"
        quit(1)
    else:
      paths.add(args[i])
    i += 1

  if paths.len == 0:
    echo "ERROR: no paths to scan"
    quit(1)

  for p in paths:
    if dirExists(p):
      for f in walkDirRec(p):
        if f.endsWith(".nim"):
          scanFile(f)
        elif matchesCIFile(f):
          scanCIFile(f)
    elif fileExists(p):
      if p.endsWith(".nim"):
        scanFile(p)
      elif matchesCIFile(p):
        scanCIFile(p)
    else:
      echo "WARN: path not found: ", p

  # Sort findings by path and line
  sort(findings, proc (a, b: Finding): int =
    result = cmp(a.path, b.path)
    if result == 0:
      result = cmp(a.line, b.line)
  )

  for f in findings:
    printFinding(f)

  if findings.len > 0:
    echo ""
    echo "FAIL: ", findings.len, " theater pattern(s) detected"
    quit(1)
  else:
    echo "PASS: no theater patterns detected"
    quit(0)
