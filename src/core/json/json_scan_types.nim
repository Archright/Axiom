import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Json Scan Types.
## Shared types for the JSON raw-string scanner family.

type
  JsonValueLookup* = object
    found*: bool
    start*: int
    stop*: int

{.pop.}
