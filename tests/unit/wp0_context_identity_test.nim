import std/[unittest, os, options]
import core/context/run_context
import core/crypto/hash_kernel
import core/results
import checksums/sha2

# Helper: compute raw SHA-256 bytes of a string payload.
func rawSha256*(payload: string): array[32, byte] =
  let digest = secureHash(Sha_256, payload)
  for i in 0..31:
    result[i] = byte(digest[i])

suite "WP0-b context identity — golden vector & edge cases":

  # ── Golden vector (self-contained, no filesystem) ──────────
  # D1 record encoding: [u32 LE len] [relPath bytes] [32-byte sha256].
  # Records for "a.nim"(content b"AA") then "bb/stew.nim"(content b"BB")
  # are already in byte-lex sorted order.  The 88-byte concat stream
  # must produce the canonical fingerprint below.

  test "golden vector: two records produce canonical fingerprint":
    let
      r1 = encodeFingerprintRecord("a.nim", rawSha256("AA"))
      r2 = encodeFingerprintRecord("bb/stew.nim", rawSha256("BB"))

    # Concat in sorted order (already sorted).
    let stream = r1 & r2
    let fp = sha256Hex(cast[string](stream))

    check fp == "40ce20871065e0171667c4fb528cb120ef76a7ff0e2a9435284d964036b450d9"

  # ── u32 LE prefix edge assert ──────────────────────────

  test "u32 LE prefix bytes for len 5 == [5, 0, 0, 0]":
    let r = encodeFingerprintRecord("a.nim", rawSha256("AA"))
    # First 4 bytes are the LE u32 length prefix.
    check r[0] == 5.byte
    check r[1] == 0.byte
    check r[2] == 0.byte
    check r[3] == 0.byte

  # ── Unicode no-normalization (NFC vs NFD) ──────────────
  # D1 mandates: "NFC/NFD 등 어떤 유니코드 정규화도 수행하지 않는다"
  # Paths that differ only by Unicode normalization must produce
  # distinct fingerprints.

  test "unicode NFC vs NFD produce different fingerprints":
    # é.nim in NFC = U+00E9 → bytes C3 A9
    let nfcPath = "\u00e9.nim"
    # é.nim in NFD = U+0065 + U+0301 → bytes 65 CC 81
    let nfdPath = "e\u0301.nim"

    let fpNfc = finalizeSourceFingerprint(@[
      encodeFingerprintRecord(nfcPath, rawSha256("XX")),
    ])
    let fpNfd = finalizeSourceFingerprint(@[
      encodeFingerprintRecord(nfdPath, rawSha256("XX")),
    ])

    check fpNfc != fpNfd

  # ── lockAbsentLiteral stable constant ──────────────────

  test "lockAbsentLiteral is stable constant \"absent\"":
    check lockAbsentLiteral == "absent"

  # ── Optional filesystem-based test (best-effort) ───────

  test "buildVerificationSubject on a tmpdir produces a subject":
    let tmpDir = getTempDir() / "axiom_wp0_ctx_test_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    # Write two tiny files so collectSubjectFileSet has work.
    writeFile(tmpDir / "a.nim", "AA")
    createDir(tmpDir / "bb")
    writeFile(tmpDir / "bb" / "stew.nim", "BB")

    let res = buildVerificationSubject(tmpDir)
    let subjOpt = if res.isOk(): some(res.value) else: none(VerificationSubject)
    check subjOpt.isSome()
    let subj = subjOpt.get()
    check subj.sourceFingerprint.len > 0
    check subj.lockfileDigest == lockAbsentLiteral
