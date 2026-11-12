import core/trusted/layer_declaration

## The k-induction proof node reports what the solver answered.
##
## `buildKInductionFinalStateNode` projected `"proved"` from the ABSENCE of a
## counter-example. Absence is not evidence: an `unknown` answer, an unparsed
## stdout and a genuine discharge are indistinguishable to that test, so the
## weakest of them was published as the strongest (docs/adr/0017-trust-claim-authority.md;
## a recorded solver `unsat` is not a proof-checked proof —
## docs/spec/evidence_calculus.md I6).

import core/api/axiom_api_session_helpers
import core/types/domain_types
import core/types/solver_types
import std/[algorithm, json]
import std/options
import std/strutils

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

proc node(baseStatus, stepStatus: SolverStatus): JsonNode =
  ## No counter-example is ever supplied, so "absent" is the only thing these
  ## calls carry — the exact input that used to be enough to print `proved`.
  buildKInductionFinalStateNode(
    3, baseStatus, stepStatus,
    none(SolverCounterExample), none(SolverCounterExample), "base_s0", "step_s1")

const everyStatus = [
  solverSat, solverUnsat, solverUnknown,
  solverVacuousContradiction, solverTimeout
]

block:
  echo "=== 1. absence of a counter-example alone never yields `proved` ==="
  for baseStatus in everyStatus:
    for stepStatus in everyStatus:
      let discharged = baseStatus == solverUnsat and stepStatus == solverUnsat
      let hasCounterExample = baseStatus == solverSat or stepStatus == solverSat
      let expected =
        if hasCounterExample: "sat"
        elif discharged: "proved"
        else: "unknown"
      let observed = node(baseStatus, stepStatus)["status"].getStr()
      expect(observed == expected,
        "base=" & $baseStatus & " step=" & $stepStatus &
        " => " & observed & " (expected " & expected & ")")

block:
  echo "=== 2. the no-evidence case lands on the weakest honest state ==="
  expect(node(solverUnknown, solverUnknown)["status"].getStr() == "unknown",
    "two unknown answers are `unknown`, not a discharge")
  expect(node(solverVacuousContradiction, solverUnknown)["status"].getStr() == "unknown",
    "a vacuous-contradiction base is not a discharge of the property")
  expect(node(solverUnsat, solverUnknown)["status"].getStr() == "unknown",
    "one obligation answered and one silent is not a discharge")
  expect(node(solverUnsat, solverVacuousContradiction)["status"].getStr() == "unknown",
    "a vacuous-contradiction step is not a discharge")
  expect(node(solverTimeout, solverTimeout)["status"].getStr() == "unknown",
    "two timeouts are not a discharge")
  expect(node(solverUnknown, solverUnsat)["status"].getStr() == "unknown",
    "one silent and one answered is not a discharge")

block:
  echo "=== 3. only an observed base∧step `unsat` discharges ==="
  expect(node(solverUnsat, solverUnsat)["status"].getStr() == "proved",
    "base and step both observed unsat is the one discharge path")
  let discharged = node(solverUnsat, solverUnsat)
  expect(not discharged.hasKey("counterExample"),
    "a discharge carries no counter-example key")

block:
  echo "=== 4. a counter-example is reported as sat and still attached ==="
  let withCounterExample = buildKInductionFinalStateNode(
    3, solverSat, solverUnsat,
    some(SolverCounterExample(
      violatedProperty: "k_induction_base",
      trace: @[],
      bindings: @[SolverBinding(name: "step_s1", value: "0")])),
    none(SolverCounterExample), "base_s0", "step_s1")
  expect(withCounterExample["status"].getStr() == "sat",
    "a `sat` obligation reports sat even when the other one is unsat")
  expect(withCounterExample["counterExample"]["property"].getStr() == "k_induction_base",
    "the counter-example body survives the status derivation")
  expect(withCounterExample["counterExample"]["bindingName"].getStr() == "step_s1",
    "the preferred binding symbol is still selected")

block:
  echo "=== 5. the emitted vocabulary is closed ==="
  ## The node's status comes from two ⟨check_sat_response⟩ values, so the only
  ## strings it can emit are the three the standard fixes plus the conjunction
  ## the k-induction argument names. There is no path from a single response,
  ## and no fourth word that a future edit could leak in unnoticed.
  var emitted: seq[string] = @[]
  for baseStatus in everyStatus:
    for stepStatus in everyStatus:
      let value = node(baseStatus, stepStatus)["status"].getStr()
      if value notin emitted:
        emitted.add value
  emitted.sort()
  expect(emitted == @["proved", "sat", "unknown"],
    "the whole status matrix emits exactly: " & emitted.join(", "))
  var provedFrom: seq[string] = @[]
  for baseStatus in everyStatus:
    for stepStatus in everyStatus:
      if node(baseStatus, stepStatus)["status"].getStr() == "proved":
        provedFrom.add($baseStatus & "&" & $stepStatus)
  expect(provedFrom == @["solverUnsat&solverUnsat"],
    "`proved` is reachable from exactly one cell of the matrix: " &
    provedFrom.join(", "))

echo "=== ALL api_session k-induction status tests PASSED ==="