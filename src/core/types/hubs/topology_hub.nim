import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Canonical topology violation types — SSOT for lock/suggest audits.

type
  ViolationKind* = enum
    vkMissing, vkOrphan, vkTransitionalExpired, vkOversized, vkSingleton,
    vkEmptyDir, vkUnknown

  Violation* = object
    kind*: ViolationKind
    moduleId*: string
    path*: string
    message*: string

{.pop.}
{.pop.}
