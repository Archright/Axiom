## test_gate_memo_fcunknown_regression.nim
## Regression test: fcUnknown FAIL verdicts must NOT be cached/reused via the
## production loadMemoIndex + lookupMemo path (DEBT#452).
##
## The bug: fcUnknown FAIL entries were silently cached and reused even though
## their semantics require cacheTtl=0 (fail-closed, always re-execute).
## The fix: parseMemoEntry (gate_memo.nim:537) now returns none for fcUnknown
## FAIL entries, so loadMemoIndex never inserts them into the MemoIndex and
## lookupMemo can never return a cached fcUnknown verdict.
##
## Run: nim c -r --hints:off tests/unit/test_gate_memo_fcunknown_regression.nim

import std/[os, strutils, times, options, json]
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

  let savedDir = getCurrentDir()

  # Helper: create a fresh tmp dir with the .axiom/cache/gate_memo tree.
  proc makeMemoTmpDir(prefix: string): string =
    let tmpDir = getTempDir() / (prefix & $epochTime().int)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    return tmpDir

  # ══════════════════════════════════════════════════════════════════
  # DEBT#452: fcUnknown FAIL must NOT survive loadMemoIndex + lookupMemo
  # ══════════════════════════════════════════════════════════════════
  echo "=== fcUnknown regression: loadMemoIndex + lookupMemo (DEBT#452) ==="

  echo "--- Test 1: fcUnknown FAIL entry is NOT reused via production path ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_fcunknown_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "fcunknown-regression-gate"
    let lockHash = "fcunknown-lock-123"

    # Save an fcUnknown FAIL entry through the real saveGateMemo (writes CAS).
    saveGateMemo(gateId, lockHash, false, testEpoch, fcUnknown,
                 "theater detection: cannot classify")

    # Load the memo index — parseMemoEntry filters fcUnknown out internally.
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    let index = loadMemoIndex(epochDir)

    # lookupMemo must yield none: fcUnknown FAIL is never reusable.
    let found = lookupMemo(index, gateId, lockHash)
    check "fcUnknown FAIL lookup returns none (not reused)":
      assert found.isNone

  echo "--- Test 2: positive sanity — PASS entry IS cached/reused ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_pass_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "pass-regression-gate"
    let lockHash = "pass-lock-456"

    # Save a PASS entry through the real saveGateMemo.
    saveGateMemo(gateId, lockHash, true, testEpoch)

    # Load the memo index — PASS entries ARE inserted.
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    let index = loadMemoIndex(epochDir)

    # lookupMemo must yield some — PASS entry is reusable.
    let found = lookupMemo(index, gateId, lockHash)
    check "PASS entry lookup returns some (cached/reused)":
      assert found.isSome
    check "cached result is true":
      assert found.get.result == true
    check "cached compositeLockHash matches":
      assert found.get.compositeLockHash == lockHash

  echo "--- Test 3: fcUnknown FAIL via legacy flat-file returns none ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_legacy_unknown_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "legacy-unknown-gate"
    let lockHash = "legacy-unknown-lock-789"
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    # Write a flat legacy memo file with fcUnknown FAIL (bypasses saveGateMemo).
    let legacyPath = epochDir / (gateId & ".json")
    let j = %*{
      "compositeLockHash": lockHash,
      "result": false,
      "timestamp": getTime().toUnix(),
      "failureCategory": $fcUnknown,
      "failureReason": "theater detection: cannot classify"
    }
    writeFile(legacyPath, $j & "\n")

    # loadLegacyGateMemo must return none for fcUnknown FAIL.
    let loaded = loadLegacyGateMemo(gateId, testEpoch)
    check "loadLegacyGateMemo returns none for fcUnknown FAIL":
      assert loaded.isNone

  echo "--- Test 4: fcPermanent FAIL still excluded (regression guard) ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_perm_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "perm-regression-gate"
    let lockHash = "perm-lock-000"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcPermanent, "missing config")

    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    let index = loadMemoIndex(epochDir)
    let found = lookupMemo(index, gateId, lockHash)
    check "fcPermanent FAIL lookup returns none (still excluded)":
      assert found.isNone

  # ══════════════════════════════════════════════════════════════════
  # Summary
  # ══════════════════════════════════════════════════════════════════
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
