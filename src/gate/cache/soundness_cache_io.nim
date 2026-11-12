import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/[os, json, strutils, algorithm]
import checksums/sha2
import core/trusted/axiom_pragmas_lite
import core/trusted/stdlib_shield
import infrastructure/logging_facade
import gate/cache/soundness_cache_types

const
  SoundnessCacheSchemaVersion* = "1.0"

## ============================================================================
## Soundness Cache I/O
## ============================================================================
## Implements persistence operations for the Soundness Cache Engine.
##
## Key properties:
## - Fail-Closed: corrupted/legacy caches are invalidated, not trusted
## - Atomic Writes: temp file + rename prevents partial writes
## - Source Hashing: hashes src/ + config files, excludes tests/
## - Cross-Platform: Windows MoveFileExW + POSIX moveFile()
## ============================================================================

# ---------------------------------------------------------------------------
# Pure computations (func)
# ---------------------------------------------------------------------------

func computeSha256*(data: string): string {.raises: [], noSideEffect.} =
  ## Compute SHA-256 hex digest of data. Pure function.
  $secureHash(Sha_256, data)

# ---------------------------------------------------------------------------
# Project source hash computation
# ---------------------------------------------------------------------------

var cachedProjectSourceHash {.threadvar.}: string
var projectSourceHashValid {.threadvar.}: bool

proc computeProjectSourceHash*(repoRoot: string; forceRefresh: bool = false): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of src/ contents + build config files.
  ## Excludes tests/ directory.
  ## Cached at runtime - first call computes, subsequent calls return cached result.
  ##
  ## Hash scope:
  ##   - src/**/*.nim (all Nim source files recursively)
  ##   - config.nims
  ##   - axiom.nimble
  ##   - nim.cfg (if present)
  ##   - EXCLUDES: tests/, nimcache/, bin/, .axiom/

  if not forceRefresh and projectSourceHashValid:
    return cachedProjectSourceHash

  var combined = ""

  ## Hash build config files
  let configFiles = ["config.nims", "axiom.nimble", "nim.cfg"]
  for cfg in configFiles:
    let cfgPath = repoRoot / cfg
    if fileExists(cfgPath):
      try:
        combined &= "CFG:" & readFile(cfgPath)
      except CatchableError:
        discard

  ## Hash src/ directory (excluding tests/)
  let srcPath = repoRoot / "src"
  if dirExists(srcPath):
    try:
      var files: seq[string] = @[]
      for path in walkDirRec(srcPath):
        if path.endsWith(".nim"):
          files.add(path)
      files.sort(system.cmp)
      for f in files:
        try:
          combined &= "SRC:" & f & ":" & readFile(f)
        except CatchableError: # axiom:best-effort(source file read failure is non-fatal)
          discard
    except CatchableError: # axiom:best-effort(source file read failure is non-fatal)
      discard

  let hash = computeSha256(combined)
  cachedProjectSourceHash = hash
  projectSourceHashValid = true
  hash

# ---------------------------------------------------------------------------
# Atomic file operations
# ---------------------------------------------------------------------------

proc atomicReplaceFile*(source, dest: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic file replacement: copy to temp, rename to dest.
  ## Cross-platform:
  ##   Windows: MoveFileExW with MOVEFILE_REPLACE_EXISTING (via Nim stdlib moveFile)
  ##   POSIX:   standard moveFile() (atomic rename via rename(2))
  let tmpPath = dest & ".tmp"
  try:
    copyFile(source, tmpPath)
    safeMoveFile(tmpPath, dest)
  except CatchableError as e:
    logWarn("soundness_cache_io", "atomicReplaceFile failed (" & source & " -> " & dest & "): " & e.msg)
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError: discard

# ---------------------------------------------------------------------------
# Cache I/O
# ---------------------------------------------------------------------------

proc loadAndValidateCache*(indexPath: string): SoundnessCache {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load cache from disk with fail-closed validation.
  ##
  ## Fail-Closed Policy:
  ##   - Missing file -> empty cache (force full gate run)
  ##   - Corrupted JSON -> empty cache (force full gate run)
  ##   - Legacy schema version -> empty cache (auto-invalidate)
  ##   - Unknown GateVerificationStatus -> treated as gvsUnchecked
  ##
  ## This ensures no stale or corrupted cache can produce false positives.

  result = SoundnessCache(version: SoundnessCacheSchemaVersion, entries: @[], projectSourceHash: "")

  if not fileExists(indexPath):
    return

  try:
    let content = readFile(indexPath)
    let root = parseJson(content)
    let version = root{"version"}.getStr("")

    ## Auto-invalidate legacy cache versions
    if version.len > 0 and (version == "0.8" or version == "0.9"):
      logInfo("soundness_cache_io", "[SOUNDNESS] Auto-invalidating legacy cache v" & version & " - upgrading to v" & SoundnessCacheSchemaVersion)
      return

    result = deserializeCache(root)

    ## Validate schema version
    if result.version != SoundnessCacheSchemaVersion and result.version.len > 0:
      logInfo("soundness_cache_io", "[SOUNDNESS] Incompatible schema v" & result.version & " - discarding cache")
      result = SoundnessCache(version: SoundnessCacheSchemaVersion, entries: @[], projectSourceHash: "")

  except CatchableError as e:
    logWarn("soundness_cache_io", "[SOUNDNESS] Cache load failed (" & indexPath & "): " & e.msg & " - starting fresh")
    result = SoundnessCache(version: SoundnessCacheSchemaVersion, entries: @[], projectSourceHash: "")

proc saveSoundnessCache*(indexPath: string; cache: SoundnessCache) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically persist the full SoundnessCache to disk.
  ## Uses temp file + rename for atomicity.
  let dir = indexPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    try: createDir(dir)
    except CatchableError: return

  let tmpPath = indexPath & ".tmp"
  try:
    let jsonContent = $serializeCache(cache)
    writeFile(tmpPath, jsonContent)
    safeMoveFile(tmpPath, indexPath)
  except CatchableError as e:
    logWarn("soundness_cache_io", "[SOUNDNESS] Cache save failed (" & indexPath & "): " & e.msg)
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError: discard

proc saveCacheEntry*(indexPath: string; entry: VerificationCacheEntry) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Save a single cache entry, merging with existing cache.
  ## Reads existing cache, adds/updates entry, writes atomically.

  var cache = loadAndValidateCache(indexPath)

  ## Update project source hash if not set
  if cache.projectSourceHash.len == 0:
    cache.projectSourceHash = computeProjectSourceHash("", forceRefresh = false)

  ## Find and update existing entry, or append new one
  var replaced = false
  for i, existing in cache.entries:
    if existing.gateId == entry.gateId and existing.sourceHash == entry.sourceHash:
      cache.entries[i] = entry
      replaced = true
      break

  if not replaced:
    cache.entries.add(entry)

  saveSoundnessCache(indexPath, cache)

{.pop.}
