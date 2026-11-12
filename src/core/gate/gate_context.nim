{.push raises: [].}
type
  GateResult* = enum
    grPass, grFail, grSkipped

  GateContext* = object
    name*: string
    result*: GateResult
    verified*: bool

proc initGateContext*(name: string): GateContext =
  GateContext(name: name, result: grSkipped, verified: false)

proc pass*(ctx: var GateContext) =
  ctx.result = grPass
  ctx.verified = true

proc fail*(ctx: var GateContext, reason: string = "") =
  ctx.result = grFail
  ctx.verified = true

proc isVerified*(ctx: GateContext): bool =
  ctx.verified

template withGate*(gateName: string, body: untyped): untyped =
  block gateBlock:
    var ctx {.inject.} = initGateContext(gateName)

    body

    if not ctx.isVerified():
      raise newException(ValueError, "Gate '" & gateName & "' did not call pass() or fail()")

    if ctx.result == grPass:
      true
    elif ctx.result == grFail:
      false
    else:
      false
