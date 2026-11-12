## test_reuse_canonical.nim — Unit tests for canonical identity reuse decision.
##
## Usage: nim c -r --hints:off tests/unit/test_reuse_canonical.nim
##
## TRAPS: parseopt positional arg text is in p.key NOT p.val;
##        quit() skips finally — use proc main(): int + quit(main()).

import std/[os, strutils, times, options, json]

import verification/semantic_query_types
import verification/verification_dependency
import verification/producer_identity
import verification/observation_pipeline
import verification/verification_query_engine
import core/gate/gate_memo
import core/types/gate_types

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

  # ═══════════════════════════════════════════════════════════════
  # decideReuseCanonical semantics
  # ═══════════════════════════════════════════════════════════════
  echo "=== decideReuseCanonical tests ==="

  echo "--- Test 1: clean deps + matching identity → rdReuse ---"
  block:
    let identity = newCanonicalIdentity("abc123def456")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    let cleanDeps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete),
      newValidatedDependency("tests/gateway/foo.feature", rcTestGateway, dkSemantic, "", osComplete),
    ]
    let decision = decideReuseCanonical(stored, identity, cleanDeps)
    check "clean deps + matching identity → rdReuse":
      assert decision.kind == rdReuse
      assert decision.verdict == "PASS"

  echo "--- Test 2: Gate1 identity mismatch → rdRecompute ---"
  block:
    let identityX = newCanonicalIdentity("abc123def456")
    let identityY = newCanonicalIdentity("def456abc123")
    let stored = newStoredVerificationResultCanonical(identityX, "PASS")
    let cleanDeps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete),
    ]
    let decision = decideReuseCanonical(stored, identityY, cleanDeps)
    check "identity mismatch → rdRecompute":
      assert decision.kind == rdRecompute

  echo "--- Test 3: Gate2 dep drRecompute (osIncomplete) → rdRecompute ---"
  block:
    let identity = newCanonicalIdentity("abc123def456")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    let deps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osIncomplete),
    ]
    let decision = decideReuseCanonical(stored, identity, deps)
    check "dep osIncomplete → rdRecompute":
      assert decision.kind == rdRecompute

  echo "--- Test 4: Gate2 dep drFailClosed (dkUnclassified) → rdRecompute ---"
  block:
    let identity = newCanonicalIdentity("abc123def456")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    let deps = @[
      newValidatedDependency("src/unknown.nim", rcModuleExistence, dkUnclassified, "", osUnclassified),
    ]
    let decision = decideReuseCanonical(stored, identity, deps)
    check "dep dkUnclassified → rdRecompute":
      assert decision.kind == rdRecompute

  echo "--- Test 5: Gate2 mixed clean + bad deps → rdRecompute ---"
  block:
    let identity = newCanonicalIdentity("abc123def456")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    let deps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete),
      newValidatedDependency("src/unknown.nim", rcModuleExistence, dkUnclassified, "", osUnclassified),
    ]
    let decision = decideReuseCanonical(stored, identity, deps)
    check "mixed clean + unknown deps → rdRecompute":
      assert decision.kind == rdRecompute

  # ═══════════════════════════════════════════════════════════════
  # newStoredVerificationResultCanonical roundtrip
  # ═══════════════════════════════════════════════════════════════
  echo "=== newStoredVerificationResultCanonical roundtrip ==="
  block:
    let identity = newCanonicalIdentity("abc123def456")
    let stored = newStoredVerificationResultCanonical(identity, "PASS")
    check "queryID matches canonical identity":
      assert string(stored.queryID) == string(identity)
    check "verdict preserved":
      assert stored.verdict == "PASS"

  # ═══════════════════════════════════════════════════════════════
  # CASE A / CASE B at unit level
  # ═══════════════════════════════════════════════════════════════
  echo "=== CASE A/B unit tests ==="

  echo "--- Test 6a: CASE A — stored PASS under identity X, same X → rdReuse ---"
  block:
    let identityX = newCanonicalIdentity("case-a-identity")
    let stored = newStoredVerificationResultCanonical(identityX, "PASS")
    let cleanDeps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete),
    ]
    let decision = decideReuseCanonical(stored, identityX, cleanDeps)
    check "CASE A → rdReuse with PASS verdict":
      assert decision.kind == rdReuse
      assert decision.verdict == "PASS"

  echo "--- Test 6b: CASE B — stored PASS under identity X, different Y → rdRecompute ---"
  block:
    let identityX = newCanonicalIdentity("case-a-identity")
    let identityY = newCanonicalIdentity("case-b-identity")
    let stored = newStoredVerificationResultCanonical(identityX, "PASS")
    let cleanDeps = @[
      newValidatedDependency("src/foo.nim", rcModuleContent, dkSemantic, "", osComplete),
    ]
    let decision = decideReuseCanonical(stored, identityY, cleanDeps)
    check "CASE B → rdRecompute":
      assert decision.kind == rdRecompute

  # ═══════════════════════════════════════════════════════════════
  # Memo persistence via the REAL store
  # ═══════════════════════════════════════════════════════════════
  echo "=== Memo persistence via real store ==="
  let savedDir = getCurrentDir()
  let tmpDir = getTempDir() / ("axiom_reuse_memo_test_" & $epochTime().int)
  createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
  setCurrentDir(tmpDir)
  try:
    echo "--- Test 7a: save PASS → loadMemoIndex+lookupMemo → some (hit) ---"
    block:
      let testEpoch = 0
      # NOTE: MemoIndex is keyed by gateId only (ONE entry per gateId per
      # epoch — the existing store's API limit). Use a distinct gateId per
      # block, exactly like the fcUnknown regression test does.
      let gateId = "rc-reuse-7a"
      let lockHash = "case-a-identity"
      saveGateMemo(gateId, lockHash, true, testEpoch)
      let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
      let index = loadMemoIndex(epochDir)
      let found = lookupMemo(index, gateId, lockHash)
      check "PASS entry lookup returns some":
        assert found.isSome
      check "cached result is true":
        assert found.get.result == true
      check "cached compositeLockHash matches":
        assert found.get.compositeLockHash == lockHash

    echo "--- Test 7b: different lockHash → none (miss) ---"
    block:
      let testEpoch = 0
      let gateId = "rc-reuse-7a"
      let differentLockHash = "case-b-identity"
      let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
      let index = loadMemoIndex(epochDir)
      let found = lookupMemo(index, gateId, differentLockHash)
      check "different lockHash returns none":
        assert found.isNone

    echo "--- Test 7c: fcUnknown FAIL → none via loadMemoIndex+lookupMemo ---"
    block:
      let testEpoch = 0
      let gateId = "rc-reuse-7c"
      let unknownLockHash = "unknown-lock-789"
      saveGateMemo(gateId, unknownLockHash, false, testEpoch, fcUnknown,
                    "theater detection: cannot classify")
      let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
      let index = loadMemoIndex(epochDir)
      let found = lookupMemo(index, gateId, unknownLockHash)
      check "fcUnknown FAIL lookup returns none (not reused)":
        assert found.isNone

    echo "--- Test 7d: positive sanity — PASS entry IS cached/reused ---"
    block:
      let testEpoch = 0
      let gateId = "rc-reuse-7d"
      let passLockHash = "pass-lock-456"
      saveGateMemo(gateId, passLockHash, true, testEpoch)
      let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
      let index = loadMemoIndex(epochDir)
      let found = lookupMemo(index, gateId, passLockHash)
      check "PASS entry lookup returns some (cached/reused)":
        assert found.isSome
      check "cached result is true":
        assert found.get.result == true
  finally:
    setCurrentDir(savedDir)
    try: removeDir(tmpDir)
    except CatchableError: discard  # axiom:best-effort(test cleanup - must not affect test verdict)

  # ═══════════════════════════════════════════════════════════════
  # Summary
  # ═══════════════════════════════════════════════════════════════
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()