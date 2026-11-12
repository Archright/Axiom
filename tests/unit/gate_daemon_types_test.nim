## gate_daemon_types_test.nim
## Business scenario tests for gate/daemon/gate_daemon_types.nim —
## the protocol types and MemoDb for the gate daemon.

import std/[unittest, tables, json]
import gate/daemon/gate_daemon_types

suite "DaemonRequest: encode/decode round-trip":
  test "ping request preserves method and requestId":
    let req = DaemonRequest(mthd: "ping", requestId: "test-1")
    let encoded = encodeRequest(req)
    let decoded = decodeRequest(encoded)
    check decoded.mthd == "ping"
    check decoded.requestId == "test-1"

  test "check_cache request preserves all fields":
    let req = DaemonRequest(
      mthd: "check_cache", requestId: "cc-1",
      gateId: "my-gate", subtreeRoot: "abc123", identity: "comp-lock-1",
      epoch: 42)
    let encoded = encodeRequest(req)
    let decoded = decodeRequest(encoded)
    check decoded.mthd == "check_cache"
    check decoded.gateId == "my-gate"
    check decoded.subtreeRoot == "abc123"
    check decoded.identity == "comp-lock-1"
    check decoded.epoch == 42

  test "protocol version is stamped on the wire and parsed back":
    let req = DaemonRequest(mthd: "ping", requestId: "v-test")
    let decoded = decodeRequest(encodeRequest(req))
    check decoded.version == DaemonProtocolVersion

  test "persist_result request preserves result and fail info":
    let req = DaemonRequest(
      mthd: "persist_result", requestId: "pr-1",
      gateId: "g1", result: true,
      failCategory: "timeout", failReason: "exceeded 120s")
    let encoded = encodeRequest(req)
    let decoded = decodeRequest(encoded)
    check decoded.result == true
    check decoded.failCategory == "timeout"
    check decoded.failReason == "exceeded 120s"

  test "malformed JSON returns empty request":
    let decoded = decodeRequest("not json{{{")
    check decoded.mthd.len == 0

suite "DaemonResponse: encode/decode round-trip":
  test "pong response preserves ok and message":
    let resp = DaemonResponse(ok: true, message: "pong", revision: 5)
    let encoded = encodeResponse(resp)
    let decoded = decodeResponse(encoded)
    check decoded.ok == true
    check decoded.message == "pong"
    check decoded.revision == 5
    check decoded.version == DaemonProtocolVersion

  test "cache hit response preserves all fields":
    let resp = DaemonResponse(ok: true, cached: true, result: true,
                              reason: "passed", failCategory: "", revision: 3)
    let encoded = encodeResponse(resp)
    let decoded = decodeResponse(encoded)
    check decoded.cached == true
    check decoded.result == true
    check decoded.reason == "passed"

  test "version is parsed from the wire v field":
    let decoded = decodeResponse("{\"v\":1,\"ok\":true}")
    check decoded.version == 1
    check decoded.ok == true

suite "MemoDb: cache operations":
  test "lookup returns empty entry on miss":
    var db = initMemoDb()
    let entry = db.lookup("ident-1")
    check entry.epoch == 0
    check entry.result == false
    check db.missCount == 1

  test "persist then lookup returns cached entry":
    var db = initMemoDb()
    let ce = CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-1",
                        result: true, epoch: 7)
    db.persist(ce)
    let entry = db.lookup("ident-1")
    check entry.result == true
    check entry.epoch == 7
    check db.hitCount == 1
    check db.persistCount == 1

  test "lookup with different identity is a miss even for same gate/subtree":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-A",
                          result: true, epoch: 7))
    let entry = db.lookup("ident-B")
    check entry.epoch == 0
    check db.missCount == 1

  test "persist updates revision":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-1", epoch: 1))
    db.persist(CacheEntry(gateId: "g2", subtreeRoot: "r2", identity: "ident-2", epoch: 2))
    check db.revision == 2

  test "invalidate removes matching entries":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-1", epoch: 1))
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r2", identity: "ident-2", epoch: 2))
    db.persist(CacheEntry(gateId: "g2", subtreeRoot: "r3", identity: "ident-3", epoch: 3))
    let removed = db.invalidate("g1")
    check removed == 2
    check db.lookup("ident-1").epoch == 0
    check db.lookup("ident-3").epoch == 3

  test "stats reports correct counts":
    var db = initMemoDb()
    db.persist(CacheEntry(gateId: "g1", subtreeRoot: "r1", identity: "ident-1", epoch: 1))
    discard db.lookup("ident-1")   # hit
    discard db.lookup("ident-miss") # miss
    let s = db.stats()
    check s.entries == 1
    check s.hits == 1
    check s.misses == 1
    check s.persists == 1
