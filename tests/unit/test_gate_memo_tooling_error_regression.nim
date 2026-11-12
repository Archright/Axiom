## test_gate_memo_tooling_error_regression.nim
## Regression test: a gate run that produced NO verdict must never become a
## durable memo verdict.
##
## The bug: `result: bool` is the only verdict carrier in GateMemoEntry, so a
## tool failure (CAS compile failure, crash, unclassified exit) was recorded
## with the same shape as a real FAIL. `classifyFailure` maps a synthesized
## exit code 1 to `fcValidation` (src/gate/orchestrator_pure.nim), and
## src/gate/orchestrator/hook/executor.nim persists that verdict on every
## `res.ok == false` dispatch — including the compile-failure return at
## executor.nim:154. The next run then read the memo back as a settled
## "failed gate" and skipped execution entirely.
##
## The fix: `classifyMemoOutcome` (src/core/gate/gate_memo.nim) splits the
## verdict axis from the execution-state axis. moNotEvaluated is never
## persisted (saveGateMemo) and never reused (parseMemoEntry /
## loadLegacyGateMemo), which also neutralizes memos already on disk.
##
## Run: AXIOM_CI_PRESERVE_CACHE=1 AXIOM_HERMETIC_BUILDING=1 \
##      nim c -r --hints:off --nimcache:/tmp/memofix \
##           tests/unit/test_gate_memo_tooling_error_regression.nim

import std/[os, strutils, times, options, json, tables]
import core/json/json_utils
import core/gate/gate_memo
import core/types/gate_types

