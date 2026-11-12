import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Gate CLI — Run gate checks or manage gate state.
##
## Subcommands:
##   list              — print all gate IDs with enabled/disabled status
##   status <gate-id>  — print last known status for a gate
##   run               — run gate checks on the current workspace
##
## Usage: ax gate [list|status|run] [args...]

import std/os
import std/osproc

import std/streams
import std/strutils
import core/contracts/z3_extraction
import infrastructure/logging_facade
import core/axiom_pragmas

proc runGateCli*(args: seq[string]): int  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if args.len == 0:
    logInfo("gate_cli", "Usage: ax gate <command> [args]")
    logInfo("gate_cli", "Commands: list, status <gate-id>, run")
    return 1

  let cmd = args[0]
  case cmd
  of "list":
    ## Delegate to bin/gate_admin for listing gates.
    if fileExists("bin/gate_admin"):
      let p = startProcess("bin/gate_admin", args=["list"],
                           options={poStdErrToStdOut, poUsePath})
      defer: p.close()
      var output = ""
      while not p.outputStream.atEnd:
        output.add(p.outputStream.readLine() & "\n")
      stdout.write(output)
      return p.waitForExit()
    else:
      echo "[gate] gate_admin binary not found. Run 'nim c -d:release src/cli/gate_admin.nim' first."
      return 1
  of "status":
    if args.len < 2:
      logInfo("gate_cli", "Usage: ax gate status <gate-id>")
      return 1
    if fileExists("bin/gate_admin"):
      let p = startProcess("bin/gate_admin", args=["status", args[1]],
                           options={poStdErrToStdOut, poUsePath})
      defer: p.close()
      var output = ""
      while not p.outputStream.atEnd:
        output.add(p.outputStream.readLine() & "\n")
      stdout.write(output)
      return p.waitForExit()
    else:
      echo "[gate] gate_admin binary not found."
      return 1
  of "run":
    var stage = "pre-commit"
    var i = 1
    while i < args.len:
      if args[i] == "--stage" and i + 1 < args.len:
        stage = args[i + 1]
        i += 2
      else:
        i += 1
    logInfo("gate_cli", "Running gate checks (stage=" & stage & ")...")
    let sourceDir = getCurrentDir()
    var modulePaths: seq[string] = @[]
    for f in walkDirRec(sourceDir):
      if f.endsWith(".nim"):
        modulePaths.add(f)
    let contractRes = extractAndVerifyContracts(modulePaths)
    if contractRes.status == psViolated:
      logError("gate_cli", "Contract verification FAILED")
      return 1
    logInfo("gate_cli", "Contract verification: " & $contractRes.procsProven & "/" & $contractRes.procsChecked & " proven")
    if fileExists("bin/gate_hook"):
      let p = startProcess("bin/gate_hook", args=[stage],
                           options={poStdErrToStdOut, poUsePath})
      defer: p.close()
      var output = ""
      while not p.outputStream.atEnd:
        output.add(p.outputStream.readLine() & "\n")
      stdout.write(output)
      return p.waitForExit()
    else:
      logInfo("gate_cli", "gate_hook binary not found (non-fatal)")
      return 0
  else:
    logInfo("gate_cli", "Unknown gate subcommand: " & cmd)
    logInfo("gate_cli", "Commands: list, status <gate-id>, run")
    return 1
{.pop.}
