## Negative compile test — Evidence Truth Boundary receipt/KAA opacity.
## nim-check: skip
##
## This file MUST FAIL to compile: `LeanKernelCheckReceipt` fields are
## private and its constructor is private to `lean_kernel_boundary.nim`.
## External initialization or mutation of a receipt is an authority
## violation and must be a compile error, not a runtime concern.
## Run with: nim c --hints:off tests/negative/forge_receipt_external.nim
## Expected: compile error (attempt to access private field / undeclared
## constructor of LeanKernelCheckReceipt)

discard """
  action: "reject"
  errorMsg: "attempt to access"
"""

import ../../src/verification/obligation/lean_kernel_boundary

proc forgeReceipt(): LeanKernelCheckReceipt =
  LeanKernelCheckReceipt(
    actualExecutableDigest: "sha256:forged",
    actualToolchainFingerprint: "sha256:forged",
    actualInvocationContract: "lake env lean --threads=1 /tmp/forged.lean",
    actualExecutionContract: "sha256:forged",
    actualInputIdentity: "sha256:forged",
    actualArtifactIdentity: "sha256:forged",
    actualTheoremIdentity: "forgedTheorem",
    actualKernelAcceptanceObservation: "forged",
    observedAt: 0
  )
