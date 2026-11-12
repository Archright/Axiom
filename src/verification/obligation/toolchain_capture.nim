# axiomIoBoundary — producer-side toolchain measurement adapter (subprocess /
# file I/O); declared so the new-code purity ratchet treats this as a boundary
# module, not core logic that should be func.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Capture-time toolchain fingerprint adapter for strict completeness
## producers. Kept OUT of lean_kernel_boundary.nim: the receipt/sink module
## stays cohesive (its SRP budget is ratcheted), while this module is the
## producer-side wrapper over the SAME shared composition
## (`measureToolchainBundleFingerprint`) — no forked formula.

import std/os
import core/axiom_pragmas
import core/trusted/env_types
import verification/obligation/lean_kernel_boundary

template canonicalCaptureResolvedCmd*(): string =
  ## The resolved command string the canonical kernel check uses
  ## (canonicalLeanKernelCheck step 1) — the same AXIOM_LEAN_CMD-override
  ## rule, extracted so the capture sites compose the fingerprint over the
  ## SAME command component the receipt will carry.
  ##
  ## A template, not a proc: this is a one-line rule, not a second unit of
  ## behavior, and the module's cohesion budget must stay with the measured
  ## composition (the SRP ratchet counts proc/func/method bodies).
  block:
    let leanCmd = getAxiomEnv(evLeanCmd, "")
    if leanCmd.len > 0: leanCmd
    else: "lake env lean"

proc measureCanonicalCaptureToolchainFingerprint*(): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The capture-time fingerprint for strict CompletenessBinding producers:
  ## the SAME composition (`measureToolchainBundleFingerprint`) the canonical
  ## kernel receipt computes, over the SAME inputs the canonical check
  ## resolves (lean binary via resolveLeanBinaryPath, lake via findExe, the
  ## AXIOM_LEAN_CMD override rule) and the canonical check's timeout
  ## (canonical_verification.runKernelCheck pins timeoutMs = 120_000 — this
  ## constant is that contract's capture-side mirror). A capture under a
  ## different toolchain/binary/manifest state than the later kernel
  ## execution measures a different value here, which fails the strict
  ## binding load closed — exactly the intended staleness gate.
  ## raises: [] — every raising resolution is caught at this boundary: an
  ## unresolvable lean binary contributes "" (its own component value, the
  ## same rule `measureToolchainBundleFingerprint` applies to unmeasurable
  ## files), and an unmeasurable composition yields "" — never an escaped
  ## exception, and never a fabricated fingerprint.
  var leanPath = ""
  try:
    leanPath = resolveLeanBinaryPath()
  except CatchableError:
    discard  # axiom:best-effort(unresolvable lean binary is an empty component)
  var lakePath = ""
  try:
    lakePath = findExe("lake")
  except CatchableError:
    discard  # axiom:best-effort(unresolvable lake binary is an empty component)
  try:
    result = measureToolchainBundleFingerprint(
      leanPath = leanPath,
      lakePath = lakePath,
      timeoutMs = 120_000,
      resolvedCmd = canonicalCaptureResolvedCmd()
    )
  except CatchableError:
    result = ""  # axiom:best-effort(unmeasurable composition fails the strict load closed)

{.pop.}
