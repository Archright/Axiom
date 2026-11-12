## src/core/debt/debt_budget.nim — Budget/Metric Drift Classification
##
## Pure, I/O-free drift classification for MetricObservation values against
## their baseline references.  DriftKind outcomes are deterministic and
## documented per rule below.
##
## Key design: a drift observation is a DriftClaim, NOT an automatic Debt.
## Promotion from drift to debt requires a separate policy decision.
##
## Public API:
##   classifyDrift — classify a MetricObservation into a DriftKind
##   driftIsAutoDebt — always false (drift never auto-promotes to Debt)

import core/types/debt_types
import std/strutils

# ---------------------------------------------------------------------------
# classifyDrift
# ---------------------------------------------------------------------------

func classifyDrift*(
    metric: MetricObservation;
    definitionChanged, measurementChanged: bool
): DriftKind {.raises: [].} =
  ## Classify a MetricObservation into a DriftKind deterministically.
  ##
  ## Rules (evaluated in priority order; first match wins):
  ##
  ##   1. metric.value == metric.baselineRef  →  driftMatch
  ##      The current measurement exactly matches the established baseline.
  ##
  ##   2. definitionChanged == true  →  driftDefinition
  ##      The metric's definition hash differs from the prior definition.
  ##      This supersedes all other drift kinds because a definitional change
  ##      invalidates the meaning of both value and baseline.
  ##
  ##   3. measurementChanged == true (and definitionChanged == false)  →  driftMeasurement
  ##      The measurement method hash differs from the prior method.
  ##      The value may be accurate under the new method but is incomparable
  ##      to the old baseline.
  ##
  ##   4. metric.value != metric.baselineRef (no definition or measurement
  ##      change)  →  driftBaseline
  ##      The current value diverges from the baseline while the definition
  ##      and measurement method remain unchanged.  This indicates a genuine
  ##      shift in the metric's behaviour.
  ##
  ##   5. driftStaleBudget  —  reserved for budgets whose baseline reference
  ##      itself is known to be outdated (e.g., the budget has not been
  ##      reviewed within the staleness window).  This function does not
  ##      detect staleness automatically; callers should use driftBaseline
  ##      and annotate the metric's scope or toolchainContext with a
  ##      staleness marker when the baseline is stale.  The driftStaleBudget
  ##      kind is provided for explicit manual classification when the
  ##      baseline is known to be stale.
  ##
  ##   6. driftUnverified  —  fallback for any case not covered above
  ##      (should not be reachable with the rules above, but provided as a
  ##      safety net).

  if metric.value == metric.baselineRef:
    return driftMatch

  if definitionChanged:
    return driftDefinition

  if measurementChanged:
    return driftMeasurement

  # value != baselineRef and no definition/measurement change
  return driftBaseline

# ---------------------------------------------------------------------------
# driftIsAutoDebt
# ---------------------------------------------------------------------------

func driftIsAutoDebt*(d: DriftKind): bool {.raises: [].} =
  ## Determine whether a DriftKind automatically constitutes a Debt.
  ##
  ## Policy: drift is a measurement claim, not a debt assertion.  Every
  ## drift must pass through a separate policy gate before it can be
  ## promoted to a Debt entry.  This function always returns false.
  ##
  ## Rationale: automatic debt promotion from drift would bypass the
  ## evidence-first verification workflow.  A drift indicates a change
  ## in measurement or baseline; whether that change constitutes a
  ## problem (debt) is a policy decision, not a measurement result.

  false
