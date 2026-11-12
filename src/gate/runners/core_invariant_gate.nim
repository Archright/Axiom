import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## Core Invariant Gate
##
## Lightweight textual scan that mirrors Bash phase 8 of .githooks/pre-commit.
## Scans direct children of src/core/ for forbidden I/O primitives and
## `when isMainModule` — enforcing the effect-free core contract (AGENTS.md §0.6).
##
## Forbidden patterns:
##   - `readFile(`   → move to verification/ or use isolation wrapper
##   - `writeFile(`  → move to verification/ or use isolation wrapper
##   - `execProcess(` → move to verification/ or use isolation wrapper
##   - `startProcess(` → move to verification/ or use isolation wrapper
##   - `when isMainModule` → use test files or I/O boundary modules
##
## Scope: direct children of src/core/ only (not recursive subdirectories).
## Subdomain modules (e.g. src/core/topology/) are validated by nimtry
## and architecture_policy.lock, not this pre-commit literal scan.
##
## Exit 0 if clean; exit 1 listing violations.

import std/os
import std/strutils
import std/options
import std/strformat
import core/axiom_pragmas
import gate/git
import core/gate/gate_vfs
import infrastructure/logging_facade


# axiomIoBoundary

const
  CoreDir = "src/core/"
  CorePattern = CoreDir & "*.nim"   ## direct children only

  ForbiddenPatterns = [
    "readFile(",
    "writeFile(",
    "execProcess(",
    "startProcess(",
  ]

  WhenMainModule = "when isMainModule"

type
  Violation = object
    path: string
    lineNo: int
    kind: string    ## "io_primitive" or "isMainModule"
    detail: string  ## the matched pattern or text

func isCoreDirectChild*(path: string): bool =
  ## Returns true if path is a direct child of src/core/ (not in subdirectories).
  ## Accepts both relative and absolute paths; matches the Bash regex:
  ##   ^src/core/[^/]+\.nim$
  if not path.endsWith(".nim"):
    return false
  ## Strip any leading path components to get the relative form
  var relPath = path
  ## Handle absolute paths by finding the src/core/ segment
  let coreIdx = relPath.find(CoreDir)
  if coreIdx < 0:
    return false
  relPath = relPath[coreIdx .. ^1]
  ## Must start with src/core/
  if relPath != CoreDir and not relPath.startsWith(CoreDir):
    return false
  ## After removing src/core/, there must be no remaining '/' before the filename
  let afterCore = relPath[CoreDir.len .. ^1]
  result = '/' notin afterCore

proc checkFile*(filepath: string): seq[Violation] {.raises: [].} =
  ## Scan a single file for forbidden I/O primitives and `when isMainModule`.
  ## Lightweight textual scan — not a full AST analysis.
  result = @[]
  try:
    let content = readFile(filepath)
    var lineNo = 0
    for line in content.splitLines():
      lineNo += 1
      let stripped = line.strip()

      ## Skip comment-only lines (single-line comments)
      if stripped.startsWith("#"):
        continue

      ## Check for forbidden I/O primitives
      for pattern in ForbiddenPatterns:
        if pattern in stripped:
          result.add(Violation(
            path: filepath,
            lineNo: lineNo,
            kind: "io_primitive",
            detail: pattern
          ))

      ## Check for `when isMainModule`
      if WhenMainModule in stripped:
        result.add(Violation(
          path: filepath,
          lineNo: lineNo,
          kind: "isMainModule",
          detail: WhenMainModule
        ))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc fetchGitDiffCachedNames*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fallback: read staged file names via core/gate/git and filter to src/core/.
  result = @[]
  let allChanged = gitDiffCachedNames()
  for f in allChanged:
    if f.startsWith(CoreDir):
      result.add(f)

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Entry point. Reads file paths from args or falls back to git diff.
  var targetFiles: seq[string] = @[]

  ## Collect files from command-line args
  for i in 1 .. paramCount():
    let f = paramStr(i)
    if isCoreDirectChild(f):
      targetFiles.add(f)

  ## Fallback to git diff if no valid core files passed
  if targetFiles.len == 0:
    targetFiles = fetchGitDiffCachedNames()

  ## Filter again in fallback path to ensure only direct children
  var filteredFiles: seq[string] = @[]
  for f in targetFiles:
    if isCoreDirectChild(f):
      filteredFiles.add(f)

  ## Scan each file
  var allViolations: seq[Violation] = @[]
  for filepath in filteredFiles:
    let violations = checkFile(filepath)
    for v in violations:
      allViolations.add(v)

  ## Report results
  if allViolations.len == 0:
    logger.info("[core-invariant-gate] PASS — no I/O primitives or isMainModule in " & $filteredFiles.len & " core module(s)")
    quit(0)
  else:
    logError("core_invariant_gate", "[core-invariant-gate] BLOCKED — " & $(allViolations.len) & " violation(s) found:")
    for v in allViolations:
      case v.kind
      of "io_primitive":
        logInfo("core_invariant_gate", fmt"  ❌ I/O primitive '{v.detail}' in {v.path}:{v.lineNo}")
        logInfo("core_invariant_gate", "     Move to verification/ or use isolation wrapper.")
      of "isMainModule":
        logInfo("core_invariant_gate", fmt"  ❌ '{v.detail}' in {v.path}:{v.lineNo}")
        logInfo("core_invariant_gate", "     Use test files or I/O boundary modules instead.")
    logInfo("core_invariant_gate", "")
    logInfo("core_invariant_gate", "If this is intentional, use: AXIOM_EMERGENCY_NO_VERIFY=1 git commit")
    quit(1)

