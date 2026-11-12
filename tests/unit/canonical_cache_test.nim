## Unit tests for canonical_cache.nim — WorkUnitFingerprint + CAS.
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[os, strutils]
import core/types/results
import core/utils/io_utils
import core/crypto/hash_kernel
import verification/canonical_cache

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

  # Helper: compute SHA-256 hex digest of a string
  func sha256hex(s: string): string =
    hash_kernel.sha256Hex(s)

  # Helper: create a temp CAS directory
  proc newTempCasDir(): string =
    let base = getTempDir() / "axiom_canonical_cache_test_" &
               $getCurrentProcessId()
    createDir(base)
    base

  # Helper: compute contentDigest for a value
  func contentDigestOf(value: string): string =
    sha256hex(value)

  # Helper: compute WorkUnitFingerprint from four hex digests
  func makeFingerprint(
    sourceClosureDigest, toolchainDigest, contractDigest,
    executionConfigDigest: string
  ): WorkUnitFingerprint =
    computeWorkUnitFingerprint(
      sourceClosureDigest, toolchainDigest, contractDigest,
      executionConfigDigest
    )

  echo "=== Canonical Cache — put-then-get hit ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "canonical-result-artifact"
    let digest = contentDigestOf(value)
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, digest)
    check "put returns cpoStored for new entry":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # Promote to authoritative so get can return the value
    let promoRes = casPromoteEntry(casDir, fp, true)
    check "promote succeeds after put":
      assert promoRes.isOk()

    let getRes = casGetEntry(casDir, fp, digest)
    check "get returns the stored value on hit":
      assert getRes.isOk()
      assert getRes.get() == value

  echo ""
  echo "=== Canonical Cache — contentHash verification ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "canonical-result-artifact"
    let correctDigest = contentDigestOf(value)
    let wrongDigest = sha256hex("wrong-content")
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, correctDigest)
    check "put succeeds with correct contentDigest":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # Promote so get can verify contentDigest against authoritative entry
    discard casPromoteEntry(casDir, fp, true)

    let getRes = casGetEntry(casDir, fp, wrongDigest)
    check "get fails when contentDigest does not match":
      assert getRes.isErr()

  echo ""
  echo "=== Canonical Cache — same-key-different-content = CONFLICT ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    # First put: store value1
    let value1 = "first-result"
    let digest1 = contentDigestOf(value1)
    let putRes1 = casPutEntry(casDir, fp, value1, digest1)
    check "first put returns cpoStored":
      assert putRes1.isOk()
      assert putRes1.get() == cpoStored

    # Second put: same key, different value → CONFLICT
    let value2 = "second-result-different-content"
    let digest2 = contentDigestOf(value2)
    let putRes2 = casPutEntry(casDir, fp, value2, digest2)
    check "second put with same key different content returns cpoConflict":
      assert putRes2.isOk()
      assert putRes2.get() == cpoConflict

    # After CONFLICT the original entry is discarded and the new value
    # is NOT written — so promote and get should both miss.
    let promoRes = casPromoteEntry(casDir, fp, true)
    check "promote fails after CONFLICT (entry discarded)":
      assert promoRes.isErr()

    let getRes = casGetEntry(casDir, fp, digest1)
    check "get misses after CONFLICT (entry discarded)":
      assert getRes.isErr()

  echo ""
  echo "=== Canonical Cache — fail-closed on corrupted value ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    # Store a valid entry
    let value = "original-result"
    let digest = contentDigestOf(value)
    let putRes = casPutEntry(casDir, fp, value, digest)
    check "put succeeds for valid entry":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # Corrupt the stored file by overwriting it with wrong content
    let epochDir = casDir / "epoch_0"
    var foundCorrupted = false
    for kind, subdir in walkDir(epochDir):
      if kind != pcDir: continue
      for fileKind, filePath in walkDir(subdir):
        if fileKind != pcFile: continue
        try:
          let writeRes = writeFileOpt(filePath, "corrupted-content")
          if writeRes.isOk():
            foundCorrupted = true
        except CatchableError:  # axiom:best-effort(corruption-write failure is non-fatal — fallback scan below retries; real assertion is get() contentDigest fail-closed below)
          discard
      if foundCorrupted: break
    if not foundCorrupted:
      # Fallback: find the file by scanning
      for kind, subdir in walkDir(epochDir):
        if kind != pcDir: continue
        for fileKind, filePath in walkDir(subdir):
          if fileKind != pcFile: continue
          try:
            discard writeFileOpt(filePath, "corrupted-content")  # axiom:best-effort(corruption setup — failed write leaves foundCorrupted unset; get() assertion below verifies fail-closed regardless)
            foundCorrupted = true
          except CatchableError:
            discard  # axiom:best-effort(corruption-write failure is non-fatal; covered by fallback scan + get() contentDigest assertion)

    # Promote so get reaches the contentDigest verification
    discard casPromoteEntry(casDir, fp, true)

    # get should fail-closed on corrupted content
    let getRes = casGetEntry(casDir, fp, digest)
    check "get fails on corrupted value (contentDigest mismatch)":
      assert getRes.isErr()

  echo ""
  echo "=== Canonical Cache — pending entry is a cache miss ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "pending-result"
    let digest = contentDigestOf(value)
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, digest)
    check "put succeeds for pending entry":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # get should return miss for non-authoritative entry
    let getRes = casGetEntry(casDir, fp, digest)
    check "get returns miss for pending (non-authoritative) entry":
      assert getRes.isErr()

  echo ""
  echo "=== Canonical Cache — promote makes entry authoritative ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "promotable-result"
    let digest = contentDigestOf(value)
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, digest)
    check "put succeeds for promotable entry":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # Before promotion: get should miss
    let getBefore = casGetEntry(casDir, fp, digest)
    check "get misses before promotion":
      assert getBefore.isErr()

    # Promote the entry
    let promoRes = casPromoteEntry(casDir, fp, true)
    check "promote succeeds":
      assert promoRes.isOk()

    # After promotion: get should succeed
    let getAfter = casGetEntry(casDir, fp, digest)
    check "get succeeds after promotion (authoritative)":
      assert getAfter.isOk()
      assert getAfter.get() == value

  echo ""
  echo "=== Canonical Cache — same-key-same-content = HIT ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "hit-test-result"
    let digest = contentDigestOf(value)
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes1 = casPutEntry(casDir, fp, value, digest)
    check "first put returns cpoStored":
      assert putRes1.isOk()
      assert putRes1.get() == cpoStored

    let putRes2 = casPutEntry(casDir, fp, value, digest)
    check "second put with same key+content returns cpoHit":
      assert putRes2.isOk()
      assert putRes2.get() == cpoHit

  echo ""
  echo "=== Canonical Cache — contentDigest mismatch on put ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "some-result"
    let wrongDigest = sha256hex("not-the-right-hash")
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, wrongDigest)
    check "put fails when contentDigest does not match SHA256(value)":
      assert putRes.isErr()

  echo ""
  echo "=== Canonical Cache — P8.4 PASS-only gate: promote requires soundnessCertified ==="

  block:
    let casDir = newTempCasDir()
    defer: removeDir(casDir)

    let value = "uncertified-result"
    let digest = contentDigestOf(value)
    let fp = makeFingerprint(
      sha256hex("source-closure"),
      sha256hex("toolchain"),
      sha256hex("contract"),
      sha256hex("exec-config")
    )

    let putRes = casPutEntry(casDir, fp, value, digest)
    check "put succeeds for uncertified entry":
      assert putRes.isOk()
      assert putRes.get() == cpoStored

    # PASS-only gate: soundnessCertified=false → promote MUST fail.
    let promoUncert = casPromoteEntry(casDir, fp, false)
    check "promote fails when soundnessCertified=false (P8.4 gate)":
      assert promoUncert.isErr()

    # Consequently the entry remains non-authoritative → get is a miss.
    let getUncert = casGetEntry(casDir, fp, digest)
    check "get misses for un-promoted (uncertified) entry":
      assert getUncert.isErr()

    # Explicit reviewer approval (soundnessCertified=true) allows promotion.
    let promoCert = casPromoteEntry(casDir, fp, true)
    check "promote succeeds when soundnessCertified=true (P8.4 gate)":
      assert promoCert.isOk()

    let getCert = casGetEntry(casDir, fp, digest)
    check "get succeeds after soundness-certified promotion":
      assert getCert.isOk()
      assert getCert.get() == value

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
