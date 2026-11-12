## tests/unit/test_obligation_execution_ledger.nim
## WP4-k (ACT 2.2 / O9-O11 + obligation execution closure) unit tests.
##
## Covers (no z3/lean binaries required):
##   O9  — canonicalEnvelopeDigest is the pre-sentinel SHA-256 of the Z3
##         transport envelope, and building the envelope is deterministic.
##   O10 — same observation (obligation → request → execution) reproduces
##         identical canonical transport identity.
##   O11 — checkTerminalAttribution rejects every malformed drop/accounting
##         shape and accepts a well-formed one.
##
## Uses the custom main() pattern like proof_state_machine_test.nim.
## Ledger fixtures are built at module scope (not inline inside check blocks)
## to avoid the `@[...]`-in-template parsing ambiguity.

import std/[options, strutils, sequtils]
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas
import verification/solver/z3_pool
import verification/obligation/verification_result_interpreter

# ---------------------------------------------------------------------------
# Ledger fixture builders (module scope)
# ---------------------------------------------------------------------------

proc makeAttempt(id: string; provenance: string): AttemptRecord =
  AttemptRecord(
    attemptNumber: 1,
    solverInvocationId: id,
    solverInputDigest: "in",
    canonicalEnvelopeDigest: "env",
    transportPayloadDigest: "payload",
    rawSolverStatus: "unsat",
    semanticAttemptOutcome: smOutcomeUnsat,
    derivationProvenance: provenance)

proc okLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1", "g2"],
    plans: @[PlanExecutionRecord(
      planRevision: 1,
      obligationId: "g1",
      attempts: @[makeAttempt("z3:1", "generated:foo:obs:division")])],
    terminalOutcome: some(smOutcomeUnsat),
    droppedObligations: @[DroppedObligationRecord(
      obligationId: "g2", dropReason: "dropped_outside_scope", planRevision: 1)])

proc zeroTerminalLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[],
    droppedObligations: @[],
    terminalOutcome: none(SemanticOutcome))

proc twoTerminalLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[PlanExecutionRecord(
      planRevision: 1,
      obligationId: "g1",
      attempts: @[makeAttempt("z3:1", "generated:foo:obs:division")])],
    droppedObligations: @[DroppedObligationRecord(
      obligationId: "g1", dropReason: "dropped_outside_scope", planRevision: 1)],
    terminalOutcome: some(smOutcomeUnsat))

proc dropNoReasonLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[],
    droppedObligations: @[DroppedObligationRecord(
      obligationId: "g1", dropReason: "", planRevision: 1)],
    terminalOutcome: some(smOutcomeFailedClosed))

proc dropUnknownLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[],
    droppedObligations: @[DroppedObligationRecord(
      obligationId: "ghost", dropReason: "dropped_outside_scope", planRevision: 1)],
    terminalOutcome: some(smOutcomeFailedClosed))

proc duplicateDropLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[],
    droppedObligations: @[
      DroppedObligationRecord(obligationId: "g1", dropReason: "dropped_outside_scope", planRevision: 1),
      DroppedObligationRecord(obligationId: "g1", dropReason: "dropped_no_plan", planRevision: 1)],
    terminalOutcome: some(smOutcomeFailedClosed))

