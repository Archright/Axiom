import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/interfaces/git_operations
import ./types
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas
import core/types/results
import core/interfaces/logging_hub
import std/[os, osproc, times, algorithm, sequtils, strutils, tables]
proc sha256hex(content: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  hash_kernel.sha256Hex(content)
func pairwiseHash(a, b: string): string {.raises: [].} =
  sha256hex("\x01" & a & b)
func pairwiseReduce(layer: seq[string]): seq[string] {.raises: [].} =
  result = @[]
  var i = 0
  while i < layer.len:
    if i + 1 < layer.len:
      result.add(pairwiseHash(layer[i], layer[i + 1]))
    else:
      result.add(layer[i])  # Odd element carries forward
    i += 2
type
  ScanError* = object
    path*: string
    msg*: string

  ScanResult* = object
    hashes*: seq[string]
    errors*: seq[ScanError]
    excludedCount*: int

func isIgnored*(path: string; patterns: openArray[string]): bool =
  for pat in patterns:
    if pat.len == 0: continue
    if pat.startsWith("*."):
      let suffix = pat[1 ..< pat.len]
      if path.len >= suffix.len and path[path.len - suffix.len ..< path.len] == suffix:
        return true
    elif pat.endsWith("/*") or pat.endsWith("/"):
      let prefix = if pat.endsWith("/*"): pat[0 ..< pat.len - 2] else: pat
      if path.startsWith(prefix):
        return true
    elif pat.startsWith("*"):
      let suffix = pat[1 ..< pat.len]
      if path.endsWith(suffix):
        return true
    else:
      if pat in path:
        return true
  result = false

proc scanDirectory*(dirPath: string; ignorePatterns: openArray[string] = @[]): ScanResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ScanResult(hashes: @[], errors: @[], excludedCount: 0)
  if not dirExists(dirPath):
    return

  try:
    for entry in walkDirRec(dirPath):
      if entry.endsWith(".nim") and not isIgnored(entry, ignorePatterns):
        try:
          let content = readFile(entry)
          let hash = sha256hex("\x00" & content)
          result.hashes.add(hash)
        except CatchableError as e:
          result.errors.add(ScanError(path: entry, msg: e.msg))
          result.excludedCount.inc()
  except CatchableError as e:
    # axiom:theater-fix(DEBT#378) — collect walk failure, preserve partial hashes
    result.errors.add(ScanError(path: dirPath, msg: "Directory walk failed: " & e.msg))
  except Defect:
    raise # axiom:theater-fix(DEBT#379) — Defect propagates as panic

func computeMerkleRoot(hashes: seq[string]; errors: seq[ScanError]): Result[string, string] {.raises: [].} =
  ## Compute Merkle root from sorted content hashes.
  ## Returns error if any scan errors were collected.
  if errors.len > 0:
    return err("Scan errors: " & $errors.len & " file(s) had errors")
  if hashes.len == 0: return ok("")
  if hashes.len == 1: return ok(hashes[0])
  var layer = hashes
  while layer.len > 1:
    layer = pairwiseReduce(layer)
  ok(layer[0])
proc getStagedFiles(repoRoot: string): seq[string] {.raises: [], tags: [AxiomIOEffect, IOEffect, RootEffect], axiomEffect: IOEffect.} =
  ## Get git staged file list. Empty if not a git repo.
  try:
    let gitExe = git_operations.findRealGit()
    let (output, exitCode) = git_operations.runGitEx(gitExe, "-C " & quoteShell(repoRoot) &
                                       " diff --cached --name-only 2>/dev/null")
    if exitCode == 0 and output.len > 0:
      result = output.splitLines().filterIt(it.len > 0)
    else:
      result = @[]
  except CatchableError:
    result = @[]
proc scanProject*(repoRoot: string;
 stagedFiles: seq[string] = @[];
                  scanDirs: seq[string] = @["src"]): ProjectMap {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
 =
  ## Single-pass project scanner.
  ## Walks scanDirs ONCE, reads + hashes every .nim file.
  ## Returns fully populated ProjectMap with Merkle root.
  ##
  ## scanDirs defaults to @["src"] — the Nim source directory.
  ## stagedFiles: if empty, auto-detected via git.

  let startTime = epochTime()
  result = projectMap(repoRoot)
  result.stagedFiles = if stagedFiles.len > 0: stagedFiles
                       else: getStagedFiles(repoRoot)

  # Collect all .nim files in a single walk
  var allPaths: seq[string] = @[]
  var errors: seq[ScanError] = @[]
  for dir in scanDirs:
    let absDir = repoRoot / dir
    if not dirExists(absDir): continue
    try:
      for entry in walkDirRec(absDir):
        if entry.endsWith(".nim"):
          allPaths.add(entry)
    except CatchableError as e:
      # axiom:theater-fix(DEBT#378) — collect walk failure, preserve partial results
      errors.add(ScanError(path: absDir, msg: "Directory walk failed: " & e.msg))
      try: stderr.writeLine("[scanner] WARN: directory walk failed for " & absDir & " — scan may be incomplete")
      except CatchableError: discard # axiom:theater-fix(DEBT#379) — stderr write failure is low-risk

  # Sort deterministically for Merkle root stability
  allPaths.sort()

  # Read + hash in a single pass, collecting per-file errors
  var hashes: seq[string] = @[]
  var excludedCount = 0
  for absPath in allPaths:
    try:
      let relPath = relativePath(absPath, repoRoot)
      let content = readFile(absPath)
      let hash = sha256hex("\x00" & content)
      let mtime: int64 = getLastModificationTime(absPath).toUnix()
      let size: int64 = getFileSize(absPath).int64
      result.files[relPath] = FileEntry(
        path: absPath,
        relativePath: relPath,
        content: content,
        contentHash: hash,
        mtime: mtime,
        size: size
      )
      hashes.add(hash)
    except CatchableError as e:
      errors.add(ScanError(path: absPath, msg: e.msg))
      try: stderr.writeLine("[scanner] WARN: skipping unreadable file: " & absPath & " (" & e.msg & ")")
      except CatchableError: discard # axiom:theater-fix(DEBT#379) — stderr write failure is low-risk
      logError("[scanner] WARN: skipping unreadable file: " & absPath)
      excludedCount.inc()

  result.fileCount = result.files.len
  result.excludedCount = excludedCount
  if excludedCount > 0:
    try: stderr.writeLine("[scanner] WARN: " & $excludedCount & " file(s) excluded from scan — integrity scan incomplete")
    except CatchableError: discard # axiom:theater-fix(DEBT#379) — stderr write failure is low-risk
    logError("[scanner] WARN: " & $excludedCount & " file(s) excluded from scan (integrity scan incomplete)")
  result.sortedPaths = toSeq(result.files.keys)
  result.sortedPaths.sort()

  # Compute Merkle root from sorted content hashes with error checking
  let merkleResult = computeMerkleRoot(hashes, errors)
  result.sourceHash = if merkleResult.isOk: merkleResult.get() else: ""

  result.scanDurationMs = (epochTime() - startTime) * 1000.0

{.pop.}
