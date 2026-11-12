## Canonical projection of the verification state (SSOT) for replay equality.
##
## Implements `canonicalProjectionHash = SHA-256(sorted included-fields JSON)`
## from docs/spec/productization_contract.md ("canonical projection"). This is
## THE single canonicalization implementation — CLI surfaces call this proc and
## must not re-derive volatile-field lists.
##
## Volatile keys (removed wherever they appear in the tree) are timing/runtime
## observation fields separated from the canonical payload per the R7
## determinism pattern (wf_render.nim); see productization_contract.md for the
## authoritative list. They additionally cover path/location identity
## (vaultPath, subjectRoot, …) and cache-state observation (cacheHit): the same
## logical subject re-verified at a different physical root must project to the
## same hash (R3 `pathIndependentProjectionEqual`), so the projection must not
## observe where the input physically lives or whether this run reused a cache.

import std/json
import std/algorithm
import std/strutils
import core/crypto/hash_kernel

const volatileKeys* = [
  "timestamp",
  "startedAtMs", "endedAtMs", "elapsedMs", "solverElapsedMs",
  "parallelOverheadMs", "activeNodeCount", "availableMemoryBytes",
  "cpuLoadRatio", "recommendedWorkerCount",
  "totalWallTimeMs", "hotspotElapsedMs", "hotspotLabel",
  # Run identity — machine/run-scoped, excluded per productization_contract.md §6.
  "runId", "generatedAt", "processId",
  # Wall-clock timeout family — hang-guard outcomes.  A wall-clock expiry is a
  # run abort, never a verification verdict, so it must not move the canonical
  # hash; otherwise identical input on a slower machine hashes differently.
  "timedOut", "timeout", "timeoutCount", "timeoutNodes", "timeoutImpactNodes",
  "timeoutHotspots", "timeoutComplexityWeight", "wallElapsedMs",
  # Path & location identity — relocation keys (productization_contract.md §6
  # exclusion "tmp path, absolutePath").  vaultPath is joinPath(vaultDir, …)
  # (src/core/orchestrator/orchestrator_vault.nim:175) and is therefore
  # state-root dependent: the same logical input re-verified at a different
  # physical root (different AXIOM_STATE_DIR / subject checkout) must produce
  # the same canonical hash (R3 pathIndependentProjectionEqual), so any
  # path-valued field would make the digest a function of where the input
  # happens to live rather than what the input means.
  "vaultPath", "tmpPath", "absolutePath", "path", "sourcePath",
  "subjectRoot", "stateRoot", "repoRoot",
  # Cache-state observation — cacheHit/cacheHitCount record whether this run
  # reused a previous proof, not what the verification decided.  They flip at a
  # cold/warm boundary for identical logical input, so keeping them would make
  # the canonical hash a function of cache state instead of logical identity;
  # cacheHitCount is already in the §6 exclusion table ("실행·성능 telemetry").
  "cacheHit", "cacheHitCount",
  # Per-node evidence log — a run-scoped telemetry blob (§6 excluded "solver
  # 내부 trace"): it duplicates outcome fields already carried by status/tier
  # and may embed run-local paths, so it is not part of logical identity.
  "evidenceLogJson",
  # Selection heuristics — verificationQueue topologyScore/complexityScore
  # are byte-derived structural metrics (a trailing comment moves them
  # 24→23), so keeping them would make the canonical hash a function of raw
  # bytes instead of what the input means — a violation of §6's own
  # semantic-equality principle ("semantic equality 정의 — raw artifact byte
  # equality 아님"). §6 동기화 (2026-10-15, 선택 휴리스틱 배제): state fields
  # remain; excluded from the projection only. Discovered when the R3 slice's
  # wp5 sensitivity gate (comment-only must-not-flip) executed for the first
  # time.
  "topologyScore", "complexityScore",
]

func isVolatileKey*(k: string): bool {.raises: [].} =
  for vk in volatileKeys:
    if k == vk:
      return true
  return false

func stripVolatile*(n: JsonNode): JsonNode {.raises: [].} =
  ## Deep copy of `n` with every volatile-keyed member removed recursively.
  case n.kind
  of JObject:
    result = newJObject()
    for k, v in n.pairs:
      if k == "runtimeMeta":
        continue # timing envelope, never part of the canonical payload
      if isVolatileKey(k):
        continue
      result[k] = stripVolatile(v)
  of JArray:
    result = newJArray()
    for v in n.items:
      result.add(stripVolatile(v))
  else:
    result = n.copy()

func sortedCanonicalJson*(n: JsonNode): string {.raises: [].} =
  ## Deterministic serializer: object members emitted in sorted key order.
  ## Exported for consumers that must fingerprint RAW documents (e.g. the §6c
  ## skReport comparison record's payloadDigest) without re-deriving a
  ## canonical form — this module remains THE single canonicalization
  ## implementation.
  case n.kind
  of JObject:
    var pairs: seq[tuple[k: string, v: JsonNode]]
    for k, v in n.pairs:
      pairs.add((k, v))
    pairs.sort(proc(a, b: auto): int = cmp(a.k, b.k))
    var parts: seq[string]
    for p in pairs:
      parts.add("\"" & p.k & "\":" & sortedCanonicalJson(p.v))
    "{" & parts.join(",") & "}"
  of JArray:
    var parts: seq[string]
    for v in n.items:
      parts.add(sortedCanonicalJson(v))
    "[" & parts.join(",") & "]"
  of JString:
    # std/json's $ already escapes per JSON rules.
    $n
  else:
    $n

func canonicalProjectionHash*(state: JsonNode): string {.raises: [].} =
  ## SHA-256 over the sorted, volatility-stripped JSON of the SSOT state.
  sha256Hex(sortedCanonicalJson(stripVolatile(state)))

func identityBindingDigest*(sidecar: JsonNode): string {.raises: [].} =
  ## THE §6c v2 production-binding digest: sha256 over the canonical sidecar
  ## document with its `binding` section removed — i.e. over exactly the
  ## {schemaVersion, identity} material the identity axis compares. The lane
  ## embeds this digest in the payload (`identityBundleDigest`) and the
  ## comparison recomputes it from the sidecar: a single definition, both
  ## directions mechanically re-checkable, nothing here trusts the caller.
  ## Lives in the canonical-form module (not the comparator) so the lane
  ## reaches it without importing the comparison surface.
  if sidecar.isNil or sidecar.kind != JObject:
    return ""
  var coreDoc = newJObject()
  for k, v in sidecar.pairs:
    if k != "binding":
      coreDoc[k] = v.copy()
  sha256Hex(sortedCanonicalJson(coreDoc))
