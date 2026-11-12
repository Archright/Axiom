import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## GraphInterpretationPolicy + GraphArtifact — canonical graph representation
## for the selector. Follows the layered identity pattern from
## candidate_identity.nim and the DerivationGraph canonicalization
## pattern from obligation_evidence.nim.

import std/[algorithm, json, sequtils, strutils]

# ---------------------------------------------------------------------------
# GraphUnresolvedEdge — local pure-data type for leaf module
# ---------------------------------------------------------------------------

type
  GraphUnresolvedEdge* = object
    fromNodeId*: string
    targetName*: string
    modulePath*: string
    resolutionKind*: string

# ---------------------------------------------------------------------------
# GraphInterpretationPolicy
# ---------------------------------------------------------------------------

type
  EdgeSemantic* = enum
    esCall        ## function call edges
    esContract    ## contract dependency edges
    esSpec        ## spec declaration edges

  GraphInterpretationPolicy* = object
    extractionMode*: string        ## "full" / "contract" / "reachability"
    edgeSemantics*: seq[EdgeSemantic]
    builderVersion*: string        ## builder identifier (digest of build_metadata.json)
    unresolvedRetention*: bool     ## true = preserve unresolved edges (required)

# ---------------------------------------------------------------------------
# GraphArtifact
# ---------------------------------------------------------------------------

type
  GraphArtifact* = object
    structureDigest*: string               ## digest of graph structure (nodes+edges+unresolved)
    constructionInputsDigest*: string      ## digest of the inputs used to build this graph
    interpretationPolicyDigest*: string    ## digest of the policy applied
    unresolvedEdges*: seq[GraphUnresolvedEdge]
    builderVersion*: string                ## builder version string (e.g. "2")

func toCanonicalJson*(ga: GraphArtifact): JsonNode {.raises: [].} =
  let sortedEdges = ga.unresolvedEdges.mapIt(
    it.fromNodeId & "|" & it.targetName & "|" & it.modulePath & "|" & $it.resolutionKind
  ).sorted(cmp)
  %*{
    "structureDigest": ga.structureDigest,
    "constructionInputsDigest": ga.constructionInputsDigest,
    "interpretationPolicyDigest": ga.interpretationPolicyDigest,
    "unresolvedEdges": sortedEdges,
    "builderVersion": ga.builderVersion}

{.pop.}