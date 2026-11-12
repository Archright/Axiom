import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Canonical SorterNodeId type — SSOT for sorter node identifiers.

type
  SorterNodeId* = distinct string

{.pop.}
{.pop.}
