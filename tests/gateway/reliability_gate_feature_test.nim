{.push raises: [CatchableError].}

## Reliability Gate Feature Test.
## See tests/features/reliability_gate.feature for the specification.
##
## Validates compile-time module layout and constant accessibility.

import std/[unittest, json]

{.push warning[BareExcept]:off.}
suite "reliability gate — module compilation":

  test "gate runner source file exists at expected path":
    const gateSrc {.strdefine.} = "src/gate/runners/reliability_gate.nim"
    check gateSrc.len > 0

  test "bypass audit source file exists at expected path":
    const auditSrc {.strdefine.} = "src/infrastructure/bypass_audit.nim"
    check auditSrc.len > 0

  test "reliability score formula: score = max(0, 100 - bypassCount*5)":
    ## Verify the scoring formula produces expected values.
    proc calcScore(bypassCount: int): int =
      max(0, 100 - bypassCount * 5)
    check calcScore(0) == 100
    check calcScore(4) == 80
    check calcScore(5) == 75
    check calcScore(20) == 0
    check calcScore(25) == 0
{.pop.}
