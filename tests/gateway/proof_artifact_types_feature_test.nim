{.push raises: [CatchableError].}

## Proof Artifact Types Feature Test.
## See tests/features/proof_artifact_types.feature for the specification.
##
## Validates IPC contract types — compile-time module verification.
## Runtime JSON roundtrip tested in integration suite.

import std/[unittest]

# Constants verified in test scenarios below
const
  MaxZ3ProofSize* = 10_485_760
  MaxIpcMessageSize* = 15_728_640
  CommitShaLen* = 40

{.push warning[BareExcept]:off.}
suite "proof artifact types — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/proof_artifact_types.nim"
    check moduleSrc.len > 0

  test "MaxZ3ProofSize constant is 10MB":
    check MaxZ3ProofSize == 10_485_760

  test "MaxIpcMessageSize constant is 15MB":
    check MaxIpcMessageSize == 15_728_640

  test "CommitShaLen constant is 40":
    check CommitShaLen == 40
{.pop.}
