import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Infrastructure-level process utilities.
## Provides `execCmdWithTimeout` — shell command execution with timeout and
## SIGTERM→SIGKILL escalation. Supports optional `progressProbe` for
## liveness-based deadline extension (see `docs/spec/execution_liveness.md` §5).

import core/axiom_pragmas
import std/os
import std/osproc
import std/posix as posixLib
import std/tempfiles
import std/times

axiomIoBoundary()

const defaultExecTimeoutMs* = 30_000

proc epochMilliseconds*(): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  int64(epochTime() * 1000.0)

## Kill subprocess gracefully: SIGTERM → 2s grace → SIGKILL → wait → close.
proc killProcessGracefully*(process: Process) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try: terminate(process)
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  let killDeadline = epochMilliseconds() + 2_000
  while true:
    try:
      if peekExitCode(process) != -1: break
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    if epochMilliseconds() >= killDeadline: break
    sleep(50)
  when defined(posix):
    try:
      let pid = processID(process)
      if pid > 0: discard posixLib.kill(cint(pid), cint(9))
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  else:
    try: kill(process)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  try: discard process.waitForExit(500)
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  try: process.close()
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)

## Exec Command With Timeout.
## Runs `cmd` via `/bin/bash -c` with optional working directory.
## Returns (output, exitCode) on success, ("", -1) on timeout or error.
## SIGTERM on timeout; after 2s grace, SIGKILL escalation.
## Output is captured through a temp FILE, not a pipe: an undrained pipe
## deadlocks once output exceeds the 64 KiB kernel buffer (the child blocks
## on write while the parent waits for exit — observed live with a
## CLI JSON listing at 16 servers: 66,615 bytes). A file has no
## capacity limit; the (output, exitCode) contract is unchanged.
## When `progressProbe` is provided and has returned true at least once,
## the deadline is extended to `lastProgressMs + timeoutMs` on liveness
## events (see `docs/spec/execution_liveness.md` §5).
proc execCmdWithTimeout*(
  cmd: string; workingDir: string = "";
  timeoutMs: int = defaultExecTimeoutMs;
  progressProbe: proc(): bool {.nimcall, raises: [], gcsafe.} = nil
): (string, int) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if cmd.len == 0: return ("", 0)
  var process: Process = nil
  var lastProgressMs = epochMilliseconds()
  var hasProgress = false
  var outPath = ""
  try:
    let (tmpFile, createdPath) = createTempFile("axexec-", ".out")
    outPath = createdPath
    tmpFile.close()  # the child re-opens the path via shell redirection
    var args = @["-c", cmd & " > '" & outPath & "' 2>&1"]
    if workingDir.len > 0:
      process = startProcess(command = "/bin/bash", args = args, workingDir = workingDir)
    else:
      process = startProcess(command = "/bin/bash", args = args)
    if process.isNil: return ("", -1)
    var deadlineMs = if timeoutMs > 0: epochMilliseconds() + int64(timeoutMs) else: -1'i64
    while true:
      var exitCode = peekExitCode(process)
      if exitCode != -1:
        try: return (readFile(outPath), exitCode)
        except CatchableError:
          return ("", exitCode)  # axiom:best-effort(ioboundary catch)
      if deadlineMs >= 0'i64 and epochMilliseconds() >= deadlineMs:
        if progressProbe != nil and hasProgress:
          deadlineMs = lastProgressMs + int64(timeoutMs)
          continue
        killProcessGracefully(process)
        return ("", -1)
      if progressProbe != nil:
        try:
          if progressProbe():
            hasProgress = true
            lastProgressMs = epochMilliseconds()
            deadlineMs = lastProgressMs + int64(timeoutMs)
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      sleep(5)
  except CatchableError:
    if not process.isNil: killProcessGracefully(process)
    return ("", -1)
  finally:
    if outPath.len > 0:
      try: removeFile(outPath)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)

{.pop.}
