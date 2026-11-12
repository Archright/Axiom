import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## axiom_codemod.nim
##
## Hybrid AST-aware / text-surgical codemod engine for Axiom.
## Phase 2 entry point: pragma rewriter.
##
## Design:
## - Use Nim compiler/parser ONLY to locate violation positions (line/col).
## - Perform actual edits on the original source text so comments, blank lines,
##   and indentation are preserved.
## - Verify mutated files in a single batch via bin/nim_check_gate and roll back
##   only the files that fail verification.

import std/os
import std/osproc
import std/strutils
import std/tables
import std/tempfiles
import core/crypto/hash_kernel
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

const
  CacheDir = "build/nimcache/axiom_codemod"
  MaxCheckJobs = 4

type
  FileResult = enum
    frUnchanged
    frModified
    frParseFailed

func contentHashHex*(content: string): string {.raises: [].} =
  sha256Hex(content)

proc ensureCacheDir() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not dirExists(CacheDir):
    createDir(CacheDir)

proc cachedHash(path: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cacheFile = CacheDir / path.replace("/", "_") & ".sha256"
  if fileExists(cacheFile):
    readFile(cacheFile).strip()
  else:
    ""

proc writeCacheHash(path, hash: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cacheFile = CacheDir / path.replace("/", "_") & ".sha256"
  writeFile(cacheFile, hash)

proc collectSourceFiles(): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect ALL .nim files under src/ recursively.
  ## walkFiles("src/**/*.nim") only matches one directory level deep;
  ## walkDirRec is the correct recursive traversal.
  for path in walkDirRec("src"):
    if path.endsWith(".nim"):
      result.add(path)

# ---------------------------------------------------------------------------
# Pragma rewriter (line-based surgical edition)
# ---------------------------------------------------------------------------

proc isPragmaLine(line, keyword: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Loose line-based detection of `{.push ...` / `{.pop...` pragmas.
  ## Intentionally simple: false positives inside strings/comments are rare
  ## for these keywords and are caught by the post-edit batch verification.
  let trimmed = line.strip()
  if not trimmed.startsWith("{."): return false
  let rest = trimmed[2 .. ^1].strip()
  if not rest.startsWith(keyword): return false
  let after = rest[keyword.len .. ^1]
  result = after.len == 0 or after[0] in {' ', '\t', '.', ':', ']'}

proc firstRealLine(source: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for line in source.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    return stripped
  ""

proc rewritePragmas(source: string): tuple[changed: bool; output: string;
                                            globalPushOnly: bool] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var pushCount = 0
  var popCount = 0
  for line in source.splitLines():
    if isPragmaLine(line, "push"):
      inc pushCount
    elif isPragmaLine(line, "pop"):
      inc popCount

  if pushCount <= popCount:
    return (false, source, false)

  # Heuristic: a single top-level {.push ...} at the start of the file with no
  # matching {.pop.} is usually an intentional file-wide pragma. Adding a pop
  # at EOF would silently change the effect contract of the whole module.
  # Skip these files and let the architect decide via policy overrides.
  let first = firstRealLine(source)
  let isGlobalPushOnly = first.startsWith("{.") and "{.push" in first and popCount == 0
  if isGlobalPushOnly:
    return (false, source, true)

  let missing = pushCount - popCount
  var output = source
  if not output.endsWith("\n"):
    output.add("\n")
  for i in 1 .. missing:
    output.add("{.pop.}\n")
  (true, output, false)

proc processFile(path: string; originals: var Table[string, string]): FileResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path):
    return frParseFailed
  let original = readFile(path)
  let currentHash = contentHashHex(original)
  ensureCacheDir()
  if cachedHash(path) == currentHash:
    return frUnchanged

  let (changed, rewritten, globalPushOnly) = rewritePragmas(original)
  if not changed:
    if globalPushOnly:
      logInfo("axiom_codemod", "[axiom_codemod] skipping global push file: " & $(path))
    writeCacheHash(path, currentHash)
    return frUnchanged

  originals[path] = original
  writeFile(path, rewritten)
  frModified

proc writeResponseFile(paths: seq[string]): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = genTempPath(prefix = "axiom_codemod_", suffix = ".txt", dir = CacheDir)
  var content = ""
  for p in paths:
    content.add(p & "\n")
  writeFile(path, content)
  path

proc parseGateSummary(output: string): tuple[ok: bool; failingFiles: seq[string]] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var lines = output.splitLines()
  # Search from the bottom for [GATE_SUMMARY]
  var summaryIdx = -1
  for i in countdown(lines.len - 1, 0):
    if lines[i].strip().startsWith("[GATE_SUMMARY]"):
      summaryIdx = i
      break
  if summaryIdx < 0:
    return (false, @[])
  let summaryLine = lines[summaryIdx].strip()
  if summaryLine == "[GATE_SUMMARY] OK":
    return (true, @[])
  if summaryLine != "[GATE_SUMMARY] FAILURE":
    return (false, @[])
  var failingFiles: seq[string] = @[]
  var inFailedFiles = false
  for i in (summaryIdx + 1) ..< lines.len:
    let line = lines[i].strip()
    if line.len == 0:
      continue
    if line == "FAILED_FILES:":
      inFailedFiles = true
      continue
    if inFailedFiles:
      failingFiles.add(line)
  (failingFiles.len == 0, failingFiles)

proc runBatchVerification(modified: seq[string]): tuple[ok: bool; failingFiles: seq[string]] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let responseFile = writeResponseFile(modified)
  defer: discard tryRemoveFile(responseFile)
  let cmd = "bin/nim_check_gate . incremental " & $MaxCheckJobs & " @" & quoteShell(responseFile)
  let (output, exitCode) = execCmdEx(cmd)
  let summary = parseGateSummary(output)
  if exitCode == 0 and summary.ok:
    return (true, @[])
  # If summary parsing failed but exit code is non-zero, treat all modified files as failing
  if summary.failingFiles.len == 0:
    return (false, modified)
  summary

proc runPragmaRewrite() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let files = collectSourceFiles()
  var originals = initTable[string, string]()
  var modified: seq[string] = @[]
  var failed = 0
  for path in files:
    case processFile(path, originals)
    of frModified: modified.add(path)
    of frUnchanged: discard
    of frParseFailed: inc failed

  if modified.len == 0:
    logger.info("[axiom_codemod] pragma rewrite complete: 0 modified, " & $failed & " failed")
    if failed > 0:
      quit(1)
    return

  logger.info("[axiom_codemod] rewrote " & $modified.len & " file(s); running batch verification...")
  let (ok, failingFiles) = runBatchVerification(modified)

  var rolledBack = 0
  for f in failingFiles:
    if originals.hasKey(f):
      logInfo("axiom_codemod", "[axiom_codemod] rolling back: " & $(f))
      writeFile(f, originals[f])
      inc rolledBack

  for path in modified:
    if path notin failingFiles:
      let content = readFile(path)
      writeCacheHash(path, contentHashHex(content))

  logger.info("[axiom_codemod] pragma rewrite complete: " & $modified.len & " modified, " & $rolledBack & " rolled back, " & $failed & " parse failed")
  if not ok or failed > 0:
    quit(1)

proc printUsage() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  logger.info("Usage: axiom_codemod <command> [--dry-run]")
  logger.info("Commands: pragma")

proc main() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let args = commandLineParams()
  if args.len == 0:
    printUsage()
    quit(1)
  let cmd = args[0]
  if cmd == "pragma":
    runPragmaRewrite()
  else:
    logInfo("axiom_codemod", "[axiom_codemod] unknown command: " & $(cmd))
    printUsage()
    quit(1)

{.pop.}

when isMainModule:
  main()
