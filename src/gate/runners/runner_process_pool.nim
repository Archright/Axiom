import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Process Pool Utilities — Hybrid Malebolgia + Process Scheduler
##
## Provides ``CmdSpec``, ``runBatch``, and process-spawning helpers for
## bounded-parallelism execution of OS commands.
##
## Phase Φ1-C: Migrated Light/Medium gates to malebolgia thread pool.
## Heavy gates retain startProcess + polling for OS-level isolation.
##
## Malebolgia integration pattern (from pipeline.nim, loop_driver.nim):
## - Heap-allocate read-only context via `create()`, pass as `ptr`
## - Gcsafe wrapper takes only gcsafe args (ptr, string, int)
## - `{.cast(gcsafe).}` inside wrapper for non-gcsafe body

import std/os
import std/osproc
import std/times
import gate/types
# axiomIoBoundary
import malebolgia
import core/trusted/axiom_pragmas
when defined(posix):
  import std/posix

# ============================================================================
# Types
# ============================================================================

type
  CmdSpec* = object
    cmd*: string
    args*: seq[string]
    timeoutMs*: int  ## DEBT#039: per-command wall-clock timeout in milliseconds.
                     ## 0 = no timeout (infinite). Default: 30_000 (30s).
    weight*: GateWeight  ## Concurrency cost for hybrid scheduling.
                         ## gwLight/gwMedium → malebolgia thread pool.
                         ## gwHeavy → startProcess + polling.
    captureOutput*: bool  ## When true, capture child stdout/stderr into
                          ## GateTaskResult instead of inheriting the parent's
                          ## streams. Used by nim_check_runner for diagnostics.
    file*: string         ## Optional per-command label (e.g. source file being
                          ## checked) surfaced in GateTaskResult for diagnostics.

  ## Read-only context for malebolgia gate workers.
  ## Heap-allocated, passed as ptr — all fields are value types.
  GateTaskContext = object
    spec: CmdSpec
    repoRoot: string
    index: int

  ## Per-task result from malebolgia thread. Value type — safe for spawn return.
  GateTaskResult* = object
    index: int
    exitCode*: int
    stdout*: string  ## Captured child output (only when CmdSpec.captureOutput).
    stderr*: string  ## Empty under poStdErrToStdOut (merged into stdout).
    file*: string    ## Echo of CmdSpec.file for diagnostics.

const DefaultCmdTimeoutMs* = 30_000  ## 30 seconds (DEBT#039)

const MalebolgiaTimeoutSecs* = 30  ## Global timeout for Light/Medium batch
const HeavyThresholdMs* = 10_000    ## Commands >=10s default to Heavy path

# ============================================================================
# Constructors
# ============================================================================

func cmdSpec*(cmd: string; args: seq[string];
              timeoutMs: int = DefaultCmdTimeoutMs;
              weight: GateWeight = gwLight;
              captureOutput: bool = false;
              file: string = ""): CmdSpec =
  ## Convenience constructor with default 30s timeout (DEBT#039).
  ## Default weight is gwLight — callers needing Heavy isolation
  ## must pass ``weight = gwHeavy`` explicitly.
  CmdSpec(cmd: cmd, args: args, timeoutMs: timeoutMs, weight: weight,
          captureOutput: captureOutput, file: file)

func isHeavy*(spec: CmdSpec): bool =
  ## Determine if a command should use process-level isolation.
  ## Heavy classification: explicit gwHeavy weight OR timeout >= 10s.
  spec.weight == gwHeavy or spec.timeoutMs >= HeavyThresholdMs

# ============================================================================
# Malebolgia Thread Pool Path (Light/Medium Gates)
# ============================================================================

