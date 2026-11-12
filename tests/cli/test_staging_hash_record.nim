## Test: stagingTreeHash recording through State Ledger
## Smoke test verifying that a real git write-tree hash flows into the ledger
## and is NOT recorded as H_VOID.
##
## Coverage:
##   - hashValueFromHex roundtrip with real SHA-1 hex
##   - State Ledger create -> open -> read stagingTreeHash
##   - Validates stagingTreeHash != H_VOID after recording
##   - Validates CRC32 integrity of written ledger
##
## Section 0.7 scope: Business scenario -- stagingTreeHash must carry real content hash.

import std/os
import std/osproc
import std/strutils
import std/times
import std/unittest
import checksums/sha2

# -- Import project modules --------------------------------------------------
import core/gate/hash_types
import core/gate/state_ledger
import core/gate/state_ledger_types

# -- Inline hex validation (matches production guard) -------------------------
# Source: src/gate/orchestrator_hook_part2_defs.nim

func isValidHexChar(c: char): bool =
  c in {'0'..'9', 'a'..'f', 'A'..'F'}

func isValidHex(s: string): bool =
  if s.len == 0:
    return false
  for c in s:
    if not isValidHexChar(c):
      return false
  return true

# -- Helpers -----------------------------------------------------------------

proc execOutput(cmd: string): string =
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    raise newException(IOError,
      "Command failed (" & $exitCode & "): " & cmd)
  output.strip()

func makeHash(seed: string): HashValue =
  hashValueFromHex(sha256Hex(seed))

proc tmpGitRepo(suffix: string): string =
  let path = getTempDir() / ("axiom_test_" & suffix & "_" & $int(epochTime()))
  createDir(path)
  let (_, rc) = execCmdEx("git init " & path)
  if rc != 0:
    raise newException(IOError, "git init failed for " & path)
  path

# -- Test Suite ---------------------------------------------------------------

suite "hashValueFromHex -- roundtrip with real git SHA-1":
  test "40-char hex string roundtrips correctly":
    let realTreeHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    let h = hashValueFromHex(realTreeHash)
    let hex = hashValueToHex(h)
    doAssert hex.len == 64
    doAssert hex.startsWith(realTreeHash),
      "Roundtrip failed: " & hex[24..63] & " != " & realTreeHash

  test "H_VOID is all zeros":
    let h = H_VOID
    doAssert h.data[0] == 0'u64
    doAssert h.data[1] == 0'u64
    doAssert h.data[2] == 0'u64
    doAssert h.data[3] == 0'u64
    doAssert h.isVoid()

  test "non-void hash is detected":
    let h = hashValueFromHex("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")
    doAssert not h.isVoid()

  test "makeHash produces non-void deterministic hash":
    let h = makeHash("test-seed")
    doAssert not h.isVoid()
    let h2 = makeHash("test-seed")
    doAssert h == h2, "Same seed should produce same hash"

  test "different seeds produce different hashes":
    let h1 = makeHash("seed-a")
    let h2 = makeHash("seed-b")
    doAssert h1 != h2, "Different seeds should produce different hashes"

suite "git write-tree -- real tree hash validation":
  test "git write-tree produces 40-char hex":
    let treeHash = execOutput("git write-tree")
    doAssert treeHash.len == 40,
      "git write-tree should produce 40-char SHA-1, got: " & $treeHash.len & " chars"
    doAssert isValidHex(treeHash),
      "git write-tree output should be valid hex: " & treeHash

  test "isValidHex rejects invalid tree hash":
    doAssert not isValidHex(""), "empty string should be invalid"
    doAssert not isValidHex("not-a-hash"), "non-hex should be invalid"

suite "State Ledger -- stagingTreeHash roundtrip":
  test "stagingTreeHash is NOT H_VOID after recording real hash":
    let tmpRoot = tmpGitRepo("staging")

    let testFile = tmpRoot / "test_file.txt"
    writeFile(testFile, "staging tree hash test content")
    let (_, addExit) = execCmdEx("git add test_file.txt", workingDir = tmpRoot)
    doAssert addExit == 0, "git add failed"

    let treeHash = execOutput("git write-tree")
    doAssert treeHash.len == 40 and isValidHex(treeHash),
      "Need valid tree hash for test, got: " & treeHash

    let stagingHash = hashValueFromHex(treeHash)
    doAssert not stagingHash.isVoid(), "Real tree hash should NOT be H_VOID"

    let dirtyHash = makeHash("dirty-test-seed")
    let ruleHash = makeHash("rule-test-seed")
    let buildEnvHash = makeHash("build-env-test-seed")
    var baseCommit: array[20, byte]
    for i in 0..19:
      baseCommit[i] = byte(i)

    createLedger(
      repoRoot = tmpRoot,
      epoch = 1000,
      dirtyHash = dirtyHash,
      ruleHash = ruleHash,
      buildEnvHash = buildEnvHash,
      stagingTreeHash = stagingHash,
      baseCommit = baseCommit,
      stage = 0,
      mode = 0,
      gateEntries = @[]
    )

    let ledger = openLedger(tmpRoot)
    doAssert ledger != nil, "Ledger should be readable after creation"

    let readHash = getStagingTreeHash(ledger)
    doAssert readHash != nil, "stagingTreeHash accessor should not return nil"
    doAssert not readHash[].isVoid(),
      "stagingTreeHash should NOT be H_VOID in the ledger"
    doAssert readHash[] == stagingHash,
      "stagingTreeHash should match what was written"

    closeLedger(ledger)
    removeDir(tmpRoot)

  test "H_VOID stagingTreeHash is recorded as-is (no crash)":
    let tmpRoot = tmpGitRepo("staging_void")

    var baseCommit: array[20, byte]
    createLedger(
      repoRoot = tmpRoot,
      epoch = 2000,
      dirtyHash = H_VOID,
      ruleHash = H_VOID,
      buildEnvHash = H_VOID,
      stagingTreeHash = H_VOID,
      baseCommit = baseCommit,
      stage = 0,
      mode = 0,
      gateEntries = @[]
    )

    let ledger = openLedger(tmpRoot)
    doAssert ledger != nil, "Ledger should open with H_VOID values"
    let readHash = getStagingTreeHash(ledger)
    doAssert readHash[].isVoid(), "H_VOID should be preserved as-is"
    closeLedger(ledger)
    removeDir(tmpRoot)

suite "State Ledger -- CRC32 integrity":
  test "ledger passes CRC32 validation after creation":
    let tmpRoot = tmpGitRepo("crc")

    let h = hashValueFromHex("deadbeef00000000000000000000000000000000000000000000000000000000")
    var baseCommit: array[20, byte]

    createLedger(
      repoRoot = tmpRoot,
      epoch = 3000,
      dirtyHash = h,
      ruleHash = h,
      buildEnvHash = h,
      stagingTreeHash = h,
      baseCommit = baseCommit,
      stage = 1,
      mode = 1,
      gateEntries = @[]
    )

    let ledger = openLedger(tmpRoot)
    doAssert ledger != nil,
      "Ledger should pass CRC32 validation after creation"
    doAssert ledger.header.magic == LedgerMagic
    doAssert ledger.header.version == LedgerVersion
    closeLedger(ledger)
    removeDir(tmpRoot)

echo "All staging hash record tests passed."
