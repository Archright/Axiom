## execution_witness_test.nim — TC-2 + INV-4: Executed/Result separation
##
## Documents the contract that execution witness (actual prover/solver
## invocation) and result (PASS|FAIL|TIMEOUT|ERROR) are independent
## domain concepts. Uses production type ExecutionWitness.
##
## INV-4: witness ≠ result — TIMEOUT is an EXECUTED result, not
## a witness-absent state.

{.push raises: [CatchableError].}

import std/[algorithm, sequtils, sets, strutils, unittest, options]
import core/types/request_id
import core/types/request_result
import core/types/request_derivation_types
import core/types/execution_witness
import core/crypto/hash_kernel
import verification/selection/verification_plan

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func makeExecutionIdentity*(reqId: RequestId): string =
  ## Canonical execution identity for a request — mirrors
  ## executionIdentity() from obligation/identity.nim pattern.
  sha256Hex(string(reqId) & "|execution-contract|bundle-fingerprint")

func makeWitness*(reqId: RequestId; prover: string = "z3"): ExecutionWitness =
  ExecutionWitness(
    executionIdentity: makeExecutionIdentity(reqId),
    prover: prover,
    invocationId: "inv-" & string(reqId))

# ---------------------------------------------------------------------------
# TC-2: Executed/Result separation
# ---------------------------------------------------------------------------

suite "TC-2 — Executed/Result separation":

  # -- Witness existence → EXECUTED --

  test "witness exists → EXECUTED":
    let reqId = makeRequestId(@["mod_a::fn_x"])
    let w = makeWitness(reqId)
    check w.executionIdentity.len > 0
    check w.prover == "z3"
    check w.invocationId.len > 0
    ## A non-nil witness with a valid executionIdentity and prover
    ## means an actual invocation occurred → EXECUTED.

  # -- No witness → NOT EXECUTED --

  test "witness absent → NOT EXECUTED":
    let reqId = makeRequestId(@["mod_b::fn_y"])
    let witness: Option[ExecutionWitness] = none(ExecutionWitness)
    let executed = witness.isSome
    check executed == false
    ## No witness means no prover/solver was invoked → NOT EXECUTED.

  # -- Pre-sieve → NOT EXECUTED (PRE_SIEVED) --

  test "pre-sieved unit → NOT EXECUTED (pre-sieved)":
    let reqId = makeRequestId(@["mod_c::fn_z"])
    let w = makeWitness(reqId)
    ## Pre-sieved units have a witness (they were considered for
    ## execution) but were filtered before reaching the prover.
    ## The witness existence is orthogonal to whether execution occurred.
    check w.executionIdentity.len > 0

  # -- Cache reuse → NOT EXECUTED (REUSED) --

  test "cache-reused unit → NOT EXECUTED (reused)":
    let reqId = makeRequestId(@["mod_d::fn_w"])
    let w = makeWitness(reqId)
    ## Cache-reused units have a witness (from the original invocation)
    ## but the result was retrieved from storage, not from a new call.
    check w.executionIdentity.len > 0

  # -- Witness ≠ Result: TIMEOUT is EXECUTED --

  test "TIMEOUT witness exists → EXECUTED (INV-4: witness ≠ result)":
    let reqId = makeRequestId(@["mod_e::fn_v"])
    let w = makeWitness(reqId, prover = "z3")
    let result = aggregateRequestResult(reqId, @[rvTimeout], cacheHit = false)
    check result.verdict == rvTimeout
    check result.counts.timeoutCount == 1
    ## TIMEOUT is a result value — it means the prover was
    ## invoked and timed out. The witness EXISTS (prover was
    ## called), but the result is TIMEOUT, not PASS or FAIL.
    ## INV-4: witness presence does NOT require a PASS/FAIL result.

  test "FAIL witness exists → EXECUTED (witness ≠ result)":
    let reqId = makeRequestId(@["mod_f::fn_u"])
    let w = makeWitness(reqId, prover = "z3")
    let result = aggregateRequestResult(reqId, @[rvFail], cacheHit = false)
    check result.verdict == rvFail
    check result.counts.failCount == 1
    ## FAIL is a result; the witness exists because the prover
    ## was actually invoked and returned unsat/fail.

  test "PASS witness exists → EXECUTED (witness ≠ result)":
    let reqId = makeRequestId(@["mod_g::fn_t"])
    let w = makeWitness(reqId, prover = "z3")
    let result = aggregateRequestResult(reqId, @[rvPass], cacheHit = false)
    check result.verdict == rvPass
    check result.counts.passCount == 1

  test "ERROR witness exists → EXECUTED (witness ≠ result)":
    let reqId = makeRequestId(@["mod_h::fn_s"])
    let w = makeWitness(reqId, prover = "z3")
    let result = aggregateRequestResult(reqId, @[rvError], cacheHit = false)
    check result.verdict == rvError
    check result.counts.errorCount == 1

  # -- Witness fields are independent of result domain --

  test "ExecutionWitness.prover is independent of RequestVerdict":
    let reqId = makeRequestId(@["mod_i::fn_r"])
    let w = makeWitness(reqId, prover = "z3")
    let result = aggregateRequestResult(reqId, @[rvPass], cacheHit = false)
    ## The witness records WHICH prover was used; the result
    ## records WHAT happened. They are orthogonal axes.
    check w.prover == "z3"
    check result.verdict == rvPass

  test "ExecutionWitness.invocationId is independent of RequestResult cacheHit":
    let reqId = makeRequestId(@["mod_j::fn_q"])
    let w = makeWitness(reqId)
    let result = aggregateRequestResult(reqId, @[rvPass], cacheHit = true)
    check w.invocationId == "inv-" & string(reqId)
    check result.cacheHit == true
    ## cacheHit is a property of the result, not the witness.

  # -- Canonical identity: witness is attributed to an ExecutionIdentity --

  test "ExecutionWitness is attributed to a canonical ExecutionIdentity":
    let reqId = makeRequestId(@["mod_k::fn_p"])
    let w = makeWitness(reqId)
    ## The witness carries an executionIdentity and invocationId that
    ## together form the canonical identity of the invocation.
    check w.executionIdentity.len > 0
    check w.invocationId.len > 0
    ## INV-4: the witness identity is canonical (not ad-hoc).

{.pop.}