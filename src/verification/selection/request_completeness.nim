import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## checkCompleteness — independent bidirectional completeness audit
##
## Implements BOTH directions with evidence-backed dispositions.
## Audit/tooling path only — does NOT self-certify.
##
## Strengthened: validates disposition `basis` against the actual
## trigger classification the disposition claims. A disposition whose
## basis label does not match the justification/evidence for that
## request is a completeness violation.
##
## See: canonical_execution_semantics.md §Appendix C
## Rule: deriveRequests must never certify its own completeness.

import std/[algorithm, sequtils, strutils, sets]
import core/types/request_id
import core/types/request_derivation_types
import core/orchestrator/orchestrator_types
import core/sorter/sorter_core

# ---------------------------------------------------------------------------
# Helper: check if a RequestId is in a seq
# ---------------------------------------------------------------------------

func containsReq*(items: seq[RequestId]; item: RequestId): bool {.raises: [].} =
  for x in items:
    if x == item:
      return true
  false

# ---------------------------------------------------------------------------
# Helper: set difference (a ∖ b) for seq[RequestId]
# ---------------------------------------------------------------------------

func diffReq*(a, b: seq[RequestId]): seq[RequestId] {.raises: [].} =
  for x in a:
    if not containsReq(b, x):
      result.add(x)

# ---------------------------------------------------------------------------
# Basis validation — strengthened check
# ---------------------------------------------------------------------------

func validateBasis*(d: Disposition): bool {.raises: [].} =
  ## A disposition's basis label must match the justification/evidence
  ## for that request. If the basis label does not match, this is a
  ## completeness violation.
  ##
  ## Rules:
  ## - dkFallback basis must be "fallback" or "budget"
  ## - dkSkip basis must be "eligibility", "oracle-gap", or "blocked_by"
  ## - evidence must be non-empty (already checked by checkCompleteness)
  ##
  ## blocked_by basis: valid only for dkSkip with non-empty evidence.
  ## Semantics: the request is blocked by a dependency-edge + failed-node
  ## execution evidence. Scheduler-level blocks (orchestrationBlocked with
  ## no failing dependency) must NOT use blocked_by — they remain
  ## uncompleted.
  case d.kind
  of dkFallback:
    d.basis in ["fallback", "budget"]
  of dkSkip:
    if d.basis notin ["eligibility", "oracle-gap", "blocked_by"]:
      return false
    if d.basis == "blocked_by" and d.evidence.len == 0:
      return false
    true

# ---------------------------------------------------------------------------
# checkCompleteness — independent comparison (no self-certification)
# ---------------------------------------------------------------------------

func checkCompleteness*(
  required: seq[RequestId]
; derived: seq[RequestId]
; dispositions: seq[Disposition]
): CompletionCheck {.raises: [].} =
  ## Completeness check: compares REQUIRED (from independent oracle) against
  ## DERIVED + evidence-backed dispositions.
  ##
  ## NO self-certification: required comes from the independent oracle,
  ## NOT from deriveRequests.
  ##
  ## Missing = required ∖ (derived ∪ evidence-backed dispositions)
  ## Unauthorized = derived ∖ required (unless covered by a disposition)
  ##
  ## A disposition without evidence is treated as a Completeness violation
  ## (ok=false) — this is a hard rule per the task specification.
  ##
  ## Strengthened: a disposition whose basis label does not match the
  ## trigger classification it claims is also a completeness violation.

  # Validate dispositions: any disposition without evidence is a violation
  for d in dispositions:
    if d.evidence.len == 0:
      return CompletionCheck(ok: false, missing: @[], unauthorized: @[])

  # Validate disposition bases: basis must match the disposition kind
  for d in dispositions:
    if not validateBasis(d):
      return CompletionCheck(ok: false, missing: @[], unauthorized: @[])

  # Build set of covered requestIds from evidence-backed dispositions
  var covered: seq[RequestId] = @[]
  for d in dispositions:
    if d.evidence.len > 0:
      covered.add(d.requestId)

  # Missing: required but not derived and not covered by a disposition
  var missing: seq[RequestId] = @[]
  for r in required:
    if not containsReq(derived, r) and not containsReq(covered, r):
      missing.add(r)

  # Unauthorized: derived but not required and not covered by a disposition
  var unauthorized: seq[RequestId] = @[]
  for d in derived:
    if not containsReq(required, d) and not containsReq(covered, d):
      unauthorized.add(d)

  CompletionCheck(
    ok: missing.len == 0 and unauthorized.len == 0,
    missing: missing.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b))),
    unauthorized: unauthorized.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b))))

# ---------------------------------------------------------------------------
# Closure completeness evaluation
# ---------------------------------------------------------------------------

func evaluateClosureCompleteness*(
  required: seq[RequestId]
; completed: seq[RequestId]
; dispositions: seq[Disposition]
; nodeReports: seq[OrchestrationNodeReport]
): tuple[complete: bool, uncompleted: seq[RequestId]] {.raises: [].} =
  ## Evaluate whether the verification closure is complete.
  ##
  ## A required request is considered completed when:
  ## - Its node ended orchestrationVerified (hard truth),
  ## - orchestrationNoObligation (terminal — no obligation to verify), or
  ## - orchestrationInductiveValid (soft truth — counts as completed for
  ##   closure purposes, though kernel scope is not yet confirmed).
  ##
  ## A required request is covered by a disposition when validateBasis
  ## returns true for that disposition (evidence-backed, basis-consistent).
  ##
  ## Returns (complete=false, uncompleted=list) when any required request
  ## is neither completed nor dispositioned.

  # Build set of completed request IDs from node reports
  var completedIds: HashSet[string] = initHashSet[string]()
  for nr in nodeReports:
    case nr.status
    of orchestrationVerified, orchestrationNoObligation, orchestrationInductiveValid:
      completedIds.incl(sorterNodeIdString(nr.nodeId))
    else:
      discard

  # Build set of covered request IDs from evidence-backed dispositions
  var coveredIds: HashSet[string] = initHashSet[string]()
  for d in dispositions:
    if d.evidence.len > 0 and validateBasis(d):
      coveredIds.incl(string(d.requestId))

  # Find uncompleted required requests
  var uncompleted: seq[RequestId] = @[]
  for r in required:
    let rid = string(r)
    if rid notin completedIds and rid notin coveredIds:
      uncompleted.add(r)

  (complete: uncompleted.len == 0, uncompleted: uncompleted)

{.pop.}