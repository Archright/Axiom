{.push raises: [Exception].}

## Source Fetcher — Unit Tests
## Verifies hash computation, local fetch+verify, lockfile round-trip, and collision detection.

import std/[os, json, times, unittest]
import gate/runners/source_fetcher

suite "computeContentHash":
  test "computeContentHash is deterministic":
    let h1 = computeContentHash("hello world")
    let h2 = computeContentHash("hello world")
    check h1 == h2

  test "different content produces different hash":
    let h1 = computeContentHash("hello")
    let h2 = computeContentHash("world")
    check h1 != h2

  test "empty content produces valid SHA-256":
    let h = computeContentHash("")
    check h.len > 0
    # SHA-256 of empty string is well-known
    check h == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  test "computeContentHash returns 64-char hex string":
    let h = computeContentHash("test data")
    check h.len == 64
    # All characters should be hex digits
    for c in h:
      check c in "0123456789abcdef"

suite "fetchAndVerify with local source":
  test "local fetch succeeds when hash matches":
    let tmpDir = getTempDir() / "source_fetcher_test_" & $epochTime().toInt
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let testFile = tmpDir / "test.txt"
    writeFile(testFile, "verified content")
    let expectedHash = computeContentHash("verified content")

    let source = FetchSource(
      name: "test-lib",
      url: testFile,
      expectedHash: expectedHash,
      fetcher: fkLocal,
      stripPrefix: ""
    )
    let result = fetchAndVerify(source)
    check result.verified == true
    check result.name == "test-lib"
    check result.contentHash == expectedHash

  test "local fetch fails when hash mismatches":
    let tmpDir = getTempDir() / "source_fetcher_mismatch_test_" & $epochTime().toInt
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let testFile = tmpDir / "mismatch.txt"
    writeFile(testFile, "actual content")
    let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"

    let source = FetchSource(
      name: "bad-lib",
      url: testFile,
      expectedHash: wrongHash,
      fetcher: fkLocal,
      stripPrefix: ""
    )
    var raisedCollision = false
    try:
      discard fetchAndVerify(source)
    except ContentCollisionDefect as e:
      raisedCollision = true
      check e.sourceName == "bad-lib"
      check e.expectedHash == wrongHash
      check e.actualHash != wrongHash
    check raisedCollision

  test "local fetch succeeds with empty expected hash (first run)":
    let tmpDir = getTempDir() / "source_fetcher_first_run_test_" & $epochTime().toInt
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let testFile = tmpDir / "first_run.txt"
    writeFile(testFile, "content to lock")

    let source = FetchSource(
      name: "new-lib",
      url: testFile,
      expectedHash: "",  # empty = first run, just compute hash
      fetcher: fkLocal,
      stripPrefix: ""
    )
    let result = fetchAndVerify(source)
    check result.verified == true
    check result.contentHash.len == 64

suite "Lockfile round-trip":
  test "save and load lockfile preserves sources":
    let tmpDir = getTempDir() / "lockfile_test_" & $epochTime().toInt
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let lockPath = tmpDir / "sources.lock"

    var lockfile = Lockfile(sources: @[
      FetchSource(
        name: "nim-stdlib",
        url: "/path/to/nim/lib",
        expectedHash: "abc123",
        fetcher: fkLocal,
        stripPrefix: ""
      ),
      FetchSource(
        name: "lean4",
        url: "https://leanprover.github.io/lean4",
        expectedHash: "def456",
        fetcher: fkHttp,
        stripPrefix: "lean4/"
      )
    ])
    saveLockfile(lockfile, lockPath)
    check fileExists(lockPath)

    let loaded = loadLockfile(lockPath)
    check loaded.sources.len == 2
    check loaded.sources[0].name == "nim-stdlib"
    check loaded.sources[0].fetcher == fkLocal
    check loaded.sources[1].name == "lean4"
    check loaded.sources[1].fetcher == fkHttp
    check loaded.sources[1].stripPrefix == "lean4/"

  test "loadLockfile returns empty for nonexistent file":
    let loaded = loadLockfile("/nonexistent/path/lock.json")
    check loaded.sources.len == 0

suite "FetcherKind enum":
  test "fkLocal represents local path":
    check $fkLocal == "local"

  test "fkHttp represents HTTP download":
    check $fkHttp == "http"

  test "fkGit represents git clone":
    check $fkGit == "git"

suite "axiomDefaultSources":
  test "axiomDefaultSources includes nim-stdlib":
    let defaults = axiomDefaultSources()
    check defaults.len >= 1
    var found = false
    for s in defaults:
      if s.name == "nim-stdlib":
        found = true
        check s.fetcher == fkLocal
        check s.expectedHash.len == 0  # first run
    check found

{.pop.}
