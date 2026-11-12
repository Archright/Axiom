# effect_contract_projection.nim
# AST-semantic effect contract projection for src/core declarations.
#
# Subject universe: source-visible canonical proc/func declarations under
# src/core/**/*.nim.  Declaration identity = (path, symbol, kind).
# Macro-generated declarations (template/macro/iterator/converter bodies) are
# outside the universe — they do not exist as subjects.
#
# No line-distance heuristic.  Compliance is determined solely by whether the
# effective effect environment at the declaration point carries an explicit
# raises contract (rules 1-5 of effectiveEffectEnvironment).
#
# Stdlib only — no imports from src/ or tools/.

import std/os
import std/sequtils
import std/strutils
import std/json
import std/algorithm

# ── Types ──────────────────────────────────────────────────────────────────

type
  Declaration* = object
    path*: string
    symbol*: string
    kind*: string     # "proc" or "func"
    line*: int
    compliant*: bool

  Violation* = object
    path*: string
    symbol*: string
    kind*: string

# ── Helpers ────────────────────────────────────────────────────────────────

proc leadingIndent(line: string): int =
  ## Count leading whitespace characters (spaces/tabs).
  var i = 0
  while i < line.len and (line[i] == ' ' or line[i] == '\t'):
    inc i
  return i

proc isTopLevelDecl(line: string): tuple[isDecl: bool; kind: string] =
  ## Detect top-level proc/func/template/macro/iterator/converter/type declarations.
  let trimmed = line.strip()
  if trimmed.startsWith("proc "):
    return (true, "proc")
  if trimmed.startsWith("func "):
    return (true, "func")
  if trimmed.startsWith("template "):
    return (true, "template")
  if trimmed.startsWith("macro "):
    return (true, "macro")
  if trimmed.startsWith("iterator "):
    return (true, "iterator")
  if trimmed.startsWith("converter "):
    return (true, "converter")
  if trimmed.startsWith("type "):
    return (true, "type")
  return (false, "")

proc isProcOrFunc(line: string): tuple[isDecl: bool; kind: string] =
  let trimmed = line.strip()
  if trimmed.startsWith("proc "):
    return (true, "proc")
  if trimmed.startsWith("func "):
    return (true, "func")
  return (false, "")

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
  # Check that there's a {. before the raises: position
  for j in 0 ..< raisesIdx:
    if line[j] == '{' and j + 1 < line.len and line[j+1] == '.':
      return true
  return false

proc hasInlineRaises(line: string): bool =
  hasRaisesPragma(line)

# ── Symbol extraction ──────────────────────────────────────────────────────

proc extractSymbol(trimmedLine, kind: string): string =
  ## Extract the symbol name from a proc/func declaration line.
  var s = trimmedLine
  # Remove the kind keyword + trailing space
  let kwLen = kind.len + 1  # +1 for the space after keyword
  if s.len > kwLen and s[0 .. kwLen - 1].startsWith(kind & " "):
    s = s[kwLen .. ^1]
  # Truncate at first '(' (parameter list)
  let parenIdx = s.find('(')
  if parenIdx > 0:
    s = s[0 ..< parenIdx]
  # Truncate at first ':' (return type annotation without params)
  let colonIdx = s.find(':')
  if colonIdx > 0:
    s = s[0 ..< colonIdx]
  # Strip export marker '*'
  if s.endsWith("*"):
    s = s[0 .. ^2]
  return s.strip()

# ── Inline raises search ──────────────────────────────────────────────────

proc findInlineRaises(lines: seq[string], startIdx: int): bool =
  ## Scan forward from startIdx to find {.raises: ...} pragmas belonging to
  ## the declaration starting at startIdx.  The LAST one wins (rule 3).
  ## We stop at: a new top-level declaration, a line starting with '=',
  ## or a blank line (if no pragma found yet).
  var found = false
  var i = startIdx
  while i < lines.len:
    let line = lines[i].strip()
    # Blank line ends the header region
    if line.len == 0:
      if found:
        break
      else:
        inc i
        continue
    # New top-level declaration ends this declaration's header
    let (isNewDecl, _) = isTopLevelDecl(line)
    if isNewDecl and i > startIdx:
      break
    # '=' at start of line marks body start — stop scanning
    if line.startsWith("="):
      break
    # Check for raises pragma (handles combined pragmas like {.importc, raises: [].})
    if hasRaisesPragma(line):
      found = true
    inc i
  return found

# ── File scanning ──────────────────────────────────────────────────────────

