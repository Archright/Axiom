## migrate_theater_allowlist.nim — Migrate theater allowlist to symbol-based anchor.
##
## Reads the legacy allowlist JSON (file + line + rule), resolves the enclosing
## top-level declaration symbol for each exact file+line entry, and writes a
## canonical allowlist JSON where every entry carries a `"symbol"` field.
##
## Canonical anchor identity: `file + symbol + rule`. The `line` field is kept
## as derived evidence only — never part of the matching key.
##
## Usage:
##   nim c -o:bin/migrate_theater_allowlist tools/ci/migrate_theater_allowlist.nim
##
##   # Generate migrated allowlist (dry-run, prints to stdout):
##   bin/migrate_theater_allowlist --allowlist tools/ci/nim_theater_allowlist.json
##
##   # Write migrated allowlist to disk:
##   bin/migrate_theater_allowlist --allowlist tools/ci/nim_theater_allowlist.json \
##     --output tools/ci/nim_theater_allowlist.json
##
##   # Verify semantic equivalence (legacy matcher == canonical matcher):
##   bin/migrate_theater_allowlist --allowlist tools/ci/nim_theater_allowlist.json \
##     --verify --scan-paths src/ tests/ tools/
##
## Exit code: 0 = success, 1 = failure (equivalence mismatch or other error)

import std/[algorithm, os, json, strutils, sequtils]

# ---------------------------------------------------------------------------
# Allowlist types
# ---------------------------------------------------------------------------

type
  LegacyEntry = object
    file: string
    line: int
    rule: string
    reason: string
    rationale: string

  CanonicalEntry = object
    file: string
    symbol: string
    rule: string
    reason: string
    rationale: string
    line: int  # derived evidence only

# ---------------------------------------------------------------------------
# Symbol resolver (mirrors check_nim_theater.nim for self-contained verify)
# ---------------------------------------------------------------------------

proc extractDeclName(line: string; keyword: string): string =
  let kwLen = keyword.len
  if line.len < kwLen + 1: return ""
  let afterKw = line[kwLen .. ^1]
  if afterKw.len == 0 or afterKw[0] notin {' ', '\t'}: return ""
  var i = 0
  while i < afterKw.len and afterKw[i] in {' ', '\t'}: i.inc
  if i >= afterKw.len: return ""
  let rest = afterKw[i .. ^1]
  if rest[0] == '`':
    let endIdx = rest.find('`', 1)
    if endIdx > 0: return rest[1 ..< endIdx]
    return rest[1 .. ^1]
  var j = 0
  while j < rest.len and (rest[j].isAlphaAscii or rest[j] == '_' or rest[j].isDigit):
    j.inc
  if j > 0: result = rest[0 ..< j]

proc resolveSymbol(path: string; lineNum: int): string =
  ## Resolve the enclosing top-level declaration name at (path, lineNum).
  ## Scans preceding lines backwards for the nearest declaration start.
  ## Falls back to file basename when no declaration encloses the line.
  let absPath = absolutePath(path)
  if not fileExists(absPath): return splitFile(absPath).name
  let content = readFile(absPath)
  let lines = content.splitLines()
  let target = lineNum - 1
  if target < 0 or target >= lines.len: return splitFile(absPath).name

  let declKeywords = ["proc", "func", "template", "macro", "iterator",
                      "converter", "type", "concept"]

  for i in countdown(target, 0):
    let trimmed = lines[i].strip()
    if trimmed.len == 0 or trimmed.startsWith("#"): continue

    if trimmed.startsWith("resource"):
      let name = extractDeclName(trimmed, "resource")
      if name.len > 0: return name
      continue

    for kw in declKeywords:
      if trimmed.startsWith(kw & " "):
        let name = extractDeclName(trimmed, kw)
        if name.len > 0: return name
        break  # keyword found but no name — keep scanning

  result = splitFile(absPath).name

# ---------------------------------------------------------------------------
# Legacy allowlist loader
# ---------------------------------------------------------------------------

