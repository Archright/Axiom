import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Audit Domain Types — SSOT for audit persistence concepts
##
## These types are shared between the Domain layer (src/core/audit/)
## and the Infrastructure layer (src/verification/audit_impl/).
## The Domain layer defines them; the Infrastructure layer implements them.

type
  AuditEntry* = object
    ## A single gate audit record for JSONL persistence.
    gateId*: string
    passed*: bool
    durationMs*: int
    timestamp*: string      ## ISO-8601 format
    metadata*: string       ## JSON-encoded additional data

  HealthLevel* = enum
    hlHealthy    ## Gate operating normally
    hlWarning    ## Occasional failures, within tolerance
    hlDegraded   ## Consistent failures, needs attention
    hlCritical   ## Gate is broken, immediate action required

{.pop}
