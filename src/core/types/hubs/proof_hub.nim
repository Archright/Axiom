import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical proof discontinuity kinds — SSOT for proof discontinuity taxonomy.

type
  DiscontinuityKind* = enum
    dkNonLinearArithmetic = 0
    dkUnboundedRecursion = 1
    dkMissingInvariant = 2
    dkExternalSideEffect = 3
    dkPointerAliasing = 4
    dkConcurrencyRace = 5

{.pop.}
