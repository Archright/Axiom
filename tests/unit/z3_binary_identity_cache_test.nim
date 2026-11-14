## VS-OPT-Z3-IDENTITY mutation battery — Z3 binary digest stat-identity
## acceleration cache (src/verification/kernel_reexecution.nim,
## z3BinaryDigestWithStats / z3BinaryChecksumAcceptedWithStats — the
## source_identity_cache.nim pattern applied to the INV-10 binary pin).
##
## Pins the contract:
##   C1 identity  — the pinned-checksum verdict is bit-identical: the digest
##                  equals the full rehash (sha256Hex(readFile(z3Bin))) on
##                  both the cold and the reused path, and the policy
##                  comparison is unchanged.
##   C2 safety    — a cached digest is reused only under an unchanged kernel
##                  stat identity (dev, ino, size, mtime_ns, ctime_ns, mode),
##                  a non-racy entry (git racy-git rule, second granularity)
##                  and the exact probed path.
##   C3 fail-closed — missing policy file, unreadable binary, corrupt /
##                  foreign-schema / untrusted cache, invalid cached digest
##                  → recompute or false, never a manufactured pass.
##   C4 boundary  — same-UID cache tampering is INSIDE the trust boundary
##                  (DEBT#524): the cache is an acceleration cache, never
##                  evidence, and no forgery defense is claimed. The last
##                  test pins that boundary so a future hardening must change
##                  the spec deliberately.
##
## All assertions are behavioral; no compiler-guaranteed behavior (§0.7).

import std/[unittest, os, times, strutils, json]

import core/crypto/hash_kernel
import verification/kernel_reexecution

when defined(posix):
  import std/posix

type
  Fixture = tuple[root, z3bin, policyDir, cachePath: string]

proc newRoot(): Fixture =
  let root = getTempDir() / ("axiom_z3id_" & $getCurrentProcessId() & "_" & $epochTime().int)
  result.root = root
  result.z3bin = root / "z3bin"
  result.policyDir = root / "data" / "policy"
  result.cachePath = root / ".axiom" / "cache" / "z3_binary_identity.json"
  createDir(result.root)

proc writePolicy(t: Fixture; digests: openArray[string]) =
  createDir(t.policyDir)
  var versions = newJObject()
  for i, d in digests:
    versions["v" & $i] = %d
  writeFile(t.policyDir / "z3_binary_checksums.json",
    $(%*{"schemaVersion": 1, "versions": versions}))

proc accepted(t: Fixture; stats: var Z3BinaryIdentityStats): bool =
  z3BinaryChecksumAcceptedWithStats(t.z3bin, t.root, stats)

proc accepted(t: Fixture): bool =
  var stats: Z3BinaryIdentityStats
  t.accepted(stats)

