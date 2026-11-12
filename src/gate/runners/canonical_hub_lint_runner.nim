import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Canonical Hub Lint Runner — Nim port of tools/canonical_hub_lint.py
##
## Enforces that forwarding stubs in src/core/ contain ONLY:
##   - Comment lines (#)
##   - Pragma directives ({.push ...}, {.pop.}, {.deprecated ...})
##   - Import statements
##   - Export statements
##
## Forbidden: func, proc, method, let, var, const, if, elif, else,
##   for, while, case, of, try, except, finally, block, template, macro, converter
##
## Pure lint logic is `func`. I/O (file reads) at the boundary only.

import std/[algorithm, os, options, strutils]
import core/axiom_pragmas
import core/gate/gate_vfs

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  Severity* = enum
    seError    ## Violation of stub purity rule
    seWarning  ## Unexpected content (not clearly forbidden)

  LintViolation* = object
    ## A single lint violation found in a forwarding stub.
    file*: string
    line*: int
    column*: int
    message*: string
    severity*: Severity

  LintResult* = object
    ## Aggregate result of a lint scan.
    filesScanned*: int
    stubsDetected*: int
    violations*: seq[LintViolation]

# ---------------------------------------------------------------------------
# Forbidden Keywords (deterministic, no regex dependency)
# ---------------------------------------------------------------------------

const
  ## Business-logic keywords that must never appear in forwarding stubs.
  ForbiddenKeywords: array[18, string] = [
    "func", "proc", "method",
    "let", "var", "const",
    "if", "elif", "else",
    "for", "while",
    "case", "of",
    "try", "except", "finally",
    "block", "template",
  ]

# ---------------------------------------------------------------------------
# Pure Logic (func)
# ---------------------------------------------------------------------------

func firstNonWhitespace*(line: string): int {.raises: [].} =
  ## Return index of first non-whitespace character, or -1 if blank.
  result = -1
  for i, ch in line:
    if ch notin {' ', '\t', '\r'}:
      return i

func isCommentLine*(line: string): bool {.raises: [].} =
  ## Check if line starts with a comment marker.
  let idx = line.firstNonWhitespace()
  if idx < 0:
    return false
  line[idx] == '#'

func isBlankLine*(line: string): bool {.raises: [].} =
  ## Check if line is empty or whitespace-only.
  line.firstNonWhitespace() < 0

func isPragmaPush*(line: string): bool {.raises: [].} =
  ## Check if line is a {.push ...} pragma.
  let stripped = line.strip()
  stripped.startsWith("{.") and "push" in stripped

func isPragmaPop*(line: string): bool {.raises: [].} =
  ## Check if line is a {.pop.} pragma.
  let stripped = line.strip()
  stripped.startsWith("{.") and "pop" in stripped

func isDeprecatedPragma*(line: string): bool {.raises: [].} =
  ## Check if line is a {.deprecated ...} pragma.
  let stripped = line.strip()
  stripped.startsWith("{.") and "deprecated" in stripped

func isImportLine*(line: string): bool {.raises: [].} =
  ## Check if line is an import statement.
  let stripped = line.strip()
  stripped.startsWith("import ") or stripped.startsWith("import\t")

func isExportLine*(line: string): bool {.raises: [].} =
  ## Check if line is an export statement.
  let stripped = line.strip()
  stripped.startsWith("export ") or stripped.startsWith("export\t")

func isFromImportLine*(line: string): bool {.raises: [].} =
  ## Check if line is a `from X import Y` statement.
  let stripped = line.strip()
  stripped.startsWith("from ") and " import " in stripped

func isAllowedLine*(line: string): bool {.raises: [].} =
  ## Check if a line is allowed in a forwarding stub.
  isBlankLine(line) or isCommentLine(line) or
  isPragmaPush(line) or isPragmaPop(line) or isDeprecatedPragma(line) or
  isImportLine(line) or isExportLine(line) or isFromImportLine(line)

func findForbiddenKeyword*(line: string): string {.raises: [].} =
  ## Return the first forbidden keyword found at line start, or "" if none.
  let stripped = line.strip()
  for kw in ForbiddenKeywords:
    # Check word-boundary match: keyword followed by space, tab, or end-of-string
    if stripped.startsWith(kw):
      let afterKw = stripped[kw.len .. ^1]
      if afterKw.len == 0 or afterKw[0] in {' ', '\t', '(', ':'}:
        return kw
  ""

func isStub*(content: string): bool {.raises: [].} =
  ## Determine if a file content looks like a forwarding stub.
  ## A stub has import+export and no func/proc definitions.
  var hasImport = false
  var hasExport = false
  var hasFuncOrProc = false

  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("import ") or stripped.startsWith("from ") and " import " in stripped:
      hasImport = true
    elif stripped.startsWith("export "):
      hasExport = true
    elif stripped.startsWith("func ") or stripped.startsWith("proc "):
      hasFuncOrProc = true

  hasImport and hasExport and not hasFuncOrProc