proc loadLegacyAllowlist(path: string): seq[LegacyEntry] =
  if not fileExists(path):
    echo "WARN: allowlist file not found: ", path
    return
  let content = readFile(path)
  if content.strip.len == 0: return
  let jsonNode = parseJson(content)
  if jsonNode.kind != JArray:
    echo "WARN: allowlist is not a JSON array, ignoring"
    return
  for entry in jsonNode:
    result.add(LegacyEntry(
      file: entry["file"].getStr(""),
      line: entry["line"].getInt(0),
      rule: entry["rule"].getStr(""),
      reason: entry["reason"].getStr(""),
      rationale: entry.getOrDefault("rationale").getStr("")
    ))

# ---------------------------------------------------------------------------
# Migration: legacy → canonical
# ---------------------------------------------------------------------------

proc migrate(entries: seq[LegacyEntry]): seq[CanonicalEntry] =
  for e in entries:
    var sym = ""
    if e.line > 0:
      sym = resolveSymbol(e.file, e.line)
    result.add(CanonicalEntry(
      file: e.file,
      symbol: sym,
      rule: e.rule,
      reason: e.reason,
      rationale: e.rationale,
      line: e.line
    ))

# ---------------------------------------------------------------------------
# Canonical allowlist loader (for --verify)
# ---------------------------------------------------------------------------

proc loadCanonicalAllowlist(path: string): seq[CanonicalEntry] =
  if not fileExists(path):
    echo "WARN: allowlist file not found: ", path
    return
  let content = readFile(path)
  if content.strip.len == 0: return
  let jsonNode = parseJson(content)
  if jsonNode.kind != JArray:
    echo "WARN: allowlist is not a JSON array, ignoring"
    return
  for entry in jsonNode:
    result.add(CanonicalEntry(
      file: entry["file"].getStr(""),
      symbol: entry.getOrDefault("symbol").getStr(""),
      rule: entry["rule"].getStr(""),
      reason: entry["reason"].getStr(""),
      rationale: entry.getOrDefault("rationale").getStr(""),
      line: entry["line"].getInt(0)
    ))

# ---------------------------------------------------------------------------
# Legacy matcher (same logic as old isAllowlisted)
# ---------------------------------------------------------------------------

proc legacyMatch(path: string; lineNum: int; rule: string;
                 allowlist: seq[LegacyEntry]): bool =
  let absPath = absolutePath(path)
  for e in allowlist:
    let eAbs = absolutePath(e.file)
    if not (absPath.startsWith(eAbs) or eAbs == absPath): continue
    if e.line == 0 and e.rule == rule: return true
    if e.line == lineNum and e.rule == rule: return true
  false

# ---------------------------------------------------------------------------
# Canonical matcher (symbol-first, legacy fallback)
# ---------------------------------------------------------------------------

proc canonicalMatch(path: string; lineNum: int; rule: string;
                    allowlist: seq[CanonicalEntry]): bool =
  let absPath = absolutePath(path)
  for e in allowlist:
    let eAbs = absolutePath(e.file)
    if not (absPath.startsWith(eAbs) or eAbs == absPath): continue
    if e.symbol.len > 0:
      let sym = resolveSymbol(path, lineNum)
      if sym == e.symbol and e.rule == rule: return true
      continue
    if e.line == 0 and e.rule == rule: return true
    if e.line == lineNum and e.rule == rule: return true
  false

# ---------------------------------------------------------------------------
# Minimal scanner — collects raw findings without allowlist filtering
# (duplicates S1-S5 rules from check_nim_theater.nim for self-contained verify)
# ---------------------------------------------------------------------------

type RawFinding = object
  path: string
  line: int
  rule: string
  message: string

proc stripLineComment(line: string): string =
  let idx = line.find('#')
  if idx >= 0: line[0 ..< idx] else: line

proc countTripleQuotes(line: string): int =
  var i = 0
  while i < line.len:
    if line[i] == '"' and i + 2 < line.len and
       line[i+1] == '"' and line[i+2] == '"':
      inc result; inc i, 3
    else: inc i

