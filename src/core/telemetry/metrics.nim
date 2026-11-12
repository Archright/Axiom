import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options
import std/strutils
import core/types/domain_types
import core/types/asi_types
import core/metrics
export metrics
import core/axiom_pragmas

## ASI SSOT (Single Source of Truth) — Calculated-Property Metrics
##
## All Architecture Stability Index calculations MUST flow through this module.
## No ad-hoc ASI math in CLI, TUI, or API layers. One formula, one denominator.

type
  AsiUniverse* = object
    ## Immutable denominator for ASI calculation.
    ## Derived from static source graph analysis (countSourceFunctions).
    ## Must be populated once per session; never recomputed ad-hoc.
    totalFunctions*: int

type
  UniverseScope* = enum
    usTotalSource    ## 전체 소스 코드 유니버스 (테스트 전용, 기본 500)
    usKernelDomain   ## 도메인 커널 함수 범위 (기본 10)

const TotalSourceThreshold* = 500
  ## Minimum source functions for the full-source-scope universe.
  ## Test-only: certificate-only counts (e.g. 299) must not satisfy this.

const KernelDomainThreshold* = 10
  ## Minimum expected source functions in the domain kernel scope.
  ## Universe totals below this trigger panic (corrupted denominator guard).

func asString*(asi: ValidatedAsi): string {.inline, raises: [], noSideEffect.} =
  ## Extract the raw string for JSON/lock serialization.
  result = string(asi)

func exportAsiFixed4*(score: ASIRatio): ValidatedAsi {.raises: [], noSideEffect.} =
  ## Canonical ASI-to-string formatter. Takes ASIRatio Smart Type.
  ## Returns ValidatedAsi to enforce SSOT pipeline at compile time.
  ## Fixed4: 4-decimal fixed-point rendering (e.g. "0.1596", "1.0000").
  result = ValidatedAsi(formatFloat(score.toFloat, ffDecimal, 4))

func validateUniverse*(count: int; scope: UniverseScope): bool {.raises: [], noSideEffect.} =
  ## Panic-level guard: corrupted denominator detection (scope-aware).
  ## If totalFunctions is below the scope threshold, the source graph was not
  ## scanned correctly or certificate-only count was used (277 instead of 2414).
  case scope
  of usTotalSource:
    count >= TotalSourceThreshold
  of usKernelDomain:
    count >= KernelDomainThreshold

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
func computeRetryPenalty*(avgRetryCount: float): ASIRatio {.raises: [], axiom.} =
  ## Retry penalty floors at 0, caps at 0.95 to avoid zeroing the score.
  let raw = min(avgRetryCount / 5.0, 0.95)
  initAsiRatio(raw).get(defaultAsiRatio())

func computeInformationGainWeightedAsi*(
  certificates: seq[FunctionCertificate];
  universe: AsiUniverse;
  avgRetryCount: float
): ASIRatio {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (and (>= universe_totalFunctions -9223372036854775808) (<= universe_totalFunctions 9223372036854775807))))
  ## axiom-lean: certificates.size ≥ 0 ∧ universe_totalFunctions ≥ -9223372036854775808 ∧ universe_totalFunctions ≤ 9223372036854775807
  ## Canonical SSOT formula for Architecture Stability Index.
  ## Returns ASIRatio Smart Type — mathematically guaranteed [0.0, 1.0].
  var verifiedWeight = 0.0
  var totalWeight = 0.0
  for cert in certificates:
    let ig = max(0.0, cert.informationGain.toFloat)
    let weight = if ig > 0.0: ig else: 1.0
    totalWeight += weight
    if cert.status == certVerifiedAxiom:
      verifiedWeight += weight
  let missingCount = max(0, universe.totalFunctions - certificates.len)
  totalWeight += missingCount.float * 1.0
  if totalWeight <= 0.0:
    return defaultAsiRatio()
  let coverage = verifiedWeight / totalWeight
  let penalty = computeRetryPenalty(avgRetryCount)
  let rawResult = max(0.0, min(1.0, coverage - penalty.toFloat))
  let opt = initAsiRatio(rawResult)
  if opt.isSome: opt.get else: defaultAsiRatio()

{.pop.} # noSideEffect

{.pop.} # raises: []
