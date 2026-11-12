import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import core/trusted/axiom_pragmas
import core/trusted/verification_model_types
import core/trusted/private/identity_core

## C19 — Canonical/Encoding Identity Layer.
##
## Types for the canonical encoding of semantic transitions into CHC
## relation identities. These are structurally separate from the semantic
## layer; canonical identity captures encoding-specific metadata only.

type
  StateSignature* {.axiomDecision(
    id = "DECISION-0602",
    reason = "State signature with parameter names and sorts for canonical encoding",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    paramNames*: seq[string]
    paramSorts*: seq[string]

  RelationIdentity* {.axiomDecision(
    id = "DECISION-0603",
    reason = "Encoding-only identity: relation id and state signature; backend field removed (BackendId dead per C19)",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    relationId*: RelationId
    stateSignature*: StateSignature

  CanonicalIdentity* {.axiomDecision(
    id = "DECISION-0604",
    reason = "Top-level canonical identity wrapping a single RelationIdentity",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    relation*: RelationIdentity

{.pop.}