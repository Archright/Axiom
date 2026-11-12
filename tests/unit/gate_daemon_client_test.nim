## gate_daemon_client_test.nim
## Business scenario tests for gate/daemon/gate_daemon_client.nim —
## the lightweight client for gate daemon communication.

import std/[unittest, strutils, os, net]
import gate/daemon/gate_daemon_types
import gate/daemon/gate_daemon_client

# Minimal one-shot fake daemon: writes <sockPath>.ready once listening, records
# the received request line to <sockPath>.line, and replies with a JSON
# response stamped with gFakeResponseVersion (1 = stale daemon binary,
# 2 = current protocol), so tests can exercise the wire protocol. File-based
# handoff keeps the thread GC-safe (no GC'd globals shared across threads).
var gFakeResponseVersion = 2

proc fakeDaemonServer(sockPath: string) {.thread.} =
  let linePath = sockPath & ".line"
  try:
    {.push warning[HoleEnumConv]: off.}
    let sock = newSocket(Domain(AF_UNIX), SockType(SOCK_STREAM), Protocol(IPPROTO_IP))
    {.pop.}
    sock.bindUnix(sockPath)
    sock.listen()
    writeFile(sockPath & ".ready", "1")
    var clientSock: Socket
    var address: string
    sock.acceptAddr(clientSock, address)
    var line = ""
    clientSock.readLine(line)
    writeFile(linePath, line)
    clientSock.send("{\"v\":" & $gFakeResponseVersion & ",\"ok\":true,\"cached\":true,\"result\":true}\n")
    clientSock.close()
    sock.close()
  except CatchableError:
    discard  # test-only server; failures surface via the client assertions
  finally:
    try: removeFile(sockPath) except CatchableError: discard

proc waitForServer(sockPath: string): bool =
  ## fileExists() cannot see AF_UNIX sockets (verified), so poll the .ready
  ## regular file the server writes right after listen().
  for i in 0..<200:  # up to 2s for the fake server to bind
    if fileExists(sockPath & ".ready"):
      return true
    sleep(10)
  false

suite "initDaemonClient: socket path":
  test "socket path contains gate-daemon.sock":
    let client = initDaemonClient("/tmp/test-repo")
    check client.socketPath.endsWith(".axiom/cache/gate-daemon.sock")
    check client.connected == false

  test "socket path uses provided repoRoot":
    let client = initDaemonClient("/home/user/project")
    check client.socketPath.contains("/home/user/project")

suite "sendRequest: daemon unreachable":
  test "returns error response when socket does not exist":
    var client = DaemonClient(
      socketPath: "/nonexistent/path/gate-daemon.sock",
      connected: false)
    let resp = client.ping()
    check resp.ok == false
    check resp.message.contains("daemon not reachable")
    check client.connected == false

suite "sendRequest: protocol version":
  test "daemon replying with old protocol version is treated as unreachable":
    let sockPath = getTempDir() / "gdd-fake1-" & $getCurrentProcessId() & ".sock"
    gFakeResponseVersion = 1
    var thread: Thread[string]
    createThread(thread, fakeDaemonServer, sockPath)
    check waitForServer(sockPath)
    var client = DaemonClient(socketPath: sockPath, connected: false)
    let resp = client.checkCache("g1", "r1", 1, "weak-ident-1")
    check resp.ok == false
    check resp.message.contains("version mismatch")
    check client.connected == false
    joinThread(thread)
    removeFile(sockPath & ".ready")

  test "identity is threaded into the wire request and a v2 reply is accepted":
    let sockPath = getTempDir() / "gdd-fake2-" & $getCurrentProcessId() & ".sock"
    gFakeResponseVersion = 2
    var thread: Thread[string]
    createThread(thread, fakeDaemonServer, sockPath)
    check waitForServer(sockPath)
    var client = DaemonClient(socketPath: sockPath, connected: false)
    let resp = client.persistResult("g2", "r2", 2, true, "comp-ident-xyz",
                                    "fcPermanent", "reason-detail")
    check resp.ok == true
    let received = readFile(sockPath & ".line")
    check received.contains("comp-ident-xyz")
    check received.contains("\"identity\"")
    joinThread(thread)
    removeFile(sockPath & ".ready")
    removeFile(sockPath & ".line")

suite "isDaemonRunning: no daemon":
  test "returns false for nonexistent repo":
    check isDaemonRunning("/nonexistent/repo/path") == false

suite "lifecycle: stop daemon":
  test "stopDaemon returns false when daemon not running":
    check stopDaemon("/nonexistent/repo/path") == false
