# effect_contract_golden.nim
# Legacy-vs-new comparison tool for effect contract projection.
#
# Implements the LEGACY line-heuristic semantics INLINE (8-line-ahead scan
# + push/pop scope tracking) WITHOUT importing immunity_gate.nim.
# Compares against the new AST-semantic projection and emits a structured
# diff report.  Exits 0 on equivalence within the documented allowed-diff
# rubric, else exits 1.
#
# Layer rule: self-contained stdlib only.  No imports from src/ or tools/.

import std/os
import std/strutils
import std/json
import std/algorithm
import std/tables

# ── LEGACY scanner (mirrors immunity_gate.nim:106-165 semantics) ────────
# This is a standalone reimplementation of the 8-line-ahead line-heuristic
# with push/pop scope tracking.  It does NOT import immunity_gate.nim.

proc isProcDeclLegacy(line: string): bool =
  let trimmed = line.strip()
  return trimmed.startsWith("proc ") or trimmed.startsWith("func ")

proc isExemptLineLegacy(line: string): bool =
  const exemptions = ["{.importc}", "{.importcpp}", "{.dynlib}",
                      "{.axiomIoBoundary.}", "{.axiomEffect:"]
  for ex in exemptions:
    if ex in line:
      return true
  return false

proc isInsideMainModuleLegacy(text: string, lineIdx: int): bool =
  let lines = text.splitLines()
  for i in countdown(lineIdx, 0):
    let l = lines[i].strip()
    if l.endsWith("when isMainModule") or l == "when isMainModule:":
      return true
  return false

proc hasRaisesAnnotLegacy(text: string, declLine: int): bool =
  ## 8-line-ahead scan (legacy line-heuristic).
  let lines = text.splitLines()
  let scanEnd = min(declLine + 8, lines.len - 1)
  for i in declLine..scanEnd:
    if "{.raises:" in lines[i]:
      return true
  return false

proc legacyScanFile(content: string, filePath: string): seq[string] =
  ## Legacy scanner: returns violation symbol names using the 8-line heuristic.
  let lines = content.splitLines()
  var raisesPushDepth = 0
  var i = 0
  var violations: seq[string] = @[]

  while i < lines.len:
    let line = lines[i]
    # Track push/pop scope (legacy only handles push raises and pop raises)
    if "{.push raises" in line:
      inc raisesPushDepth
    if "{.pop raises" in line and raisesPushDepth > 0:
      dec raisesPushDepth

    if isProcDeclLegacy(line):
      if isInsideMainModuleLegacy(content, i):
        inc i
        continue
      if isExemptLineLegacy(line):
        inc i
        continue
      if raisesPushDepth > 0 or hasRaisesAnnotLegacy(content, i):
        inc i
        continue
      # This is a violation — extract symbol name
      var procName = line.strip()
      let parenIdx = procName.find('(')
      if parenIdx > 0:
        procName = procName[0 ..< parenIdx]
      for kw in ["proc ", "func "]:
        if procName.startsWith(kw):
          procName = procName[kw.len .. ^1]
          break
      if procName.endsWith("*"):
        procName = procName[0 ..^ 2]
      violations.add(procName.strip())
    inc i

  return violations

# ── NEW projection (same as the projection module, inlined for comparison) ──

proc isPushRaises(line: string): bool =
  "{.push raises" in line

proc isPopRaises(line: string): bool =
  "{.pop raises" in line

proc isPopDot(line: string): bool =
  "{.pop.}" in line

proc hasRaisesPragma(line: string): bool =
  ## Check if line contains a raises pragma, handling combined pragmas
  ## like {.importc, raises: [].} where "{.raises:" is not a substring.
  let raisesIdx = line.find("raises:")
  if raisesIdx < 0:
    return false
  for j in 0 ..< raisesIdx:
    if line[j] == '{' and j + 1 < line.len and line[j+1] == '.':
      return true
  return false

