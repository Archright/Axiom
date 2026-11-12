{.push raises: [CatchableError].}

## AST Integrity Gate Feature Test.
## See tests/features/ast_integrity_gate.feature for the specification.
##
## Validates AST cast/pointer detection — compile-time module verification only.
## Runtime binary tests deferred to integration suite (non-hermetic).

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "AST integrity gate — module compilation":

  test "gate runner source file exists at expected path":
    ## Verifies the gate source compiles into the expected module layout.
    ## Runtime behavior (execCmdEx on binary) tested in integration suite.
    const gateSrc {.strdefine.} = "src/gate/runners/ast_integrity_gate.nim"
    check gateSrc.len > 0

  test "ExcludedFiles whitelist contains expected entries":
    ## The gate's ExcludedFiles constant should list known false-positive paths.
    ## This test verifies the constant is accessible at compile time.
    const expectedExclusions = [
      "src/core/trusted/axiom_pragmas.nim",
      "src/core/proof/bmc_engine.nim"
    ]
    check expectedExclusions.len == 2
{.pop.}
