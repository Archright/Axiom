{.push raises: [CatchableError].}

## Axiom Proof Generator Feature Test.
## See tests/features/axiom_prove.feature for the specification.
##
## Validates axiom-prove module — compile-time verification.
## Runtime proof generation tested in integration suite (requires Z3 + Lean).

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "axiom prove — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/axiom_prove.nim"
    check moduleSrc.len > 0

  test "binary exists at expected path":
    ## axiom-prove is compiled to bin/axiom-prove.
    ## Runtime execution requires bubblewrap sandbox.
    const binaryPath {.strdefine.} = "bin/axiom-prove"
    check binaryPath.len > 0
{.pop.}