proc runGateInProcess(ctx: ptr GateTaskContext): GateTaskResult
    {.gcsafe, used, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a gate command in a malebolgia thread.
  ## Each thread spawns a child process and waits for completion.
  ## No ``nice`` priority wrapping — thread pool handles scheduling.
  ## For Light/Medium gates that don't need Heavy process isolation.
  ##
  ## When ``captureOutput`` is set, child output is captured via a
  ## byte-oriented drain (poll + posix.read). This is deadlock-safe against
  ## partial lines: Stream.readLine blocks until LF, so a child that emits a
  ## partial line and pauses would deadlock a readLine-based drain. poll()
  ## returns immediately and read() consumes only available bytes, so no LF is
  ## ever awaited. Reference implementation: z3_pool.z3ExecPersistent.
  {.cast(gcsafe).}:
    {.push warning[BareExcept]:off.}
    try:
      let cap = ctx.spec.captureOutput
      let opts = if cap:
        {poStdErrToStdOut, poUsePath}
      else:
        {poParentStreams, poUsePath}
      let p = startProcess(ctx.spec.cmd,
                          args = ctx.spec.args,
                          workingDir = ctx.repoRoot,
                          options = opts)
      var exitCode: int
      var captured = ""
      when defined(posix):
        if cap:
          # ---- Byte-oriented drain: never waitForExit-then-readAll, never readLine. ----
          let fd = cint(outputHandle(p))
          if fd >= 0:
            var buf: array[8192, char]
            var timedOut = false
            let deadline =
              if ctx.spec.timeoutMs > 0:
                getTime() + initDuration(milliseconds = ctx.spec.timeoutMs)
              else:
                getTime() + initDuration(hours = 1)
            while true:
              if ctx.spec.timeoutMs > 0 and getTime() > deadline:
                timedOut = true
                p.terminate()
                sleep(50)
                if p.running():
                  p.kill()
                break
              var gotData = false
              # Drain every currently-available byte (including trailing data on
              # POLLHUP/EOF). poll+read is non-blocking — partial lines are
              # accumulated, never awaited.
              while true:
                var pfd: TPollfd
                pfd.fd = fd
                pfd.events = cshort(POLLIN)
                pfd.revents = 0
                var n = 0
                if poll(addr pfd, 1, 0) == 1 and
                   (pfd.revents and (POLLIN or POLLHUP)) != 0:
                  n = posix.read(fd, addr buf[0], buf.len.cint)
                if n > 0:
                  for i in 0 ..< n:
                    captured.add(buf[i])
                  gotData = true
                else:
                  break
              if gotData:
                continue
              if not p.running():
                # Process exited; one final read for straggler bytes, then stop.
                var pfd: TPollfd
                pfd.fd = fd
                pfd.events = cshort(POLLIN)
                pfd.revents = 0
                if poll(addr pfd, 1, 0) == 1 and
                   (pfd.revents and (POLLIN or POLLHUP)) != 0:
                  let n = posix.read(fd, addr buf[0], buf.len.cint)
                  if n > 0:
                    for i in 0 ..< n:
                      captured.add(buf[i])
                    continue
                break
              sleep(5)
            exitCode = if timedOut: -1 else: p.waitForExit()
          else:
            exitCode = p.waitForExit()
        else:
          discard
      else:
        discard
      if not cap or not defined(posix):
        if ctx.spec.timeoutMs > 0:
          let deadline = getTime() + initDuration(milliseconds = ctx.spec.timeoutMs)
          while p.running():
            if getTime() > deadline:
              p.terminate()
              sleep(50)  # Grace period for SIGTERM
              if p.running():
                p.kill()
              exitCode = -1  # Convention: -1 = timeout
              break
            sleep(10)
          if exitCode != -1:
            exitCode = p.waitForExit()
        else:
          exitCode = p.waitForExit()
      p.close()
      result = GateTaskResult(index: ctx.index, exitCode: exitCode,
                              stdout: captured, file: ctx.spec.file)
    except CatchableError:
      result = GateTaskResult(index: ctx.index, exitCode: -1,
                              file: ctx.spec.file)
    except Exception:
      result = GateTaskResult(index: ctx.index, exitCode: -1,
                              file: ctx.spec.file)
    {.pop.}

# ============================================================================
# Byte-drain helpers (shared by Light capture path and Heavy capture path)
# ============================================================================

when defined(posix):
  proc drainAvailableBytes(p: Process): string {.raises: [].} =
    ## Non-blocking read of all currently-available bytes from p's stdout pipe.
    ## Returns "" when nothing is ready. Uses poll(fd,1,0) + posix.read so it
    ## never blocks and never awaits a newline — partial lines are consumed
    ## as they arrive. Deadlock-safe against the readLine behavior.
    let fd = cint(outputHandle(p))
    if fd < 0:
      return ""
    var buf: array[8192, char]
    var acc = ""
    while true:
      var pfd: TPollfd
      pfd.fd = fd
      pfd.events = cshort(POLLIN)
      pfd.revents = 0
      var n = 0
      if poll(addr pfd, 1, 0) == 1 and (pfd.revents and (POLLIN or POLLHUP)) != 0:
        n = posix.read(fd, addr buf[0], buf.len.cint)
      if n > 0:
        for i in 0 ..< n:
          acc.add(buf[i])
      else:
        break
    result = acc
else:
  proc drainAvailableBytes(p: Process): string {.raises: [].} =
    result = ""

# ============================================================================
# Process Polling Path (Heavy Gates) — retained from original
# ============================================================================

proc launchProcess(spec: CmdSpec; repoRoot: string): Process {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Spawn a child process wrapped with ``nice -n 10`` (Layer 4: CPU priority).
  ## Used only for Heavy gates that need full OS-level isolation.
  ## When captureOutput is set, child output is redirected to a pipe (drained
  ## by drainAvailableBytes in the poll loop); otherwise it inherits the
  ## parent's streams.
  let opts = if spec.captureOutput:
    {poStdErrToStdOut, poUsePath}
  else:
    {poParentStreams, poUsePath}
  startProcess("nice", args = @["-n", "10", spec.cmd] & spec.args,
               workingDir = repoRoot, options = opts)

proc reapCompletedProcesses(running: var seq[(Process, int, times.Time, string)];
                           result: var seq[GateTaskResult];
                           commands: seq[CmdSpec]) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Poll running processes: collect exit codes for finished ones,
  ## enforce DEBT#039 per-command timeout on stragglers.
  ## Modifies ``running`` and ``result`` in-place. The 4th tuple element is the
  ## accumulated captured output (populated by the poll loop via
  ## drainAvailableBytes); a final non-blocking drain flushes stragglers here.
  var i = 0
  while i < running.len:
    if not running[i][0].running():
      running[i][3].add(drainAvailableBytes(running[i][0]))  # flush stragglers
      let code = running[i][0].waitForExit()
      running[i][3].add(drainAvailableBytes(running[i][0]))  # post-exit leftovers
      result[running[i][1]] = GateTaskResult(
        index: running[i][1], exitCode: code, stdout: running[i][3],
        file: commands[running[i][1]].file)
      running[i][0].close()
      running.del(i)
    else:
      # DEBT#039: Check per-command timeout
      let timeoutMs = commands[running[i][1]].timeoutMs
      if timeoutMs > 0:
        let elapsedMs = (getTime() - running[i][2]).inMilliseconds
        if elapsedMs > timeoutMs:
          running[i][0].terminate()
          sleep(50)  # Grace period for SIGTERM
          if running[i][0].running():
            running[i][0].kill()
          running[i][3].add(drainAvailableBytes(running[i][0]))
          result[running[i][1]] = GateTaskResult(
            index: running[i][1], exitCode: -1,  # Convention: -1 = timeout
            stdout: running[i][3], file: commands[running[i][1]].file)
          running[i][0].close()
          running.del(i)
          continue
      inc i

# ============================================================================
# Hybrid Batch Executor
# ============================================================================

proc runBatch*(commands: seq[CmdSpec]; repoRoot: string;
 maxJobs: int): seq[GateTaskResult] =
  ## Execute commands in parallel with hybrid scheduling.
  ##
  ## Light/Medium gates (gwLight/gwMedium): run via malebolgia thread pool.
  ## Heavy gates (gwHeavy): run via startProcess + polling with nice priority.
  ##
  ## Returns per-command results in the same order as commands. Callers read
  ## ``.exitCode`` (0 = success) and, when ``captureOutput`` was set, ``.stdout``.
  ##
  ## Memory-aware: checks MemAvailable every ~50ms and throttles spawning
  ## if system memory drops below safe threshold (AXIOM_MEM_HEADROOM).
  ## DEBT#009: Also applies global concurrency budget from types.nim to
  ## prevent multiplicative overcommit when multiple gates run concurrently.
  ## DEBT#039: Per-command timeout -- processes exceeding their timeoutMs
  ## are terminated and assigned exit code -1.
  result = newSeq[GateTaskResult](commands.len)
  if commands.len == 0:
    return

  # ── Classify tasks ──────────────────────────────────────────────────────
  # Separate into malebolgia (Light/Medium) and process (Heavy) queues.
  # Nim check commands are isHeavy (default 30s timeout >= HeavyThresholdMs),
  # so they route to the Heavy path — the same path the original parallel gate
  # used. The Heavy path preserves maxJobs throttling + memory-aware + global
  # budget that the malebolgia path does not apply, and avoids malebolgia's 30s
  # master timeout on large batches.
  var lightIndices: seq[int]  # indices into commands for malebolgia path
  var heavyIndices: seq[int]  # indices into commands for process path

  for i, cmd in commands:
    if cmd.isHeavy:
      heavyIndices.add(i)
    else:
      lightIndices.add(i)

  # ── Phase 1: Malebolgia thread pool (Light/Medium) ─────────────────────
  # Data-oriented parallelism: heap-allocate read-only context per task,
  # pass as ptr to malebolgia worker threads. All value types — safe for
  # spawn return. No shared mutable state.
  if lightIndices.len > 0:
    var ctxPtrs: seq[ptr GateTaskContext] = @[]
    for idx in lightIndices:
      let ctx = create(GateTaskContext)
      ctx.spec = commands[idx]
      ctx.repoRoot = repoRoot
      ctx.index = idx
      ctxPtrs.add(ctx)

    var taskResults = newSeq[GateTaskResult](lightIndices.len)

    block malebolgiaExecution:
      var m = createMaster(initDuration(seconds = MalebolgiaTimeoutSecs))
      m.awaitAll:
        for t in 0 ..< ctxPtrs.len:
          m.spawn runGateInProcess(ctxPtrs[t]) -> taskResults[t]

    # Collect results
    for tr in taskResults:
      result[tr.index] = tr

    # Deallocate contexts
    for ctx in ctxPtrs:
      dealloc(ctx)

  # ── Phase 2: Process polling (Heavy) ───────────────────────────────────
  # Retained from original implementation. Heavy gates need OS-level
  # isolation (RLIMIT memory, nice priority, independent process group).
  if heavyIndices.len > 0:
    var running: seq[(Process, int, times.Time, string)] = @[]  # (Proc, cmdIdx, start, captured)
    var nextIdx = 0
    var pollCount = 0
    var effectiveMaxJobs = maxJobs

    while nextIdx < heavyIndices.len or running.len > 0:
      # Layer 1: Memory-aware spawn gate (check every 5th poll ~50ms)
      if pollCount mod 5 == 0:
        let memBased = safeMaxJobs(maxJobs)
        # DEBT#009: Apply global concurrency budget.
        # Global budget ensures total workers across concurrent gates
        # does not exceed CPU cores / 2 (prevents OOM + GPU starvation).
        let globalBudget = computeGlobalConcurrencyBudget()
        effectiveMaxJobs = max(1, min(memBased, globalBudget))

      # Spawn up to effectiveMaxJobs processes
      while running.len < effectiveMaxJobs and nextIdx < heavyIndices.len:
        let cmdIdx = heavyIndices[nextIdx]
        let p = launchProcess(commands[cmdIdx], repoRoot)
        running.add((p, cmdIdx, getTime(), ""))
        inc nextIdx

      if running.len > 0:
        # Drain any available output for capture commands (non-blocking), then
        # poll for completed processes (DEBT#039: with per-command timeout).
        for i in 0 ..< running.len:
          running[i][3].add(drainAvailableBytes(running[i][0]))
        reapCompletedProcesses(running, result, commands)
        if running.len > 0:
          sleep(10)  # 10ms poll interval -- negligible CPU, responsive cleanup
      inc pollCount

{.pop.}
