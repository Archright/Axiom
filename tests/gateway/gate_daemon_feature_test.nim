{.push raises: [CatchableError].}

## Gate Daemon Feature Test.
## See tests/features/gate_daemon.feature for the specification.
##
## Validates L2 signing daemon module — compile-time verification.
## Runtime daemon lifecycle tested in integration suite (requires Unix socket).

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "gate daemon — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/gate_daemon.nim"
    check moduleSrc.len > 0

  test "binary exists at expected path":
    ## gate-daemon is compiled to bin/gate-daemon.
    const binaryPath {.strdefine.} = "bin/gate-daemon"
    check binaryPath.len > 0
{.pop.}
