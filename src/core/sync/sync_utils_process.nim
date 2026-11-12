import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/utils/constants
import core/trusted/axiom_pragmas
import core/types/hubs/sync_resource_hub
import infrastructure/logging_facade
import std/locks
import std/os
import std/osproc
import std/posix as posixLib
import std/streams
import std/strutils
import std/times
import std/winlean
export sync_resource_hub

# @axiom-hint: lean="lpBuffer_ullTotalPhys ≥ 0 ∧ lpBuffer_ullAvailPhys ≥ 0 ∧ lpBuffer_ullTotalPageFile ≥ 0 ∧ lpBuffer_ullAvailPageFile ≥ 0 ∧ lpBuffer_ullTotalVirtual ≥ 0 ∧ lpBuffer_ullAvailVirtual ≥ 0 ∧ lpBuffer_ullAvailExtendedVirtual ≥ 0" smt="(assert (and (>= lpBuffer_ullTotalPhys 0) (>= lpBuffer_ullAvailPhys 0) (>= lpBuffer_ullTotalPageFile 0) (>= lpBuffer_ullAvailPageFile 0) (>= lpBuffer_ullTotalVirtual 0) (>= lpBuffer_ullAvailVirtual 0) (>= lpBuffer_ullAvailExtendedVirtual 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
when defined(windows):
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  func globalMemoryStatusEx(lpBuffer: var MemoryStatusEx): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GlobalMemoryStatusEx".}

const
  defaultMinAvailableMemoryBytes* = 1'i64 shl 30
  defaultHighCpuLoadRatio* = 0.85
  defaultLowCpuLoadRatio* = 0.55

# @axiom-hint: lean="limit > 0 ∧ limit ∧ limit > 0 → result = limit" smt="(assert (and (> limit 0) limit (=> (> limit 0) (= result limit))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc epochMilliseconds*(): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  int64(epochTime() * 1000.0)

