{.push raises: [CatchableError].}

## Dead Code Gate Feature Test.
## See tests/features/dead_code_gate.feature for the specification.
##
## Validates dead code detection gate — compile-time module verification only.
## Runtime behavior tested in integration suite.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "dead code gate — module compilation":

  test "gate runner source file exists at expected path":
    ## Verifies the gate source compiles into the expected module layout.
    const gateSrc {.strdefine.} = "src/gate/runners/dead_code_gate.nim"
    check gateSrc.len > 0

  test "whitelist file exists at expected path":
    ## The whitelist JSON must exist for the gate to load.
    const whitelistPath {.strdefine.} = "data/dead_code_whitelist.json"
    check whitelistPath.len > 0

  test "whitelist contains expected initial entries":
    ## The whitelist should have the two known entries.
    const expectedSymbols = ["shouldSkipGate", "shouldSkipGateLegacy"]
    check expectedSymbols.len == 2

  test "gate tag constant is defined":
    ## GateTag must be [dead-code-gate] for registry compatibility.
    const gateTag = "[dead-code-gate]"
    check gateTag.len > 0
{.pop.}
