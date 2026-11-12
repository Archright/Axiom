import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## Hermetic Build Container Entrypoint
##
## Runs the requested command under strace execve tracing and audits the trace
## against src/policy/build_constraint.nim. Any python3/bash/sh invocation
## causes immediate failure.

import std/[os, osproc, strutils]
import shared_types/shared_types
import policy/build_constraint

const
  TraceFile = "/tmp/hermetic-exec-trace.log"

proc main() {.raises: [CatchableError], axiomEffect: IoEffect.} =
  let args = commandLineParams()
  if args.len < 1:
    stderr.writeLine("Usage: hermetic_entry <command> [args...]")
    quit(1)

  let cmd = args[0]
  let cmdArgs = if args.len > 1: args[1 .. ^1] else: @[]

  # Remove any previous trace.
  try:
    if fileExists(TraceFile):
      removeFile(TraceFile)
  except CatchableError:
    discard  # axiom:best-effort(trace-file-removal-failure: prior trace may not exist, harmless)

  stderr.writeLine("[hermetic-entry] Running under execve audit: " & cmd & " " & cmdArgs.join(" "))

  # Run strace with parent streams so the traced command's stdout/stderr remain
  # visible to the user. Only the execve trace is captured to file.
  var process: Process
  try:
    process = startProcess(
      command = "strace",
      args = @["-e", "execve", "-f", "-o", TraceFile, cmd] & cmdArgs,
      options = {poUsePath, poParentStreams}
    )
  except OSError as e:
    stderr.writeLine("[hermetic-entry] Failed to start strace: " & e.msg)
    quit(127)

  let commandExitCode = process.waitForExit()
  try:
    process.close()
  except CatchableError:
    discard  # axiom:best-effort(process-close-failure: strace already exited, resource cleanup best-effort)

  # Audit the trace. The target binary itself is permitted to execve once
  # (the initial invocation); any further execve of an interpreter or
  # disallowed external binary is a violation.
  if fileExists(TraceFile):
    var traceLines: seq[string] = @[]
    var targetSeen = false
    try:
      for line in lines(TraceFile):
        let execIdx = line.find("execve(\"")
        if execIdx < 0:
          continue
        let pathStart = execIdx + 8
        let pathEnd = line.find("\"", pathStart)
        if pathEnd < 0:
          continue
        let binaryPath = line[pathStart ..< pathEnd]
        if binaryPath == cmd:
          if not targetSeen:
            targetSeen = true
            continue
        traceLines.add(line)
    except CatchableError as e:
      stderr.writeLine("[hermetic-entry] Failed to read trace: " & e.msg)
      quit(1)

    let violations = auditExecTrace(traceLines)
    if violations.len > 0:
      stderr.writeLine("[hermetic-entry] BUILD CONSTRAINT VIOLATIONS DETECTED:")
      for v in violations:
        stderr.writeLine("  " & v)
      stderr.writeLine("[hermetic-entry] Only allowed binaries may execute inside hermetic build.")
      quit(1)
  else:
    stderr.writeLine("[hermetic-entry] WARNING: no exec trace generated")

  stderr.writeLine("[hermetic-entry] Command completed. Exit code: " & $commandExitCode)
  quit(commandExitCode)

when isMainModule:
  main()

{.pop.}
