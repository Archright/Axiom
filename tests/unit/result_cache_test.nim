# result_cache_test.nim — S4 Cache: exact-reuse cache tests
#
# Tests for src/verification/result_cache.nim:
#   - Exact HIT (store + load returns the entry)
#   - Changed input → MISS (different identity → no hit)
#   - Tampered payload → refuse (contentDigest mismatch)
#   - dependencyDigests empty → refuse (S4 precondition)
#   - Determinism of key (same inputs → same key)
#
# Execution: nim c --hints:off -r --path:src tests/unit/result_cache_test.nim

import std/[unittest, strutils, sequtils, options, tables]

import core/crypto/hash_kernel
import core/types/result_identity
import engine/proof_certificate
import infrastructure/cas_index
import verification/result_cache
import verification/obligation/identity

# ==========================================================================
# Fixtures
# ==========================================================================

func makeResultCacheEntry*(execId: string;
                     unitId: string;
                     status: ProofStatus;
                     deps: seq[string]): ResultCacheEntry =
  let ur = UnitResult(
    unitId: unitId,
    proofStatus: status,
    failureClassification: "assertion-failure",
    vacuityClassification: "",
    certificateIdentityDigest: sha256Hex("cert-" & unitId),
    resultDigest: sha256Hex(unitId & $status))
  ResultCacheEntry(
    executionIdentity: execId,
    unitResult: ur,
    dependencyDigests: deps)

# ==========================================================================
# Suite: Exact-reuse cache
# ==========================================================================

