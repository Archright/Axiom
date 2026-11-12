## Incremental proof cache for Z3 Fixedpoint results.
## Keys: functionFingerprint + chcRuleHash + z3Version → SHA256
## Storage: data/proof_cache/ (Git-ignored)
## Invalidation: source fingerprint change → cache miss → re-solve
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[tables, os, strutils, times, options]
import core/crypto/hash_kernel
import verification/solver/fixedpoint_engine
import core/trusted/axiom_pragmas
# axiomIoBoundary

type
  ProofCacheEntry* = object
    functionFingerprint*: string    ## AST fingerprint (SHA256 of source)
    chcRuleHash*: string            ## CHC rules SHA256
    z3Version*: string              ## Z3 version string
    result*: FixedpointResult       ## Cached verification result
    timestamp*: float               ## Unix timestamp (epoch seconds)

  ProofCache* = object
    entries*: Table[string, ProofCacheEntry]  ## key → entry
    cacheDir*: string                          ## e.g., "data/proof_cache"
    hits*: int
    misses*: int

func computeCacheKey*(fingerprint, chcHash, z3Ver: string): string {.raises: [].} =
  ## Compute a deterministic cache key from composite inputs.
  let combined = fingerprint & "|" & chcHash & "|" & z3Ver
  sha256Hex(combined)

proc initProofCache*(cacheDir: string): ProofCache {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Initialize cache. Creates cache directory if it doesn't exist.
  result.cacheDir = cacheDir
  result.entries = initTable[string, ProofCacheEntry]()
  result.hits = 0
  result.misses = 0
  if not dirExists(cacheDir):
    try:
      createDir(cacheDir)
    except CatchableError:
      discard  # Cache directory creation failure is non-fatal  # axiom:best-effort(ioboundary catch)

proc lookup*(cache: var ProofCache; fingerprint, chcHash, z3Ver: string): Option[ProofCacheEntry] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Look up a cached result. Returns none on miss.
  let key = computeCacheKey(fingerprint, chcHash, z3Ver)
  if cache.entries.hasKey(key):
    cache.hits += 1
    return some(cache.entries.getOrDefault(key))
  # Try disk cache
  let path = cache.cacheDir / key & ".json"
  if fileExists(path):
    try:
      let content = readFile(path)
      # Minimal JSON parsing: check if result.sat is present
      if "\"sat\":true" in content or "\"sat\":false" in content:
        var entry = ProofCacheEntry(
          functionFingerprint: fingerprint,
          chcRuleHash: chcHash,
          z3Version: z3Ver,
          timestamp: epochTime()
        )
        # Parse sat field
        if "\"sat\":true" in content:
          entry.result.sat = true
        else:
          entry.result.sat = false
        cache.entries[key] = entry
        cache.hits += 1
        return some(entry)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  cache.misses += 1
  none(ProofCacheEntry)

func escapeJson(s: string): string {.raises: [].} =
  ## Minimal JSON string escaping for proof cache persistence.
  result = ""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)

proc store*(cache: var ProofCache; fingerprint, chcHash, z3Ver: string; result: FixedpointResult) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store a result in both memory and disk cache.
  let key = computeCacheKey(fingerprint, chcHash, z3Ver)
  let entry = ProofCacheEntry(
    functionFingerprint: fingerprint,
    chcRuleHash: chcHash,
    z3Version: z3Ver,
    result: result,
    timestamp: epochTime()
  )
  cache.entries[key] = entry
  # Persist to disk
  let path = cache.cacheDir / key & ".json"
  try:
    let json = "{\"sat\":" & $result.sat &
               ",\"invariant\":\"" & escapeJson(result.invariant) & "\"" &
               ",\"counterexample\":\"" & escapeJson(result.counterexample) & "\"" &
               ",\"timestamp\":" & $entry.timestamp & "}"
    writeFile(path, json)
  except CatchableError:
    discard  # Disk write failure is non-fatal (memory cache still works)  # axiom:best-effort(ioboundary catch)

func stats*(cache: ProofCache): tuple[hits, misses: int, hitRate: float] {.raises: [].} =
  ## Return cache statistics.
  let total = cache.hits + cache.misses
  let rate = if total > 0: cache.hits.float / total.float else: 0.0
  (cache.hits, cache.misses, rate)

proc invalidateNode*(cache: var ProofCache; fingerprint: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Invalidate all cache entries for a specific function fingerprint.
  ## Called when source changes detected.
  var toDelete: seq[string] = @[]
  for key, entry in cache.entries.pairs:
    if entry.functionFingerprint == fingerprint:
      toDelete.add(key)
  for key in toDelete:
    cache.entries.del(key)
    let path = cache.cacheDir / key & ".json"
    try:
      if fileExists(path):
        removeFile(path)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

{.pop.}
