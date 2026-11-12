import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## deriveRequests — policy-aware request derivation
##
## Signature: derives from (selectionSet, policy) → DerivationResult.
## Does NOT accept oracle outputs (no RequiredRequests param).
## Does NOT call checkCompleteness (audit lives in request_completeness.nim).
##
## See: canonical_execution_semantics.md §Appendix C
## Rule: deriveRequests must never certify its own completeness.

import std/[algorithm, sequtils, sets, strutils]
import core/types/request_id
import core/types/request_derivation_types

# ---------------------------------------------------------------------------
# deriveRequests — policy-aware derivation
# ---------------------------------------------------------------------------

func deriveRequests*(
  selectionSet: seq[string]
; policy: RequestPolicy
): DerivationResult {.raises: [].} =
  ## The ACTUAL derivation (policy: eligibility/budget/fallback).
  ## Returns requests + dispositions.
  ##
  ## Policy-unaware oracle (computeRequiredRequests) produces the
  ## EXPECTED set independently. deriveRequests produces the ACTUAL set
  ## based on policy. Completeness is the comparison between the two
  ## (lives in request_completeness.nim, not here).

  var requests: seq[RequestId] = @[]
  var dispositions: seq[Disposition] = @[]

  # Apply budget cap: if selectionSet exceeds budget, cap and add fallback dispositions
  var workingSet = selectionSet.sorted(cmp)
  if workingSet.len > policy.budgetCap and policy.budgetCap > 0:
    let excess = workingSet.len - policy.budgetCap
    for i in 0 ..< excess:
      let unitId = workingSet[^1]
      workingSet.delete(workingSet.len - 1)
      dispositions.add(Disposition(
        kind: dkFallback,
        requestId: makeRequestId(@[unitId]),
        evidence: "budget cap of " & $policy.budgetCap & " exceeded; " & unitId & " deferred to fallback",
        basis: "budget"))

  # Convert working set to RequestIds
  for unitId in workingSet:
    requests.add(makeRequestId(@[unitId]))

  DerivationResult(requests: requests, dispositions: dispositions)

{.pop.}