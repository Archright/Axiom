## report_engine_test.nim — computeReportExitCode contract tests
##
## Tests for src/verification/report_engine.nim:
##   - All-no-obligation (verified=0, failedCount=0, timeoutCount=0) → exit 0
##   - A failure present (failedCount>0) → nonzero
##   - A timeout present (timeoutCount>0) → nonzero
##   - Missing/absent summary → fail-closed (exit 1)
##   - Verified with no failures → exit 0
##
## Read-time identity re-validation (execution_accounting_contract.md §15.3 and
## §17.1) — the pure half of `loadReportProofState`:
##   - an UNMEASURABLE current context reports every condition and establishes
##     nothing;
##   - the deciding case: a state that REUSED NOTHING (demoted == 0) whose
##     envelope cannot be bound still loses its PASS. No reused-vs-fresh fixture
##     can reach it, because they all presuppose a reuseRecord;
##   - the same state under a MATCHING envelope is established and is not
##     degraded at all (regression guard for the VDA routing);
##   - a REUSED-sourced state under a broken envelope is demoted to PENDING and
##     reads INCONCLUSIVE — never FAIL, which stays proof-level only (§17 rule 1);
##   - §17 rule 3 stays reachable on the read path: nothing attempted + recorded
##     blocked nodes → BLOCKED.

{.push raises: [CatchableError].}

import std/json
import std/unittest

import verification/report_engine
import verification/accounting/run_accounting
import verification/obligation/verification_decision_authority

# ---------------------------------------------------------------------------
# Helper: build a minimal proof-state JSON with a summary
# ---------------------------------------------------------------------------

func makeState*(summary: JsonNode): JsonNode =
  %*{"summary": summary}

# ---------------------------------------------------------------------------
# Suite: computeReportExitCode
# ---------------------------------------------------------------------------

suite "computeReportExitCode":

  test "all-no-obligation (verified=0, failedCount=0, timeoutCount=0) → exit 0":
    let state = makeState(%*{
      "verified": 0,
      "failedCount": 0,
      "timeoutCount": 0})
    check computeReportExitCode(state) == 0

  test "verified nodes with no failures → exit 0":
    let state = makeState(%*{
      "verified": 5,
      "failedCount": 0,
      "timeoutCount": 0})
    check computeReportExitCode(state) == 0

  test "a failure present (failedCount>0) → nonzero":
    let state = makeState(%*{
      "verified": 0,
      "failedCount": 2,
      "timeoutCount": 0})
    check computeReportExitCode(state) != 0

  test "a timeout present (timeoutCount>0) → nonzero":
    let state = makeState(%*{
      "verified": 0,
      "failedCount": 0,
      "timeoutCount": 1})
    check computeReportExitCode(state) != 0

  test "timeout-only run (verified>0) → nonzero — one rule with prove":
    ## The hang-guard abort is not a verification verdict, but incomplete
    ## verification is fail-closed on the exit axis (same rule as
    ## decision_algebra.projectRunOutcome, which axProofShortcutExitCode uses).
    let state = makeState(%*{
      "verified": 5,
      "failedCount": 0,
      "timeoutCount": 1})
    check computeReportExitCode(state) == 1

  test "both failure and timeout → nonzero":
    let state = makeState(%*{
      "verified": 0,
      "failedCount": 1,
      "timeoutCount": 1})
    check computeReportExitCode(state) != 0

  test "missing summary → fail-closed (exit 1)":
    let state = %*{}
    check computeReportExitCode(state) == 1

  test "nil summary → fail-closed (exit 1)":
    let state = newJNull()
    check computeReportExitCode(state) == 1

  test "absent failedCount and timeoutCount → fail-closed (exit 1)":
    let state = makeState(%*{"verified": 0})
    check computeReportExitCode(state) == 1

# ---------------------------------------------------------------------------
# Read-time re-validation fixtures (§15.3 / §17.1)
# ---------------------------------------------------------------------------
## The context values below are opaque identities — only their EQUALITY matters
## to the re-validation, so they are written as fixed 64-hex digests rather
## than measured (measurement would make the fixture environment-dependent).

