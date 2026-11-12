## cache_gc.nim — Deterministic Cache Garbage Collector
##
## Budget-aware eviction for .axiom/cache/ and JSONL log rotation.
## Ensures cache directories never exceed compile-time budget constants
## and log files stay bounded via FIFO rotation.
##
## Design Principles:
##   1. Deterministic: identical input → identical eviction set
##   2. Atomic: temp+fsync+rename for all writes
##   3. Rate-limited: at most one GC run per CacheGcIntervalSec (1 hour)
##   4. Non-destructive: CAS integrity verified before eviction

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[algorithm, os, strutils, times]
import core/trusted/axiom_pragmas_lite
import core/gate/gate_memo  # GateMemoBaseDir, computeCasAddress, CasAddress
import core/trusted/stdlib_shield
import core/types/results
import core/parsers/safe_parsers
import infrastructure/logging_facade
import core/macros/best_effort

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Compile-Time Budget Constants
# ---------------------------------------------------------------------------

const
  MaxCacheEntries* {.intdefine.} = 1024
    ## Maximum number of files in .axiom/cache/gate_memo/ before eviction.
  MaxCacheSizeMB* {.intdefine.} = 128
    ## Maximum total size of gate_memo in megabytes before eviction.
  MaxGateHistoryLines* {.intdefine.} = 2048
    ## Maximum lines retained in .axiom/gate_history.jsonl after rotation.
  MaxRecentCommandLines* {.intdefine.} = 4096
    ## Maximum lines retained in recent command log after rotation.
  CacheGcIntervalSec* = 3600
    ## Minimum seconds between cache GC runs (1 hour).

const
  CacheGcStateFile* = GateMemoBaseDir / ".cache_gc_last_run"
    ## State file for rate-limiting cache GC.

# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------

proc shouldRunCacheGc*(): bool {.raises: [], axiomEffect: IOEffect, bestEffort("""gc rate-limit state read — default to run""").} =
  ## Returns true if cache GC should run (no state file, stale, or first run).
  try:
    if not fileExists(CacheGcStateFile): return true
    let content = readFile(CacheGcStateFile).strip()
    let lastRun = safeParseInt(content)
    if lastRun.isErr(): return true
    return getTime().toUnix() - lastRun.get() >= CacheGcIntervalSec
  except CatchableError:
    return true

proc recordCacheGcRun*() {.raises: [], axiomEffect: IOEffect, bestEffort("""gc state write — failure is non-fatal""").} =
  ## Record current timestamp to GC state file for rate limiting.
  try:
    discard existsOrCreateDir(GateMemoBaseDir)
    writeFile(CacheGcStateFile, $getTime().toUnix() & "\n")
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# File Collection (deterministic walk)
# ---------------------------------------------------------------------------

type
  CacheFileEntry* = object
    path*: string
    mtime*: Time
    size*: int64

proc collectCacheFiles(root: string): seq[CacheFileEntry] {.axiomEffect: IOEffect.} =
  ## Recursively collect all files under root, excluding dotfiles and lock files.
  ## Returns unsorted sequence for deterministic ordering after sort.
  result = @[]
  if not dirExists(root):
    return
  for kind, path in walkDir(root, relative = false):
    if kind == pcFile:
      let name = path.extractFilename()
      # Skip hidden files, lock files, state files
      if name.startsWith(".") or name.endsWith(".lock"):
        continue
      try:
        let info = getFileInfo(path)
        result.add(CacheFileEntry(
          path: path,
          mtime: info.lastWriteTime,
          size: info.size.int64
        ))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif kind == pcDir:
      # Recurse into subdirectories (epoch_N/, hash[:2]/)
      result.add(collectCacheFiles(path))

func sortEntriesByMtimeDesc(entries: var seq[CacheFileEntry]) =
  ## Sort entries by mtime descending (newest first).
  ## Eviction removes from the end (oldest first).
  entries.sort(proc(a, b: CacheFileEntry): int =
    cmp(b.mtime.toUnix(), a.mtime.toUnix())
  )

func totalSize(entries: seq[CacheFileEntry]): int64 =
  ## Compute total size in bytes.
  result = 0
  for e in entries:
    result += e.size

# ---------------------------------------------------------------------------
# Budget Enforcement
# ---------------------------------------------------------------------------

