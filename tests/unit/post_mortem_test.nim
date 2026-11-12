{.push raises: [CatchableError].}

## Post-Mortem Unit Tests
## Verifies failed build preservation, listing, loading, and cleanup.

import std/[os, json, strutils, tables, times, unittest]
import core/gate/post_mortem

var testDir: string
var origDir: string

proc setup() =
  origDir = getCurrentDir()
  testDir = getTempDir() / "axiom_post_mortem_test_" & $epochTime().int
  createDir(testDir)
  setCurrentDir(testDir)

proc teardown() =
  setCurrentDir(origDir)
  removeDir(testDir)

suite "PostMortem":
  setup()

  test "preserveFailed creates result.json and inputs.json":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    let record = PostMortemRecord(
      actionKey: "abcdef1234567890",
      gateId: "hermetic-build",
      failedAt: 1700000000.0,
      stdout: "build output",
      stderr: "error details",
      exitCode: 1,
      inputs: {"src/main.nim": "hash_a", "src/lib.nim": "hash_b"}.toTable,
      namespaceConfig: "{}"
    )
    preserveFailed(record)

    let dir = FailedBuildsDir / "abcdef1234567890"
    check dirExists(dir)
    check fileExists(dir / "result.json")
    check fileExists(dir / "inputs.json")

  test "preserveFailed writes correct fields in result.json":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    let record = PostMortemRecord(
      actionKey: "test123",
      gateId: "integrity-gate",
      failedAt: 1700000000.0,
      stdout: "stdout text",
      stderr: "stderr text",
      exitCode: 42,
      inputs: initTable[string, string](),
      namespaceConfig: "{\"key\":\"val\"}"
    )
    preserveFailed(record)

    let rj = parseJson(readFile(FailedBuildsDir / "test123" / "result.json"))
    check rj["gateId"].getStr() == "integrity-gate"
    check rj["exitCode"].getInt() == 42
    check rj["stdout"].getStr() == "stdout text"
    check rj["stderr"].getStr() == "stderr text"
    check rj["actionKey"].getStr() == "test123"

  test "listFailed returns directory names of failed builds":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    preserveFailed(PostMortemRecord(
      actionKey: "aaa_key", gateId: "g1", failedAt: 100.0,
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))
    preserveFailed(PostMortemRecord(
      actionKey: "zzz_key", gateId: "g2", failedAt: 200.0,
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))

    let failed = listFailed()
    check failed.len == 2
    # Most recent first (reversed sort by name)
    check failed[0] == "zzz_key"
    check failed[1] == "aaa_key"

  test "listFailed excludes _latest symlink directory entries":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()
    preserveFailed(PostMortemRecord(
      actionKey: "real_key", gateId: "g1", failedAt: 100.0,
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))

    let failed = listFailed()
    for name in failed:
      check not name.startsWith("_")

  test "loadRecord restores all fields from disk":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    let inputs = {"file_a.nim": "hash_aaa", "file_b.nim": "hash_bbb"}.toTable
    preserveFailed(PostMortemRecord(
      actionKey: "load_test_key",
      gateId: "load-gate",
      failedAt: 1700000000.0,
      stdout: "out data",
      stderr: "err data",
      exitCode: 7,
      inputs: inputs,
      namespaceConfig: "{\"ns\":\"test\"}"
    ))

    let loaded = loadRecord("load_test_key")
    check loaded.actionKey == "load_test_key"
    check loaded.gateId == "load-gate"
    check loaded.exitCode == 7
    check loaded.stdout == "out data"
    check loaded.stderr == "err data"
    check loaded.inputs["file_a.nim"] == "hash_aaa"
    check loaded.inputs["file_b.nim"] == "hash_bbb"

  test "cleanPostMortem removes entries older than maxAge":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    preserveFailed(PostMortemRecord(
      actionKey: "old_entry_123456789012",
      gateId: "g1",
      failedAt: 1000.0,  # very old epoch
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))

    let before = listFailed()
    check before.len == 1

    # maxAge=1.0 second should remove entry from epoch 1000.0
    cleanPostMortem(maxAge = 1.0)
    let after = listFailed()
    check after.len == 0

  test "cleanPostMortem preserves recent entries":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    let now = epochTime()
    preserveFailed(PostMortemRecord(
      actionKey: "recent_key_12345678",
      gateId: "g2",
      failedAt: now,
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))

    cleanPostMortem(maxAge = 86400.0)
    let after = listFailed()
    check after.len == 1

  test "getLatestFailedDir returns path with _latest symlink":
    if dirExists(FailedBuildsDir): removeDir(FailedBuildsDir)
    initPostMortem()

    preserveFailed(PostMortemRecord(
      actionKey: "latest_test_1234567",
      gateId: "g3", failedAt: epochTime(),
      stdout: "", stderr: "", exitCode: 1,
      inputs: initTable[string, string](), namespaceConfig: ""
    ))

    let latest = getLatestFailedDir()
    check latest.len > 0
    check dirExists(latest)

teardown()
