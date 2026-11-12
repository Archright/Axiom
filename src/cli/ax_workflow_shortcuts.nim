import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## AX Workflow Shortcut Argument Parsing
## Remaining: ax scan shortcut only. ax prove/heal shortcuts migrated to
## macro-generated parsers in cli_surface_generated.nim.

import std/strutils
import cli/cli_io_input
import core/results

## ax Shortcut Default Limit constant.
const axShortcutDefaultLimit* = 5

# @axiom-hint: lean="token.length ≥ 0" smt="(assert (and (>= (str.len token) 0)))"
func isCliOptionToken(token: string): bool =
  token.len > 0 and token.startsWith("-")

## Parse Ax Topology Shortcut Args.
# @axiom-hint: lean="args.size ≥ 0" smt="(assert (>= (seq.len args) 0))"
func parseAxTopologyShortcutArgs*(
  args: seq[string]
): Result[tuple[targetDirectory: string, limit: int, diagnosisDepth: int, emitJson: bool], string] =
  var targetDirectory = ""
  var limit = axShortcutDefaultLimit
  var diagnosisDepth = 0
  var emitJson = false
  var i = 0
  while i < args.len:
    case args[i]
    of "--limit":
      if i + 1 >= args.len:
        return err("missing value: --limit")
      let parsedLimit = ??parseRequiredIntArg("--limit", args[i + 1])
      limit = max(1, parsedLimit)
      i += 2
    of "--diagnostic-depth":
      if i + 1 >= args.len:
        return err("missing value: --diagnostic-depth")
      let parsedDepth = ??parseRequiredIntArg("--diagnostic-depth", args[i + 1])
      diagnosisDepth = max(1, parsedDepth)
      i += 2
    of "--json":
      emitJson = true
      i += 1
    else:
      if isCliOptionToken(args[i]):
        return err("unknown option: " & args[i])
      if targetDirectory.len > 0:
        return err("unexpected positional argument: " & args[i])
      targetDirectory = args[i]
      i += 1
  if targetDirectory.len == 0:
    targetDirectory = "src"
  ok((targetDirectory: targetDirectory, limit: limit, diagnosisDepth: diagnosisDepth, emitJson: emitJson))

{.pop.}

