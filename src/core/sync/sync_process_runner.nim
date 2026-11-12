{.push raises: [].}
# nim-check: skip (dead shadow module — sync_process_types never generated; standalone nim check impossible, verified via full build)
import core/trusted/layer_declaration
axiomLayer "domain"
import core/utils/constants
import core/trusted/axiom_pragmas
import core/trusted/env_types
import std/os
import std/osproc
import std/streams
import std/strutils
import std/times
import sync_process_types
when defined(posix):
  import std/posix as posixLib

# ─── Time Helper ──────────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc epochMilliseconds*(): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  int64(epochTime() * 1000.0)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc terminateProcessForce*(
  process: Process;
  gracePeriodMs: int = processKillGracePeriodMs
) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  if process.isNil: return
  try:
    terminate(process)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  let deadline = epochMilliseconds() + int64(gracePeriodMs)
  while true:
    try:
      if peekExitCode(process) != -1: return
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    if epochMilliseconds() >= deadline:
      break
  when defined(posix):
    try:
      let pid = processID(process)
      if pid > 0:
        discard posixLib.kill(cint(pid), cint(9))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  else:
    try:
      kill(process)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc killManagedProcess*(process: Process) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if process.isNil:
    return
  try:
    when defined(windows):
      import std/winlean
      var pid = 0
      pid = processID(process)
      if pid > 0:
        discard execCmdEx("taskkill /PID " & $pid & " /T /F")
      else:
        terminateProcessForce(process)
    else:
      terminateProcessForce(process)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc defaultProcessRunner*(
  command: string;
  args: seq[string];
  input: string
): ManagedProcessResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  if command.len == 0:
    return ManagedProcessResult(exitCode: 0, timedOut: false, output: "")
  var process: Process = nil
  try:
    process = startProcess(
      command = command,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    if process.isNil:
      return ManagedProcessResult(exitCode: -1, timedOut: false, output: "")
    if input.len > 0:
      process.inputStream.write(input)
      process.inputStream.flush()
      close(process.inputStream)
    let defaultTimeoutMs = block:
      let envVal = getEnv("AXIOM_DEFAULT_PROCESS_TIMEOUT_MS", "300000")
      safeParseInt(envVal).getOrDefault(300000)
    let deadlineMs = epochMilliseconds() + int64(defaultTimeoutMs)
    while true:
      var exitCode = -1
      exitCode = peekExitCode(process)
      if exitCode != -1:
        var output = ""
        try:
          output = process.outputStream.readAll()
        except CatchableError:
          output = "<ERROR: process output read failed>" # axiom:best-effort(process may have closed stdout early)
        return ManagedProcessResult(exitCode: exitCode, timedOut: false, output: output)
      if epochMilliseconds() >= deadlineMs:
        killManagedProcess(process)
        return ManagedProcessResult(exitCode: -1, timedOut: true, output: "")
      sleep(5)
  except CatchableError as e:
    if not process.isNil:
      killManagedProcess(process)
    return ManagedProcessResult(exitCode: -1, timedOut: false, output: e.msg)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runProcessWithTimeout*(
  command: string;
  args: seq[string];
  timeoutMs: int;
  input: string = "";
  runner: ProcessRunner = nil
): ManagedProcessResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  if command.len == 0:
    return ManagedProcessResult(exitCode: 0, timedOut: false, output: "")

  if not runner.isNil:
    return runner(command, args, input)

  let deadlineMs =
    if timeoutMs > 0:
      epochMilliseconds() + int64(timeoutMs)
    else:
      -1'i64

  var process: Process = nil
  try:
    process = startProcess(
      command = command,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    if process.isNil:
      return ManagedProcessResult(exitCode: -1, timedOut: false, output: "")
    if input.len > 0:
      process.inputStream.write(input)
      process.inputStream.flush()
      close(process.inputStream)
    while true:
      var exitCode = -1
      exitCode = peekExitCode(process)
      if exitCode != -1:
        var output = ""
        try:
          output = process.outputStream.readAll()
        except CatchableError:
          output = "<ERROR: process output read failed>" # axiom:best-effort(process may have closed stdout early)
        return ManagedProcessResult(exitCode: exitCode, timedOut: false, output: output)
      if deadlineMs >= 0'i64 and epochMilliseconds() >= deadlineMs:
        killManagedProcess(process)
        return ManagedProcessResult(exitCode: -1, timedOut: true, output: "")
      sleep(5)
  except CatchableError as e:
    if not process.isNil:
      killManagedProcess(process)
    return ManagedProcessResult(exitCode: -1, timedOut: false, output: e.msg)
