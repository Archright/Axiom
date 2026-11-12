## gate_daemon_server_test.nim
## Business scenario tests for gate/daemon/gate_daemon_server.nim —
## the Unix socket server with in-memory MemoDb.

import std/[unittest, strutils, os]
import gate/daemon/gate_daemon_types
import gate/daemon/gate_daemon_server

suite "handleRequest: ping":
  test "ping returns pong":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(mthd: "ping", requestId: "t1",
                                               version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.message == "pong"

suite "handleRequest: check_cache":
  test "cache miss returns ok with cached=false":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(
      mthd: "check_cache", gateId: "g1", subtreeRoot: "r1",
      identity: "ident-1", version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.cached == false

  test "cache hit returns ok with cached=true":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-1",
                          result: true, epoch: 5))
    let resp = handleRequest(db, DaemonRequest(
      mthd: "check_cache", gateId: "g1", subtreeRoot: "r1",
      identity: "ident-1", version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.cached == true
    check resp.result == true

  test "identity mismatch is a miss — no reinterpretation of gate/subtree":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-A",
                          result: true, epoch: 5))
    let resp = handleRequest(db, DaemonRequest(
      mthd: "check_cache", gateId: "g1", subtreeRoot: "r1",
      identity: "ident-B", version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.cached == false

  test "missing identity returns error":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(mthd: "check_cache",
                                               version: DaemonProtocolVersion))
    check resp.ok == false
    check resp.message.contains("identity")

suite "handleRequest: protocol version":
  test "request with old protocol version is refused":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(mthd: "ping", requestId: "t1",
                                               version: 1))
    check resp.ok == false
    check resp.message.contains("version")

suite "handleRequest: persist_result":
  test "persist then check returns cached result":
    var db = initMemoDb()
    let persistResp = handleRequest(db, DaemonRequest(
      mthd: "persist_result", gateId: "g2", subtreeRoot: "r2",
      identity: "ident-2", epoch: 10, result: false, failCategory: "timeout",
      failReason: "exceeded 120s", version: DaemonProtocolVersion))
    check persistResp.ok == true

    let checkResp = handleRequest(db, DaemonRequest(
      mthd: "check_cache", gateId: "g2", subtreeRoot: "r2",
      identity: "ident-2", version: DaemonProtocolVersion))
    check checkResp.cached == true
    check checkResp.result == false
    check checkResp.failCategory == "timeout"

  test "persist_result with missing identity returns error":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(
      mthd: "persist_result", gateId: "g2", subtreeRoot: "r2",
      epoch: 10, result: true, version: DaemonProtocolVersion))
    check resp.ok == false
    check resp.message.contains("identity")

suite "handleRequest: invalidate":
  test "invalidate removes entries and reports count":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g3", subtreeRoot: "r1", identity: "ident-1", epoch: 1))
    db.persist(CacheEntry(gateId: "g3", subtreeRoot: "r2", identity: "ident-2", epoch: 2))
    let resp = handleRequest(db, DaemonRequest(
      mthd: "invalidate", gateId: "g3", version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.message.contains("2")

  test "invalidate unknown gate returns 0 removed":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(
      mthd: "invalidate", gateId: "nonexistent", version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.message.contains("0")

suite "handleRequest: shutdown and unknown":
  test "shutdown returns ok":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(mthd: "shutdown",
                                               version: DaemonProtocolVersion))
    check resp.ok == true
    check resp.message.contains("shutting down")

  test "unknown method returns error":
    var db = initMemoDb()
    let resp = handleRequest(db, DaemonRequest(mthd: "bogus",
                                               version: DaemonProtocolVersion))
    check resp.ok == false
    check resp.message.contains("unknown method")

suite "warmStart: missing file":
  test "warmStart handles missing file gracefully":
    var db = initMemoDb()
    let loaded = db.warmStart("/nonexistent/path/history.jsonl")
    check loaded == 0

suite "warmStart: identity requirement":
  test "lines without identity are skipped, not legacy-rekeyed":
    var db = initMemoDb()
    let historyPath = getTempDir() / "gate_history_w5_" & $getCurrentProcessId() & ".jsonl"
    writeFile(historyPath,
      "{\"gateId\":\"g1\",\"subtreeRoot\":\"r1\",\"identity\":\"ident-1\",\"result\":true,\"epoch\":1}\n" &
      "{\"gateId\":\"g2\",\"subtreeRoot\":\"r2\",\"result\":true,\"epoch\":2}\n")
    let loaded = db.warmStart(historyPath)
    check loaded == 1
    check db.lookup("ident-1").result == true   # identity-bearing line loaded
    check db.lookup("ident-2").epoch == 0       # no-identity line treated as absent
    removeFile(historyPath)

suite "defaultConfig: config generation":
  test "defaultConfig produces valid paths":
    let cfg = defaultConfig("/tmp/test-repo")
    check cfg.socketPath.endsWith("gate-daemon.sock")
    check cfg.pidPath.endsWith("gate-daemon.pid")
    check cfg.maxIdleSec == 300
