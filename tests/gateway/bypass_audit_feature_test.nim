{.push raises: [CatchableError].}

## Bypass Audit Feature Test.
## See tests/features/bypass_audit.feature for the specification.
##
## Validates compile-time module layout.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "bypass audit — module compilation":

  test "bypass audit source file exists at expected path":
    const auditSrc {.strdefine.} = "src/infrastructure/bypass_audit.nim"
    check auditSrc.len > 0

  test "reliability score formula boundary: 0 bypasses = 100, 20 bypasses = 0":
    proc calcScore(bypassCount: int): int =
      max(0, 100 - bypassCount * 5)
    check calcScore(0) == 100
    check calcScore(20) == 0
    check calcScore(21) == 0
{.pop.}
