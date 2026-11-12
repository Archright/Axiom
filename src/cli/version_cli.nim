import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Version CLI — Print version, Nim toolchain, and environment info.
##
## Usage: ax version

import std/osproc
import std/streams
import cli/version
import core/axiom_pragmas

proc detectNimVersion(): string  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let p = startProcess("nim", args=["--version"],
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      let line = p.outputStream.readLine()
      if output.len == 0:
        output = line
        break
    return output
  except CatchableError:
    return "Nim not found in PATH"

proc detectLeanVersion(): string  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let p = startProcess("lean", args=["--version"],
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      let line = p.outputStream.readLine()
      if output.len == 0:
        output = line
        break
    return output
  except CatchableError:
    return "Lean not found in PATH"

proc runVersionCli*(args: seq[string]): int =
  echo "ax " & axiomVersionWithPrefix
  echo ""
  echo "Toolchain:"
  echo "  " & detectNimVersion()
  echo "  " & detectLeanVersion()
  echo ""
  echo "Platform:"
  echo "  OS: " & hostOS
  echo "  Arch: " & hostCPU
  return 0
{.pop.}