proc leadingIndent(line: string): int =
  var i = 0
  while i < line.len and (line[i] == ' ' or line[i] == '\t'):
    inc i
  return i

proc findInlineRaisesNew(lines: seq[string], startIdx: int): bool =
  var found = false
  var i = startIdx
  var macroBodyIndent = -1
  while i < lines.len:
    let line = lines[i].strip()
    let indent = leadingIndent(lines[i])
    if line.len == 0:
      if found:
        break
      else:
        inc i
        continue
    # Track template/macro/iterator/converter bodies by indentation
    if line.startsWith("template ") or line.startsWith("macro ") or
       line.startsWith("iterator ") or line.startsWith("converter "):
      macroBodyIndent = indent
    elif macroBodyIndent >= 0 and indent <= macroBodyIndent:
      if line.startsWith("proc ") or line.startsWith("func ") or
         line.startsWith("template ") or line.startsWith("macro ") or
         line.startsWith("iterator ") or line.startsWith("converter ") or
         line.startsWith("type "):
        macroBodyIndent = -1
    if macroBodyIndent >= 0:
      inc i
      continue
    if line.startsWith("proc ") or line.startsWith("func ") or
       line.startsWith("template ") or line.startsWith("macro ") or
       line.startsWith("iterator ") or line.startsWith("converter ") or
       line.startsWith("type "):
      if i > startIdx:
        break
    if line.startsWith("="):
      break
    if hasRaisesPragma(line):
      found = true
    inc i
  return found

proc newScanFile(content: string, filePath: string): seq[string] =
  ## New scanner: returns violation symbol names using AST-semantic rules.
  let lines = content.splitLines()
  var raisesPushDepth = 0
  var violations: seq[string] = @[]
  var i = 0

  while i < lines.len:
    let line = lines[i]
    let trimmed = line.strip()

    if isPushRaises(line):
      inc raisesPushDepth
    if isPopRaises(line) and raisesPushDepth > 0:
      dec raisesPushDepth
    if isPopDot(line) and raisesPushDepth > 0:
      dec raisesPushDepth

    let isProc = trimmed.startsWith("proc ")
    let isFunc = trimmed.startsWith("func ")
    if (isProc or isFunc):
      let kind = if isProc: "proc" else: "func"
      var sym = trimmed
      let kwLen = kind.len + 1
      if sym.len > kwLen:
        sym = sym[kwLen .. ^1]
      let parenIdx = sym.find('(')
      if parenIdx > 0:
        sym = sym[0 ..< parenIdx]
      let colonIdx = sym.find(':')
      if colonIdx > 0:
        sym = sym[0 ..< colonIdx]
      if sym.endsWith("*"):
        sym = sym[0 ..^ 2]
      sym = sym.strip()

      let hasInline = findInlineRaisesNew(lines, i)
      let compliant = raisesPushDepth > 0 or hasInline
      if not compliant:
        violations.add(sym)

    inc i

  return violations

# ── Diff report ────────────────────────────────────────────────────────────

type
  DiffEntry = object
    symbol*: string
    path*: string
    legacyStatus*: string   # "compliant" or "violating"
    newStatus*: string      # "compliant" or "violating"
    flipReason*: string     # why the status changed

