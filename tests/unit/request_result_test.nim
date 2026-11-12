## request_result_test.nim — R3+P3 RequestResult canonical aggregation integrity
##
## Tests for src/core/types/request_result.nim:
##   - toRequestVerdict: exhaustive canonical ProofStatus → verdict projection
##   - aggregateRequestResult: lattice join, canonical counts, order-invariance
##   - aggregateFromProofStatuses: status-level convenience aggregation
##   - empty input → identity (rvPass) with zero counts

{.push raises: [CatchableError].}

import std/[sequtils, sets, options, unittest]
import core/types/request_id
import core/types/request_result
import core/types/proof_status

# ---------------------------------------------------------------------------
# toRequestVerdict — exhaustive canonical mapping
# ---------------------------------------------------------------------------

test "toRequestVerdict: pass-equivalent statuses → rvPass":
  for s in [psPass, psVacuousTrivial, psSkip, psNoObligation]:
    check toRequestVerdict(s) == rvPass

test "toRequestVerdict: fail-equivalent statuses → rvFail":
  check toRequestVerdict(psFail) == rvFail
  check toRequestVerdict(psVacuousCounter) == rvFail

test "toRequestVerdict: timeout → rvTimeout, error → rvError":
  check toRequestVerdict(psTimeout) == rvTimeout
  check toRequestVerdict(psError) == rvError

test "toRequestVerdict: exhaustive — every ProofStatus maps":
  # 8 enum values; ensure the case statement is total by exercising all.
  let statuses = [psPass, psFail, psTimeout, psSkip, psError,
                  psVacuousTrivial, psVacuousCounter, psNoObligation]
  check statuses.mapIt($toRequestVerdict(it)).len == 8

# ---------------------------------------------------------------------------
# aggregateRequestResult — lattice join + canonical counts
# ---------------------------------------------------------------------------

test "aggregateRequestResult: empty input → identity rvPass with zero counts":
  let r = aggregateRequestResult(makeRequestId(@["u1"]), @[])
  check r.verdict == rvPass
  check r.counts == (0, 0, 0, 0)
  check not r.cacheHit

test "aggregateRequestResult: single worst verdict dominates (join semantics)":
  let r = aggregateRequestResult(makeRequestId(@["u1"]),
    @[rvPass, rvFail, rvTimeout, rvError])
  check r.verdict == rvError          # ⊔ = worst element (top)
  check r.counts == (1, 1, 1, 1)

test "aggregateRequestResult: order-invariance — distinct input orderings":
  let base = @[rvPass, rvFail, rvTimeout, rvError]
  let expected = aggregateRequestResult(makeRequestId(@["u1"]), base)
  # Distinct reorderings of the same multiset must yield identical verdict+counts
  # (⊔ is commutative/associative/idempotent; tally is permutation-invariant).
  let reorderings = @[
    @[rvError, rvTimeout, rvFail, rvPass],
    @[rvFail, rvError, rvPass, rvTimeout],
    @[rvTimeout, rvPass, rvError, rvFail],
    @[rvFail, rvPass, rvTimeout, rvError],
    @[rvPass, rvTimeout, rvError, rvFail]]
  for perm in reorderings:
    let r = aggregateRequestResult(makeRequestId(@["u1"]), perm)
    check r.verdict == expected.verdict
    check r.counts == expected.counts

test "aggregateRequestResult: mixed pass/fail — verdict fail, counts canonical":
  let r = aggregateRequestResult(makeRequestId(@["u1"]),
    @[rvPass, rvFail, rvPass, rvPass])
  check r.verdict == rvFail
  check r.counts == (3, 1, 0, 0)

test "aggregateRequestResult: cacheHit flag preserved":
  let r = aggregateRequestResult(makeRequestId(@["u1"]), @[rvPass], cacheHit = true)
  check r.cacheHit

# ---------------------------------------------------------------------------
# aggregateFromProofStatuses — status-level convenience
# ---------------------------------------------------------------------------

test "aggregateFromProofStatuses: maps statuses then joins":
  let r = aggregateFromProofStatuses(makeRequestId(@["u1"]),
    @[psPass, psVacuousTrivial, psFail, psTimeout, psError, psSkip, psNoObligation])
  check r.verdict == rvError
  check r.counts == (4, 1, 1, 1)

test "aggregateFromProofStatuses: vacuous-counter counts as fail":
  let r = aggregateFromProofStatuses(makeRequestId(@["u1"]),
    @[psPass, psVacuousCounter])
  check r.verdict == rvFail
  check r.counts == (1, 1, 0, 0)

test "aggregateFromProofStatuses: order-invariance over statuses":
  let statuses = @[psError, psPass, psTimeout, psFail, psPass]
  let expected = aggregateFromProofStatuses(makeRequestId(@["u1"]), statuses)
  let reorderings = @[
    @[psPass, psError, psFail, psPass, psTimeout],
    @[psTimeout, psPass, psError, psPass, psFail],
    @[psFail, psPass, psTimeout, psError, psPass]]
  for perm in reorderings:
    let r = aggregateFromProofStatuses(makeRequestId(@["u1"]), perm)
    check r.verdict == expected.verdict
    check r.counts == expected.counts

# ---------------------------------------------------------------------------
# JSON round-trip
# ---------------------------------------------------------------------------

test "requestResult JSON round-trip preserves canonical fields":
  let r = aggregateRequestResult(makeRequestId(@["u1"]),
    @[rvPass, rvFail, rvTimeout, rvError])
  let node = r.toJson
  let back = fromJsonResult(node)
  check back.isSome
  check back.get().requestId == r.requestId
  check back.get().verdict == r.verdict
  check back.get().cacheHit == r.cacheHit
  check back.get().counts == r.counts

{.pop.}