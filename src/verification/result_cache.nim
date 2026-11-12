# result_cache.nim — S4 minimal exact-reuse cache
#
# Stores per-unit verification results keyed by executionIdentity
# (the canonical per-unit formula from identity.nim:212-217).
# Cross-selection reuse is allowed by design: the key is the per-unit
# execution identity, which is selection-independent.
#
# Fail-closed guards:
#   (1) dependencyDigests empty → reuse FORBIDDEN (S4 precondition:
#       dependencyDigests 미충족 reuse 금지)
#   (2) exact-match only — no restore-key/partial-key fallback
#   (3) content digest mismatch on load → refusal (InstantiationWitness
#       pattern from evidence_artifact_io.nim:114-212)
#
# Pure logic where possible; file I/O at the boundary via
# serialize/deserialize pairs (test-only persistence).

import core/trusted/layer_declaration
axiomLayer "verification"
import core/trusted/axiom_pragmas
{.push raises: [].}

import std/[tables, json, sequtils, strutils, options, algorithm]
import core/crypto/hash_kernel
import core/types/result_identity
import engine/proof_certificate
import infrastructure/cas_index
import verification/obligation/identity

# ---------------------------------------------------------------------------
# Cache entry — carries result + dependency context + integrity witness
# ---------------------------------------------------------------------------

type
  ResultCacheEntry* = object
    executionIdentity*: string     ## per-unit canonical identity key
    unitResult*: UnitResult        ## the verified unit result
    dependencyDigests*: seq[string] ## dependency digests at computation time
    contentDigest*: string         ## SHA-256 of serialized content (witness)

# ---------------------------------------------------------------------------
# Content digest computation — witness integrity
# ---------------------------------------------------------------------------

func computeContentDigest*(entry: ResultCacheEntry): string {.raises: [].} =
  ## Recompute the content digest from the entry's data fields.
  ## Excludes contentDigest itself — tampering with any field
  ## (including contentDigest) is detected.
  ## Mirrors the InstantiationWitness pattern in evidence_artifact_io.nim:134-141
  ## where computeWitnessDigest recomputes from loaded witnesses and
  ## compares with the stored value; mismatch → none (fail-closed).
  let serialized = entry.unitResult.unitId &
    $entry.unitResult.proofStatus &
    entry.unitResult.failureClassification &
    entry.unitResult.vacuityClassification &
    entry.unitResult.certificateIdentityDigest &
    entry.unitResult.resultDigest &
    sorted(entry.dependencyDigests).join("|")
  sha256Hex(serialized)

# ---------------------------------------------------------------------------
# ExactResultCache — in-memory exact-match cache
# ---------------------------------------------------------------------------

type
  ExactResultCache* = object
    ## Minimal exact-reuse cache keyed by per-unit executionIdentity.
    ## NO restore-key/partial-key fallback — GitHub-Actions-style
    ## approximate reuse is explicitly excluded by the S4 roadmap.
    entries*: Table[string, ResultCacheEntry]

# ---------------------------------------------------------------------------
# Store — exact-match insertion
# ---------------------------------------------------------------------------

func store*(cache: var ExactResultCache; entry: ResultCacheEntry) {.raises: [].} =
  ## Store a cache entry keyed by executionIdentity.
  ## The entry's contentDigest is computed and stored.
  ## Exact-match only: if an entry with the same key already exists,
  ## it is replaced (deterministic overwrite, not merge).
  var e = entry
  e.contentDigest = e.computeContentDigest
  cache.entries[e.executionIdentity] = e

# ---------------------------------------------------------------------------
# CanReuse — fail-closed guard: dependencyDigests must be non-empty
# ---------------------------------------------------------------------------

func canReuse*(cache: ExactResultCache; executionIdentity: string): bool {.raises: [].} =
  ## Check whether a reusable entry exists for the given identity.
  ## Fail-closed: returns false when:
  ##   (1) no entry exists for the key
  ##   (2) the entry's dependencyDigests is empty (S4 precondition:
  ##       dependencyDigests 미충족 reuse 금지)
  ## Exact-match only — no restore-key/partial-key fallback.
  let entry = cache.entries.getOrDefault(executionIdentity)
  if entry.executionIdentity.len == 0:
    return false
  if entry.dependencyDigests.len == 0:
    return false
  true

