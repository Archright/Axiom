import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## ASI Domain Types — Type-safe Architecture Stability Index metrics.
##
## Private field object pattern prevents casting bypass:
## - ASIRatio.val is NOT exported
## - Only initAsiRatio() factory can create valid instances
## - This makes illegal states (ASI > 1.0 or < 0.0) truly unrepresentable

import std/options
import core/contracts/spec_binding_macro

type
  ASIRatio* {.spec("SPEC-T1-ASIRATIO").} = object
    val: float  # Private field — module-internal only

# --- Safe Factory (only way to create ASIRatio) ---
func initAsiRatio*(raw: float): Option[ASIRatio] =
  ## Safely creates ASIRatio. Returns none if value out of [0.0, 1.0].
  if raw >= 0.0 and raw <= 1.0:
    some(ASIRatio(val: raw))
  else:
    none(ASIRatio)

# --- Module-internal default ---
func defaultAsiRatio*(): ASIRatio =
  ## Module-internal default. Use when ASI cannot be computed.
  ASIRatio(val: 0.0)

# --- Read-only accessor ---
func toFloat*(a: ASIRatio): float {.inline.} =
  ## Read-only access to the underlying value.
  a.val

# --- Operator overloading ---
func `$`*(a: ASIRatio): string {.inline.} = $a.val
func `<`*(a, b: ASIRatio): bool {.inline.} = a.val < b.val
func `<=`*(a, b: ASIRatio): bool {.inline.} = a.val <= b.val
func `==`*(a, b: ASIRatio): bool {.inline.} = a.val == b.val
func `!=`*(a, b: ASIRatio): bool {.inline.} = a.val != b.val
func `>`*(a, b: ASIRatio): bool {.inline.} = a.val > b.val
func `>=`*(a, b: ASIRatio): bool {.inline.} = a.val >= b.val

{.pop.}