suite "ExactResultCache — S4 Exact Reuse":

  # -----------------------------------------------------------------------
  # Exact HIT: store + load returns the entry
  # -----------------------------------------------------------------------
  test "exact HIT: store then load returns the same entry":
    let execId = executionIdentity(
      sha256Hex("source-A"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execId, "unit-A", psPass, @["dep-1", "dep-2"])
    cache.store(entry)

    let loaded = cache.load(execId)
    check loaded.isSome()
    check loaded.get().unitResult.unitId == "unit-A"
    check loaded.get().unitResult.proofStatus == psPass
    check loaded.get().dependencyDigests == @["dep-1", "dep-2"]

  # -----------------------------------------------------------------------
  # canReuse returns true for a loaded entry with non-empty deps
  # -----------------------------------------------------------------------
  test "canReuse returns true for valid entry with non-empty dependencyDigests":
    let execId = executionIdentity(
      sha256Hex("source-B"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execId, "unit-B", psFail, @["dep-X"])
    cache.store(entry)

    check cache.canReuse(execId) == true

  # -----------------------------------------------------------------------
  # Changed input → MISS
  # -----------------------------------------------------------------------
  test "changed input produces MISS (different executionIdentity)":
    let execIdA = executionIdentity(
      sha256Hex("source-A"), sha256Hex("contract"), sha256Hex("bundle"))
    let execIdB = executionIdentity(
      sha256Hex("source-B"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execIdA, "unit-A", psPass, @["dep-1"])
    cache.store(entry)

    # Different identity → MISS
    check cache.canReuse(execIdB) == false
    check cache.load(execIdB).isNone()

  # -----------------------------------------------------------------------
  # Tampered stored payload → refuse (witness integrity failure)
  # -----------------------------------------------------------------------
  test "tampered stored payload is refused on load":
    let execId = executionIdentity(
      sha256Hex("source-C"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execId, "unit-C", psPass, @["dep-1"])
    cache.store(entry)

    # Tamper: directly modify the stored unit result's proofStatus
    # (simulating a corrupted or adversarial cache entry)
    var stored = cache.entries.getOrDefault(execId)
    stored.unitResult.proofStatus = psFail
    # Do NOT recompute contentDigest — the witness is now stale
    cache.entries[execId] = stored

    # Load must refuse (contentDigest mismatch → fail-closed)
    let loaded = cache.load(execId)
    check loaded.isNone()

  # -----------------------------------------------------------------------
  # dependencyDigests empty → refuse (S4 precondition)
  # -----------------------------------------------------------------------
  test "empty dependencyDigests → canReuse returns false, load refuses":
    let execId = executionIdentity(
      sha256Hex("source-D"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    # Entry with empty dependencyDigests — S4 precondition not met
    let entry = makeResultCacheEntry(execId, "unit-D", psPass, @[])
    cache.store(entry)

    # canReuse must refuse
    check cache.canReuse(execId) == false

    # load must refuse (fail-closed: dependencyDigests 미충족 reuse 금지)
    let loaded = cache.load(execId)
    check loaded.isNone()

  # -----------------------------------------------------------------------
  # Determinism of key
  # -----------------------------------------------------------------------
  test "deterministicKey produces identical keys for identical inputs":
    let inputId = sha256Hex("same-source")
    let contractDigest = sha256Hex("same-contract")
    let bundleFp = sha256Hex("same-bundle")

    let key1 = deterministicKey(inputId, contractDigest, bundleFp)
    let key2 = deterministicKey(inputId, contractDigest, bundleFp)

    check key1 == key2
    check key1.len == 64

  test "deterministicKey differs for different bundle fingerprint":
    let inputId = sha256Hex("same-source")
    let contractDigest = sha256Hex("same-contract")

    let key1 = deterministicKey(inputId, contractDigest, sha256Hex("bundle-A"))
    let key2 = deterministicKey(inputId, contractDigest, sha256Hex("bundle-B"))

    check key1 != key2

  # -----------------------------------------------------------------------
  # Exact-match only: no restore-key/partial-key fallback
  # -----------------------------------------------------------------------
  test "no partial-key fallback: prefix of identity is not a hit":
    let execId = executionIdentity(
      sha256Hex("source-E"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execId, "unit-E", psPass, @["dep-1"])
    cache.store(entry)

    # A truncated identity (first 16 chars) must NOT match
    let truncated = execId[0 .. 15]
    check truncated != execId
    check cache.canReuse(truncated) == false
    check cache.load(truncated).isNone()

  # -----------------------------------------------------------------------
  # Content digest is recomputed correctly on store
  # -----------------------------------------------------------------------
  test "load on EMPTY cache returns none (Run A MISS-before-populate)":
    ## 계약 §10.2 — Run A canonical sequence: 빈 캐시 → MISS → execute → populate.
    ## Empty cache load must be none (never a stale/partial hit).
    var cache = ExactResultCache()
    let key = deterministicKey("in", "cc", "bf")
    check cache.load(key).isNone()
    check not cache.canReuse(key)

  test "cache key purity: SelectionDigest/PlanDigest do not touch per-unit key (Run E structural)":
    ## 계약 §10.2 Run E — structural invariant: CacheKey(U) ∌ SelectionDigest.
    ## The key is a pure function of (inputIdentity, contractDigest, bundleFingerprint);
    ## selection/plan-level digests must not alter it.
    let k1 = deterministicKey(sha256Hex("src/a.nim::f"), "cc1", "bf1")
    let k2 = deterministicKey(sha256Hex("src/a.nim::f"), "cc1", "bf1")
    check k1 == k2
    ## Behavioral counterpart (Run B) is exercised by cross-selection reuse:
    ## different selection context, same per-unit identity → same key → HIT.

  test "stored contentDigest is recomputed and verified on load":
    let execId = executionIdentity(
      sha256Hex("source-F"), sha256Hex("contract"), sha256Hex("bundle"))
    var cache = ExactResultCache()
    let entry = makeResultCacheEntry(execId, "unit-F", psPass, @["dep-1", "dep-2"])
    cache.store(entry)

    # The stored contentDigest must match what computeContentDigest would
    # produce from the entry's data (without contentDigest itself).
    let stored = cache.entries.getOrDefault(execId)
    check stored.contentDigest == stored.computeContentDigest

    # Load with matching digest succeeds
    let loaded = cache.load(execId)
    check loaded.isSome()
    check loaded.get().unitResult.unitId == "unit-F"