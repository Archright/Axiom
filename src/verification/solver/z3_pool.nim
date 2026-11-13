import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.experimental: "codeReordering".}
# Z3 Persistent Process Pool
# Extracted from gateway.nim
import core/axiom_pragmas
import core/trusted/architecture_invariants

{.pragma: safeDiscard.}
import core/parsers/safe_parsers
import core/proof/proof_budget
import core/crypto/hash_kernel
import core/results
import core/solver/z3_telemetry
import core/sync/sync_utils_process
import core/types/z3_solver_config
import core/utils/constants
import std/locks
import std/options
import std/os
import std/osproc
import std/posix
import std/streams
import std/strutils
import std/tempfiles
import std/times
import infrastructure/logging_facade
import core/trusted/stdlib_shield
import core/trusted/solver_invocation
# axiomIoBoundary

const
  z3ReadStepTimeoutMs = 50
  maxPipePayloadSize* = 60_000  ## 60KB — safe margin below OS pipe buffer (~64KB).
                                ## Payloads exceeding this bypass the persistent pool
                                ## stdin path to prevent IPC pipe deadlock.

when defined(posix):
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(tv ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= tv 0) (>= result 0)))"
  proc z3WorkerWaitData(process: Process; deadlineMs: int64): bool =
    ## Block until the Z3 worker stdout is readable, or the absolute deadline
    ## (epochMilliseconds) passes. Uses poll() instead of select()/FD_SET to
    ## avoid buffer overflow when file descriptors exceed FD_SETSIZE (1024).
    ## The OS owns the wait (one poll(2) per remaining window — no busy-wake);
    ## POLLHUP/POLLERR also report readiness so the caller's read() loop keeps
    ## sole authority over EOF/error classification, and a negative poll
    ## result (EINTR et al.) recomputes the window against the same deadline:
    ## retries can never extend the wait past it.
    let h = outputHandle(process)
    if h < 0: return false
    while true:
      let remaining = deadlineMs - epochMilliseconds()
      if remaining <= 0: return false
      var pfd: TPollfd
      pfd.fd = cint(h)
      pfd.events = cshort(POLLIN)
      pfd.revents = 0
      let rc = poll(addr pfd, 1, cint(min(remaining, int64(high(int32)))))
      if rc == 1:
        return (pfd.revents and (POLLIN or POLLHUP or POLLERR)) != 0
      if rc == 0:
        return false
else:
  proc z3WorkerWaitData(process: Process; deadlineMs: int64): bool =
    ## Non-POSIX fallback: poll the stream in small steps until the deadline.
    while epochMilliseconds() < deadlineMs:
      if hasData(process): return true
      sleep(5)
    false
type
  Z3ScopeEntry = object
    rawQuery: string
    scopeDepth: int

  Z3ScopeTracker = object
    entries: seq[Z3ScopeEntry]
    pushDepth: int
    enabled: bool

  Z3PersistentWorker = object
    process: Process
    input: Stream
    output: Stream
    gate: Lock
    scopeTracker: Z3ScopeTracker
    ready: bool  ## Readiness state barrier: true after successful spawn, false on any error/restart
    busy: bool   ## Per-query exclusive lease: true while one query owns this
                 ## worker's stdin/stdout; selectZ3WorkerIndex never hands out
                 ## a busy worker (guard: pool.gate)

  Z3PersistentPool = object
    command: string
    args: seq[string]
    maxWorkers: int
    workers: seq[Z3PersistentWorker]
    nextWorker: int
    nextQueryId: int64
    gate: Lock

  Z3PersistentPoolManager = object
    pool: Z3PersistentPool
    poolReady: bool
    bootstrapGate: Lock
    bootstrapGateReady: bool
var z3ManagerPrivate: ptr Z3PersistentPoolManager

type
  Z3ExecutionMode* = enum
    zmRaw          ## (reset)을 강제하는 일회성 쿼리 (기본값, 기존 동작)
    zmIncremental  ## (reset) 건너뛰고 push/pop 스코프 트래커 사용

  SmtPhase* = enum
    spBmc            ## 8000ms liveness ceiling; rlimit is the deterministic solve budget
    spBaseCase       ## 2000ms liveness ceiling; rlimit is the deterministic solve budget
    spInductiveStep  ## 5000ms liveness ceiling; rlimit is the deterministic solve budget

  SmtBudget* = object
    timeoutMs*: int
    memoryLimitMb*: int

proc recordPush*(tracker: var Z3ScopeTracker) {.raises: [], used.} =
  ## Record a (push) command sent to the Z3 worker.
  ## Future API for incremental push/pop scope management.
  ## Currently unused — retained as part of the public scope-tracking API.
  if tracker.enabled:
    tracker.pushDepth += 1

proc recordPop*(tracker: var Z3ScopeTracker; n: int = 1) {.raises: [], used.} =
  ## Record n (pop) commands; evict assertions that fell out of scope.
  ## Future API for incremental push/pop scope management.
  ## Currently unused — retained as part of the public scope-tracking API.
  if tracker.enabled:
    tracker.pushDepth -= n
    var newEntries: seq[Z3ScopeEntry]
    for e in tracker.entries:
      if e.scopeDepth <= tracker.pushDepth:
        newEntries.add(e)
    tracker.entries = newEntries

proc recordAssertion*(tracker: var Z3ScopeTracker; rawQuery: string) {.raises: [].} =
  ## Record an assertion by its raw query at the current scope depth.
  if tracker.enabled:
    tracker.entries.add(Z3ScopeEntry(rawQuery: rawQuery, scopeDepth: tracker.pushDepth))

proc replayCommands*(tracker: Z3ScopeTracker): seq[string] {.raises: [].} =
  ## Produce a list of SMT-LIB commands to restore the tracked scope state.
  ## Each live assertion gets wrapped in a (push)/(pop) pair.
  result = @[]
  if not tracker.enabled:
    return
  for entry in tracker.entries:
    result.add("(push)")
    result.add(entry.rawQuery)
    result.add("(pop)")

proc scopeDepth*(tracker: Z3ScopeTracker): int {.raises: [].} =
  ## Current push depth of the tracker.
  tracker.pushDepth

proc resetTracker*(tracker: var Z3ScopeTracker) {.raises: [], used.} =
  ## Clear all tracked state (called after a full (reset)).
  ## Future API: explicitly reset the scope tracker when a full Z3 `(reset)`
  ## is issued. Currently unused — `startZ3WorkerProcess` handles tracker
  ## reset via direct struct reassignment instead.

# ── Thread-Local Z3 Worker (Wave E+B) ──────────────────────────────
# Each thread owns a single Z3 process with its own scope context.
# When the worker restarts, scope state is replayed automatically.
type
  ThreadZ3Worker = object
    process: Process
    inputStream: Stream
    outputStream: Stream
    scopeTracker: Z3ScopeTracker
    initialized: bool