func checkStubContent*(filePath: string, content: string): seq[LintViolation] {.raises: [].} =
  ## Check a forwarding stub's content for violations. Returns list of violations.
  result = @[]
  let lines = content.splitLines()

  for i, line in lines:
    if line.isBlankLine():
      continue
    if line.isAllowedLine():
      continue

    # Check for specific forbidden keywords
    let keyword = line.findForbiddenKeyword()
    if keyword.len > 0:
      result.add LintViolation(
        file: filePath,
        line: i + 1,
        column: line.firstNonWhitespace() + 1,
        message: "stub contains '" & keyword & "' — forwarding stubs must only import/export",
        severity: seError
      )
    else:
      let stripped = line.strip()
      let preview = if stripped.len > 60: stripped[0 ..< 60] else: stripped
      result.add LintViolation(
        file: filePath,
        line: i + 1,
        column: line.firstNonWhitespace() + 1,
        message: "unexpected content in stub: " & preview,
        severity: seWarning
      )

func formatViolation*(v: LintViolation): string {.raises: [].} =
  ## Format a violation for display.
  v.file & ":" & $v.line & ": " & v.message

# ---------------------------------------------------------------------------
# I/O Boundary — File Discovery & Scanning
# ---------------------------------------------------------------------------

proc findNimFiles*(dir: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Find all top-level .nim files in a directory (not in subdirectories).
  result = @[]
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path)
  result.sort()

proc readFileContent*(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read file content, return empty string on error.
  try:
    readFile(path)
  except CatchableError:
    ""

proc runCanonicalHubLint*(paths: seq[string]): LintResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run the canonical hub lint check on the given paths.
  ## If paths is empty, scans src/core/ by default.
  var filesToCheck: seq[string]
  if paths.len == 0:
    # Determine project root and scan src/core/
    let projectRoot = getCurrentDir()
    let coreDir = projectRoot / "src" / "core"
    filesToCheck = findNimFiles(coreDir)
  else:
    for p in paths:
      let info = getFileInfo(p)
      if info.kind == pcDir:
        filesToCheck.add(findNimFiles(p))
      else:
        filesToCheck.add(p)

  result.filesScanned = filesToCheck.len
  result.stubsDetected = 0
  result.violations = @[]

  for filePath in filesToCheck:
    let content = readFileContent(filePath)
    if content.len == 0:
      continue
    if isStub(content):
      inc result.stubsDetected
      let violations = checkStubContent(filePath, content)
      result.violations.add(violations)

func hasViolations*(lr: LintResult): bool {.raises: [].} =
  ## Check if the lint result contains any errors (not warnings).
  for v in lr.violations:
    if v.severity == seError:
      return true
  false

func errorCount*(lr: LintResult): int {.raises: [].} =
  ## Count errors in the lint result.
  for v in lr.violations:
    if v.severity == seError:
      inc result

func warningCount*(lr: LintResult): int {.raises: [].} =
  ## Count warnings in the lint result.
  for v in lr.violations:
    if v.severity == seWarning:
      inc result

proc findNimFilesVfs*(ctx: GateContext; dir: string): seq[string]  =
  ## VFS-aware version of findNimFiles.
  result = @[]
  let entries = vfsListDir(ctx, dir)
  for path in entries:
    if path.endsWith(".nim"):
      result.add(path)
  result.sort()

proc readFileContentVfs*(ctx: GateContext; path: string): string =
  ## VFS-aware version of readFileContent.
  vfsReadOpt(ctx, path).get("")

proc runCanonicalHubLintVfs*(ctx: GateContext; paths: seq[string]): LintResult =
  ## VFS-aware version of runCanonicalHubLint.
  var filesToCheck: seq[string]
  if paths.len == 0:
    let coreDir = ctx.repoRoot / "src" / "core"
    filesToCheck = findNimFilesVfs(ctx, coreDir)
  else:
    for p in paths:
      # In VFS mode, check if p is a directory by listing its entries
      let entries = vfsListDir(ctx, p)
      if entries.len > 0:
        filesToCheck.add(findNimFilesVfs(ctx, p))
      else:
        filesToCheck.add(p)

  result.filesScanned = filesToCheck.len
  result.stubsDetected = 0
  result.violations = @[]

  for filePath in filesToCheck:
    let content = readFileContentVfs(ctx, filePath)
    if content.len == 0:
      continue
    if isStub(content):
      inc result.stubsDetected
      let violations = checkStubContent(filePath, content)
      result.violations.add(violations)

{.pop.}

