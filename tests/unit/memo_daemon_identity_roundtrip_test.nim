## memo_daemon_identity_roundtrip_test.nim
## End-to-end regression for W5 (debt-authority consolidation):
## the gate daemon must CONSUME the memo's canonical composite lock hash —
## it must not generate, recompute, or reinterpret cache identity.
##
## Mirrors the orchestrator flow (src/gate/orchestrator/hook/memo.nim):
## the memo computes computeCompositeLockHash, persist_result carries the
## identity over the wire, and check_cache keys on it verbatim.

import std/[unittest, os, strutils, tables]
import core/gate/gate_memo  # computeCompositeLockHash — the memo's canonical identity
import gate/daemon/gate_daemon_types
import gate/daemon/gate_daemon_server

suite "memo → daemon composite identity roundtrip":
  test "persist by identity hits; different identity misses; storage is byte-identical":
    let repoRoot = getCurrentDir()
    # DEBT#471: the orchestrator memo resolves the gate's transitive-closure
    # digest (resolveGateHash) and hands the composite a PRE-RESOLVED digest —
    # the gateHash slot is consumed verbatim, not re-derived from a path.
    let gateDigest = "e2e-gate-transitive-closure-digest"

    # Compute the composite identity the way the orchestrator memo does
    # (computeGateCacheKey delegates to computeCompositeLockHash).
    let identityA = computeCompositeLockHash("e2e-input-hash", gateDigest,
                                             repoRoot, "e2e-subtree")
    let identityB = computeCompositeLockHash("e2e-input-hash", gateDigest,
                                             repoRoot, "e2e-subtree-other")
    check identityA.len > 0
    check identityA != identityB

    var db = initMemoDb()

    # persist_result with the strong identity
    let persistResp = handleRequest(db, DaemonRequest(
      mthd: "persist_result", version: DaemonProtocolVersion,
      gateId: "e2e-gate", subtreeRoot: "e2e-subtree",
      identity: identityA, epoch: 3, result: true))
    check persistResp.ok == true

    # check_cache with the SAME identity → HIT
    let hit = handleRequest(db, DaemonRequest(
      mthd: "check_cache", version: DaemonProtocolVersion,
      gateId: "e2e-gate", subtreeRoot: "e2e-subtree",
      identity: identityA, epoch: 3))
    check hit.cached == true
    check hit.result == true

    # check_cache with a DIFFERENT identity — same gate, same subtree, but
    # the strong key differs → MISS (no weak-key reinterpretation)
    let miss = handleRequest(db, DaemonRequest(
      mthd: "check_cache", version: DaemonProtocolVersion,
      gateId: "e2e-gate", subtreeRoot: "e2e-subtree",
      identity: identityB, epoch: 3))
    check miss.cached == false

    # Consume-only: the daemon stored the identity byte-identical — no
    # server-side transformation, hashing, or re-keying of the opaque string.
    var stored: seq[string]
    for entry in db.entries.values:
      stored.add(entry.identity)
    check stored == @[identityA]