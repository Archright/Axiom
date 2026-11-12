import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/strutils
import core/crypto/hash_kernel

## SemanticProfileV1 — verified semantics contract for Axiom V1.
##
## Values below declare what the encoder ACTUALLY VERIFIES, not an
## aspirational encoder target. The former nominal declaration
## (truncation toward zero for all operands, checked overflow) overclaimed
## the verified domain; the Phase 2 "make the encoder conform to the
## nominal contract" direction is WITHDRAWN (DEBT#494, 2026-10-07) and the
## declarations were moved to the verified meaning instead. Machine
## semantics: docs/spec/semantic_profile_verified_semantics.md.
##
## V1 VERIFIED SEMANTICS:
##   signed int overflow:  spOverflowObligationDischarged (reachability NOT
##                         modeled; every obligation carries a no-overflow
##                         goal, so checked and wrapping arithmetic coincide
##                         in the verified domain)
##   division:              spDivCoincidentNonnegative (Nim `div` (trunc) ==
##                         Lean `/` (floor) only on the nonnegative domain;
##                         no claim for negative operands)
##   modulo (signed):       spModuloSigned — Nim `mod` == Lean `Int.emod` only
##                         on the nonnegative-dividend domain (same
##                         coincidence shape as division)
##   modulo (unsigned):     spModuloUnsigned (Nim `%%`)
##   shift:                 spShiftUnsupported (not guaranteed in V1)
##   float:                 spFloatUnsupported (not guaranteed in V1)
##   string:                spStringUnsupported (not guaranteed in V1)
##   uint:                  spUintWrapping (wrapping arithmetic)

type
  SemanticProfileOverflowMode* = enum
    spOverflowBounded    ## nominal only (NOT guaranteed in V1): checked overflow → OverflowDefect; V2+ encoder-conformance target
    spOverflowTrapping   ## V2+: trap on overflow
    spOverflowWrapping   ## V2+: wrap on overflow
    spOverflowObligationDischarged ## V1 VERIFIED: overflow reachability is not modeled; each obligation discharges it via a no-overflow goal, so checked and wrapping arithmetic coincide in the verified domain

  SemanticProfileDivisionMode* = enum
    spDivTruncTowardZero ## nominal only (NOT guaranteed in V1): Nim truncation toward zero for ALL operands; V2+ encoder-conformance target
    spDivCoincidentNonnegative ## V1 VERIFIED: Nim `div` (trunc) == Lean `/` (floor) on the nonnegative domain; no claim for negative operands

  SemanticProfileModuloMode* = enum
    spModuloSigned   ## V1: Nim `mod`, verified coincident with Lean `Int.emod` on the nonnegative-dividend domain (negative-dividend sign semantics NOT claimed)
    spModuloUnsigned ## V1: Nim `%%` (unsigned modulo)

  SemanticProfileShiftMode* = enum
    spShiftUnsupported ## V1: shift operations not guaranteed

  SemanticProfileFloatMode* = enum
    spFloatUnsupported ## V1: floating-point not guaranteed

  SemanticProfileStringMode* = enum
    spStringUnsupported ## V1: string operations not guaranteed

  SemanticProfileUintMode* = enum
    spUintWrapping ## V1: unsigned integer wrapping arithmetic

  SemanticProfileV1* = object
    target*: string          ## target architecture (e.g. "x86_64")
    intWidth*: int           ## signed integer width in bits
    uintWidth*: int          ## unsigned integer width in bits
    overflowMode*: SemanticProfileOverflowMode
    divisionMode*: SemanticProfileDivisionMode
    moduloMode*: SemanticProfileModuloMode
    shiftMode*: SemanticProfileShiftMode
    floatMode*: SemanticProfileFloatMode
    stringMode*: SemanticProfileStringMode
    uintMode*: SemanticProfileUintMode

func `$`*(profile: SemanticProfileV1): string {.raises: [].} =
  ## Canonical string representation for debugging and hashing.
  result = profile.target & "|" &
    $profile.intWidth & "|" &
    $profile.uintWidth & "|" &
    $ord(profile.overflowMode) & "|" &
    $ord(profile.divisionMode) & "|" &
    $ord(profile.moduloMode) & "|" &
    $ord(profile.shiftMode) & "|" &
    $ord(profile.floatMode) & "|" &
    $ord(profile.stringMode) & "|" &
    $ord(profile.uintMode)

func `==`*(a, b: SemanticProfileV1): bool {.raises: [].} =
  ## Structural equality for SemanticProfileV1.
  a.target == b.target and
    a.intWidth == b.intWidth and
    a.uintWidth == b.uintWidth and
    a.overflowMode == b.overflowMode and
    a.divisionMode == b.divisionMode and
    a.moduloMode == b.moduloMode and
    a.shiftMode == b.shiftMode and
    a.floatMode == b.floatMode and
    a.stringMode == b.stringMode and
    a.uintMode == b.uintMode

func canonicalForm*(profile: SemanticProfileV1): string {.raises: [].} =
  ## Deterministic canonical serialization for hashing.
  profile.`$`

func ProfileHash*(profile: SemanticProfileV1): string {.raises: [].} =
  ## Deterministic hex hash (SHA-256) of the canonical serialization.
  ## Uses the repo crypto kernel (same as core/trusted spec artifacts), so the
  ## same profile ALWAYS produces the same hash across platforms/versions.
  sha256Hex(profile.canonicalForm)

const GlobalSemanticProfileV1* = SemanticProfileV1(
  target: "x86_64",
  intWidth: 64,
  uintWidth: 64,
  overflowMode: spOverflowObligationDischarged,
  divisionMode: spDivCoincidentNonnegative,
  moduloMode: spModuloSigned,
  shiftMode: spShiftUnsupported,
  floatMode: spFloatUnsupported,
  stringMode: spStringUnsupported,
  uintMode: spUintWrapping,
)

const SemanticProfileV1Hash* = ProfileHash(GlobalSemanticProfileV1)

{.pop.}