## Acquire Resource Semaphore Timeout.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireResourceSemaphoreTimeout*(
  semaphore: ptr ResourceSemaphore;
  timeoutMs: int = resourceSemaphoreTimeoutMs
) {.raises: [ResourceTimeoutError, ResourceLimitError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Acquire a semaphore slot with a hard deadline. Raises on timeout or limit=0.
  let deadline = epochMilliseconds() + int64(timeoutMs)
  while true:
    acquire(semaphore[].gate)
    if semaphore[].limit <= 0:
      release(semaphore[].gate)
      raise newException(ResourceLimitError,
        "ResourceSemaphore limit=0 — guaranteed deadlock prevented")
    if semaphore[].active < semaphore[].limit:
      inc semaphore[].active
      release(semaphore[].gate)
      return
    release(semaphore[].gate)
    sleep(1)
    if epochMilliseconds() >= deadline:
      raise newException(ResourceTimeoutError,
        "ResourceSemaphore acquire timed out after " & $timeoutMs & "ms")

## Acquire Ticket.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807 ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807)) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807))))"
# @axiom-hint: lean="semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireTicket*(
  semaphore: ptr ResourceSemaphore;
  timeoutMs: int = resourceSemaphoreTimeoutMs
): ResourceTicket {.raises: [ResourceTimeoutError, ResourceLimitError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  acquireResourceSemaphoreTimeout(semaphore, timeoutMs)
  ResourceTicket(semaphore: semaphore, acquired: true)


## Terminate Process Force.
# @axiom-hint: lean="pid > 0 ∧ true" smt="(assert (and (> pid 0) true))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc terminateProcessForce*(
  process: Process;
  gracePeriodMs: int = processKillGracePeriodMs
) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## SIGTERM -> wait gracePeriod -> SIGKILL escalation.
  ## Guarantees the process is dead or dying when this returns.
  if process.isNil: return
  try:
    terminate(process)  # SIGTERM
  except CatchableError as e:
    logWarn("sync_utils_process", "terminateProcessForce: SIGTERM failed for process — continuing to escalation: " & e.msg)
  let deadline = epochMilliseconds() + int64(gracePeriodMs)
  while true:
    try:
      if peekExitCode(process) != -1: return  # exited cleanly
    except CatchableError as e:
      logWarn("sync_utils_process", "terminateProcessForce: peekExitCode failed during polling — continuing: " & e.msg)
    if epochMilliseconds() >= deadline:
      break
    sleep(50)
  # SIGTERM ignored -> SIGKILL
  when defined(posix):
    try:
      let pid = processID(process)
      if pid > 0:
        let _ = posixLib.kill(cint(pid), cint(9))  # SIGKILL
    except CatchableError as e:
      logWarn("sync_utils_process", "terminateProcessForce: SIGKILL failed — process may still be running: " & e.msg)
  else:
    try:
      kill(process)
    except CatchableError as e:
      logWarn("sync_utils_process", "terminateProcessForce: Windows kill failed — process may still be running: " & e.msg)

## Kill Managed Process.
# @axiom-hint: lean="pid > 0 ∧ (pid ≥ 0) ∧ external_io_isolated" smt="(assert (and (> pid 0) (>= pid 0) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc killManagedProcess*(process: Process) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  if process.isNil:
    return
  try:
    when defined(windows):
      var pid = 0
      pid = processID(process)
      if pid > 0:
        let _ = execCmdEx("taskkill /PID " & $pid & " /T /F")
      else:
        terminateProcessForce(process)
    else:
      terminateProcessForce(process)
  except CatchableError as e:
    logWarn("sync_utils_process", "killManagedProcess: exception during kill — process may still be running: " & e.msg)

## Run Process With Timeout.
# @axiom-hint: lean="command.length = 0 ∧ input.length > 0 ∧ timeoutMs > 0 ∧ exitCode ≠ -1 ∧ true ∧ (output ≥ 0) ∧ (process ≥ 0) ∧ (exitCode ≥ 0) ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (= (str.len command) 0) (> (str.len input) 0) (> timeoutMs 0) (not (= exitCode -1)) true (>= output 0) (>= process 0) (>= exitCode 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runProcessWithTimeout*(
  command: string;
  args: seq[string];
  timeoutMs: int;
  input: string = ""
): ManagedProcessResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
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
    let deadlineMs =
      if timeoutMs > 0:
        epochMilliseconds() + int64(timeoutMs)
      else:
        -1'i64
    while true:
      var exitCode = -1
      exitCode = peekExitCode(process)
      if exitCode != -1:
        var output = ""
        try:
          output = process.outputStream.readAll()
        except CatchableError as e:
          logWarn("sync_utils_process", "runProcessWithTimeout: failed to read process output stream: " & e.msg)
        return ManagedProcessResult(exitCode: exitCode, timedOut: false, output: output)
      if deadlineMs >= 0'i64 and epochMilliseconds() >= deadlineMs:
        killManagedProcess(process)
        try:
          let _ = process.waitForExit(500)
        except CatchableError as e:
          logWarn("sync_utils_process", "runProcessWithTimeout: waitForExit failed during timeout cleanup: " & e.msg)
        try:
          process.close()
        except CatchableError as e:
          logWarn("sync_utils_process", "runProcessWithTimeout: process.close() failed during timeout cleanup: " & e.msg)
        return ManagedProcessResult(exitCode: -1, timedOut: true, output: "")
      sleep(5)
  except CatchableError as e:
    if not process.isNil:
      killManagedProcess(process)
      try:
        let _ = process.waitForExit(500)
      except CatchableError as e:
        logWarn("sync_utils_process", "runProcessWithTimeout: waitForExit failed during exception cleanup: " & e.msg)
      try:
        process.close()
      except CatchableError as e:
        logWarn("sync_utils_process", "runProcessWithTimeout: process.close() failed during exception cleanup: " & e.msg)
    return ManagedProcessResult(exitCode: -1, timedOut: false, output: e.msg)

## Read Current Rss Bytes.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readCurrentRssBytes*(): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(linux):
    var rss: int64 = 0'i64
    let path = "/proc/self/status"
    if fileExists(path):
      try:
        for line in lines(path):
          if line.startsWith("VmRSS:"):
            let parts = line.splitWhitespace()
            if parts.len >= 2:
              rss = parseBiggestInt(parts[1]) * 1024
              break
      except CatchableError as e:
        logWarn("sync_utils_process", "readCurrentRssBytes: failed to read /proc/self/status: " & e.msg)
    return rss
  else:
    return 0'i64

## Read System Cpu Load Ratio.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readSystemCpuLoadRatio*(): float {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(linux):
    var ratio: float = 0.0
    let path = "/proc/stat"
    if fileExists(path):
      try:
        let f = open(path, fmRead)
        let line = f.readLine()
        f.close()
        if line.startsWith("cpu "):
          let parts = line.splitWhitespace()
          if parts.len >= 5:
            let user = parseBiggestInt(parts[1])
            let nice = parseBiggestInt(parts[2])
            let system = parseBiggestInt(parts[3])
            let idle = parseBiggestInt(parts[4])
            let total = user + nice + system + idle
            if total > 0:
              ratio = 1.0 - (idle.float / total.float)
      except CatchableError as e:
        logWarn("sync_utils_process", "readSystemCpuLoadRatio: failed to read /proc/stat: " & e.msg)
    return ratio
  else:
    return 0.0

## Get Current Thread Id.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getCurrentThreadId*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(posix):
    return int(getThreadId())
  else:
    return 0

## renameat2 atomic-exchange primitive (Linux).
# The raw Linux syscall number for renameat2(2), per architecture.
# The generic syscall(2) shim takes the syscall number as its first
# argument, so routing AT_FDCWD there (as a naive "dirfd" would) is
# wrong and fails with EINVAL even on filesystems that support the
# exchange itself.
proc renameat2Exchange*(oldpath, newpath: cstring): cint {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Swap two paths atomically via renameat2(2) with RENAME_EXCHANGE.
  ## Returns 0 on success, nonzero errno-style on failure (or -1 when
  ## renameat2 is unavailable on the platform).
  when defined(linux):
    const AT_FDCWD: cint = -100
    const RENAME_EXCHANGE: cint = 2
    when defined(amd64) or defined(x86_64):
      const renRENAMEAT2 = 316
    elif defined(i386) or defined(x86):
      const renRENAMEAT2 = 353
    elif defined(arm64) or defined(aarch64) or defined(riscv64):
      const renRENAMEAT2 = 276
    elif defined(arm) or defined(arm32):
      const renRENAMEAT2 = 382
    else:
      {.error: "renameat2 syscall number not defined for this architecture".}
    func rawSyscall(
      number: cint; olddirfd: cint; oldpath: cstring;
      newdirfd: cint; newpath: cstring; flags: cint
    ): cint {.importc: "syscall", header: "<unistd.h>".}
    rawSyscall(renRENAMEAT2, AT_FDCWD, oldpath, AT_FDCWD, newpath, RENAME_EXCHANGE)
  else:
    -1


