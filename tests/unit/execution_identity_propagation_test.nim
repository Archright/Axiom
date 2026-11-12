# execution_identity_propagation_test.nim
# Phase B — End-to-end identity propagation regression tests.
#
# Proves that execution identity binds the MEASURED bundle fingerprint
# (from canonicalLeanKernelCheck → receipt.receiptToolchainFingerprint)
# rather than any hand-built placeholder.
#
# Run: nim c -r --hints:off tests/unit/execution_identity_propagation_test.nim

import std/[unittest, os]
import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/verification/obligation/identity

const
  DefaultResolvedCmd = "lake env lean"
  DefaultTimeoutMs = 120_000

proc d2LeanSource(): string =
  "theorem d2Golden : True := trivial\n"

suite "Execution Identity Propagation — Phase B":

  # -----------------------------------------------------------------------
  # (a) same binary + same deps + same env → same bundle/evidence identity
  # -----------------------------------------------------------------------

  test "same source run twice produces identical bundle fingerprints and execution identities":
    let source = d2LeanSource()
    let receipt1 = canonicalLeanKernelCheck(source).get()
    let receipt2 = canonicalLeanKernelCheck(source).get()

    ## Both receipts must carry the same measured toolchain fingerprint.
    check receipt1.receiptToolchainFingerprint.len == 64
    check receipt2.receiptToolchainFingerprint.len == 64
    check receipt1.receiptToolchainFingerprint == receipt2.receiptToolchainFingerprint

    ## Execution identity must be identical when the measured fingerprint is the same.
    let inputId = sha256Hex(source)
    let contract = canonicalExecutionContract(
      invocation = "lake env lean --threads=1 <artifact>.lean",
      platform = "linux-x86_64",
      workdir = getCurrentDir(),
      allowedEnv = @[
        EnvVarSpec(name: "AXIOM_LEAN_CMD", canonicalValue: ""),
        EnvVarSpec(name: "PATH", canonicalValue: ""),
        EnvVarSpec(name: "TMPDIR", canonicalValue: "")
      ],
      fsBoundary = getCurrentDir(),
      networkPolicy = "deny",
      mountedInputs = inputId,
      resourcePolicy = "cpu=1,mem=512MB"
    )
    let contractDigest = executionContractDigest(contract)
    let execId1 = executionIdentity(inputId, contractDigest, receipt1.receiptToolchainFingerprint)
    let execId2 = executionIdentity(inputId, contractDigest, receipt2.receiptToolchainFingerprint)
    check execId1 == execId2

  # -----------------------------------------------------------------------
  # (b) same label + different binary → different bundle/evidence identity
  # -----------------------------------------------------------------------

  test "different lean binary bytes produce different bundle digests":
    let tmpBase = getTempDir() / ("axiom_prop_test_" & $getCurrentProcessId())
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

  # -----------------------------------------------------------------------
  # (c) same binary + different dependency manifest → different bundle identity
  # -----------------------------------------------------------------------

  test "same binary with different lean-toolchain manifest produces different bundle digest":
    let tmpBase = getTempDir() / ("axiom_prop_test_" & $getCurrentProcessId())
    createDir(tmpBase)
    let leanBin = tmpBase / "lean_bin"
    writeFile(leanBin, "same-binary-content")

    let dirA = tmpBase / "env_a"
    let dirB = tmpBase / "env_b"
    createDir(dirA)
    createDir(dirB)

    let origCwd = getCurrentDir()
    try:
      ## Write different lean-toolchain manifests into two CWDs.
      writeFile(dirA / "lean-toolchain", "lean 4.33.0")
      writeFile(dirB / "lean-toolchain", "lean 4.34.0")

      ## Compute digest from CWD A.
      setCurrentDir(dirA)
      let digestA = computeBundleDigest(leanBin, "", DefaultTimeoutMs, DefaultResolvedCmd)

      ## Compute digest from CWD B (same binary, different manifest).
      setCurrentDir(dirB)
      let digestB = computeBundleDigest(leanBin, "", DefaultTimeoutMs, DefaultResolvedCmd)

      check digestA.len == 64
      check digestB.len == 64
      check digestA != digestB
    finally:
      setCurrentDir(origCwd)
      removeDir(tmpBase)
