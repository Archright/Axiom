## validate_axiom_root_test.nim — Integration test for bin/validate_axiom_root.
##
## Runs the compiled binary under three AXIOM_ROOT states and asserts
## the expected exit codes and output patterns.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils]

let
  projectRoot = getEnv("AXIOM_PROJECT_ROOT", getAppDir().parentDir())
  validatorBin = projectRoot / "bin" / "validate_axiom_root"

proc runWithEnv(envVal: string = ""): tuple[exitCode: int; output: string] =
  ## Run the validator with optional AXIOM_ROOT override via shell.
  let cmd = if envVal.len > 0:
    "AXIOM_ROOT=" & envVal & " " & validatorBin
  else:
    "env -u AXIOM_ROOT " & validatorBin
  let r = execCmdEx(cmd, options = {poStdErrToStdOut})
  result.exitCode = r.exitCode
  result.output = r.output

proc main() =
  var failures = 0

  block unsetAXIOM:
    echo "TEST: AXIOM_ROOT unset -> exit 0, informational message"
    let r = runWithEnv("")
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      inc failures
    elif "AXIOM_ROOT is not set" notin r.output:
      echo "  FAIL: missing informational message in output"
      inc failures
    else:
      echo "  PASS"

  block correctAXIOM:
    echo "TEST: AXIOM_ROOT correct -> exit 0, PASS message"
    let r = runWithEnv(projectRoot)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      inc failures
    elif "VALIDATE AXIOM_ROOT PASS" notin r.output:
      echo "  FAIL: missing PASS in output"
      inc failures
    else:
      echo "  PASS"

  block bogusAXIOM:
    echo "TEST: AXIOM_ROOT bogus dir -> exit 1, FAIL message"
    let r = runWithEnv("/nonexistent/path/xyz")
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "VALIDATE AXIOM_ROOT FAIL" notin r.output:
      echo "  FAIL: missing FAIL in output"
      inc failures
    else:
      echo "  PASS"

  block noAnchorDir:
    echo "TEST: AXIOM_ROOT = /tmp (no anchor) -> exit 1"
    let r = runWithEnv("/tmp")
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "no project root anchor found" notin r.output:
      echo "  FAIL: missing anchor error in output"
      inc failures
    else:
      echo "  PASS"

  echo ""
  if failures > 0:
    echo $failures & " test(s) FAILED"
    quit(1)
  else:
    echo "All validate_axiom_root tests passed."

when isMainModule:
  main()
