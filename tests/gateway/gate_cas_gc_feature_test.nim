## Gate CAS GC Feature Test
##
## Verifies content-addressed storage garbage collection:
##   - graceful handling of missing/empty CAS directories
##   - retention of newest MaxEntriesPerGate entries per gate ID
##   - deletion of entries older than MinCasEntryAgeSec
##   - shouldRunCasGc reflects lock state correctly
##
## See tests/features/gate_cas_gc.feature for the specification.

import std/[os, osproc, times, strutils, unittest]
import core/gate/gate_cas_gc

const
  CasGatesSubDir = ".axiom/cache/gates"

proc makeCasEntry(base, gateId, suffix: string) =
  ## Create a CAS entry directory: <gateId>-<suffix> inside the gates dir.
  let dirName = gateId & "-" & suffix
  let entryPath = base / CasGatesSubDir / dirName
  createDir(entryPath)
  writeFile(entryPath / "artifact.bin", "data-" & suffix)

proc backdateEntry(base, gateId, suffix: string, ageSeconds: int64) =
  ## Set the mtime of a CAS entry directory to `ageSeconds` in the past.
  ## Uses `touch -d @<epoch>` for reliable directory mtime manipulation on Linux.
  let dirName = gateId & "-" & suffix
  let entryPath = base / CasGatesSubDir / dirName
  let pastEpoch = (getTime() - ageSeconds.seconds).toUnix()
  let cmd = "touch -d @" & $pastEpoch & " '" & entryPath & "'"
  let ret = execCmd(cmd)
  if ret != 0:
    raise newException(IOError, "touch failed for " & entryPath)

proc countEntries(casDir: string): int =
  ## Count non-hidden subdirectories inside the CAS gates directory.
  result = 0
  for kind, path in walkDir(casDir):
    if kind == pcDir:
      let name = path.extractFilename()
      if not name.startsWith("."):
        inc result

proc listEntries(casDir: string): seq[string] =
  ## Return filenames of non-hidden subdirectories inside the CAS gates dir.
  result = @[]
  for kind, path in walkDir(casDir):
    if kind == pcDir:
      let name = path.extractFilename()
      if not name.startsWith("."):
        result.add(name)

suite "Gate CAS GC":
  setup:
    let tmpDir = getTempDir() / "axiom_cas_gc_test_" & $epochTime().int
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "runCasGc does not crash on missing CAS directory":
    ## Given a repo root with no .axiom/cache/gates directory
    ## When runCasGc is called
    ## Then it returns without error
    runCasGc(tmpDir)
    # Reaching this line without exception means graceful handling passed.
    check dirExists(tmpDir)

  test "runCasGc does nothing when entries are within retention limit":
    ## Given 2 CAS entries for gate "mygate" (below MaxEntriesPerGate = 3)
    ## When runCasGc is called
    ## Then both entries are preserved
    let casDir = tmpDir / CasGatesSubDir
    createDir(casDir)
    makeCasEntry(tmpDir, "mygate", "aaa11111111111111-1111111111111111")
    makeCasEntry(tmpDir, "mygate", "bbb22222222222222-2222222222222222")

    runCasGc(tmpDir)

    check countEntries(casDir) == 2

  test "runCasGc deletes oldest entries beyond retention limit":
    ## Given 5 CAS entries for gate "testgate" with varying ages
    ## When runCasGc is called
    ## Then the 3 newest are preserved and the 2 oldest (≥ MinCasEntryAgeSec) are deleted
    let casDir = tmpDir / CasGatesSubDir
    createDir(casDir)

    # Create 5 entries — 3 recent, 2 old (exceeds MaxEntriesPerGate=3)
    makeCasEntry(tmpDir, "testgate", "newest1-aaaa1111-11111111")
    backdateEntry(tmpDir, "testgate", "newest1-aaaa1111-11111111", 100)

    makeCasEntry(tmpDir, "testgate", "second2-bbbb2222-22222222")
    backdateEntry(tmpDir, "testgate", "second2-bbbb2222-22222222", 200)

    makeCasEntry(tmpDir, "testgate", "third3--cccc3333-33333333")
    backdateEntry(tmpDir, "testgate", "third3--cccc3333-33333333", 300)

    makeCasEntry(tmpDir, "testgate", "fourth4-dddd4444-44444444")
    backdateEntry(tmpDir, "testgate", "fourth4-dddd4444-44444444", 7200)

    makeCasEntry(tmpDir, "testgate", "fifth5--eeee5555-55555555")
    backdateEntry(tmpDir, "testgate", "fifth5--eeee5555-55555555", 10800)

    runCasGc(tmpDir)

    let remaining = listEntries(casDir)
    check remaining.len == 3
    check "testgate-newest1-aaaa1111-11111111" in remaining
    check "testgate-second2-bbbb2222-22222222" in remaining
    check "testgate-third3--cccc3333-33333333" in remaining
    check "testgate-fourth4-dddd4444-44444444" notin remaining
    check "testgate-fifth5--eeee5555-55555555" notin remaining

  test "young entries are never deleted even beyond retention limit":
    ## Given 5 entries for gate "youngate" where all are younger than MinCasEntryAgeSec
    ## When runCasGc is called
    ## Then no entries are deleted — age guard overrides retention
    let casDir = tmpDir / CasGatesSubDir
    createDir(casDir)

    for i in 1..5:
      let suffix = "hash" & $i & "aaaa-bbbbcccc"
      makeCasEntry(tmpDir, "youngate", suffix)
      # Backdate only 120s (2 min) — well under MinCasEntryAgeSec (3600s)
      backdateEntry(tmpDir, "youngate", suffix, 120)

    runCasGc(tmpDir)

    check countEntries(casDir) == 5

  test "shouldRunCasGc returns true when no lock file exists":
    ## Given no gc.lock file in the working directory
    ## When shouldRunCasGc is called
    ## Then it returns true (GC should run)
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    check shouldRunCasGc() == true
    setCurrentDir(savedDir)

  test "shouldRunCasGc returns false after recordCasGcRun":
    ## Given a fresh gc.lock written by recordCasGcRun
    ## When shouldRunCasGc is called from the same working directory
    ## Then it returns false (lock is not stale)
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    recordCasGcRun()
    check shouldRunCasGc() == false
    setCurrentDir(savedDir)
