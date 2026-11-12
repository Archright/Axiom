import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Gateway Spec — Pure type layer for gateway generation.
## Zero dependencies. All fields are primitive types (string, bool, seq)
## to ensure compile-time literal conversion via newLit.
##
## AGENTS.md §0.2 First-Principles: primitive-only fields prevent
## newLit failures on nested custom ADTs.

type
  GatewayEndpoint* = object
    typeName*: string
    predicate*: string      ## Name of the validation predicate proc
    errValue*: string       ## Name of the AxiomError enum value
    requires*: string       ## Extra requirement expression as string; empty = none

  EnumMapping* = object
    raw*: string
    enumVal*: string

  GatewayEnumSpec* = object
    typeName*: string
    mappings*: seq[EnumMapping]

{.pop.}