proc buildStringMask(lines: seq[string]): seq[bool] =
  result = newSeq[bool](lines.len)
  var inString = false
  for i, line in lines:
    let n = countTripleQuotes(stripLineComment(line))
    if n == 0: result[i] = inString
    else:
      if (n mod 2) == 1: inString = not inString
      result[i] = false

proc hasBestEffort(line: string): bool =
  "axiom:best-effort(" in line.strip()

proc hasFailClosedSilent(line: string): bool =
  "fail-closed: silent-by-design(" in line.strip()

proc hasCompileCheck(line: string): bool =
  "axiom:compile-check" in line.strip()

proc isTestDir(path: string): bool =
  path.startsWith("tests/") or "/tests/" in path

proc isBlockBoundary(line: string): bool =
  let t = line.strip()
  t.startsWith("except ") or t.startsWith("except:") or
  t.startsWith("finally") or t.startsWith("finally:") or
  t == "end" or t == "else:" or t.startsWith("else:")

proc isIntentionalGuard(message: string): bool =
  let m = message.toLowerAscii()
  "should not" in m or "exhaustive" in m or "invariant" in m or
  "release mode" in m or "timeout" in m or "unreachable" in m or
  "failed" in m or "not found from" in m

proc extractAssertMessage(line: string): string =
  let commaIdx = line.find(",")
  if commaIdx < 0: return ""
  let rest = line[commaIdx + 1 .. ^1].strip()
  if rest.startsWith("\"") and rest.endsWith("\"") and rest.len > 2:
    return rest[1 .. rest.len - 2]
  if rest.startsWith("'") and rest.endsWith("'") and rest.len > 2:
    return rest[1 .. rest.len - 2]
  ""

proc isCriticalWriteName(name: string): bool =
  let n = name.toLowerAscii()
  "writefile" in n or "writecertificate" in n or "atomicwrite" in n or
  "store" in n or "commit" in n or "persist" in n or "appendlog" in n

proc hasSaveContext(line: string): bool =
  let t = line.toLowerAscii()
  "savesettings" in t or "saveconfig" in t or "savestate" in t or
  "savecertif" in t or "saveproof" in t or "savedata" in t or "savecache" in t