var threadZ3Worker {.threadvar.}: ThreadZ3Worker

proc isAlive*(w: ThreadZ3Worker): bool {.raises: [].} =
  ## Check if the thread-local worker process is alive.
  not w.process.isNil and w.initialized

proc resetState*(w: var ThreadZ3Worker) {.raises: [].} =
  ## Mark the worker as uninitialized; scope tracker is preserved.
  w.process = nil
  w.inputStream = nil
  w.outputStream = nil
  w.initialized = false

# Forward declarations — implementations below safeCloseStream (line ~308)
proc getThreadZ3Worker*(): var ThreadZ3Worker {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc initThreadZ3Worker*(worker: var ThreadZ3Worker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc stopThreadZ3Worker*(worker: var ThreadZ3Worker) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].}
proc replayScopeToWorker*(worker: var ThreadZ3Worker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# ── Safe wrappers: exception → Result ──────────────────────────────
type
  Z3HealthStatus* = enum
    zhsHealthy       ## Both sat/unsat probes succeeded
    zhsInfraCrash    ## Process died, EPIPE, or timed out
    zhsLogicalFail   ## Z3 responded but wrong answer
    zhsNotFound      ## Z3 binary not resolvable

  Z3HealthProbeResult* = object
    status*: Z3HealthStatus
    z3Path*: string
    satProbe*: ManagedProcessResult
    unsatProbe*: ManagedProcessResult

  VerifiedZ3Pool* = object
    ## Compile-time gate token. Created only after probeZ3Health() == zhsHealthy.
    ## Functions accepting this type guarantee Z3 was healthy at init time.
    z3Path*: string
{.push raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
const Z3HealthProbeTimeoutMs* = 2000
proc probeZ3Health*(): Z3HealthProbeResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Deterministic Z3 health check using canonical SMT-LIB2 queries.
  ## Uses existing runProcessWithTimeout for zombie/deadlock protection.
  let z3Path = resolveZ3Path()
  if z3Path.len == 0 or not fileExists(z3Path):
    return Z3HealthProbeResult(status: zhsNotFound, z3Path: z3Path)

  let satProbe = runProcessWithTimeout(
    z3Path, @["-smt2", "-in"], Z3HealthProbeTimeoutMs,
    input = "(declare-fun x () Int)\n(assert (= x x))\n(check-sat)\n")

  let unsatProbe = runProcessWithTimeout(
    z3Path, @["-smt2", "-in"], Z3HealthProbeTimeoutMs,
    input = "(declare-fun x () Int)\n(assert (and (> x 0) (< x 0)))\n(check-sat)\n")

  if satProbe.timedOut or unsatProbe.timedOut or
     satProbe.exitCode == -1 or unsatProbe.exitCode == -1:
    return Z3HealthProbeResult(status: zhsInfraCrash, z3Path: z3Path,
      satProbe: satProbe, unsatProbe: unsatProbe)

  # Read the probes through the one classifier. Comparing the whole stdout to a
  # literal token would both miss a verdict buried under elaboration and score
  # an error-bearing stream as a healthy solver — and an undeclared `x` in this
  # very probe is what produced `(error "unknown constant x")` alongside a `sat`
  # on Z3 4.13.3, marking a working solver `zhsLogicalFail` on every run.
  if solverResponse(satProbe.output, satProbe.exitCode) != srSat or
     solverResponse(unsatProbe.output, unsatProbe.exitCode) != srUnsat:
    return Z3HealthProbeResult(status: zhsLogicalFail, z3Path: z3Path,
      satProbe: satProbe, unsatProbe: unsatProbe)

  return Z3HealthProbeResult(status: zhsHealthy, z3Path: z3Path,
    satProbe: satProbe, unsatProbe: unsatProbe)
# Forward declarations (defined later in this file)
proc z3EnsurePersistentPool*(desiredWorkers: int)
proc z3ExecPersistent*(query: string; timeoutMs: int; desiredWorkers: int = 1; enableProofs: bool = false; queryType: string = "unknown"; cegarIters: int = 0;
    canonicalEnvelopeDigest: var string; transportPayloadDigest: var string): Result[string, string] {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].}

proc initVerifiedZ3Pool*(): Option[VerifiedZ3Pool] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Factory: returns none if Z3 is unhealthy. The ONLY way to create VerifiedZ3Pool.
  let probe = probeZ3Health()
  if probe.status != zhsHealthy:
    return none(VerifiedZ3Pool)
  z3EnsurePersistentPool(1)
  return some(VerifiedZ3Pool(z3Path: probe.z3Path))
proc execZ3Verified*(vp: VerifiedZ3Pool, query: string,
    timeoutMs: int = 30000): Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## z3ExecPersistent wrapper that classifies Z3 output.
  ## Returns ok(output) only for "unsat" (proven property).
  ## Returns err for sat/unknown/timeout/error — never silently succeeds.
  ## Phase 1B: Fail-safe correction — Z3 unknown → verification failure.
  var poolCanonicalDigest, poolTransportDigest: string
  let res = z3ExecPersistent(query, timeoutMs,
    canonicalEnvelopeDigest = poolCanonicalDigest, transportPayloadDigest = poolTransportDigest)
  if res.isErr:
    return err("z3-error: " & res.error())
  let output = res.get().strip()
  case solverResponse(output)
  of srUnsat:   ok(output)
  of srSat:     err("counterexample-found")
  of srUnknown: err("z3-unknown")
  of srNoDecision: err("z3-error: no solver decision: " & output)

proc queryZ3ViaFile*(smtQuery: string; repoRoot: string; irHash: string): (string, string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## File-based Z3 execution — avoids IPC deadlock by using file input instead of stdin pipe.
  ## PID-based naming prevents race conditions in parallel execution.
  let absRepoRoot = absolutePath(repoRoot)
  let debugDir = absRepoRoot / "logs" / "smt_debug"
  let queryPath = debugDir / (irHash & "_" & $getCurrentProcessId() & ".run.smt2")
  let debugPath = debugDir / (irHash & ".debug.smt2")

  createDir(debugDir)
  writeFile(queryPath, smtQuery)

  try:
    let z3Bin = resolveZ3Path()
    if z3Bin.len == 0:
      return ("error", "Axiom Engine Error: z3 binary not found in PATH")
    let cmd = quoteShell(z3Bin) & " " & quoteShell(queryPath)
    let (output, exitCode) = execCmdEx(cmd)

    if exitCode != 0 or solverStreamHasErrorResponse(output):
      try:
        if queryPath != debugPath:
          safeMoveFile(queryPath, debugPath)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      logError("z3_pool", "Z3 execution failed. Query isolated at: " & debugPath)
      return (output, "Z3-ExitCode: " & $exitCode)

    safeRemoveFile(queryPath)
    return (output, "")

  except CatchableError as e:
    try:
      if fileExists(queryPath):
        safeMoveFile(queryPath, debugPath)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    return ("error", "Axiom IPC Exception: " & e.msg)

proc safeInitLock(lock: var Lock): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    initLock(lock)
    ok(true)
  except CatchableError as e:
    err("initLock failed: " & e.msg)
proc safeDeinitLock(lock: var Lock): Result[bool, string] {.raises: [], safeDiscard, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    deinitLock(lock)
    ok(true)
  except CatchableError:
    ok(true)
proc safeCloseProcess(process: Process): Result[bool, string] {.safeDiscard, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    close(process)
    ok(true)
  except CatchableError:
    ok(true)
proc safePeekExitCode(process: Process): Result[int, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    ok(peekExitCode(process))
  except CatchableError as e:
    err("peekExitCode failed: " & e.msg)

proc safeCloseStream(stream: Stream) {.raises: [], safeDiscard.} =
  try:
    if stream != nil: close(stream)
  except CatchableError:
    discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)

proc safeKillAndClose(p: Process) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  try:
    if p != nil:
      killManagedProcess(p)
      # Reap zombie — must waitForExit before close
      try:
        discard p.waitForExit(500)
      except CatchableError:
        discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)
      close(p)
  except CatchableError:
    discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)

# ── Thread-Local Z3 Worker implementations (Wave E+B) ─────────────
# These depend on safeCloseStream defined above.

proc getThreadZ3Worker*(): var ThreadZ3Worker {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Lazily initialize the thread-local Z3 worker.
  ## Scope tracking is enabled when AXIOM_Z3_INCREMENTAL=1.
  if not threadZ3Worker.initialized:
    threadZ3Worker.scopeTracker.enabled = getEnv("AXIOM_Z3_INCREMENTAL") == "1"
  threadZ3Worker

proc initThreadZ3Worker*(worker: var ThreadZ3Worker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Start the Z3 process for this thread-local worker.
  try:
    worker.process = startProcess(
      command = command,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    if worker.process.isNil:
      return err("ThreadZ3Worker: startProcess returned nil")
    worker.inputStream = inputStream(worker.process)
    worker.outputStream = outputStream(worker.process)
    if worker.inputStream.isNil or worker.outputStream.isNil:
      return err("ThreadZ3Worker: streams not available")
    worker.initialized = true
    ok(true)
  except CatchableError as e:
    err("ThreadZ3Worker init failed: " & e.msg)

proc stopThreadZ3Worker*(worker: var ThreadZ3Worker) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Kill the thread-local Z3 process. Scope tracker state is preserved.
  if not worker.process.isNil:
    killManagedProcess(worker.process)
    try:
      discard worker.process.waitForExit(500)
    except CatchableError:
      discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)
    safeCloseStream(worker.inputStream)
    safeCloseStream(worker.outputStream)
    worker.process = nil
    worker.inputStream = nil
    worker.outputStream = nil
    worker.initialized = false

proc replayScopeToWorker*(worker: var ThreadZ3Worker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Restart the Z3 process and replay tracked scope context.
  ## This is the key operation: when a worker crashes/times out,
  ## the scope tracker replays push/assert/pop to restore state.
  stopThreadZ3Worker(worker)
  let initRes = initThreadZ3Worker(worker, command, args)
  if initRes.isErr:
    return initRes
  # Replay scope context if tracking is enabled
  if worker.scopeTracker.enabled:
    let cmds = worker.scopeTracker.replayCommands()
    if cmds.len > 0:
      try:
        for cmd in cmds:
          worker.inputStream.write(cmd & "\n")
        worker.inputStream.flush()
      except CatchableError as e:
        return err("scope replay failed: " & e.msg)
  ok(true)

type Z3PoolContext* = object
  pool: Z3PersistentPool
  poolReady: bool

proc `=destroy`(ctx: var Z3PoolContext) {.raises: [], tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if ctx.poolReady:
    for w in ctx.pool.workers.mitems:
      safeKillAndClose(w.process)
      safeCloseStream(w.input)
      safeCloseStream(w.output)
      discard safeDeinitLock(w.gate)
    discard safeDeinitLock(ctx.pool.gate)
    ctx.poolReady = false

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc z3Manager(): ptr Z3PersistentPoolManager {.gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if z3ManagerPrivate.isNil:
    z3ManagerPrivate = create(Z3PersistentPoolManager)
  z3ManagerPrivate

# @axiom-hint: lean="command.length ≥ 0 ∧ args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) external_io_isolated))"
proc waitForSentinel(worker: var Z3PersistentWorker; sentinel: string; timeoutMs: int): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read from Z3 stdout until sentinel appears or timeout.
  ## Uses existing lineBuffer pattern from z3ExecPersistent (no cast[string]).
  let deadline = epochMilliseconds() + timeoutMs
  var found = false
  var lineBuffer = ""
  var chunk: array[256, char]

  while epochMilliseconds() < deadline:
    if z3WorkerWaitData(worker.process, deadline):
      let n = posix.read(cint(outputHandle(worker.process)), addr chunk[0], 256)
      if n > 0:
        for i in 0..<n:
          let c = chunk[i]
          if c == '\L':
            if sentinel in lineBuffer:
              found = true
              break
            lineBuffer = ""
          elif c != '\c':
            lineBuffer.add(c)
        if found: break
      elif n == 0:
        return err("Z3 process pipe closed prematurely")

  if found: ok(true)
  else: err("Z3 sentinel timeout. Expected: " & sentinel)

# @axiom-hint: lean="false ∧ (worker ≥ 0) ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and false (>= worker 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) external_io_isolated))"
proc startZ3WorkerProcess(worker: var Z3PersistentWorker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    worker.process = startProcess(
      command = command,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    if worker.process.isNil:
      return err("startProcess returned nil")
    worker.input = inputStream(worker.process)
    worker.output = outputStream(worker.process)
    if worker.input.isNil or worker.output.isNil:
      return err("worker streams not available")
    # One-time Z3 context initialization at spawn
    worker.input.writeLine("(reset)")
    worker.input.flush()
    # Spawn barrier: wait for Z3 to complete (reset)
    const spawnSentinel = "AXIOM_Z3_SPAWN_READY"
    worker.input.writeLine("(echo \"" & spawnSentinel & "\")")
    worker.input.flush()
    let syncRes = worker.waitForSentinel(spawnSentinel, 2000)
    if syncRes.isErr:
      worker.ready = false
      return err("Z3 spawn barrier failed: " & syncRes.error)
    # R1: Preserve enabled flag — Z3ScopeTracker() default-initializes enabled=false,
    # which kills scope replay on subsequent restartZ3WorkerProcess calls.
    let wasEnabled = worker.scopeTracker.enabled
    worker.scopeTracker = Z3ScopeTracker()
    worker.scopeTracker.enabled = wasEnabled
    # Readiness state barrier: worker is Ready only after the spawn handshake
    # completes. selectZ3WorkerIndex refuses to assign queries to non-ready workers.
    worker.ready = true
    ok(true)
  except CatchableError as e:
    worker.ready = false
    err("startZ3WorkerProcess: " & e.msg)

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(worker ≥ 0)" smt="(assert (and (>= worker 0)))"
proc stopZ3WorkerProcess(worker: var Z3PersistentWorker) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  if not worker.process.isNil:
    killManagedProcess(worker.process)
    # Reap zombie — must waitForExit before close to avoid zombie processes
    try:
      discard worker.process.waitForExit(500)  # 500ms grace for reaping
    except CatchableError:
      discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)
    discard safeCloseProcess(worker.process)
    safeCloseStream(worker.input)
    safeCloseStream(worker.output)
    worker.process = nil
    worker.input = nil
    worker.output = nil

# @axiom-hint: lean="command.length ≥ 0 ∧ args.size ≥ 0 ∧ ∀ (i : Fin args.size), (args.get i).length ≥ 0" smt="(assert (and (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len args))) (>= (str.len (seq.nth args i)) 0)))))"
# @axiom-hint: lean="command.length ≥ 0 ∧ args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
# @axiom-hint: lean="false ∧ (result ≥ 0) ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and false (>= result 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
proc initZ3Worker(worker: var Z3PersistentWorker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let lockResult = safeInitLock(worker.gate)
  if lockResult.isErr:
    return lockResult
  let startResult = startZ3WorkerProcess(worker, command, args)
  if startResult.isErr:
    discard safeDeinitLock(worker.gate)
    return startResult
  ok(true)

# @axiom-hint: lean="command.length ≥ 0 ∧ args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
# @axiom-hint: lean="(∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
proc restartZ3WorkerProcess(worker: var Z3PersistentWorker; command: string; args: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stopZ3WorkerProcess(worker)
  let res = startZ3WorkerProcess(worker, command, args)
  if res.isOk and worker.scopeTracker.enabled:
    # Replay saved assertions to the fresh process
    for cmd in worker.scopeTracker.replayCommands():
      worker.input.writeLine(cmd)
      worker.input.flush()
  res

# @axiom-hint: lean="pool_command.length ≥ 0 ∧ pool_args.size ≥ 0 ∧ pool_maxWorkers ≥ -9223372036854775808 ∧ pool_maxWorkers ≤ 9223372036854775807 ∧ pool_workers.size ≥ 0 ∧ pool_nextWorker ≥ -9223372036854775808 ∧ pool_nextWorker ≤ 9223372036854775807 ∧ pool_nextQueryId ≥ -9223372036854775808 ∧ pool_nextQueryId ≤ 9223372036854775807 ∧ workerIdx ≥ -9223372036854775808 ∧ workerIdx ≤ 9223372036854775807" smt="(assert (and (>= (str.len pool_command) 0) (>= (seq.len pool_args) 0) (and (>= pool_maxWorkers -9223372036854775808) (<= pool_maxWorkers 9223372036854775807)) (>= (seq.len pool_workers) 0) (and (>= pool_nextWorker -9223372036854775808) (<= pool_nextWorker 9223372036854775807)) (and (>= pool_nextQueryId -9223372036854775808) (<= pool_nextQueryId 9223372036854775807)) (and (>= workerIdx -9223372036854775808) (<= workerIdx 9223372036854775807))))"
# @axiom-hint: lean="result = false ∧ false ∧ (result ≥ 0)" smt="(assert (and (= result false) false (>= result 0)))"
proc restartZ3PoolWorker(pool: var Z3PersistentPool; workerIdx: int): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if workerIdx < 0 or workerIdx >= pool.workers.len:
    return err("invalid worker index")
  acquire(pool.gate)
  defer:
    release(pool.gate)
  acquire(pool.workers[workerIdx].gate)
  defer:
    release(pool.workers[workerIdx].gate)
  let restartRes = restartZ3WorkerProcess(
    pool.workers[workerIdx],
    pool.command,
    pool.args
  )
  if restartRes.isErr:
    return restartRes
  # R2: Scope replay is already handled by restartZ3WorkerProcess (called above).
  # The former duplicate replay block here was removed to prevent double-replay
  # of assertions, which sent duplicate push/assert/pop commands to Z3.
  ok(true)

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc deinitZ3Worker(worker: var Z3PersistentWorker) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  stopZ3WorkerProcess(worker)
  discard safeDeinitLock(worker.gate)

# @axiom-hint: lean="pool_command.length ≥ 0 ∧ pool_args.size ≥ 0 ∧ pool_maxWorkers ≥ -9223372036854775808 ∧ pool_maxWorkers ≤ 9223372036854775807 ∧ pool_workers.size ≥ 0 ∧ pool_nextWorker ≥ -9223372036854775808 ∧ pool_nextWorker ≤ 9223372036854775807 ∧ pool_nextQueryId ≥ -9223372036854775808 ∧ pool_nextQueryId ≤ 9223372036854775807 ∧ command.length ≥ 0 ∧ args.size ≥ 0 ∧ ∀ (i : Fin args.size), (args.get i).length ≥ 0 ∧ workerCount ≥ -9223372036854775808 ∧ workerCount ≤ 9223372036854775807" smt="(assert (and (>= (str.len pool_command) 0) (>= (seq.len pool_args) 0) (and (>= pool_maxWorkers -9223372036854775808) (<= pool_maxWorkers 9223372036854775807)) (>= (seq.len pool_workers) 0) (and (>= pool_nextWorker -9223372036854775808) (<= pool_nextWorker 9223372036854775807)) (and (>= pool_nextQueryId -9223372036854775808) (<= pool_nextQueryId 9223372036854775807)) (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len args))) (>= (str.len (seq.nth args i)) 0))) (and (>= workerCount -9223372036854775808) (<= workerCount 9223372036854775807))))"
# @axiom-hint: lean="pool_command.length ≥ 0 ∧ pool_args.size ≥ 0 ∧ pool_maxWorkers ≥ -9223372036854775808 ∧ pool_maxWorkers ≤ 9223372036854775807 ∧ pool_workers.size ≥ 0 ∧ pool_nextWorker ≥ -9223372036854775808 ∧ pool_nextWorker ≤ 9223372036854775807 ∧ pool_nextQueryId ≥ -9223372036854775808 ∧ pool_nextQueryId ≤ 9223372036854775807 ∧ command.length ≥ 0 ∧ args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ workerCount ≥ -9223372036854775808 ∧ workerCount ≤ 9223372036854775807" smt="(assert (and (>= (str.len pool_command) 0) (>= (seq.len pool_args) 0) (and (>= pool_maxWorkers -9223372036854775808) (<= pool_maxWorkers 9223372036854775807)) (>= (seq.len pool_workers) 0) (and (>= pool_nextWorker -9223372036854775808) (<= pool_nextWorker 9223372036854775807)) (and (>= pool_nextQueryId -9223372036854775808) (<= pool_nextQueryId 9223372036854775807)) (>= (str.len command) 0) (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) (and (>= workerCount -9223372036854775808) (<= workerCount 9223372036854775807))))"
# @axiom-hint: lean="workerCount ≤ 0 ∧ false ∧ workerCount ≤ 0 → result = false ∧ (pool ≥ 0) ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and (<= workerCount 0) false (=> (<= workerCount 0) (= result false)) (>= pool 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
proc initZ3Pool(pool: var Z3PersistentPool; command: string; args: seq[string]; workerCount: int): Result[bool, string] =
  if workerCount <= 0:
    return err("workerCount must be positive")
  pool.command = command
  pool.args = args
  pool.maxWorkers = workerCount
  pool.workers = @[]
  pool.nextWorker = 0
  pool.nextQueryId = 1'i64
  let lockResult = safeInitLock(pool.gate)
  if lockResult.isErr:
    return lockResult
  ok(true)

## Z3Ensure Persistent Pool.
# @axiom-hint: lean="desiredWorkers ≥ -9223372036854775808 ∧ desiredWorkers ≤ 9223372036854775807" smt="(assert (and (and (>= desiredWorkers -9223372036854775808) (<= desiredWorkers 9223372036854775807))))"
# @axiom-hint: lean="desiredWorkers ≤ 0 ∧ (poolReady ≥ 0) ∧ (bootstrapGateReady ≥ 0) ∧ (maxWorkers ≥ 0)" smt="(assert (and (<= desiredWorkers 0) (>= poolReady 0) (>= bootstrapGateReady 0) (>= maxWorkers 0)))"
proc z3EnsurePersistentPool*(desiredWorkers: int) =
  if desiredWorkers <= 0:
    return
  if not z3Manager().bootstrapGateReady:
    let lockResult = safeInitLock(z3Manager().bootstrapGate)
    if lockResult.isErr:
      return
    z3Manager().bootstrapGateReady = true
  acquire(z3Manager().bootstrapGate)
  defer:
    release(z3Manager().bootstrapGate)

  if not z3Manager().poolReady:
    let poolInitRes = initZ3Pool(z3Manager().pool, DefaultSolverCommand, @["-smt2", "-in"], desiredWorkers)
    if poolInitRes.isErr:
      logError("z3_pool", "[ERROR] z3_pool: initZ3Pool failed: " & poolInitRes.error())
    z3Manager().poolReady = true
    return
  if z3Manager().pool.command != DefaultSolverCommand or z3Manager().pool.args != @["-smt2", "-in"]:
    return
  if desiredWorkers > z3Manager().pool.maxWorkers:
    z3Manager().pool.maxWorkers = min(desiredWorkers, 8)
# @axiom-hint: lean="pool_command.length ≥ 0 ∧ pool_args.size ≥ 0 ∧ pool_maxWorkers ≥ -9223372036854775808 ∧ pool_maxWorkers ≤ 9223372036854775807 ∧ pool_workers.size ≥ 0 ∧ pool_nextWorker ≥ -9223372036854775808 ∧ pool_nextWorker ≤ 9223372036854775807 ∧ pool_nextQueryId ≥ -9223372036854775808 ∧ pool_nextQueryId ≤ 9223372036854775807" smt="(assert (and (>= (str.len pool_command) 0) (>= (seq.len pool_args) 0) (and (>= pool_maxWorkers -9223372036854775808) (<= pool_maxWorkers 9223372036854775807)) (>= (seq.len pool_workers) 0) (and (>= pool_nextWorker -9223372036854775808) (<= pool_nextWorker 9223372036854775807)) (and (>= pool_nextQueryId -9223372036854775808) (<= pool_nextQueryId 9223372036854775807))))"
proc getBudgetFor*(phase: SmtPhase): SmtBudget {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase-default budget, clamped by optional AXIOM_SMT_TIMEOUT (ms) override.
  let userTimeoutMs = safeParseInt(getEnv("AXIOM_SMT_TIMEOUT", "")).getOrDefault(0)
  case phase
  of spBmc:           result = SmtBudget(timeoutMs: 8000, memoryLimitMb: 512)
  of spBaseCase:      result = SmtBudget(timeoutMs: 2000, memoryLimitMb: 1024)
  of spInductiveStep: result = SmtBudget(timeoutMs: 5000, memoryLimitMb: 2048)
  if userTimeoutMs > 0:
    result.timeoutMs = min(result.timeoutMs, userTimeoutMs)  # Per-Phase Clamp

proc buildZ3QueryEnvelope*(query: string; timeoutMs: int; sentinel: string; enableProofs: bool = false; mode: Z3ExecutionMode = zmRaw;
    canonicalEnvelopeDigest: var string = ""): string =
  result = query
  # Conditionally enable proof production for trace extraction
  if enableProofs and result.find("(set-option :produce-proofs") < 0:
    result = "(set-option :produce-proofs true)\n" & result
  # Enable unsat core production if the query requests it
  if "get-unsat-core" in query:
    if result.find("(set-option :produce-unsat-cores") < 0:
      result = "(set-option :produce-unsat-cores true)\n" & result
  # Every option below is projected from the ONE pinned set in
  # core/trusted/solver_invocation, whose digest is what gets recorded. Deriving
  # the emitted text from the same projection is what keeps the recorded
  # solverOptionsDigest from drifting away from what Z3 was actually handed.
  # rlimit is the deterministic solve budget (z3DeterministicBudget); timeout
  # is the liveness backstop (z3SafetyNetMs) and never decides the answer.
  for spec in deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs):
    if result.find("(set-option :" & spec.name) < 0:
      result = solverOptionDirective(spec) & "\n" & result
  # IMPORTANT: (reset) must be prepended LAST so it comes before all options
  # and the query. Z3's (reset) clears all options, assertions, and declarations,
  # so options set after (reset) are preserved.
  # In zmIncremental mode, scope tracker manages state — no reset needed.
  case mode
  of zmRaw:
    if result.find("(reset)") < 0:
      result = "(reset)\n" & result
  of zmIncremental:
    discard  # scope tracker manages state — no reset needed
  if not result.endsWith("\n"):
    result.add("\n")
  canonicalEnvelopeDigest = sha256Hex(result)
  result.add("(echo \"" & sentinel & "\")\n")

# @axiom-hint: lean="pool_command.length ≥ 0 ∧ pool_args.size ≥ 0 ∧ pool_maxWorkers ≥ -9223372036854775808 ∧ pool_maxWorkers ≤ 9223372036854775807 ∧ pool_workers.size ≥ 0 ∧ pool_nextWorker ≥ -9223372036854775808 ∧ pool_nextWorker ≤ 9223372036854775807 ∧ pool_nextQueryId ≥ -9223372036854775808 ∧ pool_nextQueryId ≤ 9223372036854775807" smt="(assert (and (>= (str.len pool_command) 0) (>= (seq.len pool_args) 0) (and (>= pool_maxWorkers -9223372036854775808) (<= pool_maxWorkers 9223372036854775807)) (>= (seq.len pool_workers) 0) (and (>= pool_nextWorker -9223372036854775808) (<= pool_nextWorker 9223372036854775807)) (and (>= pool_nextQueryId -9223372036854775808) (<= pool_nextQueryId 9223372036854775807))))"
proc nextZ3Sentinel(pool: var Z3PersistentPool): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  acquire(pool.gate)
  let id = pool.nextQueryId
  inc pool.nextQueryId
  release(pool.gate)
  "AXIOM_Z3_EOF_" & $id

# ── Per-query exclusive worker lease ────────────────────────────────
# A query leases exactly one worker for its whole lifetime (write, sentinel
# read, post-query clean, and any restart). This is what actually enforces
# the W2-C invariant that a leased worker's pipe output belongs exclusively
# to the lease holder until its sentinel is found: selectZ3WorkerIndex waits
# while every worker is leased instead of handing out a busy one, and
# releaseZ3WorkerLease returns the lease on the caller's defer, so every
# exit path (success, large-payload bypass, parse error, read deadline,
# restart, exception) frees the worker.
proc releaseZ3WorkerLease(pool: var Z3PersistentPool; workerIdx: int) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Idempotent per-query lease release. Out-of-range indexes are a no-op so
  ## the caller-side defer can release unconditionally.
  if workerIdx < 0 or workerIdx >= pool.workers.len:
    return
  try:
    acquire(pool.gate)
    pool.workers[workerIdx].busy = false
    release(pool.gate)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="-1 ∧ selected ∧ (pool ≥ 0)" smt="(assert (and -1 selected (>= pool 0)))"
proc selectZ3WorkerIndex(pool: var Z3PersistentPool): int {.gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Lease one worker for the caller's exclusive use until releaseZ3WorkerLease.
  ## Round-robin scan starting at nextWorker, skipping busy workers; waits
  ## while every worker is leased — a busy worker's pipe belongs to another
  ## query, and sharing it interleaves two queries' stdout so one steals the
  ## other's sentinel. Worker growth (up to maxWorkers) is attempted on the
  ## first pass only, so a failing spawn cannot be retried in a tight loop.
  var mayGrow = true
  while true:
    var selected = -1
    acquire(pool.gate)
    if pool.workers.len == 0:
      if pool.maxWorkers <= 0:
        release(pool.gate)
        return -1
      var w: Z3PersistentWorker
      w.scopeTracker.enabled = getEnv("AXIOM_Z3_INCREMENTAL") == "1"
      if initZ3Worker(w, pool.command, pool.args).isOk:
        pool.workers.add(w)
        selected = pool.nextWorker mod pool.workers.len
        pool.nextWorker = (pool.nextWorker + 1) mod pool.workers.len
    else:
      if mayGrow and pool.workers.len < pool.maxWorkers:
        var w: Z3PersistentWorker
        w.scopeTracker.enabled = getEnv("AXIOM_Z3_INCREMENTAL") == "1"
        if initZ3Worker(w, pool.command, pool.args).isOk:
          pool.workers.add(w)
      for k in 0 ..< pool.workers.len:
        let candidate = (pool.nextWorker + k) mod pool.workers.len
        if not pool.workers[candidate].busy:
          selected = candidate
          break
    if selected >= 0:
      pool.workers[selected].busy = true
      pool.nextWorker = (selected + 1) mod pool.workers.len
      release(pool.gate)
      return selected
    release(pool.gate)
    mayGrow = false
    # All workers leased: wait for a releaseZ3WorkerLease instead of sharing
    # a pipe. pool.gate is released around the poll so holders can free.
    sleep(2)

proc acquireZ3WorkerLease*(): int {.gcsafe, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Lease a worker from the process-global pool for exclusive per-query use.
  ## Blocks while all workers are busy. Returns the worker index, or -1 when
  ## the pool cannot provide a worker. Must be paired with
  ## releaseZ3WorkerLease on every exit path.
  selectZ3WorkerIndex(z3Manager().pool)

proc releaseZ3WorkerLease*(workerIdx: int) {.gcsafe, raises: [].} =
  ## Return a worker lease acquired via acquireZ3WorkerLease. Idempotent and
  ## safe for out-of-range indexes; called from the query's defer.
  try:
    releaseZ3WorkerLease(z3Manager().pool, workerIdx)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Deinit Z3Pool.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc deinitZ3Pool*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Safely tear down the global Z3 persistent pool. All workers are killed.
  if not z3Manager().poolReady: return
  acquire(z3Manager().pool.gate)
  for i in 0 ..< z3Manager().pool.workers.len:
    deinitZ3Worker(z3Manager().pool.workers[i])
  z3Manager().pool.workers.setLen(0)
  z3Manager().poolReady = false
  release(z3Manager().pool.gate)
  deinitLock(z3Manager().pool.gate)
  if z3Manager().bootstrapGateReady:
    deinitLock(z3Manager().bootstrapGate)
    z3Manager().bootstrapGateReady = false
  if not z3ManagerPrivate.isNil:
    reset(z3ManagerPrivate.pool.command)
    reset(z3ManagerPrivate.pool.args)
    reset(z3ManagerPrivate.pool.workers)
    dealloc(z3ManagerPrivate)
    z3ManagerPrivate = nil

## I Z3Worker Alive.
# @axiom-hint: lean="false" smt="(assert (and false))"
proc isZ3WorkerAlive*(worker: Z3PersistentWorker): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a Z3 worker process is still running.
  if worker.process.isNil: return false
  let codeRes = safePeekExitCode(worker.process)
  if codeRes.isErr: return false
  codeRes.get() == -1

## Z3Exec Persistent.
# @axiom-hint: lean="query.length ≥ 0 ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807 ∧ desiredWorkers ≥ -9223372036854775808 ∧ desiredWorkers ≤ 9223372036854775807" smt="(assert (and (>= (str.len query) 0) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807)) (and (>= desiredWorkers -9223372036854775808) (<= desiredWorkers 9223372036854775807))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc getWorkerPeakMemoryMb(worker: Z3PersistentWorker): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(linux):
    try:
      if not worker.process.isNil:
        let pid = processID(worker.process)
        if pid > 0:
          let statusPath = "/proc/" & $pid & "/status"
          if fileExists(statusPath):
            let content = readFile(statusPath)
            for line in content.splitLines():
              if line.startsWith("VmHWM:"):
                let parts = line.splitWhitespace()
                if parts.len >= 2:
                  return int(parseBiggestInt(parts[1]) div 1024)
            for line in content.splitLines():
              if line.startsWith("VmPeak:"):
                let parts = line.splitWhitespace()
                if parts.len >= 2:
                  return int(parseBiggestInt(parts[1]) div 1024)
    except CatchableError:
      discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)
  return 0
proc z3ExecPersistent*(query: string; timeoutMs: int; desiredWorkers: int = 1; enableProofs: bool = false; queryType: string = "unknown"; cegarIters: int = 0;
    canonicalEnvelopeDigest: var string; transportPayloadDigest: var string): Result[string, string] {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let startMs = epochMilliseconds()
  var z3Result: Result[string, string]
  var resultStatus = "unknown"
  var payload: string
  var workerIdx = -1

  defer:
    # Per-query exclusive lease release: runs on every exit path — success,
    # large-payload bypass, parse/pool error, read deadline, restart, and
    # any exception — so a worker can never stay leased after its query ends.
    if workerIdx >= 0:
      releaseZ3WorkerLease(workerIdx)
    let timeMs = int(epochMilliseconds() - startMs)
    var memoryMb = 0
    try:
      if workerIdx >= 0 and workerIdx < z3Manager().pool.workers.len:
        memoryMb = getWorkerPeakMemoryMb(z3Manager().pool.workers[workerIdx])
    except CatchableError:
      discard  # Safe: cleanup operation, failure acceptable  # axiom:best-effort(ioboundary catch)
    if z3Result.isOk():
      # The response grammar is exactly sat | unsat | unknown, and "the stream
      # carried no decision at all" is recorded as an error because that is what
      # it is: a refusal or a truncated read, not an answer the solver gave.
      let response = solverResponse(z3Result.get())
      resultStatus =
        if response == srNoDecision: "error" else: $response
    else:
      let errLower = z3Result.error().toLowerAscii()
      if errLower.contains("deadline") or errLower.contains("timeout"):
        resultStatus = "timeout"
      else:
        resultStatus = "error"
    transportPayloadDigest = sha256Hex(payload)
    let record = Z3TelemetryRecord(
      ts: now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      queryType: queryType,
      rlimit: z3DeterministicBudget,
      result: resultStatus,
      timeMs: timeMs,
      memoryMb: memoryMb,
      cegarIters: cegarIters,
      baseCaseResult: "",
      stepCaseResult: "",
      canonicalEnvelopeDigest: canonicalEnvelopeDigest,
      transportPayloadDigest: transportPayloadDigest
    )
    try: appendZ3Telemetry(record)
    except CatchableError: discard  # telemetry is non-critical  # axiom:best-effort(ioboundary catch)

  try:
    if desiredWorkers > 0:
      z3EnsurePersistentPool(desiredWorkers)
  except CatchableError as e:
    try: logError("z3_pool", "[ERROR] z3_pool: pool ensure failed: " & e.msg)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  try:
    if not z3Manager().poolReady:
      z3Result = err("z3 persistent pool not available")
      return z3Result
  except CatchableError:
    z3Result = err("z3 persistent pool not available")
    return z3Result
  try:
    workerIdx = acquireZ3WorkerLease()
    if workerIdx < 0:
      z3Result = err("z3 persistent pool empty")
      return z3Result
    if workerIdx >= z3Manager().pool.workers.len:
      z3Result = err("z3 persistent pool index out of bounds")
      return z3Result
    # Readiness barrier: never assign a query to a worker whose pipe state is
    # unknown (EOF/deadline/post-clean failure set ready=false). Force a restart
    # so the query runs against a freshly-synced, Ready worker. We are outside
    # pool.gate here (selectZ3WorkerIndex released it via defer), so the
    # restart's own gate acquisition cannot deadlock.
    if not z3Manager().pool.workers[workerIdx].ready:
      try: discard restartZ3PoolWorker(z3Manager().pool, workerIdx)
      except CatchableError:
        try: logError("z3_pool", "[WARN] z3_pool: readiness restart failed")
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    z3Result = err("z3 persistent pool error")
    return z3Result
  # Liveness safety net ONLY — the logical solve budget is the rlimit in the SMT script.
  let livenessDeadlineMs = epochMilliseconds() + int64(z3SafetyNetMs)
  var readDeadlineMs = livenessDeadlineMs
  var sentinel: string
  try:
    sentinel = nextZ3Sentinel(z3Manager().pool)
  except CatchableError:
    z3Result = err("z3 persistent pool error")
    return z3Result
  try:
    let mode = if workerIdx >= 0 and workerIdx < z3Manager().pool.workers.len and
                  z3Manager().pool.workers[workerIdx].scopeTracker.enabled: zmIncremental
               else: zmRaw
    payload = buildZ3QueryEnvelope(query, timeoutMs, sentinel, enableProofs, mode, canonicalEnvelopeDigest)
  except CatchableError:
    z3Result = err("z3 persistent pool error")
    return z3Result
  # ── Deadlock prevention: large-payload file-based fallback ────────
  # OS pipe buffer is ~64KB. Blocking write of a larger payload hangs
  # forever because the timeout check only fires at loop boundaries.
  # Redirect large queries to a one-shot Z3 process via temp file.
  if payload.len > maxPipePayloadSize:
    let tmpFile = genTempPath("axiom_z3_large_", ".smt2")
    var largePayloadOk = false
    var largePayloadResult = ""
    try:
      writeFile(tmpFile, payload)
      let z3Bin = z3Manager().pool.command
      if z3Bin.len == 0:
        z3Result = err("z3 command not configured")
        return z3Result
      let p = startProcess(z3Bin, args = @["-smt2", tmpFile],
                           options = {poUsePath, poStdErrToStdOut})
      defer: close(p)
      let exited = p.waitForExit(z3SafetyNetMs)
      if exited == -1:
        try: kill(p)
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
        discard p.waitForExit(2000)
        z3Result = err("z3 timeout on large query (file-based fallback)")
        return z3Result
      let rawOutput = p.outputStream.readAll()
      var largeOutputLines: seq[string] = @[]
      for line in rawOutput.splitLines():
        largeOutputLines.add(line)
      var sentinelFound = false
      for i in countdown(largeOutputLines.len - 1, 0):
        if largeOutputLines[i].strip() == sentinel:
          largeOutputLines.setLen(i)
          sentinelFound = true
          break
      largePayloadResult = largeOutputLines.join("\n").strip()
      # The one-shot fallback owns a real exit code (`waitForExit` returns it on
      # this path), unlike the persistent worker. Reading a verdict from a script
      # Z3 refused is exactly the failure this detector exists to stop, and this
      # branch is where a large script would otherwise have scored one.
      if solverResponse(largePayloadResult, exited) == srNoDecision:
        z3Result = err("z3 large query: no solver decision (error response or non-zero exit)")
        return z3Result
      largePayloadOk = true
      z3Result = ok(largePayloadResult)
    except CatchableError as e:
      z3Result = err("large query fallback failed: " & e.msg)
    finally:
      try: removeFile(tmpFile)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    if largePayloadOk:
      return ok(largePayloadResult)
    return z3Result
  # ── End large-payload fallback ───────────────────────────────────
  var outputLines: seq[string] = @[]
  var restartAttempted = false
  while true:
    if epochMilliseconds() >= readDeadlineMs:
      try:
        let mgr = z3Manager()
        if workerIdx >= 0 and workerIdx < mgr.pool.workers.len:
          mgr.pool.workers[workerIdx].ready = false
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      z3Result = err("z3 persistent read deadline exceeded")
      return z3Result
    var ok = true
    try:
      # W2-C: Acquire gate only for write (short critical section).
      # After flush, release gate immediately — the read phase is lock-free
      # because the pipe output belongs exclusively to this query until the
      # sentinel is found. The sentinel protocol guarantees no cross-talk.
      acquire(z3Manager().pool.workers[workerIdx].gate)
      try:
        z3Manager().pool.workers[workerIdx].input.write(payload)
        z3Manager().pool.workers[workerIdx].input.flush()
      finally:
        release(z3Manager().pool.workers[workerIdx].gate)
      # W2-D: Accumulate raw read chunks as seq[string] instead of per-char
      # string buffer to avoid O(n²) reallocation on large outputs.
      var rawChunks: seq[string] = @[]
      var lineBuffer = ""
      var sentinelScanFrom = 0  # W2-E: incremental sentinel scan index
      while true:
        if epochMilliseconds() >= readDeadlineMs:
          ok = false
          break
        let stepDeadline = min(epochMilliseconds() + int64(z3ReadStepTimeoutMs), readDeadlineMs)
        # W2-F: single blocking poll(2) until readable or stepDeadline — the
        # OS owns the wait. hasDataAvailable == false keeps the exact original
        # branch semantics (recheck readDeadline, else continue the outer
        # loop); EOF stays owned by the read() path below.
        let hasDataAvailable = z3WorkerWaitData(
          z3Manager().pool.workers[workerIdx].process, stepDeadline)
        if not hasDataAvailable:
          if epochMilliseconds() >= readDeadlineMs:
            ok = false
            break
          continue
        var chunk: array[256, char]
        let fd = cint(outputHandle(z3Manager().pool.workers[workerIdx].process))
        let bytesRead = posix.read(fd, addr chunk[0], chunk.len.cint)
        if bytesRead <= 0:
          if lineBuffer.len > 0:
            rawChunks.add(lineBuffer)
            lineBuffer = ""
          z3Manager().pool.workers[workerIdx].ready = false
          ok = false
          break
        # W2-D: Buffer raw bytes into lineBuffer, flush complete lines
        # into rawChunks as single string additions (O(1) amortized).
        for i in 0 ..< bytesRead:
          let c = chunk[i]
          if c == '\c':
            discard  # No-op: intentional empty branch
          elif c == '\L':
            rawChunks.add(lineBuffer)
            lineBuffer = ""
          elif c == '\0':
            if lineBuffer.len > 0:
              rawChunks.add(lineBuffer)
              lineBuffer = ""
          else:
            lineBuffer.add(c)
        # W2-E: Scan only from last checked position for sentinel
        var sentinelFound = false
        for i in sentinelScanFrom ..< rawChunks.len:
          if rawChunks[i].strip() == sentinel:
            rawChunks.setLen(i)
            sentinelFound = true
            break
        sentinelScanFrom = max(0, rawChunks.len - 1)
        if sentinelFound:
          outputLines = rawChunks
          break
    except CatchableError:
      ok = false
    if ok:
      z3Result = ok(outputLines.join("\n").strip())
      # W1: Record assertion hash for scope replay on restart
      try:
        let mgr = z3Manager()
        if workerIdx >= 0 and workerIdx < mgr.pool.workers.len:
          mgr.pool.workers[workerIdx].scopeTracker.recordAssertion(query)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      # Post-query context reset for next query
      try:
        var worker = z3Manager().pool.workers[workerIdx]
        worker.input.writeLine("(reset)")
        const cleanSentinel = "AXIOM_Z3_CLEAN_READY"
        worker.input.writeLine("(echo \"" & cleanSentinel & "\")")
        worker.input.flush()
        let cleanRes = worker.waitForSentinel(cleanSentinel, 1000)
        if cleanRes.isErr:
          try: z3Manager().pool.workers[workerIdx].ready = false
          except CatchableError: discard  # axiom:best-effort(ioboundary catch)
          return err("Z3 Post-Query Clean Failed: " & cleanRes.error)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      # NOTE: do NOT use `return z3Result` here — Nim 2.2 ARC/ORC emits
      # wasMoved(z3Result) before the telemetry defer body runs, causing the
      # defer to read a moved-from err("") instead of the actual ok value.
      # Return a literal to preserve z3Result for the defer. See TELEMETRY.md.
      return ok(outputLines.join("\n").strip())
    if epochMilliseconds() >= readDeadlineMs:
      try: z3Manager().pool.workers[workerIdx].ready = false
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      try: discard restartZ3PoolWorker(z3Manager().pool, workerIdx)
      except CatchableError:
        try: logError("z3_pool", "[WARN] z3_pool: restartWorkers failed")
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      z3Result = err("z3 persistent read deadline exceeded")
      return z3Result
    if restartAttempted:
      try: z3Manager().pool.workers[workerIdx].ready = false
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      try: discard restartZ3PoolWorker(z3Manager().pool, workerIdx)
      except CatchableError:
        try: logError("z3_pool", "[WARN] z3_pool: restartWorkers failed")
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      z3Result = err("z3 persistent execution failed after restart")
      return z3Result
    restartAttempted = true
    outputLines = @[]
    # Restart consumes part of the original read deadline; grant the retry a
    # fresh full budget so a slow worker restart cannot burn the whole window.
    readDeadlineMs = epochMilliseconds() + int64(z3SafetyNetMs)
    try: discard restartZ3PoolWorker(z3Manager().pool, workerIdx)
    except CatchableError:
      try: logError("z3_pool", "[WARN] z3_pool: restartWorkers failed")
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)

collectPtrViolations(currentSourcePath())
{.pop.}
