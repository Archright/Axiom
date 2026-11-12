import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## DAG CLI — Task DAG visualization, execution, and validation.
##
## Subcommands:
##   show              — display the current task DAG
##   validate          — validate DAG structure for cycles and invariants
##   run [args...]     — execute the DAG
##
## Usage: ax dag [show|validate|run] [args...]

import std/os
import std/osproc
import std/streams
import infrastructure/logging_facade
import core/axiom_pragmas

proc dagShow*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fileExists("bin/dag_executor"):
    let p = startProcess("bin/dag_executor", args=["--show"],
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      output.add(p.outputStream.readLine() & "\n")
    stdout.write(output)
    return p.waitForExit()
  elif fileExists("bin/task_dag"):
    let p = startProcess("bin/task_dag", args=["show"],
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      output.add(p.outputStream.readLine() & "\n")
    stdout.write(output)
    return p.waitForExit()
  else:
    echo "[dag] DAG binaries not found (bin/dag_executor, bin/task_dag)."
    echo "[dag] Build with: nim c -d:release tools/dag_executor.nim"
    return 1

proc dagValidate*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  echo "[dag] Validating DAG structure..."
  if fileExists("bin/task_dag"):
    let p = startProcess("bin/task_dag", args=["validate"],
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      output.add(p.outputStream.readLine() & "\n")
    stdout.write(output)
    return p.waitForExit()
  else:
    echo "[dag] DAG validator binary not found."
    return 1

proc dagRun*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fileExists("bin/dag_executor"):
    var cmdArgs: seq[string]
    for arg in args:
      cmdArgs.add(arg)
    let p = startProcess("bin/dag_executor", args=cmdArgs,
                         options={poStdErrToStdOut, poUsePath})
    defer: p.close()
    var output = ""
    while not p.outputStream.atEnd:
      output.add(p.outputStream.readLine() & "\n")
    stdout.write(output)
    return p.waitForExit()
  else:
    echo "[dag] DAG executor binary not found."
    echo "[dag] Build with: nim c -d:release tools/dag_executor.nim"
    return 1

proc runDagCli*(args: seq[string]): int =
  if args.len == 0:
    logInfo("dag_cli", "Usage: ax dag <command> [args]")
    logInfo("dag_cli", "Commands: show, validate, run")
    return 1

  let cmd = args[0]
  case cmd
  of "show":
    return dagShow()
  of "validate":
    return dagValidate()
  of "run":
    return dagRun(args[1 .. ^1])
  else:
    logInfo("dag_cli", "Unknown dag subcommand: " & cmd)
    logInfo("dag_cli", "Commands: show, validate, run")
    return 1
{.pop.}
