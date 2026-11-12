import core/trusted/layer_declaration
axiomLayer "gate"
# axiom:cas-cache
## Gate Cache — Simplified CAS engine for gate execution results.
##
## Computes cache key from gate ID, config, and input state hash.
## Stores results in .cache/gates/ directory.

import std/[json, os, times, algorithm, options]
import gate/gate_contract
export GateResult, FailureCategory

# axiom:json-serialization
# ═══════════════════════════════════════════════════════════════
# GateResult JSON Serialization
# ═══════════════════════════════════════════════════════════════

proc `$`*(fc: FailureCategory): string =
  case fc
  of fcPermanent: "fcPermanent"
  of fcTransient: "fcTransient"
  of fcValidation: "fcValidation"
  of fcUnknown: "fcUnknown"

proc `%`*(res: GateResult): JsonNode =
  ## Serialize GateResult to JSON node.
  result = %*{
    "ok": res.ok,
    "name": res.name,
    "stdout": res.stdout,
    "stderr": res.stderr,
    "durationMs": inMilliseconds(res.duration),
    "failureCategory": $res.failureCategory,
    "failureReason": res.failureReason,
    "skipCiRequested": res.skipCiRequested
  }

proc toGateResult*(node: JsonNode): GateResult =
  ## Deserialize GateResult from JSON node.
  ## Defaults: ok=false, empty strings, zero duration, fcUnknown
  if node.kind == JNull:
    return GateResult(
      ok: false,
      name: "",
      stdout: "",
      stderr: "",
      duration: initDuration(),
      failureCategory: fcUnknown,
      failureReason: "",
      skipCiRequested: false
    )

  if node.kind != JObject:
    return GateResult(
      ok: false,
      name: "",
      stdout: "",
      stderr: "",
      duration: initDuration(),
      failureCategory: fcUnknown,
      failureReason: "",
      skipCiRequested: false
    )

  func tryGetBool(node: JsonNode; key: string): bool =
    let v = node[key]
    if v.kind == JBool: return v.getBool()
    false

  func tryGetString(node: JsonNode; key: string): string =
    let v = node[key]
    if v.kind == JString: return v.str
    ""

  func tryGetInt(node: JsonNode; key: string): int =
    let v = node[key]
    if v.kind == JInt: return int(v.num)
    0

  func parseFailureCategory(s: string): FailureCategory =
    case s
    of "fcPermanent": fcPermanent
    of "fcTransient": fcTransient
    of "fcValidation": fcValidation
    else: fcUnknown

  result = GateResult(
    ok: tryGetBool(node, "ok"),
    name: tryGetString(node, "name"),
    stdout: tryGetString(node, "stdout"),
    stderr: tryGetString(node, "stderr"),
    duration: initDuration(milliseconds = tryGetInt(node, "durationMs")),
    failureCategory: parseFailureCategory(tryGetString(node, "failureCategory")),
    failureReason: tryGetString(node, "failureReason"),
    skipCiRequested: tryGetBool(node, "skipCiRequested")
  )

# axiom:pure-cas
# Pure Content-Addressable Storage — no time-based expiration.
# Cache entries are valid as long as their input state hash matches.
# Capacity enforcement uses a simple LRU sweeper based on file modification time.

const
  MaxCacheSize* = 100 * 1024 * 1024  # 100 MB

# ---------------------------------------------------------------------------
# Cache Key Generation
# ---------------------------------------------------------------------------

proc computeGateCacheKey*(gateId: string, configJson: string, targetStateHash: string): string =
  ## Compute deterministic cache key using SHA-1.
  let input = gateId & ":" & configJson & ":" & targetStateHash
  result = $secureHash(input)

# ---------------------------------------------------------------------------
# Cache Storage (Pure CAS)
# ---------------------------------------------------------------------------

proc getCachePath*(cacheKey: string): string =
  ## Get file path for cache key.
  result = ".cache/gates/" & cacheKey & ".json"

proc hasCachedResult*(cacheKey: string): bool =
  ## Check if cache exists for key.
  let path = getCachePath(cacheKey)
  result = fileExists(path)

