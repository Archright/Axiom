import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Gate Daemon Client
##
## Lightweight client library for communicating with the gate daemon.
## Used by the orchestrator to check/persist gate results via the daemon's
## in-memory MemoDb instead of disk-based gate_history.jsonl.
##
## Safety: All operations have a 100ms connect timeout. If the daemon is
## unreachable, the client returns a "not connected" result and the
## orchestrator falls back to direct gate_memo operations (zero behavior change).

import std/[net, os, osproc]
import gate_daemon_types
import infrastructure/logging_facade
import core/trusted/axiom_pragmas
export DaemonRequest, DaemonResponse, DaemonSocketPath

type
  DaemonClient* = object
    ## Lightweight client for a single request-response cycle.
    ## Not persistent: connects, sends, receives, closes.
    socketPath*: string
    connected*: bool

func initDaemonClient*(repoRoot: string): DaemonClient =
  DaemonClient(
    socketPath: repoRoot / DaemonSocketPath,
    connected: false
  )

proc closeSocket(sock: Socket) {.used, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Safe close that never raises.
  {.push warning[BareExcept]: off.}
  try: sock.close() except Exception: discard  # Nim socket.close() infers Exception under strictEffects
  {.pop.}

proc sendRequest(client: var DaemonClient, req: DaemonRequest): DaemonResponse {.raises: [CatchableError], used, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Send a request to the daemon and return the response.
  ## Returns error response if connection fails (caller should fall back).
  var sock: Socket
  try:
    {.push warning[HoleEnumConv]: off.}
    sock = newSocket(Domain(AF_UNIX), SockType(SOCK_STREAM), Protocol(IPPROTO_IP))
    {.pop.}
    sock.connectUnix(client.socketPath)
    client.connected = true
  except CatchableError:
    client.connected = false
    return DaemonResponse(ok: false, message: "daemon not reachable")

  # Send request
  try:
    sock.send(encodeRequest(req))
  except CatchableError:
    closeSocket(sock)
    client.connected = false
    return DaemonResponse(ok: false, message: "send failed")

  # Read response
  var line = ""
  try:
    sock.readLine(line)
  except CatchableError:
    closeSocket(sock)
    client.connected = false
    return DaemonResponse(ok: false, message: "recv failed")

  closeSocket(sock)
  let resp = decodeResponse(line)
  if resp.version != DaemonProtocolVersion:
    ## Stale daemon binary speaking the old protocol — block weak-key hits,
    ## treat as unreachable so the caller falls through to disk memo.
    client.connected = false
    return DaemonResponse(ok: false, message: "daemon protocol version mismatch")
  resp

# ══════════════════════════════════════════════════════════════════════════════
# High-Level API
# ══════════════════════════════════════════════════════════════════════════════

proc ping*(client: var DaemonClient): DaemonResponse {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if daemon is alive. Returns pong message.
  sendRequest(client, DaemonRequest(mthd: "ping", requestId: "ping"))

proc checkCache*(client: var DaemonClient, gateId, subtreeRoot: string,
                 epoch: int, identity: string): DaemonResponse {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a gate result is cached in daemon's MemoDb.
  ## identity is the memo's composite lock hash — consumed verbatim by the daemon.
  ## Returns: ok=true, cached=true/false, result=pass/fail
  sendRequest(client, DaemonRequest(
    mthd: "check_cache", requestId: "cc-" & gateId,
    gateId: gateId, subtreeRoot: subtreeRoot, identity: identity, epoch: epoch))

proc persistResult*(client: var DaemonClient, gateId, subtreeRoot: string,
                    epoch: int, passed: bool, identity: string,
                    failCategory = "", failReason = ""): DaemonResponse {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist a gate result to daemon's MemoDb, keyed verbatim on identity.
  sendRequest(client, DaemonRequest(
    mthd: "persist_result", requestId: "pr-" & gateId,
    gateId: gateId, subtreeRoot: subtreeRoot, identity: identity, epoch: epoch,
    result: passed, failCategory: failCategory, failReason: failReason))

proc invalidate*(client: var DaemonClient, gateId: string): DaemonResponse {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Invalidate all cached entries for a gate.
  sendRequest(client, DaemonRequest(
    mthd: "invalidate", requestId: "inv-" & gateId, gateId: gateId))

proc shutdown*(client: var DaemonClient): DaemonResponse {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Ask daemon to shut down gracefully.
  sendRequest(client, DaemonRequest(mthd: "shutdown", requestId: "shutdown"))

# ══════════════════════════════════════════════════════════════════════════════
# Daemon Lifecycle Management
# ══════════════════════════════════════════════════════════════════════════════

proc isDaemonRunning*(repoRoot: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if daemon is running by testing socket connectivity.
  ## Does NOT start the daemon.
  let socketPath = repoRoot / DaemonSocketPath
  if not fileExists(socketPath) and not dirExists(parentDir(socketPath)):
    return false
  # Try to connect — fileExists returns false for Unix sockets
  var client = initDaemonClient(repoRoot)
  try:
    let resp = client.ping()
    resp.ok and resp.message == "pong"
  except CatchableError:
    false

proc startDaemon*(repoRoot: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Start the gate daemon as a background process.
  ## Returns true if daemon started (or was already running).
  if isDaemonRunning(repoRoot):
    return true

  # Ensure cache directory exists
  let cacheDir = repoRoot / ".axiom" / "cache"
  try:
    discard existsOrCreateDir(cacheDir)
  except CatchableError:
    return false

  # Start daemon as detached background process
  let daemonBin = repoRoot / "bin" / "gate-daemon"
  if not fileExists(daemonBin):
    logInfo("gate_daemon_client", "[GATE-DAEMON] Binary not found: " & daemonBin &
                     " — falling back to direct mode")
    return false

  try:
    let pid = startProcess(daemonBin, workingDir = repoRoot,
                           options = {poDaemon, poStdErrToStdOut})
    try: pid.close() except CatchableError: discard  # Detach — daemon outlives parent  # axiom:best-effort(ioboundary catch)
  except CatchableError as e:
    logError("gate_daemon_client", "[GATE-DAEMON] Failed to start: " & e.msg)
    return false

  # Wait briefly for daemon to initialize (poll socket)
  for i in 0..<10:  # up to 100ms
    if isDaemonRunning(repoRoot):
      return true
    sleep(10)

  false

proc stopDaemon*(repoRoot: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Gracefully stop the daemon.
  var client = initDaemonClient(repoRoot)
  let resp = client.shutdown()
  resp.ok

{.pop.}
