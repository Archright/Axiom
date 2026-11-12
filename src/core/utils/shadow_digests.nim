## Shadow Digests — 6-dimension canonical fingerprint for replay equality.
##
## Pure functions that compute deterministic SHA-256 digests over
## verification artifacts. Used by the shadow harness to compare
## execution results across different CWDs / paths / stateRoots.
##
## No proof execution is required; proof-dependent dimensions
## (obligation, solver, verified-set) consume pre-computed
## artifact strings produced by a prior proof run.

import std/[algorithm, sequtils, strutils]
import std/json
import core/crypto/hash_kernel
import core/utils/canonical_projection
import core/topology/topology_types
import core/topology/verified_set
import core/trusted/solver_invocation

# ── 1. Canonical projection digest ──────────────────────────────────

func projectionDigest*(proofStateJson: JsonNode): string {.raises: [].} =
  ## Reuse the existing canonicalProjectionHash — volatility stripping
  ## and key sorting are already handled there.
  canonicalProjectionHash(proofStateJson)

# ── 2. Planned queue digest ─────────────────────────────────────────

func plannedQueueDigest*(analysis: TopologyAnalysis): string {.raises: [].} =
  ## Sort verificationQueue by sorterNodeIdString, join with separator,
  ## and SHA-256 the result.
  var ids: seq[string]
  for nid in analysis.verificationQueue:
    ids.add(sorterNodeIdString(nid))
  ids.sort()
  sha256Hex(ids.join("|"))

# ── 3. Dependency-graph digest ──────────────────────────────────────

func dependencyGraphDigest*(analysis: TopologyAnalysis): string {.raises: [].} =
  ## For each SorterNode in state.nodes, produce a canonical
  ## "(nodeId|dep1,dep2,...)" string, sort all such strings,
  ## join with separator, and SHA-256.
  ## Unresolved/ambiguous edges are also included as
  ## "(fromNodeId|targetName|modulePath|resolutionKind)" entries
  ## so that a change in the unresolved set changes the digest.
  var entries: seq[string]
  for node in analysis.state.nodes:
    let nodeStr = sorterNodeIdString(node.id)
    var deps: seq[string]
    for dep in node.dependencyIds:
      deps.add(sorterNodeIdString(dep))
    deps.sort()
    entries.add(nodeStr & "|" & deps.join(","))
  for edge in analysis.unresolvedEdges:
    entries.add(sorterNodeIdString(edge.fromNodeId) & "|" &
                edge.targetName & "|" &
                edge.modulePath & "|" &
                $edge.resolutionKind)
  entries.sort()
  sha256Hex(entries.join(";"))

# ── 4. Obligation-list digest ───────────────────────────────────────

func obligationListDigest*(obligationIds: seq[string]): string {.raises: [].} =
  ## Sort obligation IDs, join, and SHA-256.
  var sorted = obligationIds
  sorted.sort()
  sha256Hex(sorted.join("|"))

# ── 5. Solver-run digest ────────────────────────────────────────────

func solverRunDigest*(replayKeys: seq[string]): string {.raises: [].} =
  ## Sort replay keys, join, and SHA-256.
  var sorted = replayKeys
  sorted.sort()
  sha256Hex(sorted.join("|"))

# ── 6. Verified-set digest ──────────────────────────────────────────
##
## VerifiedSet stores NodeId handles (distinct uint32) as a bitset
## (seq[uint64]).  The module does NOT export a helper to resolve
## bit positions back to sorterNodeId strings (that requires the
## InternPoolSnapshot which is not available in a pure func).
##
## Fallback: serialize the backing bitset words in their natural
## order (word index = bit position group) as a canonical string
## and SHA-256 that.  This is deterministic and preserves the
## bitset semantics without mutating VerifiedSet.

func verifiedSetBitsDigest*(words: seq[uint64]): string {.raises: [].} =
  ## Serialize the raw bitset words in order, join with separator, SHA-256.
  ## This is the shared primitive; verifiedSetDigest derives from it so the
  ## shadow harness can digest a JSON-parsed word list without reaching into
  ## VerifiedSet's private `bits` field.
  if words.len == 0:
    return sha256Hex("")
  var parts: seq[string]
  for w in words:
    parts.add($w)
  sha256Hex(parts.join("|"))

func verifiedSetDigest*(verified: VerifiedSet): string {.raises: [].} =
  ## Serialize the bitset words in order, join with separator, SHA-256.
  verifiedSetBitsDigest(verified.digestBits())

# ── 7. Six-dimension fingerprint ────────────────────────────────────

func sixDimensionFingerprint*(
  projection: string; planned: string; dependencyGraph: string;
  obligationList: string; solverRun: string; verifiedSet: string
): string {.raises: [].} =
  ## Sort the six digest strings, join with separator, and SHA-256.
  var dims = @[projection, planned, dependencyGraph,
               obligationList, solverRun, verifiedSet]
  dims.sort()
  sha256Hex(dims.join("|"))
