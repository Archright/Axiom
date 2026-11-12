import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical ForbiddenPragmaPattern type — SSOT for pragma-based SoC enforcement.
##
## Imported by core/policy/architecture_policy_types and consumers.

type
  ForbiddenPragmaPattern* = object
    pragmaName*: string
    callerPattern*: string
    allowedCallers*: seq[string]

{.pop.}
