# bundle_digest_test.nim
# Regression test for the "same label / different binary" invariant.
#
# The bug was that computeBundleDigest used hardcoded version-label placeholders
# (lean-4.33.0, sha256Hex("axiom-binary")) instead of the ACTUAL executed binary
# bytes, so two runs with the same digest could point at different real Lean/Lake
# environments. This test proves that computeBundleDigest responds to actual content
# differences in the lean binary path.
#
# Run: nim c -r --hints:off tests/unit/bundle_digest_test.nim

import std/[unittest, os]
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/core/crypto/hash_kernel

const
  DefaultResolvedCmd = "lake env lean"
  DefaultTimeoutMs = 120_000

suite "computeBundleDigest — content-addressed fingerprint invariant":

  test "different lean binary bytes produce different digests":
    ## Core regression: same version label but different actual binary bytes
    ## must yield different bundle fingerprints.
    let tmpBase = getTempDir() / ("axiom_bundle_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanPath1 = tmpBase / "lean_bin_1"
      let leanPath2 = tmpBase / "lean_bin_2"
      writeFile(leanPath1, "lean-binary-content-v1")
      writeFile(leanPath2, "lean-binary-content-v2-different-bytes")

      let digest1 = computeBundleDigest(leanPath1, "", DefaultTimeoutMs, DefaultResolvedCmd)
      let digest2 = computeBundleDigest(leanPath2, "", DefaultTimeoutMs, DefaultResolvedCmd)

      check digest1.len == 64
      check digest2.len == 64
      check digest1 != digest2
    finally:
      removeDir(tmpBase)

  test "same lean binary bytes produce identical digests (determinism)":
    let tmpBase = getTempDir() / ("axiom_bundle_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanPath = tmpBase / "lean_bin"
      writeFile(leanPath, "identical-binary-content")

      let digest1 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, DefaultResolvedCmd)
      let digest2 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, DefaultResolvedCmd)

      check digest1 == digest2
    finally:
      removeDir(tmpBase)

  test "different resolvedCmd produces different digest":
    let tmpBase = getTempDir() / ("axiom_bundle_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanPath = tmpBase / "lean_bin"
      writeFile(leanPath, "same-binary-content")

      let digest1 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, "lake env lean")
      let digest2 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, "lake env lean --threads=2")

      check digest1 != digest2
    finally:
      removeDir(tmpBase)

  test "different timeoutMs produces different digest":
    let tmpBase = getTempDir() / ("axiom_bundle_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanPath = tmpBase / "lean_bin"
      writeFile(leanPath, "same-binary-content")

      let digest1 = computeBundleDigest(leanPath, "", 100_000, DefaultResolvedCmd)
      let digest2 = computeBundleDigest(leanPath, "", 200_000, DefaultResolvedCmd)

      check digest1 != digest2
    finally:
      removeDir(tmpBase)

  test "non-existent lean binary produces consistent empty digest component":
    let tmpBase = getTempDir() / ("axiom_bundle_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanPath = tmpBase / "nonexistent"
      # leanPath does not exist; lakePath also empty — function should not crash
      let digest1 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, DefaultResolvedCmd)
      let digest2 = computeBundleDigest(leanPath, "", DefaultTimeoutMs, DefaultResolvedCmd)

      check digest1.len == 64
      check digest2.len == 64
      check digest1 == digest2
    finally:
      removeDir(tmpBase)
