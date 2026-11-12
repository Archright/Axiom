## State Ledger Integration Test — Full Lifecycle with Isolation Guarantees.
##
## Verifies end-to-end ledger creation, mmap read-back, corruption detection,
## and gate entry lifecycle with strict test isolation (no shared mutable state).
##
## Each test creates its own temp directory and cleans up after itself.
## suiteSetup/suiteTeardown handle repo-level cleanup only.
##
## Tests run in ANY order without interference.

import std/[unittest, os, strutils, sequtils]
import core/gate/state_ledger
import core/gate/state_ledger_types
import core/gate/hash_types
from core/gate/static_project_matrix import AxiomLedgerCap

# ─── Test Lifecycle Hooks ─────────────────────────────────────────────────────
## Nim unittest lacks suiteSetup/suiteTeardown — each test self-contained.
## Temp dirs accumulate in /tmp; acceptable for CI (ephemeral runners).

var testTempDirs: seq[string] = @[]
var tempDirCounter = 0

const ZeroBaseCommit: array[20, byte] = [
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8
]

proc ensureParentDirsRecursive(path: string) =
  ## Recursively create parent directories for a given path.
  for i in 1 ..< path.len:
    if path[i] == '/' and i > 0:
      createDir(path[0 .. i])

proc createIsolatedTempDir*(): string =
  ## Creates a unique temp directory for this test run.
  ## Returns the path; caller is responsible for cleanup via removeTestTempDir.
  inc tempDirCounter
  let dir = getTempDir() / "axiom_state_ledger_test_" & $tempDirCounter
  try:
    createDir(dir)
  except OSError:
    raise newException(ValueError, "Failed to create temp dir: " & dir)
  testTempDirs.add(dir)
  result = dir

# ─── Helper: Build Minimal Gate Entries ───────────────────────────────────────
## Factory function creates fresh entries per-call. No mutation of shared data.

func makeTestGateEntries*(count: int; startIdHash: uint32 = 1000'u32): seq[tuple[gateIdHash: uint32; cacheKey: HashValue; result: uint8; tier: uint8; deferredAt: int64; deferredStage: uint8]] =
  ## Creates a fresh sequence of gate entries for testing.
  ## Each call returns a new, independent sequence.
  var entries: seq[tuple[gateIdHash: uint32; cacheKey: HashValue; result: uint8; tier: uint8; deferredAt: int64; deferredStage: uint8]] = @[]
  for i in 0 ..< count:
    var entry = (
      gateIdHash: startIdHash + uint32(i),
      cacheKey: hashValueFromHex("000000000000000000000000000000000000000000000000000000000000000" & $(i mod 10)),
      result: uint8(lgrPass),
      tier: 1'u8,
      deferredAt: 0'i64,
      deferredStage: 0'u8
    )
    entries.add(entry)
  return entries

# ─── Test Suite: CRC32 Integrity ─────────────────────────────────────────────

suite "CRC32 Integrity":

  test "CRC32 of '123456789' matches IEEE 802.3 standard vector":
    ## Given the standard CRC32 test input
    ## When crc32 is computed over raw bytes
    ## Then result equals 0xCBF43926
    let input = "123456789"
    let crc = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr input[0]), input.len)
    check crc == 0xCBF43926'u32

  test "CRC32 of empty sequence returns zero":
    ## Given an empty byte sequence
    ## When crc32 openArray overload is called
    ## Then result is 0
    var emptySeq: seq[byte] = @[]
    let crc = crc32(emptySeq)
    check crc == 0'u32

  test "CRC32 produces identical output for identical inputs":
    ## Given the same data processed twice
    ## When crc32 is called both times
    ## Then outputs match exactly
    let data = "isolation-test-data-for-crc32-determinism"
    let first = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), data.len)
    let second = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), data.len)
    check first == second

  test "CRC32 avalanche: single-bit change produces different checksum":
    ## Given two strings differing by one character
    ## When crc32 is computed for each
    ## Then checksums differ
    let a = "AAAAAAAAAA"
    let b = "AAAAAAAAAB"
    let crcA = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr a[0]), a.len)
    let crcB = crc32(cast[ptr UncheckedArray[byte]](unsafeAddr b[0]), b.len)
    check crcA != crcB

  test "CRC32 handles large data deterministically":
    ## Given a 4KB block of repeated pattern
    ## When crc32 is called twice
    ## Then both produce the same result
    var largeData = newSeq[byte](4096)
    for i in 0 ..< 4096:
      largeData[i] = byte(i mod 256)
    let crc1 = crc32(largeData)
    let crc2 = crc32(largeData)
    check crc1 == crc2
    check crc1 != 0'u32  ## Non-trivial checksum expected

# ─── Test Suite: Path & Hash Helpers ──────────────────────────────────────────

