import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import core/axiom_pragmas

import std/tables
import std/options
import core/trusted/assurance_profile
import core/trusted/claim_authority

## ClaimStore — rich per-symbol claim records, parallel to VerifiedSet.
##
## Invariant: s ∈ VerifiedSet  ⇒  ∃ ClaimStore entry with outcome=clProved.
## The ClaimStore is a materialized per-symbol index (NOT a full event database).
## It is built at the same chokepoint as VerifiedSet and consumed by
## "rich" readers (evidence queries, audit, reporting).

type
  ClaimStore* = object
    ## Map from subjectId → VerifiedClaim.
    claims*: Table[string, VerifiedClaim]

func add*(store: var ClaimStore; claim: VerifiedClaim) {.raises: [].} =
  store.claims[claim.subjectId] = claim

func get*(store: ClaimStore; subjectId: string): Option[VerifiedClaim] {.raises: [], axiomDecision(id = "DECISION-0632", reason = "Lookup verified claim by subjectId with Option return type", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  if store.claims.hasKey(subjectId):
    some(store.claims.getOrDefault(subjectId, VerifiedClaim()))
  else:
    none(VerifiedClaim)

func contains*(store: ClaimStore; subjectId: string): bool {.raises: [].} =
  store.claims.hasKey(subjectId)

func verifiedMemberCount*(store: ClaimStore): int {.raises: [].} =
  var count = 0
  for claim in store.claims.values:
    if claim.outcome == clProved:
      inc count
  count

func outcomeFor*(store: ClaimStore; subjectId: string): Option[VerificationOutcomeRef] {.raises: [], axiomDecision(id = "DECISION-0633", reason = "Retrieve verification outcome for a subject by subjectId", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  if store.claims.hasKey(subjectId):
    some(store.claims.getOrDefault(subjectId, VerifiedClaim()).outcome)
  else:
    none(VerificationOutcomeRef)

{.pop.}