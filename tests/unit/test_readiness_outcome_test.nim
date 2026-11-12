import std/[json, unittest]
import ../../tools/readiness_evaluator
import core/utils/decision_algebra

## Continual revalidation §4 — ObservedState vs DecisionOutcome separation.
## UNKNOWN / NOT_RUN must NEVER be conflated with a confirmed contract FAIL,
## and an INFRA/UNRESOLVED must not auto-BLOCK the product (fail-closed but
## correctly classified). Representative cases only — no fault-injection.

proc criticalPolicy(): JsonNode =
  var inv = newJObject()
  for rid in ["R1", "R2", "R3", "R4", "R5", "R6", "R8"]:
    inv[rid] = %*{"criticality": "critical"}
  inv["R7"] = %*{"criticality": "non-critical"}
  %*{"invariants": inv}

suite "readiness outcome classification — observed state vs decision outcome":
  let pol = criticalPolicy()

  proc sts(pairs: openArray[(string, InvState)]): seq[tuple[id: string, state: InvState]] =
    for (id, s) in pairs: result.add((id, s))

  test "all PASS (incl. non-critical R7 FAIL = conditional) -> CONTINUE":
    let s = classifyOutcome(sts([
      ("R1", stPass), ("R2", stPass), ("R3", stPass), ("R4", stPass),
      ("R5", stPass), ("R6", stPass), ("R7", stFail),  # non-critical: not a blocker
      ("R8", stPass)]), pol)
    check s.outcome == "CONTINUE"
    check s.category == ""

  test "critical CONFIRMED FAIL -> BLOCK with failure category":
    check classifyOutcome(sts([("R1", stFail)]), pol) == ("BLOCK", "CONTRACT_FAIL")
    check classifyOutcome(sts([("R4", stFail)]), pol) == ("BLOCK", "EVIDENCE_FAIL")
    check classifyOutcome(sts([("R6", stFail)]), pol) == ("BLOCK", "PROVENANCE_FAIL")

  test "UNKNOWN / NOT_RUN on critical -> UNRESOLVED, never a confirmed BLOCK":
    let u = classifyOutcome(sts([("R3", stUnknown)]), pol)
    check u == ("UNRESOLVED", "UNKNOWN")
    check u.outcome != "BLOCK"          # structural: UNKNOWN ≠ FAIL ≠ BLOCK
    let n = classifyOutcome(sts([("R8", stNotRun)]), pol)
    check n == ("UNRESOLVED", "UNKNOWN")
    check n.outcome != "BLOCK"

  test "UNKNOWN on non-critical R7 -> CONTINUE (maturity, not a blocker)":
    let s = classifyOutcome(sts([("R7", stUnknown)]), pol)
    check s.outcome == "CONTINUE"

## §3 unification — one state mapping, one verdict per fact. Verdict and
## outcome are two axes of ONE decision, so a critical invariant can no longer
## be reported NO-GO by one path and UNRESOLVED as a competing verdict by
## another. See src/core/utils/decision_algebra.nim.

suite "decision algebra — single authority (core/utils/decision_algebra)":
  let pol = criticalPolicy()

  proc sts(pairs: openArray[(string, InvState)]): seq[tuple[id: string, state: InvState]] =
    for (id, s) in pairs: result.add((id, s))

  proc candidate(pairs: openArray[(string, InvState)]): DecisionCandidate =
    for (id, s) in pairs:
      result.invariants.add(InvariantStatus(
        id: id, state: s, critical: id != "R7",
        failureDomain: (if id == "R4": "EVIDENCE_FAIL" else: "CONTRACT_FAIL")))

  test "critical UNKNOWN -> ONE verdict (NO-GO) on both public paths":
    ## §3 table: NO-GO ⟺ ∃ critical ∈ {FAIL, UNKNOWN}. §4: UNKNOWN is never
    ## promoted to PASS, so the verdict can never be GO or CONDITIONAL GO.
    for st in [stUnknown, stNotRun]:
      let (v, conds) = verdictFromStates(sts([("R3", st)]), pol)
      let o = classifyOutcome(sts([("R3", st)]), pol)
      check v == "NO-GO"
      check conds.len == 0
      check o.outcome == "UNRESOLVED"
      check o.category == "UNKNOWN"
      check v != "GO" and v != "CONDITIONAL GO"

  test "critical FAIL and critical UNKNOWN never disagree on the verdict":
    ## The defect being removed: the same input reached both mappings and each
    ## produced its own verdict for one fact.
    let (vFail, _) = verdictFromStates(sts([("R4", stFail)]), pol)
    let (vUnknown, _) = verdictFromStates(sts([("R4", stUnknown)]), pol)
    let (vNotRun, _) = verdictFromStates(sts([("R4", stNotRun)]), pol)
    check vFail == vUnknown
    check vUnknown == vNotRun
    check vFail == "NO-GO"

  test "confirmed FAIL outranks UNKNOWN on the outcome axis":
    let o = classifyOutcome(sts([("R3", stUnknown), ("R4", stFail)]), pol)
    check o.outcome == "BLOCK"
    check o.category == "EVIDENCE_FAIL"
    check verdictFromStates(sts([("R3", stUnknown), ("R4", stFail)]), pol).verdict == "NO-GO"

  test "Decide reproduces the §3 verdict, outcome and conditions":
    let d = Decide(candidate([
        ("R1", stPass), ("R2", stPass), ("R3", stPass), ("R4", stPass),
        ("R5", stPass), ("R6", stPass), ("R7", stFail), ("R8", stPass)]),
      DecisionEvidence(schemaVersion: 1, digest: "ev"),
      ExecutionContract(contractId: "policy-1"))
    check d.verdict == "CONDITIONAL GO"
    check d.conditions == @["R7=FAIL"]
    check d.outcome == "CONTINUE"
    check d.failureCategory == ""
    check d.decisionDigest.len == 64

  test "Decide on a critical UNKNOWN agrees with the projected evaluator":
    let d = Decide(candidate([("R3", stUnknown)]),
      DecisionEvidence(schemaVersion: 1, digest: "ev"),
      ExecutionContract(contractId: "policy-1"))
    check d.verdict == "NO-GO"
    check d.outcome == "UNRESOLVED"
    check d.failureCategory == "UNKNOWN"
    check d.verdict == verdictFromStates(sts([("R3", stUnknown)]), pol).verdict
    check d.outcome == classifyOutcome(sts([("R3", stUnknown)]), pol).outcome

  test "Decide is deterministic — same inputs, same decisionDigest":
    let c = candidate([("R1", stPass), ("R2", stUnknown), ("R7", stFail)])
    let a = Decide(c, DecisionEvidence(schemaVersion: 1, digest: "ev"),
                   ExecutionContract(contractId: "policy-1"))
    let b = Decide(c, DecisionEvidence(schemaVersion: 1, digest: "ev"),
                   ExecutionContract(contractId: "policy-1"))
    check a.decisionDigest == b.decisionDigest
    check a == b
    check a.verdict == "NO-GO"

  test "decision is current only for the execution contract it was taken under":
    let taken = ExecutionContract(contractId: "policy-1")
    let d = Decide(candidate([("R1", stPass)]),
      DecisionEvidence(schemaVersion: 1, digest: "ev"), taken)
    check d.isCurrent(taken)
    check not d.isCurrent(ExecutionContract(contractId: "policy-2"))

