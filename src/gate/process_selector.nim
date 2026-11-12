import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Axiom Process Selector — Event-Driven Subprocess Management
##
## Replaces the sleep(50) polling loop with OS-level event notification
## via Nim's selectors module (epoll on Linux, kqueue on BSD).
##
## Design: posix.pipe() + fork/exec for full FD control. The Selector
## monitors stdout read-end FDs; when data arrives or EOF is detected,
## the kernel wakes the orchestrator immediately (0ms idle overhead).
##
## Stdin file-list injection: passFilenames=true gates receive their
## file list via stdin pipe (one path per line), eliminating ARG_MAX
## risk and temp-file I/O pollution.

import std/posix
import std/selectors
import core/axiom_pragmas

type
  ManagedProcess* = object
    ## A subprocess with manually-controlled pipe FDs for Selector integration.
    pid*: Pid
    stdoutRead*: cint        # Pipe read-end (registered with Selector)
    stdinWrite*: cint        # Pipe write-end for stdin injection
    output*: string          # Accumulated stdout output
    exitCode*: int           # Process exit code (valid when finished=true)
    finished*: bool          # True when EOF detected on stdout
    startTime*: float64      # Epoch seconds when process was spawned
    allocatedTokens*: int    # Token budget held by this gate
    gateIdx*: int            # Index into the gate config array

  PosixErrorCode* = enum
    ## Deterministic error code mapping for Selector events.
    pecEagain = 0    # Pipe empty (non-blocking) → retry
    pecEpipe = 1     # Child process exited (EOF)
    pecEintr = 2     # Signal interrupted → retry
    pecEbadf = 3     # Bad FD → unregister + error
    pecUnknown = 4   # Unknown error

proc classifyPosixError*(errno: cint): PosixErrorCode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Map posix errno to deterministic error code for telemetry.
  case errno
  of EAGAIN: pecEagain
  of EPIPE: pecEpipe
  of EINTR: pecEintr
  of EBADF: pecEbadf
  else: pecUnknown

func spawnManaged*(cmd: string; workingDir: string;
 gateIdx: int = 0; allocatedTokens: int = 0): ManagedProcess =
  ## Spawn a subprocess with manual pipe control.
  ## Creates stdout and stdin pipes, forks, and execs via /bin/sh.
  ## The parent registers stdoutRead with a Selector for event-driven I/O.
  var stdoutPipe: array[2, cint]
  var stdinPipe: array[2, cint]

  if posix.pipe(stdoutPipe) != 0:
    raise newException(OSError, "pipe(stdout) failed: " & $errno)
  if posix.pipe(stdinPipe) != 0:
    raise newException(OSError, "pipe(stdin) failed: " & $errno)

  let pid = fork()
  if pid == 0:
    # ── Child process ──
    # Close parent-side pipe ends
    discard close(stdoutPipe[0])  # Close read-end of stdout pipe
    discard close(stdinPipe[1])   # Close write-end of stdin pipe

    # Redirect stdout/stdin to pipes
    discard dup2(stdoutPipe[1], STDOUT_FILENO)
    discard dup2(stdinPipe[0], STDIN_FILENO)

    # Close the original FDs after dup2
    if stdoutPipe[1] != STDOUT_FILENO:
      discard close(stdoutPipe[1])
    if stdinPipe[0] != STDIN_FILENO:
      discard close(stdinPipe[0])

    # Change working directory
    if workingDir.len > 0:
      discard chdir(workingDir.cstring)

    # Execute via /bin/sh
    let shell = "/bin/sh"
    let args = allocCStringArray(["/bin/sh", "-c", cmd])
    discard execvp(shell.cstring, args)
    # execvp only returns on failure
    quit(1)

  elif pid > 0:
    # ── Parent process ──
    # Close child-side pipe ends
    discard close(stdoutPipe[1])  # Close write-end of stdout pipe
    discard close(stdinPipe[0])   # Close read-end of stdin pipe

    result = ManagedProcess(
      pid: pid,
      stdoutRead: stdoutPipe[0],
      stdinWrite: stdinPipe[1],
      output: "",
      exitCode: -1,
      finished: false,
      startTime: 0.0,  # caller sets this
      allocatedTokens: allocatedTokens,
      gateIdx: gateIdx
    )
  else:
    raise newException(OSError, "fork() failed: " & $errno)

proc writeStdin*(mp: var ManagedProcess; data: string) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write data to the child process's stdin pipe.
  ## Used for stdin file-list injection (passFilenames=true gates).
  if mp.stdinWrite < 0:
    return
  let written = posix.write(mp.stdinWrite, unsafeAddr data[0], data.len)
  if written < 0:
    raise newException(IOError, "write(stdin) failed: " & $errno)

proc closeStdin*(mp: var ManagedProcess) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Close the child's stdin pipe (signals EOF to child).
  if mp.stdinWrite >= 0:
    discard close(mp.stdinWrite)
    mp.stdinWrite = -1

proc registerWithSelector*(sel: var Selector[int]; mp: ManagedProcess;
                            index: int) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Register the process's stdout FD with the Selector for event monitoring.
  ## The data field stores the index into the process array.
  sel.registerHandle(mp.stdoutRead, {Event.Read, Event.Error}, index)

proc unregisterFromSelector*(sel: var Selector[int]; mp: ManagedProcess) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unregister the process's stdout FD from the Selector.
  try:
    sel.unregister(mp.stdoutRead)
  except KeyError:
    discard  # Already unregistered

proc drainStdout*(mp: var ManagedProcess): int {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read available data from stdout pipe. Returns bytes read, 0 on EOF, -1 on error.
  ## Non-blocking read to drain the pipe buffer without blocking.
  var buf: array[8192, char]
  let n = read(mp.stdoutRead, addr buf[0], buf.len)
  if n > 0:
    # Convert char array slice to string
    var s = newString(n)
    copyMem(addr s[0], unsafeAddr buf[0], n)
    mp.output.add(s)
    return n
  elif n == 0:
    # EOF — child closed stdout (process exited)
    return 0
  else:
    # Error
    let err = errno
    if err == EAGAIN or err == EINTR:
      return -1  # Retry later
    return 0     # Treat as EOF

proc collectExitCode*(mp: var ManagedProcess) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reap the child process and collect exit code. Call after EOF on stdout.
  if mp.finished:
    return
  var status: cint = 0
  let ret = waitpid(mp.pid, status, 0)
  if ret > 0:
    if WIFEXITED(status):
      mp.exitCode = WEXITSTATUS(status)
    else:
      mp.exitCode = -1
    mp.finished = true
  # Close stdout read-end FD
  if mp.stdoutRead >= 0:
    discard close(mp.stdoutRead)
    mp.stdoutRead = -1

proc killManaged*(mp: var ManagedProcess) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Kill a running process and clean up FDs.
  if not mp.finished:
    discard posix.kill(mp.pid, SIGKILL)
    var status: cint = 0
    discard waitpid(mp.pid, status, WNOHANG)
    mp.finished = true
    mp.exitCode = -1
  if mp.stdoutRead >= 0:
    discard close(mp.stdoutRead)
    mp.stdoutRead = -1
  if mp.stdinWrite >= 0:
    discard close(mp.stdinWrite)
    mp.stdinWrite = -1

proc closeManaged*(mp: var ManagedProcess) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Clean up all resources. Call after process is finished and output consumed.
  if mp.stdoutRead >= 0:
    discard close(mp.stdoutRead)
    mp.stdoutRead = -1
  if mp.stdinWrite >= 0:
    discard close(mp.stdinWrite)
    mp.stdinWrite = -1

{.pop.}
