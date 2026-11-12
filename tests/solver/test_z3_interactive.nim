{.push raises: [CatchableError].}

## Z3 Interactive Tests — Unit tests for core/solver/z3_interactive.nim
## Tests exported constants and type construction. All Z3Stream proc operations
## require a live Z3 process and cannot be unit tested without a mock.

import std/[unittest, strutils]
import core/solver/z3_interactive

# ---------------------------------------------------------------------------
# Exported constants
# ---------------------------------------------------------------------------

suite "Exported constants":
  test "AxiomSyncMarker is non-empty":
    check AxiomSyncMarker.len > 0

  test "AxiomSyncCmd is non-empty":
    check AxiomSyncCmd.len > 0

  test "AxiomSyncTimeoutMs is positive":
    check AxiomSyncTimeoutMs > 0

  test "AxiomSyncTimeoutMs is reasonable (1-60 seconds in ms)":
    check AxiomSyncTimeoutMs >= 1000
    check AxiomSyncTimeoutMs <= 60_000

  test "AxiomSyncCmd contains the marker":
    check AxiomSyncCmd.contains(AxiomSyncMarker)

# ---------------------------------------------------------------------------
# Z3Stream type (fields: process, stdin, stdout, alive)
# ---------------------------------------------------------------------------

suite "Z3Stream type":
  test "dead stream construction (alive=false)":
    let stream = Z3Stream(alive: false)
    check stream.process == nil
    check stream.alive == false

  test "stream alive field defaults to false":
    let stream = Z3Stream()
    check stream.alive == false

# ---------------------------------------------------------------------------
# Z3RoundResult type (fields: lines, rawOutput, syncReceived)
# ---------------------------------------------------------------------------

suite "Z3RoundResult type":
  test "default construction":
    let result = Z3RoundResult()
    check result.lines.len == 0
    check result.rawOutput.len == 0
    check result.syncReceived == false

  test "construction with values":
    let result = Z3RoundResult(
      lines: @["sat"],
      rawOutput: "sat\nAXIOM_SYNC_xxx",
      syncReceived: true
    )
    check result.lines.len == 1
    check result.lines[0] == "sat"
    check result.syncReceived == true
    check result.rawOutput.contains("sat")

  test "timeout result (syncReceived=false)":
    let result = Z3RoundResult(
      lines: @[],
      rawOutput: "",
      syncReceived: false
    )
    check result.syncReceived == false
    check result.lines.len == 0

{.pop.}
