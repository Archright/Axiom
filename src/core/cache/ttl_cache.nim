import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## ttl_cache.nim — Generic TTL cache with automatic eviction.
##
## Uses Table + Deque for O(1) lookup and O(1) expiry.
## No external dependencies. Thread-safe via value semantics.

import std/[times, monotimes, deques, tables, options]
import core/trusted/axiom_pragmas

type
  CacheEntry*[V] = object
    value*: V
    expiresAt*: MonoTime
    createdAt*: MonoTime

  TtlCache*[K, V] = object
    store*: Table[K, CacheEntry[V]]
    expiryOrder*: Deque[K]
    ttl*: Duration

func newTtlCache*[K, V](ttl: Duration): TtlCache[K, V] =
  TtlCache[K, V](
    store: initTable[K, CacheEntry[V]](),
    expiryOrder: initDeque[K](),
    ttl: ttl
  )

proc evictExpired*[K, V](cache: var TtlCache[K, V]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove all expired entries. Called automatically on get/put.
  let now = getMonoTime()
  while cache.expiryOrder.len > 0:
    let front = cache.expiryOrder.peekFirst()
    if cache.store.hasKey(front):
      let entry = cache.store.getOrDefault(front)
      if entry.expiresAt <= now:
        cache.store.del(front)
        cache.expiryOrder.popFirst()
      else:
        break
    else:
      cache.expiryOrder.popFirst()

proc put*[K, V](cache: var TtlCache[K, V], key: K, value: V) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Insert or update a cache entry with TTL.
  cache.evictExpired()
  let now = getMonoTime()
  cache.store[key] = CacheEntry[V](value: value, expiresAt: now + cache.ttl, createdAt: now)
  cache.expiryOrder.addLast(key)

proc get*[K, V](cache: var TtlCache[K, V], key: K): Option[V] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retrieve a cached value. Returns none if expired or missing.
  cache.evictExpired()
  if cache.store.hasKey(key):
    some(cache.store.getOrDefault(key).value)
  else:
    none(V)

proc contains*[K, V](cache: var TtlCache[K, V], key: K): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  cache.evictExpired()
  cache.store.hasKey(key)

func len*[K, V](cache: TtlCache[K, V]): int =
  cache.store.len

proc clear*[K, V](cache: var TtlCache[K, V]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  cache.store.clear()
  cache.expiryOrder.clear()

{.pop.}

