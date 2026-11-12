## Unsat Core Cache — Additional Feature Tests
## See tests/features/unsat_core_cache.feature for the specification.
##
## Focuses on scenarios NOT covered in cache_middleware_feature_test.nim:
##   - LRU eviction at maxCacheEntries capacity
##   - Hit rate tracking at 0.7 (7 hits, 3 misses)
##   - Value-type safety (no ref object fields)
##   - totalLookups counter consistency
##   - store update (existing key) does not grow entry count

import std/[unittest, strutils]
import verification/batch_uap/unsat_core_cache

suite "Unsat Core Cache — LRU Eviction at Capacity":

  test "maxCacheEntries constant is 4096":
    ## Given the unsat_core_cache module
    ## When the maxCacheEntries constant is accessed
    ## Then it must equal 4096 (feature: capacity 4096)
    check maxCacheEntries == 4096

  test "eviction removes oldest entry when at capacity":
    ## Given a cache filled to maxCacheEntries
    ## When a new entry is stored
    ## Then the total entry count does not exceed maxCacheEntries
    ## And the new entry is present
    var cache = initUnsatCoreCache()

    # Fill cache to capacity using deterministic keys
    for i in 0 ..< maxCacheEntries:
      cache.store("fp_" & $i, true, "proof_" & $i, "mod_" & $i)

    check cache.entryCount() == maxCacheEntries

    # Store one more — triggers eviction of oldest (fp_0)
    cache.store("fp_new", true, "proof_new", "mod_new")

    # Entry count stays at or below max (one evicted, one added)
    check cache.entryCount() <= maxCacheEntries

    # The new entry must be present
    check cache.lookup("fp_new") == true

    # The very first entry (fp_0) should have been evicted
    # (it was the oldest timestamp)
    cache.misses = 0  # reset for clean check
    let wasEvicted = not cache.lookup("fp_0")
    check wasEvicted == true

  test "eviction fires only when at capacity boundary":
    ## Given a cache below capacity
    ## When entries are stored
    ## Then no eviction occurs and entry count grows
    var cache = initUnsatCoreCache()

    for i in 0 ..< 100:
      cache.store("fp_" & $i, true)

    # All 100 should be present — no eviction at sub-capacity
    check cache.entryCount() == 100
    check cache.lookup("fp_0") == true
    check cache.lookup("fp_99") == true

  test "store update on existing key does not grow entry count":
    ## Given a cache with one entry
    ## When storing with the same fingerprint (update)
    ## Then entry count remains 1
    var cache = initUnsatCoreCache()
    cache.store("fp_update", true, "old_proof")
    check cache.entryCount() == 1

    # Update the same key
    cache.store("fp_update", false, "new_proof")
    check cache.entryCount() == 1

    # The updated value should be returned
    check cache.lookupResult("fp_update") == false

suite "Unsat Core Cache — Hit Rate at 0.7":

  test "hit rate is exactly 0.7 with 7 hits and 3 misses":
    ## Given a cache with 3 misses and 7 hits
    ## When the hit rate is queried
    ## Then the hit rate must be 0.7
    var cache = initUnsatCoreCache()

    # Pre-populate 10 entries so lookups can hit
    for i in 0 ..< 10:
      cache.store("hit_" & $i, i < 5)

    # Reset counters to start fresh
    cache.hits = 0
    cache.misses = 0

    # 3 misses on non-existent keys
    check cache.lookup("miss_a") == false
    check cache.lookup("miss_b") == false
    check cache.lookup("miss_c") == false

    # 7 hits on pre-stored keys
    for i in 0 ..< 7:
      check cache.lookup("hit_" & $i) == true

    check cache.hits == 7
    check cache.misses == 3
    check abs(cache.hitRate() - 0.7) < 0.001

  test "hit rate is 1.0 when all lookups hit":
    ## Given a cache with entries
    ## When every lookup is a hit
    ## Then hit rate is 1.0
    var cache = initUnsatCoreCache()
    cache.store("a", true)
    cache.store("b", true)
    cache.store("c", true)

    discard cache.lookup("a")
    discard cache.lookup("b")
    discard cache.lookup("c")
    discard cache.lookup("a")  # duplicate hit

    check cache.hits == 4
    check cache.misses == 0
    check abs(cache.hitRate() - 1.0) < 0.001

  test "hit rate is 0.0 when all lookups miss":
    ## Given an empty cache
    ## When lookups miss
    ## Then hit rate is 0.0
    var cache = initUnsatCoreCache()
    discard cache.lookup("x")
    discard cache.lookup("y")

    check cache.hits == 0
    check cache.misses == 2
    check abs(cache.hitRate() - 0.0) < 0.001

  test "totalLookups equals hits plus misses":
    ## Given a cache with activity
    ## When totalLookups is queried
    ## Then it equals hits + misses
    var cache = initUnsatCoreCache()
    cache.store("a", true)
    discard cache.lookup("a")   # hit
    discard cache.lookup("b")   # miss
    discard cache.lookup("c")   # miss
    discard cache.lookup("a")   # hit

    check cache.totalLookups() == 4
    check cache.totalLookups() == cache.hits + cache.misses

suite "Unsat Core Cache — Value-Type Safety":

  test "UnsatCoreCache is a value type (copy semantics)":
    ## Given an UnsatCoreCache value
    ## When copied to another variable
    ## Then mutations to the copy do not affect the original
    var original = initUnsatCoreCache()
    original.store("fp_val", true)

    var copy = original
    copy.store("fp_copy", false)

    # Original should not be affected by copy's mutation
    check original.entryCount() == 1
    check original.lookup("fp_val") == true

    # Copy has both entries
    check copy.entryCount() == 2

  test "initUnsatCoreCache returns zero-valued object":
    ## Given a freshly initialized cache
    ## When inspected
    ## Then all fields are at their zero/default values
    var cache = initUnsatCoreCache()
    check cache.entryCount() == 0
    check cache.hits == 0
    check cache.misses == 0

  test "buildFingerprint produces deterministic output":
    ## Given the same content and invariant hashes
    ## When buildFingerprint is called twice
    ## Then both calls return identical strings
    let fp1 = buildFingerprint("abc123", "def456")
    let fp2 = buildFingerprint("abc123", "def456")
    check fp1 == fp2

  test "buildFingerprint uses pipe separator":
    ## Given content hash and invariant hash
    ## When buildFingerprint is called
    ## Then the result contains a pipe separator
    let fp = buildFingerprint("content", "inv")
    check "|" in fp
    check fp == "content|inv"

  test "lookupResult default parameter works on miss":
    ## Given an empty cache
    ## When lookupResult is called with a non-default default
    ## Then the custom default is returned
    var cache = initUnsatCoreCache()
    check cache.lookupResult("nope", default = true) == true
    check cache.lookupResult("nope", default = false) == false
    check cache.misses == 2

  test "remove on nonexistent key is safe":
    ## Given an empty cache
    ## When remove is called for a nonexistent key
    ## Then no error occurs and entry count stays 0
    var cache = initUnsatCoreCache()
    cache.remove("nonexistent")
    check cache.entryCount() == 0
