import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## I/O CLI — I/O boundary operations.
##
## Subcommands:
##   list              — list all axiomIoBoundary procs in src/
##   check <file>      — check a file for axiomIoBoundary compliance
##
## Usage: ax io [list|check] [args...]

import std/os
import std/strutils
import infrastructure/logging_facade
import core/axiom_pragmas

proc ioList*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  echo "[io] Scanning src/ for {.axiomIoBoundary.} or '# axiomIoBoundary' markers..."
  if not dirExists("src"):
    logInfo("io_cli", "[io] src/ directory not found.")
    return 1
  var count = 0
  for path in walkDirRec("src/", yieldFilter = {pcFile}):
    if not path.endsWith(".nim"):
      continue
    try:
      let content = readFile(path)
      for line in content.splitLines():
        let trimmed = line.strip()
        if trimmed.contains("axiomIoBoundary"):
          inc(count)
          echo "  " & path & ": " & trimmed
          break
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  echo "[io] Found " & $count & " I/O boundary marker(s)."
  return 0

proc ioCheck(path: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path):
    logInfo("io_cli", "[io] File not found: " & path)
    return 1
  try:
    let content = readFile(path)
    var hasBoundary = false
    for line in content.splitLines():
      if line.contains("axiomIoBoundary"):
        hasBoundary = true
        break
    if hasBoundary:
      echo "[io] " & path & " has axiomIoBoundary marker."
      return 0
    else:
      echo "[io] " & path & " does NOT have axiomIoBoundary marker."
      return 1
  except CatchableError as e:
    logError("io_cli", "[io] Error reading " & path & ": " & e.msg)
    return 1

proc runIoCli*(args: seq[string]): int =
  if args.len == 0:
    logInfo("io_cli", "Usage: ax io <command> [args]")
    logInfo("io_cli", "Commands: list, check <file>")
    return 1

  let cmd = args[0]
  case cmd
  of "list":
    return ioList()
  of "check":
    if args.len < 2:
      logInfo("io_cli", "Usage: ax io check <file>")
      return 1
    return ioCheck(args[1])
  else:
    logInfo("io_cli", "Unknown io subcommand: " & cmd)
    logInfo("io_cli", "Commands: list, check <file>")
    return 1
{.pop.}
