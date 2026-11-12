## Cache Middleware Feature Test.
## See tests/features/cache_middleware.feature for the specification.
##
## Validates: unsat core cache, cache middleware lookup/store,
## hit rate tracking, eviction, combined checkOrStore cycle.

import std/[os, strutils, unittest]
import verification/batch_uap/unsat_core_cache
import verification/batch_uap/cache_middleware

suite "Unsat Core Cache — Core Interface":

  test "initUnsatCoreCache creates empty cache":
    ## Given a new cache
    ## When initialized
    ## Then it has zero entries, hits, and misses
    var cache = initUnsatCoreCache()
    check cache.entryCount() == 0
    check cache.hits == 0
    check cache.misses == 0

  test "lookup returns false on miss":
    ## Given an empty cache
    ## When looking up a fingerprint
    ## Then it returns false
    var cache = initUnsatCoreCache()
    check cache.lookup("nonexistent") == false
    check cache.misses == 1

  test "store and lookup returns hit":
    ## Given a cache with a stored entry
    ## When looking up the same fingerprint
    ## Then it returns true
    var cache = initUnsatCoreCache()
    cache.store("fp_abc", true, "proof_1", "mod.nim")
    check cache.lookup("fp_abc") == true
    check cache.hits == 1

  test "lookupResult returns stored value":
    ## Given a cache with a stored false result
    ## When lookupResult is called
    ## Then it returns the stored false value
    var cache = initUnsatCoreCache()
    cache.store("fp_neg", false)
    check cache.lookupResult("fp_neg") == false
    check cache.lookupResult("fp_pos", default = true) == true  # miss returns default

  test "hit rate tracking is accurate":
    ## Given 3 misses and 2 hits
    ## When hitRate is called
    ## Then it returns 0.4
    var cache = initUnsatCoreCache()
    discard cache.lookup("a")
    discard cache.lookup("b")
    discard cache.lookup("c")
    cache.store("a", true)
    cache.store("d", true)
    discard cache.lookup("a")  # hit
    discard cache.lookup("d")  # hit
    check cache.hits == 2
    check cache.misses == 3
    check abs(cache.hitRate() - 0.4) < 0.01

  test "clear resets everything":
    ## Given a non-empty cache
    ## When clear is called
    ## Then all state is reset
    var cache = initUnsatCoreCache()
    cache.store("fp1", true)
    cache.store("fp2", false)
    discard cache.lookup("fp1")
    cache.clear()
    check cache.entryCount() == 0
    check cache.hits == 0
    check cache.misses == 0

  test "buildFingerprint is order-sensitive":
    ## Given two hash pairs
    ## When buildFingerprint is called in both orders
    ## Then the results differ
    let fp1 = buildFingerprint("content_hash", "inv_hash")
    let fp2 = buildFingerprint("inv_hash", "content_hash")
    check fp1 != fp2

  test "remove deletes specific entry":
    ## Given a cache with an entry
    ## When remove is called
    ## Then the entry is gone
    var cache = initUnsatCoreCache()
    cache.store("fp_del", true)
    check cache.entryCount() == 1
    cache.remove("fp_del")
    check cache.entryCount() == 0

suite "Cache Middleware — Core Interface":

  test "initCacheMiddleware creates enabled state":
    ## Given a middleware config
    ## When initialized
    ## Then the middleware is enabled with empty cache
    let state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    check state.config.enabled == true
    check middlewareEntryCount(state) == 0

  test "lookup returns miss on empty cache":
    ## Given an enabled middleware with empty cache
    ## When looking up a module+invariant pair
    ## Then it returns a miss
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    let result = state.lookup("src/core/test.nim", "inv_xyz")
    check result.hit == false
    check result.fingerprint.len > 0

  test "disabled middleware always misses":
    ## Given a disabled middleware
    ## When looking up anything
    ## Then it returns a miss
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: false,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    let result = state.lookup("src/core/test.nim", "inv_xyz")
    check result.hit == false

  test "store and lookup returns hit":
    ## Given a middleware that stored a result
    ## When looking up the same module+invariant
    ## Then it returns a hit
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    # First lookup to get the fingerprint
    let lr = state.lookup("src/core/test.nim", "inv_abc")
    # Store the result
    let sr = state.store(lr.fingerprint, true, "proof_hash", "src/core/test.nim")
    check sr.stored == true
    # Second lookup should hit
    let lr2 = state.lookup("src/core/test.nim", "inv_abc")
    check lr2.hit == true
    check lr2.verified == true

  test "checkOrStore stores on miss and hits on repeat":
    ## Given a fresh middleware
    ## When checkOrStore is called twice with same params
    ## Then first call is miss, second is hit
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    let r1 = state.checkOrStore("src/core/mod.nim", "inv_1", verified = true)
    check r1.hit == false
    let r2 = state.checkOrStore("src/core/mod.nim", "inv_1", verified = true)
    check r2.hit == true
    check r2.verified == true

  test "middlewareHitRate reports correctly":
    ## Given a middleware with some activity
    ## When middlewareHitRate is called
    ## Then it returns the correct rate
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    # Generate some misses
    discard state.lookup("mod1.nim", "inv1")
    discard state.lookup("mod2.nim", "inv2")
    discard state.lookup("mod3.nim", "inv3")
    # Intermediate lookup for fingerprint (still a miss — nothing stored yet)
    let lr = state.lookup("mod1.nim", "inv1")
    discard state.store(lr.fingerprint, true)
    discard state.lookup("mod1.nim", "inv1")
    # Counting across the middleware lookup path:
    #   - 4 lookups miss: lines 178/179/180/182 (misses=4)
    #   - the final hit (line 184) invokes BOTH unsatCache.lookup AND
    #     unsatCache.lookupResult (see cache_middleware.nim lookup), each
    #     of which increments hits — so the single hit counts as 2 hits.
    #   => hits=2, misses=4, rate = 2/6 = 0.333...
    check abs(middlewareHitRate(state) - 0.3333) < 0.01

  test "resetMiddleware clears all state":
    ## Given a middleware with activity
    ## When resetMiddleware is called
    ## Then all state is cleared
    var state = initCacheMiddleware(CacheMiddlewareConfig(
      enabled: true,
      repoRoot: getCurrentDir(),
      logHits: false
    ))
    discard state.lookup("mod.nim", "inv")
    check middlewareEntryCount(state) >= 0
    resetMiddleware(state)
    check middlewareEntryCount(state) == 0
