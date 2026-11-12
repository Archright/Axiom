## Pipeline Cache Middleware — integrates AST hash + unsat core cache.
##
## Sits between the CEGAR pipeline request and the solver invocation.
## On verification request:
##   1. Compute content-addressed cache key via ast_hash.computeCacheKey()
##   2. Build fingerprint from (cacheKey, invariantHash)
##   3. Check unsat_core_cache.lookup()
##   4. HIT → return cached result immediately (short-circuit CEGAR)
##   5. MISS → pass to CEGAR engine, store result in cache
##   6. Report CacheMetrics (reuse Phase 5's recordCacheHit/Miss)
##
## Phase 6C: Eliminates redundant solver calls for identical
## (source, invariant) pairs across batch verification runs.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/[strutils]
import core/axiom_pragmas
import verification/batch_uap/ast_hash

# Cache metrics counters (merge artifact: recordCacheHit/Miss were referenced
# but never defined. Providing lightweight stubs.)
var cacheHitCount {.threadvar.}: int
var cacheMissCount {.threadvar.}: int

proc recordCacheHit*() {.inline, raises: [].} =
  cacheHitCount += 1

proc recordCacheMiss*() {.inline, raises: [].} =
  cacheMissCount += 1

proc getCacheHitCount*(): int {.inline, raises: [].} =
  cacheHitCount

proc getCacheMissCount*(): int {.inline, raises: [].} =
  cacheMissCount
import verification/batch_uap/unsat_core_cache
import infrastructure/logging_facade

# axiomIoBoundary — this module coordinates I/O-bearing cache operations

type
  CacheMiddlewareConfig* = object
    ## Configuration for the cache middleware.
    enabled*: bool            ## Master enable/disable switch
    repoRoot*: string         ## Project root for config snapshot loading
    logHits*: bool            ## Whether to log cache hits to stderr

  CacheMiddlewareState* = object
    ## Mutable state for the middleware within a pipeline run.
    config*: CacheMiddlewareConfig
    unsatCache*: UnsatCoreCache
    configHash*: string       ## Cached config combined hash (lazy-loaded)

  CacheLookupResult* = object
    ## Result of a middleware cache lookup.
    hit*: bool                ## true if cache hit
    verified*: bool           ## cached verification result (valid only on hit)
    fingerprint*: string      ## the fingerprint used for lookup
    cacheKey*: string         ## the content-addressed cache key

  CacheStoreResult* = object
    ## Result of a middleware cache store operation.
    stored*: bool             ## true if entry was stored
    fingerprint*: string      ## the fingerprint that was stored
    entryCount*: int          ## current cache size after store

# ── Initialization ───────────────────────────────────────────────────────

func initCacheMiddleware*(config: CacheMiddlewareConfig): CacheMiddlewareState =
  ## Create a new middleware state with the given configuration.
  result.config = config
  result.unsatCache = initUnsatCoreCache()
  result.configHash = ""

proc resetMiddleware*(state: var CacheMiddlewareState) =
  ## Reset all state for a new pipeline run.
  state.unsatCache.clear()
  state.configHash = ""
  resetConfigSnapshot()

# ── Lazy config hash loading ─────────────────────────────────────────────

proc ensureConfigHash(state: var CacheMiddlewareState) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load config snapshot hash if not yet loaded.
  if state.configHash.len == 0:
    let snapshot = loadConfigSnapshot(state.config.repoRoot)
    state.configHash = snapshot.combinedHash

# ── Lookup ───────────────────────────────────────────────────────────────

proc lookup*(state: var CacheMiddlewareState;
    modulePath: string; invariantHash: string): CacheLookupResult
    {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a (module, invariant) pair has already been verified.
  ## Returns hit=true with the cached result on cache hit.
  if not state.config.enabled:
    return CacheLookupResult(hit: false)

  # Ensure config hash is loaded
  ensureConfigHash(state)

  # Compute content-addressed cache key
  let cacheKey = computeCacheKey(modulePath, state.config.repoRoot)

  # Build fingerprint from (cacheKey, invariantHash)
  let fingerprint = buildFingerprint(cacheKey, invariantHash)

  # Check unsat core cache
  if state.unsatCache.lookup(fingerprint):
    let verified = state.unsatCache.lookupResult(fingerprint)
    if state.config.logHits:
      logInfo("cache_middleware", "[CACHE-MIDDLEWARE] HIT " & modulePath &
        " verified=" & $verified &
        " rate=" & formatFloat(state.unsatCache.hitRate(), ffDecimal, 2))
    recordCacheHit()
    return CacheLookupResult(
      hit: true,
      verified: verified,
      fingerprint: fingerprint,
      cacheKey: cacheKey
    )

  # Cache miss
  if state.config.logHits:
    logInfo("cache_middleware", "[CACHE-MIDDLEWARE] MISS " & modulePath &
      " rate=" & formatFloat(state.unsatCache.hitRate(), ffDecimal, 2))
  recordCacheMiss()
  result = CacheLookupResult(
    hit: false,
    fingerprint: fingerprint,
    cacheKey: cacheKey
  )

# ── Store ────────────────────────────────────────────────────────────────

proc store*(state: var CacheMiddlewareState;
    fingerprint: string; verified: bool;
    proofHash: string = ""; modulePath: string = ""): CacheStoreResult
    {.axiomEffect: IOEffect, tags: [TimeEffect, AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store a verification result in the cache.
  ## Call this after the CEGAR engine produces a result.
  if not state.config.enabled or fingerprint.len == 0:
    return CacheStoreResult(stored: false, fingerprint: fingerprint)

  state.unsatCache.store(fingerprint, verified, proofHash, modulePath)
  result = CacheStoreResult(
    stored: true,
    fingerprint: fingerprint,
    entryCount: state.unsatCache.entryCount()
  )

# ── Convenience: full lookup+store cycle ─────────────────────────────────

proc checkOrStore*(state: var CacheMiddlewareState;
    modulePath: string; invariantHash: string;
    verified: bool; proofHash: string = ""): CacheLookupResult
    {.axiomEffect: IOEffect, tags: [TimeEffect, AxiomIOEffect, IOEffect, RootEffect].} =
  ## Combined operation: lookup first, store on miss.
  ## Returns the lookup result (check .hit to know if CEGAR was skipped).
  let lookupResult = state.lookup(modulePath, invariantHash)
  if not lookupResult.hit:
    discard state.store(lookupResult.fingerprint, verified, proofHash, modulePath)
  result = lookupResult

# ── Metrics reporting ────────────────────────────────────────────────────

func middlewareHitRate*(state: CacheMiddlewareState): float =
  ## Expose the unsat core cache hit rate.
  result = state.unsatCache.hitRate()

func middlewareEntryCount*(state: CacheMiddlewareState): int =
  ## Expose the unsat core cache entry count.
  result = state.unsatCache.entryCount()

proc reportMiddlewareMetrics*(state: CacheMiddlewareState)
    {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Output middleware cache metrics to stderr in structured format.
  let rate = formatFloat(state.unsatCache.hitRate(), ffDecimal, 2)
  logInfo("cache_middleware", "[CACHE-MIDDLEWARE-METRICS] hit_rate=" & rate &
    " hits=" & $state.unsatCache.hits &
    " misses=" & $state.unsatCache.misses &
    " entries=" & $state.unsatCache.entryCount())

{.pop.}
