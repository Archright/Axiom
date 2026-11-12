import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## ValidatedAsi — Canonical SSOT type for ASI (Architecture Stability Index).
##
## This type MUST live in src/core/metrics.nim per architecture_policy.lock.
## It is a distinct string that proves the ASI value was produced by the
## metrics.nim SSOT pipeline. Cannot be constructed from raw string literals
## outside the metrics module.

import std/json
import std/options
import core/types/asi_types
import core/types/vkd_types

type
  AsiSource* {.pure.} = enum
    asiComputed     ## 명식 계산 완료 — 0.0000 포함 모든 수치 허용
    asiInjected     ## 주입/기본값 — 0.0000 또는 빈 값 거부

  ValidatedAsi* = distinct string
    ## Type-level proof that an ASI string was produced by metrics.nim SSOT.
    ## Cannot be constructed from raw string literals outside this module.

# JSON serialization helpers for Smart Types
func `%`*(x: CurrentRunVerified): JsonNode = %(int(x))
proc `%`*(x: TotalKernelCount): JsonNode = %(int(x))
proc `%`*(x: ASIRatio): JsonNode = %(toFloat(x))
proc `%`*(x: VerifiedKernelRatio): JsonNode = %(toFloat(x))

# Safe division — returns Smart Type
func `/`*(num: CurrentRunVerified, den: TotalKernelCount): VerifiedKernelRatio =
  if int(den) <= 0:
    defaultKernelRatio()
  else:
    initKernelRatio(int(num), int(den)).get(defaultKernelRatio())

func computeVerified*(
  rawVerified: int;
  inductiveValid: int = 0;
  vacuous: int = 0;
  tautology: int = 0;
  includeInductiveValid: bool = true;
  includeDemotions: bool = true
): CurrentRunVerified =
  var count = rawVerified
  if includeInductiveValid:
    count += inductiveValid
  if includeDemotions:
    count -= (vacuous + tautology)
  result = CurrentRunVerified(max(0, count))

{.pop}
