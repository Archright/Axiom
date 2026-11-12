import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## RequestResult — join-semilattice reducer for per-request verdicts
##
## Canonical location of the reducer (supVertex/Reduce) and the
## RequestResult aggregation (toRequestVerdict/aggregateRequestResult).
## See: canonical_execution_semantics.md §Appendix C.

import std/[sequtils, json, options, strutils]
import core/types/request_id
import core/types/proof_status

# ---------------------------------------------------------------------------
# RequestVerdict — ordered enum forming a join-semilattice
# ---------------------------------------------------------------------------

type
  RequestVerdict* = enum
    rvPass     ## pass (bottom element — identity for ⊔)
    rvFail     ## fail
    rvTimeout  ## timeout
    rvError    ## error (top element)

  ## Ordering: rvPass < rvFail < rvTimeout < rvError
  ## This gives a total order compatible with the semilattice join.

# ---------------------------------------------------------------------------
# supVertex — the join operation ⊔
# ---------------------------------------------------------------------------

func supVertex*(a, b: RequestVerdict): RequestVerdict {.raises: [].} =
  ## Join (⊔) of two RequestVerdicts.
  ## Returns the "worse" verdict per the ordering rvPass < rvFail < rvTimeout < rvError.
  if a >= b: a else: b

# ---------------------------------------------------------------------------
# Reduce — fold ⊔ over a sequence
# ---------------------------------------------------------------------------

func Reduce*(unitVerdicts: seq[RequestVerdict]): RequestVerdict {.raises: [].} =
  ## Fold ⊔ over unitVerdicts, starting at bottom=rvPass.
  ## Deterministic: same input list → same result regardless of internal ordering
  ## (because ⊔ is commutative, associative, idempotent).
  result = rvPass
  for v in unitVerdicts:
    result = supVertex(result, v)

# ---------------------------------------------------------------------------
# toRequestVerdict — canonical ProofStatus → verdict projection
# ---------------------------------------------------------------------------

func toRequestVerdict*(status: ProofStatus): RequestVerdict {.raises: [].} =
  ## Consistent with CertificateBatch counting (ir_pipeline_runner
  ## toCertificateBatch): verdict-level pass-equivalence for
  ## skip/vacuous-trivial/no-obligation, fail for vacuous-counter.
  case status
  of psPass, psVacuousTrivial, psSkip, psNoObligation: rvPass
  of psFail, psVacuousCounter: rvFail
  of psTimeout: rvTimeout
  of psError: rvError

# ---------------------------------------------------------------------------
# RequestResult — per-request verification result
# ---------------------------------------------------------------------------

type
  RequestResult* = object
    requestId*: RequestId
    verdict*: RequestVerdict
    cacheHit*: bool
    counts*: tuple[passCount: int, failCount: int, timeoutCount: int, errorCount: int]

# ---------------------------------------------------------------------------
# aggregateRequestResult — canonical per-request aggregation (⊔ UnitResults)
# ---------------------------------------------------------------------------

func aggregateRequestResult*(
  requestId: RequestId
; unitVerdicts: seq[RequestVerdict]
; cacheHit = false
): RequestResult {.raises: [].} =
  ## Canonical aggregation per confirmed semantics: verdict = ⊔ unitVerdicts
  ## (via Reduce), counts = pure tally of the input sequence.
  ## Order-independent: ⊔ is commutative/associative/idempotent and a tally is
  ## permutation-invariant, so UnitResult input order never changes the result.
  result = RequestResult(requestId: requestId, verdict: Reduce(unitVerdicts), cacheHit: cacheHit)
  for v in unitVerdicts:
    case v
    of rvPass: inc result.counts.passCount
    of rvFail: inc result.counts.failCount
    of rvTimeout: inc result.counts.timeoutCount
    of rvError: inc result.counts.errorCount

func aggregateFromProofStatuses*(
  requestId: RequestId
; statuses: seq[ProofStatus]
; cacheHit = false
): RequestResult {.raises: [].} =
  ## Convenience: maps unit ProofStatuses via toRequestVerdict, then aggregates.
  aggregateRequestResult(requestId, statuses.mapIt(toRequestVerdict(it)), cacheHit)

# ---------------------------------------------------------------------------
# JSON round-trip
# ---------------------------------------------------------------------------

func toJson*(hr: RequestResult): JsonNode {.raises: [].} =
  %*{
    "requestId": hr.requestId.toString(),
    "verdict": $hr.verdict,
    "cacheHit": hr.cacheHit,
    "counts": %*{
      "passCount": hr.counts.passCount,
      "failCount": hr.counts.failCount,
      "timeoutCount": hr.counts.timeoutCount,
      "errorCount": hr.counts.errorCount}}

func fromJsonResult*(node: JsonNode): Option[RequestResult] {.raises: [].} =
  if node.kind != JObject:
    return none(RequestResult)
  let reqIdNode = node{"requestId"}
  if reqIdNode.kind != JString:
    return none(RequestResult)
  let verdictNode = node{"verdict"}
  if verdictNode.kind != JString:
    return none(RequestResult)
  let verdict = try:
    parseEnum[RequestVerdict](verdictNode.getStr())
  except ValueError:
    return none(RequestResult)
  let cacheHit = node{"cacheHit"}.getBool(false)
  let countsNode = node{"counts"}
  let counts = if countsNode.kind == JObject:
    (passCount: countsNode{"passCount"}.getInt(0),
     failCount: countsNode{"failCount"}.getInt(0),
     timeoutCount: countsNode{"timeoutCount"}.getInt(0),
     errorCount: countsNode{"errorCount"}.getInt(0))
  else:
    (0, 0, 0, 0)
  some(RequestResult(
    requestId: RequestId(reqIdNode.getStr()),
    verdict: verdict,
    cacheHit: cacheHit,
    counts: counts))

{.pop.}