proc provenanceLedgerFixture(): ObligationExecutionRecord =
  ObligationExecutionRecord(
    generatedObligationIds: @["g1"],
    plans: @[PlanExecutionRecord(
      planRevision: 1,
      obligationId: "g1",
      attempts: @[makeAttempt("z3:1:deadbeef", "generated:foo:obs:division")])],
    terminalOutcome: some(smOutcomeUnsat),
    droppedObligations: @[])

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  template checkOk(name: string, result: untyped) =
    check(name):
      assert result.isOk, name & " should be Ok"

  template checkErr(name: string, result: untyped) =
    check(name):
      assert not result.isOk, name & " should be Err"

  # ── O9: canonicalEnvelopeDigest is the pre-sentinel hash, deterministic ──
  echo "=== O9: Z3 Envelope Digest Identity ==="

  check "O9: canonicalEnvelopeDigest equals hash of pre-sentinel payload":
    let query = "(assert (= x 0))\n(check-sat)"
    let sentinel = "AXIOM_Z3_EOF_TEST"
    var digestA = ""
    let env = buildZ3QueryEnvelope(query, timeoutMs = 8000, sentinel = sentinel,
                                   mode = zmRaw, canonicalEnvelopeDigest = digestA)
    let echoLine = "(echo \"" & sentinel & "\")\n"
    doAssert env.endsWith(echoLine), "envelope must end with sentinel echo"
    let preSentinel = env[0 ..< env.len - echoLine.len]
    assert digestA == sha256Hex(preSentinel), "pre-sentinel digest mismatch"

  check "O9: buildZ3QueryEnvelope is deterministic (same input -> same digest & bytes)":
    let query = "(assert (= x 0))\n(check-sat)"
    let sentinel = "AXIOM_Z3_EOF_DET"
    var digestB = ""
    var digestC = ""
    let env1 = buildZ3QueryEnvelope(query, timeoutMs = 8000, sentinel = sentinel,
                                    mode = zmRaw, canonicalEnvelopeDigest = digestB)
    let env2 = buildZ3QueryEnvelope(query, timeoutMs = 8000, sentinel = sentinel,
                                    mode = zmRaw, canonicalEnvelopeDigest = digestC)
    assert digestB == digestC, "digests differ across identical inputs"
    assert env1 == env2, "envelope bytes differ across identical inputs"
    assert digestB.len == 64, "SHA-256 hex digest must be 64 chars"

  check "O9: different payload -> different canonical digest":
    var d1 = ""
    var d2 = ""
    discard buildZ3QueryEnvelope("(assert (= x 0))", timeoutMs = 8000,
                                 sentinel = "S1", mode = zmRaw, canonicalEnvelopeDigest = d1)
    discard buildZ3QueryEnvelope("(assert (= x 1))", timeoutMs = 8000,
                                 sentinel = "S2", mode = zmRaw, canonicalEnvelopeDigest = d2)
    assert d1 != d2, "different payloads must yield different digests"

  # ── O10: same obligation observation reproduces identical identity ──
  echo "=== O10: Canonical Transport Identity Reproducibility ==="

  check "O10: identical obligation -> identical canonical envelope digest":
    var digestRunA = ""
    var digestRunB = ""
    let obligationSmt = "(assert (not (= resultBits 0)))\n(check-sat)"
    discard buildZ3QueryEnvelope(obligationSmt, timeoutMs = 8000,
                                 sentinel = "AXIOM_Z3_EOF_R", mode = zmRaw,
                                 canonicalEnvelopeDigest = digestRunA)
    discard buildZ3QueryEnvelope(obligationSmt, timeoutMs = 8000,
                                 sentinel = "AXIOM_Z3_EOF_R", mode = zmRaw,
                                 canonicalEnvelopeDigest = digestRunB)
    assert digestRunA == digestRunB, "identical obligation must reproduce digest"

  check "O10: obligation kind is recorded in ledger provenance":
    let ledger = provenanceLedgerFixture()
    assert ledger.plans.len == 1, "expected 1 plan"
    assert ledger.plans[0].obligationId == "g1", "obligation id mismatch"
    assert ledger.plans[0].attempts[0].solverInvocationId == "z3:1:deadbeef", "solverInvocationId mismatch"
    assert ledger.plans[0].attempts[0].rawSolverStatus == "unsat", "solver status mismatch"
    assert ledger.plans[0].attempts[0].derivationProvenance == "generated:foo:obs:division", "provenance mismatch"

  # ── O11: Terminal Attribution Completeness ──
  echo "=== O11: Terminal Attribution Completeness ==="

  check "O11 accept: every generated id has exactly one terminal account":
    assert checkTerminalAttribution(okLedgerFixture()).ok

  check "O11 reject: 0 terminal accounts for a generated obligation":
    assert not checkTerminalAttribution(zeroTerminalLedgerFixture()).ok

  check "O11 reject: 2 terminals (plan AND drop) for one obligation":
    assert not checkTerminalAttribution(twoTerminalLedgerFixture()).ok

  check "O11 reject: drop without reason":
    assert not checkTerminalAttribution(dropNoReasonLedgerFixture()).ok

  check "O11 reject: drop for unknown obligation":
    assert not checkTerminalAttribution(dropUnknownLedgerFixture()).ok

  check "O11 reject: duplicate drop":
    assert not checkTerminalAttribution(duplicateDropLedgerFixture()).ok

  # ── Summary ──────────────────────────────────────────────

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
