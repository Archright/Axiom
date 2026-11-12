## Unit tests for the canonical VerificationIdentity (S2: Provisional -> Validated -> Canonical).
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: dependencyClosureDigest determinism/order/dedupe/sensitivity,
## canonicalVerificationIdentity 3-component boundary preservation,
## and CanonicalVerificationIdentity distinct type.

import std/[strutils]
import core/crypto/hash_kernel
import verification/verification_dependency
import verification/observation_pipeline
import verification/semantic_query_types
import verification/producer_identity

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

  let hA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let hB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let hC = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let hD = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

  # Dependency fixtures (semantic + one unknown)
  let depSem = newValidatedDependency("src/a.nim", rcModuleContent, dkSemantic, "d1", osComplete)
  let depPro = newValidatedDependency("HEAD", rcCommitId, dkProvenance, "", osComplete)
  let depUnk = newValidatedDependency("/proc/self/exe", rcOther, dkUnclassified, "", osUnclassified)

  echo "=== dependencyClosureDigest: determinism & order ==="

  block:
    let c1 = dependencyClosureDigest(@[depSem, depPro, depUnk])
    let c2 = dependencyClosureDigest(@[depUnk, depSem, depPro])
    check "same deps (any order) -> same digest":
      assert c1 == c2
    check "digest is 64 hex chars":
      assert c1.len == 64

  block:
    let dups = dependencyClosureDigest(@[depSem, depSem, depPro])
    let dedup = dependencyClosureDigest(@[depSem, depPro])
    check "duplicate entries collapsed (duplicate-safe)" :
      assert dups == dedup

  block:
    let base = dependencyClosureDigest(@[depSem, depPro])
    check "kind change -> digest changes":
      assert dependencyClosureDigest(@[newValidatedDependency("src/a.nim", rcModuleContent, dkUnclassified, "d1", osComplete), depPro]) != base
    check "status change -> digest changes":
      assert dependencyClosureDigest(@[newValidatedDependency("src/a.nim", rcModuleContent, dkSemantic, "d1", osIncomplete), depPro]) != base
    check "contentDigest change -> digest changes":
      assert dependencyClosureDigest(@[newValidatedDependency("src/a.nim", rcModuleContent, dkSemantic, "d2", osComplete), depPro]) != base
    check "path change -> digest changes":
      assert dependencyClosureDigest(@[newValidatedDependency("src/b.nim", rcModuleContent, dkSemantic, "d1", osComplete), depPro]) != base
    check "empty closure -> stable digest":
      assert dependencyClosureDigest(@[]) == dependencyClosureDigest(@[])

  echo "=== canonicalVerificationIdentity: 3-component identity ==="

  let pi = newProducerIdentity(
    gateSourceClosure = hA, auditorSourceClosure = hB,
    compilerExeDigest = hC, compilerVersion = hA,
    hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
  let sq = SemanticQuery(
    gateId: newGateId("g"),
    snapshot: newSnapshotDigest(hA),
    testClosure: newTestClosureDigest(hB),
    baseline: newBaselineDigest(hC),
    lock: newLockDigest(hD),
    policy: newPolicyDigest(hA),
    gateImpl: newGateImplDigest(hB),
    selectionRuleVersion: "1",
    selectionRuleDigest: hC)
  let closure = dependencyClosureDigest(@[depSem, depPro])

  block:
    check "same SQ+PI+closure -> same identity":
      assert canonicalVerificationIdentity(sq, pi, closure) == canonicalVerificationIdentity(sq, pi, closure)
    check "closure change -> identity changes (THE canonicalization property)":
      assert canonicalVerificationIdentity(sq, pi, closure) != canonicalVerificationIdentity(sq, pi, dependencyClosureDigest(@[depUnk]))
    check "SQ change -> identity changes":
      let sq2 = SemanticQuery(
        gateId: newGateId("g"), snapshot: newSnapshotDigest(hB),
        testClosure: newTestClosureDigest(hB), baseline: newBaselineDigest(hC),
        lock: newLockDigest(hD), policy: newPolicyDigest(hA),
        gateImpl: newGateImplDigest(hB), selectionRuleVersion: "1",
        selectionRuleDigest: hC)
      assert canonicalVerificationIdentity(sq, pi, closure) != canonicalVerificationIdentity(sq2, pi, closure)
    check "PI change -> identity changes":
      let pi2 = newProducerIdentity(
        gateSourceClosure = hB, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
      assert canonicalVerificationIdentity(sq, pi, closure) != canonicalVerificationIdentity(sq, pi2, closure)
    check "deps overload equals explicit-closure version":
      assert canonicalVerificationIdentity(sq, pi, @[depSem, depPro]) == canonicalVerificationIdentity(sq, pi, closure)
    check "identity is 64 hex chars":
      assert canonicalVerificationIdentity(sq, pi, closure).len == 64

  block:
    # Boundary preservation: SQ bytes vs PI bytes are distinct components —
    # swapping their (distinct) hex values yields a different identity.
    let sqSwap = SemanticQuery(
      gateId: newGateId("g"), snapshot: newSnapshotDigest(hB),
      testClosure: newTestClosureDigest(hB), baseline: newBaselineDigest(hC),
      lock: newLockDigest(hD), policy: newPolicyDigest(hA),
      gateImpl: newGateImplDigest(hB), selectionRuleVersion: "1",
      selectionRuleDigest: hC)
    check "component order boundary preserved (SQ/PI swap)":
      let swappedPi = newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hA,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
      # sq(payload B-snapshot) with pi(gateSourceClosure A) vs sq(payload A) with pi(A):
      assert canonicalVerificationIdentity(sqSwap, pi, closure) !=
             canonicalVerificationIdentity(sq, swappedPi, closure)

  echo "=== CanonicalVerificationIdentity distinct type ==="

  block:
    let id1 = newCanonicalVerificationIdentity(hA)
    let id2 = newCanonicalVerificationIdentity(hA)
    let id3 = newCanonicalVerificationIdentity(hB)
    check "same hex -> same identity, != works":
      assert id1 == id2 and id1 != id3
    check "$ roundtrip":
      assert $id1 == hA

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()