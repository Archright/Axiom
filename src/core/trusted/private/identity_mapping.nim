import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import core/trusted/axiom_pragmas
import core/trusted/verification_model_types
import core/trusted/private/identity_core

## C14 — Semantic-to-Canonical Identity Mapping.
##
## Bidirectional map between semantic NodeId and canonical RelationId.
## Identity is deterministic and explicit; never guessed from relation-name strings.
## lookupNode and lookupRelation are DEAD (zero real consumers) and have been removed.

type
  SemanticToCanonicalMap* {.axiomDecision(
    id = "DECISION-0607",
    reason = "Bidirectional map between semantic NodeId and canonical RelationId (C14 explicit identity)",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    nodeToRelation*: seq[tuple[node: NodeId, relation: RelationId]]
    relationToNode*: seq[tuple[relation: RelationId, node: NodeId]]

func setNodeMapping*(m: var SemanticToCanonicalMap; node: NodeId; relation: RelationId) {.axiomDecision(
      id = "DECISION-0608",
      reason = "Record deterministic bidirectional NodeId <-> RelationId mapping (C14 explicit identity); typed RelationId key per C19",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v37"), raises: [].} =
  m.nodeToRelation.add((node, relation))
  m.relationToNode.add((relation, node))

{.pop.}