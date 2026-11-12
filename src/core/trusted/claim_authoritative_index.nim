import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/sets
import std/tables
import core/trusted/claim_store
import core/trusted/claim_authority
import core/trusted/assurance_profile

## Phase-5b — Claim-authoritative hydration.
##
## The forward direction: build a VerifiedSet index FROM a ClaimStore,
## enforcing the invariant s ∈ VerifiedSet ⇒ ∃ Claim(s, outcome=clProved).
## This does NOT touch the legacy certificate-based hydration path.

func buildVerifiedSetFromClaims*(store: ClaimStore): HashSet[string] {.raises: [].} =
  ## Only claims with confirmed kernel checking (Lean acceptance) are
  ## counted as verified. Z3-only or candidate claims (kernelChecking=false)
  ## are excluded — they must NOT promote to VERIFIED through this path.
  for claim in store.claims.values:
    if claim.outcome == clProved and claim.assurance.kernelChecking:
      result.incl(claim.subjectId)

func isAuthoritativeSource*(subjectId: string; store: ClaimStore): bool {.raises: [].} =
  store.claims.hasKey(subjectId) and store.claims.getOrDefault(subjectId, VerifiedClaim()).outcome == clProved

{.pop.}