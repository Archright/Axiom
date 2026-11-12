## decision_types.nim - Decision node types for Decision Knowledge Graph
## See: docs/spec/decision_binding_framework.md

type
  DecisionCategory* {.pure.} = enum
    dcArchitecture = "architecture"
    dcSafety = "safety"
    dcPerformance = "performance"
    dcQuirk = "quirk"
    dcLegacy = "legacy"

  DecisionStatus* {.pure.} = enum
    dsProposed = "proposed"
    dsAccepted = "accepted"
    dsDeprecated = "deprecated"
    dsSuperseded = "superseded"

  DecisionNode* = object
    id*: string
    category*: DecisionCategory
    title*: string
    rationale*: string
    files*: seq[string]
    dependsOn*: seq[string]
    status*: DecisionStatus
    date*: string

  DecisionGraph* = object
    version*: int
    generatedAt*: string
    nodes*: seq[DecisionNode]
