## VS-1 mutation battery — SourceCoherence acceleration cache
## (src/infrastructure/source_identity_cache.nim).
##
## Pins the contract (docs/spec/artifact_determinism.md):
##   C1 identity  — the tree digest is ALWAYS recomposed from the live walk;
##                  the cache may only supply per-file digests.
##   C2 safety    — a per-file digest is reused only under an unchanged kernel
##                  stat identity (dev, ino, size, mtime_ns, ctime_ns, mode)
##                  and a non-racy entry (git racy-git rule).
##   C3 fail-closed — unreadable source raises (never silently skipped);
##                  corrupt/untrusted cache is discarded and recomputed.
##   C4 boundary  — same-UID cache tampering is INSIDE the trust boundary
##                  (DEBT#524): the cache is an acceleration cache, never
##                  evidence, and no forgery defense is claimed. The last test
##                  pins that boundary so a future hardening must change the
##                  spec deliberately.
##
## All assertions are behavioral; no compiler-guaranteed behavior (§0.7).

import std/[unittest, os, times, strutils, json, hashes]

import core/utils/build_provenance
import infrastructure/source_identity_cache

when defined(posix):
  import std/posix

# Twin invariant: the NimScript VM (config.nims) and compiled std/hashes agree
# byte-for-byte; the build-time mirror relies on this (measured 2026-11-12).
static:
  doAssert $hash("abc") == "2640714258260161385"
  doAssert $hash("") == "-7286425919675154353"

const
  Formula = "vs1-tree-hash/1"

proc newTree(): tuple[root, srcDir, cachePath: string] =
  let root = getTempDir() / ("axiom_sic_" & $getCurrentProcessId() & "_" & $epochTime().int)
  result.root = root
  result.srcDir = root / "src"
  result.cachePath = root / "cache" / "source_tree_identity.json"
  createDir(result.srcDir)

proc cached(t: tuple[root, srcDir, cachePath: string];
            stats: var SourceIdentityStats): string =
  computeSourceTreeDigestCachedWithStats(t.srcDir, t.cachePath, stats)

proc cached(t: tuple[root, srcDir, cachePath: string]): string =
  computeSourceTreeDigestCached(t.srcDir, t.cachePath)

proc writeSources(t: tuple[root, srcDir, cachePath: string]) =
  writeFile(t.srcDir / "alpha.nim", "echo 1\n")
  writeFile(t.srcDir / "beta.nim", "echo 2\n")

