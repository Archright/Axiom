## Unit tests for semantic_query_types.nim — Semantic Query Contract.
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: changing each single semantic input produces a different
## provisional QueryID; identical inputs produce the same ID (deterministic).

import std/[os, strutils]
import core/crypto/hash_kernel
import verification/semantic_query_types

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # Pre-computed hex digests for fixed test inputs.
  let
    fixedHex   = hash_kernel.sha256Hex("fixed")
    snapHex    = hash_kernel.sha256Hex("snapshot-content")
    testClHex  = hash_kernel.sha256Hex("test-closure")
    baseHex    = hash_kernel.sha256Hex("baseline")
    lockHex    = hash_kernel.sha256Hex("lock")
    policyHex  = hash_kernel.sha256Hex("policy")
    gateHex    = hash_kernel.sha256Hex("gate-impl")

  func baseQuery(): SemanticQuery =
    SemanticQuery(
      gateId: newGateId("verification-auditor"),
      snapshot: newSnapshotDigest(snapHex),
      testClosure: newTestClosureDigest(testClHex),
      baseline: newBaselineDigest(baseHex),
      lock: newLockDigest(lockHex),
      policy: newPolicyDigest(policyHex),
      gateImpl: newGateImplDigest(gateHex),
      selectionRuleVersion: "1",
      selectionRuleDigest: selectionRuleDigest(SelectionRule(
        includeDirs: @["src"], skipDirs: @[".git"],
        symlinkPolicy: spFollowRegularFiles, version: 1
      ))
    )

  echo "=== Semantic Query — determinism (same inputs => same ID) ==="

  block:
    let q1 = baseQuery()
    let q2 = baseQuery()
    let id1 = provisionalQueryID(q1)
    let id2 = provisionalQueryID(q2)
    check "same query produces identical QueryID":
      assert id1 == id2
    check "QueryID is non-empty":
      assert string(id1).len > 0

  echo ""
  echo "=== Semantic Query — sensitivity (each component change => different ID) ==="

  block:
    let qBase = baseQuery()
    let idBase = provisionalQueryID(qBase)

    # Change snapshot
    var q = qBase
    q.snapshot = newSnapshotDigest(hash_kernel.sha256Hex("different-snapshot"))
    check "changing snapshot -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change testClosure
    q = qBase
    q.testClosure = newTestClosureDigest(hash_kernel.sha256Hex("different-test-closure"))
    check "changing testClosure -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change baseline
    q = qBase
    q.baseline = newBaselineDigest(hash_kernel.sha256Hex("different-baseline"))
    check "changing baseline -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change lock
    q = qBase
    q.lock = newLockDigest(hash_kernel.sha256Hex("different-lock"))
    check "changing lock -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change policy
    q = qBase
    q.policy = newPolicyDigest(hash_kernel.sha256Hex("different-policy"))
    check "changing policy -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change gateImpl
    q = qBase
    q.gateImpl = newGateImplDigest(hash_kernel.sha256Hex("different-gate-impl"))
    check "changing gateImpl -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change selectionRuleVersion
    q = qBase
    q.selectionRuleVersion = "2"
    q.selectionRuleDigest = selectionRuleDigest(SelectionRule(
      includeDirs: @["src"], skipDirs: @[".git"],
      symlinkPolicy: spFollowRegularFiles, version: 2
    ))
    check "changing selectionRuleVersion -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change selectionRule includeDirs
    q = qBase
    q.selectionRuleDigest = selectionRuleDigest(SelectionRule(
      includeDirs: @["src", "extra"], skipDirs: @[".git"],
      symlinkPolicy: spFollowRegularFiles, version: 1
    ))
    check "changing selectionRule includeDirs -> different QueryID":
      assert provisionalQueryID(q) != idBase

    # Change gateId does NOT change QueryID (provenance, not a component)
    q = qBase
    q.gateId = newGateId("different-gate")
    check "changing gateId does NOT change QueryID (provenance-only)":
      assert provisionalQueryID(q) == idBase

  echo ""
  echo "=== Distinct digest types are distinct (no cross-contamination) ==="

  block:
    let hexVal = hash_kernel.sha256Hex("same-hex")
    let snap = newSnapshotDigest(hexVal)
    let testCl = newTestClosureDigest(hexVal)
    check "distinct types carry the same hex value but are compiler-separated":
      assert string(snap) == string(testCl)  # same underlying hex
      # The compiler enforces that SnapshotDigest != TestClosureDigest
      # at the type level (distinct string).

  echo ""
  echo "=== SelectionRule digest is deterministic ==="

  block:
    let r1 = SelectionRule(includeDirs: @["b", "a"], skipDirs: @["z", ".git"], symlinkPolicy: spFollowRegularFiles, version: 1)
    let r2 = SelectionRule(includeDirs: @["a", "b"], skipDirs: @[".git", "z"], symlinkPolicy: spFollowRegularFiles, version: 1)
    let d1 = selectionRuleDigest(r1)
    let d2 = selectionRuleDigest(r2)
    check "sorting dirs makes rule digest order-independent":
      assert d1 == d2

  echo ""
  echo "=== Distinct digests produce distinct QueryIDs ==="

  block:
    let q1 = baseQuery()
    var q2 = baseQuery()
    # Change exactly one digest
    q2.snapshot = newSnapshotDigest(hash_kernel.sha256Hex("x"))
    check "different snapshot -> different QueryID":
      assert provisionalQueryID(q1) != provisionalQueryID(q2)

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()