proc getCacheStats*(): tuple[count: int, size: int64] =
  ## Get cache statistics (file count + total size in bytes).
  let cacheDir = ".cache/gates"
  if not dirExists(cacheDir):
    return (0, 0)
  
  var count = 0
  var size = 0'i64
  
  for file in walkFiles(cacheDir / "*.json"):
    inc count
    size += getFileSize(file)
  
  result = (count, size)

proc sweepCacheIfNeeded*() =
  ## Capacity-based LRU sweeper.
  ## If total cache size exceeds MaxCacheSize, delete the oldest files
  ## (by modification time) until the cache fits within the limit.
  let cacheDir = ".cache/gates"
  let (count, size) = getCacheStats()
  if size <= MaxCacheSize or count == 0:
    return
  
  # Collect files sorted by modification time (oldest first)
  var files: seq[string] = @[]
  for file in walkFiles(cacheDir / "*.json"):
    files.add(file)
  
  # Sort by mtime ascending (oldest first)
  files.sort(proc (a, b: string): int =
    cmp(getLastModificationTime(a), getLastModificationTime(b))
  )
  
  # Delete oldest files until we're under the limit
  for file in files:
    if getCacheStats().size <= MaxCacheSize:
      break
    try:
      removeFile(file)
    except CatchableError:
      discard

proc saveCacheResult*(cacheKey: string, res: GateResult) =
  ## Save gate result to cache as full JSON using % operator.
  let path = getCachePath(cacheKey)
  let dir = path.parentDir()
  
  try:
    if not dirExists(dir):
      createDir(dir)
    
    let json = %res
    writeFile(path, $json)
  except CatchableError:
    discard
  
  # Enforce capacity via LRU sweeper after every write
  sweepCacheIfNeeded()

proc getCachedResult*(cacheKey: string): Option[GateResult] =
  ## Load cached gate result from JSON using toGateResult.
  let path = getCachePath(cacheKey)
  if not fileExists(path):
    return none(GateResult)
  
  try:
    let content = readFile(path)
    let node = parseJson(content)
    result = some(toGateResult(node))
  except CatchableError:
    return none(GateResult)

# ---------------------------------------------------------------------------
# Cache Management
# ---------------------------------------------------------------------------

proc clearCache*() =
  ## Clear all cached results.
  let cacheDir = ".cache/gates"
  if dirExists(cacheDir):
    removeDir(cacheDir)

# ---------------------------------------------------------------------------
# Test Harness
# ---------------------------------------------------------------------------

when isMainModule:
  let key = computeGateCacheKey("test-gate", "{}", "abc123")
  echo "=== Cache Key ==="
  echo "Cache key: " & key
  echo "Cache path: " & getCachePath(key)
  
  # Test GateResult serialization round-trip
  let original = GateResult(
    ok: true,
    name: "test-gate",
    stdout: "gate passed successfully",
    stderr: "",
    duration: initDuration(milliseconds = 150),
    failureCategory: fcValidation,
    failureReason: "",
    skipCiRequested: false
  )
  
  echo "\n=== Serialization Test ==="
  echo "Original: ok=" & $original.ok & " name=" & original.name & " durationMs=" & $inMilliseconds(original.duration)
  
  saveCacheResult(key, original)
  echo "Saved to cache: " & $hasCachedResult(key)
  
  let loadedOpt = getCachedResult(key)
  if loadedOpt.isSome():
    let loaded = loadedOpt.get()
    echo "Loaded: ok=" & $loaded.ok & " name=" & loaded.name & " durationMs=" & $inMilliseconds(loaded.duration)
    echo "Round-trip match: " & $(loaded.ok == original.ok and loaded.name == original.name and loaded.stdout == original.stdout and loaded.failureCategory == original.failureCategory)
  else:
    echo "ERROR: Failed to load cached result"
  
  echo "\n=== Cache Stats ==="
  let stats = getCacheStats()
  echo "Stats: " & $stats.count & " files, " & $stats.size & " bytes"
