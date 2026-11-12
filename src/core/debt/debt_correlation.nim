## src/core/debt/debt_correlation.nim — Layer-3 provenance correlation.
##
## Pure correlation primitives over the Provenance DAG:
##   - structArtifactIdentity  : three-level identity construction
##   - linkExecutionToArtifact : execution→proof-artifact chain detection
##   - findBrokenChains        : provenance-gap detection
##   - declaredVsExecuted      : set-difference gap report

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[options, sets, strutils]
import core/types/debt_types
import core/debt/debt_provenance

{.push raises: [].}

# ---------------------------------------------------------------------------
# 1. structArtifactIdentity — three-level identity separation (禁止 #3)
# ---------------------------------------------------------------------------

func structArtifactIdentity*(verificationId: LineageId;
                             toolchain, config, inputs, params: string): ProofArtifactIdentity =
  ## Build a `ProofArtifactIdentity` with three distinct identities:
  ##   artifactId    = sha256Ref("proof-artifact:", ...)  — content identity
  ##   executionId   = newExecutionId(...)                — execution identity
  ##   verificationId = given LineageId                   — lineage identity
  ##
  ## Each field is computed independently so no hash serves double duty.
  let contentPayload = toolchain & "\x1e" & config & "\x1e" & inputs & "\x1e" & params
  result.artifactId = ContentDigest(sha256Ref("proof-artifact:", contentPayload))
  result.executionId = newExecutionId("", toolchain, config, inputs, params)
  result.verificationId = verificationId

# ---------------------------------------------------------------------------
# 2. linkExecutionToArtifact — chain-presence helper
# ---------------------------------------------------------------------------

type ChainStatus* {.pure.} = enum
  csComplete       ## full chain present
  csMissingEdge    ## one or more edges absent
  csOrphanNode     ## node reachable but not linked to any terminal

func linkExecutionToArtifact*(edges: seq[ProvenanceEdge]): ChainStatus =
  ## Given a sequence of provenance edges, determine whether the canonical
  ## Execution →(peProves)→ ProofArtifact →(pePromotedBy)→ Certificate/Promotion
  ## chain is complete.
  ##
  ## Returns csComplete only when BOTH peProves and pePromotedBy are present
  ## in the edge set. Otherwise returns csMissingEdge.
  var hasProves = false
  var hasPromotedBy = false
  for e in edges:
    if e.edgeKind == peProves: hasProves = true
    elif e.edgeKind == pePromotedBy: hasPromotedBy = true
  if hasProves and hasPromotedBy:
    csComplete
  else:
    csMissingEdge

# ---------------------------------------------------------------------------
# 3. findBrokenChains — provenance-gap detection
# ---------------------------------------------------------------------------

type BrokenChain* = object
  subject*: string           ## canonical subject of the broken link
  missingEdge*: ProvenanceEdgeKind
  fromNode*: string          ## node that should have the outgoing edge
  expectedToKind*: ProvenanceNodeKind
  integrityPattern*: string  ## human-readable description

func findBrokenChains*(graph: ProvenanceGraph; expectedTier: string): seq[BrokenChain] =
  ## Detect provenance gaps in the graph. For each node that SHOULD have an
  ## outgoing edge to a canonical/promotion terminal but does NOT, return a
  ## `BrokenChain` describing the gap.
  ##
  ## The `expectedTier` parameter selects which integrity pattern to enforce:
  ##   "execution"  — every pnkObservation must have peProves → pnkArtifact
  ##   "proof"      — every pnkArtifact must have pePromotedBy → promotion
  ##   "full"       — both checks above
  ##
  ## Absence is reported only when the source node is reachable (exists in the
  ## graph) and the expected outgoing edge is missing. This captures the
  ## "declared gate ≠ executed gate / certificate ≠ underlying proof /
  ## canonical vs promoted" Layer-3 correlation failure mode.
  case expectedTier.strip().toLowerAscii()
  of "execution":
    for node in graph.nodes:
      if node.kind != pnkObservation: continue
      # Check: does this observation node have an outgoing peProves edge?
      var hasProves = false
      for e in graph.edges:
        if e.fromNode == node.nodeId and e.edgeKind == peProves:
          hasProves = true
          break
      if not hasProves:
        result.add(BrokenChain(
          subject: node.payloadRef,
          missingEdge: peProves,
          fromNode: node.nodeId,
          expectedToKind: pnkArtifact,
          integrityPattern: "observation without proof link"
        ))
  of "proof":
    for node in graph.nodes:
      if node.kind != pnkArtifact: continue
      # Check: does this artifact node have an outgoing pePromotedBy edge?
      var hasPromotedBy = false
      for e in graph.edges:
        if e.fromNode == node.nodeId and e.edgeKind == pePromotedBy:
          hasPromotedBy = true
          break
      if not hasPromotedBy:
        result.add(BrokenChain(
          subject: node.payloadRef,
          missingEdge: pePromotedBy,
          fromNode: node.nodeId,
          expectedToKind: pnkRepositorySnapshot,
          integrityPattern: "artifact without promotion link"
        ))
  of "full", "":
    # Run both checks
    for node in graph.nodes:
      if node.kind != pnkObservation: continue
      var hasProves = false
      for e in graph.edges:
        if e.fromNode == node.nodeId and e.edgeKind == peProves:
          hasProves = true
          break
      if not hasProves:
        result.add(BrokenChain(
          subject: node.payloadRef,
          missingEdge: peProves,
          fromNode: node.nodeId,
          expectedToKind: pnkArtifact,
          integrityPattern: "observation without proof link"
        ))
    for node in graph.nodes:
      if node.kind != pnkArtifact: continue
      var hasPromotedBy = false
      for e in graph.edges:
        if e.fromNode == node.nodeId and e.edgeKind == pePromotedBy:
          hasPromotedBy = true
          break
      if not hasPromotedBy:
        result.add(BrokenChain(
          subject: node.payloadRef,
          missingEdge: pePromotedBy,
          fromNode: node.nodeId,
          expectedToKind: pnkRepositorySnapshot,
          integrityPattern: "artifact without promotion link"
        ))
  else:
    discard  # unknown tier → no-op

# ---------------------------------------------------------------------------
# 4. declaredVsExecuted — set difference gap report
# ---------------------------------------------------------------------------

func declaredVsExecuted*(declared: openArray[string]; executed: openArray[string]): seq[string] =
  ## Set difference: items in `declared` but NOT in `executed`.
  ## These represent correlation gaps — gates declared in topology but never
  ## actually executed.
  var executedSet: HashSet[string] = initHashSet[string]()
  for item in executed:
    executedSet.incl(item)
  for item in declared:
    if item notin executedSet:
      result.add(item)

# ---------------------------------------------------------------------------
# 5. metric correlation — SKIPPED per scope constraint
# ---------------------------------------------------------------------------

{.pop.}
