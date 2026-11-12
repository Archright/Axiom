import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Scaffold CLI — Generate test stubs from .feature files.
## Wraps tools/scaffold_feature_test.nim via startProcess.
##
## Usage: ax scaffold <feature_name> [--force]

import std/osproc
import std/streams
import std/strutils
import infrastructure/logging_facade
import core/axiom_pragmas

proc runScaffoldCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run the scaffold tool with the given args.
  ## Returns 0 on success, non-zero on failure.
  if args.len == 0 or args[0].startsWith("-"):
    logError("scaffold_cli", "Error: feature name required.")
    logInfo("scaffold_cli", "Usage: ax scaffold <feature_name> [--force]")
    return 1

  let featureName = args[0]
  var cmdArgs = @["c", "-r", "tools/scaffold_feature_test.nim", featureName]

  # Pass through --force if present
  for i in 1 ..< args.len:
    if args[i] == "--force" or args[i] == "-f":
      cmdArgs.add("--force")
    elif args[i] == "--help" or args[i] == "-h":
      cmdArgs.add("--help")

  let p = startProcess("nim", args=cmdArgs,
                        options={poStdErrToStdOut, poUsePath})
  defer: p.close()

  let s = p.outputStream
  var output = ""
  while not s.atEnd:
    output.add(s.readLine() & "\n")

  let exitCode = p.waitForExit()
  stdout.write(output)
  return exitCode
{.pop.}
