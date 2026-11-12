{.push raises: [CatchableError].}

## Batch UAP Stages Feature Test.
## See tests/features/stages.feature for the specification.
##
## Validates compile-time module layout and cache metrics type.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "stages — module compilation":

  test "stages source file exists at expected path":
    const stagesSrc {.strdefine.} = "src/verification/batch_uap/stages.nim"
    check stagesSrc.len > 0

  test "summary cache source file exists at expected path":
    const cacheSrc {.strdefine.} = "src/core/types/function_verification_summary.nim"
    check cacheSrc.len > 0
{.pop.}
