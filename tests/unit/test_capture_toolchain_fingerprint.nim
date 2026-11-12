## tests/unit/test_capture_toolchain_fingerprint.nim
## Phase 1A + VS-R1 — strict-binding capture fingerprint & 10-scenario
## tamper/memoization regression battery.
##
## Covers:
##   - Shared composition (no fork): `computeBundleDigest` == `measureToolchainBundleFingerprint`
##   - Capture-site composition == receipt composition
##   - 10-scenario tamper & invalidation battery for `measured_digests` and
##     `lean_kernel_boundary`:
##     1. Repeated calls on same file/binary increment `hits` and keep `misses == 1`
##     2. File size change invalidates memo and produces new digest
##     3. File content + mtime change invalidates memo and produces new digest
##     4. Same-size content change ("ABCDEF" -> "XYZDEF") within the same ms
##        AND with `mtime` restored via `setLastModificationTime` is detected
##     5. Atomic `moveFile`/`rename` replacement (new `ino`, same size + mtime)
##        invalidates memo and produces new digest
##     6. `CWD` change (`setCurrentDir(dirA)` -> `setCurrentDir(dirB)`)
##        re-evaluates relative paths (`"lean-toolchain"`)
##     7. `"lean-toolchain"` content change invalidates both
##        `resolveLeanBinaryPath` memo and `measureToolchainBundleFingerprint`
##     8. `AXIOM_LEAN_CMD` change is reflected immediately in
##        `resolveLeanBinaryPath` and `canonicalCaptureResolvedCmd`
##     9. `timeoutMs` change produces a different `computeBundleDigest`
##     10. Manifest (`lake-manifest.json` / `lakefile.toml`) or lowering file
##         (`pnode_to_canon.nim`) change invalidates `measuredFileDigest` and
##         produces a different `computeBundleDigest`

import std/[os, strutils, times]
import core/crypto/hash_kernel
import infrastructure/process_utils
import verification/obligation/measured_digests
import verification/obligation/lean_kernel_boundary
import verification/obligation/toolchain_capture

