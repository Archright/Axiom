import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import core/axiom_pragmas
import gate_daemon_types
import std/[json, os, net, posix, times, strutils]
import infrastructure/logging_facade
import core/parsers/safe_parsers
import core/results
type
  DaemonConfig* = object
    socketPath*: string
    pidPath*: string
    dataDir*: string       ## .axiom/cache/ for disk persistence
    maxIdleSec*: int       ## Auto-shutdown after N seconds of no requests
    historyPath*: string   ## gate_history.jsonl path for warm start
# Module-level paths for signal handler (noconv procs cannot capture locals)
var gSocketPath, gPidPath: string
proc defaultConfig*(repoRoot: string): DaemonConfig =
  DaemonConfig(
    socketPath: repoRoot / DaemonSocketPath,
    pidPath: repoRoot / DaemonPidPath,
    dataDir: repoRoot / ".axiom" / "cache",
    maxIdleSec: 300,  ## 5 minutes idle → auto-shutdown
    historyPath: repoRoot / ".axiom" / "cache" / "gate_history.jsonl"
  )

# ══════════════════════════════════════════════════════════════════════════════
# Warm Start: Load existing cache into MemoDb
# ══════════════════════════════════════════════════════════════════════════════
proc warmStart*(db: var MemoDb, historyPath: string): int {.raises: [CatchableError].} =
  ## Load gate_history.jsonl into MemoDb for warm cache.
  ## Returns count of loaded entries.
  if not fileExists(historyPath):
    return 0
  try:
    for line in lines(historyPath):
      if line.len == 0: continue
      let j = parseJson(line)
      let gateId = j{"gateId"}.getStr("")
      let subtreeRoot = j{"subtreeRoot"}.getStr("")
      let identity = j{"identity"}.getStr("")
      if gateId.len == 0: continue
      if identity.len == 0: continue  # no usable identity → treat as absent (never legacy-rekeyed)
      let entry = CacheEntry(
        gateId: gateId,
        subtreeRoot: subtreeRoot,
        identity: identity,
        result: j{"result"}.getBool(false),
        epoch: j{"epoch"}.getInt(0),
        failCategory: j{"failCategory"}.getStr(""),
        failReason: j{"failReason"}.getStr(""),
        timestamp: j{"timestamp"}.getInt(0).int64,
        revision: 0
      )
      db.persist(entry)
      inc result
  except CatchableError:
    discard  # Best-effort warm start  # axiom:best-effort(ioboundary catch)

# ══════════════════════════════════════════════════════════════════════════════
# Request Handler
# ══════════════════════════════════════════════════════════════════════════════
proc handleRequest*(db: var MemoDb, req: DaemonRequest): DaemonResponse {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDebt: "DEBT#451".} =
  ## Process a single request and return a response.
  if req.version != DaemonProtocolVersion:
    ## Refuse pre-v2 requests: stale daemon clients must degrade to disk memo
    ## instead of receiving weak-key cache hits.
    return DaemonResponse(ok: false, message: "protocol version mismatch")
  case req.mthd
  of "ping":
    let s = db.stats()
    DaemonResponse(ok: true, message: "pong", revision: s.revision)
  of "check_cache":
    if req.identity.len == 0:
      return DaemonResponse(ok: false, message: "missing identity")
    let entry = db.lookup(req.identity)
    if entry.epoch > 0:
      # Cache hit
      DaemonResponse(ok: true, cached: true, result: entry.result,
                     reason: entry.failReason,
                     failCategory: entry.failCategory,
                     revision: db.revision)
    else:
      # Cache miss
      DaemonResponse(ok: true, cached: false, revision: db.revision)
  of "persist_result":
    if req.identity.len == 0:
      return DaemonResponse(ok: false, message: "missing identity")
    let entry = CacheEntry(
      gateId: req.gateId,
      subtreeRoot: req.subtreeRoot,
      identity: req.identity,
      result: req.result,
      epoch: req.epoch,
      failCategory: req.failCategory,
      failReason: req.failReason,
      timestamp: getTime().toUnix().int64,
      revision: 0
    )
    db.persist(entry)
    DaemonResponse(ok: true, revision: db.revision)
  of "invalidate":
    if req.gateId.len == 0:
      return DaemonResponse(ok: false, message: "missing gateId")
    let removed = db.invalidate(req.gateId)
    DaemonResponse(ok: true, message: $removed & " entries removed",
                   revision: db.revision)
  of "shutdown":
    DaemonResponse(ok: true, message: "shutting down")
  else:
    DaemonResponse(ok: false, message: "unknown method: " & req.mthd)

