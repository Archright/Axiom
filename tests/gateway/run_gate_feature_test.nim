## Run Gate Feature Test — end-to-end verification of the Nim orchestrator.
##
## Scenario: bin/run-gate dispatches nim check and nimtry without shell/Python.

import std/[unittest, osproc, os, strutils, json, streams]

suite "Run Gate — Single Control Plane":
  test "bin/run-gate executes without Python or shell eval":
    ## Scenario 1: JSON input is accepted and gates are dispatched
    ## Given a valid Nim source file
    ## When it is passed to bin/run-gate via stdin JSON
    ## Then the process exits 0 and no Python process is spawned
    let input = """{"files":["src/cli/main.nim"]}"""
    let runGatePath = getCurrentDir() / "bin" / "run_gate"
    check fileExists(runGatePath)

    let p = startProcess(
      command = runGatePath,
      options = {poStdErrToStdOut}
    )
    p.inputStream().write(input)
    p.inputStream().close()
    let output = p.outputStream().readAll()
    let exitCode = p.waitForExit()
    p.close()

    check exitCode == 0
    check "nim check" in output
    check "Gate completed" in output
    # The wrapper must not contain Python references.
    let wrapper = readFile(runGatePath)
    check "python3" notin wrapper.toLowerAscii()
    check "eval" notin wrapper