const
  BundleFpCurrent = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  BundleFpStale = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  ConfigDigest = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  ExecutionEpoch = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  VerifierBuildIdCurrent = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  VerifierBuildIdStale = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  ToolchainId = "nim-2.2.10-linux-x86_64"

func currentCtx(): ReuseVerificationContext =
  ReuseVerificationContext(
    executionBundleFingerprint: BundleFpCurrent,
    executionConfigDigest: ConfigDigest,
    toolchainIdentity: ToolchainId,
    currentEpoch: ExecutionEpoch,
    verifierBuildId: VerifierBuildIdCurrent,
    platform: "linux-x86_64")

func staleEnvelope(): JsonNode =
  ## An envelope recorded under a DIFFERENT execution-bundle fingerprint (b) —
  ## a state that outlived the execution closure that produced it.
  var ctx = currentCtx()
  ctx.executionBundleFingerprint = BundleFpStale
  executionIdentityToJson(ctx)

func foreignVerifierBuildEnvelope(): JsonNode =
  ## An envelope recorded under a DIFFERENT verifier build identity (e) —
  ## a state written by another engine build, whose verdicts are not
  ## evidence about the current context.
  var ctx = currentCtx()
  ctx.verifierBuildId = VerifierBuildIdStale
  executionIdentityToJson(ctx)

func unitRow(unitId: string; source: SatisfactionSource): JsonNode =
  %*{"unitId": unitId,
     "requirementDecision": $rdRequired,
     "verificationOutcome": $voSatisfied,
     "consistency": $csConsistent,
     "executionEvidence": (if source == ssReused: $eeNotAttempted else: $eeAttempted),
     "satisfactionSource": $source}

func runOutcomeBlock(verdict: RunVerdict; basis: RunVerdictBasis): JsonNode =
  %*{"planComplete": true,
     "executionComplete": true,
     "verificationComplete": true,
     "verdict": $verdict,
     "basis": $basis,
     "gateVerdict": (if verdict == vrPass: $gvPass else: $gvFail),
     "reuseConditions": []}

func freshOnlyState(envelope: JsonNode): JsonNode =
  ## Every REQUIRED unit was satisfied by a GENUINE fresh execution — the §17
  ## rule 7 shape (PASS basis PROVEN), and ZERO reused rows, so the demotion is
  ## silent here by construction. `envelope = nil` omits the envelope entirely.
  result = %*{
    "blockedNodes": [],
    "runAccounting": {
      "requiredCount": 2, "notRequiredCount": 0, "unresolvedDecisionCount": 0,
      "satisfiedCount": 2, "unsatisfiedCount": 0, "pendingCount": 0,
      "contestedCount": 0, "satisfiedByFresh": 2, "satisfiedByReused": 0,
      "preSievedCount": 0, "attemptedCount": 2, "notAttemptedCount": 0,
      "freshExecutionCount": 2, "executedCount": 2,
      "proofFailedCount": 0, "timeoutUnsatCount": 0,
      "reuseEligibleRowCount": 0, "reuseRejectedRowCount": 0,
      "units": [unitRow("mod::alpha", ssFresh), unitRow("mod::beta", ssFresh)],
      "anomalies": [], "derivations": []
    },
    "runOutcome": runOutcomeBlock(vrPass, rbProven)
  }
  if not envelope.isNil:
    result[executionIdentityKey] = envelope

func reusedOnlyState(envelope: JsonNode): JsonNode =
  ## Both REQUIRED units were satisfied by cache reuse — the §17 rule 8 shape
  ## (PASS basis REUSED), entirely demotable when the envelope does not bind.
  %*{
    executionIdentityKey: envelope,
    "blockedNodes": [],
    "runAccounting": {
      "requiredCount": 2, "notRequiredCount": 0, "unresolvedDecisionCount": 0,
      "satisfiedCount": 2, "unsatisfiedCount": 0, "pendingCount": 0,
      "contestedCount": 0, "satisfiedByFresh": 0, "satisfiedByReused": 2,
      "preSievedCount": 0, "attemptedCount": 0, "notAttemptedCount": 2,
      "freshExecutionCount": 0, "executedCount": 2,
      "proofFailedCount": 0, "timeoutUnsatCount": 0,
      "reuseEligibleRowCount": 2, "reuseRejectedRowCount": 0,
      "units": [unitRow("mod::alpha", ssReused), unitRow("mod::beta", ssReused)],
      "anomalies": [], "derivations": []
    },
    "runOutcome": runOutcomeBlock(vrPass, rbReused)
  }

