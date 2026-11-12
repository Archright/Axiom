import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## proof_cache.nim — Cache for Legislator LLM invariant drafting results.
##
## Caches invariant proposals by (functionName, sourceHash) to avoid
## redundant LLM calls for unchanged source code.
## Uses TtlCache for automatic expiry.

import std/[times, options, strutils, hashes]
import core/cache/ttl_cache
import core/trusted/axiom_pragmas

const
  DefaultProofCacheTtl* = initDuration(minutes = 30)
  MaxCacheKeyLen* = 256

type
  ProofCacheKey* = object
    functionName*: string
    sourceHash*: string

  ProofCacheEntry* = object
    proposedInvariant*: string
    activeInvariant*: string
    evolutionReasoning*: string
    fromCache*: bool

  ProofCache* = TtlCache[ProofCacheKey, ProofCacheEntry]

func hash*(key: ProofCacheKey): Hash =
  result = hash(key.functionName)
  result = result !& hash(key.sourceHash)

func `==`*(a, b: ProofCacheKey): bool =
  a.functionName == b.functionName and a.sourceHash == b.sourceHash

func newProofCache*(ttl: Duration = DefaultProofCacheTtl): ProofCache {.refines: "src/core/cache/proof_cache_shadow.nim".} =
  newTtlCache[ProofCacheKey, ProofCacheEntry](ttl)

func computeSourceHash*(source: string): string =
  let h = hash(source)
  result = toHex(h.int64)

func makeCacheKey*(functionName, source: string): ProofCacheKey =
  ProofCacheKey(
    functionName: functionName,
    sourceHash: computeSourceHash(source)
  )

proc get*(cache: var ProofCache, functionName, source: string): Option[ProofCacheEntry] =
  let key = makeCacheKey(functionName, source)
  cache.get(key)

proc put*(cache: var ProofCache, functionName, source: string,
          proposedInvariant, activeInvariant, evolutionReasoning: string) =
  let key = makeCacheKey(functionName, source)
  cache.put(key, ProofCacheEntry(
    proposedInvariant: proposedInvariant,
    activeInvariant: activeInvariant,
    evolutionReasoning: evolutionReasoning,
    fromCache: false
  ))

proc getOrEmpty*(cache: var ProofCache, functionName, source: string): ProofCacheEntry =
  let cached = cache.get(functionName, source)
  if cached.isSome:
    var entry = cached.get()
    entry.fromCache = true
    entry
  else:
    ProofCacheEntry(fromCache: false)

{.pop.}
