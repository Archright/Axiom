import std/[json, os, unittest]
import ../../src/core/proof/proof_integrity
import ../../src/core/types/vkd_types
import ../../src/cli/shared/proof_hydration
import ../../src/cli/shared/baseline_snapshot_core

# Phase 3 WS-C — SSOT VKD invariant test.
#
# Verifies that every VKD computation path is "kernel_symbols" (Set Membership)
# based and converges on the same honest dual-metric value:
#   rawKernelCoverage = verified / kernel_total         (|K|)
#   vkd               = verified / vksTotal (|VKS| = |K∖E|)
#
# Rationale: schema v3 verification_scope.lock distinguishes K (kernel_total=40),
# E (kernel_exempt_symbols=17), and VKS (vksTotal = K−E = 23).
# VKD = |VKS ∩ certGreen|.
#
# P0 (certGreen status-aliasing elimination): VKD admits ONLY genuinely
# dual-verified (Z3 ∧ Lean) certGreen certificates. The 5 formerly mislabeled
# certGreen certs were Z3-only and have been reclassified to certZ3Verified, so
# VKD is now 0 (no dual-verified kernel cert). verifiedFunctions reflects only
# evidence-derived certGreen certificates. The denominator stays |VKS| = 23.
#
# This test is a deliberate *SSOT fragmentation detector*: if any path deviates
# from the honest dual metric, the assert below fails, reporting fragmentation.

const
  StaticVaultDir = "src" / "verification" / "certificates"
  LockPath = "data" / "verification_scope.lock"
  CachePath = "logs" / "ax_proof_state.json"
  # Honest VKD: |deep-verified kernel symbols| / kernel_total.
  # Honest dual-metric snapshot (schema v3 lock): K=40, E=17, VKS=23.
  ExpectedKernelTotal = 40      # |K|                       (kernel_total)
  ExpectedExemptTotal = 17      # |E|                       (kernel_exempt_symbols)
  ExpectedProvableTotal = 23    # |VKS| = |K∖E|              (vksTotal)
  ExpectedVerified = 0          # |VKD| = |VKS ∩ certGreen| (P0: dual-only)
  ExpectedRawVkdFixed4 = "0.0000"   # 0 / 40 (exportAsiFixed4 4dp)
  ExpectedProvableVkdFixed4 = "0.0000"  # 0 / 23

proc repoRoot(): string =
  ## Resolves the repository root at runtime (tests execute from the project root).
  getCurrentDir()

proc removeCache() =
  ## Remove the L1 cache so the canonical VKD read CANNOT depend on it. Post-#936
  ## the reader is journal-driven and never reads this cache, so the removal is
  ## a no-op for the metric — kept as a negative precondition: the canonical
  ## value must be identical whether or not the cache file exists.
  if fileExists(repoRoot() / CachePath):
    try:
      removeFile(repoRoot() / CachePath)
    except CatchableError:
      discard  # axiom:best-effort(optional cache cleanup)

suite "VKD SSOT Invariant (Phase 3 WS-C)":
  test "proof_integrity rooted in verification_scope.lock kernel_symbols":
    let scope = loadKernelScope(repoRoot() / LockPath)
    check scope.kernelTotal == ExpectedKernelTotal
    check scope.kernelSymbols.len == ExpectedKernelTotal
    check scope.kernelExemptSymbols.len == ExpectedExemptTotal
    check scope.vksTotal == ExpectedProvableTotal
    check scope.vksTotal == scope.kernelTotal - scope.kernelExemptSymbols.len

  test "baseline (computeBaselineSnapshot) is honest kernel_symbols based":
    let scope = loadKernelScope(repoRoot() / LockPath)
    let baseline = computeBaselineSnapshot(repoRoot() / StaticVaultDir, scope)
    # WS-B converged the baseline on kernel_symbols: numerator deep-verified kernel
    # symbols (5), denominator kernel_total (40) — no longer 219/220 = 0.9955.
    check baseline.verifiedFunctions == ExpectedVerified
    check baseline.totalFunctions == ExpectedKernelTotal
    check baseline.vkdFixed4 == ExpectedRawVkdFixed4
    # Dual-metric contract: kernelVerified is the SINGLE SSOT shared by both
    # VKD = |VKS ∩ certGreen| / |VKS|; rawKernelCoverage = |K ∩ certGreen| / |K|.
    check baseline.kernelTotal == ExpectedKernelTotal
    check baseline.kernelExemptTotal == ExpectedExemptTotal
    check baseline.vksTotal == ExpectedProvableTotal

  test "canonical getCanonicalVkdMetrics converges on honest VKS metric (SSOT detector)":
    removeCache()
    let canonical = getCanonicalVkdMetrics(repoRoot())
    # The canonical VKD denominator is vksTotal (|VKS| = 23), so the
    # VKD is 5/23. rawKernelCoverage (5/40) lives in baseline.
    check canonical.verifiedCount == ExpectedVerified
    check canonical.totalCount == ExpectedProvableTotal
