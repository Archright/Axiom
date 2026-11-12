## tests/unit/test_capture_toolchain_fingerprint.nim
## Phase 1A — the strict-binding capture fingerprint is the receipt/CLE
## composition, never a forked formula.
##
## Covers (each named for the failure mode it pins):
##   - the shared core is ONE proc: `computeBundleDigest` (the receipt-side
##     entry the canonical kernel check calls) returns byte-identical output
##     to `measureToolchainBundleFingerprint` over the same inputs.
##   - the capture-site composition equals the receipt composition: what
##     `canonicalLeanKernelCheck` measures into `receiptToolchainFingerprint`
##     (over its resolved lean binary, lake binary, AXIOM_LEAN_CMD rule and
##     120_000 ms timeout) is exactly what
##     `measureCanonicalCaptureToolchainFingerprint` records at capture time.
##   - the capture fingerprint is a measured 64-hex digest, never a label.
##   - determinism: two captures in the same environment agree.
##
## Run: nim c --hints:off --path:src -o:tmp/test_capture_toolchain_fingerprint -r tests/unit/test_capture_toolchain_fingerprint.nim
## (requires the repo toolchain layout — `lake env which lean` must resolve)

import std/[os, strutils]
import core/crypto/hash_kernel
import infrastructure/process_utils
import verification/obligation/lean_kernel_boundary
import verification/obligation/toolchain_capture

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
    # canonicalLeanKernelCheck: leanCmd non-empty → resolvedCmd = leanCmd,
    # else "lake env lean". canonicalCaptureResolvedCmd is the same rule.
    let saved = getEnv("AXIOM_LEAN_CMD", "")
    try:
      putEnv("AXIOM_LEAN_CMD", "")
      doAssert canonicalCaptureResolvedCmd() == "lake env lean"
      putEnv("AXIOM_LEAN_CMD", "/custom/lean")
      doAssert canonicalCaptureResolvedCmd() == "/custom/lean"
    finally:
      putEnv("AXIOM_LEAN_CMD", saved)

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
