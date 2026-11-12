import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Gate Runner Common Infrastructure
##
## Shared types, option parsing, and subprocess helpers for all
## `src/gate/runners/*.nim` executables. Keeps individual runners small and
## consistent.

import std/[os, osproc, strtabs, streams, options]
import core/results
import infrastructure/logging_facade
import core/trusted/axiom_pragmas

export results

type
  RunnerContext* = object
    ## Parsed command-line context for a gate runner.
    repoRoot*: string
    args*: seq[string]
    legacyVerifyPath*: Option[string]
    updateBaseline*: bool
    verbose*: bool

  GateResult* = object
    ## Normalized result returned by a gate runner.
    ok*: bool
    stdout*: string
    stderr*: string
    exitCode*: int

proc parseRunnerContext*(): RunnerContext {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse standard runner CLI options.
  ## Supported flags:
  ##   --legacy-verify <py>   enable Shadow Execution against Python original
  ##   --update-baseline      regenerate committed baseline
  ##   -v, --verbose          extra logging
  result.repoRoot = "."
  result.args = @[]
  result.legacyVerifyPath = none(string)
  result.updateBaseline = false
  result.verbose = false

  try:
    result.repoRoot = getCurrentDir()
  except CatchableError:
    result.repoRoot = "."

  let params = commandLineParams()
  var i = 0
  while i < params.len:
    let p = params[i]
    case p
    of "--legacy-verify":
      if i + 1 < params.len:
        result.legacyVerifyPath = some(params[i + 1])
        inc i
      else:
        logError("runner_common", "[runner] ERROR: --legacy-verify requires a path")
        quit(2)
    of "--update-baseline":
      result.updateBaseline = true
    of "-v", "--verbose":
      result.verbose = true
    else:
      result.args.add(p)
    inc i

proc runCommand*(
  cmd: string;
  args: openArray[string] = [];
  workingDir: string = "";
  env: openArray[(string, string)] = [];
  maxOutputLen: int = 2 * 1024 * 1024
): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run an external command via startProcess (shell-free).
  ## Captures stdout/stderr up to maxOutputLen bytes.
  var envTable: StringTableRef = nil
  if env.len > 0:
    envTable = newStringTable()
    for (k, v) in env:
      envTable[k] = v

  let wd = if workingDir.len > 0: workingDir else: getCurrentDir()
  var process: Process
  try:
    process = startProcess(
      command = cmd,
      workingDir = wd,
      args = args,
      env = envTable,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as e:
    return GateResult(ok: false, stderr: "Failed to start " & cmd & ": " & e.msg, exitCode: 127)

  var output = ""
  try:
    let stream = process.outputStream()
    var line = ""
    while not stream.atEnd():
      if output.len >= maxOutputLen:
        output.add("\n[output truncated at " & $maxOutputLen & " bytes]\n")
        break
      try:
        if stream.readLine(line):
          output.add(line)
          output.add("\n")
        else:
          break
      except IOError:
        break
  except CatchableError as e:
    output.add("\n[error reading output: " & e.msg & "]\n")

  let exitCode = process.waitForExit()
  try:
    process.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  result = GateResult(
    ok: exitCode == 0,
    stdout: output,
    stderr: "",
    exitCode: exitCode
  )

proc fail*(msg: string): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  GateResult(ok: false, stderr: msg, exitCode: 1)

proc pass*(msg: string = ""): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  GateResult(ok: true, stdout: msg, exitCode: 0)

{.pop.}