proc scanFileRaw(filePath: string): seq[RawFinding] =
  if not fileExists(filePath): return
  if not filePath.endsWith(".nim"): return
  let content = readFile(filePath)
  let lines = content.splitLines()
  if lines.len == 0: return
  let mask = buildStringMask(lines)

  # S1 — Swallowed Failure
  var i = 0
  while i < lines.len:
    if mask[i]: inc i; continue
    let trimmed = lines[i].strip()
    if trimmed.startsWith("except CatchableError:") and trimmed.endsWith(":"):
      if hasBestEffort(lines[i]) or hasFailClosedSilent(lines[i]):
        inc i; continue
      let afterColon = trimmed[trimmed.find(":")+1 .. ^1].strip
      if afterColon.len > 0 and afterColon != "discard":
        inc i; continue
      if afterColon == "discard":
        if hasBestEffort(lines[i]) or hasFailClosedSilent(lines[i]):
          inc i; continue
        result.add(RawFinding(path: filePath, line: i + 1, rule: "S1",
          message: "Swallowed failure: except CatchableError: discard"))
        inc i; continue
      if i + 1 < lines.len:
        let nextTrimmed = lines[i+1].strip()
        if nextTrimmed == "discard" and not mask[i+1]:
          if hasBestEffort(lines[i]) or hasFailClosedSilent(lines[i]) or
             hasBestEffort(lines[i+1]) or hasFailClosedSilent(lines[i+1]):
            inc i; continue
          result.add(RawFinding(path: filePath, line: i + 1, rule: "S1",
            message: "Swallowed failure: except CatchableError: discard"))
    if trimmed.startsWith("try:"):
      var j = i + 1
      while j < lines.len and j < i + 5:
        if mask[j]: inc j; continue
        let lt = lines[j].strip()
        if (lt.startsWith("except ") or lt.startsWith("except:")) and
           "CatchableError" in lt and "discard" in lt:
          if not hasBestEffort(lines[j]) and not hasFailClosedSilent(lines[j]):
            result.add(RawFinding(path: filePath, line: j + 1, rule: "S1",
              message: "Swallowed failure: except CatchableError: discard in try block"))
          break
        inc j
    if "except CatchableError" in trimmed and "discard" in trimmed and ":" in trimmed:
      if not trimmed.startsWith("except CatchableError:") or trimmed.len > 80:
        inc i; continue
      if not hasBestEffort(lines[i]) and not hasFailClosedSilent(lines[i]):
        result.add(RawFinding(path: filePath, line: i + 1, rule: "S1",
          message: "Swallowed failure: except CatchableError: discard inline"))
    inc i

  # S2 — Always-Pass
  for i, line in lines:
    if mask[i]: continue
    let trimmed = line.strip()
    if trimmed == "check true":
      if not hasCompileCheck(line) and (i == 0 or not hasCompileCheck(lines[i-1])):
        result.add(RawFinding(path: filePath, line: i + 1, rule: "S2",
          message: "Always-pass pattern: check true"))
    if trimmed == "doAssert true" or trimmed == "assert true":
      if not hasCompileCheck(line) and (i == 0 or not hasCompileCheck(lines[i-1])):
        result.add(RawFinding(path: filePath, line: i + 1, rule: "S2",
          message: "Always-pass pattern: " & trimmed))
    if trimmed == "return true":
      let prev = if i > 0: lines[i-1].strip() else: ""
      let prev2 = if i > 1: lines[i-2].strip() else: ""
      if (prev.len == 0 or prev.startsWith("{") or prev.startsWith("#")) and
         prev2.endsWith("{.raises: [].}="):
        result.add(RawFinding(path: filePath, line: i + 1, rule: "S2",
          message: "Always-pass pattern: stub return true"))

  # S3 — Dead Catch
  i = 0
  while i < lines.len:
    if mask[i]: inc i; continue
    let trimmed = lines[i].strip()
    inc i
    if not (trimmed.startsWith("except") and trimmed.endsWith(":")): continue
    if hasBestEffort(lines[i-1]) or hasFailClosedSilent(lines[i-1]): continue
    let lastColon = trimmed.rfind(":")
    if lastColon < 0: continue
    let afterColon = trimmed[lastColon+1 .. ^1].strip
    if afterColon.len > 0: continue
    var j = i
    var bodyEmpty = true
    while j < lines.len:
      if mask[j]: inc j; continue
      let bt = lines[j].strip()
      if bt.len == 0: inc j; continue
      if isBlockBoundary(lines[j]): break
      if not bt.startsWith("#") and bt != "discard":
        bodyEmpty = false; break
      inc j
    if bodyEmpty:
      result.add(RawFinding(path: filePath, line: i, rule: "S3",
        message: "Empty/trivial except block"))

  # S4 — Critical Write Discard
  for i, line in lines:
    if mask[i]: continue
    let trimmed = line.strip()
    if "discard" notin trimmed: continue
    if hasBestEffort(line) or hasFailClosedSilent(line): continue
    let afterDiscard = trimmed[trimmed.find("discard") + 7 .. ^1].strip
    if afterDiscard.len == 0: continue
    var callTarget = ""
    if afterDiscard[0] in {'a'..'z', 'A'..'Z', '_'}:
      var j = 0
      while j < afterDiscard.len and afterDiscard[j] in {'a'..'z', 'A'..'Z', '_', '0'..'9'}:
        callTarget.add(afterDiscard[j]); j.inc
    elif afterDiscard[0] == '.': continue
    else: continue
    if callTarget.len == 0: continue
    if isCriticalWriteName(callTarget) or hasSaveContext(trimmed):
      result.add(RawFinding(path: filePath, line: i + 1, rule: "S4",
        message: "Critical write discard: " & callTarget))

  # S5 — Unreachable Stub (test files only)
  if isTestDir(filePath):
    for i, line in lines:
      if mask[i]: continue
      let trimmed = line.strip()
      let isDoAssertFalse = trimmed.startsWith("doAssert false") or trimmed == "doAssert false"
      let isAssertFalse = trimmed.startsWith("assert false") or trimmed == "assert false"
      if not (isDoAssertFalse or isAssertFalse): continue
      var msg = extractAssertMessage(trimmed)
      if msg.len == 0 and i + 1 < lines.len and not mask[i+1]:
        let nextLine = lines[i+1].strip()
        if nextLine.startsWith(","): msg = extractAssertMessage(nextLine)
      if "not implemented" notin msg.toLowerAscii(): continue
      if isIntentionalGuard(msg): continue
      if hasBestEffort(line) or (i + 1 < lines.len and not mask[i+1] and hasBestEffort(lines[i+1])):
        continue
      result.add(RawFinding(path: filePath, line: i + 1, rule: "S5",
        message: "Unreachable stub: doAssert false NOT IMPLEMENTED"))

