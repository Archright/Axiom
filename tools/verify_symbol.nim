import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, osproc]
proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()

  if params.len < 1:
    echo "Usage: verify_symbol <file>"
    echo "  Runs nim check on a single file and reports pass/fail."
    quit(1)

  let filePath = params[0]

  if not fileExists(filePath):
    stderr.writeLine("FILE_NOT_FOUND: ", filePath)
    quit(1)

  # Run nim check with suppressed hints/warnings
  let cmd = "nim check --hints:off --warnings:off " & quoteShell(filePath)
  let (output, exitCode) = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})

  # Capture only first 20 lines of output (matches head -20 in shell)
  var truncatedOutput: seq[string] = @[]
  var lineCount = 0
  for line in output.splitLines():
    if lineCount >= 20:
      break
    truncatedOutput.add(line)
    inc lineCount

  if exitCode != 0:
    echo "COMPILE_FAILED: ", filePath
    for line in truncatedOutput:
      echo line
    quit(1)

  echo "COMPILE_OK: ", filePath

when isMainModule:
  main()
