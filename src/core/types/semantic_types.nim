import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Pure Semantic Graph Types
## Extracted from semantic_graph.nim to prevent Domain→Infrastructure
## reverse references during module relocation.

import std/tables

type
  SemanticNodeStatus* = enum
    snsVerified
    snsPending
    snsPendingByDependency
    snsInvalid
    snsRisk
    snsExternalRisk
    snsUnknown

  SemanticGraphNode* = object
    name*: string
    modulePath*: string
    qualifiedName*: string
    status*: SemanticNodeStatus
    certificateHash*: string
    irFingerprint*: string
    ancestors*: seq[string]
    descendants*: seq[string]
    depth*: int
    impactIndex*: float
    invalidDescendantsCount*: int
    isExternal*: bool
    externalSource*: string
    externalVersion*: string

  SccGroup* = object
    id*: int
    members*: seq[string]
    status*: SemanticNodeStatus

  SemanticGraph* = object
    nodes*: Table[string, SemanticGraphNode]
    sccGroups*: seq[SccGroup]
    rootDir*: string
    graphGeneratedAt*: int64
    sourceLastModifiedAt*: int64
    totalNodes*: int
    verifiedNodes*: int
    pendingNodes*: int
    invalidNodes*: int
    riskNodes*: int
    externalNodes*: int

{.pop.}

{.pop.}
