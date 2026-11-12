## WP4-d-3 — shadow_digests 6-dimension canonical digest unit tests
## EXPERIMENT_ID=act2-wp4d-symbol-identity / SUB_TASK=WP4-d-3

import std/[algorithm, sequtils, strutils]
import std/json
import core/crypto/hash_kernel
import core/utils/shadow_digests
import core/topology/topology_types
import core/topology/verified_set
import core/topology/symbol_interning
import core/sorter/sorter_core

# ── Helpers ─────────────────────────────────────────────────────────

proc expectEq(actual, expected: string; name: string): bool =
  if actual == expected:
    echo "  [OK] " & name
    true
  else:
    echo "  [FAIL] " & name & " (got=" & actual[0 ..< min(16, actual.len)] & ")"
    false

proc makeNode(idStr: string; deps: seq[string]): SorterNode =
  var n: SorterNode
  n.id = sorterNodeId(idStr)
  for d in deps:
    n.dependencyIds.add(sorterNodeId(d))
  n

proc makeAnalysis(nodeIds: seq[string]; deps: seq[seq[string]]): TopologyAnalysis =
  result.verificationQueue = @[]
  for id in nodeIds:
    result.verificationQueue.add(sorterNodeId(id))
  for i in 0 ..< nodeIds.len:
    result.state.nodes.add(makeNode(nodeIds[i], deps[i]))

# ── Suite ───────────────────────────────────────────────────────────

var failures = 0

echo "[Suite] shadow_digests determinism & order-independence"

block:
  let a1 = makeAnalysis(@["m::a", "m::b"], @[@["m::b"], @[]])
  let a2 = makeAnalysis(@["m::a", "m::b"], @[@["m::b"], @[]])
  failures += int(not expectEq(plannedQueueDigest(a1), plannedQueueDigest(a2),
    "plannedQueueDigest deterministic for same input"))
  failures += int(not expectEq(dependencyGraphDigest(a1), dependencyGraphDigest(a2),
    "dependencyGraphDigest deterministic for same input"))

block:
  # order-independence of obligation list digest
  let d1 = obligationListDigest(@["ob-a", "ob-b"])
  let d2 = obligationListDigest(@["ob-b", "ob-a"])
  failures += int(not expectEq(d1, d2, "obligationListDigest order-independent"))

block:
  # solver run digest order-independence
  let s1 = solverRunDigest(@["rk-1", "rk-2"])
  let s2 = solverRunDigest(@["rk-2", "rk-1"])
  failures += int(not expectEq(s1, s2, "solverRunDigest order-independent"))

block:
  # empty inputs produce stable digest without crash
  let emptyAnalysis = makeAnalysis(@[], @[])
  discard plannedQueueDigest(emptyAnalysis)
  discard dependencyGraphDigest(emptyAnalysis)
  discard obligationListDigest(@[])
  discard solverRunDigest(@[])
  let v = initVerifiedSet()
  discard verifiedSetDigest(v)
  echo "  [OK] empty inputs compute without crash"

block:
  # six-dimension fingerprint order-independence
  let f1 = sixDimensionFingerprint("p", "q", "r", "s", "t", "u")
  let f2 = sixDimensionFingerprint("u", "t", "s", "r", "q", "p")
  failures += int(not expectEq(f1, f2, "sixDimensionFingerprint order-independent"))

block:
  # projectionDigest reuses canonicalProjectionHash (volatile stripped, keys sorted)
  let state = %*{
    "result": "Verified",
    "timestamp": 12345,
    "solverElapsedMs": 9,
    "zNodes": @["n1", "n2"]
  }
  let state2 = %*{
    "zNodes": @["n1", "n2"],
    "solverElapsedMs": 888,
    "result": "Verified",
    "timestamp": 99999
  }
  failures += int(not expectEq(projectionDigest(state), projectionDigest(state2),
    "projectionDigest strips volatile keys & sorts object keys"))
  # distinct content must differ (array order preserved by canonicalProjectionHash)
  let dN1 = projectionDigest(%*{"result": "Verified", "nodes": @["n1"]})
  let dN2 = projectionDigest(%*{"result": "Verified", "nodes": @["n2"]})
  if dN1 != dN2:
    echo "  [OK] projectionDigest differs for different content"
  else:
    echo "  [FAIL] projectionDigest should differ for different content"
    inc failures

block:
  # verifiedSetDigest is deterministic per bitset content
  var vs = initVerifiedSet()
  vs.incl(NodeId(1))
  vs.incl(NodeId(2))
  var vs2 = initVerifiedSet()
  vs2.incl(NodeId(2))
  vs2.incl(NodeId(1))
  failures += int(not expectEq(verifiedSetDigest(vs), verifiedSetDigest(vs2),
    "verifiedSetDigest deterministic"))

if failures == 0:
  echo "ALL PASS"
else:
  echo $failures & " FAILURE(S)"
quit(failures)
