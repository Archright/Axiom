# NIMTRY TEST FIXTURE — intentionally violates SSOT (Single Source of Truth)
#
# This fixture defines the type `ValidatedAsi` which is owned by
# `src/core/metrics.nim` per the policy:
#   ssot_types: "ValidatedAsi" = "src/core/metrics.nim"
#
# Defining this type outside its canonical owner triggers
# the `ssot-type-placement` query.
#
# This fixture also attempts to assign to fields that are policy-owned,
# which would trigger `ssot-forbidden-assignments` if the file path
# matched the policy's forbidden_assignments patterns.

type
  ValidatedAsi* = object
    ## SSOT violation: this type is owned by src/core/metrics.nim
    score*: float
    label*: string
    timestamp*: int64

proc computeScore*(metrics: ValidatedAsi): float =
  ## Simulates a non-owner module that should not define ValidatedAsi.
  result = metrics.score
