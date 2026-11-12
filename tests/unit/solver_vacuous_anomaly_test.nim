import core/trusted/layer_declaration

## A solver response stream that contradicts itself must not discharge anything.
##
## `runZ3Proof` mapped the parser's answer straight onto `psProven`, so a stdout
## carrying `unsat` and then `sat` counted as a proof of the contract. The
## removal of the old `solverVacuousContradiction` branch was right — that
## anomaly was being used as a verdict — but it also removed the only signal
## that the stream contradicted itself. The signal is restored as an anomaly
## that fails closed to `psUnknown`, with the reason kept in `reports`
## (docs/adr/0017-trust-claim-authority.md; docs/spec/evidence_calculus.md I6).

import core/contracts/z3_extraction
import core/solver/z3_result_parser
import core/trusted/solver_invocation
import core/types/solver_types
import std/options
import std/strutils

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

const
  contradictory* = "unsat\nsat\n"
  reverseContradiction* = "sat\nunsat\n"
  repeatedUnsat* = "unsat\nunsat\n"
  loneSat* = "sat\n"
  loneUnknown* = "unknown\n"
  emptyStream* = ""

block:
  echo "=== 1. the stream is read once: status from the parser, count from the same rule ==="
  let first = readSolverStream(contradictory)
  expect(first.status == solverUnknown,
    "unsat-then-sat carries no decidable status")
  expect(first.responseCount == 2, "both response lines are counted")
  expect(first.isAnomalous, "two responses in one invocation are an anomaly")

  let repeated = readSolverStream(repeatedUnsat)
  expect(repeated.responseCount == 2,
    "a repeated response is still two responses")
  expect(repeated.isAnomalous,
    "one invocation cannot carry two answers, even when they agree")
  expect(repeated.status == solverUnknown,
    "a stream that answers twice discharges nothing")

  let single = readSolverStream(loneSat)
  expect(single.responseCount == 1 and not single.isAnomalous,
    "a single sat is one answer, not an anomaly")
  expect(single.status == solverSat, "a single sat is reported as sat")

  let satThenUnsat = readSolverStream(reverseContradiction)
  expect(satThenUnsat.isAnomalous, "sat-then-unsat is an anomaly too")
  expect(satThenUnsat.status == solverSat,
    "an anomaly never withholds a counter-example the stream did produce")

  let silent = readSolverStream(emptyStream)
  expect(silent.responseCount == 0, "an empty stream has no response")
  expect(not silent.isAnomalous,
    "no answer is not a contradiction — it is the absence of one")
  expect(silent.status == solverUnknown, "an empty stream carries no status")

  let unknownStream = readSolverStream(loneUnknown)
  expect(unknownStream.responseCount == 1,
    "an `unknown` line is still one response")
  expect(unknownStream.status == solverUnknown, "unknown is carried through")

block:
  echo "=== 2. the parser is still the only rule that says what the status is ==="
  ## The count must be measuring the same grammar as the verdict it qualifies:
  ## asking the parser's classifier and asking for a verdict must never
  ## disagree about which lines are responses.
  let streams = @[contradictory, reverseContradiction, repeatedUnsat, loneSat,
                  loneUnknown, emptyStream,
                  "Z3 version 4.13.3\nsat\n",
                  "(error \"line 5: sat_1 is not a response\")\n",
                  "sat_1\nsat_2\n",
                  "(model (define-fun x () Int 0))\n"]
  for s in streams:
    let outcome = readSolverStream(s)
    expect(outcome.status != solverUnsat or not outcome.isAnomalous,
      "no anomalous stream reports a discharge: " & s.replace("\n", "|"))
    if s != contradictory and s != reverseContradiction and s != repeatedUnsat:
      expect(outcome.status == parseStatusLine(s),
        "a non-contradictory stream reads exactly as the parser reads it: " &
        s.replace("\n", "|"))

  expect(parseStatusLine(contradictory) == solverUnsat,
    "the parser still answers first-response-wins — this is not a parser change")

block:
  echo "=== 3. a contradictory stream lands on the weakest honest state, with a reason ==="
  let proven = proofResultFromSolverStream(contradictory)
  expect(proven.status == psUnknown,
    "unsat-then-sat is psUnknown, never psProven")
  expect(proven.procsProven == 0, "nothing is counted as proven")
  expect(proven.procsInconclusive == 1 and proven.procsChecked == 1,
    "it is checked and inconclusive")
  expect(proven.verificationStatus == vsInconclusive,
    "a contradictory stream never verifies")
  expect(proven.reports.len == 1,
    "the contradiction is recorded rather than swallowed")
  expect(proven.reports[0].message.contains("anomalous") and
         proven.reports[0].message.contains("2"),
    "the recorded reason names the anomaly: " & proven.reports[0].message)
  expect(proven.reports[0].ciBlocking == false and
         proven.reports[0].status == tsWarning,
    "an anomaly warns; it does not block a build as a failure")

  let repeatedResult = proofResultFromSolverStream(repeatedUnsat)
  expect(repeatedResult.status == psUnknown,
    "two agreeing answers are still not one proof")
  expect(repeatedResult.reports.len == 1,
    "the repeated response is recorded as the same anomaly")

block:
  echo "=== 4. the working paths still work ==="
  let genuine = proofResultFromSolverStream("unsat\n")
  expect(genuine.status == psProven,
    "one honest unsat still discharges")
  expect(genuine.procsProven == 1, "the discharge is still counted")
  expect(genuine.reports.len == 0,
    "an honest answer carries no anomaly report")

  let counterExample = proofResultFromSolverStream(
    "sat\n(model\n  (define-fun x () Int 0)\n)\n")
  expect(counterExample.status == psViolated,
    "a counter-example is still a violation")
  expect(counterExample.counterexample.isSome,
    "the model bindings are still attached")
  expect(counterExample.reports.len == 0, "a single answer is not an anomaly")

  let nothing = proofResultFromSolverStream(loneUnknown)
  expect(nothing.status == psUnknown and nothing.reports.len == 0,
    "an unparsed answer is inconclusive without an anomaly label")

block:
  echo "=== 5. the invariant, over every response pair ==="
  ## Exhaustively: no combination of two responses in one stream can ever
  ## produce psProven.
  for first in ["sat", "unsat", "unknown"]:
    for second in ["sat", "unsat", "unknown"]:
      let stream = first & "\n" & second & "\n"
      let r = proofResultFromSolverStream(stream)
      expect(r.status != psProven or r.reports.len == 0,
        "two responses never yield an unreported proof: " &
        first & " then " & second)
      if first == "sat":
        expect(r.status == psViolated,
          "sat first keeps the counter-example: " & first & " then " & second)
      elif second == "sat":
        expect(r.status == psUnknown,
          "unsat/unknown then sat is weakened, not promoted: " &
          first & " then " & second)