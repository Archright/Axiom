import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## CST CLI — Tree-sitter CST operations via vendor/static C linking.
##
## Replaces tools/run_cst_tool.sh (Python venv + tree-sitter-nim).
## Validates vendor/tree-sitter prerequisites, then compiles and runs
## the CST parser tool with static linking.
##
## Subcommands:
##   (default) — compile-check and validate CST tool prerequisites
##
## Usage: ax cst [--dry-run]

import std/os
import std/osproc
import infrastructure/logging_facade

proc runCstCli*(args: seq[string]): int  =
  var dryRun = false
  for a in args:
    if a == "--dry-run":
      dryRun = true

  let root = getCurrentDir()
  let vendorDir = root / "vendor" / "tree-sitter"

  # 1. Validate vendor/tree-sitter directory exists
  if not dirExists(vendorDir):
    logInfo("cst_cli", "ax cst: vendor/tree-sitter/ not found")
    logInfo("cst_cli", "ax cst: run: git submodule update --init vendor/tree-sitter")
    return 1

  # 2. Verify tree-sitter header exists
  let headerPath = vendorDir / "lib" / "include" / "tree_sitter" / "api.h"
  if not fileExists(headerPath):
    logInfo("cst_cli", "ax cst: tree_sitter/api.h not found — run git submodule update")
    return 1

  # 3. Locate the CST tool source (Nim port of cst_nim_parser.py)
  let cstSrc = root / "tools" / "cst_nim_parser.nim"
  if not fileExists(cstSrc):
    logInfo("cst_cli", "ax cst: tools/cst_nim_parser.nim not found")
    return 1

  if dryRun:
    echo "ax cst: dry-run — would compile and run CST tool"
    echo "ax cst: vendor/tree-sitter headers: " & headerPath
    echo "ax cst: CST tool source: " & cstSrc
    return 0

  # 4. Find nim binary
  let nimBin = findExe("nim")
  if nimBin.len == 0:
    logInfo("cst_cli", "ax cst: nim not found in PATH")
    return 1

  # 5. Compile-check the CST tool source
  let (output, exitCode) = execCmdEx(
    nimBin & " check --hints:off --warnings:off " & cstSrc)
  if exitCode != 0:
    logError("cst_cli", "ax cst: CST tool source has errors")
    if output.len > 0:
      logInfo("cst_cli", output)
    return 1

  echo "ax cst: CST tool source verified (nim check OK)"
  echo "ax cst: tree-sitter headers verified at " & headerPath
  echo "ax cst: CST parser ready — tools/cst_nim_parser.nim"

  # 6. Run the smoke test to verify the tool works
  let (runOutput, runExit) = execCmdEx(
    nimBin & " c -r --hints:off --warnings:off " & cstSrc & " --smoke-test")
  if runExit != 0:
    logError("cst_cli", "ax cst: smoke test failed")
    if runOutput.len > 0:
      logInfo("cst_cli", runOutput)
    return 1

  echo runOutput
  echo "ax cst: smoke test passed"
  return 0
{.pop.}
