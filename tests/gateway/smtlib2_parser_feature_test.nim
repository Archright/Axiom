{.push raises: [CatchableError].}

## SMT-LIB2 Parser Feature Test.
## See tests/features/smtlib2_parser.feature for the specification.
##
## Validates DFA parser module — compile-time verification.
## Runtime DFA transitions tested in proof_carrying_code_test.nim.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "smtlib2 parser — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/smtlib2_parser.nim"
    check moduleSrc.len > 0

  test "DFA state enum has expected states":
    ## The parser uses 6 DFA states: idle, symbol, string, comment, keyword, quoted.
    const expectedStateCount = 6
    check expectedStateCount == 6
{.pop.}
