## Unit tests for the deterministic verification replay harness (Phase 3.0).
## Uses custom main() pattern to avoid unittest framework crashes.
## Covers: gate_memo multi-entry regression (one gateId, many lockHashes),
## ExperimentID determinism, mutateContent/canonicalMutationSpec, declaredDeps,
## and the strict-decision fail-closed evidence semantics.

import std/[os, strutils, times, options, json]
import core/crypto/hash_kernel
import core/types/gate_types
import verification/verification_dependency
import verification/observation_pipeline
import verification/verification_query_engine
import core/gate/gate_memo
import tools/ci/verification_experiment
from tools/ci/verification_reuse_check import declaredDeps

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

  echo "=== gate_memo multi-entry regression (same gateId, one epoch) ==="

  block:
    let savedDir = getCurrentDir()
    let tmpDir = getTempDir() / ("axiom_replay_memo_" & $epochTime().int)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    setCurrentDir(tmpDir)
    try:
      let gateId = "verification-auditor"
      let testEpoch = 0
      # A and B are TWO DISTINCT lockHashes (canonical identity digests) under
      # the SAME gateId — the multi-entry index must keep BOTH addressable.
      let lockA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      let lockB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      saveGateMemo(gateId, lockA, true, testEpoch)
      saveGateMemo(gateId, lockB, true, testEpoch)
      let idx = loadMemoIndex(GateMemoBaseDir / "epoch_" & $testEpoch)
      check "A still addressable after B stored (multi-entry)":
        let found = lookupMemo(idx, gateId, lockA)
        assert found.isSome and found.get.result == true
      check "B addressable (multi-entry)":
        let found = lookupMemo(idx, gateId, lockB)
        assert found.isSome
      check "stored PASS under A has A's lockHash":
        let found = lookupMemo(idx, gateId, lockA)
        assert found.isSome and found.get.compositeLockHash == lockA
      check "unknown lockHash remains a miss":
        let found = lookupMemo(idx, gateId, "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
        assert found.isNone
    finally:
      setCurrentDir(savedDir)
      try: removeDir(tmpDir)
      except CatchableError: discard  # axiom:best-effort(test cleanup - must not affect test verdict)

  echo "=== ExperimentID determinism (definition content-addressing) ==="

  let sBase = Scenario(name: "base", mutationKind: mkNone)
  let sMut = Scenario(
    name: "semantic-mutation", mutationKind: mkAppendComment,
    targetRelPath: "src/api.nim", payload: "xp-semantic-mutation")
  let sNeutral = Scenario(
    name: "neutral-comment", mutationKind: mkAppendComment,
    targetRelPath: "docs/guides/local_exact_gate.md", payload: "xp-neutral")
  let fixtureSha = "1d772c4fabcb3ab412d7dcc1a395591818ecf363"
  let toolchain = "nim:2.2.10"
  let policy = "pol-digest-1"

  block:
    let id1 = experimentID(fixtureSha, sBase, toolchain, policy)
    let id2 = experimentID(fixtureSha, sBase, toolchain, policy)
    check "same scenario definition -> same ExperimentID":
      assert id1 == id2
    check "ExperimentID is 64 hex chars":
      assert id1.len == 64
    check "payload change -> ExperimentID changes":
      assert id1 != experimentID(fixtureSha, sMut, toolchain, policy)
    check "fixture change -> ExperimentID changes":
      assert id1 != experimentID("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", sBase, toolchain, policy)
    check "toolchain change -> ExperimentID changes":
      assert id1 != experimentID(fixtureSha, sBase, "nim:2.2.9", policy)
    check "policy change -> ExperimentID changes":
      assert id1 != experimentID(fixtureSha, sBase, toolchain, "pol-digest-2")
    check "neutral vs base differ (different definition)" :
      assert experimentID(fixtureSha, sNeutral, toolchain, policy) != id1

  echo "=== canonicalMutationSpec / mutateContent ==="

  block:
    check "canonicalMutationSpec stable & order-fixed":
      assert canonicalMutationSpec(sMut) == "mkAppendComment|src/api.nim|xp-semantic-mutation|"
      assert canonicalMutationSpec(sBase) == "mkNone|||"
    check "mkNone returns content unchanged":
      assert mutateContent("abc", sBase) == "abc"
    check "mkAppendComment appends comment line":
      assert mutateContent("proc x() = discard", sMut).endsWith("# xp-semantic-mutation\n")
    check "mkReplaceString replaces":
      let sRep = Scenario(name: "r", mutationKind: mkReplaceString,
                          targetRelPath: "src/a.nim",
                          replaceFrom: "OLD", payload: "NEW")
      assert mutateContent("a OLD b", sRep) == "a NEW b"

  echo "=== declaredDeps (gate-free deterministic closure) ==="

  block:
    let savedDir = getCurrentDir()
    let tmpDir = getTempDir() / ("axiom_replay_fix_" & $epochTime().int)
    createDir(tmpDir / "src")
    createDir(tmpDir / "data")
    createDir(tmpDir / "config")
    try:
      writeFile(tmpDir / "src" / "a.nim", "proc x() = discard\n")
      writeFile(tmpDir / "data" / "verification_auditor_baseline.json", "{\"domain_count\": 1}\n")
      writeFile(tmpDir / "config" / "gates.json", "{}\n")
      writeFile(tmpDir / "topology.lock", "{\"lock_revision\": 0}\n")
      let deps = declaredDeps(tmpDir)
      check "declaredDeps includes the subject module (dkSemantic)":
        var foundModule = false
        for d in deps:
          if depPath(d).endsWith("src/a.nim") and depKind(d) == dkSemantic:
            foundModule = true
        assert foundModule
      check "declaredDeps non-empty":
        assert deps.len > 0
    finally:
      setCurrentDir(savedDir)
      try: removeDir(tmpDir)
      except CatchableError: discard  # axiom:best-effort(test cleanup - must not affect test verdict)

  echo "=== strict decision is evidence (fail-closed) ==="

  block:
    let identity = newCanonicalIdentity("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    let cleanDeps = @[newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete)]
    let unknownDeps = @[newValidatedDependency("/proc/self/exe", rcOther, dkUnclassified, "", osUnclassified)]
    check "clean deps + matching identity -> rdReuse":
      assert decideReuseCanonical(stored, identity, cleanDeps).kind == rdReuse
    check "unknown dep -> rdRecompute (strict evidence, fail-closed)":
      assert decideReuseCanonical(stored, identity, unknownDeps).kind == rdRecompute

  echo "=== decideMemoHit semantics (forcedMiss independent of store) ==="

  block:
    # Named-variable construction: Nim 2.2.10 liftdestructors asserts on
    # anonymous tuple literals carrying a seq into Option[...].
    var entryValue: GateMemoEntry
    entryValue.compositeLockHash = "x"
    entryValue.result = true
    entryValue.timestamp = 0'i64
    entryValue.failureCategory = FailureCategory.fcTransient
    entryValue.failureReason = ""
    entryValue.findings = @[]
    let entry = some(entryValue)
    check "forcedMiss=true always yields false regardless of store":
      assert decideMemoHit(true, entry) == false
    check "forcedMiss=false with found yields true":
      assert decideMemoHit(false, entry) == true
    check "forcedMiss=false without found yields false":
      assert decideMemoHit(false, none(GateMemoEntry)) == false

  echo "=== buildCiEvidence CI report structure ==="

  block:
    putEnv("PBC_CACHE_MATCHED_KEY", "cache-key-abc-123")
    let ev = buildCiEvidence(
      "ci-gate", "eid-1", "identity-xyz", "rdReuse",
      true, 0, 1, 1, 42, "cache-key-abc-123",
      "", "", false
    )
    check "semantic contains memoHit (bool)":
      assert ev["semantic"]["memoHit"].getBool == true
    check "semantic contains identity":
      assert ev["semantic"]["identity"].getStr == "identity-xyz"
    check "semantic contains gateRuns and strictDecision":
      assert ev["semantic"]["gateRuns"].getInt == 0
      assert ev["semantic"]["strictDecision"].getStr == "rdReuse"
    check "transport carries cacheMatchedKey pass-through from env":
      assert ev["transport"]["cacheMatchedKey"].getStr == "cache-key-abc-123"
    check "epoch present":
      assert ev["epoch"].getInt == 42
    check "transport.cacheMatchedKey and semantic.identity are independent namespaces":
      assert ev.hasKey("transport") and ev["transport"].hasKey("cacheMatchedKey")
      assert ev.hasKey("semantic") and ev["semantic"].hasKey("identity")
      assert ev["transport"]["cacheMatchedKey"].getStr != ev["semantic"]["identity"].getStr
    check "no equality assertion field between cacheMatchedKey and identity":
      assert not ev.hasKey("cacheMatchedKeyEqualsIdentity")
      assert not ev.hasKey("transportEqualsSemantic")
      assert not ev.hasKey("assertion")
    check "forcedMiss field present":
      assert ev["forcedMiss"].getBool == false

  echo "API: decideMemoHit, buildCiEvidence | Tests: " & $passed & " passed, " & $failed & " failed"
  if failed > 0: quit(1)

main()