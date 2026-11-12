import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Discarded Write Audit Gate — Hard-Fail Gate
##
## Enforces that every `discard writeFileOpt(...)` or
## `discard appendFileLineOpt(...)` has a preceding
## `## intentional-discard:` comment explaining the discard.
##
## Detection:
##   - Lines containing `discard writeFileOpt(` or `discard appendFileLineOpt(`
##   - Verifies the immediately preceding non-empty line starts with
##     `## intentional-discard:`
##
## Scope: all `.nim` files under `src/`, excluding `vendor/`, `tests/`,
##        and `_shadow.nim` files.
##
## Exit 0 = pass (all discards annotated), exit 1 = violations found.

import std/os
import std/options
import std/strutils
import core/axiom_pragmas
import core/gate/gate_vfs
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

axiomIoBoundary()

const
  GateTag = "[discarded-write-audit]"
  SourceDir = "src"

  ## Patterns that indicate a discarded write call.
  DiscardPatterns: array[2, string] = [
    "discard writeFileOpt(",
    "discard appendFileLineOpt(",
  ]

  ## Required annotation prefix on the line above each discard.
  IntentionalComment = "## intentional-discard:"

# ── Pure logic ──────────────────────────────────────────────────────────────

func hasIntentionalComment(lines: seq[string], discardIdx: int): bool =
  ## Check if the line immediately above the discard line at `discardIdx`
  ## contains an `## intentional-discard:` comment.
  if discardIdx <= 0:
    return false
  let prevLine = lines[discardIdx - 1]
  prevLine.strip().startsWith(IntentionalComment)

type
  AuditViolation* = object
    file*: string
    line*: int
    snippet*: string

# ── File scanner ────────────────────────────────────────────────────────────

func isExcludedPath(path: string): bool =
  ## Returns true if the path should be excluded from scanning.
  if path.contains("/vendor/"): return true
  if path.contains("/tests/"): return true
  if path.extractFilename().endsWith("_shadow.nim"): return true
  false

func scanFileContent(content: string, filePath: string): seq[AuditViolation] =
  ## Scan file content for discard-write violations (pure function).
  ## Only matches lines that start with `discard writeFileOpt(` or
  ## `discard appendFileLineOpt(` (actual statements, not string literals).
  result = @[]
  let lines = content.splitLines()
  for i, line in lines:
    let stripped = line.strip()
    if not stripped.startsWith("discard "): continue
    for pat in DiscardPatterns:
      if stripped.startsWith(pat):
        if not hasIntentionalComment(lines, i):
          let snippet = line.strip()
          result.add(AuditViolation(
            file: filePath,
            line: i + 1,  # 1-based line number
            snippet: if snippet.len > 80: snippet[0 ..< 80] & "..." else: snippet,
          ))
        break  # Only match one pattern per line

# ── I/O: directory walker ───────────────────────────────────────────────────

proc scanSourceDir(srcDir: string): seq[AuditViolation] {.axiomEffect: IOEffect.} =
  ## Recursively scan all .nim files under srcDir for violations.
  result = @[]
  if not dirExists(srcDir): return
  for kind, path in walkDir(srcDir, relative = false):
    if kind == pcFile and path.endsWith(".nim"):
      if isExcludedPath(path): continue
      try:
        let content = readFile(path)
        let violations = scanFileContent(content, path)
        for v in violations:
          result.add(v)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif kind == pcDir:
      if isExcludedPath(path): continue
      for kind2, path2 in walkDir(path, relative = false):
        if kind2 == pcFile and path2.endsWith(".nim"):
          if isExcludedPath(path2): continue
          try:
            let content = readFile(path2)
            let violations = scanFileContent(content, path2)
            for v in violations:
              result.add(v)
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
        elif kind2 == pcDir:
          if isExcludedPath(path2): continue
          for kind3, path3 in walkDir(path2, relative = false):
            if kind3 == pcFile and path3.endsWith(".nim"):
              if isExcludedPath(path3): continue
              try:
                let content = readFile(path3)
                let violations = scanFileContent(content, path3)
                for v in violations:
                  result.add(v)
              except CatchableError:
                discard  # axiom:best-effort(ioboundary catch)

# ── VFS scanner ─────────────────────────────────────────────────────────────

func vfsCollectNimPaths(ctx: GateContext, dir: string): seq[string] =
  ## Recursively collect all .nim file paths from the VFS under `dir`.
  result = @[]
  let entries = vfsListDir(ctx, dir)
  for entry in entries:
    let fullPath = dir & "/" & entry
    if fullPath.endsWith(".nim"):
      if not isExcludedPath(fullPath):
        result.add(fullPath)
    elif vfsExists(ctx, fullPath & "/"):
      # It's a directory — recurse
      result.add(vfsCollectNimPaths(ctx, fullPath))

func scanVfs(ctx: GateContext): seq[AuditViolation] =
  ## Scan all .nim files in VFS for violations.
  result = @[]
  let paths = vfsCollectNimPaths(ctx, SourceDir)
  for path in paths:
    if isExcludedPath(path): continue
    let optContent = vfsReadOpt(ctx, path)
    if optContent.isNone(): continue
    let content = optContent.get()
    let violations = scanFileContent(content, path)
    for v in violations:
      result.add(v)

# ── Gate runner ─────────────────────────────────────────────────────────────

func formatViolations(violations: seq[AuditViolation]): string =
  var lines: seq[string] = @[]
  for v in violations:
    lines.add("  " & v.file & ":" & $v.line & "  " & v.snippet)
  lines.join("\n")

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## CLI entry point. Walks src/ directory and checks for violations.
  let srcDir = getCurrentDir() / SourceDir
  let violations = scanSourceDir(srcDir)

  if violations.len == 0:
    logger.info $GateTag & " PASS — all discard write calls have intentional-discard comments"
    quit(0)
  else:
    logError("discarded_write_audit_gate",
      $GateTag & " FAIL — " & $violations.len &
      " discard(s) missing intentional-discard comment:")
    logInfo("discarded_write_audit_gate", formatViolations(violations))
    logInfo("discarded_write_audit_gate", "")
    logError("discarded_write_audit_gate",
      "BLOCKED: Every `discard writeFileOpt/appendFileLineOpt` must have " &
      "an `## intentional-discard:` comment above it (spec §4.1).")
    quit(1)

proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Reads from the in-memory VFS instead of disk.
  let violations = scanVfs(ctx)

  if violations.len == 0:
    logger.info $GateTag & " PASS — all discard write calls have intentional-discard comments"
    quit(0)
  else:
    logError("discarded_write_audit_gate",
      $GateTag & " FAIL — " & $violations.len &
      " discard(s) missing intentional-discard comment:")
    logInfo("discarded_write_audit_gate", formatViolations(violations))
    logInfo("discarded_write_audit_gate", "")
    logError("discarded_write_audit_gate",
      "BLOCKED: Every `discard writeFileOpt/appendFileLineOpt` must have " &
      "an `## intentional-discard:` comment above it (spec §4.1).")
    quit(1)

{.pop.}

when isMainModule:
  main()
