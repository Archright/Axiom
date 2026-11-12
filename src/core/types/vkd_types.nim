{.push raises: [].}
## VKD Domain Types — Correctness-by-Construction for Verification Kernel Density.
##
## Private field object pattern prevents casting bypass:
## - VerifiedKernelRatio.val is NOT exported
## - Only initKernelRatio() factory can create valid instances
## - This makes illegal states (VKD > 100%) truly unrepresentable

import std/options
import std/strutils
import core/contracts/spec_binding_macro
import core/trusted/axiom_pragmas

type
  CurrentRunVerified* = distinct int
  TotalKernelCount* = distinct int

  # Private field object: val NOT exported -> external construction impossible
  VerifiedKernelRatio* {.spec("SPEC-T1-VKDRATIO").} = object
    val: float  # Private field -- module-internal only

  # VKD domain contract — raw integer counts only (SSOT, no fabricated ratios).
  # coverageRatio / vkdFixed4 are computed template getters, never stored fields,
  # preventing theater where a stale ratio outlives its counts.
  VkdMetrics* = object
    verifiedCount*: int
    totalCount*: int
    failed*: bool  ## Explicit FAIL sentinel: true when the scope lock was
                   ## missing/corrupt and failClosed=true prevented a degraded
                   ## empty-scope fallback (never silently zero out ASI).
    ogr*: float  ## OGR (Obligation Grounding Rate) — runtime-computed,
                  ## 0.0 when no runtime counters are available (additive).
    par*: float  ## PAR (Proof Attempt Rate) — runtime-computed,
                  ## 0.0 when no runtime counters are available (additive).

# --- Safe Factory (only way to create VerifiedKernelRatio) ---
func initKernelRatio*(verified, total: int): Option[VerifiedKernelRatio] =
  ## Safely creates VerifiedKernelRatio. Returns none if constraints violated.
  if total > 0 and verified <= total:
    some(VerifiedKernelRatio(val: verified.float / total.float))
  else:
    none(VerifiedKernelRatio)

# --- Safe unwrap for {.raises: [].} context ---
func getKernelRatioOr*(opt: Option[VerifiedKernelRatio]; default: VerifiedKernelRatio): VerifiedKernelRatio {.inline.} =
  ## Unwrap or return default. Does NOT raise — caller controls both paths.
  if opt.isSome:
    VerifiedKernelRatio(val: opt.get.val)
  else:
    default

# --- Module-internal default (prevents fallback bypass) ---
func defaultKernelRatio*(): VerifiedKernelRatio =
  ## Module-internal default. Use when kernel count is 0 (avoids division).
  VerifiedKernelRatio(val: 0.0)

# --- Read-only accessor ---
func toFloat*(r: VerifiedKernelRatio): float {.inline.} =
  ## Read-only access to the underlying value.
  r.val

# --- Operator overloading (manual, since object doesn't borrow) ---
func `$`*(r: VerifiedKernelRatio): string {.inline.} =
  $r.val

func `<`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val < b.val

func `<=`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val <= b.val

func `==`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val == b.val

func `!=`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val != b.val

func `>`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val > b.val

func `>=`*(a, b: VerifiedKernelRatio): bool {.inline.} =
  a.val >= b.val

# --- VkdMetrics domain contract ----------------------------------------------

template coverageRatio*(m: VkdMetrics): float =
  if m.totalCount == 0: 0.0 else: m.verifiedCount.float / m.totalCount.float

template vkdFixed4*(m: VkdMetrics): string =
  m.coverageRatio.formatFloat(ffDecimal, 4)

func computeVkd*(verified, total: int): VkdMetrics =
  ## Factory producing a VkdMetrics from raw integer counts.
  VkdMetrics(verifiedCount: verified, totalCount: total)

{.pop.}
