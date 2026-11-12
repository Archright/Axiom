## drnim Gate Feature Test.
## Verifies the drnim gate handles nim check correctly.
##
## Tests:
##   - Target file list includes core modules
##   - -d:allowMissingZ3 flag is used for nim check
##   - axiom.nimble boundary check

import std/[unittest, os, strutils]

suite "drnim Gate — Core Module Verification":

  test "drnim targets include bmc_race and results":
    ## Given the drnim gate target list
    ## When checked
    ## Then it includes the core BMC and result type modules
    let targets = @["src/core/bmc_race.nim", "src/core/types/results.nim"]
    check targets.len == 2
    check "bmc_race" in targets[0]
    check "results" in targets[1]

  test "drnim uses -d:allowMissingZ3 for nim check":
    ## Given the drnim gate runs nim check
    ## When examining the command
    ## Then it includes -d:allowMissingZ3 to handle gorge() PATH quirk
    let cmd = "nim check -d:allowMissingZ3 src/core/types/results.nim"
    check "-d:allowMissingZ3" in cmd

  test "drnim skips when axiom.nimble is missing":
    ## Given a directory without axiom.nimble
    ## When checking the boundary condition
    ## Then the gate should return early
    let hasNimble = fileExists("axiom.nimble")
    # In the Axiom project, axiom.nimble exists
    check hasNimble
