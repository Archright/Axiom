## Cached wrapper around solveFixedpoint with proof cache integration.
## Breaks circular dependency: proof_cache imports fixedpoint_engine,
## so fixedpoint_engine cannot import proof_cache.
## This module imports BOTH and provides cached entry points.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[options, hashes]
import core/axiom_pragmas
import verification/solver/fixedpoint_engine
import verification/solver/proof_cache
# axiomIoBoundary

var gProofCache: ProofCache
var gCacheInitialized = false

proc initCachedProofCache*(cacheDir: string) {.raises: [].} =
  ## Initialize the module-level proof cache.
  gProofCache = initProofCache(cacheDir)
  gCacheInitialized = true

proc chcHash(chcSource: string): string {.raises: [].} =
  ## Compute a deterministic hash of the CHC source for cache lookup.
  $hash(chcSource)

## @anchor(cached_fixedpoint.cachedSolveFixedpoint)
## Solve a CHC program with proof cache integration.
## On cache hit, skips Z3 invocation entirely.
proc cachedSolveFixedpoint*(
  chcSource: string;
  fingerprint: string;
  timeoutMs: int = 30000
): FixedpointResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not gCacheInitialized:
    # Fallback: no cache initialized, solve directly
    return solveFixedpoint(chcSource, timeoutMs)

  let chcHash = chcHash(chcSource)
  let lookupResult = gProofCache.lookup(fingerprint, chcHash, "")
  if lookupResult.isSome():
    return lookupResult.get().result

  # Cache miss — invoke the solver
  let fxResult = solveFixedpoint(chcSource, timeoutMs)
  gProofCache.store(fingerprint, chcHash, "", fxResult)
  fxResult

proc getProofCacheStats*(): tuple[hits, misses: int, hitRate: float] {.raises: [].} =
  ## Return current proof cache statistics.
  if not gCacheInitialized:
    return (0, 0, 0.0)
  gProofCache.stats()

{.pop.}