proc main() =
  var passed = 0
  var failed = 0

  ## Non-aborting check: every check is evaluated and reported, so one failure
  ## never hides the state of the others.
  template check(name: string, cond: untyped) =
    block:
      if (cond):
        inc passed
        echo "  PASS: " & name
      else:
        inc failed
        echo "  FAIL: " & name

  let savedDir = getCurrentDir()

  proc makeMemoTmpDir(prefix: string): string =
    let tmpDir = getTempDir() / (prefix & $epochTime().int)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    tmpDir

  proc gateIdInAnyMemoFile(epochDir: string; gateId: string): bool =
    ## True if any CAS memo file under epochDir records this gateId.
    if not dirExists(epochDir): return false
    for kind, subdir in walkDir(epochDir):
      if kind != pcDir: continue
      for fileKind, filePath in walkDir(subdir):
        if fileKind != pcFile: continue
        try:
          if parseJsonOpt(readFile(filePath)).get(newJObject()){"gateId"}.getStr("") == gateId:
            return true
        except CatchableError:
          # An unreadable memo cannot record this gateId, so it contributes no
          # match — the same result the non-excepting path returns. Malformed
          # JSON never reaches here: parseJsonOpt already yields an empty node.
          discard  # axiom:best-effort(ioboundary catch)

  # ══════════════════════════════════════════════════════════════════
  # 1. The axis itself: verdict vs. execution state
  # ══════════════════════════════════════════════════════════════════
  echo "=== 1. classifyMemoOutcome: verdict axis vs. execution-state axis ==="

  check "PASS is a verdict",
    classifyMemoOutcome(true, fcTransient, "") == moVerdictPass
  check "evidenced fcValidation FAIL is a verdict",
    classifyMemoOutcome(false, fcValidation, "import cycle") == moVerdictFail
  check "evidenced fcTransient FAIL is a verdict",
    classifyMemoOutcome(false, fcTransient, "network timeout") == moVerdictFail
  check "unevidenced fcValidation FAIL is NOT a verdict (tool failure shape)",
    classifyMemoOutcome(false, fcValidation, "") == moNotEvaluated
  check "blank-only reason is NOT a verdict",
    classifyMemoOutcome(false, fcValidation, "   \n ") == moNotEvaluated
  check "fcPermanent FAIL stays a non-verdict (unchanged policy)",
    classifyMemoOutcome(false, fcPermanent, "missing config") == moNotEvaluated
  check "fcUnknown FAIL stays a non-verdict (unchanged policy)",
    classifyMemoOutcome(false, fcUnknown, "cannot classify") == moNotEvaluated

  # ══════════════════════════════════════════════════════════════════
  # 2. Tool failure is never persisted as a verdict memo
  # ══════════════════════════════════════════════════════════════════
  echo "=== 2. tool failure is not durable: re-run instead of reuse ==="

  echo "--- Test 2a: CAS compile-failure shape (fcValidation, no evidence) ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_toolingerr_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "cas-compile-fail-gate"
    let lockHash = "compile-fail-lock-1"
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    # This is exactly what the orchestrator persists when dispatchGate returns
    # ok=false for a CAS compile failure: exit 1 -> fcValidation, and stdout
    # ("CAS compile failed for <id>") yields no "FAIL" line -> empty reason.
    saveGateMemo(gateId, lockHash, false, testEpoch, fcValidation, "")

    check "no memo file is written at all",
      not gateIdInAnyMemoFile(epochDir, gateId)
    check "loadGateMemo yields none (gate re-runs)",
      loadGateMemo(gateId, lockHash, testEpoch).isNone

    let index = loadMemoIndex(epochDir)
    check "production path lookupMemo yields none",
      lookupMemo(index, gateId, lockHash).isNone

  echo "--- Test 2b: crash/unclassified shape (fcTransient, no evidence) ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_crashshape_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "crashed-gate"
    let lockHash = "crash-lock-2"
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    saveGateMemo(gateId, lockHash, false, testEpoch, fcTransient, "")

    check "no memo file is written at all",
      not gateIdInAnyMemoFile(epochDir, gateId)
    check "loadGateMemo yields none",
      loadGateMemo(gateId, lockHash, testEpoch).isNone

  # ══════════════════════════════════════════════════════════════════
  # 3. Real verdicts keep memoizing (no regression)
  # ══════════════════════════════════════════════════════════════════
  echo "=== 3. real verdicts remain durable ==="

  echo "--- Test 3a: evidenced fcValidation FAIL is reused ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_valfail_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "import-encapsulation-gate"
    let lockHash = "valfail-lock-3"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcValidation, "import cycle")

    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    check "evidenced fcValidation FAIL is cached", loaded.isSome
    check "cached verdict is FAIL", loaded.isSome and not loaded.get.result
    check "cached category is fcValidation",
      loaded.isSome and loaded.get.failureCategory == fcValidation
    check "cached reason survives",
      loaded.isSome and loaded.get.failureReason == "import cycle"

    let index = loadMemoIndex(GateMemoBaseDir / "epoch_" & $testEpoch)
    check "production path reuses the verdict",
      lookupMemo(index, gateId, lockHash).isSome

  echo "--- Test 3b: PASS is reused ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_passverdict_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "pass-verdict-gate"
    let lockHash = "pass-lock-4"

    saveGateMemo(gateId, lockHash, true, testEpoch)

    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    check "PASS is cached", loaded.isSome
    check "cached verdict is PASS", loaded.isSome and loaded.get.result

  # ══════════════════════════════════════════════════════════════════
  # 4. Memos already on disk must be ignored (fail-closed), never flipped
  # ══════════════════════════════════════════════════════════════════
  echo "=== 4. pre-existing tool-failure memos are ignored, not replayed ==="

  echo "--- Test 4a: old CAS-layout memo written directly (bypasses saveGateMemo) ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_oldcas_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "legacy-cas-fail-gate"
    let lockHash = "oldcas-lock-5"
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    # Reconstruct the exact bytes a pre-fix saveGateMemo would have written.
    var j = %*{
      "gateId": gateId,
      "compositeLockHash": lockHash,
      "result": false,
      "timestamp": getTime().toUnix(),
      "epoch": testEpoch,
      "expiresAt": 0,
      "failureCategory": $fcValidation,
      "failureReason": ""
    }
    let jsonContent = $j & "\n"
    let casFilePath = casPath(epochDir, computeCasAddress(jsonContent))
    createDir(casFilePath.parentDir())
    writeFile(casFilePath, jsonContent)

    check "old tool-failure memo yields no verdict via loadGateMemo",
      loadGateMemo(gateId, lockHash, testEpoch).isNone

    let index = loadMemoIndex(epochDir)
    check "old tool-failure memo never enters the index",
      lookupMemo(index, gateId, lockHash).isNone
    check "index is empty (no verdict survives)", index.entries.len == 0

  echo "--- Test 4b: old flat-file memo written directly ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_oldflat_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "legacy-flat-fail-gate"
    let lockHash = "oldflat-lock-6"
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    let legacyPath = epochDir / (gateId & ".json")
    let j = %*{
      "compositeLockHash": lockHash,
      "result": false,
      "timestamp": getTime().toUnix(),
      "failureCategory": $fcValidation,
      "failureReason": ""
    }
    writeFile(legacyPath, $j & "\n")

    check "old flat tool-failure memo yields no verdict",
      loadLegacyGateMemo(gateId, testEpoch).isNone
    check "loadGateMemo yields none via legacy fallback",
      loadGateMemo(gateId, lockHash, testEpoch).isNone

  echo "--- Test 4c: a neighboring real verdict in the same epoch is untouched ---"
  block:
    let tmpDir = makeMemoTmpDir("axiom_mixed_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let epochDir = GateMemoBaseDir / "epoch_" & $testEpoch
    createDir(epochDir)

    # Old tool-failure memo (must be dropped) alongside a real PASS memo.
    var stale = %*{
      "gateId": "stale-tooling-gate",
      "compositeLockHash": "stale-lock-7",
      "result": false,
      "timestamp": getTime().toUnix(),
      "epoch": testEpoch,
      "expiresAt": 0,
      "failureCategory": $fcValidation,
      "failureReason": ""
    }
    let staleContent = $stale & "\n"
    let stalePath = casPath(epochDir, computeCasAddress(staleContent))
    createDir(stalePath.parentDir())
    writeFile(stalePath, staleContent)

    saveGateMemo("healthy-gate", "healthy-lock-8", true, testEpoch)

    let index = loadMemoIndex(epochDir)
    check "stale tool-failure memo is dropped",
      lookupMemo(index, "stale-tooling-gate", "stale-lock-7").isNone
    let healthy = lookupMemo(index, "healthy-gate", "healthy-lock-8")
    check "healthy PASS memo still loads", healthy.isSome
    check "healthy PASS verdict is true", healthy.isSome and healthy.get.result

  # ══════════════════════════════════════════════════════════════════
  # 5. Unchanged policy guards (regression)
  # ══════════════════════════════════════════════════════════════════
  echo "=== 5. fcPermanent / fcUnknown policy unchanged ==="

  block:
    let tmpDir = makeMemoTmpDir("axiom_permguard_")
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    saveGateMemo("perm-gate", "perm-lock-9", false, testEpoch, fcPermanent,
                 "missing config")
    saveGateMemo("unknown-gate", "unknown-lock-10", false, testEpoch,
                 fcUnknown, "cannot classify")

    let index = loadMemoIndex(GateMemoBaseDir / "epoch_" & $testEpoch)
    check "fcPermanent FAIL is still not reusable",
      lookupMemo(index, "perm-gate", "perm-lock-9").isNone
    check "fcUnknown FAIL is still not reusable",
      lookupMemo(index, "unknown-gate", "unknown-lock-10").isNone

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)
  echo "ALL CHECKS PASSED"

main()