suite "source identity cache — contract":
  test "cache off == cache on; warm call reuses every entry":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100) # files older than the cache write second -> not racy
    var coldStats: SourceIdentityStats
    let cold = t.cached(coldStats)
    check coldStats.rehashed == 2
    check cold == computeSourceTreeDigestUncached(t.srcDir)
    check cold.startsWith(Formula & ":")

    var warmStats: SourceIdentityStats
    let warm = t.cached(warmStats)
    check warmStats.reused == 2
    check warmStats.rehashed == 0
    check warm == cold

  test "same-second entry is racy: rehashed once, then reusable":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    let d0 = t.cached() # files and cache written in the same second
    sleep(1100)
    var s1: SourceIdentityStats
    let d1 = t.cached(s1) # racy entry -> rehash once
    check s1.racy == 2
    check s1.rehashed == 2
    check d1 == d0
    var s2: SourceIdentityStats
    let d2 = t.cached(s2) # cache now written a second later -> reusable
    check s2.reused == 2
    check d2 == d0

  test "same-size content change is rehashed":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let before = t.cached()
    let p = t.srcDir / "alpha.nim"
    check getFileSize(p) == "echo 1\n".len
    writeFile(p, "echo 9\n")
    check getFileSize(p) == "echo 1\n".len
    var stats: SourceIdentityStats
    let after = t.cached(stats)
    check after != before
    check stats.rehashed == 1
    check after == computeSourceTreeDigestUncached(t.srcDir)

  test "mtime restored, same size: ctime still forces a rehash":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let before = t.cached()
    let p = t.srcDir / "alpha.nim"
    let originalMtime = getFileInfo(p).lastWriteTime
    sleep(1100)
    writeFile(p, "echo 9\n")
    setLastModificationTime(p, originalMtime)
    check getFileSize(p) == "echo 1\n".len
    var stats: SourceIdentityStats
    let after = t.cached(stats)
    check after != before
    check stats.reused == 1

  test "added and deleted files invalidate":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let base = t.cached()

    writeFile(t.srcDir / "gamma.nim", "echo 3\n")
    var addStats: SourceIdentityStats
    let added = t.cached(addStats)
    check added != base
    check addStats.rehashed >= 1

    removeFile(t.srcDir / "gamma.nim")
    let removed = t.cached()
    check removed == base

  test "regular file -> symlink leaves the universe (digest changes)":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let before = t.cached()
    let p = t.srcDir / "alpha.nim"
    removeFile(p)
    createSymlink(t.srcDir / "beta.nim", p)
    let after = t.cached()
    check after != before
    check after == computeSourceTreeDigestUncached(t.srcDir)

  test "unreadable source fails closed even with a warm cache":
    when defined(posix):
      if geteuid() != 0:
        let t = newTree()
        defer: removeDir(t.root)
        t.writeSources()
        sleep(1100)
        discard t.cached() # warm, valid cache entry for alpha
        let p = t.srcDir / "alpha.nim"
        doAssert chmod(p.cstring, 0o000) == 0
        expect CatchableError:
          discard t.cached()
        expect CatchableError:
          discard computeSourceTreeDigestUncached(t.srcDir)

  test "corrupt cache is discarded, never trusted":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let expected = t.cached()
    writeFile(t.cachePath, "{ this is not json")
    var stats: SourceIdentityStats
    let recomputed = t.cached(stats)
    check recomputed == expected
    check stats.rehashed == 2

  test "cache with a foreign schema is discarded":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let expected = t.cached()
    writeFile(t.cachePath, $(%*{"schema": "other/1", "formula": Formula,
      "writtenAtNs": "0", "files": []}))
    var stats: SourceIdentityStats
    check t.cached(stats) == expected
    check stats.rehashed == 2

  test "group-writable cache is not trusted and is rewritten 0600":
    when defined(posix):
      if geteuid() != 0:
        let t = newTree()
        defer: removeDir(t.root)
        t.writeSources()
        sleep(1100)
        let expected = t.cached()
        doAssert chmod(t.cachePath.cstring, 0o664) == 0
        var stats: SourceIdentityStats
        check t.cached(stats) == expected
        check stats.reused == 0
        check getFilePermissions(t.cachePath) == {fpUserRead, fpUserWrite}

  test "mutation during the scan is re-read, never half-hashed":
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    var fired = false
    let hook = proc(path: string) {.closure, raises: [].} =
      if not fired and path.endsWith("alpha.nim"):
        fired = true
        try: writeFile(path, "echo 9\n")
        except CatchableError: discard
    var stats: SourceIdentityStats
    let seen = computeSourceTreeDigestCachedWithStats(t.srcDir, t.cachePath, stats, hook)
    check fired
    check seen == computeSourceTreeDigestUncached(t.srcDir)

  test "kernel digest binds paths (no file-boundary ambiguity)":
    let split = sourceTreeDigest(@[
      ("a.nim", fileContentDigest("x")),
      ("b.nim", fileContentDigest("y"))])
    let merged = sourceTreeDigest(@[("ab.nim", fileContentDigest("xy"))])
    check split != merged
    check split.startsWith(Formula & ":")
    check fileContentDigest("abc") == "2640714258260161385"

  test "same-UID cache tampering is inside the trust boundary (documented)":
    ## C4: this is the DEBT#524 boundary, not a defended path. If a future
    ## slice hardens the cache, this test flips and the spec must change with
    ## it — the cache must never be cited as evidence either way.
    let t = newTree()
    defer: removeDir(t.root)
    t.writeSources()
    sleep(1100)
    let genuine = t.cached()
    var node = parseFile(t.cachePath)
    for i in 0 ..< node["files"].len:
      if node["files"][i]["p"].getStr() == "alpha.nim":
        node["files"][i]["digest"] = %fileContentDigest("forged")
    writeFile(t.cachePath, $node)
    var stats: SourceIdentityStats
    let tampered = t.cached(stats)
    check stats.reused == 2
    check tampered != genuine
    check tampered != computeSourceTreeDigestUncached(t.srcDir)