suite "z3 binary identity cache — contract":
  test "cold call hashes and equals the full rehash; warm call reuses without rehashing":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100) # binary older than the cache write second -> not racy
    var digStats: Z3BinaryIdentityStats
    let coldDigest = z3BinaryDigestWithStats(t.z3bin, t.root, digStats)
    check digStats.rehashed == 1
    check digStats.reused == 0
    check coldDigest == sha256Hex(readFile(t.z3bin))
    check fileExists(t.cachePath)
    when defined(posix):
      check getFilePermissions(t.cachePath) == {fpUserRead, fpUserWrite}
    var cold: Z3BinaryIdentityStats
    check t.accepted(cold) # the digest call warmed the cache -> reused
    check cold.reused == 1
    check cold.rehashed == 0

    var warm: Z3BinaryIdentityStats
    let warmDigest = z3BinaryDigestWithStats(t.z3bin, t.root, warm)
    check warm.reused == 1
    check warm.rehashed == 0
    check warmDigest == coldDigest
    var warmAcc: Z3BinaryIdentityStats
    check t.accepted(warmAcc)
    check warmAcc.reused == 1
    check warmAcc.rehashed == 0

  test "same-size content change: digest recomputed, mismatch is fail-closed false":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    writeFile(t.z3bin, "fake z3 payload B\n") # same size, different bytes
    check getFileSize(t.z3bin) == "fake z3 payload A\n".len
    var stats: Z3BinaryIdentityStats
    check not t.accepted(stats) # fresh digest matches no policy entry -> false
    check stats.rehashed == 1
    check stats.reused == 0
    t.writePolicy([sha256Hex("fake z3 payload A\n"), sha256Hex("fake z3 payload B\n")])
    check t.accepted() # racy entry re-hashed once -> the fresh verdict is a pass

  test "corrupt cache (not JSON) is discarded and recomputed, never a pass":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    writeFile(t.cachePath, "{ this is not json")
    var stats: Z3BinaryIdentityStats
    check t.accepted(stats) # discarded -> recompute -> genuine verdict
    check stats.rehashed == 1
    check stats.reused == 0

  test "cache with a foreign schema is discarded":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    writeFile(t.cachePath, $(%*{"schema": "other/1", "path": t.z3bin,
      "digest": sha256Hex("forged"), "writtenAtNs": "0"}))
    var stats: Z3BinaryIdentityStats
    check t.accepted(stats)
    check stats.rehashed == 1
    check stats.reused == 0

  test "cached digest with an invalid hex shape is discarded (never a pass)":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    var node = parseFile(t.cachePath)
    node["digest"] = %"deadbeef" # identity valid, digest shape impossible
    writeFile(t.cachePath, $node)
    var stats: Z3BinaryIdentityStats
    check t.accepted(stats) # discarded -> recompute -> genuine verdict
    check stats.rehashed == 1
    check stats.reused == 0

  test "cache without writtenAtNs is racily conservative: rehash":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    var node = parseFile(t.cachePath)
    node.delete("writtenAtNs") # missing -> 0 -> every entry is racy
    writeFile(t.cachePath, $node)
    var stats: Z3BinaryIdentityStats
    check t.accepted(stats)
    check stats.racy == 1
    check stats.rehashed == 1
    check stats.reused == 0

  test "same-second entry is racy: rehashed, then reusable":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    let v0 = t.accepted() # cache written in the same second as the binary
    sleep(1100)
    var s1: Z3BinaryIdentityStats
    let v1 = t.accepted(s1) # racy entry -> rehash, rewrite a second later
    check s1.racy == 1
    check s1.rehashed == 1
    check s1.reused == 0
    check v1 == v0
    var s2: Z3BinaryIdentityStats
    let v2 = t.accepted(s2) # cache now written a second later -> reusable
    check s2.reused == 1
    check s2.rehashed == 0
    check v2 == v0

  test "path change recomputes (the cache is keyed by the probed path)":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    let other = t.root / "z3bin2"
    writeFile(other, "fake z3 payload A\n") # identical content, different path
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted() # warms the cache for t.z3bin
    var stats: Z3BinaryIdentityStats
    check z3BinaryChecksumAcceptedWithStats(other, t.root, stats)
    check stats.rehashed == 1
    check stats.reused == 0

  test "missing policy file fails closed even with a warm cache":
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    removeFile(t.policyDir / "z3_binary_checksums.json")
    check not t.accepted() # the cache can never bypass the policy

  test "unreadable binary fails closed even with a warm cache":
    when defined(posix):
      if geteuid() != 0:
        let t = newRoot()
        defer: removeDir(t.root)
        writeFile(t.z3bin, "fake z3 payload A\n")
        t.writePolicy([sha256Hex("fake z3 payload A\n")])
        sleep(1100)
        check t.accepted()
        doAssert chmod(t.z3bin.cstring, 0o000) == 0
        var stats: Z3BinaryIdentityStats
        check not t.accepted(stats) # mode/ctime changed -> rehash -> EACCES -> false
        check stats.reused == 0

  test "group-writable cache is not trusted and is rewritten 0600":
    when defined(posix):
      if geteuid() != 0:
        let t = newRoot()
        defer: removeDir(t.root)
        writeFile(t.z3bin, "fake z3 payload A\n")
        t.writePolicy([sha256Hex("fake z3 payload A\n")])
        sleep(1100)
        check t.accepted()
        doAssert chmod(t.cachePath.cstring, 0o664) == 0
        var stats: Z3BinaryIdentityStats
        check t.accepted(stats)
        check stats.reused == 0
        check getFilePermissions(t.cachePath) == {fpUserRead, fpUserWrite}

  test "same-UID cache tampering is inside the trust boundary (documented)":
    ## C4: this is the DEBT#524 boundary, not a defended path. A same-UID
    ## writer can forge a 64-hex digest with a matching identity; the cache
    ## reuses it and the verdict flips to false (mismatch), exactly like the
    ## source_identity_cache twin. If a future slice hardens the cache, this
    ## test flips and the spec must change with it — the cache must never be
    ## cited as evidence either way.
    let t = newRoot()
    defer: removeDir(t.root)
    writeFile(t.z3bin, "fake z3 payload A\n")
    t.writePolicy([sha256Hex("fake z3 payload A\n")])
    sleep(1100)
    check t.accepted()
    var node = parseFile(t.cachePath)
    node["digest"] = %sha256Hex("forged") # 64-hex, identity untouched
    writeFile(t.cachePath, $node)
    var stats: Z3BinaryIdentityStats
    check not t.accepted(stats)
    check stats.reused == 1
    check stats.rehashed == 0
