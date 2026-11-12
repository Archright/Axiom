import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Lint CLI — Run canonical hub linting on source files.
##
## Delegates to bin/canonical_hub_lint for actual lint execution.
##
## Usage: ax lint [files...]

import std/os
import std/osproc
import std/streams
import infrastructure/logging_facade
import core/axiom_pragmas

proc runLintCli*(args: seq[string]): int  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if args.len == 0:
    logInfo("lint_cli", "Usage: ax lint [files...]")
    logInfo("lint_cli", "Run canonical hub linting on the given files (or all src/ if none specified).")
    return 1

  if fileExists("bin/canonical_hub_lint"):
    var cmdArgs: seq[string]
    for arg in args:
      cmdArgs.add(arg)
    let p = startProcess("bin/canonical_hub_lint", args=cmdArgs,
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      output.add(p.outputStream.readLine() & "\n")
    stdout.write(output)
    return p.waitForExit()
  else:
    echo "[lint] canonical_hub_lint binary not found."
    echo "[lint] Build with: nim c -d:release tools/canonical_hub_lint.nim"
    return 1
{.pop.}
