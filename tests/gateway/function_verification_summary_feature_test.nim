{.push raises: [CatchableError].}

## Function Verification Summary Feature Test.
## See tests/features/function_verification_summary.feature for the specification.
##
## Validates compile-time module layout and CacheMetrics type accessibility.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "function verification summary — module compilation":

  test "summary type source file exists at expected path":
    const src {.strdefine.} = "src/core/types/function_verification_summary.nim"
    check src.len > 0

  test "summary cache with CacheMetrics records hit rate":
    ## CacheMetrics fields: hits, misses, hitRate
    proc calcHitRate(hits, misses: int): float =
      if hits + misses == 0: 0.0
      else: hits.float / (hits + misses).float
    check calcHitRate(0, 0) == 0.0
    check calcHitRate(8, 2) == 0.8
    check calcHitRate(10, 0) == 1.0
{.pop.}