# ══════════════════════════════════════════════════════════════════════════════
# Server Loop
# ══════════════════════════════════════════════════════════════════════════════
proc writePidFile(pidPath: string) {.raises: [CatchableError].} =
  ## Write current PID to pidPath for daemon lifecycle management.
  try:
    writeFile(pidPath, $getCurrentProcessId())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc removePidFile(pidPath: string) {.raises: [CatchableError], axiomEffect: IOEffect.} =
  try:
    removeFile(pidPath)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc removeSocket(socketPath: string) {.raises: [CatchableError], axiomEffect: IOEffect.} =
  try:
    removeFile(socketPath)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc validateOrphanPid(pidPath, socketPath: string) {.raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Kill orphan daemon processes and clean up stale files.
  if fileExists(pidPath):
    try:
      let oldPidRes = safeParseInt(readFile(pidPath).strip())
      if oldPidRes.isErr:
        discard  # axiom:best-effort(unparseable pid file — nothing to kill)
      else:
        let oldPid = oldPidRes.get
        if kill(Pid(oldPid), 0) == 0:
          logInfo("gate_daemon_server", "[GATE-DAEMON] Orphan daemon detected (pid=" & $oldPid & "), killing")
          discard kill(Pid(oldPid), SIGTERM)
          discard usleep(200_000)
          if kill(Pid(oldPid), 0) == 0:
            discard kill(Pid(oldPid), SIGKILL)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    try: removeFile(pidPath) except CatchableError: discard  # cleanup best-effort  # axiom:best-effort(ioboundary catch)
  if fileExists(socketPath):
    try: removeFile(socketPath) except CatchableError: discard  # cleanup best-effort  # axiom:best-effort(ioboundary catch)
proc runDaemon*(config: DaemonConfig) {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Main daemon loop. Listens on Unix domain socket, handles requests.
  ## Auto-shuts down after maxIdleSec of inactivity.
  var db = initMemoDb()

  # Warm start: load existing gate history
  let loaded = db.warmStart(config.historyPath)
  logInfo("gate_daemon_server", "[GATE-DAEMON] Warm start: " & $loaded & " entries loaded")

  # Create Unix domain socket
  validateOrphanPid(config.pidPath, config.socketPath)
  removeSocket(config.socketPath)
  let sock = newSocket(Domain(AF_UNIX), SockType(SOCK_STREAM), Protocol(IPPROTO_IP))
  try:
    sock.bindUnix(config.socketPath)
    sock.listen()
  except CatchableError as e:
    logInfo("gate_daemon_server", "[GATE-DAEMON] FATAL: Cannot bind socket: " & e.msg)
    try: sock.close() except Exception: discard  # Nim socket.close() raises Exception
    quit(1)

  writePidFile(config.pidPath)

  # Store paths for signal handler (noconv procs cannot capture locals)
  gSocketPath = config.socketPath
  gPidPath = config.pidPath

  # Graceful shutdown on SIGTERM/SIGINT
  proc sigtermHandler(sig: cint) {.noconv, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    try: logInfo("gate_daemon_server", "[GATE-DAEMON] Signal " & $sig & " received, shutting down")
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    try: removeSocket(gSocketPath) except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    try: removePidFile(gPidPath) except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    quit(0)
  signal(SIGTERM, sigtermHandler)
  signal(SIGINT, sigtermHandler)

  logInfo("gate_daemon_server", "[GATE-DAEMON] Listening on " & config.socketPath &
                   " (pid=" & $getCurrentProcessId() & ")")

  var shuttingDown = false
  var lastActivity = getTime()

  while not shuttingDown:
    # Accept with timeout for idle detection
    var client: Socket
    var address: string
    try:
      sock.acceptAddr(client, address)
    except TimeoutError:
      # Check idle timeout
      let idle = (getTime() - lastActivity).inSeconds
      if idle > config.maxIdleSec:
        logInfo("gate_daemon_server", "[GATE-DAEMON] Idle timeout (" & $config.maxIdleSec &
                         "s). Shutting down.")
        break
      continue
    except CatchableError:
      continue

    lastActivity = getTime()

    # Read request line
    var line = ""
    try:
      client.readLine(line)
    except CatchableError:
      try: client.close() except Exception: discard  # Nim socket.close() raises Exception
      continue

    if line.len == 0:
      try: client.close() except Exception: discard  # Nim socket.close() raises Exception
      continue

    let req = decodeRequest(line)
    var resp = db.handleRequest(req)

    # Send response
    try:
      client.send(encodeResponse(resp))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    try: client.close() except Exception: discard  # Nim socket.close() raises Exception

    # Handle shutdown
    if req.mthd == "shutdown":
      shuttingDown = true

  # Cleanup
  try: sock.close() except Exception: discard  # Nim socket.close() raises Exception
  removeSocket(config.socketPath)
  removePidFile(config.pidPath)

  # Flush final stats
  let s = db.stats()
  logInfo("gate_daemon_server", "[GATE-DAEMON] Shutdown. Stats: " & $s.entries &
                   " entries, " & $s.hits & " hits, " & $s.misses &
                   " misses, rev=" & $s.revision)

{.pop.}

