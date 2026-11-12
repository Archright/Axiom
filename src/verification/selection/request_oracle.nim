import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## EligibilityOracle — independent required-requests computation
##
## Computes the EXPECTED request set from selection + universe + graph
## facts. This is policy-unaware — it does NOT use deriveRequests or
## any derivation policy. The oracle is CODE-LEVEL independent from
## request_derivation.nim (zero cross-import edges).
##
## See: canonical_execution_semantics.md §Appendix C
## Rule: required comes from the independent oracle, NOT from deriveRequests.

import std/[algorithm, json, sequtils, sets, strutils]
import core/types/request_id
import core/types/request_derivation_types
import core/types/selection_derivation
import core/types/graph_artifact
import core/topology/topology_types
import core/proof/proof_integrity
import verification/selection/selection_digests

# ---------------------------------------------------------------------------
# Independent Oracle — policy-unaware requiredRequests computation
# ---------------------------------------------------------------------------

func computeRequiredRequests*(
  selection: SelectionDerivation
; universe: seq[string]
; graph: GraphArtifact
): seq[RequestId] {.raises: [].} =
  ## Independent oracle: computes the EXPECTED request set from selection +
  ## universe + graph facts. This is policy-unaware — it does NOT use
  ## deriveRequests or any derivation policy.
  ##
  ## Basis: semantic closure of the selection. The oracle reads the
  ## SelectionDerivation's selected units and the graph's unresolved edges
  ## to determine which requests are required.
  ##
  ## This mirrors soundness_oracle's containment basis: the oracle is
  ## implementation-independent from the selector (contract sentence 1).

  var required: seq[RequestId] = @[]
  var seen = initHashSet[string]()

  # All selected units from the derivation are required
  for ps in selection.selected:
    if ps.unitId notin seen:
      seen.incl(ps.unitId)
      required.add(makeRequestId(@[ps.unitId]))

  # Units referenced in exclusions (excluded units still need requests
  # for completeness tracking — they are required but dispositioned)
  for (unitId, _) in selection.excluded:
    if unitId notin seen:
      seen.incl(unitId)
      required.add(makeRequestId(@[unitId]))

  # If the selection status indicates fallback is required, the full
  # universe is required (FALLBACK_REQUIRED means containment unproven)
  if selection.status in [ssFallbackRequired, ssError]:
    for u in universe:
      if u notin seen:
        seen.incl(u)
        required.add(makeRequestId(@[u]))

  # Unresolved edges in the graph expand the required set
  # (unresolved edges mean potential impact that must be verified)
  for edge in graph.unresolvedEdges:
    let key = edge.fromNodeId
    if key notin seen:
      seen.incl(key)
      required.add(makeRequestId(@[key]))

  result = required.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b)))

# ---------------------------------------------------------------------------
# Full-scope independent oracle — kernel-scope aware, verified-subtracted
# ---------------------------------------------------------------------------

func computeRequiredRequestsFull*(
  universe: seq[string]
; analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
; verifiedSet: HashSet[string]
): seq[RequestId] {.raises: [].} =
  ## Independent oracle: computes the EXPECTED request set from the
  ## full universe, applying kernel-scope membership and verified-set
  ## subtraction. INDEPENDENT of SelectionDerivation — does NOT call
  ## any selector outputs.
  ##
  ## Kernel-scope filter: a universe entry is required only when it
  ## is a member of kernelScope.kernelSymbols and is NOT in
  ## kernelScope.kernelExemptSymbols. When kernelSymbols is empty
  ## (lock unavailable/legacy), the filter is skipped (degraded mode).
  ##
  ## Verified subtraction: already-verified nodes (present in
  ## verifiedSet) are excluded — they do not need re-verification.
  ##
  ## Unresolved edges: from-nodes of unresolved edges are always
  ## required regardless of kernel-scope status, because an unresolved
  ## edge represents a potential impact that must be verified.
  ##
  ## Output is sorted deterministically for reproducible oracle
  ## results across runs.

  var required: seq[RequestId] = @[]
  var seen = initHashSet[string]()

  let scopeActive = kernelScope.kernelSymbols.len > 0

  for unitId in universe:
    # Kernel-scope membership filter
    if scopeActive:
      if unitId notin kernelScope.kernelSymbols:
        continue
      if unitId in kernelScope.kernelExemptSymbols:
        continue
    # Verified subtraction
    if unitId in verifiedSet:
      continue
    if unitId notin seen:
      seen.incl(unitId)
      required.add(makeRequestId(@[unitId]))

  # Unresolved edges always expand the required set — but stay within the same
  # admissible kernel scope (an unresolved edge from a non-kernel node must not
  # inflate the closure required-set with unrelated symbols).
  for edge in analysis.unresolvedEdges:
    let key = sorterNodeIdString(edge.fromNodeId)
    if scopeActive and key notin kernelScope.kernelSymbols:
      continue
    if scopeActive and key in kernelScope.kernelExemptSymbols:
      continue
    if key notin seen:
      seen.incl(key)
      required.add(makeRequestId(@[key]))

  result = required.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b)))

# ---------------------------------------------------------------------------
# Provenance oracle — observation-only, mirrors computeRequiredRequestsFull
# ---------------------------------------------------------------------------

type ProvenanceEntry* = tuple[requestId: RequestId, reason: string]

func computeRequiredRequestsWithProvenance*(
  universe: seq[string]
; analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
; verifiedSet: HashSet[string]
): seq[ProvenanceEntry] {.raises: [].} =
  ## Independent oracle: mirrors computeRequiredRequestsFull exactly but
  ## returns per-unit provenance alongside each RequestId.
  ##
  ## Reason taxonomy:
  ##   "kernel-scope member"   — unit passed kernel-scope filter via the
  ##                             universe loop (primary inclusion path).
  ##   "unresolved edge from-node" — unit was added because it is the
  ##                             from-node of an unresolved edge (secondary
  ##                             expansion path; only used when the unit was
  ##                             NOT already in the universe loop result).
  ##   "verified-excluded"     — unit is in verifiedSet and therefore
  ##                             excluded from the result (not in result).
  ##
  ## INDEPENDENT of SelectionDerivation — does NOT call deriveRequests,
  ## computeSelection, or computeRequiredRequests(SelectionDerivation).
  ## Driven purely by (universe, analysis, kernelScope, verifiedSet).

  var provenance: seq[ProvenanceEntry] = @[]
  var seen = initHashSet[string]()

  let scopeActive = kernelScope.kernelSymbols.len > 0

  for unitId in universe:
    if scopeActive:
      if unitId notin kernelScope.kernelSymbols:
        continue
      if unitId in kernelScope.kernelExemptSymbols:
        continue
    if unitId in verifiedSet:
      provenance.add((makeRequestId(@[unitId]), "verified-excluded"))
      continue
    if unitId notin seen:
      seen.incl(unitId)
      provenance.add((makeRequestId(@[unitId]), "kernel-scope member"))

  for edge in analysis.unresolvedEdges:
    let key = sorterNodeIdString(edge.fromNodeId)
    if scopeActive and key notin kernelScope.kernelSymbols:
      continue
    if scopeActive and key in kernelScope.kernelExemptSymbols:
      continue
    if key notin seen:
      seen.incl(key)
      provenance.add((makeRequestId(@[key]), "unresolved edge from-node"))

  result = provenance.sorted(proc(a, b: ProvenanceEntry): int = cmp(string(a.requestId), string(b.requestId)))

{.pop.}