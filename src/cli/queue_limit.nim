import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary

type
  VerificationBound* = enum
    vbUnlimited
    vbCapped

  QueueLimit* = object
    case kind*: VerificationBound
    of vbCapped:
      capValue*: Positive ## range[1..high(int)] — 0 is compile-time/runtime rejected
    of vbUnlimited:
      discard

func unlimited*(): QueueLimit =
  QueueLimit(kind: vbUnlimited)

func capped*(n: Positive): QueueLimit =
  QueueLimit(kind: vbCapped, capValue: n)

func resolve*(limit: QueueLimit; default: Positive = 200): Positive =
  ## Resolve to a concrete positive integer. Never returns 0.
  case limit.kind
  of vbUnlimited: default
  of vbCapped: limit.capValue

func isUnlimited*(limit: QueueLimit): bool =
  limit.kind == vbUnlimited

func `$`*(limit: QueueLimit): string =
  case limit.kind
  of vbUnlimited: "unlimited"
  of vbCapped: "capped(" & $limit.capValue & ")"

{.pop.}

