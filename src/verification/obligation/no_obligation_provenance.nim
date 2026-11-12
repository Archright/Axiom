import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## NoObligationProvenance — audit trail for "no obligation applies".
##
## When a semantic target has no applicable obligations, this type records
## WHY — making the absence of obligations a "proven classification" rather
## than an unexplained gap.  The plan §1.1 specifies:
##   - applicableClasses: always empty (no classes are applicable)
##   - excludedClasses: which classes were considered and excluded
##   - derivationRule: reference to the rule that determined exclusion
##   - semanticFacts: machine-readable facts supporting the decision

import std/[sequtils, strutils]
import verification/obligation/obligation_types

type
  NoObligationProvenance* = object
    applicableClasses*: seq[ObligationKind]
      ## Always empty — if any class applied, we'd be in ogrGenerated.
      ## The constructor enforces this invariant.
    excludedClasses*: seq[ObligationKind]
      ## Classes that were considered but found not applicable.
    derivationRule*: string
      ## Reference to the derivation rule / policy document ID.
    semanticFacts*: seq[string]
      ## Machine-readable facts supporting the exclusion decision.

func makeNoApplicableProvenance*(
  excludedClasses: seq[ObligationKind],
  derivationRule: string,
  semanticFacts: seq[string]
): NoObligationProvenance {.raises: [].} =
  ## Constructor that enforces applicableClasses == @[] invariant.
  doAssert excludedClasses.len > 0 or semanticFacts.len > 0,
    "NoObligationProvenance requires at least one excluded class or semantic fact"
  result = NoObligationProvenance(
    applicableClasses: @[],
    excludedClasses: excludedClasses,
    derivationRule: derivationRule,
    semanticFacts: semanticFacts
  )

{.pop.}