proc scanFile(content: string, filePath: string): seq[Declaration] =
  ## Scan a single file for proc/func declarations and their compliance.
  let lines = content.splitLines()
  var raisesPushDepth = 0
  # Track template/macro/iterator/converter body indentation.
  # Any proc/func at a greater indentation level is inside the body
  # and is macro-generated (excluded from the subject universe).
  var macroBodyIndent: int = -1  # -1 means not inside a macro body
  var i = 0

  while i < lines.len:
    let line = lines[i]
    let trimmed = line.strip()
    let indent = leadingIndent(line)

    # Track push/pop raises scope (rule 2)
    if isPushRaises(line):
      inc raisesPushDepth
    if isPopRaises(line) and raisesPushDepth > 0:
      dec raisesPushDepth
    if isPopDot(line) and raisesPushDepth > 0:
      dec raisesPushDepth

    # Track macro/template/iterator/converter bodies by indentation.
    # When we enter a macro body, record its indent level.
    # Any proc/func at a greater indent is inside the body.
    # When we see a declaration at the same or lesser indent, exit the body.
    let (isTopDecl, declKind) = isTopLevelDecl(trimmed)
    if isTopDecl and declKind in ["template", "macro", "iterator", "converter"]:
      macroBodyIndent = indent
    elif macroBodyIndent >= 0 and indent <= macroBodyIndent and isTopDecl:
      # We've exited the macro body (new top-level decl at same or lesser indent)
      macroBodyIndent = -1

    # Only process proc/func declarations outside macro bodies
    let (isProcFunc, kind) = isProcOrFunc(trimmed)
    if isProcFunc and macroBodyIndent < 0:
      let symbol = extractSymbol(trimmed, kind)

      # Check compliance: inline raises pragma (rule 1) OR push scope (rule 2)
      let hasInline = findInlineRaises(lines, i)
      let compliant = raisesPushDepth > 0 or hasInline

      result.add(Declaration(
        path: filePath,
        symbol: symbol,
        kind: kind,
        line: i + 1,
        compliant: compliant
      ))

    inc i

# ── Include file handling ─────────────────────────────────────────────────

proc resolveIncludeTarget(includePath: string, includingFile: string,
                          projectRoot: string): string =
  ## Resolve an include target path relative to the including file's directory,
  ## then relative to the project root.
  let incDir = parentDir(includingFile)
  # Try relative to including file's directory
  let relPath = incDir / includePath
  if fileExists(relPath):
    return relPath
  # Try relative to project root
  let rootPath = projectRoot / includePath
  if fileExists(rootPath):
    return rootPath
  return ""

proc scanIncludes(content: string, filePath: string,
                   projectRoot: string): seq[Declaration] =
  ## Scan include'd files and attribute their declarations to the including file.
  let lines = content.splitLines()
  for i, line in lines:
    let trimmed = line.strip()
    if not trimmed.startsWith("include "):
      continue
    # Parse include target — handles both `include foo.nim` and `include "foo.nim"`
    var target = trimmed["include ".len .. ^1].strip()
    # Remove quotes if present
    if target.len >= 2 and target[0] == '"' and target[^1] == '"':
      target = target[1 .. ^2]
    if target.len == 0:
      continue
    let resolved = resolveIncludeTarget(target, filePath, projectRoot)
    if resolved.len == 0:
      continue
    let incContent = readFile(resolved)
    let incDecls = scanFile(incContent, filePath)  # attribute to INCLUDING file
    result.add(incDecls)

# ── Project scanning ──────────────────────────────────────────────────────

proc walkNimFiles(rootDir: string): seq[string] =
  ## Recursively collect .nim files under rootDir.
  if not dirExists(rootDir):
    return @[]
  for entry in walkDirRec(rootDir, relative = true, checkDir = true):
    if entry.endsWith(".nim"):
      result.add(rootDir / entry)

proc projectDeclarations*(projectRoot: string): seq[Declaration] =
  ## Scan all src/core/**/*.nim files and return declarations with compliance.
  let coreDir = projectRoot / "src" / "core"
  let nimFiles = walkNimFiles(coreDir)
  for filePath in nimFiles:
    let content = readFile(filePath)
    let decls = scanFile(content, filePath)
    let incDecls = scanIncludes(content, filePath, projectRoot)
    result.add(decls)
    result.add(incDecls)

# ── Output helpers ────────────────────────────────────────────────────────

proc toOutputJson*(decls: seq[Declaration]): JsonNode =
  ## Produce a deterministic JSON object with fixed key order.
  let totalDecls = decls.len
  let violations = decls.filterIt(not it.compliant)
  let violationCount = violations.len

  # Build eligible list (all declaration names, sorted)
  var eligible: seq[string] = @[]
  for d in decls:
    eligible.add(d.symbol)
  eligible.sort()

  # Build violations list sorted by (path, symbol, kind)
  var violList: seq[JsonNode] = @[]
  for v in violations:
    let entry = %* {
      "path": v.path,
      "symbol": v.symbol,
      "kind": v.kind
    }
    violList.add(entry)
  violList.sort(proc(a, b: JsonNode): int =
    let aPath = a["path"].getStr()
    let bPath = b["path"].getStr()
    if aPath != bPath:
      return cmp(aPath, bPath)
    let aSym = a["symbol"].getStr()
    let bSym = b["symbol"].getStr()
    if aSym != bSym:
      return cmp(aSym, bSym)
    let aKind = a["kind"].getStr()
    let bKind = b["kind"].getStr()
    cmp(aKind, bKind)
  )

  result = %* {
    "declarations": totalDecls,
    "violations": violationCount,
    "eligible": eligible,
    "violations_list": violList
  }

# ── CLI surface (debt_engine evalEffectViolations subprocess contract) ────
# Deterministic JSON to stdout, exit 0. debt_engine reads only the "violations"
# integer; the remaining fields are for human diagnosis. Subject universe is
# <cwd>/src/core — the evaluator runs at the repo/snapshot root.
when isMainModule:
  stdout.write(toOutputJson(projectDeclarations(getCurrentDir())).pretty())
  stdout.write("\n")
