import core/trusted/layer_declaration

## The k-induction proof node must not publish a claim its evidence cannot carry.
##
## `generateKInductionProofFromSessionId` computed one boolean from the ABSENCE
## of a counter-example and used it for both the verdict and the claim text.
## Absence is also what an `unknown` answer looks like, so a trust artifact
## asserted a discharge from evidence that never produced one
## (docs/adr/0017-trust-claim-authority.md; a recorded solver `unsat` is not a
## proof-checked proof — docs/spec/evidence_calculus.md I6). The verdict, the
## claim and the witness node are three projections of one stream pair; they
## are asserted together here so they cannot drift apart again.

import core/api/axiom_api_session_ops
import core/session/session_parser_gateway
import core/session/session_parser_types
import core/types/domain_types
import core/types/results
import std/[json, options, strutils]

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

const sessionUuid = "00000000-0000-4000-8000-000000000000"

type Published = object
  verdict: string
  claim: string
  witnessStatus: string

proc publish(baseStdout, stepStdout: string): Published =
  let res = generateKInductionProofFromSessionId(
    sessionUuid, 3, 10, 1, baseStdout, stepStdout)
  if res.isErr():
    doAssert false, "k-induction unexpectedly refused: " & $res.error.code
  result.verdict = verdictString(res.get().proof.verdict)
  result.claim = claimString(res.get().proof.claims[0])
  result.witnessStatus =
    (string(res.get().proof.witness.finalState)).parseJson()["status"].getStr()

block:
  echo "=== 1. the genuine conjunction still discharges ==="
  ## Fixing an over-claim must not break a working proof.
  let genuine = publish("unsat\n", "unsat\n")
  expect(genuine.verdict == "safe_within_bound",
    "base and step both observed unsat is still safe_within_bound")
  expect(genuine.claim == "k-induction base and step are unsat",
    "the claim still states what was observed")
  expect(genuine.witnessStatus == "proved",
    "the witness node still reports the discharge")

block:
  echo "=== 2. a self-contradicting stream discharges nothing ==="
  for (label, baseStdout, stepStdout) in [
      ("unsat-then-sat base", "unsat\nsat\n", "unsat\n"),
      ("unsat-then-sat step", "unsat\n", "unsat\nsat\n"),
      ("repeated unsat base", "unsat\nunsat\n", "unsat\n"),
      ("repeated unsat step", "unsat\n", "unsat\nunsat\n"),
      ("unsat-then-sat in both", "unsat\nsat\n", "unsat\nsat\n")]:
    let p = publish(baseStdout, stepStdout)
    expect(p.verdict == "inconclusive",
      label & ": the verdict is inconclusive, never safe_within_bound")
    expect(p.claim == "k-induction base and step were not both unsat",
      label & ": the claim does not assert a discharge")
    expect(p.claim != "k-induction base and step are unsat",
      label & ": the discharge claim is not emitted")
    expect(p.witnessStatus != "proved",
      label & ": the witness node does not report proved either")

block:
  echo "=== 3. a counter-example is still reported, anomaly or not ==="
  for (label, baseStdout, stepStdout) in [
      ("sat base", "sat\n", "unsat\n"),
      ("sat-then-unsat base", "sat\nunsat\n", "unsat\n"),
      ("sat step", "unsat\n", "sat\nunsat\n")]:
    let p = publish(baseStdout, stepStdout)
    expect(p.verdict == "race_detected",
      label & ": a counter-example is still a detected race")
    expect(p.claim == "k-induction found reachable violation",
      label & ": the claim still reports the violation")
    expect(p.witnessStatus == "sat",
      label & ": the witness node still carries the counter-example")

block:
  echo "=== 4. an unparsed answer is never promoted to a safety claim ==="
  ## `parseZ3StdoutAsResult` refuses these outright, so reaching the claim
  ## derivation at all is the thing being asserted: the refusal must not be
  ## convertible into a discharge by any other route.
  for (label, baseStdout, stepStdout) in [
      ("empty base", "", "unsat\n"),
      ("empty step", "unsat\n", ""),
      ("no response at all", "\n\n", "unsat\n")]:
    let res = generateKInductionProofFromSessionId(
      sessionUuid, 3, 10, 1, baseStdout, stepStdout)
    expect(res.isErr(),
      label & ": a stream with no usable answer is refused, not discharged")
    if res.isErr():
      expect(res.error.code == axiomErrSolverParseFailure or
             res.error.code == axiomErrSolverUnknown,
        label & ": the refusal names the unreadable stream, got " &
        $res.error.code)

block:
  echo "=== 5. all three projections agree on every pair ==="
  ## The defect was three projections of one evidence pair disagreeing. Assert
  ## the agreement itself rather than the individual values, so a future
  ## change cannot make one of them over-claim alone.
  let pairs: seq[(string, string)] = @[
    ("unsat\n", "unsat\n"),
    ("unsat\nsat\n", "unsat\n"),
    ("unsat\n", "unsat\nsat\n"),
    ("unsat\nunsat\n", "unsat\n"),
    ("sat\n", "unsat\n"),
    ("sat\nunsat\n", "unsat\n"),
    ("unsat\n", "sat\nunsat\n"),
    ("unknown\n", "unsat\n")
  ]
  for pair in pairs:
    let res = generateKInductionProofFromSessionId(
      sessionUuid, 3, 10, 1, pair[0], pair[1])
    if res.isErr():
      continue
    let p = Published(
      verdict: verdictString(res.get().proof.verdict),
      claim: claimString(res.get().proof.claims[0]),
      witnessStatus:
        (string(res.get().proof.witness.finalState)).parseJson()["status"].getStr())
    let where = "base=" & pair[0].replace("\n", "|") &
               " step=" & pair[1].replace("\n", "|")
    case p.verdict
    of "safe_within_bound":
      expect(p.claim == "k-induction base and step are unsat" and
             p.witnessStatus == "proved",
        where & ": a safety verdict is stated by the claim and the witness")
    of "race_detected":
      expect(p.claim == "k-induction found reachable violation" and
             p.witnessStatus == "sat",
        where & ": a detected race is stated by the claim and the witness")
    else:
      expect(p.witnessStatus != "proved",
        where & ": an inconclusive verdict never leaves a proved witness")
      expect(p.claim != "k-induction base and step are unsat",
        where & ": an inconclusive verdict never states a discharge")