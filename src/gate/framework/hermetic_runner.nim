import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/[os, osproc, streams]
import core/trusted/axiom_pragmas
import infrastructure/logging_facade

type
  GateStatusKind* = enum
    gskPass
    gskFail
    gskError

  GateResult* = object
    status*: GateStatusKind
    message*: string
    output*: string

  HermeticRunner* = object
    timeoutMs*: int
    enablePanicMode*: bool
    captureOutput*: bool

func initHermeticRunner*(
  timeoutMs: int = 300000;
  enablePanicMode: bool = true;
  captureOutput: bool = true
): HermeticRunner {.raises: [].} =
  HermeticRunner(
    timeoutMs: timeoutMs,
    enablePanicMode: enablePanicMode,
    captureOutput: captureOutput
  )

proc compileGate*(runner: HermeticRunner; gateEntry: string; outBin: string): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  logInfo("hermetic-runner", "Compiling gate: " & gateEntry & " -> " & outBin)

  var compileArgs = @["c"]
  if runner.enablePanicMode:
    compileArgs.add("--panics:on")
  compileArgs.add("-o:" & outBin)
  compileArgs.add(gateEntry)

  var compileProcess: Process
  try:
    compileProcess = startProcess(
      command = "nim",
      args = compileArgs,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as e:
    return GateResult(status: gskError, message: "Failed to start Nim compiler: " & e.msg)

  var compileOutput = ""
  var line = ""
  while compileProcess.outputStream.readLine(line):
    compileOutput.add(line)
    compileOutput.add("\n")

  let compileCode = compileProcess.waitForExit()
  try:
    compileProcess.close()
  except CatchableError:
    discard

  if compileCode != 0:
    GateResult(status: gskError, message: "Compilation failed (exit code " & $compileCode & ")", output: compileOutput)
  else:
    GateResult(status: gskPass, message: "Compilation succeeded", output: compileOutput)

proc runGateIsolated*(runner: HermeticRunner; gateEntry: string; args: seq[string]): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tmpDir = getTempDir() / "axiom_hermetic"
  try:
    createDir(tmpDir)
  except OSError:
    return GateResult(status: gskError, message: "Failed to create temp directory: " & tmpDir)

  let tmpBin = tmpDir / "gate_" & $getCurrentProcessId()

  let compileResult = compileGate(runner, gateEntry, tmpBin)
  if compileResult.status != gskPass:
    return compileResult

  logInfo("hermetic-runner", "Executing gate: " & tmpBin)

  var execProcess: Process
  try:
    execProcess = startProcess(
      command = tmpBin,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as e:
    return GateResult(status: gskError, message: "Failed to start gate binary: " & e.msg)

  var output = ""
  if runner.captureOutput:
    var line = ""
    while execProcess.outputStream.readLine(line):
      output.add(line)
      output.add("\n")

  let exitCode = execProcess.waitForExit(runner.timeoutMs)
  if exitCode == -1:
    execProcess.kill()
    try:
      execProcess.close()
    except CatchableError:
      discard
    return GateResult(status: gskError, message: "Timeout", output: output)

  let finalCode = execProcess.peekExitCode()
  try:
    execProcess.close()
  except CatchableError:
    discard

  try:
    if fileExists(tmpBin):
      removeFile(tmpBin)
  except OSError:
    discard

  case finalCode
  of 0:
    GateResult(status: gskPass, message: "Pass", output: output)
  of 1:
    GateResult(status: gskFail, message: "Fail", output: output)
  else:
    GateResult(status: gskError, message: "Process panic/crash (exit code " & $finalCode & ")", output: output)

{.pop.}
