import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Session Types
## Response types shared across axiom_api_session sub-modules.
## Extracted from axiom_api_session.nim to enable proper import-based module structure.

import core/session/session_parser

type
  CaptureSessionResponse* = object
    stored*: bool
    sessionId*: string

  GenerateProofResponse* = object
    proof*: SessionProofArtifact

  InspectTraceResponse* = object
    traceUrl*: string
    traceRef*: string
    vulnerabilityKind*: string
    violatedProperty*: string
    branchPoints*: seq[string]
    pathSignature*: string
    counterExampleSummary*: string
    evolutionReasoning*: string

  ExportProofResponse* = object
    url*: string

  NimLeanBridgeResponse* = object
    bridgeId*: string
    ruleText*: string
    invariantText*: string
    theoremName*: string
    transitionOperator*: string
    delta*: int
    invariantKind*: string
    invariantValue*: int
    leanNamespace*: string
    leanInvariantExpr*: string
    leanTransitionExpr*: string
    leanTheoremExpr*: string

{.pop.}