func blockedState(envelope: JsonNode): JsonNode =
  ## Nothing was attempted and the run recorded blocked nodes (§17 rule 3).
  %*{
    executionIdentityKey: envelope,
    "blockedNodes": ["mod::alpha"],
    "runAccounting": {
      "requiredCount": 1, "notRequiredCount": 0, "unresolvedDecisionCount": 0,
      "satisfiedCount": 0, "unsatisfiedCount": 0, "pendingCount": 1,
      "contestedCount": 0, "satisfiedByFresh": 0, "satisfiedByReused": 0,
      "preSievedCount": 0, "attemptedCount": 0, "notAttemptedCount": 1,
      "freshExecutionCount": 0, "executedCount": 0,
      "proofFailedCount": 0, "timeoutUnsatCount": 0,
      "reuseEligibleRowCount": 0, "reuseRejectedRowCount": 0,
      "units": [%*{"unitId": "mod::alpha",
                   "requirementDecision": $rdRequired,
                   "verificationOutcome": $voPending,
                   "consistency": $csConsistent,
                   "executionEvidence": $eeNotAttempted,
                   "satisfactionSource": $ssNone}],
      "anomalies": [], "derivations": []
    },
    "runOutcome": %*{"planComplete": true, "executionComplete": false,
                     "verificationComplete": false, "verdict": $vrInconclusive,
                     "basis": $rbNone, "gateVerdict": $gvFail,
                     "reuseConditions": []}
  }

# ---------------------------------------------------------------------------
# Suite: read-time identity re-validation (§15.3)
# ---------------------------------------------------------------------------

suite "read-time identity re-validation (§15.3)":

  test "unmeasurable current context → every condition reported, established=false":
    ## An unmeasurable context is not a partial pass: (b), (c) and the (e)
    ## components are each reported, so a missing measurement is diagnosable
    ## rather than silent.
    let state = freshOnlyState(executionIdentityToJson(currentCtx()))
    let reval = revalidateRestoredStateIdentity(state, defaultReuseVerificationContext())
    check not reval.established
    check reval.reasons.len == 5
    check "no current execution-bundle fingerprint in context (b)" in reval.reasons
    check "no current execution-config digest in context (c)" in reval.reasons
    check "no current toolchain identity in context (e)" in reval.reasons
    check "no current execution epoch in context (e)" in reval.reasons
    check "no current verifier build identity in context (e)" in reval.reasons

  test "state carrying no execution identity envelope → established=false":
    let state = freshOnlyState(nil)
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    check reval.reasons.len == 1
    check "state carries no execution identity envelope — a restored state " &
      "cannot be bound to the current context" in reval.reasons

  test "envelope under a different execution bundle → (b) mismatch, established=false":
    let state = freshOnlyState(staleEnvelope())
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    check reval.reasons == @["execution-bundle fingerprint mismatch (b)"]

  test "matching envelope → established with no reasons":
    let state = freshOnlyState(executionIdentityToJson(currentCtx()))
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check reval.established
    check reval.reasons.len == 0

  test "envelope under a different verifier build → (e) mismatch, established=false":
    ## A state written by another engine build is not evidence about the
    ## current context even when every other identity component matches.
    let state = freshOnlyState(foreignVerifierBuildEnvelope())
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    check reval.reasons == @["verifier build identity mismatch (e)"]

  test "'unmeasured' verifier build in context → established=false, never self-matching":
    ## verifier_build_identity.md: an "unmeasured" identity must never compare
    ## equal to a recorded "unmeasured" — without this guard a vacuous run
    ## would establish itself.
    var ctx = currentCtx()
    ctx.verifierBuildId = "unmeasured"
    let state = freshOnlyState(executionIdentityToJson(ctx))
    let reval = revalidateRestoredStateIdentity(state, ctx)
    check not reval.established
    check reval.reasons == @["verifier build identity is 'unmeasured' in context (e)"]