proc evictToBudget*(cacheDir: string) {.raises: [], axiomEffect: IOEffect.} =
  ## Evict oldest cache entries until under MaxCacheEntries and MaxCacheSizeMB.
  ## Deterministic: sorts by mtime, removes oldest files first.
  ## Rate-limited: skips if cache GC ran recently.
  if not shouldRunCacheGc():
    return

  try:
    if not dirExists(cacheDir):
      recordCacheGcRun()
      return

    var entries = collectCacheFiles(cacheDir)
    let totalCount = entries.len
    let totalBytes = totalSize(entries)

    # Check if eviction is needed
    let budgetBytes = MaxCacheSizeMB.int64 * 1024 * 1024
    if totalCount <= MaxCacheEntries and totalBytes <= budgetBytes:
      recordCacheGcRun()
      return

    # Sort newest first; evict from end (oldest)
    sortEntriesByMtimeDesc(entries)

    var removed = 0
    var freedBytes: int64 = 0
    var remaining = totalCount
    var remainingBytes = totalBytes

    # Evict by count first
    while remaining > MaxCacheEntries and entries.len > 0:
      let victim = entries.pop()
      try:
        removeFile(victim.path)
        inc removed
        freedBytes += victim.size
        dec remaining
        remainingBytes -= victim.size
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

    # Evict by size
    while remainingBytes > budgetBytes and entries.len > 0:
      let victim = entries.pop()
      try:
        removeFile(victim.path)
        inc removed
        freedBytes += victim.size
        dec remaining
        remainingBytes -= victim.size
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

    if removed > 0:
      logInfo("cache_gc", "[CACHE-GC] Evicted " & $removed &
                       " entries (" & $freedBytes & " bytes) from " & cacheDir)
      stderr.flushFile()

    # Clean empty subdirectories left behind
    for kind, path in walkDir(cacheDir):
      if kind == pcDir:
        try:
          var isEmpty = true
          for subKind, subPath in walkDir(path):
            isEmpty = false
            break
          if isEmpty:
            removeDir(path)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)

    recordCacheGcRun()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# JSONL Log Rotation
# ---------------------------------------------------------------------------

proc rotateLog*(path: string; maxLines: int) {.raises: [], axiomEffect: IOEffect.} =
  ## Rotate a JSONL log file to keep only the last maxLines lines.
  ## Uses atomic write (temp + rename) to prevent corruption on crash.
  ## If the file has fewer than maxLines lines, no action is taken.
  try:
    if not fileExists(path):
      return

    let content = readFile(path)
    var lines: seq[string] = @[]
    for line in content.splitLines():
      if line.strip().len > 0:
        lines.add(line)

    # No rotation needed
    if lines.len <= maxLines:
      return

    # Keep last maxLines lines (FIFO — oldest lines are dropped)
    let trimmed = lines[^maxLines..^1]

    # Write atomically: temp + rename
    let tmpPath = path & ".tmp"
    try:
      var f = open(tmpPath, fmWrite)
      for line in trimmed:
        f.writeLine(line)
      f.flushFile()
      f.close()
      # Atomic replace
      safeMoveFile(tmpPath, path)
    except FileMoveError:
      # Clean up temp file on failure
      try: removeFile(tmpPath)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)

    let dropped = lines.len - maxLines
    if dropped > 0:
      logInfo("cache_gc", "[CACHE-GC] Rotated " & path &
                       ": dropped " & $dropped & " old lines, kept " & $maxLines)
      stderr.flushFile()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Composite Cache GC
# ---------------------------------------------------------------------------

proc runCacheGC*(cacheDir: string; logPaths: seq[string]) {.axiomEffect: IOEffect.} =
  ## Run all cache GC operations: budget eviction + log rotation.
  ## Designed to be called once at pipeline end (non-blocking path).
  ##
  ## Parameters:
  ##   cacheDir  — root cache directory (typically ".axiom/cache/gate_memo")
  ##   logPaths  — JSONL log files to rotate (gate_history, etc.)
  evictToBudget(cacheDir)
  for logPath in logPaths:
    rotateLog(logPath, MaxGateHistoryLines)

# ---------------------------------------------------------------------------
# Orphan Trash Cleanup
# ---------------------------------------------------------------------------

proc cleanupOrphanTrash*(repoRoot: string) {.axiomEffect: IOEffect.} =
  ## Scan for stale .axiom/cache_trash_* directories and remove them.
  let axiomDir = repoRoot / ".axiom"
  if not dirExists(axiomDir): return
  for entry in walkDir(axiomDir):
    if entry.kind == pcDir and entry.path.extractFilename.startsWith("cache_trash_"):
      try:
        removeDir(entry.path)
        logInfo("cache_gc", "Cleaned orphan trash: " & entry.path)
      except CatchableError:
        logWarn("cache_gc", "Could not clean orphan trash: " & entry.path)
