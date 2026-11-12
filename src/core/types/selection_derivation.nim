import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## SelectionDerivation — selector derivation certificate (not affectedness proof).
##
## Follows the DerivationGraph canonicalization pattern from obligation_evidence.nim
## and the InstantiationWitness fail-closed verification pattern from evidence_artifact_io.nim.

import std/[algorithm, json, sequtils, sets, strutils]
import core/types/obligation_evidence

# ---------------------------------------------------------------------------
# SelectionStatus — maps 1:1 to roadmap VALID/FALLBACK_REQUIRED/ERROR
# ---------------------------------------------------------------------------

type
  SelectionStatus* = enum
    ssValid             ## selection is valid; containment self-proven
    ssFallbackRequired  ## containment unproven; V2 full certification needed
    ssError             ## argument or internal error

# ---------------------------------------------------------------------------
# Reason kind for ProofOfSelection / exclusion
# ---------------------------------------------------------------------------

type
  SelectionReasonKind* = enum
    rkDeltaChanged            ## change in diff content
    rkDependencyChanged       ## change in dependency graph
    rkContractChanged         ## change in contract declaration
    rkSpecChanged             ## change in spec declaration
    rkGeneratedArtifactChanged ## change in generated artifact
    rkUniverseChanged         ## change in universe scope

# ---------------------------------------------------------------------------
# ProofOfSelection — per-unit derivation chain
# ---------------------------------------------------------------------------

type
  ProofOfSelection* = object
    unitId*: string
    reasonKind*: SelectionReasonKind
    predecessorChain*: seq[string]  ## derivation chain for replay (NOT an affectedness proof)

# ---------------------------------------------------------------------------
# SelectionInputs — the four semantic input digests
# ---------------------------------------------------------------------------

type
  SelectionInputs* = object
    changeSetDigest*: string
    graphDigest*: string
    universeDigest*: string
    policyDigest*: string

# ---------------------------------------------------------------------------
# SelectionDerivation — the derivation certificate
# ---------------------------------------------------------------------------

type
  SelectionDerivation* = object
    inputDigests*: SelectionInputs
    status*: SelectionStatus
    selected*: seq[ProofOfSelection]
    excluded*: seq[(string, string)]  ## (unitId, reason) pairs
    fallbackReason*: string
    witnessDigest*: string

# ---------------------------------------------------------------------------
# DerivationGraph comes from core/types/obligation_evidence:
# idempotent·commutative·associative union (mergeGraphs/toCanonicalJson).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Canonical serialization of SelectionDerivation
# ---------------------------------------------------------------------------

func toCanonicalJson*(sd: SelectionDerivation): JsonNode {.raises: [].} =
  ## Deterministic JSON — sorted keys, sorted selections, sorted exclusions.
  let sortedSelected = sd.selected.sorted(proc(a, b: ProofOfSelection): int =
    cmp(a.unitId, b.unitId))
  let sortedExcluded = sd.excluded.sorted(proc(a, b: (string, string)): int =
    let c = cmp(a[0], b[0])
    if c != 0: return c
    return cmp(a[1], b[1]))
  let inputs = sd.inputDigests
  %*{
    "changeSetDigest": inputs.changeSetDigest,
    "graphDigest": inputs.graphDigest,
    "universeDigest": inputs.universeDigest,
    "policyDigest": inputs.policyDigest,
    "status": $sd.status,
    "selected": sortedSelected.mapIt(%*{
      "unitId": it.unitId,
      "reasonKind": $it.reasonKind,
      "predecessorChain": it.predecessorChain}),
    "excluded": sortedExcluded.mapIt(%*{
      "unitId": it[0],
      "reason": it[1]}),
    "fallbackReason": sd.fallbackReason}

{.pop.}