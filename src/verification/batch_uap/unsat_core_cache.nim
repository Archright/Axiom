## Unsat Core Cache — fingerprint-to-result mapping for CEGAR pipeline.
##
## Maps invariant+AST fingerprints to verification results, enabling
## short-circuit of redundant solver calls when the same logical
## specification has already been verified.
##
## Phase 6C: Content-addressed cache layer that sits above the summary
## cache and uses SHA-256 fingerprints for high-precision deduplication.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/[times, tables]

const vacuityGateSchemaVersion* = "v5_semantic_gate"

type
  UnsatCoreEntry* = object
    ## A single cached verification result keyed by fingerprint.
    fingerprint*: string      ## SHA-256 of (invariant + AST content hash)
    result*: bool             ## true = verified, false = not verified
    timestamp*: float         ## epoch seconds when stored
    proofHash*: string        ## hash of proof certificate (for auditing)
    modulePath*: string       ## source module for diagnostics

  UnsatCoreCache* = object
    ## In-memory fingerprint cache with O(1) amortized LRU eviction.
    entries*: Table[string, UnsatCoreEntry]
    insertionOrder*: seq[string]  ## Bounded insertion-order queue
    evictionHead*: int            ## Index into insertionOrder for O(1) eviction
    hits*: int
    misses*: int

const maxCacheEntries* = 4096  ## Hard cap to prevent memory growth

# ── Core operations ──────────────────────────────────────────────────────

proc initUnsatCoreCache*(): UnsatCoreCache =
  ## Create an empty cache.
  result.entries = initTable[string, UnsatCoreEntry]()
  result.insertionOrder = @[]
  result.evictionHead = 0
  result.hits = 0
  result.misses = 0

proc lookup*(cache: var UnsatCoreCache; fingerprint: string): bool =
  ## Returns true if cache HIT (fingerprint found), false if MISS.
  ## On hit, caller should use the cached result. On miss, caller
  ## should run verification and call store().
  if fingerprint in cache.entries:
    cache.hits += 1
    return true
  cache.misses += 1
  return false

proc lookupResult*(cache: var UnsatCoreCache; fingerprint: string;
    default: bool = false): bool =
  ## Lookup and return the cached result, or default on miss.
  if fingerprint in cache.entries:
    cache.hits += 1
    return cache.entries[fingerprint].result
  cache.misses += 1
  return default

proc store*(cache: var UnsatCoreCache; fingerprint: string;
    result: bool; proofHash: string = ""; modulePath: string = "") {.raises: [].} =
  ## Store a verification result in the cache.
  ## Evicts oldest entry in O(1) amortized via insertion-order queue.
  if fingerprint in cache.entries:
    # Update existing entry — no change to insertionOrder (tombstone tolerated)
    cache.entries[fingerprint] = UnsatCoreEntry(
      fingerprint: fingerprint,
      result: result,
      timestamp: epochTime(),
      proofHash: proofHash,
      modulePath: modulePath
    )
    return

  # W2-F: O(1) amortized eviction — pop from insertion-order head, skip tombstones
  if cache.entries.len >= maxCacheEntries:
    while cache.evictionHead < cache.insertionOrder.len:
      let oldestKey = cache.insertionOrder[cache.evictionHead]
      inc cache.evictionHead
      if oldestKey in cache.entries:
        cache.entries.del(oldestKey)
        break

  cache.insertionOrder.add(fingerprint)
  cache.entries[fingerprint] = UnsatCoreEntry(
    fingerprint: fingerprint,
    result: result,
    timestamp: epochTime(),
    proofHash: proofHash,
    modulePath: modulePath
  )

proc remove*(cache: var UnsatCoreCache; fingerprint: string) =
  ## Remove a specific entry from the cache.
  if fingerprint in cache.entries:
    cache.entries.del(fingerprint)

proc clear*(cache: var UnsatCoreCache) =
  ## Clear all entries and reset counters.
  cache.entries.clear()
  cache.insertionOrder = @[]
  cache.evictionHead = 0
  cache.hits = 0
  cache.misses = 0

# ── Metrics ──────────────────────────────────────────────────────────────

proc hitRate*(cache: UnsatCoreCache): float =
  ## Cache hit ratio as [0.0, 1.0]. Returns 0.0 when no lookups recorded.
  let total = cache.hits + cache.misses
  if total == 0: 0.0
  else: cache.hits.float / total.float

proc totalLookups*(cache: UnsatCoreCache): int =
  ## Total number of lookup attempts.
  result = cache.hits + cache.misses

proc entryCount*(cache: UnsatCoreCache): int =
  ## Number of entries currently in the cache.
  result = cache.entries.len

proc buildFingerprint*(contentHash: string;
    invariantHash: string): string =
  ## Build a cache fingerprint from content and invariant hashes.
  ## The fingerprint uniquely identifies a (source, invariant) pair.
  ## Order-sensitive: different invariant on same source → different key.
  result = contentHash & "|" & invariantHash & "|" & vacuityGateSchemaVersion

{.pop.}

