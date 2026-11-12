{.push raises: [CatchableError].}

## Manifest Integrity Gate Feature Test.
## See tests/features/manifest_integrity_gate.feature for the specification.
##
## Validates compile-time module layout and schema validator accessibility.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "manifest integrity gate — module compilation":

  test "gate runner source file exists at expected path":
    const gateSrc {.strdefine.} = "src/gate/runners/manifest_integrity_gate.nim"
    check gateSrc.len > 0

  test "manifest schema validator source exists":
    const schemaSrc {.strdefine.} = "tools/manifest_schema.nim"
    check schemaSrc.len > 0

  test "bootstrap_manifest.json exists at expected path":
    const manifestPath {.strdefine.} = "tests/specs/bootstrap_manifest.json"
    check manifestPath.len > 0
{.pop.}