# ---------------------------------------------------------------------------
# File walker
# ---------------------------------------------------------------------------

proc walkNimFiles(paths: openArray[string]): seq[string] =
  for p in paths:
    if dirExists(p):
      for f in walkDirRec(p):
        if f.endsWith(".nim"): result.add(f)
    elif fileExists(p):
      result.add(p)

# ---------------------------------------------------------------------------
# Apply allowlist filter to raw findings
# ---------------------------------------------------------------------------

proc applyLegacyFilter(raw: seq[RawFinding];
                       allowlist: seq[LegacyEntry]): seq[RawFinding] =
  for f in raw:
    if not legacyMatch(f.path, f.line, f.rule, allowlist):
      result.add(f)

proc applyCanonicalFilter(raw: seq[RawFinding];
                          allowlist: seq[CanonicalEntry]): seq[RawFinding] =
  for f in raw:
    if not canonicalMatch(f.path, f.line, f.rule, allowlist):
      result.add(f)

# ---------------------------------------------------------------------------
# JSON serialization helpers
# ---------------------------------------------------------------------------

proc toJson(entry: CanonicalEntry): JsonNode =
  result = newJObject()
  result["file"] = newJString(entry.file)
  result["symbol"] = newJString(entry.symbol)
  result["rule"] = newJString(entry.rule)
  result["reason"] = newJString(entry.reason)
  result["rationale"] = newJString(entry.rationale)
  result["line"] = newJInt(entry.line)