func checkFileVfs(ctx: GateContext; filepath: string): seq[Violation] =
  ## VFS-aware version of checkFile.
  result = @[]
  let contentOpt = vfsReadOpt(ctx, filepath)
  if contentOpt.isNone:
    return
  let content = contentOpt.get()
  var lineNo = 0
  for line in content.splitLines():
    lineNo += 1
    let stripped = line.strip()
    if stripped.startsWith("#"):
      continue
    for pattern in ForbiddenPatterns:
      if pattern in stripped:
        result.add(Violation(
          path: filepath,
          lineNo: lineNo,
          kind: "io_primitive",
          detail: pattern
        ))
    if WhenMainModule in stripped:
      result.add(Violation(
        path: filepath,
        lineNo: lineNo,
        kind: "isMainModule",
        detail: WhenMainModule
      ))

proc mainWithVfs*(ctx: GateContext) =
  ## VFS-aware entry point. Scans src/core/ for forbidden I/O primitives via VFS.
  var targetFiles: seq[string] = @[]
  # Collect .nim files from src/core/ via VFS directory listing
  let coreEntries = vfsListDir(ctx, "src/core")
  for path in coreEntries:
    if isCoreDirectChild(path):
      targetFiles.add(path)

  var filteredFiles: seq[string] = @[]
  for f in targetFiles:
    if isCoreDirectChild(f):
      filteredFiles.add(f)

  var allViolations: seq[Violation] = @[]
  for filepath in filteredFiles:
    let violations = checkFileVfs(ctx, filepath)
    for v in violations:
      allViolations.add(v)

  if allViolations.len == 0:
    logger.info("[core-invariant-gate] PASS — no I/O primitives or isMainModule in " & $filteredFiles.len & " core module(s)")
    quit(0)
  else:
    logError("core_invariant_gate", "[core-invariant-gate] BLOCKED — " & $(allViolations.len) & " violation(s) found:")
    for v in allViolations:
      case v.kind
      of "io_primitive":
        logInfo("core_invariant_gate", fmt"  ❌ I/O primitive '{v.detail}' in {v.path}:{v.lineNo}")
        logInfo("core_invariant_gate", "     Move to verification/ or use isolation wrapper.")
      of "isMainModule":
        logInfo("core_invariant_gate", fmt"  ❌ '{v.detail}' in {v.path}:{v.lineNo}")
        logInfo("core_invariant_gate", "     Use test files or I/O boundary modules instead.")
    logInfo("core_invariant_gate", "")
    logInfo("core_invariant_gate", "If this is intentional, use: AXIOM_EMERGENCY_NO_VERIFY=1 git commit")
    quit(1)

{.pop.}

when isMainModule:
  main()