proc populateSandboxRepo(repoDir: string) =
  createDir(repoDir)
  createDir(repoDir / "proofs" / "IR")
  createDir(repoDir / "src" / "core" / "trusted")
  writeFile(repoDir / "lean-toolchain", "leanprover/lean4:v4.29.0\n")
  writeFile(repoDir / "proofs" / "lean-toolchain", "leanprover/lean4:v4.29.0\n")
  writeFile(repoDir / "lake-manifest.json", "{\"version\": 7, \"packages\": []}\n")
  writeFile(repoDir / "proofs" / "lake-manifest.json", "{\"version\": 7, \"packages\": []}\n")
  writeFile(repoDir / "lakefile.toml", "name = \"axiom\"\n")
  writeFile(repoDir / "proofs" / "lakefile.lean", "-- lakefile\n")
  writeFile(repoDir / "src" / "core" / "trusted" / "pnode_to_canon.nim", "# pnode_to_canon v1\n")
  writeFile(repoDir / "src" / "core" / "trusted" / "ast_to_ir.nim", "# ast_to_ir v1\n")
  writeFile(repoDir / "src" / "core" / "trusted" / "ir_to_lean.nim", "# ir_to_lean v1\n")
  writeFile(repoDir / "proofs" / "IR" / "Denotation.lean", "-- Denotation v1\n")

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
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  echo "=== shared composition (no fork) ==="

  check "computeBundleDigest == measureToolchainBundleFingerprint (same inputs)":
    let leanPath = resolveLeanBinaryPath()
    let lakePath = findExe("lake")
    let resolvedCmd = canonicalCaptureResolvedCmd()
    let viaReceiptEntry = computeBundleDigest(leanPath, lakePath, 120_000,
      resolvedCmd)
    let viaSharedCore = measureToolchainBundleFingerprint(leanPath, lakePath,
      120_000, resolvedCmd)
    doAssert viaReceiptEntry == viaSharedCore
    doAssert viaReceiptEntry.len == 64

  echo "=== capture == receipt composition ==="

  check "measureCanonicalCaptureToolchainFingerprint equals the receipt composition":
    let receiptComposition = computeBundleDigest(
      leanPath = resolveLeanBinaryPath(),
      lakePath = findExe("lake"),
      timeoutMs = 120_000,
      resolvedCmd = canonicalCaptureResolvedCmd()
    )
    let captured = measureCanonicalCaptureToolchainFingerprint()
    doAssert captured == receiptComposition

  check "capture fingerprint is a measured sha256-hex digest, never a label":
    let captured = measureCanonicalCaptureToolchainFingerprint()
    doAssert captured.len == 64
    for ch in captured:
      doAssert ch in {'0'..'9', 'a'..'f'}

  check "capture determinism: two captures in one environment agree":
    doAssert measureCanonicalCaptureToolchainFingerprint() ==
             measureCanonicalCaptureToolchainFingerprint()

  check "resolvedCmd rule mirrors the canonical check (AXIOM_LEAN_CMD override)":
    let saved = getEnv("AXIOM_LEAN_CMD", "")
    try:
      putEnv("AXIOM_LEAN_CMD", "")
      doAssert canonicalCaptureResolvedCmd() == "lake env lean"
      putEnv("AXIOM_LEAN_CMD", "/custom/lean")
      doAssert canonicalCaptureResolvedCmd() == "/custom/lean"
    finally:
      putEnv("AXIOM_LEAN_CMD", saved)

  echo "=== VS-R1 10-scenario tamper & memoization regression battery ==="

  let tmpRoot = getTempDir() / ("axiom_vs_r1_test_" & $getCurrentProcessId())
  createDir(tmpRoot)
  try:
    check "Scenario 1: repeated calls on same file/binary increment hits and do not recompute SHA-256":
      let smallFile = tmpRoot / "scenario1_small.txt"
      let largeBin = tmpRoot / "scenario1_large.bin"
      writeFile(smallFile, "deterministic-manifest-payload")
      let largePayload = "HEAD-MARKER-" & repeat('X', 1_100_000) & "-TAIL-MARKER"
      writeFile(largeBin, largePayload)

      resetMeasuredDigestStats()
      doAssert measuredDigestStats() == (hits: 0, misses: 0)

      let d1 = measuredFileDigest(smallFile)
      doAssert d1 == sha256Hex("deterministic-manifest-payload")
      doAssert measuredDigestStats() == (hits: 0, misses: 1)

      let d2 = measuredFileDigest(smallFile)
      let d3 = measuredBinaryDigest(smallFile)
      doAssert d2 == d1 and d3 == d1
      doAssert measuredDigestStats() == (hits: 2, misses: 1)

      resetMeasuredDigestStats()
      let b1 = measuredBinaryDigest(largeBin)
      doAssert b1 == sha256Hex(largePayload)
      doAssert measuredDigestStats() == (hits: 0, misses: 1)

      let b2 = measuredBinaryDigest(largeBin)
      let b3 = measuredBinaryDigest(largeBin)
      doAssert b2 == b1 and b3 == b1
      doAssert measuredDigestStats() == (hits: 2, misses: 1)

    check "Scenario 2: file size change invalidates memo and produces new digest":
      let p = tmpRoot / "scenario2_size.txt"
      writeFile(p, "short")
      resetMeasuredDigestStats()
      let d1 = measuredFileDigest(p)
      doAssert d1 == sha256Hex("short")
      doAssert measuredDigestStats() == (hits: 0, misses: 1)

      writeFile(p, "longer-content-now")
      let d2 = measuredFileDigest(p)
      doAssert d2 == sha256Hex("longer-content-now")
      doAssert d2 != d1
      doAssert measuredDigestStats() == (hits: 0, misses: 2)

    check "Scenario 3: file content + mtime change invalidates memo and produces new digest":
      let p = tmpRoot / "scenario3_mtime.txt"
      writeFile(p, "version-alpha")
      setLastModificationTime(p, fromUnix(1_700_000_000))
      resetMeasuredDigestStats()
      let d1 = measuredFileDigest(p)
      doAssert d1 == sha256Hex("version-alpha")

      writeFile(p, "version-bravo")
      setLastModificationTime(p, fromUnix(1_700_000_100))
      let d2 = measuredFileDigest(p)
      doAssert d2 == sha256Hex("version-bravo")
      doAssert d2 != d1
      doAssert measuredDigestStats() == (hits: 0, misses: 2)

    check "Scenario 4: same-size content change ('ABCDEF' -> 'XYZDEF') within same ms + restored mtime is detected":
      let p = tmpRoot / "scenario4_samesize.txt"
      let forgedTime = fromUnix(1_700_123_456)
      writeFile(p, "ABCDEF")
      setLastModificationTime(p, forgedTime)
      resetMeasuredDigestStats()

      let d1 = measuredFileDigest(p)
      doAssert d1 == sha256Hex("ABCDEF")
      doAssert measuredDigestStats() == (hits: 0, misses: 1)

      # Overwrite in-place with identical byte length (6 bytes) and restore mtime
      writeFile(p, "XYZDEF")
      setLastModificationTime(p, forgedTime)

      let d2 = measuredFileDigest(p)
      doAssert d2 == sha256Hex("XYZDEF")
      doAssert d2 != d1
      doAssert measuredDigestStats() == (hits: 0, misses: 2)

    check "Scenario 5: file replacement via atomic moveFile/rename (new ino, same size/mtime) invalidates memo":
      let target = tmpRoot / "scenario5_target.bin"
      let staging = tmpRoot / "scenario5_staging.bin"
      let fixedTime = fromUnix(1_700_222_222)
      writeFile(target, "BINARY_V1")
      setLastModificationTime(target, fixedTime)
      resetMeasuredDigestStats()

      let d1 = measuredBinaryDigest(target)
      doAssert d1 == sha256Hex("BINARY_V1")
      doAssert measuredDigestStats() == (hits: 0, misses: 1)

      writeFile(staging, "BINARY_V2")
      setLastModificationTime(staging, fixedTime)
      moveFile(staging, target)
      setLastModificationTime(target, fixedTime)

      let d2 = measuredBinaryDigest(target)
      doAssert d2 == sha256Hex("BINARY_V2")
      doAssert d2 != d1
      doAssert measuredDigestStats() == (hits: 0, misses: 2)

    check "Scenario 6: CWD change (setCurrentDir(dirA) -> setCurrentDir(dirB)) re-evaluates relative paths":
      let origCwd = getCurrentDir()
      let dirA = tmpRoot / "cwd_A"
      let dirB = tmpRoot / "cwd_B"
      createDir(dirA)
      createDir(dirB)
      writeFile(dirA / "lean-toolchain", "leanprover/lean4:v4.29.0\n")
      writeFile(dirB / "lean-toolchain", "leanprover/lean4:v4.33.0\n")
      try:
        resetMeasuredDigestStats()
        setCurrentDir(dirA)
        let dA = measuredFileDigest("lean-toolchain")
        doAssert dA == sha256Hex("leanprover/lean4:v4.29.0\n")

        setCurrentDir(dirB)
        let dB = measuredFileDigest("lean-toolchain")
        doAssert dB == sha256Hex("leanprover/lean4:v4.33.0\n")
        doAssert dA != dB

        setCurrentDir(dirA)
        let dA2 = measuredFileDigest("lean-toolchain")
        doAssert dA2 == dA
        doAssert measuredDigestStats() == (hits: 1, misses: 2)
      finally:
        setCurrentDir(origCwd)

    check "Scenario 7: 'lean-toolchain' content change invalidates resolveLeanBinaryPath memo and measureToolchainBundleFingerprint":
      let origCwd = getCurrentDir()
      let savedPath = getEnv("PATH", "")
      let savedLeanCmd = getEnv("AXIOM_LEAN_CMD", "")
      let repoDir = tmpRoot / "scenario7_repo"
      let binDir = tmpRoot / "scenario7_bin"
      populateSandboxRepo(repoDir)
      createDir(binDir)

      let leanV1 = binDir / "lean_v4_29"
      let leanV2 = binDir / "lean_v4_33"
      let fakeLake = binDir / "lake"
      writeFile(leanV1, "#!/bin/sh\necho Lean4.29\n")
      writeFile(leanV2, "#!/bin/sh\necho Lean4.33\n")
      writeFile(
        fakeLake,
        "#!/bin/sh\n" &
        "if grep -q 'v4.29.0' lean-toolchain 2>/dev/null; then\n" &
        "  echo '" & leanV1 & "'\n" &
        "else\n" &
        "  echo '" & leanV2 & "'\n" &
        "fi\n"
      )
      setFilePermissions(leanV1, {fpUserRead, fpUserWrite, fpUserExec})
      setFilePermissions(leanV2, {fpUserRead, fpUserWrite, fpUserExec})
      setFilePermissions(fakeLake, {fpUserRead, fpUserWrite, fpUserExec})

      try:
        putEnv("AXIOM_LEAN_CMD", "")
        putEnv("PATH", binDir & ":" & savedPath)
        setCurrentDir(repoDir)
        resetMeasuredDigestStats()

        let resolved1 = resolveLeanBinaryPath()
        doAssert resolved1 == leanV1
        let resolved1Cached = resolveLeanBinaryPath()
        doAssert resolved1Cached == leanV1
        let fp1 = measureToolchainBundleFingerprint(
          resolved1, fakeLake, 120_000, "lake env lean")

        # Mutate lean-toolchain -> must invalidate both resolveLeanBinaryPath and fingerprint
        writeFile(repoDir / "lean-toolchain", "leanprover/lean4:v4.33.0\n")
        let resolved2 = resolveLeanBinaryPath()
        doAssert resolved2 == leanV2
        doAssert resolved2 != resolved1
        let fp2 = measureToolchainBundleFingerprint(
          resolved2, fakeLake, 120_000, "lake env lean")
        doAssert fp2 != fp1
      finally:
        setCurrentDir(origCwd)
        putEnv("PATH", savedPath)
        putEnv("AXIOM_LEAN_CMD", savedLeanCmd)

    check "Scenario 8: AXIOM_LEAN_CMD change is reflected immediately in resolveLeanBinaryPath and canonicalCaptureResolvedCmd":
      let savedLeanCmd = getEnv("AXIOM_LEAN_CMD", "")
      try:
        putEnv("AXIOM_LEAN_CMD", "/tmp/custom_lean_alpha")
        doAssert resolveLeanBinaryPath() == "/tmp/custom_lean_alpha"
        doAssert canonicalCaptureResolvedCmd() == "/tmp/custom_lean_alpha"

        putEnv("AXIOM_LEAN_CMD", "/tmp/custom_lean_bravo")
        doAssert resolveLeanBinaryPath() == "/tmp/custom_lean_bravo"
        doAssert canonicalCaptureResolvedCmd() == "/tmp/custom_lean_bravo"
      finally:
        putEnv("AXIOM_LEAN_CMD", savedLeanCmd)

    check "Scenario 9: timeoutMs change produces a different computeBundleDigest":
      let leanBin = tmpRoot / "scenario9_lean.bin"
      let lakeBin = tmpRoot / "scenario9_lake.bin"
      writeFile(leanBin, "lean-kernel-bytes")
      writeFile(lakeBin, "lake-runner-bytes")
      let fp120 = computeBundleDigest(leanBin, lakeBin, 120_000, "lake env lean")
      let fp60 = computeBundleDigest(leanBin, lakeBin, 60_000, "lake env lean")
      doAssert fp120.len == 64 and fp60.len == 64
      doAssert fp120 != fp60

    check "Scenario 10: manifest (lake-manifest.json / lakefile.toml) or lowering file (pnode_to_canon.nim) change invalidates measuredFileDigest and computeBundleDigest":
      let origCwd = getCurrentDir()
      let repoDir = tmpRoot / "scenario10_repo"
      populateSandboxRepo(repoDir)
      let leanBin = repoDir / "lean.bin"
      let lakeBin = repoDir / "lake.bin"
      writeFile(leanBin, "lean-kernel-v1")
      writeFile(lakeBin, "lake-binary-v1")

      try:
        setCurrentDir(repoDir)
        resetMeasuredDigestStats()

        let m0 = measuredFileDigest("lake-manifest.json")
        let l0 = measuredFileDigest("lakefile.toml")
        let p0 = measuredFileDigest("src/core/trusted/pnode_to_canon.nim")
        let fp0 = computeBundleDigest(leanBin, lakeBin, 120_000, "lake env lean")

        # 10a: lake-manifest.json change
        writeFile(repoDir / "lake-manifest.json", "{\"version\": 7, \"packages\": [{\"name\": \"mathlib\"}]}\n")
        let m1 = measuredFileDigest("lake-manifest.json")
        let fp1 = computeBundleDigest(leanBin, lakeBin, 120_000, "lake env lean")
        doAssert m1 != m0
        doAssert fp1 != fp0

        # 10b: lakefile.toml change
        writeFile(repoDir / "lakefile.toml", "name = \"axiom_v2\"\n")
        let l1 = measuredFileDigest("lakefile.toml")
        let fp2 = computeBundleDigest(leanBin, lakeBin, 120_000, "lake env lean")
        doAssert l1 != l0
        doAssert fp2 != fp1

        # 10c: lowering file (pnode_to_canon.nim) same-size change
        writeFile(repoDir / "src" / "core" / "trusted" / "pnode_to_canon.nim", "# pnode_to_canon v2\n")
        let p1 = measuredFileDigest("src/core/trusted/pnode_to_canon.nim")
        let fp3 = computeBundleDigest(leanBin, lakeBin, 120_000, "lake env lean")
        doAssert p1 != p0
        doAssert fp3 != fp2
      finally:
        setCurrentDir(origCwd)
  finally:
    removeDir(tmpRoot)

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
