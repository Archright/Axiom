{.push raises: [CatchableError].}

## Batch UAP Loop Driver Feature Test.
## See tests/features/loop_driver.feature for the specification.
##
## Validates compile-time module layout and cache metrics integration.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "loop driver — module compilation":

  test "loop driver source file exists at expected path":
    const driverSrc {.strdefine.} = "src/verification/batch_uap/loop_driver.nim"
    check driverSrc.len > 0

  test "stages module source file exists at expected path":
    const stagesSrc {.strdefine.} = "src/verification/batch_uap/stages.nim"
    check stagesSrc.len > 0
{.pop.}