proc formatJson(entries: seq[CanonicalEntry]): string =
  if entries.len == 0: return "[]"
  var arr = newJArray()
  for e in entries: arr.add(e.toJson())
  result = pretty(arr)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  var args = commandLineParams()
  if args.len == 0:
    echo "Usage: migrate_theater_allowlist [--allowlist <file>] [--output <file>] [--verify] [--scan-paths <p1> ...]"
    quit(1)

  var allowlistPath = ""
  var outputPath = ""
  var verifyMode = false
  var scanPaths: seq[string] = @[]

  var i = 0
  while i < args.len:
    case args[i]
    of "--allowlist", "--allow-list":
      inc i; if i < args.len: allowlistPath = args[i]
    of "--output":
      inc i; if i < args.len: outputPath = args[i]
    of "--verify":
      verifyMode = true
    of "--scan-paths":
      inc i
      while i < args.len and not args[i].startsWith("--"):
        scanPaths.add(args[i]); inc i
      dec i  # will be incremented by loop
    else:
      scanPaths.add(args[i])
    inc i

  if allowlistPath.len == 0:
    echo "ERROR: --allowlist is required"
    quit(1)

  # Load legacy allowlist
  let legacyEntries = loadLegacyAllowlist(allowlistPath)
  echo "Loaded ", legacyEntries.len, " legacy allowlist entries from ", allowlistPath

  # Migrate to canonical form
  var canonicalEntries = migrate(legacyEntries)

  # Sort deterministically: by file, then line, then rule
  sort(canonicalEntries, proc (a, b: CanonicalEntry): int =
    var r = cmp(a.file, b.file)
    if r == 0: r = cmp(a.line, b.line)
    if r == 0: r = cmp(a.rule, b.rule)
    r
  )

  # Report ambiguous entries (where symbol resolution returned file-level fallback)
  var ambiguousCount = 0
  for e in canonicalEntries:
    if e.symbol.len == 0:
      echo "AMBIGUOUS: ", e.file, ":", e.line, " (no enclosing declaration found, symbol=", e.symbol, ")"
      inc ambiguousCount
  if ambiguousCount > 0:
    echo "WARNING: ", ambiguousCount, " entries resolved to file-level symbol (ambiguous)"

  # --verify mode: compare legacy vs canonical matching on full scan
  if verifyMode:
    echo ""
    echo "=== VERIFICATION MODE ==="
    echo "Scanning paths: ", scanPaths.join(", ")

    # Walk all .nim files
    let allFiles = walkNimFiles(scanPaths)
    echo "Found ", allFiles.len, " .nim files"

    # Scan all files once, collect raw findings
    var allRaw: seq[RawFinding] = @[]
    for f in allFiles:
      let findings = scanFileRaw(f)
      allRaw.add(findings)

    echo "Total raw findings (unfiltered): ", allRaw.len

    # Apply legacy filter
    var legacyFiltered = applyLegacyFilter(allRaw, legacyEntries)
    echo "Legacy-filtered findings: ", legacyFiltered.len

    # Apply canonical filter
    var canonicalFiltered = applyCanonicalFilter(allRaw, canonicalEntries)
    echo "Canonical-filtered findings: ", canonicalFiltered.len

    # Compare
    if legacyFiltered.len != canonicalFiltered.len:
      echo ""
      echo "FAIL: finding counts differ!"
      echo "  legacy:       ", legacyFiltered.len
      echo "  canonical:    ", canonicalFiltered.len
      quit(1)

    # Sort both for element-wise comparison
    sort(legacyFiltered, proc (a, b: RawFinding): int =
      var r = cmp(a.path, b.path)
      if r == 0: r = cmp(a.line, b.line)
      if r == 0: r = cmp(a.rule, b.rule)
      r
    )
    sort(canonicalFiltered, proc (a, b: RawFinding): int =
      var r = cmp(a.path, b.path)
      if r == 0: r = cmp(a.line, b.line)
      if r == 0: r = cmp(a.rule, b.rule)
      r
    )

    if legacyFiltered == canonicalFiltered:
      echo ""
      echo "PASS: legacy_findings == canonical_findings (" & $legacyFiltered.len & " findings)"
    else:
      echo ""
      echo "FAIL: filtered findings differ element-wise"
      # Show differences
      let maxLen = max(legacyFiltered.len, canonicalFiltered.len)
      for k in 0 ..< maxLen:
        if k >= legacyFiltered.len:
          echo "  [canonical only] ", canonicalFiltered[k].path, ":", canonicalFiltered[k].line, " [", canonicalFiltered[k].rule, "]"
        elif k >= canonicalFiltered.len:
          echo "  [legacy only] ", legacyFiltered[k].path, ":", legacyFiltered[k].line, " [", legacyFiltered[k].rule, "]"
        elif legacyFiltered[k] != canonicalFiltered[k]:
          echo "  [DIFF] legacy:       ", legacyFiltered[k].path, ":", legacyFiltered[k].line, " [", legacyFiltered[k].rule, "]"
          echo "  [DIFF] canonical:   ", canonicalFiltered[k].path, ":", canonicalFiltered[k].line, " [", canonicalFiltered[k].rule, "]"
      quit(1)

  # Write output
  if outputPath.len > 0:
    let jsonOutput = formatJson(canonicalEntries)
    writeFile(outputPath, jsonOutput & "\n")
    echo ""
    echo "Wrote ", canonicalEntries.len, " canonical entries to ", outputPath
  else:
    # Dry-run: print to stdout
    let jsonOutput = formatJson(canonicalEntries)
    echo ""
    echo jsonOutput