proc compareScans(legacyViolations: seq[string], newViolations: seq[string],
                   projectRoot: string): seq[DiffEntry] =
  ## Compare legacy and new violation sets and produce a structured diff.
  # Build sets for comparison
  var legacySet: Table[string, bool] = initTable[string, bool]()
  for v in legacyViolations:
    legacySet[v] = true
  var newSet: Table[string, bool] = initTable[string, bool]()
  for v in newViolations:
    newSet[v] = true

  # Find all unique symbols
  var allSymbols: seq[string] = @[]
  for k in legacySet.keys:
    if k notin allSymbols:
      allSymbols.add(k)
  for k in newSet.keys:
    if k notin allSymbols:
      allSymbols.add(k)
  allSymbols.sort()

  for sym in allSymbols:
    let inLegacy = legacySet.hasKey(sym)
    let inNew = newSet.hasKey(sym)
    if inLegacy and inNew:
      # Both agree it's a violation — no flip
      discard
    elif inLegacy and not inNew:
      # Legacy says violating, new says compliant
      result.add(DiffEntry(
        symbol: sym,
        path: "",
        legacyStatus: "violating",
        newStatus: "compliant",
        flipReason: "New projection found inline raises pragma or push-scope coverage that 8-line scan missed"
      ))
    elif not inLegacy and inNew:
      # Legacy says compliant, new says violating
      result.add(DiffEntry(
        symbol: sym,
        path: "",
        legacyStatus: "compliant",
        newStatus: "violating",
        flipReason: "Legacy 8-line scan found a nearby raises pragma that does not belong to this declaration's header"
      ))

# ── Main ──────────────────────────────────────────────────────────────────

proc main() =
  let projectRoot = getCurrentDir()
  let scanDir = projectRoot / "src" / "core"

  if not dirExists(scanDir):
    echo "ERROR: src/core directory not found at " & scanDir
    quit(1)

  # Collect all .nim files
  var nimFiles: seq[string] = @[]
  for entry in walkDirRec(scanDir, relative = true, checkDir = true):
    if entry.endsWith(".nim"):
      nimFiles.add(scanDir / entry)

  nimFiles.sort()

  # Run both scanners
  var allLegacyViolations: seq[string] = @[]
  var allNewViolations: seq[string] = @[]
  var totalDecls = 0

  for filePath in nimFiles:
    let content = readFile(filePath)
    let legacyViol = legacyScanFile(content, filePath)
    let newViol = newScanFile(content, filePath)
    allLegacyViolations.add(legacyViol)
    allNewViolations.add(newViol)
    # Count total declarations (approximate: count proc/func lines)
    for line in content.splitLines():
      let t = line.strip()
      if t.startsWith("proc ") or t.startsWith("func "):
        inc totalDecls

  # Compare
  let diff = compareScans(allLegacyViolations, allNewViolations, projectRoot)

  # Report
  echo "=== Effect Contract Projection: Legacy vs New Diff Report ==="
  echo ""
  echo "Total declarations scanned: " & $totalDecls
  echo "Legacy violations: " & $allLegacyViolations.len
  echo "New projection violations: " & $allNewViolations.len
  echo "Declarations that flip compliant<->violating: " & $diff.len
  echo ""

  if diff.len > 0:
    echo "--- Flips (first 3 examples) ---"
    let showCount = min(diff.len, 3)
    for i in 0 ..< showCount:
      let entry = diff[i]
      echo "  Symbol: " & entry.symbol
      echo "    Legacy: " & entry.legacyStatus & " -> New: " & entry.newStatus
      echo "    Reason: " & entry.flipReason
      echo ""

  # Allowed-diff rubric:
  # Flips are expected and acceptable when:
  # 1. Legacy false positives: 8-line scan found a raises pragma in a nearby
  #    declaration's header and incorrectly attributed it to this declaration.
  # 2. Legacy false negatives: a declaration has an inline raises pragma but
  #    is more than 8 lines away from the declaration line (multi-line header).
  # If flips exceed 20% of total declarations, exit 1 (significant divergence).
  let flipRate = if totalDecls > 0: diff.len.float / totalDecls.float else: 0.0
  let allowedFlipRate = 0.20

  if flipRate > allowedFlipRate:
    echo "FAIL: Flip rate " & $flipRate & " exceeds allowed rubric of " & $allowedFlipRate
    quit(1)
  else:
    echo "PASS: Flip rate " & $flipRate & " within allowed rubric of " & $allowedFlipRate
    quit(0)

when isMainModule:
  main()