## The run-exit rule — one function, two thin consumers (`axProofShortcutExitCode`
## in cli/wf_runners.nim, `computeReportExitCode` in verification/report_engine).
## A timeout is a hang-guard node abort, not a verification verdict; the decision
## is fail-closed about it anyway, and the exit axis is coarser still.

func runReport(summary: JsonNode): JsonNode = %*{"summary": summary}

suite "run-exit rule — single projection (decision_algebra.projectRunOutcome)":

  test "CONTINUE — verified>0 and no failed, no timed-out node":
    check projectRunOutcome(runReport(%*{"verified": 5, "failedCount": 0, "timeoutCount": 0})) ==
      OutcomeContinue

  test "CONTINUE — empty (no-obligation) run establishes nothing to fail":
    ## §7 makes `verified == 0` a failure only together with a failed or
    ## timed-out node; with neither, the run is CONTINUE.
    check projectRunOutcome(runReport(%*{"verified": 0, "failedCount": 0, "timeoutCount": 0})) ==
      OutcomeContinue

  test "CONTINUE — topology-only preview (no verified key) is outside the rule":
    check projectRunOutcome(runReport(%*{"topologyScanComplete": true, "symbolCount": 4})) ==
      OutcomeContinue

  test "BLOCK — at least one failed node, whatever else was verified":
    check projectRunOutcome(runReport(%*{"verified": 7, "failedCount": 1, "timeoutCount": 0})) ==
      OutcomeBlock
    check projectRunOutcome(runReport(%*{"verified": 0, "failedCount": 3, "timeoutCount": 0})) ==
      OutcomeBlock

  test "BLOCK — nothing verified and the run was aborted":
    check projectRunOutcome(runReport(%*{"verified": 0, "failedCount": 0, "timeoutCount": 1})) ==
      OutcomeBlock

  test "UNRESOLVED — timeout-only run: incomplete, not a confirmed failure":
    ## The hole the unification closes: this used to exit 0 on the prove path.
    check projectRunOutcome(runReport(%*{"verified": 2, "failedCount": 0, "timeoutCount": 1})) ==
      OutcomeUnresolved
    check projectRunOutcome(runReport(%*{"verified": 9, "failedCount": 0, "timeoutCount": 4})) ==
      OutcomeUnresolved

  test "UNRESOLVED — a summary that cannot be read (fail-closed)":
    check projectRunOutcome(%*{}) == OutcomeUnresolved            # no summary
    check projectRunOutcome(newJNull()) == OutcomeUnresolved      # nil document
    check projectRunOutcome(runReport(%*{"verified": 4})) == OutcomeUnresolved  # counts absent
    check projectRunOutcome(runReport(%*{"verified": "4", "failedCount": 0,
                                         "timeoutCount": 0})) == OutcomeUnresolved
    check projectRunOutcome(runReport(%*{"verified": 4, "failedCount": "0",
                                         "timeoutCount": 0})) == OutcomeUnresolved

  test "pure — the same document always yields the same outcome":
    let n = runReport(%*{"verified": 2, "failedCount": 0, "timeoutCount": 1})
    check projectRunOutcome(n) == projectRunOutcome(n)

  test "one rule, two consumers — decision axis is finer than the exit axis":
    ## The decision keeps BLOCK vs UNRESOLVED; both project to exit 1.
    let failedRun = projectRunOutcome(runReport(%*{"verified": 0, "failedCount": 1, "timeoutCount": 0}))
    let abortedRun = projectRunOutcome(runReport(%*{"verified": 2, "failedCount": 0, "timeoutCount": 1}))
    check failedRun != abortedRun
    check failedRun == OutcomeBlock and abortedRun == OutcomeUnresolved
