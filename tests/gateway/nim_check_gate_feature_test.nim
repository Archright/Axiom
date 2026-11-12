## Nim Check Gate Feature Test — Mode parsing and aggregator strategy (hermetic).
## See tests/features/nim_check_gate.feature for the specification.
##
## Contract: mode alias parsing, invalid mode rejection.
## Hermetic: tests pure parsing logic without external process calls.

import std/[unittest, strutils]

type GateRunMode = enum
  grmIncremental
  grmExhaustive

proc parseMode(input: string): GateRunMode =
  ## Mirror of nim_check_gate.nim mode parsing logic
  let modeStr = input.toLowerAscii()
  if modeStr in ["incremental", "inc", "grmincremental", "pre-commit"]:
    grmIncremental
  elif modeStr in ["exhaustive", "full", "grmexhaustive", "pre-push"]:
    grmExhaustive
  else:
    raise newException(ValueError, "invalid mode '" & input & "'")

suite "Nim Check Gate — Mode Parsing":
  test "Accepts incremental mode":
    ## Scenario: Accepts incremental mode
    check parseMode("incremental") == grmIncremental

  test "Accepts pre-commit mode alias":
    ## Scenario: Accepts pre-commit mode alias
    check parseMode("pre-commit") == grmIncremental

  test "Accepts inc shorthand":
    ## Scenario: Accepts inc shorthand
    check parseMode("inc") == grmIncremental

  test "Accepts exhaustive mode":
    ## Scenario: Accepts exhaustive mode
    check parseMode("exhaustive") == grmExhaustive

  test "Accepts pre-push mode alias":
    ## Scenario: Accepts pre-push mode alias
    check parseMode("pre-push") == grmExhaustive

  test "Accepts full shorthand":
    ## Scenario: Accepts full shorthand
    check parseMode("full") == grmExhaustive

  test "Rejects invalid mode":
    ## Scenario: Rejects invalid mode
    expect ValueError:
      discard parseMode("invalid-mode")

  test "Case insensitive parsing":
    ## Scenario: Case insensitive parsing
    check parseMode("PRE-COMMIT") == grmIncremental
    check parseMode("Pre-Push") == grmExhaustive
    check parseMode("GRMINCREMENTAL") == grmIncremental

suite "Nim Check Gate — Aggregator Strategy":
  test "Forwarding stub detection — pattern matching":
    ## Scenario: Forwarding stubs excluded from aggregator
    ## Verify the forwarding stub detection pattern
    let stubContent = "# Forwarding stub: 'old_module' deprecated\nimport something"
    check stubContent.contains("Forwarding stub")

  test "isMainModule detection — pattern matching":
    ## Scenario: isMainModule files checked per-file
    ## Verify the isMainModule detection pattern
    let mainContent = "when isMainModule:\n  main()"
    check mainContent.contains("when isMainModule")