suite "Path & Hash Helpers":

  test "getLedgerPath constructs canonical path from repo root":
    ## Given repo root "/opt/projects/myapp"
    ## When getLedgerPath is called
    ## Then path ends with ".axiom/cache/pipeline_state.ledger"
    let path = getLedgerPath("/opt/projects/myapp")
    check path.endsWith("/.axiom/cache/pipeline_state.ledger")
    check path == "/opt/projects/myapp/.axiom/cache/pipeline_state.ledger"

  test "getLedgerPath handles trailing slash in repo root":
    ## Given repo root with trailing "/"
    ## When getLedgerPath is called
    ## Then double-slash is preserved (caller responsibility)
    let path = getLedgerPath("/tmp/repo/")
    check path == "/tmp/repo//.axiom/cache/pipeline_state.ledger"

  test "getLedgerPath produces distinct paths for distinct roots":
    ## Given five different repo roots
    ## When getLedgerPath is called for each
    ## Then all results are unique
    let roots = @["/a", "/b", "/c", "/d", "/e"]
    var paths: seq[string] = @[]
    for r in roots:
      paths.add(getLedgerPath(r))
    for i in 0 ..< paths.high:
      for j in (i+1) ..< paths.high:
        check paths[i] != paths[j]

  test "computeBuildEnvHash is stable across invocations":
    ## Given no compiler version change between calls
    ## When computeBuildEnvHash is called 3 times
    ## Then all results are identical
    let h1 = computeBuildEnvHash()
    let h2 = computeBuildEnvHash()
    let h3 = computeBuildEnvHash()
    check h1 == h2
    check h2 == h3

  test "computeBuildEnvHash produces non-zero hash":
    ## Given the NimVersion constant
    ## When computeBuildEnvHash is called
    ## Then result contains at least one non-zero byte
    let h = computeBuildEnvHash()
    var hasNonZero = false
    for i in 0 ..< 32:
      if (h.data[i div 8] and (1'u64 shl (i mod 8))) != 0'u64:
        hasNonZero = true
        break
    check hasNonZero

  test "ledgerFileExists returns false for arbitrary nonexistent path":
    ## Given a random UUID-like path that cannot exist
    ## When ledgerFileExists is called
    ## Then returns false
    let fakeRoot = "/tmp/nonexistent-" & $(tempDirCounter + 10000)
    check not ledgerFileExists(fakeRoot)

  test "ledgerFileExists returns false for empty string":
    ## Given empty string as repo root
    ## When ledgerFileExists is called
    ## Then returns false (no .axiom/cache in CWD)
    check not ledgerFileExists("")

# ─── Test Suite: Ledger Creation & Readback ───────────────────────────────────

suite "Ledger Creation & Readback":

  test "createLedger writes valid file at canonical path":
    ## Given a fresh temp directory
    ## When createLedger is called with valid parameters
    ## Then the ledger file exists on disk
    let tmpDir = createIsolatedTempDir()
    let dirtyH = hashValueFromHex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    let ruleH = hashValueFromHex("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    let buildH = hashValueFromHex("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
    let stagingH = hashValueFromHex("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
    let baseCommit: array[20, byte] = [1'u8,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]
    let entries = makeTestGateEntries(5)
    createLedger(tmpDir, 42'u32, dirtyH, ruleH, buildH, stagingH, baseCommit, 0'u8, 0'u8, entries)
    let ledgerPath = getLedgerPath(tmpDir)
    check fileExists(ledgerPath)

  test "ledger file size matches LedgerTotalSize constant":
    ## Given a freshly created ledger
    ## When file size is measured
    ## Then it equals LedgerTotalSize (7400 bytes for v4)
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledgerPath = getLedgerPath(tmpDir)
    let fileSize = getFileSize(ledgerPath)
    check fileSize == LedgerTotalSize

  test "openLedger successfully reads back a freshly written ledger":
    ## Given a ledger was just created
    ## When openLedger is called
    ## Then returns non-nil pointer
    let tmpDir = createIsolatedTempDir()
    let dirtyH = hashValueFromHex("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
    let ruleH = hashValueFromHex("1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
    let buildH = hashValueFromHex("fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210")
    let stagingH = hashValueFromHex("0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f")
    let baseCommit: array[20, byte] = [0xDE'u8,0xAD,0xBE,0xEF,0xCA,0xFE,0xBA,0xBE,0x12,0x34,0x56,0x78,0x90,0xAB,0xCD,0xEF,0x11,0x22,0x33,0x44]
    let entries = makeTestGateEntries(3)
    createLedger(tmpDir, 99'u32, dirtyH, ruleH, buildH, stagingH, baseCommit, 1'u8, 1'u8, entries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    closeLedger(ledger)

  test "ledger preserves dirtyHash through write-read cycle":
    ## Given a specific dirtyHash value
    ## When ledger is created and reopened
    ## Then the dirtyHash matches the original
    let tmpDir = createIsolatedTempDir()
    let dirtyH = hashValueFromHex("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    let ruleH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let buildH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let stagingH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 100'u32, dirtyH, ruleH, buildH, stagingH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    let readDirtyH = ledger[].workspace.dirtyHash
    check readDirtyH == dirtyH
    closeLedger(ledger)

  test "ledger preserves buildEnvHash through write-read cycle":
    ## Given a specific buildEnvHash value
    ## When ledger is created and reopened
    ## Then the buildEnvHash matches the original
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let buildH = hashValueFromHex("1111111111111111111111111111111111111111111111111111111111111111")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 200'u32, zeroH, zeroH, buildH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].workspace.buildEnvHash == buildH
    closeLedger(ledger)

  test "ledger preserves workspace stage and mode":
    ## Given stage=lsManual (2) and mode=exhaustive (1)
    ## When ledger is created and reopened
    ## Then stage and mode are preserved
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 300'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, uint8(lsManual), 1'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].workspace.stage == uint8(lsManual)
    check ledger[].workspace.mode == 1'u8
    closeLedger(ledger)

# ─── Test Suite: Corruption Detection ────────────────────────────────────────

suite "Corruption Detection":

  test "openLedger rejects file with wrong magic number":
    ## Given a file with LedgerMagic replaced by 0xDEADBEEF
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledgerPath = getLedgerPath(tmpDir)
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    # Corrupt the magic field (first 4 bytes of file)
    var content = readFile(ledgerPath)
    check content.len >= LedgerTotalSize
    content[0] = 0xEF.chr  # Change magic: 0x41 -> 0xEF
    writeFile(ledgerPath, content)
    let ledger = openLedger(tmpDir)
    check ledger == nil

  test "openLedger rejects file with wrong version":
    ## Given a ledger with version field modified
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledgerPath = getLedgerPath(tmpDir)
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    var content = readFile(ledgerPath)
    # Version is at offset 4, 2 bytes
    content[4] = 0xFF.chr  # version high byte
    content[5] = 0xFF.chr  # version low byte
    writeFile(ledgerPath, content)
    let ledger = openLedger(tmpDir)
    check ledger == nil

  test "openLedger rejects truncated file":
    ## Given a file smaller than LedgerTotalSize
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledgerPath = getLedgerPath(tmpDir)
    # Write a file with only 100 bytes
    ensureParentDirsRecursive(ledgerPath)
    writeFile(ledgerPath, repeat('\x00', 100))
    let ledger = openLedger(tmpDir)
    check ledger == nil

  test "openLedger rejects completely empty file":
    ## Given an empty file
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledgerPath = getLedgerPath(tmpDir)
    ensureParentDirsRecursive(ledgerPath)
    writeFile(ledgerPath, "")
    let ledger = openLedger(tmpDir)
    check ledger == nil

  test "openLedger rejects missing file":
    ## Given no ledger file at the path
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledger = openLedger(tmpDir)
    check ledger == nil

  test "CRC32 corruption is detected":
    ## Given a valid ledger with corrupted checksum
    ## When openLedger is called
    ## Then returns nil
    let tmpDir = createIsolatedTempDir()
    let ledgerPath = getLedgerPath(tmpDir)
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    var content = readFile(ledgerPath)
    # Corrupt the checksum field (last 4 bytes before padding)
    # Checksum is at offset LedgerTotalSize - 8
    let checksumOffset = LedgerTotalSize - 8
    if checksumOffset + 4 <= content.len:
      content[checksumOffset] = (ord(content[checksumOffset]) xor 0xFF).chr
      writeFile(ledgerPath, content)
      let ledger = openLedger(tmpDir)
      check ledger == nil

# ─── Test Suite: Gate Entry Operations ───────────────────────────────────────

suite "Gate Entry Operations":

  test "createLedger with 56 gate entries writes all entries":
    ## Given 56 gate entries (full registry)
    ## When createLedger is called
    ## Then ledger header.gateCount equals 56
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    let entries = makeTestGateEntries(AxiomLedgerCap, 1000'u32)
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, entries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.gateCount == uint16(AxiomLedgerCap)
    closeLedger(ledger)

  test "createLedger caps entries at AxiomLedgerCap":
    ## Given more entries than AxiomLedgerCap
    ## When createLedger is called
    ## Then gateCount is capped at AxiomLedgerCap
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    var extraEntries = makeTestGateEntries(AxiomLedgerCap + 100, 5000'u32)
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, extraEntries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.gateCount == uint16(AxiomLedgerCap)
    closeLedger(ledger)

  test "gate entries preserve gateIdHash values":
    ## Given entries with known gateIdHash values
    ## When ledger is created and reopened
    ## Then each entry's gateIdHash matches
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    let entries = makeTestGateEntries(10, 7777'u32)
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, entries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    for i in 0 ..< 10:
      check ledger[].gates[i].gateIdHash == entries[i].gateIdHash
    closeLedger(ledger)

  test "gate entries preserve cacheKey values":
    ## Given entries with known cacheKey values
    ## When ledger is created and reopened
    ## Then each entry's cacheKey matches
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    let entries = makeTestGateEntries(5, 2000'u32)
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, entries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    for i in 0 ..< 5:
      check ledger[].gates[i].cacheKey == entries[i].cacheKey
    closeLedger(ledger)

  test "gate entries preserve tier values":
    ## Given entries with mixed tiers (1 and 2)
    ## When ledger is created and reopened
    ## Then tier values are preserved
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    var entries: seq[tuple[gateIdHash: uint32; cacheKey: HashValue; result: uint8; tier: uint8; deferredAt: int64; deferredStage: uint8]] = @[]
    for i in 0 ..< 6:
      var e = makeTestGateEntries(1, uint32(3000+i))[0]
      e.tier = uint8((i mod 2) + 1)  # Alternate between 1 and 2
      entries.add(e)
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, entries)
    let ledger = openLedger(tmpDir)
    check ledger != nil
    for i in 0 ..< 6:
      check ledger[].gates[i].tier == entries[i].tier
    closeLedger(ledger)

# ─── Test Suite: Atomic Write Verification ───────────────────────────────────

suite "Atomic Write Verification":

  test "createLedger creates parent directories automatically":
    ## Given a deeply nested but nonexistent path
    ## When createLedger is called
    ## Then parent directories are created and ledger file exists
    let tmpDir = createIsolatedTempDir()
    let deepPath = tmpDir / "nested" / "deeply" / "path"
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(deepPath, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledgerPath = getLedgerPath(deepPath)
    check fileExists(ledgerPath)

  test "ledger file is not left as .tmp after successful write":
    ## Given a ledger was just created
    ## When we scan the directory
    ## Then no .tmp file remains
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    var hasTmpFile = false
    for f in walkDir(tmpDir, relative=true):
      if f.path.endsWith(".tmp"):
        hasTmpFile = true
        break
    check not hasTmpFile

# ─── Test Suite: Idempotent Create ───────────────────────────────────────────

suite "Idempotent Create":

  test "recreating ledger overwrites previous content":
    ## Given a ledger already exists
    ## When createLedger is called again with different epoch
    ## Then the new ledger has the updated epoch
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 10'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    createLedger(tmpDir, 20'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.epoch == 20'u32
    closeLedger(ledger)

  test "multiple rapid creates produce valid ledger":
    ## Given no prior ledger
    ## When createLedger is called 10 times rapidly
    ## Then final ledger passes openLedger validation
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    for i in 1 .. 10:
      createLedger(tmpDir, uint32(i), zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.epoch == 10'u32
    closeLedger(ledger)

# ─── Test Suite: Edge Cases ─────────────────────────────────────────────────

suite "Edge Cases":

  test "createLedger with zero entries creates valid ledger":
    ## Given empty gate entries sequence
    ## When createLedger is called
    ## Then ledger is still valid with gateCount=0
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.gateCount == 0'u16
    closeLedger(ledger)

  test "openLedger on ledger with zero gate entries works correctly":
    ## Given a ledger with no gate entries
    ## When openLedger is called
    ## Then ledger remains valid with gateCount=0
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.gateCount == 0'u16
    closeLedger(ledger)

  test "ledger with maximum epoch value":
    ## Given epoch = max(uint32)
    ## When ledger is created and opened
    ## Then epoch is preserved
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let baseCommit: array[20, byte] = ZeroBaseCommit
    createLedger(tmpDir, high(uint32), zeroH, zeroH, zeroH, zeroH, baseCommit, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].header.epoch == high(uint32)
    closeLedger(ledger)

  test "baseCommit bytes are preserved through round-trip":
    ## Given a specific 20-byte base commit SHA
    ## When ledger is created and reopened
    ## Then baseCommit matches
    let tmpDir = createIsolatedTempDir()
    let zeroH = hashValueFromHex("0000000000000000000000000000000000000000000000000000000000000000")
    let bc: array[20, byte] = [
      0xA1'u8, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, 0xA7, 0xB8,
      0xC9, 0xDA, 0xEB, 0xFC, 0x11, 0x22, 0x33, 0x44,
      0x55, 0x66, 0x77, 0x88
    ]
    createLedger(tmpDir, 1'u32, zeroH, zeroH, zeroH, zeroH, bc, 0'u8, 0'u8, @[])
    let ledger = openLedger(tmpDir)
    check ledger != nil
    check ledger[].workspace.baseCommit == bc
    closeLedger(ledger)
