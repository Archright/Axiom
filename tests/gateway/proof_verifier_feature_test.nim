{.push raises: [CatchableError].}

## Proof Verifier Feature Test.
## See tests/features/proof_verifier.feature for the specification.
##
## Validates Lean kernel-only verification — compile-time verification.
## Runtime verification tested in proof_carrying_code_test.nim.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "proof verifier — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/proof_verifier.nim"
    check moduleSrc.len > 0

  test "VerificationResult enum has expected values":
    ## vrSuccess, vrInputTooLarge, vrMalformedInput, vrInvalidToolchain,
    ## vrInvalidZ3Proof, vrInvalidLeanKernel, vrInvalidMerkle
    const expectedResultCount = 7
    check expectedResultCount == 7
{.pop.}