# ---------------------------------------------------------------------------
# Suite: restored-state verdict — VDA owns the read path (§17.1)
# ---------------------------------------------------------------------------

suite "restored-state run verdict (VDA, §17.1 identity binding)":

  test "zero reused rows + envelope mismatch → INCONCLUSIVE; the recorded PASS does not survive":
    ## THE deciding case. `demoted == 0` says nothing about the identity: the
    ## demotion is silent because nothing was REUSED, and a state that outlived
    ## its execution closure still cannot assert a PASS. rule 7 is decided on
    ## BOUND state; the unbound reading of the same state is fail-closed.
    let state = freshOnlyState(staleEnvelope())
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    check demoteRestoredReusedUnits(state, reval) == 0
    let decided = evaluateRestoredStateRunOutcome(state, reval)
    check decided{"runOutcome"}{"verdict"}.getStr() == $vrInconclusive
    check decided{"runOutcome"}{"basis"}.getStr() == $rbNone
    check decided{"runOutcome"}{"gateVerdict"}.getStr() == $gvFail
    check decided{"runOutcome"}{"readTimeRevalidation"}{"established"}.getBool() == false
    check decided{"runOutcome"}{"readTimeRevalidation"}{"demotedReusedUnits"}.getInt() == 0
    # the fresh rows themselves are untouched — fail-closed happens at the
    # verdict axis, not by fabricating a PENDING the run never recorded
    check decided{"runOutcome"}{"verificationComplete"}.getBool()
    check decided{"runAccounting"}{"satisfiedByFresh"}.getInt() == 2

  test "zero reused rows + matching envelope → established and NOT degraded":
    ## The regression guard: the read path returns an established state
    ## untouched, so a genuinely current fresh run still reads exactly as it
    ## recorded. Every difference from the case above comes from the envelope.
    let state = freshOnlyState(executionIdentityToJson(currentCtx()))
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check reval.established
    check demoteRestoredReusedUnits(state, reval) == 0
    check state{"runOutcome"}{"verdict"}.getStr() == $vrPass
    check state{"runOutcome"}{"basis"}.getStr() == $rbProven
    check state{"runOutcome"}{"gateVerdict"}.getStr() == $gvPass
    check state{"runAccounting"}{"anomalies"}.len == 0
    check state{"runAccounting"}{"pendingCount"}.getInt() == 0

  test "reused rows + broken envelope → demoted to PENDING, INCONCLUSIVE (never FAIL)":
    let state = reusedOnlyState(staleEnvelope())
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    let decided = evaluateRestoredStateRunOutcome(state, reval)
    check decided{"runOutcome"}{"verdict"}.getStr() == $vrInconclusive
    check decided{"runOutcome"}{"gateVerdict"}.getStr() == $gvFail
    check decided{"runOutcome"}{"verificationComplete"}.getBool() == false
    check decided{"runOutcome"}{"readTimeRevalidation"}{"demotedReusedUnits"}.getInt() == 2
    # reducer counting invariants survive the demotion
    check decided{"runAccounting"}{"satisfiedCount"}.getInt() == 0
    check decided{"runAccounting"}{"satisfiedByReused"}.getInt() == 0
    check decided{"runAccounting"}{"pendingCount"}.getInt() == 2
    check decided{"runAccounting"}{"anomalies"}.len == 1
    let row = decided{"runAccounting"}{"units"}[0]
    check row{"verificationOutcome"}.getStr() == $voPending
    check row{"satisfactionSource"}.getStr() == $ssNone

  test "nothing attempted + recorded blocked nodes + broken envelope → BLOCKED":
    ## §17 rule 3 stays reachable on the read path — BLOCKED is decided by its
    ## own terms, not as a synonym for "the envelope did not bind".
    let state = blockedState(staleEnvelope())
    let reval = revalidateRestoredStateIdentity(state, currentCtx())
    check not reval.established
    let decided = evaluateRestoredStateRunOutcome(state, reval)
    check decided{"runOutcome"}{"verdict"}.getStr() == $vrBlocked
    check decided{"runOutcome"}{"basis"}.getStr() == $rbNone
    check decided{"runOutcome"}{"gateVerdict"}.getStr() == $gvFail

{.pop.}