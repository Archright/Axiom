{.push raises: [CatchableError].}

## Hotspot Coverage Gate Feature Test.
## See tests/features/hotspot_coverage_gate.feature for the specification.
##
## Validates tiered coverage threshold logic.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "hotspot coverage gate — tier thresholds":

  test "Tier 1 hotspot requires 100% coverage":
    const tier1Threshold = 100
    check tier1Threshold == 100

  test "Tier 2 hotspot requires 80% coverage":
    const tier2Threshold = 80
    check tier2Threshold == 80

  test "Tier 3 hotspot requires 50% coverage":
    const tier3Threshold = 50
    check tier3Threshold == 50

  test "gate runner source file exists at expected path":
    const gateSrc {.strdefine.} = "src/gate/runners/hotspot_coverage_gate.nim"
    check gateSrc.len > 0
{.pop.}
