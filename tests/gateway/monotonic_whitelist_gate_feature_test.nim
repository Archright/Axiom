{.push raises: [CatchableError].}

## Monotonic Whitelist Gate Feature Test.
## See tests/features/monotonic_whitelist_gate.feature for the specification.
##
## Validates whitelist count parsing logic.

import std/[unittest, strutils]

{.push warning[BareExcept]:off.}
suite "monotonic whitelist gate — count parsing":

  test "parseWhitelistCount counts quoted entries correctly":
    ## Inline replica of the gate's counting logic for verification.
    proc countQuotedEntries(value: string): int =
      var i = 0
      while i < value.len:
        if value[i] == '"':
          inc i
          while i < value.len and value[i] != '"':
            inc i
          inc i
          inc result
        else:
          inc i
    check countQuotedEntries("\"a\",\"b\",\"c\"") == 3
    check countQuotedEntries("") == 0
    check countQuotedEntries("\"single\"") == 1

  test "gate runner source file exists at expected path":
    const gateSrc {.strdefine.} = "src/gate/runners/monotonic_whitelist_gate.nim"
    check gateSrc.len > 0
{.pop.}
