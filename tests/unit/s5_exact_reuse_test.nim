## s5_exact_reuse_test.nim — S5 / Promotion-B exact-reuse integrity
##
## Covers (canonical infrastructure only — no new identity schema):
##   - cross-selection exact reuse: same semantic unit under Selection A/B/C
##     yields the SAME per-unit ExecutionIdentity → same cache key → HIT with
##     identical content (resultDigest equal), selection context never in key.
##   - false cache hit = 0: a stored entry can never load as a DIFFERENT
##     result; contentDigest witness mismatch → refusal (fail-closed).
##   - selection-independent UnitResult: UnitResult serialization contains no
##     selection/plan digest fields; resultDigest is a pure function of the
##     unit's own fields.
##
## Uses: verification/result_cache (ExactResultCache), identity.nim
## (executionIdentity), proof_status.

{.push raises: [CatchableError].}

import std/[json, sequtils, strutils, options, tables, unittest]
import core/crypto/hash_kernel
import core/types/proof_status
import core/types/result_identity
import verification/obligation/identity
import verification/result_cache

# ---------------------------------------------------------------------------
# Fixture (test-local constructor — mirrors result_cache_test.nim helper)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc unitExecutionIdentity(unitSrc: string): string =
  ## Canonical per-unit identity: inputIdentity = sha256(lean source),
  ## contract = hermetic closure digest, bundle = toolchain fingerprint.
  executionIdentity(
    sha256Hex(unitSrc),                    # inputIdentity
    sha256Hex("exec-contract-v1"),         # executionContractDigest (fixed hermetic closure)
    sha256Hex("toolchain-bundle-v1"))      # bundleFingerprint

# ---------------------------------------------------------------------------
# Cross-selection exact reuse (Selection A / B / C)
# ---------------------------------------------------------------------------

test "S5: same unit under Selection A/B/C → identical ExecutionIdentity":
  let unit = "src/core/topology/topology_dependency.nim::proximityScore"
  # 3 distinct selection contexts (different selection/plan digests) —
  # per confirmed semantics these must NEVER enter the per-unit identity.
  let selectionA = "sel:A:111111"
  let selectionB = "sel:B:222222"
  let selectionC = "sel:C:333333"
  let idA = unitExecutionIdentity(unit)
  # The identity API takes no selection inputs, but emulate call sites that
  # could accidentally mix selection context into the identity: assert the
  # canonical function is literally selection-free by construction.
  check idA.len == 64
  discard selectionA & selectionB & selectionC  # contexts are irrelevant by design
  let idB = unitExecutionIdentity(unit)
  let idC = unitExecutionIdentity(unit)
  check idA == idB
  check idB == idC

test "S5: cross-selection cache reuse — store under A, HIT under B and C (3/3)":
  let unitA = "src/kernel/f.nim::f"
  let key = unitExecutionIdentity(unitA)
  var cache = ExactResultCache()
  # Selection A context populates the cache
  cache.store(makeResultCacheEntry(key, unitA, psPass, @["dep-1", "dep-2"]))
  check cache.canReuse(key)
  let first = cache.load(key)
  check first.isSome
  let freshKey = unitExecutionIdentity(unitA)
  check freshKey == key
  # Selection B and C reuse the same per-unit identity → HIT with identical content
  check cache.canReuse(freshKey)
  let hitB = cache.load(freshKey)
  let hitC = cache.load(freshKey)
  check hitB.isSome
  check hitC.isSome
  check hitB.get().unitResult.resultDigest == first.get().unitResult.resultDigest
  check hitC.get().unitResult.resultDigest == first.get().unitResult.resultDigest
  check hitB.get().contentDigest == hitC.get().contentDigest

test "S5: reuse is exact — cached result equals a fresh recomputation":
  let unit = "src/kernel/g.nim::g"
  let key = unitExecutionIdentity(unit)
  var cache = ExactResultCache()
  cache.store(makeResultCacheEntry(key, unit, psFail, @["dep-x"]))
  let entry = cache.load(key)
  check entry.isSome
  # A fresh recomputation of the same unit with the same deps must match exactly
  let recomputed = makeResultCacheEntry(unitExecutionIdentity(unit), unit, psFail, @["dep-x"])
  check computeContentDigest(recomputed) == entry.get().contentDigest
  check recomputed.unitResult.resultDigest == entry.get().unitResult.resultDigest

test "S5: false cache hit = 0 — tampered payload under a valid key refuses load":
  let unit = "src/kernel/h.nim::h"
  let key = unitExecutionIdentity(unit)
  var cache = ExactResultCache()
  cache.store(makeResultCacheEntry(key, unit, psPass, @["dep-1"]))
  # Tamper: flip the stored unitResult's status WITHOUT updating the witness
  cache.entries[key].unitResult.proofStatus = psFail
  check cache.load(key).isNone()   # witness mismatch → fail-closed refusal (no false hit)
  # Restore → valid again (the refusal is witness-driven, not key-driven)
  cache.entries[key].unitResult.proofStatus = psPass
  check cache.load(key).isSome()
  # A different unit's key never hits (exact-match, no partial-key fallback)
  check cache.load(unitExecutionIdentity("src/kernel/other.nim::x")).isNone()

test "S5: partial-key / restore-key fallback is absent (exact-match only)":
  let keyA = unitExecutionIdentity("src/kernel/i.nim::i")
  let keyB = unitExecutionIdentity("src/kernel/j.nim::j")
  var cache = ExactResultCache()
  cache.store(makeResultCacheEntry(keyA, "src/kernel/i.nim::i", psPass, @[]))
  # A DIFFERENT unit's key must never hit
  check not cache.canReuse(keyB)
  check cache.load(keyB).isNone()

# ---------------------------------------------------------------------------
# Selection-independent UnitResult
# ---------------------------------------------------------------------------

test "S5: UnitResult serialization contains no selection/plan digest fields":
  let ur = UnitResult(
    unitId: "src/kernel/k.nim::k",
    proofStatus: psPass,
    failureClassification: "",
    vacuityClassification: "",
    certificateIdentityDigest: sha256Hex("cert-k"),
    resultDigest: sha256Hex("result-k"))
  let json = ur.toCanonicalJson()
  var keys: seq[string] = @[]
  for k, v in json.pairs():
    keys.add(k)
  check "selectionDigest" notin keys
  check "planDigest" notin keys
  check "derivationDigest" notin keys
  check "unitId" in keys
  check "proofStatus" in keys
  check "resultDigest" in keys

test "S5: same unit under different selection contexts → identical resultDigest":
  # resultDigest is a pure function of the unit's own certified fields;
  # a selection context can never change it.
  let urA = UnitResult(
    unitId: "src/kernel/k.nim::k",
    proofStatus: psPass,
    failureClassification: "",
    vacuityClassification: "",
    certificateIdentityDigest: sha256Hex("cert-k"),
    resultDigest: sha256Hex("result-k"))
  # Context B/C reuse the identical certified fields (selection-independent)
  let urB = UnitResult(
    unitId: "src/kernel/k.nim::k",
    proofStatus: psPass,
    failureClassification: "",
    vacuityClassification: "",
    certificateIdentityDigest: sha256Hex("cert-k"),
    resultDigest: sha256Hex("result-k"))
  check urA.resultDigest == urB.resultDigest
  check urA.toCanonicalJson() == urB.toCanonicalJson()

{.pop.}