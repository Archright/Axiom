import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical effect kinds — SSOT for Axiom IR effect constraints.

type
  EffectKind* = enum
    effPure
    effNoSideEffect
    effIO
    effNetwork
    effFileSystem
    effUnknown

{.pop.}