# ---------------------------------------------------------------------------
# Load — fail-closed with witness integrity verification
# ---------------------------------------------------------------------------

func load*(cache: ExactResultCache; executionIdentity: string): Option[ResultCacheEntry] {.axiomDecision, raises: [].} =
  ## Load a cache entry by exact executionIdentity match.
  ## Fail-closed: returns none when:
  ##   (1) no entry exists for the key
  ##   (2) dependencyDigests is empty (S4 precondition)
  ##   (3) contentDigest mismatch (tampered payload — witness integrity
  ##       failure, following the InstantiationWitness pattern in
  ##       evidence_artifact_io.nim:163-212 where loadInstantiationWitnesses
  ##       recomputes witnessDigest and returns none on mismatch)
  let entry = cache.entries.getOrDefault(executionIdentity)
  if entry.executionIdentity.len == 0:
    return none(ResultCacheEntry)
  if entry.dependencyDigests.len == 0:
    return none(ResultCacheEntry)
  let computed = entry.computeContentDigest
  if computed != entry.contentDigest:
    return none(ResultCacheEntry)
  some(entry)

# ---------------------------------------------------------------------------
# Serialize / Deserialize — persistence pair (pure logic, JSON-based)
# ---------------------------------------------------------------------------

func serializeEntry*(entry: ResultCacheEntry): JsonNode {.raises: [].} =
  ## Serialize a ResultCacheEntry to a JSON object for persistence.
  %*{
    "executionIdentity": entry.executionIdentity,
    "unitResult": %*{
      "unitId": entry.unitResult.unitId,
      "proofStatus": $entry.unitResult.proofStatus,
      "failureClassification": entry.unitResult.failureClassification,
      "vacuityClassification": entry.unitResult.vacuityClassification,
      "certificateIdentityDigest": entry.unitResult.certificateIdentityDigest,
      "resultDigest": entry.unitResult.resultDigest},
    "dependencyDigests": entry.dependencyDigests,
    "contentDigest": entry.contentDigest}

func deserializeEntry*(node: JsonNode): Option[ResultCacheEntry] {.axiomDecision, raises: [].} =
  ## Deserialize a JSON node to a ResultCacheEntry.
  ## Returns none if the node is malformed or missing required fields.
  try:
    if node.kind != JObject:
      return none(ResultCacheEntry)
    let execId = node{"executionIdentity"}.getStr("")
    if execId.len == 0:
      return none(ResultCacheEntry)
    let urNode = node{"unitResult"}
    if urNode.kind != JObject:
      return none(ResultCacheEntry)
    let unitResult = UnitResult(
      unitId: urNode{"unitId"}.getStr(""),
      proofStatus: parseEnum[ProofStatus](urNode{"proofStatus"}.getStr("")),
      failureClassification: urNode{"failureClassification"}.getStr(""),
      vacuityClassification: urNode{"vacuityClassification"}.getStr(""),
      certificateIdentityDigest: urNode{"certificateIdentityDigest"}.getStr(""),
      resultDigest: urNode{"resultDigest"}.getStr(""))
    let depsNode = node{"dependencyDigests"}
    var deps: seq[string]
    if depsNode.kind == JArray:
      for elem in depsNode:
        deps.add(elem.getStr(""))
    let contentDigest = node{"contentDigest"}.getStr("")
    some(ResultCacheEntry(
      executionIdentity: execId,
      unitResult: unitResult,
      dependencyDigests: deps,
      contentDigest: contentDigest))
  except CatchableError:
    return none(ResultCacheEntry)

# ---------------------------------------------------------------------------
# Determinism helper — key is the executionIdentity itself
# ---------------------------------------------------------------------------

func deterministicKey*(inputIdentity, contractDigest, bundleFingerprint: string): string {.raises: [].} =
  ## Compute the cache key deterministically from the same inputs
  ## as executionIdentity. This mirrors identity.nim:212-217.
  executionIdentity(inputIdentity, contractDigest, bundleFingerprint)

{.pop.}